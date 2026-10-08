note
	description: "[
		SCOOP-compatible process execution: run a command, wait for it,
		and capture what it wrote.

		THE GUARANTEE (1.0.1). A child process running here never stops
		another processor's allocator. Every external that waits is
		declared `external "C blocking inline"'. ISE's garbage collector
		stops every thread of the system before it collects, and the
		marker is how a thread that is about to sit in the kernel hands
		itself to the runtime first. Without it the collection waits for
		the call to return, and every other processor waits with it at
		its very next allocation - which is exactly what froze
		simple_chat's window on 2026-09-02. Since 1.1.0 every execution
		runs through SIMPLE_PIPED_PROCESS, whose waiting externals are
		all marked; `c_file_in_path' is this class's own. The assault
		that proves it lives in testing/scoop/.

		OUTPUT IS UTF-8 (1.1.0). `last_output' decodes the child's bytes
		as UTF-8 (SIMPLE_PROCESS_UTF_8); before 1.1.0 every byte became
		one character, so Hebrew, Greek or any non-ASCII text came back
		as mojibake. A byte that starts no well-formed UTF-8 sequence
		still reads as its Latin-1 character, exactly as before, and NUL
		is still dropped. `last_output_bytes' keeps the raw bytes. stderr
		is captured with stdout, as always.

		OUTPUT IS NOT CUT (1.1.0). Before 1.1.0 capture stopped silently
		at 1 MB. Now everything is kept unless `set_output_limit' asks for
		a cap, and then `was_output_truncated' reports the cut. Past the
		cap the child's output is still drained, so it never blocks.

		STDIN (1.1.0). `execute' gives the child an empty stdin: a child
		that reads it sees end of file at once. Before 1.1.0 the child
		was handed this process's own stdin, so a child that read it
		hung, or took keystrokes from this program's console.
		`set_inherits_standard_input (True)' restores that.
		`execute_with_input' gives the child text (UTF-8) or bytes on
		its stdin instead - any size, with no pipe deadlock.

		ANY COMMAND LINE (1.1.0). Commands and directories may hold any
		characters: they reach CreateProcessW as UTF-16. Before 1.1.0 a
		character above U+00FF violated a `to_string_8' precondition.

		Windows only: elsewhere every execution fails with a
		`last_error' that says so.
	]"
	author: "Larry Rix"
	date: "$Date$"
	revision: "$Revision$"

class
	SIMPLE_PROCESS

create
	make

feature {NONE} -- Initialization

	make
			-- Initialize process executor.
		do
			show_window := False
			execution_count_impl := 0
		ensure
			window_hidden: not show_window
			no_executions: execution_count = 0
			stdin_empty: not inherits_standard_input
			no_limit: output_limit = 0
		end

feature -- Access

	last_output,
	output,
	stdout,
	result_text,
	captured_output: detachable STRING_32
			-- Output from last command execution, decoded as UTF-8.

	last_output_bytes: detachable STRING_8
			-- The raw bytes behind `last_output', as the child wrote them.

	last_exit_code,
	exit_code,
	return_code,
	status_code: INTEGER
			-- Exit code from last command execution

	last_error,
	error_message,
	stderr,
	failure_reason: detachable STRING_32
			-- Error message if execution failed

	was_successful,
	succeeded,
	ok,
	passed,
	completed_ok: BOOLEAN
			-- Was last execution successful?

	was_output_truncated: BOOLEAN
			-- Did the last execution's output pass `output_limit', so the
			-- rest was dropped?

