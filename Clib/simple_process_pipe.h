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

#else  /* ============ not Windows ============ */

/* simple_process runs child processes on Windows only. Every start fails
   with a message saying so; the rest answer "nothing". */

typedef struct {
    int process;
    char error_message[1024];
} spp_process;

static spp_process* spp_start(void* a_command, void* a_directory, int a_show_window, int a_merge_error, int a_options, int a_limit, void* a_job)
{
    spp_process* p = (spp_process*) calloc(1, sizeof(spp_process));
    (void) a_command; (void) a_directory; (void) a_show_window; (void) a_merge_error; (void) a_options; (void) a_limit; (void) a_job;
    if (p) strcpy(p->error_message, "simple_process runs child processes on Windows only");
    return p;
}
static int spp_started(spp_process* p) { (void) p; return 0; }
static const char* spp_error(spp_process* p) { return p ? p->error_message : ""; }
static unsigned long spp_pid(spp_process* p) { (void) p; return 0; }
static int spp_in_job(spp_process* p) { (void) p; return 0; }
static void* spp_new_owner_job(void) { return NULL; }
static int spp_is_running(spp_process* p) { (void) p; return 0; }
static int spp_exit_code(spp_process* p) { (void) p; return -1; }
static int spp_write(spp_process* p, const char* a_data, int a_count) { (void) p; (void) a_data; (void) a_count; return 0; }
static void spp_close_input(spp_process* p) { (void) p; }
static int spp_input_open(spp_process* p) { (void) p; return 0; }
static int spp_available(spp_process* p, int a_which) { (void) p; (void) a_which; return 0; }
static int spp_take(spp_process* p, int a_which, char* a_buffer, int a_capacity) { (void) p; (void) a_which; (void) a_buffer; (void) a_capacity; return 0; }
static int spp_drained(spp_process* p, int a_which) { (void) p; (void) a_which; return 1; }
static int spp_lost(spp_process* p) { (void) p; return 0; }
static int spp_truncated(spp_process* p) { (void) p; return 0; }
static int spp_file_in_path(void* a_name) { (void) a_name; return 0; }
static int spp_await(spp_process* p, int a_mode, int a_timeout_ms) { (void) p; (void) a_mode; (void) a_timeout_ms; return 1; }
static int spp_wait_exit(spp_process* p, int a_timeout_ms) { (void) p; (void) a_timeout_ms; return 1; }
static int spp_kill(spp_process* p) { (void) p; return 0; }
static void spp_close(spp_process* p) { free(p); }

#endif

#endif /* SIMPLE_PROCESS_PIPE_H */
