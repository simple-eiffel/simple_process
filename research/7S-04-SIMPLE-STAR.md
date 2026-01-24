# 7S-04-SIMPLE-STAR: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## Ecosystem Position

simple_process is a FOUNDATION-level library providing process execution.

```
FOUNDATION_API
├── simple_process (sync execution)
└── simple_async_process (future: async)
```

## Dependencies

| Library | Purpose | Required |
|---------|---------|----------|
| EiffelBase | Core types | Yes |
| Win32 API | Process API | Yes (C wrapper) |

## Integration Pattern

### ECF Configuration
```xml
<library name="simple_process"
         location="$SIMPLE_EIFFEL/simple_process/simple_process.ecf"/>
```

### C Library Compilation
```bash
cd simple_process/Clib
cl /c simple_process.c
```

### Basic Usage
```eiffel
local
    proc: SIMPLE_PROCESS
    output: STRING_32
do
    create proc.make
    output := proc.output_of_command ("cmd /c dir")
    if proc.was_successful then
        print (output)
    end
end
```

## Ecosystem Conventions

1. **Alias methods** - Multiple names for same feature
2. **Model queries** - execution_count, has_executed
3. **DBC coverage** - Full contracts
4. **Void safe** - Complete
5. **SCOOP compatible** - No threads