feature -- Settings

	show_window: BOOLEAN
			-- Show process window during execution? (A console child never
			-- gets a console window either way, as before 1.1.0.)

	set_show_window (a_value: BOOLEAN)
			-- Set whether to show process window.
		do
			show_window := a_value
		ensure
			set: show_window = a_value
			execution_count_unchanged: execution_count = old execution_count
		end

	inherits_standard_input: BOOLEAN
			-- Does `execute' hand the child this process's own stdin? Default
			-- False: the child's stdin is empty, so a read sees end of file.

	set_inherits_standard_input (a_value: BOOLEAN)
			-- Set `inherits_standard_input' to `a_value'.
		do
			inherits_standard_input := a_value
		ensure
			set: inherits_standard_input = a_value
			execution_count_unchanged: execution_count = old execution_count
		end

	output_limit: INTEGER
			-- Most bytes of output kept per execution; 0 (the default) keeps
			-- everything.

	set_output_limit (a_bytes: INTEGER)
			-- Keep at most `a_bytes' of output (0: no limit).
		require
			non_negative: a_bytes >= 0
		do
			output_limit := a_bytes
		ensure
			set: output_limit = a_bytes
			execution_count_unchanged: execution_count = old execution_count
		end

feature -- Model Queries

	execution_count: INTEGER
			-- Number of commands executed since creation.
			-- Model query for tracking execution history.
		do
			Result := execution_count_impl
		ensure
			non_negative: Result >= 0
		end

	has_executed: BOOLEAN
			-- Has at least one command been executed?
		do
			Result := execution_count > 0
		ensure
			definition: Result = (execution_count > 0)
		end

	last_command: detachable READABLE_STRING_GENERAL
			-- Last command that was executed (for model purposes).

feature -- Execution

	execute,
	run,
	run_command,
	shell,
	exec,
	spawn,
	launch (a_command: READABLE_STRING_GENERAL)
			-- Execute `a_command' and capture output.
		require
			command_not_empty: not a_command.is_empty
		do
			execute_in_directory (a_command, Void)
		ensure
			execution_recorded: execution_count = old execution_count + 1
			command_recorded: attached last_command as lc and then lc.same_string (a_command)
		end

	execute_in_directory,
	run_in,
	run_in_directory,
	exec_in,
	shell_in,
	launch_in (a_command: READABLE_STRING_GENERAL; a_directory: detachable READABLE_STRING_GENERAL)
			-- Execute `a_command' in `a_directory' (Void or empty: the current
			-- one) and capture output. Waits for the child's output to end and
			-- for the child to exit, with no timeout.
		require
			command_not_empty: not a_command.is_empty
		do
			run_child (a_command, Void, a_directory)
		ensure
			execution_recorded: execution_count = old execution_count + 1
			command_recorded: attached last_command as lc and then lc.same_string (a_command)
			output_forms_agree: attached last_output implies attached last_output_bytes
		end

	output_of_command,
	run_and_capture,
	exec_output,
	shell_output,
	capture_output,
	command_output (a_command: READABLE_STRING_GENERAL): STRING_32
			-- Execute `a_command' and return output.
		require
			command_not_empty: not a_command.is_empty
		do
			execute (a_command)
			if attached last_output as l_out then
				Result := l_out
			else
				create Result.make_empty
			end
		ensure
			execution_recorded: execution_count = old execution_count + 1
			empty_on_failure: not was_successful implies Result.is_empty
		end

	output_of_command_in_directory,
	run_and_capture_in,
	exec_output_in,
	capture_output_in (a_command: READABLE_STRING_GENERAL; a_directory: READABLE_STRING_GENERAL): STRING_32
			-- Execute `a_command' in `a_directory' and return output.
		require
			command_not_empty: not a_command.is_empty
			directory_not_empty: not a_directory.is_empty
		do
			execute_in_directory (a_command, a_directory)
			if attached last_output as l_out then
				Result := l_out
			else
				create Result.make_empty
			end
		ensure
			execution_recorded: execution_count = old execution_count + 1
			empty_on_failure: not was_successful implies Result.is_empty
		end

feature -- Execution with input

	execute_with_input (a_command, a_input: READABLE_STRING_GENERAL)
			-- Execute `a_command' with `a_input' on its stdin, as UTF-8, then
			-- end of file; capture its output as `execute' does. (A STRING_8
			-- `a_input' is taken as characters: use `execute_with_input_bytes'
			-- for bytes.)
		require
			command_not_empty: not a_command.is_empty
		do
			run_child (a_command, utf_8.bytes (a_input), Void)
		ensure
			execution_recorded: execution_count = old execution_count + 1
			command_recorded: attached last_command as lc and then lc.same_string (a_command)
			output_forms_agree: attached last_output implies attached last_output_bytes
		end

	execute_with_input_in_directory (a_command, a_input: READABLE_STRING_GENERAL; a_directory: detachable READABLE_STRING_GENERAL)
			-- `execute_with_input' in `a_directory' (Void: the current one).
		require
			command_not_empty: not a_command.is_empty
			directory_not_empty: attached a_directory as al_dir implies not al_dir.is_empty
		do
			run_child (a_command, utf_8.bytes (a_input), a_directory)
		ensure
			execution_recorded: execution_count = old execution_count + 1
			command_recorded: attached last_command as lc and then lc.same_string (a_command)
			output_forms_agree: attached last_output implies attached last_output_bytes
		end

	execute_with_input_bytes (a_command: READABLE_STRING_GENERAL; a_input: READABLE_STRING_8)
			-- Execute `a_command' with the bytes `a_input' on its stdin, exactly
			-- as they are, then end of file; capture its output.
		require
			command_not_empty: not a_command.is_empty
		do
			run_child (a_command, a_input, Void)
		ensure
			execution_recorded: execution_count = old execution_count + 1
			command_recorded: attached last_command as lc and then lc.same_string (a_command)
			output_forms_agree: attached last_output implies attached last_output_bytes
		end

	execute_with_input_bytes_in_directory (a_command: READABLE_STRING_GENERAL; a_input: READABLE_STRING_8; a_directory: detachable READABLE_STRING_GENERAL)
			-- `execute_with_input_bytes' in `a_directory' (Void: the current one).
			-- Input and output of any size flow at once without deadlock.
			-- Input the child never reads is discarded when it exits.
		require
			command_not_empty: not a_command.is_empty
			directory_not_empty: attached a_directory as al_dir implies not al_dir.is_empty
		do
			run_child (a_command, a_input, a_directory)
		ensure
			execution_recorded: execution_count = old execution_count + 1
			command_recorded: attached last_command as lc and then lc.same_string (a_command)
			output_forms_agree: attached last_output implies attached last_output_bytes
		end

	output_of_command_with_input (a_command, a_input: READABLE_STRING_GENERAL): STRING_32
			-- Execute `a_command' with `a_input' on its stdin (UTF-8) and return
			-- its output.
		require
			command_not_empty: not a_command.is_empty
		do
			execute_with_input (a_command, a_input)
			if attached last_output as l_out then
				Result := l_out
			else
				create Result.make_empty
			end
		ensure
			execution_recorded: execution_count = old execution_count + 1
			empty_on_failure: not was_successful implies Result.is_empty
		end

