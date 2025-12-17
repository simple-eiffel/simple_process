/*
 * simple_process.c - Cross-platform process execution wrapper for Eiffel
 *
 * Windows: Uses Win32 CreateProcess API
 * Linux: Uses POSIX fork/exec with pipes
 *
 * Provides SCOOP-compatible process execution without thread dependencies.
 * Uses synchronous I/O for output capture.
 *
 * Copyright (c) 2025 Larry Rix - MIT License
 */

#include "simple_process.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUFFER_SIZE 4096
#define MAX_OUTPUT_SIZE (1024 * 1024)  /* 1MB max output */

static char last_error_msg[512] = {0};

#if defined(_WIN32) || defined(EIF_WINDOWS)
/* ============ WINDOWS ERROR HANDLING ============ */

/* Store last error message */
static void store_last_error(void) {
    DWORD err = GetLastError();
    FormatMessageA(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL,
        err,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        last_error_msg,
        sizeof(last_error_msg) - 1,
        NULL
    );
}

#else
/* ============ POSIX ERROR HANDLING ============ */

#include <sys/wait.h>
#include <sys/select.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>

static void store_last_error(void) {
    const char* err = strerror(errno);
    strncpy(last_error_msg, err, sizeof(last_error_msg) - 1);
    last_error_msg[sizeof(last_error_msg) - 1] = '\0';
}

#endif

const char* sp_get_last_error(void) {
    return last_error_msg;
}

#if defined(_WIN32) || defined(EIF_WINDOWS)
/* ============ WINDOWS sp_execute_command ============ */

sp_result* sp_execute_command(const char* command, const char* working_dir, int show_window) {
    sp_result* result;
    SECURITY_ATTRIBUTES sa;
    HANDLE hStdOutRead = NULL, hStdOutWrite = NULL;
    HANDLE hStdErrRead = NULL, hStdErrWrite = NULL;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    char* cmd_copy = NULL;
    char* output_buffer = NULL;
    int output_size = 0;
    int output_capacity = BUFFER_SIZE;
    DWORD bytes_read;
    char read_buffer[BUFFER_SIZE];
    BOOL success;

    /* Allocate result structure */
    result = (sp_result*)malloc(sizeof(sp_result));
    if (!result) return NULL;
    memset(result, 0, sizeof(sp_result));

    /* Set up security attributes for inheritable handles */
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = NULL;

    /* Create pipes for stdout */
    if (!CreatePipe(&hStdOutRead, &hStdOutWrite, &sa, 0)) {
        store_last_error();
        result->error_message = _strdup(last_error_msg);
        result->success = 0;
        return result;
    }

    /* Ensure read handle is not inherited */
    SetHandleInformation(hStdOutRead, HANDLE_FLAG_INHERIT, 0);

    /* Create pipes for stderr (redirect to stdout) */
    if (!DuplicateHandle(GetCurrentProcess(), hStdOutWrite,
                         GetCurrentProcess(), &hStdErrWrite,
                         0, TRUE, DUPLICATE_SAME_ACCESS)) {
        store_last_error();
        result->error_message = _strdup(last_error_msg);
        result->success = 0;
        CloseHandle(hStdOutRead);
        CloseHandle(hStdOutWrite);
        return result;
    }

    /* Set up startup info */
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.hStdOutput = hStdOutWrite;
    si.hStdError = hStdErrWrite;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.dwFlags |= STARTF_USESTDHANDLES;

    if (!show_window) {
        si.dwFlags |= STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;
    }

    /* CreateProcess needs a modifiable string */
    cmd_copy = _strdup(command);
    if (!cmd_copy) {
        result->error_message = _strdup("Memory allocation failed");
        result->success = 0;
        CloseHandle(hStdOutRead);
        CloseHandle(hStdOutWrite);
        CloseHandle(hStdErrWrite);
        return result;
    }

    memset(&pi, 0, sizeof(pi));

    /* Create the process */
    success = CreateProcessA(
        NULL,           /* Application name (use command line) */
        cmd_copy,       /* Command line */
        NULL,           /* Process security attributes */
        NULL,           /* Thread security attributes */
        TRUE,           /* Inherit handles */
        CREATE_NO_WINDOW, /* Creation flags */
        NULL,           /* Environment (inherit) */
        working_dir,    /* Working directory */
        &si,            /* Startup info */
        &pi             /* Process info */
    );

    free(cmd_copy);

    /* Close write ends of pipes (child has them now) */
    CloseHandle(hStdOutWrite);
    CloseHandle(hStdErrWrite);

    if (!success) {
        store_last_error();
        result->error_message = _strdup(last_error_msg);
        result->success = 0;
        CloseHandle(hStdOutRead);
        return result;
    }

    /* Allocate output buffer */
    output_buffer = (char*)malloc(output_capacity);
    if (!output_buffer) {
        result->error_message = _strdup("Memory allocation failed");
        result->success = 0;
        CloseHandle(hStdOutRead);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        return result;
    }

    /* Read output from pipe */
    while (1) {
        success = ReadFile(hStdOutRead, read_buffer, BUFFER_SIZE - 1, &bytes_read, NULL);
        if (!success || bytes_read == 0) break;

        /* Expand buffer if needed */
        if (output_size + bytes_read >= output_capacity) {
            int new_capacity = output_capacity * 2;
            char* new_buffer;
            if (new_capacity > MAX_OUTPUT_SIZE) {
                new_capacity = MAX_OUTPUT_SIZE;
            }
            if (output_size + bytes_read >= new_capacity) {
                break; /* Max size reached */
            }
            new_buffer = (char*)realloc(output_buffer, new_capacity);
            if (!new_buffer) break;
            output_buffer = new_buffer;
            output_capacity = new_capacity;
        }

        memcpy(output_buffer + output_size, read_buffer, bytes_read);
        output_size += bytes_read;
    }

    /* Null-terminate output */
    output_buffer[output_size] = '\0';

    CloseHandle(hStdOutRead);

    /* Wait for process to complete */
    WaitForSingleObject(pi.hProcess, INFINITE);

    /* Get exit code */
    GetExitCodeProcess(pi.hProcess, (DWORD*)&result->exit_code);

    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    result->success = 1;
    result->output = output_buffer;
    result->output_length = output_size;

    return result;
}

