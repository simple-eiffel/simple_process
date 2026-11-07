/*
 * simple_process_pipe.h - a child process with stdin, stdout and stderr all
 * piped (simple_process 1.1.0, SIMPLE_PIPED_PROCESS).
 *
 * HEADER-ONLY, AND STATELESS AT FILE SCOPE. Every function is `static', so
 * each generated C file that includes this header compiles its own copy of
 * the CODE. There is no file-scope data of any kind: every piece of state
 * lives in the malloc'd spp_process the Eiffel caller owns. Per-translation-
 * unit copies therefore cannot fork state (the simple_shell.h overlay lockup,
 * 2026-08-25, was mutable statics in a shared header).
 *
 * NO PIPE DEADLOCK. A parent that writes a large input while the child writes
 * a large output deadlocks when both pipe buffers fill: the child blocks on a
 * full stdout and stops reading stdin, the parent blocks on a full stdin and
 * never reads stdout. Here each output stream is drained from the moment the
 * child starts by its own pump thread into a C-heap buffer that grows as
 * needed, so the child can always finish a write, and a blocking write to its
 * stdin completes as long as the child keeps reading.
 *
 * The pump threads are plain C threads. They never call into the Eiffel
 * runtime and touch only C-heap memory owned by their spp_process.
 *
 * Copyright (c) 2026 Larry Rix - MIT License
 */

#ifndef SIMPLE_PROCESS_PIPE_H
#define SIMPLE_PROCESS_PIPE_H

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define SPP_STDOUT 1
#define SPP_STDERR 2

#define SPP_AWAIT_ANY 1   /* some bytes in any stream, or every stream ended */
#define SPP_AWAIT_LINE 2  /* a LF in stdout, or stdout ended */
#define SPP_AWAIT_END 3   /* every stream ended */

/* spp_start options */
#define SPP_INHERIT_STDIN 1      /* the child reads this process's stdin, not a pipe */
#define SPP_NO_CONSOLE 2         /* CREATE_NO_WINDOW even when the window is shown */

#if defined(_WIN32) || defined(EIF_WINDOWS)

#include <windows.h>
#include <process.h>

#ifndef STACK_SIZE_PARAM_IS_A_RESERVATION
#define STACK_SIZE_PARAM_IS_A_RESERVATION 0x00010000
#endif

#define SPP_READ_CHUNK 65536
#define SPP_PIPE_BUFFER 65536

struct spp_process_s;

typedef struct {
    HANDLE pipe;                 /* read end, owned; NULL when the stream does not exist */
    HANDLE thread;               /* pump thread; NULL when none */
    char* data;                  /* bytes collected and not yet taken */
    size_t count;
    size_t capacity;
    int ended;                   /* EOF (or a read error) seen */
    int lost;                    /* out of memory: bytes were dropped */
    size_t limit;                /* keep at most this many bytes in all; 0 = no limit */
    size_t total;                /* bytes kept so far, taken or not */
    int truncated;               /* bytes past `limit' were read and dropped */
    struct spp_process_s* owner;
} spp_stream;

typedef struct spp_process_s {
    HANDLE process;              /* NULL when the start failed */
    DWORD pid;
    int in_job;                  /* the child joined the owner job it was given */
    HANDLE input;                /* write end of the child's stdin; NULL once closed */
    spp_stream out;
    spp_stream err;              /* pipe NULL, ended = 1 when stderr is merged into stdout */
    CRITICAL_SECTION lock;       /* guards both streams */
    HANDLE signal;               /* manual reset: set when a stream gains bytes or ends */
    volatile LONG closing;
    char error_message[1024];    /* UTF-8 */
} spp_process;

/* Vista-and-later declarations. ISE compiles generated C with
   -D_WIN32_WINNT=0x0500, which hides them; they are resolved at run time
   instead, so no client ECF needs a newer _WIN32_WINNT. */
typedef BOOL (WINAPI *spp_init_attributes_fn)(void*, DWORD, DWORD, SIZE_T*);
typedef BOOL (WINAPI *spp_update_attribute_fn)(void*, DWORD, ULONG_PTR, PVOID, SIZE_T, PVOID, SIZE_T*);
typedef void (WINAPI *spp_delete_attributes_fn)(void*);
typedef BOOL (WINAPI *spp_cancel_io_fn)(HANDLE);

typedef struct {
    STARTUPINFOW si;
    void* attributes;
} spp_startup_info_ex;

#define SPP_EXTENDED_STARTUPINFO_PRESENT 0x00080000
#define SPP_PROC_THREAD_ATTRIBUTE_HANDLE_LIST 0x00020002

static void spp_set_error(spp_process* p, const char* a_where, DWORD a_code)
{
    wchar_t l_wide[512];
    int l_len;
    DWORD l_n;

    l_len = sprintf(p->error_message, "%s failed (Win32 error %lu): ", a_where, (unsigned long) a_code);
    if (l_len < 0) l_len = 0;
    l_n = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, a_code,
                         MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), l_wide, 511, NULL);
    if (l_n > 0) {
        l_wide[l_n] = 0;
        WideCharToMultiByte(CP_UTF8, 0, l_wide, -1, p->error_message + l_len,
                            (int) sizeof(p->error_message) - l_len - 1, NULL, NULL);
    }
    p->error_message[sizeof(p->error_message) - 1] = 0;
}

static unsigned __stdcall spp_pump(void* a_stream)
{
    spp_stream* s = (spp_stream*) a_stream;
    spp_process* p = s->owner;
    char* l_chunk = (char*) malloc(SPP_READ_CHUNK);
    DWORD l_n = 0;
    int l_done = 0;

    while (!l_done) {
        if (!l_chunk || p->closing || !ReadFile(s->pipe, l_chunk, SPP_READ_CHUNK, &l_n, NULL)) {
            /* EOF arrives as ERROR_BROKEN_PIPE once every writer is gone. A
               successful read of 0 bytes is a 0-byte write, not EOF. */
            l_done = 1;
        }
        EnterCriticalSection(&p->lock);
        if (l_done) {
            s->ended = 1;
            if (!l_chunk) s->lost = 1;
        } else if (l_n > 0) {
            /* Past the limit the pump keeps READING, so the child never
               blocks on a full pipe, but drops what it reads. */
            if (s->limit > 0 && s->total + l_n > s->limit) {
                s->truncated = 1;
                l_n = (DWORD) (s->limit - s->total);
            }
        }
        if (!l_done && l_n > 0) {
            if (s->count + l_n > s->capacity) {
                size_t l_cap = s->capacity ? s->capacity : SPP_READ_CHUNK;
                char* l_grown;
                while (l_cap < s->count + l_n) l_cap *= 2;
                l_grown = (char*) realloc(s->data, l_cap);
                if (l_grown) {
                    s->data = l_grown;
                    s->capacity = l_cap;
                } else {
                    s->lost = 1;
                    l_n = 0;
                }
            }
            if (l_n > 0) {
                memcpy(s->data + s->count, l_chunk, l_n);
                s->count += l_n;
                s->total += l_n;
            }
        }
        SetEvent(p->signal);
        LeaveCriticalSection(&p->lock);
    }
    free(l_chunk);
    return 0;
}

/* Start `a_command' (UTF-16) in `a_directory' (UTF-16 or NULL). `a_options'
   is SPP_INHERIT_STDIN and/or SPP_NO_CONSOLE. `a_limit' caps the bytes kept
   per output stream (0: none). Always answers a record unless malloc fails;
   `process' is NULL when the start failed, and `error_message' says why. Free
   it with spp_close either way. */
