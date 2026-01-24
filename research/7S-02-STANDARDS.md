# 7S-02-STANDARDS: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## Applicable Standards

### Win32 API
- **CreateProcess** - Process creation
- **WaitForSingleObject** - Process completion wait
- **ReadFile** - Pipe output reading
- **GetExitCodeProcess** - Exit code retrieval

### Command Execution
- **cmd /c** - Shell command execution
- **PATH** - Executable search path
- **Working Directory** - Current directory for process

### Output Encoding
- **UTF-8** - Primary output encoding
- **UTF-16** - Windows native encoding
- **Console Codepage** - System default

## C Interface

```c
typedef struct {
    int success;
    int exit_code;
    char* output;
    int output_length;
    char* error_message;
} sp_result;

sp_result* sp_execute_command(const char* command,
                               const char* working_dir,
                               int show_window);
void sp_free_result(sp_result* result);
int sp_file_in_path(const char* filename);
```

## Design Patterns

1. **Facade Pattern** - SIMPLE_PROCESS wraps C API
2. **Command Pattern** - Execute commands
3. **Result Object** - sp_result structure