#else
/* ============ POSIX sp_execute_command ============ */

sp_result* sp_execute_command(const char* command, const char* working_dir, int show_window) {
    sp_result* result;
    int pipefd[2];
    pid_t pid;
    char* output_buffer = NULL;
    int output_size = 0;
    int output_capacity = BUFFER_SIZE;
    ssize_t bytes_read;
    char read_buffer[BUFFER_SIZE];
    int status;

    (void)show_window;  /* Unused on POSIX */

    /* Allocate result structure */
    result = (sp_result*)malloc(sizeof(sp_result));
    if (!result) return NULL;
    memset(result, 0, sizeof(sp_result));

    /* Create pipe for stdout */
    if (pipe(pipefd) < 0) {
        store_last_error();
        result->error_message = strdup(last_error_msg);
        result->success = 0;
        return result;
    }

    pid = fork();
    if (pid < 0) {
        store_last_error();
        result->error_message = strdup(last_error_msg);
        result->success = 0;
        close(pipefd[0]);
        close(pipefd[1]);
        return result;
    }

    if (pid == 0) {
        /* Child process */
        close(pipefd[0]);  /* Close read end */

        /* Redirect stdout and stderr to pipe */
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        close(pipefd[1]);

        /* Change working directory if specified */
        if (working_dir && working_dir[0]) {
            if (chdir(working_dir) < 0) {
                _exit(127);
            }
        }

        /* Execute command via shell */
        execl("/bin/sh", "sh", "-c", command, (char*)NULL);
        _exit(127);  /* exec failed */
    }

    /* Parent process */
    close(pipefd[1]);  /* Close write end */

    /* Allocate output buffer */
    output_buffer = (char*)malloc(output_capacity);
    if (!output_buffer) {
        result->error_message = strdup("Memory allocation failed");
        result->success = 0;
        close(pipefd[0]);
        waitpid(pid, NULL, 0);
        return result;
    }

    /* Read output from pipe */
    while ((bytes_read = read(pipefd[0], read_buffer, BUFFER_SIZE - 1)) > 0) {
        /* Expand buffer if needed */
        if (output_size + bytes_read >= output_capacity) {
            int new_capacity = output_capacity * 2;
            char* new_buffer;
            if (new_capacity > MAX_OUTPUT_SIZE) {
                new_capacity = MAX_OUTPUT_SIZE;
            }
            if (output_size + (int)bytes_read >= new_capacity) {
                break; /* Max size reached */
            }
            new_buffer = (char*)realloc(output_buffer, new_capacity);
            if (!new_buffer) break;
            output_buffer = new_buffer;
            output_capacity = new_capacity;
        }

        memcpy(output_buffer + output_size, read_buffer, bytes_read);
        output_size += bytes_read;
    }

    /* Null-terminate output */
    output_buffer[output_size] = '\0';

    close(pipefd[0]);

    /* Wait for child to exit */
    if (waitpid(pid, &status, 0) < 0) {
        store_last_error();
        result->error_message = strdup(last_error_msg);
        result->success = 0;
        free(output_buffer);
        return result;
    }

    if (WIFEXITED(status)) {
        result->exit_code = WEXITSTATUS(status);
    } else {
        result->exit_code = -1;
    }

    result->success = 1;
    result->output = output_buffer;
    result->output_length = output_size;

    return result;
}

