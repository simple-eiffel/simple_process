note
	description: "[
		SCOOP-compatible process execution.
		Uses direct Win32 API calls via C wrapper - no thread dependencies.

		THE GUARANTEE (1.0.1). A child process running here never stops
		another processor's allocator.

		Every external of this class that waits is declared
		`external "C blocking inline"': `c_sp_execute_command', which runs
		a child to completion, and `c_sp_file_in_path', which walks PATH.
		ISE's garbage collector stops every thread of the system before it
		collects, and the marker is how a thread that is about to sit in
		the kernel hands itself to the runtime first. Without it the
		collection waits for the call to return, and every other processor
		waits with it at its very next allocation - which is exactly what
		froze simple_chat's window on 2026-09-02.

		The assault that proves it lives in testing/scoop/.

		OUTPUT IS UTF-8 (1.1.0). `last_output' decodes the child's bytes as
		UTF-8 (SIMPLE_PROCESS_UTF_8); before 1.1.0 every byte became one
		character, so Hebrew, Greek or any non-ASCII text came back as
		mojibake. A byte that starts no well-formed UTF-8 sequence still
		reads as its Latin-1 character, exactly as before, and NUL is still
		dropped. `last_output_bytes' keeps the raw bytes.

		INPUT (1.1.0). `execute_with_input' runs a command with text on its
		stdin (UTF-8) and captures its output; `execute_with_input_bytes'
		takes the bytes as they are. Any size in either direction, with no
		pipe deadlock (see SIMPLE_PIPED_PROCESS, which they are built on).
		Plain `execute' still hands the child this process's own stdin.
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
		end

feature -- Access

	last_output,
	output,
	stdout,
	result_text,
	captured_output: detachable STRING_32
			-- Output from last command execution

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

feature -- Settings

	show_window: BOOLEAN
			-- Show process window during execution?

	set_show_window (a_value: BOOLEAN)
			-- Set whether to show process window.
		do
			show_window := a_value
		ensure
			set: show_window = a_value
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
			-- Execute `a_command' in `a_directory' and capture output.
		require
			command_not_empty: not a_command.is_empty
		local
			l_cmd: C_STRING
			l_dir: detachable C_STRING
			l_result: POINTER
			l_output_ptr: POINTER
			l_output_len: INTEGER
			l_error_ptr: POINTER
			l_bytes: STRING_8
		do
			-- Reset state
			last_output := Void
			last_output_bytes := Void
			last_error := Void
			last_exit_code := 0
			was_successful := False

			-- Convert strings to C
			create l_cmd.make (a_command.to_string_8)
			if attached a_directory as al_dir then
				create l_dir.make (al_dir.to_string_8)
			end

			-- Execute command
			if attached l_dir then
				l_result := c_sp_execute_command (l_cmd.item, l_dir.item, show_window.to_integer)
			else
				l_result := c_sp_execute_command (l_cmd.item, default_pointer, show_window.to_integer)
			end

			if l_result /= default_pointer then
				-- Extract results from C structure
				was_successful := c_sp_result_success (l_result) /= 0
				last_exit_code := c_sp_result_exit_code (l_result)

				if was_successful then
					l_output_ptr := c_sp_result_output (l_result)
					l_output_len := c_sp_result_output_length (l_result)
					if l_output_ptr /= default_pointer and l_output_len > 0 then
						create l_bytes.make_from_c_byte_array (l_output_ptr, l_output_len)
					else
						create l_bytes.make_empty
					end
					last_output_bytes := l_bytes
					last_output := utf_8.text (l_bytes)
				else
					l_error_ptr := c_sp_result_error (l_result)
					if l_error_ptr /= default_pointer then
						last_error := pointer_to_string (l_error_ptr)
					end
				end

				-- Free C result
				c_sp_free_result (l_result)
			else
				last_error := {STRING_32} "Failed to execute command"
			end

			-- Update model state
			last_command := a_command
			execution_count_impl := execution_count_impl + 1
		ensure
			execution_recorded: execution_count = old execution_count + 1
			command_recorded: attached last_command as lc and then lc.same_string (a_command)
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
			execute_with_input_bytes_in_directory (a_command, utf_8.bytes (a_input), Void)
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
			execute_with_input_bytes_in_directory (a_command, utf_8.bytes (a_input), a_directory)
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
			execute_with_input_bytes_in_directory (a_command, a_input, Void)
		ensure
			execution_recorded: execution_count = old execution_count + 1
			command_recorded: attached last_command as lc and then lc.same_string (a_command)
			output_forms_agree: attached last_output implies attached last_output_bytes
		end

	execute_with_input_bytes_in_directory (a_command: READABLE_STRING_GENERAL; a_input: READABLE_STRING_8; a_directory: detachable READABLE_STRING_GENERAL)
			-- `execute_with_input_bytes' in `a_directory' (Void: the current one).
			--
			-- The child's stdout and stderr come back together in
			-- `last_output', as with `execute'. Input and output of any size
			-- flow at once without deadlock. Input the child never reads is
			-- discarded when it exits. Waits for the child's output to end and
			-- for the child to exit, with no timeout - as `execute' does. The
			-- command and directory may hold any characters (CreateProcessW).
		require
			command_not_empty: not a_command.is_empty
			directory_not_empty: attached a_directory as al_dir implies not al_dir.is_empty
		local
			l_child: SIMPLE_PIPED_PROCESS
		do
			last_output := Void
			last_output_bytes := Void
			last_error := Void
			last_exit_code := 0
			was_successful := False

			create l_child.make
			l_child.set_show_window (show_window)
			l_child.start_in_directory (a_command, a_directory)
			if l_child.is_started then
				if l_child.is_input_open then
					l_child.write_bytes (a_input)
					l_child.close_input
				end
				l_child.await_output_end ({SIMPLE_PIPED_PROCESS}.Infinite)
				l_child.wait_for_exit ({SIMPLE_PIPED_PROCESS}.Infinite)
				l_child.close
				last_exit_code := l_child.exit_code
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
			output_forms_agree: attached last_output implies attached last_output_bytes
			success_has_output: was_successful implies attached last_output
			failure_has_reason: not was_successful implies attached last_error
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
			-- Does `a_filename' exist in system PATH?
		require
			filename_not_empty: not a_filename.is_empty
		local
			l_name: C_STRING
		do
			create l_name.make (a_filename.to_string_8)
			Result := c_sp_file_in_path (l_name.item) /= 0
		ensure
			execution_unchanged: execution_count = old execution_count
		end