static spp_process* spp_start(void* a_command, void* a_directory, int a_show_window, int a_merge_error, int a_options, int a_limit, void* a_job)
{
    spp_process* p;
    SECURITY_ATTRIBUTES sa;
    HANDLE in_read = NULL, in_write = NULL, out_read = NULL, out_write = NULL, err_read = NULL, err_write = NULL;
    HANDLE l_parent_in;
    HANDLE l_inherit[3];
    int l_inherit_count;
    spp_startup_info_ex six;
    PROCESS_INFORMATION pi;
    const wchar_t* l_command = (const wchar_t*) a_command;
    const wchar_t* l_directory = (const wchar_t*) a_directory;
    wchar_t* l_command_copy = NULL;
    size_t l_len;
    DWORD l_flags = 0;
    DWORD l_code = 0;
    BOOL l_ok = FALSE;
    void* l_attributes = NULL;
    SIZE_T l_attributes_size = 0;
    HMODULE l_kernel;
    spp_init_attributes_fn l_init = NULL;
    spp_update_attribute_fn l_update = NULL;
    spp_delete_attributes_fn l_delete = NULL;

    p = (spp_process*) calloc(1, sizeof(spp_process));
    if (!p) return NULL;
    InitializeCriticalSection(&p->lock);
    p->out.owner = p;
    p->err.owner = p;
    if (a_limit > 0) {
        p->out.limit = (size_t) a_limit;
        p->err.limit = (size_t) a_limit;
    }
    p->signal = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!p->signal) { spp_set_error(p, "CreateEvent", GetLastError()); return p; }

    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = NULL;
    if (a_options & SPP_INHERIT_STDIN) {
        /* An inheritable duplicate of this process's own stdin. No usable
           stdin (a GUI process): fall back to a pipe closed at once. */
        l_parent_in = GetStdHandle(STD_INPUT_HANDLE);
        if (l_parent_in && l_parent_in != INVALID_HANDLE_VALUE &&
            DuplicateHandle(GetCurrentProcess(), l_parent_in, GetCurrentProcess(), &in_read, 0, TRUE, DUPLICATE_SAME_ACCESS)) {
            in_write = NULL;
        } else {
            in_read = NULL;
        }
    }
    if (!in_read && !CreatePipe(&in_read, &in_write, &sa, SPP_PIPE_BUFFER)) { spp_set_error(p, "CreatePipe (stdin)", GetLastError()); goto fail; }
    if (!CreatePipe(&out_read, &out_write, &sa, SPP_PIPE_BUFFER)) { spp_set_error(p, "CreatePipe (stdout)", GetLastError()); goto fail; }
    if (!a_merge_error && !CreatePipe(&err_read, &err_write, &sa, SPP_PIPE_BUFFER)) { spp_set_error(p, "CreatePipe (stderr)", GetLastError()); goto fail; }
    /* The parent's ends must not be inherited by anyone. */
    if (in_write) SetHandleInformation(in_write, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(out_read, HANDLE_FLAG_INHERIT, 0);
    if (err_read) SetHandleInformation(err_read, HANDLE_FLAG_INHERIT, 0);

    memset(&six, 0, sizeof(six));
    six.si.cb = sizeof(STARTUPINFOW);
    six.si.dwFlags = STARTF_USESTDHANDLES;
    six.si.hStdInput = in_read;
    six.si.hStdOutput = out_write;
    six.si.hStdError = a_merge_error ? out_write : err_write;
    if (a_show_window) {
        /* defaults: a console child gets a console window */
    } else {
        six.si.dwFlags |= STARTF_USESHOWWINDOW;
        six.si.wShowWindow = SW_HIDE;
        l_flags |= CREATE_NO_WINDOW;
    }
    if (a_options & SPP_NO_CONSOLE) l_flags |= CREATE_NO_WINDOW;
    /* An owner job: start suspended, join the job, then run - so the child
       never runs a single instruction outside it. */
    if (a_job) l_flags |= CREATE_SUSPENDED;

    /* Inherit exactly the child's own pipe ends: a child another processor
       starts at this moment can then never be handed ours, and ours never
       theirs. */
    l_inherit[0] = in_read;
    l_inherit[1] = out_write;
    l_inherit_count = 2;
    if (err_write) l_inherit[l_inherit_count++] = err_write;
    l_kernel = GetModuleHandleW(L"kernel32.dll");
    if (l_kernel) {
        l_init = (spp_init_attributes_fn) GetProcAddress(l_kernel, "InitializeProcThreadAttributeList");
        l_update = (spp_update_attribute_fn) GetProcAddress(l_kernel, "UpdateProcThreadAttribute");
        l_delete = (spp_delete_attributes_fn) GetProcAddress(l_kernel, "DeleteProcThreadAttributeList");
    }
    if (l_init && l_update && l_delete) {
        l_init(NULL, 1, 0, &l_attributes_size);
        l_attributes = malloc(l_attributes_size);
        if (l_attributes && l_init(l_attributes, 1, 0, &l_attributes_size)) {
            if (l_update(l_attributes, 0, SPP_PROC_THREAD_ATTRIBUTE_HANDLE_LIST, l_inherit,
                         l_inherit_count * sizeof(HANDLE), NULL, NULL)) {
                six.si.cb = sizeof(six);
                six.attributes = l_attributes;
                l_flags |= SPP_EXTENDED_STARTUPINFO_PRESENT;
            } else {
                l_delete(l_attributes);
                free(l_attributes);
                l_attributes = NULL;
            }
        } else {
            free(l_attributes);
            l_attributes = NULL;
        }
    }

    /* CreateProcessW may write into its command line. */
    l_len = wcslen(l_command);
    l_command_copy = (wchar_t*) malloc((l_len + 1) * sizeof(wchar_t));
    if (l_command_copy) {
        memcpy(l_command_copy, l_command, (l_len + 1) * sizeof(wchar_t));
        memset(&pi, 0, sizeof(pi));
        l_ok = CreateProcessW(NULL, l_command_copy, NULL, NULL, TRUE, l_flags, NULL,
                              (l_directory && l_directory[0]) ? l_directory : NULL, &six.si, &pi);
        if (!l_ok) l_code = GetLastError();
        free(l_command_copy);
    } else {
        l_code = ERROR_NOT_ENOUGH_MEMORY;
    }
    if (l_attributes) {
        l_delete(l_attributes);
        free(l_attributes);
    }
    /* The child holds its own ends now (or never will). */
    CloseHandle(in_read); in_read = NULL;
    CloseHandle(out_write); out_write = NULL;
    if (err_write) { CloseHandle(err_write); err_write = NULL; }
    if (!l_ok) { spp_set_error(p, "CreateProcess", l_code); goto fail; }

    if (a_job) {
        p->in_job = AssignProcessToJobObject((HANDLE) a_job, pi.hProcess) ? 1 : 0;
        ResumeThread(pi.hThread);
    }
    CloseHandle(pi.hThread);
    p->process = pi.hProcess;
    p->pid = pi.dwProcessId;
    p->input = in_write; in_write = NULL;  /* NULL when stdin is inherited */
    p->out.pipe = out_read; out_read = NULL;
    p->err.pipe = err_read; err_read = NULL;
    p->out.thread = (HANDLE) _beginthreadex(NULL, 65536, spp_pump, &p->out, STACK_SIZE_PARAM_IS_A_RESERVATION, NULL);
    if (!p->out.thread) p->out.ended = 1;
    if (p->err.pipe) {
        p->err.thread = (HANDLE) _beginthreadex(NULL, 65536, spp_pump, &p->err, STACK_SIZE_PARAM_IS_A_RESERVATION, NULL);
        if (!p->err.thread) p->err.ended = 1;
    } else {
        p->err.ended = 1;
    }
    if ((!p->out.thread) || (p->err.pipe && !p->err.thread)) {
        /* Without a pump the child could block forever on a full pipe. */
        spp_set_error(p, "_beginthreadex (pump)", GetLastError());
        TerminateProcess(p->process, 1);
        WaitForSingleObject(p->process, 5000);
        CloseHandle(p->process);
        p->process = NULL;
    }
    return p;

fail:
    if (in_read) CloseHandle(in_read);
    if (in_write) CloseHandle(in_write);
    if (out_read) CloseHandle(out_read);
    if (out_write) CloseHandle(out_write);
    if (err_read) CloseHandle(err_read);
    if (err_write) CloseHandle(err_write);
    return p;
}

