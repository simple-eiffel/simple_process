# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Testing config updates, AutoTest fixes, .gitignore cleanup
- Migrate to simple_testing library
- Add SCOOP-compatible C wrapper (no more Eiffel process dependency)
- Add GitHub Pages documentation
- Update ref docs paths in roadmap
- Add documentation and .gitignore
- init
- first commit

## [1.1.0] - 2026-10-08

Defect D14 from the simple_bible D-014 debate (fork 03, F3-C stdio spike):
simple_process could not write to a child's stdin, and it corrupted every
non-ASCII character a child wrote (Hebrew intact as shipped: 0/1000).

### Added
- **`SIMPLE_PIPED_PROCESS`**: a child with stdin, stdout and stderr all piped.
  `start` / `start_in_directory` (CreateProcessW: the command line and
  directory may hold any characters), `write_bytes`, `write_text`,
  `write_line` (UTF-8), `close_input` (the child reads EOF),
  `receive_output`, `await_output`, `await_output_end`, `read_line` with a
  timeout, `pending_output` / `pending_error` (raw bytes) and their `_text`
  forms, `wait_for_exit`, `kill`, `close`. `merge_error_output` (default
  True) or a separate `pending_error`, so diagnostics cannot corrupt a
  protocol on stdout.
- **No pipe deadlock.** From the moment the child starts, each of its output
  streams is drained by its own C thread into a growing C-heap buffer, so a
  write of any size completes while the child keeps reading. Proven with
  1.5 MB each way, and against a child that writes 1 MB before it reads a
  byte while the parent writes 1 MB before it reads one.
- **`SIMPLE_PROCESS.execute_with_input`** (text as UTF-8),
  **`execute_with_input_bytes`** (bytes as they are), their `_in_directory`
  forms, and **`output_of_command_with_input`**: run a command with this
  input and capture its output, built on `SIMPLE_PIPED_PROCESS`.
- **`SIMPLE_PROCESS_UTF_8`**: the codec (`text`, `bytes`,
  `sequence_length`, `unfinished_tail_count`).
- **Raw bytes**: `SIMPLE_PROCESS.last_output_bytes`,
  `SIMPLE_ASYNC_PROCESS.accumulated_bytes`.
- The child inherits only its own three pipe ends
  (`PROC_THREAD_ATTRIBUTE_HANDLE_LIST`, resolved at run time because ISE
  compiles with `_WIN32_WINNT=0x0500`), so a child another processor starts
  at the same moment can never hold this one's output open.
- Test helper target `simple_process_echo` (`sp_echo_child.exe`, byte-exact
  ReadFile/WriteFile echo with exit, stderr, sleep, flood and cat modes). Build
  it before running `simple_process_tests`.

### Changed (behavior dependents may notice)
- **`last_output` (and `SIMPLE_PROCESS_HELPER.output_of_command`,
  `SIMPLE_ASYNC_PROCESS.read_available_output` / `accumulated_output`) are now
  UTF-8 decoded.** Before, each byte became one character 0-255, so UTF-8
  text arrived as mojibake. A byte that starts no well-formed UTF-8 sequence
  (RFC 3629: no overlongs, no surrogates, nothing above U+10FFFF) still reads
  as its Latin-1 character, exactly as before, and NUL is still dropped, so
  ASCII and ANSI/OEM code-page output read as they always did. The old form
  is `last_output_bytes` widened to STRING_32.
  - A client that worked around the old behavior by narrowing `last_output`
    to STRING_8 and UTF-8 decoding it again now double-decodes when the text
    holds characters 128-255 and none above 255 (it is a no-op otherwise).
    Known: `simple_ai_client` `AI_CLIENT.decode_process_bytes` and
    `OLLAMA_EMBEDDING_CLIENT.decode_process_bytes` should become the
    identity, or read `last_output_bytes`.
  - A client that calls `last_output.to_string_8` now violates its
    precondition when the child writes a character above U+00FF. Known:
    `simple_code` `SC_COMPILER` (`last_output := l_out.to_string_8`).