feature {NONE} -- Model Implementation

	execution_count_impl: INTEGER
			-- Internal counter for execution tracking.

feature {NONE} -- String conversion

	utf_8: SIMPLE_PROCESS_UTF_8
			-- The codec.
		once
			create Result
		end

	pointer_to_string (a_ptr: POINTER): STRING_32
			-- Convert C string pointer to STRING_32.
		local
			l_c_string: C_STRING
		do
			create l_c_string.make_by_pointer (a_ptr)
			Result := l_c_string.string.to_string_32
		end

feature {NONE} -- C externals

	c_sp_execute_command (a_command, a_working_dir: POINTER; a_show_window: INTEGER): POINTER
			-- Execute command and return result pointer.
			--
			-- BLOCKING. This is the whole life of a child process: CreateProcess,
			-- a full drain of its stdout pipe, and then WaitForSingleObject with
			-- INFINITE. Unmarked, it held ISE's collector - and every other
			-- processor's allocator - for as long as the child lived.
			--
			-- Safe to mark: both string arguments are C_STRING buffers, which
			-- MANAGED_POINTER allocates with memory_calloc on the C heap, and the
			-- result is a malloc'd sp_result read only after the call returns. The
			-- C code touches no Eiffel-collected memory while it waits.
		external
			"C blocking inline use %"simple_process.h%""
		alias
			"return sp_execute_command((const char*)$a_command, (const char*)$a_working_dir, (int)$a_show_window);"
		end

	c_sp_free_result (a_result: POINTER)
			-- Free result structure.
		external
			"C inline use %"simple_process.h%""
		alias
			"sp_free_result((sp_result*)$a_result);"
		end

	c_sp_result_success (a_result: POINTER): INTEGER
			-- Get success flag from result.
		external
			"C inline use %"simple_process.h%""
		alias
			"return ((sp_result*)$a_result)->success;"
		end

	c_sp_result_exit_code (a_result: POINTER): INTEGER
			-- Get exit code from result.
		external
			"C inline use %"simple_process.h%""
		alias
			"return ((sp_result*)$a_result)->exit_code;"
		end

	c_sp_result_output (a_result: POINTER): POINTER
			-- Get output pointer from result.
		external
			"C inline use %"simple_process.h%""
		alias
			"return ((sp_result*)$a_result)->output;"
		end

	c_sp_result_output_length (a_result: POINTER): INTEGER
			-- Get output length from result.
		external
			"C inline use %"simple_process.h%""
		alias
			"return ((sp_result*)$a_result)->output_length;"
		end

	c_sp_result_error (a_result: POINTER): POINTER
			-- Get error message pointer from result.
		external
			"C inline use %"simple_process.h%""
		alias
			"return ((sp_result*)$a_result)->error_message;"
		end

	c_sp_file_in_path (a_filename: POINTER): INTEGER
			-- Check if file exists in PATH.
			--
			-- BLOCKING. SearchPathA walks the application directory, the system
			-- and Windows directories and then every entry of PATH; one dead
			-- network share on PATH costs seconds. On POSIX the same query runs
			-- system ("command -v ..."), which forks a whole shell.
			--
			-- Safe to mark: the one argument is a C_STRING buffer on the C heap.
		external
			"C blocking inline use %"simple_process.h%""
		alias
			"return sp_file_in_path((const char*)$a_filename);"
		end

invariant
	execution_count_non_negative: execution_count >= 0
	has_executed_consistency: has_executed = (execution_count > 0)
	success_state_consistency: was_successful implies last_output /= Void
	output_forms_agree: (last_output = Void) = (last_output_bytes = Void)

end