static int spp_started(spp_process* p) { return (p && p->process) ? 1 : 0; }

static const char* spp_error(spp_process* p) { return p ? p->error_message : ""; }

static unsigned long spp_pid(spp_process* p) { return (p && p->process) ? (unsigned long) p->pid : 0; }
static int spp_in_job(spp_process* p) { return (p && p->process) ? p->in_job : 0; }

/* A job that kills every process in it when its last handle closes: when the
   program holding the handle ends, however it ends (closed, crashed, killed
   from Task Manager). Nothing is stored here - the caller keeps the handle for
   the program's life (SIMPLE_PIPED_PROCESS.owner_job, a once per process). The
   handle is not inheritable, so no child can keep the job alive. NULL on failure. */
static void* spp_new_owner_job(void)
{
    HANDLE l_job = CreateJobObjectW(NULL, NULL);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION l_info;
    if (!l_job) return NULL;
    memset(&l_info, 0, sizeof(l_info));
    l_info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(l_job, JobObjectExtendedLimitInformation, &l_info, sizeof(l_info))) {
        CloseHandle(l_job);
        return NULL;
    }
    return (void*) l_job;
}

/* Has the child exited? Never waits (a 0 ms wait). */
static int spp_is_running(spp_process* p)
{
    if (!p || !p->process) return 0;
    return WaitForSingleObject(p->process, 0) == WAIT_TIMEOUT ? 1 : 0;
}

/* Exit code, or -1 while running. Never waits. */
static int spp_exit_code(spp_process* p)
{
    DWORD l_code = 0;
    if (!p || !p->process) return -1;
    if (WaitForSingleObject(p->process, 0) != WAIT_OBJECT_0) return -1;
    if (!GetExitCodeProcess(p->process, &l_code)) return -1;
    return (int) l_code;
}

/* Write all `a_count' bytes to the child's stdin. 1 on success, 0 when the
   pipe is gone (the child exited or closed its stdin). WAITS while the pipe
   is full. */
static int spp_write(spp_process* p, const char* a_data, int a_count)
{
    DWORD l_written = 0;
    int l_total = 0;
    if (!p || !p->input) return 0;
    while (l_total < a_count) {
        if (!WriteFile(p->input, a_data + l_total, (DWORD) (a_count - l_total), &l_written, NULL)) return 0;
        if (l_written == 0) return 0;
        l_total += (int) l_written;
    }
    return 1;
}

/* Close the child's stdin: it reads EOF. */
static void spp_close_input(spp_process* p)
{
    if (p && p->input) {
        CloseHandle(p->input);
        p->input = NULL;
    }
}

static int spp_input_open(spp_process* p) { return (p && p->input) ? 1 : 0; }

static spp_stream* spp_stream_of(spp_process* p, int a_which)
{
    return a_which == SPP_STDERR ? &p->err : &p->out;
}

/* Bytes of stream `a_which' collected and not yet taken. */
static int spp_available(spp_process* p, int a_which)
{
    size_t l_count;
    if (!p || !p->process) return 0;
    EnterCriticalSection(&p->lock);
    l_count = spp_stream_of(p, a_which)->count;
    LeaveCriticalSection(&p->lock);
    return l_count > 0x3FFFFFFF ? 0x3FFFFFFF : (int) l_count;
}

/* Move at most `a_capacity' collected bytes of stream `a_which' into
   `a_buffer'. Answers how many. */
static int spp_take(spp_process* p, int a_which, char* a_buffer, int a_capacity)
{
    spp_stream* s;
    size_t l_n;
    if (!p || !p->process || a_capacity <= 0) return 0;
    EnterCriticalSection(&p->lock);
    s = spp_stream_of(p, a_which);
    l_n = s->count < (size_t) a_capacity ? s->count : (size_t) a_capacity;
    if (l_n > 0) {
        memcpy(a_buffer, s->data, l_n);
        memmove(s->data, s->data + l_n, s->count - l_n);
        s->count -= l_n;
    }
    LeaveCriticalSection(&p->lock);
    return (int) l_n;
}

/* Has stream `a_which' ended with every byte taken? */
static int spp_drained(spp_process* p, int a_which)
{
    int l_result;
    spp_stream* s;
    if (!p || !p->process) return 1;
    EnterCriticalSection(&p->lock);
    s = spp_stream_of(p, a_which);
    l_result = (s->ended && s->count == 0) ? 1 : 0;
    LeaveCriticalSection(&p->lock);
    return l_result;
}

/* Did a stream pass its limit, so bytes were dropped? */
static int spp_truncated(spp_process* p)
{
    int l_result;
    if (!p || !p->process) return 0;
    EnterCriticalSection(&p->lock);
    l_result = (p->out.truncated || p->err.truncated) ? 1 : 0;
    LeaveCriticalSection(&p->lock);
    return l_result;
}

/* Is `a_name' (UTF-16) found the way CreateProcess would find it: the
   application directory, the system directories, then PATH, ".exe" added
   when it has no extension? WAITS: a dead network share on PATH costs
   seconds. */
static int spp_file_in_path(void* a_name)
{
    wchar_t l_found[MAX_PATH];
    return SearchPathW(NULL, (const wchar_t*) a_name, L".exe", MAX_PATH, l_found, NULL) > 0 ? 1 : 0;
}

/* Did a pump run out of memory and drop bytes? */
static int spp_lost(spp_process* p)
{
    int l_result;
    if (!p || !p->process) return 0;
    EnterCriticalSection(&p->lock);
    l_result = (p->out.lost || p->err.lost) ? 1 : 0;
    LeaveCriticalSection(&p->lock);
    return l_result;
}

static int spp_ready(spp_process* p, int a_mode)
{
    switch (a_mode) {
    case SPP_AWAIT_ANY:
        return p->out.count > 0 || p->err.count > 0 || (p->out.ended && p->err.ended);
    case SPP_AWAIT_LINE:
        return p->out.ended || (p->out.count > 0 && memchr(p->out.data, '\n', p->out.count) != NULL);
    default:
        return p->out.ended && p->err.ended;
    }
}

/* Wait until `a_mode' holds or `a_timeout_ms' passes (negative: forever).
   1 when it holds, 0 on timeout. */
