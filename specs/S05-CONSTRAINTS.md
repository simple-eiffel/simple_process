# S05-CONSTRAINTS: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## Technical Constraints

### Platform Requirements
- **Windows** only (Win32 API)
- Visual Studio C++ Build Tools
- EiffelStudio with C compiler

### C Library Requirements
- simple_process.obj must be compiled
- Link with kernel32.lib (automatic)
- 64-bit compilation required

### Command Format
- Commands passed to cmd.exe /c
- Use forward slashes or escaped backslashes
- Quote paths with spaces

### Output Constraints
- UTF-8 conversion from console output
- Large output buffered in memory
- No streaming (wait for completion)

## API Constraints

### Commands
- Must be non-empty
- Shell metacharacters interpreted
- Working directory must exist

### Results
- last_output may be Void on failure
- Exit code 0 typically means success
- Error messages from Windows API

## Invariants

### Execution Tracking
- execution_count >= 0
- has_executed = (execution_count > 0)
- was_successful implies last_output attached

### Settings
- show_window defaults to False
- Settings persist across executions