#endif

sp_result* sp_execute_with_args(const char* program, const char* args, const char* working_dir, int show_window) {
    char* full_command;
    sp_result* result;
    size_t len;

    if (args && args[0]) {
        len = strlen(program) + strlen(args) + 2;
        full_command = (char*)malloc(len);
        if (!full_command) {
            result = (sp_result*)malloc(sizeof(sp_result));
            if (result) {
                memset(result, 0, sizeof(sp_result));
#if defined(_WIN32) || defined(EIF_WINDOWS)
                result->error_message = _strdup("Memory allocation failed");
#else
                result->error_message = strdup("Memory allocation failed");
#endif
            }
            return result;
        }
        sprintf(full_command, "%s %s", program, args);
    } else {
#if defined(_WIN32) || defined(EIF_WINDOWS)
        full_command = _strdup(program);
#else
        full_command = strdup(program);
#endif
    }

    result = sp_execute_command(full_command, working_dir, show_window);
    free(full_command);
    return result;
}

void sp_free_result(sp_result* result) {
    if (result) {
        if (result->output) free(result->output);
        if (result->error_message) free(result->error_message);
        free(result);
    }
}

#if defined(_WIN32) || defined(EIF_WINDOWS)

int sp_file_in_path(const char* filename) {
    char path_buffer[MAX_PATH];
    DWORD result;

    result = SearchPathA(NULL, filename, ".exe", MAX_PATH, path_buffer, NULL);
    return (result > 0) ? 1 : 0;
}

#else

int sp_file_in_path(const char* filename) {
    char check_cmd[512];
    snprintf(check_cmd, sizeof(check_cmd), "command -v %s > /dev/null 2>&1", filename);
    return system(check_cmd) == 0 ? 1 : 0;
}

#endif

/* ============ ASYNC PROCESS FUNCTIONS ============ */

#if defined(_WIN32) || defined(EIF_WINDOWS)
/* ============ WINDOWS ASYNC FUNCTIONS ============ */

sp_async_process* sp_start_async(const char* command, const char* working_dir, int show_window) {
    sp_async_process* proc;
    SECURITY_ATTRIBUTES sa;
    HANDLE hStdOutWrite = NULL;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    char* cmd_copy = NULL;
    BOOL success;

    /* Allocate process structure */
    proc = (sp_async_process*)malloc(sizeof(sp_async_process));
    if (!proc) return NULL;
    memset(proc, 0, sizeof(sp_async_process));

    /* Set up security attributes for inheritable handles */
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = NULL;

    /* Create pipe for stdout */
    if (!CreatePipe(&proc->hStdOutRead, &hStdOutWrite, &sa, 0)) {
        store_last_error();
        proc->error_message = _strdup(last_error_msg);
        proc->started = 0;
        return proc;
    }

    /* Ensure read handle is not inherited */
    SetHandleInformation(proc->hStdOutRead, HANDLE_FLAG_INHERIT, 0);

    /* Set up startup info */
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.hStdOutput = hStdOutWrite;
    si.hStdError = hStdOutWrite;  /* Redirect stderr to stdout */
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.dwFlags |= STARTF_USESTDHANDLES;

    if (!show_window) {
        si.dwFlags |= STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;
    }

    /* CreateProcess needs a modifiable string */
    cmd_copy = _strdup(command);
    if (!cmd_copy) {
        proc->error_message = _strdup("Memory allocation failed");
        proc->started = 0;
        CloseHandle(proc->hStdOutRead);
        CloseHandle(hStdOutWrite);
        return proc;
    }

    memset(&pi, 0, sizeof(pi));

    /* Create the process */
    success = CreateProcessA(
        NULL,           /* Application name (use command line) */
        cmd_copy,       /* Command line */
        NULL,           /* Process security attributes */
        NULL,           /* Thread security attributes */
        TRUE,           /* Inherit handles */
        CREATE_NO_WINDOW, /* Creation flags */
        NULL,           /* Environment (inherit) */
        working_dir,    /* Working directory */
        &si,            /* Startup info */
        &pi             /* Process info */
    );

    free(cmd_copy);
    CloseHandle(hStdOutWrite);  /* Close write end - child has it */

    if (!success) {
        store_last_error();
        proc->error_message = _strdup(last_error_msg);
        proc->started = 0;
        CloseHandle(proc->hStdOutRead);
        return proc;
    }

    /* Store process info */
    proc->hProcess = pi.hProcess;
    proc->hThread = pi.hThread;
    proc->processId = pi.dwProcessId;
    proc->started = 1;

    return proc;
}