static int spp_await(spp_process* p, int a_mode, int a_timeout_ms)
{
    DWORD l_start = GetTickCount();
    DWORD l_elapsed;
    DWORD l_wait;
    int l_ready;
    if (!p || !p->process) return 1;
    for (;;) {
        EnterCriticalSection(&p->lock);
        l_ready = spp_ready(p, a_mode);
        /* Reset under the lock the pumps set it under: no lost wake-up. */
        if (!l_ready) ResetEvent(p->signal);
        LeaveCriticalSection(&p->lock);
        if (l_ready) return 1;
        if (a_timeout_ms < 0) {
            l_wait = INFINITE;
        } else {
            l_elapsed = GetTickCount() - l_start;
            if (l_elapsed >= (DWORD) a_timeout_ms) return 0;
            l_wait = (DWORD) a_timeout_ms - l_elapsed;
        }
        WaitForSingleObject(p->signal, l_wait);
    }
}

/* Wait for the child to exit. 1 when it has, 0 on timeout (negative: forever). */
static int spp_wait_exit(spp_process* p, int a_timeout_ms)
{
    if (!p || !p->process) return 1;
    return WaitForSingleObject(p->process, a_timeout_ms < 0 ? INFINITE : (DWORD) a_timeout_ms) == WAIT_OBJECT_0 ? 1 : 0;
}

static int spp_kill(spp_process* p)
{
    if (!p || !p->process) return 0;
    return TerminateProcess(p->process, 1) ? 1 : 0;
}

static void spp_join_pump(spp_process* p, spp_stream* s, spp_cancel_io_fn a_cancel)
{
    if (s->thread) {
        /* A pump may sit in ReadFile for as long as the child lives. Cancel
           the read, repeatedly: a pump between two reads is not yet in one. */
        while (WaitForSingleObject(s->thread, 0) != WAIT_OBJECT_0) {
            if (a_cancel) {
                a_cancel(s->thread);
                WaitForSingleObject(s->thread, 20);
            } else {
                WaitForSingleObject(s->thread, INFINITE);
            }
        }
        CloseHandle(s->thread);
        s->thread = NULL;
    }
    if (s->pipe) { CloseHandle(s->pipe); s->pipe = NULL; }
    free(s->data);
    s->data = NULL;
    s->count = 0;
    s->capacity = 0;
}

/* Close stdin, stop the pumps, release everything. Does NOT kill the child:
   one still running keeps running, and its later writes fail. */
static void spp_close(spp_process* p)
{
    HMODULE l_kernel;
    spp_cancel_io_fn l_cancel = NULL;
    if (!p) return;
    spp_close_input(p);
    InterlockedExchange(&p->closing, 1);
    l_kernel = GetModuleHandleW(L"kernel32.dll");
    if (l_kernel) l_cancel = (spp_cancel_io_fn) GetProcAddress(l_kernel, "CancelSynchronousIo");
    spp_join_pump(p, &p->out, l_cancel);
    spp_join_pump(p, &p->err, l_cancel);
    if (p->process) CloseHandle(p->process);
    if (p->signal) CloseHandle(p->signal);
    DeleteCriticalSection(&p->lock);
    free(p);
}

#else  /* ============ POSIX: macOS and Linux ============ */

/* The same contract as the Windows half, with these platform choices:

   - The command line is split here, by the Windows rules (white space
     separates, double quotes group, backslashes are literal unless they
     precede a double quote), and the program is run directly with no shell,
     as CreateProcess does. A missing program is therefore a failed start. To
     get a shell, run one: sh -c "a | b".
   - fork and exec, with only async-signal-safe calls between them, because
     other threads may hold any lock at that moment. The program is found
     before the fork. A close-on-exec status pipe carries a failure in the
     child back as a failed start.
   - The child closes every descriptor above its own, so it holds exactly its
     own pipe ends, whichever other processor starts a child at this moment.
   - Pump and reaper threads run with every signal blocked: the Eiffel
     runtime's signal handler must never run on a thread it does not know.
   - An owner job is a pipe whose write end only the owner holds. A small
     watcher process per bound child sees it end, however the owner ended, and
     kills the child's process group. The watcher leaves when the child's life
     pipe ends, which the child holds on descriptor 3.
   - A record is reference counted, because `spp_close' does not kill the
     child: the reaper thread keeps it until the child has exited. */

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/syscall.h>
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define SPP_READ_CHUNK 65536
#define SPP_THREAD_STACK 131072
#define SPP_FIRST_FREE_FD 5      /* pipes stay above the descriptors a child sets up */
#define SPP_WAIT_SLICE_MS 100    /* a wall clock jump can only cost this much */

struct spp_process_s;

typedef struct {
    int pipe;                    /* read end, owned; -1 when the stream does not exist */
    pthread_t thread;            /* pump thread, when `has_thread' */
    int has_thread;
    char* data;                  /* bytes collected and not yet taken */
    size_t count;
    size_t capacity;
    int ended;                   /* EOF (or a read error) seen */
    int lost;                    /* out of memory: bytes were dropped */
    size_t limit;                /* keep at most this many bytes in all; 0 = no limit */
    size_t total;                /* bytes kept so far, taken or not */
    int truncated;               /* bytes past `limit' were read and dropped */
    struct spp_process_s* owner;
} spp_stream;

typedef struct spp_process_s {
    int process;                 /* 0 when the start failed */
    pid_t pid;
    int in_job;                  /* a watcher ends the child with its owner */
    int input;                   /* write end of the child's stdin; -1 once closed */
    spp_stream out;
    spp_stream err;              /* pipe -1, ended = 1 when stderr is merged into stdout */
    pthread_mutex_t lock;        /* guards the streams and the fields below */
    pthread_cond_t signal;       /* a stream gained bytes or ended, or the child exited */
    int wake[2];                 /* closing wake[1] stops the pumps */
    int exited;
    int exit_code;
    int killed;                  /* `spp_kill' ended it */
    int references;              /* the owner, and the reaper while the child runs */
    char error_message[1024];    /* UTF-8 */
} spp_process;

typedef struct {
    int read_end;
    int write_end;
} spp_owner_job;

static void spp_set_error(spp_process* p, const char* a_where, int a_code)
{
    snprintf(p->error_message, sizeof(p->error_message), "%s failed (errno %d): %s", a_where, a_code, strerror(a_code));
}

static void spp_close_fd(int* a_fd)
{
    if (*a_fd >= 0) {
        close(*a_fd);
        *a_fd = -1;
    }
}

/* A close-on-exec pipe, both ends at or above SPP_FIRST_FREE_FD. 1 on success. */
static int spp_pipe(int a_ends[2])
{
    int l_i, l_moved;
    if (pipe(a_ends) != 0) {
        a_ends[0] = -1;
        a_ends[1] = -1;
        return 0;
    }
    for (l_i = 0; l_i < 2; l_i++) {
        if (a_ends[l_i] < SPP_FIRST_FREE_FD) {
            l_moved = fcntl(a_ends[l_i], F_DUPFD_CLOEXEC, SPP_FIRST_FREE_FD);
            if (l_moved < 0) {
                l_moved = errno;
                close(a_ends[0]);
                close(a_ends[1]);
                a_ends[0] = -1;
                a_ends[1] = -1;
                errno = l_moved;
                return 0;
            }
            close(a_ends[l_i]);
            a_ends[l_i] = l_moved;
        } else {
            fcntl(a_ends[l_i], F_SETFD, FD_CLOEXEC);
        }
    }
    return 1;
}

