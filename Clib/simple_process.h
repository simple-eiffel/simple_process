/*
 * simple_process.h - Cross-platform process execution wrapper for Eiffel
 *
 * Windows: Uses Win32 CreateProcess API
 * Linux: Uses POSIX fork/exec with pipes
 *
 * Provides SCOOP-compatible process execution without thread dependencies.
 * Uses synchronous I/O for output capture.
 *
 * Copyright (c) 2025 Larry Rix - MIT License
 */

#ifndef SIMPLE_PROCESS_H
#define SIMPLE_PROCESS_H

#if defined(_WIN32) || defined(EIF_WINDOWS)
#include <windows.h>
#else
#include <sys/types.h>
#include <unistd.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Process result structure */
typedef struct {
    int exit_code;
    int success;
    char* output;
    int output_length;
    char* error_message;
} sp_result;

/* Async process handle structure */
#if defined(_WIN32) || defined(EIF_WINDOWS)
typedef struct {
    HANDLE hProcess;        /* Process handle */
    HANDLE hThread;         /* Thread handle */
    HANDLE hStdOutRead;     /* Pipe read handle for output */
    DWORD processId;        /* Process ID (PID) */
    int started;            /* Was process started successfully? */
    char* error_message;    /* Error if start failed */
} sp_async_process;
#else
typedef struct {
    pid_t pid;              /* Process ID */
    int stdout_fd;          /* Pipe read handle for output */
    int started;            /* Was process started successfully? */
    char* error_message;    /* Error if start failed */
} sp_async_process;
#endif

/* Execute a command and capture output synchronously
 * Returns: sp_result pointer (caller must free with sp_free_result)
 */
sp_result* sp_execute_command(const char* command, const char* working_dir, int show_window);

/* Execute with separate args (command, args as space-separated string)
 * Returns: sp_result pointer (caller must free with sp_free_result)
 */
sp_result* sp_execute_with_args(const char* program, const char* args, const char* working_dir, int show_window);

/* Free result structure */
void sp_free_result(sp_result* result);

/* Get last Win32 error as string */
const char* sp_get_last_error(void);

/* Check if a file exists in system PATH */
int sp_file_in_path(const char* filename);

/* ============ ASYNC PROCESS FUNCTIONS ============ */

/* Start a process asynchronously (does not wait)
 * Returns: sp_async_process pointer (caller must free with sp_async_close)
 */
sp_async_process* sp_start_async(const char* command, const char* working_dir, int show_window);

/* Check if async process is still running
 * Returns: 1 if running, 0 if finished
 */
int sp_is_running(sp_async_process* proc);

/* Get the process ID (PID)
 * Returns: process ID or 0 if invalid
 */
#if defined(_WIN32) || defined(EIF_WINDOWS)
DWORD sp_get_pid(sp_async_process* proc);
#else
pid_t sp_get_pid(sp_async_process* proc);
#endif

/* Wait for process with timeout
 * Returns: 1 if process finished, 0 if timeout, -1 on error
 */
int sp_wait_timeout(sp_async_process* proc, unsigned int timeout_ms);

/* Kill/terminate the process
 * Returns: 1 on success, 0 on failure
 */
int sp_kill(sp_async_process* proc);

/* Get exit code (only valid after process finished)
 * Returns: exit code or -1 if still running
 */
int sp_get_exit_code(sp_async_process* proc);

/* Read available output (non-blocking)
 * Returns: output string (caller must free) or NULL if none available
 */
char* sp_read_output(sp_async_process* proc, int* out_length);

/* Cleanup async process handle */
void sp_async_close(sp_async_process* proc);

#ifdef __cplusplus
}
#endif

#endif /* SIMPLE_PROCESS_H */
