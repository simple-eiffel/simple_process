# S02-CLASS-CATALOG: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## Class Hierarchy

```
ANY
├── SIMPLE_PROCESS              # Main process class
├── SIMPLE_ASYNC_PROCESS        # Async wrapper
└── SIMPLE_PROCESS_HELPER       # Legacy helper
```

## Class Descriptions

### SIMPLE_PROCESS
Main class for synchronous process execution.
- **Creation**: `make`
- **Purpose**: Execute commands, capture output
- **Key Features**:
  - execute/run/shell (aliases)
  - output_of_command
  - execute_in_directory
  - file_exists_in_path

### Feature Aliases
SIMPLE_PROCESS provides multiple names for the same operations:

| Primary | Aliases |
|---------|---------|
| last_output | output, stdout, result_text, captured_output |
| last_exit_code | exit_code, return_code, status_code |
| last_error | error_message, stderr, failure_reason |
| was_successful | succeeded, ok, passed, completed_ok |
| execute | run, run_command, shell, exec, spawn, launch |
| execute_in_directory | run_in, run_in_directory, exec_in, shell_in, launch_in |
| output_of_command | run_and_capture, exec_output, shell_output, capture_output, command_output |
| file_exists_in_path | is_in_path, command_exists, has_command |

### SIMPLE_ASYNC_PROCESS
Async wrapper for background execution.
- **Purpose**: Non-blocking command execution

### SIMPLE_PROCESS_HELPER
Legacy helper class.
- **Purpose**: Backward compatibility