/* Start a plain C thread with every signal blocked. 1 on success. */
static int spp_thread(pthread_t* a_thread, void* (*a_body)(void*), void* a_argument, int a_detached)
{
    pthread_attr_t l_attributes;
    pthread_t l_ignored;
    sigset_t l_all, l_old;
    int l_result;

    if (pthread_attr_init(&l_attributes) != 0) return 0;
    pthread_attr_setstacksize(&l_attributes, SPP_THREAD_STACK);
    if (a_detached) pthread_attr_setdetachstate(&l_attributes, PTHREAD_CREATE_DETACHED);
    sigfillset(&l_all);
    pthread_sigmask(SIG_SETMASK, &l_all, &l_old);
    l_result = pthread_create(a_thread ? a_thread : &l_ignored, &l_attributes, a_body, a_argument);
    pthread_sigmask(SIG_SETMASK, &l_old, NULL);
    pthread_attr_destroy(&l_attributes);
    return l_result == 0 ? 1 : 0;
}

static void spp_release(spp_process* p)
{
    int l_left;
    pthread_mutex_lock(&p->lock);
    p->references--;
    l_left = p->references;
    pthread_mutex_unlock(&p->lock);
    if (l_left == 0) {
        pthread_cond_destroy(&p->signal);
        pthread_mutex_destroy(&p->lock);
        free(p);
    }
}

static void* spp_pump(void* a_stream)
{
    spp_stream* s = (spp_stream*) a_stream;
    spp_process* p = s->owner;
    char* l_chunk = (char*) malloc(SPP_READ_CHUNK);
    struct pollfd l_wait[2];
    ssize_t l_read;
    size_t l_n;
    int l_done = 0;

    while (!l_done) {
        l_n = 0;
        if (!l_chunk) {
            l_done = 1;
        } else {
            l_wait[0].fd = s->pipe;
            l_wait[0].events = POLLIN;
            l_wait[0].revents = 0;
            l_wait[1].fd = p->wake[0];
            l_wait[1].events = POLLIN;
            l_wait[1].revents = 0;
            if (poll(l_wait, 2, -1) < 0) {
                if (errno == EINTR) continue;
                l_done = 1;
            } else if (l_wait[1].revents) {
                l_done = 1;
            } else {
                l_read = read(s->pipe, l_chunk, SPP_READ_CHUNK);
                if (l_read > 0) {
                    l_n = (size_t) l_read;
                } else if (l_read == 0 || (errno != EINTR && errno != EAGAIN)) {
                    l_done = 1;
                } else {
                    continue;
                }
            }
        }
        pthread_mutex_lock(&p->lock);
        if (l_done) {
            s->ended = 1;
            if (!l_chunk) s->lost = 1;
        } else if (s->limit > 0 && s->total + l_n > s->limit) {
            /* Past the limit the pump keeps READING, so the child never
               blocks on a full pipe, but drops what it reads. */
            s->truncated = 1;
            l_n = s->limit - s->total;
        }
        if (l_n > 0 && s->count + l_n > s->capacity) {
            size_t l_cap = s->capacity ? s->capacity : SPP_READ_CHUNK;
            char* l_grown;
            while (l_cap < s->count + l_n) l_cap *= 2;
            l_grown = (char*) realloc(s->data, l_cap);
            if (l_grown) {
                s->data = l_grown;
                s->capacity = l_cap;
            } else {
                s->lost = 1;
                l_n = 0;
            }
        }
        if (l_n > 0) {
            memcpy(s->data + s->count, l_chunk, l_n);
            s->count += l_n;
            s->total += l_n;
        }
        pthread_cond_broadcast(&p->signal);
        pthread_mutex_unlock(&p->lock);
    }
    free(l_chunk);
    return NULL;
}

/* Wait for the child and record how it ended. A kill by `spp_kill' reads as
   exit code 1, as TerminateProcess gives on Windows; any other signal as the
   shell convention, 128 + the signal. */
static void* spp_reap(void* a_process)
{
    spp_process* p = (spp_process*) a_process;
    int l_status = 0;
    pid_t l_pid;

    do {
        l_pid = waitpid(p->pid, &l_status, 0);
    } while (l_pid < 0 && errno == EINTR);
    pthread_mutex_lock(&p->lock);
    if (l_pid < 0) {
        p->exit_code = -1;
    } else if (WIFEXITED(l_status)) {
        p->exit_code = WEXITSTATUS(l_status);
    } else if (p->killed) {
        p->exit_code = 1;
    } else {
        p->exit_code = 128 + WTERMSIG(l_status);
    }
    p->exited = 1;
    pthread_cond_broadcast(&p->signal);
    pthread_mutex_unlock(&p->lock);
    spp_release(p);
    return NULL;
}

/* Split `a_command' by the Windows rules. Answers an argument vector whose
   first entry is the start of the single block holding the text (free that
   and the vector), or NULL when out of memory. `a_count' may be 0. */
static char** spp_split_command(const char* a_command, int* a_count)
{
    size_t l_len = strlen(a_command);
    char* l_text = (char*) malloc(l_len + 1);
    char** l_arguments = (char**) malloc((l_len / 2 + 2) * sizeof(char*));
    const char* s = a_command;
    char* l_out = l_text;
    size_t l_slashes, l_i;
    int l_count = 0;
    int l_quoted;

    *a_count = 0;
    if (!l_text || !l_arguments) {
        free(l_text);
        free(l_arguments);
        return NULL;
    }
    for (;;) {
        while (*s == ' ' || *s == '\t') s++;
        if (!*s) break;
        l_arguments[l_count++] = l_out;
        l_quoted = 0;
        while (*s && (l_quoted || (*s != ' ' && *s != '\t'))) {
            if (*s == '\\') {
                l_slashes = 0;
                while (*s == '\\') { l_slashes++; s++; }
                if (*s == '"') {
                    for (l_i = 0; l_i < l_slashes / 2; l_i++) *l_out++ = '\\';
                    if (l_slashes % 2) *l_out++ = *s++;
                } else {
                    for (l_i = 0; l_i < l_slashes; l_i++) *l_out++ = '\\';
                }
            } else if (*s == '"') {
                l_quoted = !l_quoted;
                s++;
            } else {
                *l_out++ = *s++;
            }
        }
        *l_out++ = 0;
    }
    l_arguments[l_count] = NULL;
    *a_count = l_count;
    if (l_count == 0) free(l_text);
    return l_arguments;
}

static int spp_is_program(const char* a_path)
{
    struct stat l_info;
    if (stat(a_path, &l_info) != 0) return 0;
    if (!S_ISREG(l_info.st_mode)) { errno = EACCES; return 0; }
    return access(a_path, X_OK) == 0 ? 1 : 0;
}

/* Find `a_name' the way a shell would: as a path when it holds a slash, else
   along PATH. `a_found' (PATH_MAX bytes) gets an absolute path, because the
   child changes directory before it runs the program. 1 when found, else 0
   with errno set. */
