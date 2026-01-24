# S06-BOUNDARIES: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## System Boundaries

### Component Architecture

```
+-------------------+
|   Application     |
+--------+----------+
         |
         v
+--------+----------+
|  SIMPLE_PROCESS   |
|    (Eiffel)       |
+--------+----------+
         |
         v
+--------+----------+
|  C Externals      |
| (inline/wrapper)  |
+--------+----------+
         |
         v
+--------+----------+
|  simple_process.c |
|   (Win32 API)     |
+--------+----------+
         |
         v
+--------+----------+
|   CreateProcess   |
|   (kernel32.dll)  |
+-------------------+
```

### Input Boundaries

| Input | Source | Validation |
|-------|--------|------------|
| Command | Caller | Non-empty |
| Working Dir | Caller | Optional |
| Show Window | Caller | Boolean |
| Filename | Caller | Non-empty (PATH check) |

### Output Boundaries

| Output | Target | Format |
|--------|--------|--------|
| Output | Caller | STRING_32 |
| Exit Code | Caller | INTEGER |
| Error | Caller | STRING_32 |
| Success | Caller | BOOLEAN |

## Dependency Boundaries

### Required
- EiffelBase
- kernel32.dll (Windows)
- cmd.exe (shell)

### Build Time
- Visual Studio C++ compiler
- EiffelStudio

## Trust Boundaries

### Trusted
- Windows API
- C wrapper code

### Untrusted
- Command strings (injection risk)
- Process output (may be unexpected)
- External executables
