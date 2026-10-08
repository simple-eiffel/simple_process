<p align="center">
  <img src="docs/images/logo.svg" alt="simple_process logo" width="200">
</p>

<h1 align="center">simple_process</h1>

<p align="center">
  <a href="https://simple-eiffel.github.io/simple_process/">Documentation</a> •
  <a href="https://github.com/simple-eiffel/simple_process">GitHub</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/Eiffel-25.02-purple.svg" alt="Eiffel 25.02">
  <img src="https://img.shields.io/badge/DBC-Contracts-green.svg" alt="Design by Contract">
</p>

**SCOOP-compatible process execution for Eiffel** — Win32 API wrapper with output capture. Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

## Status

✅ **Production Ready** — v1.1.0
- 41 tests passing, plus a 7-test SCOOP freeze assault
- **A child gets an empty stdin**, output is **never silently cut**, and commands may hold **any characters** (1.1.0)
- **Write to a child's stdin** without pipe deadlock, any size (1.1.0)
- **Output is UTF-8 decoded**; raw bytes kept (1.1.0, see CHANGELOG for what changed)
- **A running child never stops another processor's allocator** (see CHANGELOG 1.0.1)
- SCOOP-compatible (no thread dependency)
- Direct Win32 API wrapper
- Full Design by Contract coverage

## Overview

SIMPLE_PROCESS provides SCOOP-compatible process execution for Eiffel applications. It wraps Win32 Process APIs through a clean C interface, enabling command execution with output capture without threading complications.

**Important:** This library has **no dependency on the EiffelStudio process library**. It uses direct Win32 API calls through a custom C wrapper, making it fully SCOOP-compatible.

---

## Features

### Process Operations

- **Execute Commands** - Run shell commands and capture output
- **Working Directory** - Execute in specific directories
- **Output Capture** - Get stdout as STRING_32, UTF-8 decoded (raw bytes in `last_output_bytes`)
- **Standard Input** - Run with input (`execute_with_input`), or talk to a running child line by line (`SIMPLE_PIPED_PROCESS`)
- **Exit Codes** - Access process exit codes
- **Error Handling** - Detailed error messages on failure
- **PATH Lookup** - Check if executables exist in PATH
- **Window Visibility** - Show/hide process windows

---

## Quick Start

### Installation

1. Clone the repository:
```bash
git clone https://github.com/simple-eiffel/simple_process.git
```

2. Nothing to compile separately: since 1.1.0 all C is inline, in the
   header `Clib/simple_process_pipe.h`.

3. Set the environment variable (one-time setup for all simple_* libraries):
```bash
set SIMPLE_EIFFEL=D:\prod
```

4. Add to your ECF file:
```xml
<library name="simple_process" location="$SIMPLE_EIFFEL/simple_process/simple_process.ecf"/>
```

### Basic Usage

```eiffel
class
    MY_APPLICATION

feature

    process_example
        local
            proc: SIMPLE_PROCESS
            output: STRING_32
        do
            create proc.make

            -- Execute command and get output
            output := proc.output_of_command ("cmd /c dir")
            print (output)

            -- Check result
            if proc.was_successful then
                print ("Exit code: " + proc.last_exit_code.out + "%N")
            else
                if attached proc.last_error as err then
                    print ("Error: " + err + "%N")
                end
            end

            -- Execute in specific directory
            output := proc.output_of_command_in_directory ("cmd /c dir", "C:\Windows")
            print (output)

            -- Check if executable exists in PATH
            if proc.file_exists_in_path ("git.exe") then
                print ("Git is installed%N")
            end

            -- Show process window (default is hidden)
            proc.set_show_window (True)
            proc.execute ("notepad.exe")
        end

end
```

---

## API Reference

### SIMPLE_PROCESS Class

#### Creation

```eiffel
make
    -- Initialize process executor.
```

#### Execution

```eiffel
execute (a_command: READABLE_STRING_GENERAL)
    -- Execute `a_command' and capture output.

execute_in_directory (a_command: READABLE_STRING_GENERAL; a_directory: detachable READABLE_STRING_GENERAL)
    -- Execute `a_command' in `a_directory' and capture output.