static int spp_find_program(const char* a_name, char* a_found)
{
    const char* l_path;
    const char* l_end;
    char l_candidate[PATH_MAX];
    size_t l_dir, l_name = strlen(a_name);
    int l_code = ENOENT;

    if (l_name == 0) { errno = ENOENT; return 0; }
    if (strchr(a_name, '/')) {
        if (!spp_is_program(a_name)) return 0;
        if (a_name[0] == '/') {
            if (l_name >= PATH_MAX) { errno = ENAMETOOLONG; return 0; }
            memcpy(a_found, a_name, l_name + 1);
            return 1;
        }
        return realpath(a_name, a_found) ? 1 : 0;
    }
    l_path = getenv("PATH");
    if (!l_path) l_path = "/usr/bin:/bin";
    for (;;) {
        l_end = strchr(l_path, ':');
        l_dir = l_end ? (size_t) (l_end - l_path) : strlen(l_path);
        if (l_dir + l_name + 2 <= sizeof(l_candidate)) {
            if (l_dir == 0) {
                l_candidate[0] = '.';
                l_dir = 1;
            } else {
                memcpy(l_candidate, l_path, l_dir);
            }
            l_candidate[l_dir] = '/';
            memcpy(l_candidate + l_dir + 1, a_name, l_name + 1);
            if (spp_is_program(l_candidate)) {
                if (l_candidate[0] == '/') {
                    memcpy(a_found, l_candidate, strlen(l_candidate) + 1);
                    return 1;
                }
                return realpath(l_candidate, a_found) ? 1 : 0;
            }
            if (errno == EACCES) l_code = EACCES;
        }
        if (!l_end) break;
        l_path = l_end + 1;
    }
    errno = l_code;
    return 0;
}

/* Close every descriptor from `a_first' up. Async-signal-safe. */
static void spp_close_from(int a_first, long a_limit)
{
    long l_fd;
#if defined(__linux__) && defined(SYS_close_range)
    if (syscall(SYS_close_range, (unsigned int) a_first, ~0U, 0U) == 0) return;
#endif
    for (l_fd = a_first; l_fd < a_limit; l_fd++) close((int) l_fd);
}

/* After the fork: become the program. Reports through `a_status' on failure. */
static void spp_run_child(const char* a_program, char** a_arguments, const char* a_directory,
                          int a_input, int a_output, int a_error, int a_life, int a_status,
                          int a_own_group, long a_fd_limit)
{
    int l_report[2];
    int l_next = 3;
    sigset_t l_none;

    if (a_own_group) setpgid(0, 0);
    if (a_input == 0) {
        fcntl(0, F_SETFD, 0);
    } else {
        dup2(a_input, 0);
    }
    dup2(a_output, 1);
    dup2(a_error, 2);
    if (a_life >= 0) {
        dup2(a_life, 3);
        l_next = 4;
    }
    dup2(a_status, l_next);
    fcntl(l_next, F_SETFD, FD_CLOEXEC);
    spp_close_from(l_next + 1, a_fd_limit);
    /* An ignored signal would stay ignored through exec. */
    signal(SIGPIPE, SIG_DFL);
    l_report[0] = 0;
    if (a_directory && chdir(a_directory) != 0) {
        l_report[0] = 1;
    } else {
        sigemptyset(&l_none);
        sigprocmask(SIG_SETMASK, &l_none, NULL);
        execv(a_program, a_arguments);
        l_report[0] = 2;
    }
    l_report[1] = errno;
    if (write(l_next, l_report, sizeof(l_report)) < 0) { /* the parent sees a plain exit 127 */ }
    _exit(127);
}

/* The watcher: ends child group `a_pid' when the owner's pipe ends. It keeps
   no other descriptor, so nothing waiting on the owner's output waits on it. */
static void spp_watch(int a_owner, int a_life, pid_t a_pid, long a_fd_limit)
{
    struct pollfd l_wait[2];
    int l_i;

    dup2(a_owner, 3);
    dup2(a_life, 4);
    for (l_i = 0; l_i < 3; l_i++) close(l_i);
    spp_close_from(5, a_fd_limit);
    if (chdir("/") != 0) { /* stays where it was */ }
    l_wait[0].fd = 3;
    l_wait[0].events = POLLIN;
    l_wait[1].fd = 4;
    l_wait[1].events = POLLIN;
    for (;;) {
        l_wait[0].revents = 0;
        l_wait[1].revents = 0;
        if (poll(l_wait, 2, -1) < 0) {
            if (errno == EINTR) continue;
            _exit(1);
        }
        if (l_wait[1].revents) _exit(0);
        if (l_wait[0].revents) {
            if (kill(-a_pid, SIGKILL) != 0) kill(a_pid, SIGKILL);
            _exit(0);
        }
    }
}

/* Start `a_command' (UTF-8) in `a_directory' (UTF-8 or NULL). `a_show_window'
   and SPP_NO_CONSOLE mean nothing here. `a_limit' caps the bytes kept per
   output stream (0: none). Always answers a record unless malloc fails;
   `process' is 0 when the start failed, and `error_message' says why. Free it
   with spp_close either way. */