feature -- Query

	file_exists_in_path,
	is_in_path,
	command_exists,
	has_command (a_filename: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_filename' exist in system PATH? (".exe" is tried when it
			-- has no extension; any characters, since 1.1.0.)
		require
			filename_not_empty: not a_filename.is_empty
		local
			l_name: NATIVE_STRING
		do
			create l_name.make (a_filename)
			Result := c_file_in_path (l_name.item) /= 0
		ensure
			execution_unchanged: execution_count = old execution_count
		end

feature {NONE} -- Implementation

	run_child (a_command: READABLE_STRING_GENERAL; a_input: detachable READABLE_STRING_8; a_directory: detachable READABLE_STRING_GENERAL)
			-- Run `a_command' in `a_directory' (Void or empty: the current one)
			-- with `a_input' on its stdin, or, when Void, an empty stdin (or this
			-- process's own, when `inherits_standard_input'); wait for its output
			-- to end and for it to exit; record the result.
		require
			command_not_empty: not a_command.is_empty
		local
			l_child: SIMPLE_PIPED_PROCESS
			l_directory: detachable READABLE_STRING_GENERAL
		do
			last_output := Void
			last_output_bytes := Void
			last_error := Void
			last_exit_code := 0
			was_successful := False
			was_output_truncated := False

			if attached a_directory as al_dir and then not al_dir.is_empty then
				l_directory := al_dir
			end
			create l_child.make
			l_child.set_show_window (show_window)
			l_child.set_suppresses_console (True)
			l_child.set_output_limit (output_limit)
			l_child.set_inherits_standard_input (a_input = Void and inherits_standard_input)
			l_child.start_in_directory (a_command, l_directory)
			if l_child.is_started then
				if l_child.is_input_open then
					if attached a_input as al_input then
						l_child.write_bytes (al_input)
					end
					l_child.close_input
				end
				l_child.await_output_end ({SIMPLE_PIPED_PROCESS}.Infinite)
				l_child.wait_for_exit ({SIMPLE_PIPED_PROCESS}.Infinite)
				l_child.close
				last_exit_code := l_child.exit_code
				was_output_truncated := l_child.was_output_truncated
				last_output_bytes := l_child.pending_output
				last_output := utf_8.text (l_child.pending_output)
				was_successful := True
			elseif attached l_child.last_error as l_reason then
				last_error := l_reason
			else
				last_error := {STRING_32} "Failed to execute command"
			end

			last_command := a_command
			execution_count_impl := execution_count_impl + 1
		ensure
			execution_recorded: execution_count = old execution_count + 1
			command_recorded: attached last_command as lc and then lc.same_string (a_command)
			success_has_output: was_successful implies attached last_output
			failure_has_reason: not was_successful implies attached last_error
			cut_only_with_limit: was_output_truncated implies output_limit > 0
		end

	utf_8: SIMPLE_PROCESS_UTF_8
			-- The codec.
		once
			create Result
		end

feature {NONE} -- Model Implementation

	execution_count_impl: INTEGER
			-- Internal counter for execution tracking.

feature {NONE} -- C externals

	c_file_in_path (a_filename: POINTER): INTEGER
			-- Is `a_filename' (UTF-16) on the search path?
			--
			-- BLOCKING. SearchPathW walks the application directory, the system
			-- and Windows directories and then every entry of PATH; one dead
			-- network share on PATH costs seconds.
			--
			-- Safe to mark: the one argument is a NATIVE_STRING buffer on the C heap.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"return spp_file_in_path((void*)$a_filename);"
		end

invariant
	execution_count_non_negative: execution_count >= 0
	has_executed_consistency: has_executed = (execution_count > 0)
	success_state_consistency: was_successful implies last_output /= Void
	output_forms_agree: (last_output = Void) = (last_output_bytes = Void)
	limit_non_negative: output_limit >= 0

end