output_of_command (a_command: READABLE_STRING_GENERAL): STRING_32
    -- Execute `a_command' and return output.

output_of_command_in_directory (a_command: READABLE_STRING_GENERAL; a_directory: READABLE_STRING_GENERAL): STRING_32
    -- Execute `a_command' in `a_directory' and return output.
```

#### Results

```eiffel
last_output: detachable STRING_32
    -- Output from last command execution.

last_exit_code: INTEGER
    -- Exit code from last command execution.

last_error: detachable STRING_32
    -- Error message if execution failed.

was_successful: BOOLEAN
    -- Was last execution successful?
```

`last_output` is the child's output decoded as UTF-8. A byte that starts no
well-formed UTF-8 sequence reads as its Latin-1 character, as every byte did
before 1.1.0, and NUL is dropped. `last_output_bytes: detachable STRING_8`
holds the raw bytes.

#### Execution with input (1.1.0)

```eiffel
execute_with_input (a_command, a_input: READABLE_STRING_GENERAL)
    -- Run `a_command' with `a_input' on its stdin as UTF-8, then EOF.

execute_with_input_bytes (a_command: READABLE_STRING_GENERAL; a_input: READABLE_STRING_8)
    -- The same with bytes, exactly as they are.

output_of_command_with_input (a_command, a_input: READABLE_STRING_GENERAL): STRING_32
    -- Run it and return its output.
```

Input and output of any size flow at once without deadlock.

### SIMPLE_PIPED_PROCESS Class (1.1.0)

A child with stdin, stdout and stderr piped, for a conversation:

```eiffel
child: SIMPLE_PIPED_PROCESS
create child.make
child.start ("helper.exe")
if child.is_started then
    child.write_line ({STRING_32} "{%"id%":1}")    -- UTF-8 + LF
    child.read_line (5_000)                          -- wait up to 5 s
    if attached child.last_line as reply then ... end
    child.close_input                                -- child reads EOF
    child.wait_for_exit (5_000)
    child.close
end
```

Also `write_bytes`, `write_text`, `receive_output`, `await_output`,
`await_output_end`, `pending_output` / `pending_error` (raw bytes) and their
`_text` forms, `set_merge_error_output (False)` to keep stderr out of a
protocol on stdout, `kill`, `exit_code`. Each output stream is drained by its
own C thread from the moment the child starts, so a write never deadlocks
against the child's output. Windows only.

#### Settings

```eiffel
show_window: BOOLEAN
    -- Show process window during execution?

set_show_window (a_value: BOOLEAN)
    -- Set whether to show process window.

inherits_standard_input: BOOLEAN
set_inherits_standard_input (a_value: BOOLEAN)
    -- Hand the child this process's own stdin (1.1.0). Default False:
    -- the child's stdin is empty, so a read sees end of file at once.

output_limit: INTEGER
set_output_limit (a_bytes: INTEGER)
was_output_truncated: BOOLEAN
    -- Cap the output kept (1.1.0). Default 0: keep everything (before
    -- 1.1.0 output was cut at 1 MB without a word).
```

Commands, directories and `has_command` names may hold any characters
(CreateProcessW / SearchPathW, 1.1.0).

#### Query

```eiffel
file_exists_in_path (a_filename: READABLE_STRING_GENERAL): BOOLEAN
    -- Does `a_filename' exist in system PATH?
```

---

## Building & Testing

### Build Library

```bash
cd simple_process
ec -config simple_process.ecf -target simple_process -c_compile
```

### Run Tests

```bash
/d/prod/ec.sh test -config simple_process.ecf -target simple_process_echo    # the test child, first
/d/prod/ec.sh test -config simple_process.ecf -target simple_process_tests
./EIFGENs/simple_process_tests/F_code/simple_process.exe
```

**Test Results:** 41 tests passing, including 1000/1000 Hebrew-and-Greek
lines intact through every capture path and 1.5 MB each way through stdin
and stdout

### The freeze assault (SCOOP)

```bash
/d/prod/ec.sh test -config simple_process.ecf -target simple_process_scoop_tests
./EIFGENs/simple_process_scoop_tests/F_code/simple_process.exe
```