static spp_process* spp_start(void* a_command, void* a_directory, int a_show_window, int a_merge_error, int a_options, int a_limit, void* a_job)
{
    spp_process* p;
    spp_owner_job* l_job = (spp_owner_job*) a_job;
    const char* l_directory = (const char*) a_directory;
    int l_in[2] = {-1, -1}, l_out[2] = {-1, -1}, l_err[2] = {-1, -1};
    int l_status[2] = {-1, -1}, l_life[2] = {-1, -1};
    int l_child_in, l_report[2];
    int l_argument_count = 0;
    char** l_arguments;
    char l_program[PATH_MAX];
    long l_fd_limit;
    sigset_t l_all, l_old;
    pid_t l_pid, l_middle;
    ssize_t l_read;

    (void) a_show_window;
    p = (spp_process*) calloc(1, sizeof(spp_process));
    if (!p) return NULL;
    pthread_mutex_init(&p->lock, NULL);
    pthread_cond_init(&p->signal, NULL);
    p->references = 1;
    p->input = -1;
    p->wake[0] = -1;
    p->wake[1] = -1;
    p->out.pipe = -1;
    p->err.pipe = -1;
    p->out.owner = p;
    p->err.owner = p;
    if (a_limit > 0) {
        p->out.limit = (size_t) a_limit;
        p->err.limit = (size_t) a_limit;
    }

    l_arguments = spp_split_command((const char*) a_command, &l_argument_count);
    if (!l_arguments) { spp_set_error(p, "Reading the command", ENOMEM); return p; }
    if (l_argument_count == 0) {
        spp_set_error(p, "Reading the command", EINVAL);
        free(l_arguments);
        return p;
    }
    if (!spp_find_program(l_arguments[0], l_program)) { spp_set_error(p, "Finding the program", errno); goto fail; }

    /* No usable stdin to inherit: fall back to a pipe. */
    if ((a_options & SPP_INHERIT_STDIN) && fcntl(0, F_GETFD) != -1) {
        l_child_in = 0;
    } else {
        if (!spp_pipe(l_in)) { spp_set_error(p, "pipe (stdin)", errno); goto fail; }
        l_child_in = l_in[0];
#ifdef F_SETNOSIGPIPE
        fcntl(l_in[1], F_SETNOSIGPIPE, 1);
#endif
    }
    if (!spp_pipe(l_out)) { spp_set_error(p, "pipe (stdout)", errno); goto fail; }
    if (!a_merge_error && !spp_pipe(l_err)) { spp_set_error(p, "pipe (stderr)", errno); goto fail; }
    if (!spp_pipe(l_status)) { spp_set_error(p, "pipe (status)", errno); goto fail; }
    if (!spp_pipe(p->wake)) { spp_set_error(p, "pipe (wake)", errno); goto fail; }
    if (l_job && !spp_pipe(l_life)) { spp_set_error(p, "pipe (owner)", errno); goto fail; }
    l_fd_limit = sysconf(_SC_OPEN_MAX);
    if (l_fd_limit < 0 || l_fd_limit > 65536) l_fd_limit = 65536;

    /* Every signal stays blocked across the fork, so no Eiffel handler runs
       in the child; the child opens the mask just before exec. */
    sigfillset(&l_all);
    pthread_sigmask(SIG_SETMASK, &l_all, &l_old);
    l_pid = fork();
    if (l_pid == 0) {
        spp_run_child(l_program, l_arguments, (l_directory && l_directory[0]) ? l_directory : NULL,
                      l_child_in, l_out[1], a_merge_error ? l_out[1] : l_err[1], l_life[1], l_status[1],
                      l_job != NULL, l_fd_limit);
    }
    if (l_pid > 0 && l_job) {
        setpgid(l_pid, l_pid);
        /* Two forks: the watcher belongs to init, so nobody here reaps it. */
        l_middle = fork();
        if (l_middle == 0) {
            if (fork() == 0) spp_watch(l_job->read_end, l_life[0], l_pid, l_fd_limit);
            _exit(0);
        }
        if (l_middle > 0) {
            int l_ignored;
            while (waitpid(l_middle, &l_ignored, 0) < 0 && errno == EINTR) { }
            p->in_job = 1;
        }
    }
    if (l_pid < 0) {
        int l_code = errno;
        pthread_sigmask(SIG_SETMASK, &l_old, NULL);
        spp_set_error(p, "fork", l_code);
        goto fail;
    }
    pthread_sigmask(SIG_SETMASK, &l_old, NULL);

    /* The child holds its own ends now. */
    spp_close_fd(&l_in[0]);
    spp_close_fd(&l_out[1]);
    spp_close_fd(&l_err[1]);
    spp_close_fd(&l_status[1]);
    spp_close_fd(&l_life[0]);
    spp_close_fd(&l_life[1]);

    /* End of file means exec worked. */
    do {
        l_read = read(l_status[0], l_report, sizeof(l_report));
    } while (l_read < 0 && errno == EINTR);
    spp_close_fd(&l_status[0]);
    if (l_read == (ssize_t) sizeof(l_report)) {
        int l_ignored;
        while (waitpid(l_pid, &l_ignored, 0) < 0 && errno == EINTR) { }
        spp_set_error(p, l_report[0] == 1 ? "Changing to the directory" : "exec", l_report[1]);
        p->in_job = 0;
        goto fail;
    }

    free(l_arguments[0]);
    free(l_arguments);
    p->pid = l_pid;
    p->process = 1;
    p->input = l_in[1];          /* -1 when stdin is inherited */
    p->out.pipe = l_out[0];
    p->err.pipe = l_err[0];
    if (spp_thread(&p->out.thread, spp_pump, &p->out, 0)) p->out.has_thread = 1; else p->out.ended = 1;
    if (p->err.pipe >= 0) {
        if (spp_thread(&p->err.thread, spp_pump, &p->err, 0)) p->err.has_thread = 1; else p->err.ended = 1;
    } else {
        p->err.ended = 1;
    }
    p->references = 2;
    if (!spp_thread(NULL, spp_reap, p, 1)) {
        p->references = 1;
        p->out.ended = 1;
        p->err.ended = 1;
        kill(l_pid, SIGKILL);
        { int l_ignored; while (waitpid(l_pid, &l_ignored, 0) < 0 && errno == EINTR) { } }
        spp_set_error(p, "pthread_create (reaper)", EAGAIN);
        p->process = 0;
    } else if (!p->out.has_thread || (p->err.pipe >= 0 && !p->err.has_thread)) {
        /* Without a pump the child could block forever on a full pipe. */
        spp_set_error(p, "pthread_create (pump)", EAGAIN);
        kill(l_pid, SIGKILL);
        p->process = 0;
    }
    return p;

fail:
    free(l_arguments[0]);
    free(l_arguments);
    spp_close_fd(&l_in[0]);
    spp_close_fd(&l_in[1]);
    spp_close_fd(&l_out[0]);
    spp_close_fd(&l_out[1]);
    spp_close_fd(&l_err[0]);
    spp_close_fd(&l_err[1]);
    spp_close_fd(&l_status[0]);
    spp_close_fd(&l_status[1]);
    spp_close_fd(&l_life[0]);
    spp_close_fd(&l_life[1]);
    spp_close_fd(&p->wake[0]);
    spp_close_fd(&p->wake[1]);
    return p;
}

static int spp_started(spp_process* p) { return (p && p->process) ? 1 : 0; }

static const char* spp_error(spp_process* p) { return p ? p->error_message : ""; }

static unsigned long spp_pid(spp_process* p) { return (p && p->process) ? (unsigned long) p->pid : 0; }
static int spp_in_job(spp_process* p) { return (p && p->process) ? p->in_job : 0; }

/* The pipe that ends with this program, however it ends: only this program
   holds the write end, and it never closes it. The caller keeps the record
   for the program's life (SIMPLE_PIPED_PROCESS.owner_job, a once per
   process). NULL on failure. */
static void* spp_new_owner_job(void)
{
    int l_ends[2];
    spp_owner_job* l_job = (spp_owner_job*) malloc(sizeof(spp_owner_job));
    if (!l_job) return NULL;
    if (!spp_pipe(l_ends)) {
        free(l_job);
        return NULL;
    }
    l_job->read_end = l_ends[0];
    l_job->write_end = l_ends[1];
    return (void*) l_job;
}

/* Has the child exited? Never waits. */
static int spp_is_running(spp_process* p)
{
    int l_result;
    if (!p || !p->process) return 0;
    pthread_mutex_lock(&p->lock);
    l_result = p->exited ? 0 : 1;
    pthread_mutex_unlock(&p->lock);
    return l_result;
}

/* Exit code, or -1 while running. Never waits. */
static int spp_exit_code(spp_process* p)
{
    int l_result;
    if (!p || !p->process) return -1;
    pthread_mutex_lock(&p->lock);
    l_result = p->exited ? p->exit_code : -1;
    pthread_mutex_unlock(&p->lock);
    return l_result;
}

/* Write all `a_count' bytes to the child's stdin. 1 on success, 0 when the
   pipe is gone (the child exited or closed its stdin). WAITS while the pipe
   is full. A write to a gone reader raises SIGPIPE, which must not reach the
   Eiffel runtime: macOS turns it off per pipe (F_SETNOSIGPIPE at the start);
   elsewhere it is blocked for this call and any it raised is consumed. */
static int spp_write(spp_process* p, const char* a_data, int a_count)
{
    int l_total = 0;
    int l_result = 1;
    ssize_t l_written;
#ifndef F_SETNOSIGPIPE
    sigset_t l_pipe, l_pending, l_old;
    struct timespec l_now = {0, 0};
    int l_was_pending;
#endif
    if (!p || p->input < 0) return 0;
#ifndef F_SETNOSIGPIPE
    sigemptyset(&l_pipe);
    sigaddset(&l_pipe, SIGPIPE);
    sigpending(&l_pending);
    l_was_pending = sigismember(&l_pending, SIGPIPE);
    pthread_sigmask(SIG_BLOCK, &l_pipe, &l_old);
#endif
    while (l_total < a_count && l_result) {
        l_written = write(p->input, a_data + l_total, (size_t) (a_count - l_total));
        if (l_written > 0) {
            l_total += (int) l_written;
        } else if (l_written == 0 || errno != EINTR) {
            l_result = 0;
        }
    }
#ifndef F_SETNOSIGPIPE
    if (!l_was_pending) {
        while (sigtimedwait(&l_pipe, NULL, &l_now) < 0 && errno == EINTR) { }
    }
    pthread_sigmask(SIG_SETMASK, &l_old, NULL);
#endif
    return l_result;
}