int sp_is_running(sp_async_process* proc) {
    DWORD exit_code;
    if (!proc || !proc->started || proc->hProcess == NULL) {
        return 0;
    }
    if (GetExitCodeProcess(proc->hProcess, &exit_code)) {
        return (exit_code == STILL_ACTIVE) ? 1 : 0;
    }
    return 0;
}

DWORD sp_get_pid(sp_async_process* proc) {
    if (!proc || !proc->started) return 0;
    return proc->processId;
}

int sp_wait_timeout(sp_async_process* proc, unsigned int timeout_ms) {
    DWORD result;
    if (!proc || !proc->started || proc->hProcess == NULL) {
        return -1;
    }
    result = WaitForSingleObject(proc->hProcess, (DWORD)timeout_ms);
    if (result == WAIT_OBJECT_0) {
        return 1;  /* Process finished */
    } else if (result == WAIT_TIMEOUT) {
        return 0;  /* Timeout */
    }
    return -1;  /* Error */
}

int sp_kill(sp_async_process* proc) {
    if (!proc || !proc->started || proc->hProcess == NULL) {
        return 0;
    }
    if (TerminateProcess(proc->hProcess, 1)) {
        return 1;
    }
    return 0;
}

int sp_get_exit_code(sp_async_process* proc) {
    DWORD exit_code;
    if (!proc || !proc->started || proc->hProcess == NULL) {
        return -1;
    }
    if (GetExitCodeProcess(proc->hProcess, &exit_code)) {
        if (exit_code == STILL_ACTIVE) {
            return -1;  /* Still running */
        }
        return (int)exit_code;
    }
    return -1;
}

char* sp_read_output(sp_async_process* proc, int* out_length) {
    char* buffer = NULL;
    char read_buffer[4096];
    DWORD bytes_available, bytes_read;
    int total_size = 0;
    int buffer_capacity = 0;

    *out_length = 0;

    if (!proc || !proc->started || proc->hStdOutRead == NULL) {
        return NULL;
    }

    /* Check if data is available (non-blocking) */
    if (!PeekNamedPipe(proc->hStdOutRead, NULL, 0, NULL, &bytes_available, NULL)) {
        return NULL;
    }

    if (bytes_available == 0) {
        return NULL;  /* No data available */
    }

    /* Allocate initial buffer */
    buffer_capacity = (bytes_available > 4096) ? bytes_available + 1 : 4096;
    buffer = (char*)malloc(buffer_capacity);
    if (!buffer) return NULL;

    /* Read available data */
    while (PeekNamedPipe(proc->hStdOutRead, NULL, 0, NULL, &bytes_available, NULL) && bytes_available > 0) {
        DWORD to_read = (bytes_available > sizeof(read_buffer) - 1) ? sizeof(read_buffer) - 1 : bytes_available;

        if (ReadFile(proc->hStdOutRead, read_buffer, to_read, &bytes_read, NULL) && bytes_read > 0) {
            /* Expand buffer if needed */
            if (total_size + bytes_read >= buffer_capacity) {
                int new_capacity = buffer_capacity * 2;
                char* new_buffer = (char*)realloc(buffer, new_capacity);
                if (!new_buffer) break;
                buffer = new_buffer;
                buffer_capacity = new_capacity;
            }
            memcpy(buffer + total_size, read_buffer, bytes_read);
            total_size += bytes_read;
        } else {
            break;
        }
    }

    buffer[total_size] = '\0';
    *out_length = total_size;
    return buffer;
}

void sp_async_close(sp_async_process* proc) {
    if (proc) {
        if (proc->hProcess) CloseHandle(proc->hProcess);
        if (proc->hThread) CloseHandle(proc->hThread);
        if (proc->hStdOutRead) CloseHandle(proc->hStdOutRead);
        if (proc->error_message) free(proc->error_message);
        free(proc);
    }
}

#else
/* ============ POSIX ASYNC FUNCTIONS ============ */

