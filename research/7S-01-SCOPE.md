# 7S-01-SCOPE: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## Problem Statement

Eiffel applications need to execute external processes and capture output. The EiffelStudio process library has SCOOP compatibility issues due to threading dependencies.

## Target Users

1. **System Administrators** - Automation scripts
2. **Build Tools** - Compile and test execution
3. **Integration Systems** - External tool orchestration
4. **CLI Applications** - Shell command execution

## Core Capabilities

1. **Command Execution** - Run shell commands
2. **Output Capture** - Get stdout as STRING_32
3. **Exit Codes** - Access process exit codes
4. **Error Handling** - Detailed error messages
5. **Working Directory** - Execute in specific directories
6. **PATH Lookup** - Check executable availability
7. **Window Visibility** - Show/hide process windows

## Out of Scope

- Interactive processes (stdin)
- Streaming output
- Process signals
- Process trees
- Linux/macOS support (Windows only)
- Async execution (use simple_async_process)

## Success Criteria

1. Execute commands with <50ms overhead
2. Capture full output (no truncation)
3. SCOOP compatible (no threading)
4. UTF-8/UTF-16 output support
5. Full Design by Contract coverage
