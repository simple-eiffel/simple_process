note
	description: "[
		Simple process execution helper.
		Provides features for executing shell commands and capturing output.
		Uses SIMPLE_PROCESS for SCOOP-compatible execution.
	]"
	author: "Larry Rix"
	date: "$Date$"
	revision: "$Revision$"

class
	SIMPLE_PROCESS_HELPER

feature -- Status Report

	has_file_in_path,
	is_in_path,
	command_exists,
	has_command (a_name: STRING): BOOLEAN
			-- Does `a_name' exist in the system PATH?
		local
			l_process: SIMPLE_PROCESS
		do
			create l_process.make
			Result := l_process.file_exists_in_path (a_name)
		end

feature -- Basic Operations

	last_error: INTEGER
			-- Last error code from process execution

	output_of_command,
	run_and_capture,
	exec_output,
	shell_output,
	capture_output,
	command_output (a_command_line: READABLE_STRING_32; a_directory: detachable READABLE_STRING_32): STRING_32
			-- Execute `a_command_line' in `a_directory' and return captured output.
			-- If `a_directory' is Void, uses current directory.
		require
			cmd_not_empty: not a_command_line.is_empty
			dir_not_empty: attached a_directory as al_dir implies not al_dir.is_empty
		local
			l_process: SIMPLE_PROCESS
		do
			create l_process.make
			l_process.set_show_window (show_process)

			if attached a_directory as al_dir then
				Result := l_process.output_of_command_in_directory (a_command_line, al_dir)
			else
				Result := l_process.output_of_command (a_command_line)
			end

			last_error := l_process.last_exit_code

			if not l_process.was_successful then
				if attached l_process.last_error as l_err then
					last_error_result := l_err.to_string_8
				end
			end

			-- Remove carriage returns for consistency
			Result.prune_all ('%R')
		end

	show_process: BOOLEAN
			-- Show process window during `output_of_command'?

	set_show_process (a_value: like show_process)
			-- Set `show_process' to `a_value'.
		do
			show_process := a_value
		ensure
			set: show_process = a_value
		end

	launch_fail_handler (a_result: STRING)
			-- Handle launch failure with `a_result' message.
		do
			last_error_result := a_result
		end

	last_error_result: detachable STRING
			-- Last error message from process execution

feature -- Status Report: Wait for Exit

	is_not_wait_for_exit: BOOLEAN
			-- Do not wait for process to exit?
			-- Note: Current implementation always waits (synchronous).

	is_wait_for_exit: BOOLEAN
			-- Wait for process to exit?
		do
			Result := not is_not_wait_for_exit
		end

	set_do_not_wait_for_exit
			-- Set to not wait for process exit.
			-- Note: This is kept for API compatibility but has no effect.
		do
			is_not_wait_for_exit := True
		end

	set_wait_for_exit
			-- Set to wait for process exit.
		do
			is_not_wait_for_exit := False
		end

feature -- Implementation: Constants

	Dos_where_not_found_message: STRING = "INFO: Could not find files for the given pattern(s).%N"
			-- Windows 'where' command not found message

note
	copyright: "Copyright (c) 2024-2025, Larry Rix"
	license: "MIT License"
	source: "[
		SIMPLE_PROCESS - SCOOP-compatible process execution library
		Uses direct Win32 API calls without thread dependencies
	]"

end