sp_async_process* sp_start_async(const char* command, const char* working_dir, int show_window) {
    sp_async_process* proc;
    int pipefd[2];
    pid_t pid;

    (void)show_window;  /* Unused on POSIX */

    /* Allocate process structure */
    proc = (sp_async_process*)malloc(sizeof(sp_async_process));
    if (!proc) return NULL;
    memset(proc, 0, sizeof(sp_async_process));
    proc->stdout_fd = -1;

    /* Create pipe for stdout */
    if (pipe(pipefd) < 0) {
        store_last_error();
        proc->error_message = strdup(last_error_msg);
        proc->started = 0;
        return proc;
    }

    pid = fork();
    if (pid < 0) {
        store_last_error();
        proc->error_message = strdup(last_error_msg);
        proc->started = 0;
        close(pipefd[0]);
        close(pipefd[1]);
        return proc;
    }

    if (pid == 0) {
        /* Child process */
        close(pipefd[0]);  /* Close read end */

        /* Redirect stdout and stderr to pipe */
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        close(pipefd[1]);

        /* Change working directory if specified */
        if (working_dir && working_dir[0]) {
            if (chdir(working_dir) < 0) {
                _exit(127);
            }
        }

        /* Execute command via shell */
        execl("/bin/sh", "sh", "-c", command, (char*)NULL);
        _exit(127);  /* exec failed */
    }

    /* Parent process */
    close(pipefd[1]);  /* Close write end */

    /* Set stdout_fd to non-blocking */
    fcntl(pipefd[0], F_SETFL, fcntl(pipefd[0], F_GETFL) | O_NONBLOCK);

    proc->pid = pid;
    proc->stdout_fd = pipefd[0];
    proc->started = 1;

    return proc;
}

int sp_is_running(sp_async_process* proc) {
    int status;
    pid_t result;

    if (!proc || !proc->started || proc->pid <= 0) {
        return 0;
    }

    result = waitpid(proc->pid, &status, WNOHANG);
    if (result == 0) {
        return 1;  /* Still running */
    }
    return 0;  /* Finished or error */
}

pid_t sp_get_pid(sp_async_process* proc) {
    if (!proc || !proc->started) return 0;
    return proc->pid;
}

int sp_wait_timeout(sp_async_process* proc, unsigned int timeout_ms) {
    int status;
    pid_t result;
    unsigned int elapsed = 0;
    unsigned int sleep_interval = 10;  /* 10ms */

    if (!proc || !proc->started || proc->pid <= 0) {
        return -1;
    }

    while (elapsed < timeout_ms) {
        result = waitpid(proc->pid, &status, WNOHANG);
        if (result > 0) {
            return 1;  /* Process finished */
        } else if (result < 0) {
            return -1;  /* Error */
        }
        usleep(sleep_interval * 1000);
        elapsed += sleep_interval;
    }
    return 0;  /* Timeout */
}

int sp_kill(sp_async_process* proc) {
    if (!proc || !proc->started || proc->pid <= 0) {
        return 0;
    }
    if (kill(proc->pid, SIGKILL) == 0) {
        return 1;
    }
    return 0;
}

int sp_get_exit_code(sp_async_process* proc) {
    int status;
    pid_t result;

    if (!proc || !proc->started || proc->pid <= 0) {
        return -1;
    }

    result = waitpid(proc->pid, &status, WNOHANG);
    if (result > 0) {
        if (WIFEXITED(status)) {
            return WEXITSTATUS(status);
        }
        return -1;
    }
    return -1;  /* Still running or error */
}

char* sp_read_output(sp_async_process* proc, int* out_length) {
    char* buffer = NULL;
    char read_buffer[4096];
    ssize_t bytes_read;
    int total_size = 0;
    int buffer_capacity = 4096;

    *out_length = 0;

    if (!proc || !proc->started || proc->stdout_fd < 0) {
        return NULL;
    }

    buffer = (char*)malloc(buffer_capacity);
    if (!buffer) return NULL;

    /* Read available data (non-blocking) */
    while ((bytes_read = read(proc->stdout_fd, read_buffer, sizeof(read_buffer) - 1)) > 0) {
        /* Expand buffer if needed */
        if (total_size + bytes_read >= buffer_capacity) {
            int new_capacity = buffer_capacity * 2;
            char* new_buffer = (char*)realloc(buffer, new_capacity);
            if (!new_buffer) break;
            buffer = new_buffer;
            buffer_capacity = new_capacity;
        }
        memcpy(buffer + total_size, read_buffer, bytes_read);
        total_size += bytes_read;
    }

    if (total_size == 0) {
        free(buffer);
        return NULL;
    }

    buffer[total_size] = '\0';
    *out_length = total_size;
    return buffer;
}

void sp_async_close(sp_async_process* proc) {
    if (proc) {
        if (proc->stdout_fd >= 0) close(proc->stdout_fd);
        if (proc->error_message) free(proc->error_message);
        free(proc);
    }
}

#endif
