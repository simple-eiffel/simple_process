note
	description: "[
		SCOOP-compatible process execution.
		Uses direct Win32 API calls via C wrapper - no thread dependencies.
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
		end

feature -- Access

	last_output,
	output,
	stdout,
	result_text,
	captured_output: detachable STRING_32
			-- Output from last command execution

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
		end

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
			l_managed: MANAGED_POINTER
		do
			-- Reset state
			last_output := Void
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
						create l_managed.share_from_pointer (l_output_ptr, l_output_len)
						last_output := utf8_to_string_32 (l_managed, l_output_len)
					else
						create last_output.make_empty
					end
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
		end

feature {NONE} -- String conversion

	utf8_to_string_32 (a_data: MANAGED_POINTER; a_length: INTEGER): STRING_32
			-- Convert UTF-8 data to STRING_32.
		local
			i: INTEGER
			c: NATURAL_8
		do
			create Result.make (a_length)
			from
				i := 0
			until
				i >= a_length
			loop
				c := a_data.read_natural_8 (i)
				if c /= 0 then
					Result.append_character (c.to_character_32)
				end
				i := i + 1
			end
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
		external
			"C inline use %"simple_process.h%""
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
		external
			"C inline use %"simple_process.h%""
		alias
			"return sp_file_in_path((const char*)$a_filename);"
		end

end