/* Close the child's stdin: it reads EOF. */
static void spp_close_input(spp_process* p)
{
    if (p) spp_close_fd(&p->input);
}

static int spp_input_open(spp_process* p) { return (p && p->input >= 0) ? 1 : 0; }

static spp_stream* spp_stream_of(spp_process* p, int a_which)
{
    return a_which == SPP_STDERR ? &p->err : &p->out;
}

/* Bytes of stream `a_which' collected and not yet taken. */
static int spp_available(spp_process* p, int a_which)
{
    size_t l_count;
    if (!p || !p->process) return 0;
    pthread_mutex_lock(&p->lock);
    l_count = spp_stream_of(p, a_which)->count;
    pthread_mutex_unlock(&p->lock);
    return l_count > 0x3FFFFFFF ? 0x3FFFFFFF : (int) l_count;
}

/* Move at most `a_capacity' collected bytes of stream `a_which' into
   `a_buffer'. Answers how many. */
static int spp_take(spp_process* p, int a_which, char* a_buffer, int a_capacity)
{
    spp_stream* s;
    size_t l_n;
    if (!p || !p->process || a_capacity <= 0) return 0;
    pthread_mutex_lock(&p->lock);
    s = spp_stream_of(p, a_which);
    l_n = s->count < (size_t) a_capacity ? s->count : (size_t) a_capacity;
    if (l_n > 0) {
        memcpy(a_buffer, s->data, l_n);
        memmove(s->data, s->data + l_n, s->count - l_n);
        s->count -= l_n;
    }
    pthread_mutex_unlock(&p->lock);
    return (int) l_n;
}

/* Has stream `a_which' ended with every byte taken? */
static int spp_drained(spp_process* p, int a_which)
{
    int l_result;
    spp_stream* s;
    if (!p || !p->process) return 1;
    pthread_mutex_lock(&p->lock);
    s = spp_stream_of(p, a_which);
    l_result = (s->ended && s->count == 0) ? 1 : 0;
    pthread_mutex_unlock(&p->lock);
    return l_result;
}

/* Did a stream pass its limit, so bytes were dropped? */
static int spp_truncated(spp_process* p)
{
    int l_result;
    if (!p || !p->process) return 0;
    pthread_mutex_lock(&p->lock);
    l_result = (p->out.truncated || p->err.truncated) ? 1 : 0;
    pthread_mutex_unlock(&p->lock);
    return l_result;
}

/* Is `a_name' (UTF-8) found the way `spp_start' would find it? WAITS: a dead
   network mount on PATH costs seconds. */
static int spp_file_in_path(void* a_name)
{
    char l_found[PATH_MAX];
    return spp_find_program((const char*) a_name, l_found);
}

/* Did a pump run out of memory and drop bytes? */
static int spp_lost(spp_process* p)
{
    int l_result;
    if (!p || !p->process) return 0;
    pthread_mutex_lock(&p->lock);
    l_result = (p->out.lost || p->err.lost) ? 1 : 0;
    pthread_mutex_unlock(&p->lock);
    return l_result;
}

static int spp_ready(spp_process* p, int a_mode)
{
    switch (a_mode) {
    case SPP_AWAIT_ANY:
        return p->out.count > 0 || p->err.count > 0 || (p->out.ended && p->err.ended);
    case SPP_AWAIT_LINE:
        return p->out.ended || (p->out.count > 0 && memchr(p->out.data, '\n', p->out.count) != NULL);
    default:
        return p->out.ended && p->err.ended;
    }
}

static long long spp_now_ms(void)
{
    struct timespec l_now;
    clock_gettime(CLOCK_MONOTONIC, &l_now);
    return (long long) l_now.tv_sec * 1000 + l_now.tv_nsec / 1000000;
}

/* With the lock held: wait for a change, at most `a_ms' (negative: no limit). */
static void spp_wait_change(spp_process* p, long long a_ms)
{
    struct timespec l_until;
    long long l_slice = (a_ms < SPP_WAIT_SLICE_MS) ? a_ms : SPP_WAIT_SLICE_MS;
    if (a_ms < 0) {
        pthread_cond_wait(&p->signal, &p->lock);
    } else {
        clock_gettime(CLOCK_REALTIME, &l_until);
        l_until.tv_sec += (time_t) (l_slice / 1000);
        l_until.tv_nsec += (long) (l_slice % 1000) * 1000000L;
        if (l_until.tv_nsec >= 1000000000L) {
            l_until.tv_sec += 1;
            l_until.tv_nsec -= 1000000000L;
        }
        pthread_cond_timedwait(&p->signal, &p->lock, &l_until);
    }
}

/* Wait until `a_mode' holds or `a_timeout_ms' passes (negative: forever).
   1 when it holds, 0 on timeout. */
static int spp_await(spp_process* p, int a_mode, int a_timeout_ms)
{
    long long l_start = spp_now_ms();
    long long l_left = -1;
    int l_result = 0;
    if (!p || !p->process) return 1;
    pthread_mutex_lock(&p->lock);
    for (;;) {
        if (spp_ready(p, a_mode)) { l_result = 1; break; }
        if (a_timeout_ms >= 0) {
            l_left = (long long) a_timeout_ms - (spp_now_ms() - l_start);
            if (l_left <= 0) break;
        }
        spp_wait_change(p, l_left);
    }
    pthread_mutex_unlock(&p->lock);
    return l_result;
}

/* Wait for the child to exit. 1 when it has, 0 on timeout (negative: forever). */
static int spp_wait_exit(spp_process* p, int a_timeout_ms)
{
    long long l_start = spp_now_ms();
    long long l_left = -1;
    int l_result = 0;
    if (!p || !p->process) return 1;
    pthread_mutex_lock(&p->lock);
    for (;;) {
        if (p->exited) { l_result = 1; break; }
        if (a_timeout_ms >= 0) {
            l_left = (long long) a_timeout_ms - (spp_now_ms() - l_start);
            if (l_left <= 0) break;
        }
        spp_wait_change(p, l_left);
    }
    pthread_mutex_unlock(&p->lock);
    return l_result;
}

static int spp_kill(spp_process* p)
{
    int l_result = 0;
    if (!p || !p->process) return 0;
    pthread_mutex_lock(&p->lock);
    if (!p->exited) {
        p->killed = 1;
        l_result = kill(p->pid, SIGKILL) == 0 ? 1 : 0;
    }
    pthread_mutex_unlock(&p->lock);
    return l_result;
}

static void spp_join_pump(spp_stream* s)
{
    if (s->has_thread) {
        pthread_join(s->thread, NULL);
        s->has_thread = 0;
    }
    spp_close_fd(&s->pipe);
    free(s->data);
    s->data = NULL;
    s->count = 0;
    s->capacity = 0;
}

/* Close stdin, stop the pumps, release everything. Does NOT kill the child:
   one still running keeps running, and its later writes fail. */
static void spp_close(spp_process* p)
{
    if (!p) return;
    spp_close_input(p);
    spp_close_fd(&p->wake[1]);
    spp_join_pump(&p->out);
    spp_join_pump(&p->err);
    spp_close_fd(&p->wake[0]);
    spp_release(p);
}

#endif

#endif /* SIMPLE_PROCESS_PIPE_H */
