/*
 * simple_process.h - Win32 process execution wrapper for Eiffel
 *
 * Provides SCOOP-compatible process execution without thread dependencies.
 * Uses synchronous I/O for output capture.
 *
 * Copyright (c) 2025 Larry Rix - MIT License
 */

#ifndef SIMPLE_PROCESS_H
#define SIMPLE_PROCESS_H

#include <windows.h>

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

#ifdef __cplusplus
}
#endif

#endif /* SIMPLE_PROCESS_H */
