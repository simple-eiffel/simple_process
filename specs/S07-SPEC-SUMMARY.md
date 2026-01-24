# S07-SPEC-SUMMARY: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## Executive Summary

simple_process provides SCOOP-compatible process execution for Eiffel applications using direct Win32 API calls, replacing the threading-dependent EiffelStudio process library.

## Key Specifications

### Architecture
- **Pattern**: Facade over C wrapper
- **Main Class**: SIMPLE_PROCESS
- **C Library**: simple_process.c/h
- **API**: Win32 CreateProcess

### API Design
- **Multiple Aliases**: Various names for same features
- **Model Queries**: execution_count, has_executed
- **Fluent Results**: was_successful, last_output

### Features
1. Command execution
2. Output capture (STRING_32)
3. Exit code retrieval
4. Error handling
5. Working directory
6. Window visibility
7. PATH lookup
8. Execution tracking

### Dependencies
- EiffelBase
- Win32 API (kernel32.dll)

### Platform Support
- Windows only (by design)

## Contract Highlights

- Commands must be non-empty
- Execution count tracks all calls
- Success implies output attached
- PATH checks don't count as executions

## Performance Targets

| Operation | Target |
|-----------|--------|
| Simple command | <100ms |
| PATH check | <10ms |
| Overhead | <50ms |