- `SIMPLE_ASYNC_PROCESS.read_available_output` holds back the first 1-3
  bytes of a character whose remaining bytes have not arrived yet, while the
  child runs; they come out with the next read (or at `close`).

### Fixed
- **D14.3 audit, the `blocking` marker.** Every waiting external of 1.0.1 was
  already marked; nothing remained. Every new external that waits or takes
  the pump threads' lock is `C blocking` (`c_start`, `c_write`,
  `c_close_input`, `c_await`, `c_wait_exit`, `c_close`, `c_available`,
  `c_take`, `c_drained`, `c_lost`); the unmarked ones never wait (field
  reads, a 0 ms WaitForSingleObject, TerminateProcess). The 423 ms stall the
  F3-C spike measured was its own deliberately unmarked control
  (`F3C_PIPE_CHILD.c_read_unmarked`), not this library.
- **The freeze assault's control could not fail.** Test 2 ("an unmarked C
  call stops the allocator") failed on the 1.1.0 baseline: after test 1 grew
  the heap, no collection ran in its window and an unmarked 3 s wait cost the
  root 2 ms. Each burst now forces `{MEMORY}.full_collect`: unmarked 3016 ms,
  marked 2 ms.
- Two new assault tests, red then green: `execute_with_input` and
  `SIMPLE_PIPED_PROCESS.read_line` on a three-second child. With `c_await`
  unmarked on purpose the root's worst allocation was 3066 ms and 3053 ms;
  marked, 5 ms and 4 ms.

### Evidence
- `simple_process_tests` 34/34 (17 new): 1000/1000 Hebrew-and-Greek lines
  intact through `execute`, through `SIMPLE_ASYNC_PROCESS` read in chunks
  that ended inside a character, through `execute_with_input`, and as 1000
  request/reply lines over one `SIMPLE_PIPED_PROCESS`.
- `simple_process_scoop_tests` 7/7.
- The F3-C spike re-run against 1.1.0: "Hebrew intact AS SHIPPED" 1000/1000
  (was 0/1000).

### Not changed
- Plain `execute` still runs the child with this process's own stdin, caps
  captured output at 1 MB, and passes the command through `to_string_8`
  (CreateProcessA): a command with characters above U+00FF violates that
  precondition. `execute_with_input` has none of the three limits.
- `SIMPLE_PIPED_PROCESS` is Windows only; elsewhere `start` fails with a
  `last_error` saying so.

[1.1.0]: https://github.com/simple-eiffel/simple_process/releases/tag/v1.1.0

## [1.0.1] - 2026-09-02