Seven tests on two processors. A real three-second child runs through
`SIMPLE_PROCESS.execute`, `SIMPLE_ASYNC_PROCESS.wait`,
`SIMPLE_PROCESS.execute_with_input` and `SIMPLE_PIPED_PROCESS.read_line` on its own
processor while the root does nothing but allocate against a growing live set;
the root's worst single allocation must stay under 500 ms. Unmarked it was
3,166 ms and 3,053 ms; marked it is 4 ms and 4 ms. Three companion probes hold
the law itself - the same wait as an Eiffel sleep, as an unmarked C call, and
as the same C call marked `blocking`. Every burst forces a full collection
(1.1.0), so the unmarked probe stops the root every time (3,016 ms) instead of
only when the allocator happens to collect.

Tests cover:
- Command execution
- Output capture
- Exit code retrieval
- Directory execution
- PATH checking
- Window visibility settings
- Error handling

---

## Project Structure

```
simple_process/
├── Clib/
│   └── simple_process_pipe.h   # All the C, header-only (static functions, no file-scope data)
├── src/                        # Eiffel source
│   ├── simple_process.e        # Run a command, capture its output
│   ├── simple_async_process.e  # Start, poll, read, kill
│   ├── simple_piped_process.e  # Talk to a child over stdin/stdout
│   ├── simple_process_utf_8.e  # The UTF-8 codec for pipe bytes
│   └── simple_process_helper.e # Legacy helper class
├── testing/                    # Test suite
│   ├── test_app.e              # Test runner
│   ├── test_piped_process.e    # 1.1.0 tests
│   ├── echo/                   # sp_echo_child.exe, the test child
│   └── scoop/                  # The freeze assault
├── simple_process.ecf          # Library configuration
├── README.md                   # This file
└── LICENSE                     # MIT License
```

---

## Migration from Previous Version

If you were using the previous version that depended on the EiffelStudio process library:

### Old (Thread-dependent)
```eiffel
-- Required thread concurrency mode
-- Used PROCESS_FACTORY and BASE_PROCESS
```

### New (SCOOP-compatible)
```eiffel
-- Uses direct Win32 API calls
-- No thread dependencies
-- Cleaner, simpler API
local
    proc: SIMPLE_PROCESS
do
    create proc.make
    proc.execute ("my_command")
end
```

---

## Dependencies

- **Windows OS** - Process API is Windows-specific
- **EiffelStudio 23.09+** - Development environment
- **Visual Studio C++ Build Tools** - For compiling C wrapper

**No EiffelStudio process library dependency** - This library uses its own C wrapper for all process operations.

---

## SCOOP Compatibility

SIMPLE_PROCESS is fully SCOOP-compatible. The C wrapper handles all Win32 API calls synchronously without threading dependencies, making it safe for use in concurrent Eiffel applications.

This is a key improvement over the previous version which required thread concurrency mode due to its dependency on the EiffelStudio process library.

**And a running child never freezes the others.** Every external here that waits - since 1.1.0 those of `SIMPLE_PIPED_PROCESS` (start, write, the waits for output and exit, joining the pump threads, every call that takes the pumps' lock) and `SIMPLE_PROCESS.c_file_in_path`; in 1.0.1 `c_sp_execute_command`, `c_sp_file_in_path`, `c_sp_start_async`, `c_sp_wait_timeout`, `c_sp_read_output` - is declared `external "C blocking inline ..."`. ISE's collector stops every thread of the system before it collects, and a thread inside an *unmarked* external cannot be seen or stopped, so the collection waits for it - and every other processor waits with it, at its very next allocation. `sp_execute_command` waits on the child with `INFINITE`, so before 1.0.1 a two-minute `claude -p` stopped the whole program for two minutes (simple_chat, 2026-09-02). Marked, the runtime knows the thread has left Eiffel and collects without it. The struct-field readers and the deallocators are left unmarked on purpose: none of them can wait on anything, and a marker costs a runtime transition on every call.

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Contact

- **Author:** Larry Rix
- **Repository:** https://github.com/simple-eiffel/simple_process
- **Issues:** https://github.com/simple-eiffel/simple_process/issues

---

Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.
