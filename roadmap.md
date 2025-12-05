# SIMPLE_PROCESS Roadmap

---

## Claude: Start Here

**When starting a new conversation, read this file first.**

### Session Startup

1. **Read Eiffel reference docs**: `D:/prod/reference_docs/eiffel/claude/CONTEXT.md`
2. **Review this roadmap** for project-specific context
3. **Ask**: "What would you like to work on this session?"

### Key Reference Files

| File | Purpose |
|------|---------|
| `D:/prod/reference_docs/eiffel/claude/CONTEXT.md` | Generic Eiffel knowledge |
| `D:/prod/reference_docs/eiffel/language/gotchas.md` | Generic Eiffel gotchas |
| `D:/prod/reference_docs/eiffel/language/patterns.md` | Verified code patterns |

### Build & Test Commands

```batch
:: Set environment variable (if not already set)
set TESTING_EXT=D:\prod\testing_ext

:: Compile
ec.exe -batch -config simple_process.ecf -target simple_process_tests -c_compile -freeze

:: Clean compile
ec.exe -batch -config simple_process.ecf -target simple_process_tests -c_compile -freeze -clean

:: Run tests
ec.exe -batch -config simple_process.ecf -target simple_process_tests -tests
```

### Current Status

**Stable** - 9 tests passing

---

## Project Overview

SIMPLE_PROCESS is a lightweight wrapper for executing shell commands and capturing output. It was created to replace the heavier `framework` library dependency, specifically the `FW_PROCESS_HELPER` class.

### Design Philosophy

- **Minimal dependencies**: Only uses `base`, `encoding`, and `process` libraries
- **Single responsibility**: Process execution only, no unrelated features
- **Thread-compatible**: Uses `thread` concurrency to match ISE process library

---

## Current State

### SIMPLE_PROCESS_HELPER

The single class providing all functionality:

| Feature | Description |
|---------|-------------|
| `output_of_command` | Execute command and capture stdout/stderr |
| `has_file_in_path` | Check if executable exists in PATH |
| `show_process` | Control process window visibility |
| `is_wait_for_exit` | Control wait behavior |

---

## Class Structure

```
SIMPLE_PROCESS_HELPER
  - output_of_command (command, directory): STRING_32
  - has_file_in_path (name): BOOLEAN
  - show_process: BOOLEAN
  - set_show_process (value)
  - is_wait_for_exit: BOOLEAN
  - set_wait_for_exit
  - set_do_not_wait_for_exit
```

---

## Dependencies

- `base` - Eiffel standard library
- `encoding` - LOCALIZED_PRINTER, SYSTEM_ENCODINGS
- `process` - PROCESS, PROCESS_FACTORY

### Concurrency Note

The ISE `process` library only supports `thread` concurrency (not SCOOP). Therefore, SIMPLE_PROCESS uses:

```xml
<capability>
    <concurrency support="thread" use="thread"/>
</capability>
```

Any project using SIMPLE_PROCESS must also use thread concurrency or be compatible with it.

---

## Potential Future Work

| Feature | Description | Priority |
|---------|-------------|----------|
| **Async execution** | Fire-and-forget command execution | Low |
| **Timeout support** | Kill process after timeout | Low |
| **Exit code capture** | Return exit code along with output | Medium |
| **Environment variables** | Pass custom environment to subprocess | Low |

---

## Session Notes

### 2025-12-02 (Initial Creation)

**Task**: Create lightweight process library to replace framework dependency

**Motivation**: The `framework` library brought in the `process` library which created SCOOP/Thread concurrency conflicts. simple_web needed process execution but didn't need all of framework's other features.

**Implementation**:
- Created SIMPLE_PROCESS_HELPER based on FW_PROCESS_HELPER
- Removed RANDOMIZER inheritance (no longer needed)
- Simplified to essential features only
- 9 tests covering core functionality

**Result**: 9/9 tests passing, successfully used by simple_web

---

## Notes

- All development follows Eiffel Design by Contract principles
- Classes use ECMA-367 standard Eiffel
- Testing via EiffelStudio AutoTest framework with TEST_SET_BASE