### Fixed
- **Every external that waits on a child process is now marked `blocking`.**
  `SIMPLE_PROCESS.c_sp_execute_command` - the one call that runs a whole child
  process - was declared `external "C inline use "simple_process.h""` with no
  `blocking` marker. ISE's garbage collector stops every thread of the system
  before it collects, and a thread inside an unmarked external is where the
  runtime can neither see it nor stop it: the collection waits for that call to
  return, and every other processor waits with it, at its very next allocation.
  A library whose whole purpose is to wait for a child therefore stopped the
  entire program for the length of every command.

  It was the worst case of the shape. `sp_execute_command` does CreateProcess,
  a full drain of the child's stdout pipe, and then
  `WaitForSingleObject(pi.hProcess, INFINITE)`. There is no timeout on that
  wait at all. simple_chat's server runs `claude -p` through it and a bot can
  think for two minutes: one question, and the chat server froze for every user
  in it.

  Five externals are now marked:

  | External | What it waits on |
  |---|---|
  | `SIMPLE_PROCESS.c_sp_execute_command` | a child's whole life - `WaitForSingleObject(..., INFINITE)` |
  | `SIMPLE_PROCESS.c_sp_file_in_path` | `SearchPathA` over every PATH entry (POSIX: `system ("command -v ...")`) |
  | `SIMPLE_ASYNC_PROCESS.c_sp_start_async` | CreateProcess - image load, and any AV filter driver in front of it |
  | `SIMPLE_ASYNC_PROCESS.c_sp_wait_timeout` | `WaitForSingleObject(..., timeout)` - bounded is not short |
  | `SIMPLE_ASYNC_PROCESS.c_sp_read_output` | a `PeekNamedPipe`-guarded `ReadFile` loop |

  It is safe to mark all five because nothing the C layer touches is
  Eiffel-collected memory. Every string crossing the boundary is a `C_STRING`,
  whose buffer `MANAGED_POINTER.make` allocates with `memory_calloc` on the C
  heap; the process handles are malloc'd structures this library owns; results
  are malloc'd and read only after the call returns. The one out parameter,
  `c_sp_read_output`'s `$a_len`, is the address of a LOCAL `INTEGER` of its sole
  caller `read_available_output` - it lives in that routine's own C stack frame,
  never in an object the collector may move.

  Deliberately left unmarked: the struct-field readers (`c_sp_result_success`,
  `c_sp_result_exit_code`, `c_sp_result_output`, `c_sp_result_output_length`,
  `c_sp_result_error`, `c_sp_async_started`, `c_sp_async_error`,
  `c_sp_get_pid`), the handle calls that cannot wait (`c_sp_is_running` and
  `c_sp_get_exit_code`, one `GetExitCodeProcess`; `c_sp_kill`, one asynchronous
  `TerminateProcess`; `c_sp_async_close`, three `CloseHandle`s and a `free`),
  and the two deallocators (`c_sp_free_result`, `c_free`). Each is a
  microsecond of bookkeeping, and a marker costs a runtime transition on every
  call.

  HOW IT WAS FOUND. Larry's simple_chat window froze on 2026-09-02 - 13 stalls
  and 211 seconds of frozen window in one 20-minute session. That hunt ended in
  simple_winhttp (see its CHANGELOG 0.1.1) and proved the mechanism; this
  library was audited against the same law the same day and was found carrying
  five of them, including an unbounded one.

  MEASURED, on the same machine, same duration, nothing else running: a
  processor asleep 3,000 ms in `EXECUTION_ENVIRONMENT.sleep` (which EiffelBase
  itself marks `C blocking`) cost another processor's worst allocation 3 ms; a
  processor inside a 3,000 ms UNMARKED C call cost it 2,896 ms.

### Added
- `simple_process_scoop_tests` - a SCOOP test target carrying the vector test
  that would have caught this. `PROCESS_CALLER` drives the real
  `SIMPLE_PROCESS` and `SIMPLE_ASYNC_PROCESS` from its own processor against a
  real child that lives three seconds; the root does nothing but allocate, with
  a live set that keeps growing so the collector always has work, and records
  its worst single allocation. `BLOCKING_PROBE` holds the law itself - the same
  wait taken three ways (an Eiffel sleep, an unmarked C call, the same C call
  marked `blocking`).

  RED (unmarked): the root's worst allocation was **3,166 ms** against
  `SIMPLE_PROCESS.execute` and **3,053 ms** against `SIMPLE_ASYNC_PROCESS.wait`.
  3 passed, 2 failed.
  GREEN (1.0.1): **4 ms** and **4 ms**, with the children still taking their
  full 6,356 ms and 6,371 ms in the library. 5 passed, 0 failed. The assertion
  is bounded at 500 ms, with margin on both sides.

  The existing suite is 17 passed / 0 failed either way.

### Changed
- `SIMPLE_PROCESS` and `SIMPLE_ASYNC_PROCESS` class notes and the README now
  state the guarantee: a child process running here never stops another
  processor's allocator.
- `package.json` version corrected to match the CHANGELOG (it had been left at
  `0.1.0` while the CHANGELOG and README released `1.0.0`).

[1.0.1]: https://github.com/simple-eiffel/simple_process/releases/tag/v1.0.1

## [1.0.0] - 2025-12-08

### Added
- Initial release
- Core functionality implemented
- Test suite with comprehensive coverage
- Documentation and examples

[Unreleased]: https://github.com/simple-eiffel/simple_process/compare/v1.1.0...HEAD
[1.0.0]: https://github.com/simple-eiffel/simple_process/releases/tag/v1.0.0
