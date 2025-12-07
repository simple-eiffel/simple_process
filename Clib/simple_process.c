/*
 * simple_process.c - Win32 process execution wrapper for Eiffel
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

const char* sp_get_last_error(void) {
    return last_error_msg;
}

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
                result->error_message = _strdup("Memory allocation failed");
            }
            return result;
        }
        sprintf(full_command, "%s %s", program, args);
    } else {
        full_command = _strdup(program);
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

int sp_file_in_path(const char* filename) {
    char path_buffer[MAX_PATH];
    DWORD result;

    result = SearchPathA(NULL, filename, ".exe", MAX_PATH, path_buffer, NULL);
    return (result > 0) ? 1 : 0;
}
