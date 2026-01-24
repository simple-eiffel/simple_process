# S03-CONTRACTS: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## SIMPLE_PROCESS Contracts

### make
```eiffel
make
    ensure
        window_hidden: not show_window
        no_executions: execution_count = 0
```

### set_show_window
```eiffel
set_show_window (a_value: BOOLEAN)
    ensure
        set: show_window = a_value
        execution_count_unchanged: execution_count = old execution_count
```

### execute
```eiffel
execute (a_command: READABLE_STRING_GENERAL)
    require
        command_not_empty: not a_command.is_empty
    ensure
        execution_recorded: execution_count = old execution_count + 1
        command_recorded: attached last_command as lc and then
                          lc.same_string (a_command)
```

### output_of_command
```eiffel
output_of_command (a_command: READABLE_STRING_GENERAL): STRING_32
    require
        command_not_empty: not a_command.is_empty
    ensure
        execution_recorded: execution_count = old execution_count + 1
        empty_on_failure: not was_successful implies Result.is_empty
```

### file_exists_in_path
```eiffel
file_exists_in_path (a_filename: READABLE_STRING_GENERAL): BOOLEAN
    require
        filename_not_empty: not a_filename.is_empty
    ensure
        execution_unchanged: execution_count = old execution_count
```

## Invariants

```eiffel
invariant
    execution_count_non_negative: execution_count >= 0
    has_executed_consistency: has_executed = (execution_count > 0)
    success_state_consistency: was_successful implies last_output /= Void
```
