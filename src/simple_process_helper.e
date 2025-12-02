note
	description: "[
		Simple process execution helper.
		Provides features for executing shell commands and capturing output.
		Replaces FW_PROCESS_HELPER from framework with minimal dependencies.
	]"
	author: "Larry Rix"
	date: "$Date$"
	revision: "$Revision$"

class
	SIMPLE_PROCESS_HELPER

feature -- Status Report

	has_file_in_path (a_name: STRING): BOOLEAN
			-- Does `a_name' exist in the system PATH?
		local
			l_result: STRING_32
		do
			l_result := output_of_command ({STRING_32} "cmd /c where " + a_name, Void)
			-- When file is found, output contains the path to the file
			-- When not found, output is empty (error goes to stderr) or contains "INFO:" message
			-- So file is in path if output is not empty AND doesn't contain "INFO:"
			Result := not l_result.is_empty and then not l_result.has_substring ("INFO:")
		end

feature -- Basic Operations

	last_error: INTEGER
			-- Last error code from process execution

	output_of_command (a_command_line: READABLE_STRING_32; a_directory: detachable READABLE_STRING_32): STRING_32
			-- Execute `a_command_line' in `a_directory' and return captured output.
			-- If `a_directory' is Void, uses current directory.
		require
			cmd_not_empty: not a_command_line.is_empty
			dir_not_empty: attached a_directory as al_dir implies not al_dir.is_empty
		local
			l_process: PROCESS
			l_buffer: SPECIAL [NATURAL_8]
			l_result: STRING_32
			l_args: ARRAY [STRING_32]
			l_cmd: STRING_32
			l_list: LIST [READABLE_STRING_32]
		do
			create Result.make_empty
			l_list := a_command_line.split (' ')
			l_cmd := l_list [1]
			if l_list.count >= 2 then
				create l_args.make_filled ({STRING_32} "", 1, l_list.count - 1)
				across
					2 |..| l_list.count as ic
				loop
					l_args.put (l_list [ic.item], ic.item - 1)
				end
			end
			l_process := (create {PROCESS_FACTORY}).process_launcher (l_cmd, l_args, a_directory)
			l_process.set_hidden (show_process)
			l_process.redirect_output_to_stream
			l_process.redirect_error_to_same_as_output
			l_process.launch
			if l_process.launched then
				from
					create l_buffer.make_filled (0, 512)
				until
					l_process.has_output_stream_closed or else l_process.has_output_stream_error
				loop
					l_buffer := l_buffer.aliased_resized_area_with_default (0, l_buffer.capacity)
					l_process.read_output_to_special (l_buffer)
					l_result := converter.console_encoding_to_utf32 (console_encoding, create {STRING_8}.make_from_c_substring ($l_buffer, 1, l_buffer.count))
					l_result.prune_all ({CHARACTER_32} '%R')
					Result.append (l_result)
				end
				l_process.wait_for_exit
			end
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

	is_wait_for_exit: BOOLEAN
			-- Wait for process to exit?
		do
			Result := not is_not_wait_for_exit
		end

	set_do_not_wait_for_exit
			-- Set to not wait for process exit.
		do
			is_not_wait_for_exit := True
		end

	set_wait_for_exit
			-- Set to wait for process exit.
		do
			is_not_wait_for_exit := False
		end

feature {NONE} -- Code page conversion

	converter: LOCALIZED_PRINTER
			-- Converter of the input data into Unicode.
		once
			create Result
		end

	console_encoding: ENCODING
			-- Current console encoding.
		once
			Result := (create {SYSTEM_ENCODINGS}).console_encoding
		end

feature -- Implementation: Constants

	Dos_where_not_found_message: STRING = "INFO: Could not find files for the given pattern(s).%N"
			-- Windows 'where' command not found message

note
	copyright: "Copyright (c) 2024-2025, Larry Rix"
	license: "MIT License"
	source: "[
		SIMPLE_PROCESS - Lightweight process execution library
		Provides simple wrapper for shell command execution
	]"

end
