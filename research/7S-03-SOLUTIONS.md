# 7S-03-SOLUTIONS: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## Alternative Solutions Considered

### 1. EiffelStudio Process Library (Rejected)
- **Approach**: Use ISE's PROCESS_FACTORY
- **Pros**: Standard library, cross-platform
- **Cons**: Threading dependencies, SCOOP incompatible
- **Decision**: Rejected - SCOOP issues

### 2. Direct C Runtime (Rejected)
- **Approach**: Use system() or popen()
- **Pros**: Simple, portable
- **Cons**: Limited control, no window hiding
- **Decision**: Rejected - insufficient features

### 3. Custom Win32 Wrapper (Chosen)
- **Approach**: Direct Win32 API via C wrapper
- **Pros**: Full control, SCOOP compatible, no threads
- **Cons**: Windows only, C code required
- **Decision**: Selected - best for ecosystem

### 4. PowerShell Execution (Rejected)
- **Approach**: Use PowerShell for all commands
- **Pros**: Rich scripting
- **Cons**: Overhead, dependency
- **Decision**: Rejected - too heavy

## Architecture Decisions

1. **C wrapper library** - simple_process.c/h
2. **Synchronous execution** - No threading
3. **Pipe-based output** - Capture stdout
4. **Managed memory** - sp_result allocation
5. **Inline C externals** - No separate .c in Eiffel
