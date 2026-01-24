# S04-FEATURE-SPECS: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## SIMPLE_PROCESS Features

### Creation
| Feature | Signature | Description |
|---------|-----------|-------------|
| make | `make` | Initialize process executor |

### Settings
| Feature | Signature | Description |
|---------|-----------|-------------|
| show_window | `show_window: BOOLEAN` | Show process window? |
| set_show_window | `set_show_window (a_value: BOOLEAN)` | Set window visibility |

### Execution
| Feature | Signature | Description |
|---------|-----------|-------------|
| execute | `execute (a_command)` | Execute and capture output |
| execute_in_directory | `execute_in_directory (a_command, a_dir)` | Execute in directory |
| output_of_command | `output_of_command (a_command): STRING_32` | Execute and return output |
| output_of_command_in_directory | `output_of_command_in_directory (a_command, a_dir): STRING_32` | Execute in directory |

### Results
| Feature | Signature | Description |
|---------|-----------|-------------|
| last_output | `last_output: detachable STRING_32` | Captured output |
| last_exit_code | `last_exit_code: INTEGER` | Process exit code |
| last_error | `last_error: detachable STRING_32` | Error message |
| was_successful | `was_successful: BOOLEAN` | Execution succeeded? |

### Model Queries
| Feature | Signature | Description |
|---------|-----------|-------------|
| execution_count | `execution_count: INTEGER` | Commands executed |
| has_executed | `has_executed: BOOLEAN` | Any execution done? |
| last_command | `last_command: detachable READABLE_STRING_GENERAL` | Last command |

### Query
| Feature | Signature | Description |
|---------|-----------|-------------|
| file_exists_in_path | `file_exists_in_path (a_filename): BOOLEAN` | Check PATH |
