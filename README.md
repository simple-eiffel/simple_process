<p align="center">
  <img src="https://raw.githubusercontent.com/simple-eiffel/.github/main/profile/assets/logo.png" alt="simple_ library logo" width="400">
</p>

# SIMPLE_PROCESS

**[Documentation](https://simple-eiffel.github.io/simple_process/)**

### Process Execution Library for Eiffel

[![Language](https://img.shields.io/badge/language-Eiffel-blue.svg)](https://www.eiffel.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-blue.svg)]()
[![SCOOP](https://img.shields.io/badge/SCOOP-compatible-orange.svg)]()
[![Design by Contract](https://img.shields.io/badge/DbC-enforced-orange.svg)]()
[![Tests](https://img.shields.io/badge/tests-9%20passing-brightgreen.svg)]()

---

## Overview

SIMPLE_PROCESS provides SCOOP-compatible process execution for Eiffel applications. It wraps Win32 Process APIs through a clean C interface, enabling command execution with output capture without threading complications.

**Important:** This library has **no dependency on the EiffelStudio process library**. It uses direct Win32 API calls through a custom C wrapper, making it fully SCOOP-compatible and eliminating threading issues that existed with the previous Eiffel process library dependency.

**Developed using AI-assisted methodology:** Built interactively with Claude Opus 4.5 following rigorous Design by Contract principles.

---

## Features

### Process Operations

- **Execute Commands** - Run shell commands and capture output
- **Working Directory** - Execute in specific directories
- **Output Capture** - Get stdout as STRING_32
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

2. Compile the C library:
```bash
cd simple_process/Clib
compile.bat
```

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

#### Settings

```eiffel
show_window: BOOLEAN
    -- Show process window during execution?

set_show_window (a_value: BOOLEAN)
    -- Set whether to show process window.
```

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
ec -config simple_process.ecf -target simple_process_tests -c_compile
./EIFGENs/simple_process_tests/W_code/simple_process.exe
```

**Test Results:** 9 tests passing

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
├── Clib/                       # C wrapper library
│   ├── simple_process.h        # C header file
│   ├── simple_process.c        # C implementation
│   └── compile.bat             # Build script
├── src/                        # Eiffel source
│   ├── simple_process.e        # Main process class
│   └── simple_process_helper.e # Legacy helper class
├── testing/                    # Test suite
│   ├── application.e           # Test runner
│   └── test_simple_process.e   # Test cases
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

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Contact

- **Author:** Larry Rix
- **Repository:** https://github.com/simple-eiffel/simple_process
- **Issues:** https://github.com/simple-eiffel/simple_process/issues

---

## Acknowledgments

- Built with Claude Opus 4.5 (Anthropic)
- Uses Win32 Process APIs (Microsoft)
- Part of the simple_ library collection for Eiffel
