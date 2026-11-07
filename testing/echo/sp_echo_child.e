note
	description: "[
		The child the stdin/UTF-8 tests run (target simple_process_echo,
		executable sp_echo_child.exe). Byte-exact: it moves bytes with
		raw reads and writes on the standard streams, so no text-mode
		CR LF translation and no code page touch them.

		    sp_echo_child                 copy stdin to stdout until EOF
		    sp_echo_child stderr          copy stdin to stderr, then write
		                                  "OUT" LF to stdout
		    sp_echo_child exit <n>        copy stdin to stdout, exit with <n>
		    sp_echo_child sleep <ms>      wait <ms>, then copy stdin to stdout
		    sp_echo_child flood <n>       write <n> bytes to stdout BEFORE
		                                  reading anything, then copy stdin
		                                  to stdout (the classic deadlock
		                                  shape for a parent that writes
		                                  first and reads later)
		    sp_echo_child cat <path>      write the file's bytes to stdout
		    sp_echo_child inherit <0|1>   run this same program in echo mode
		                                  through SIMPLE_PROCESS.execute, with
		                                  `inherits_standard_input' 0 or 1,
		                                  and write what it captured to stdout
		                                  (so a test can see which stdin the
		                                  grandchild was given)
		    sp_echo_child own <0|1>       start this same program as
		                                  "sleep 60000" through
		                                  SIMPLE_PIPED_PROCESS with
		                                  `ends_with_owner' 0 or 1, write
		                                  "<pid> <bound 0|1>" LF, then sleep
		                                  a minute (so a test can kill this
		                                  owner and see the grandchild live
		                                  or die)
		    sp_echo_child cat <path> <n> <ms>
		                                  the same, <n> bytes per write with
		                                  a <ms> pause after each, so a reader
		                                  sees the stream cut at arbitrary
		                                  byte positions
	]"
	author: "Larry Rix"

class
	SP_ECHO_CHILD

inherit
	ARGUMENTS_32

create
	make

feature {NONE} -- Initialization

	make
			-- Do what the command line asks.
		local
			l_mode: STRING_32
			l_code: INTEGER
			l_process: SIMPLE_PROCESS
			l_piped: SIMPLE_PIPED_PROCESS
		do
			if argument_count >= 1 then
				l_mode := argument (1)
			else
				l_mode := {STRING_32} "echo"
			end
			if l_mode.same_string ("stderr") then
				c_copy (Std_input, Std_error)
				c_write_text (Std_output, (create {C_STRING}.make ("OUT%N")).item)
			elseif l_mode.same_string ("exit") and argument_count >= 2 then
				c_copy (Std_input, Std_output)
				l_code := argument (2).to_integer
			elseif l_mode.same_string ("sleep") and argument_count >= 2 then
				(create {EXECUTION_ENVIRONMENT}).sleep (argument (2).to_integer_64 * 1_000_000)
				c_copy (Std_input, Std_output)
			elseif l_mode.same_string ("flood") and argument_count >= 2 then
				c_flood (Std_output, argument (2).to_integer)
				c_copy (Std_input, Std_output)
			elseif l_mode.same_string ("inherit") and argument_count >= 2 then
				create l_process.make
				l_process.set_inherits_standard_input (argument (2).same_string ("1"))
				l_process.execute ({STRING_32} "%"" + command_name + {STRING_32} "%"")
				if attached l_process.last_output_bytes as al_bytes and then not al_bytes.is_empty then
					c_write_count (Std_output, (create {C_STRING}.make (al_bytes)).item, al_bytes.count)
				end
			elseif l_mode.same_string ("own") and argument_count >= 2 then
				create l_piped.make
				l_piped.set_ends_with_owner (argument (2).same_string ("1"))
				l_piped.start ({STRING_32} "%"" + command_name + {STRING_32} "%" sleep 60000")
				if l_piped.is_started then
					c_write_text (Std_output, (create {C_STRING}.make (l_piped.process_id.out + " "
						+ l_piped.is_bound_to_owner.to_integer.out + "%N")).item)
				end
				(create {EXECUTION_ENVIRONMENT}).sleep ({INTEGER_64} 60_000 * 1_000_000)
			elseif l_mode.same_string ("cat") and argument_count >= 2 then
				if argument_count >= 4 then
					l_code := c_cat ((create {NATIVE_STRING}.make (argument (2))).item, Std_output, argument (3).to_integer, argument (4).to_integer)
				else
					l_code := c_cat ((create {NATIVE_STRING}.make (argument (2))).item, Std_output, 65536, 0)
				end
			else
				c_copy (Std_input, Std_output)
			end
			if l_code /= 0 then
				(create {EXCEPTIONS}).die (l_code)
			end
		end

feature {NONE} -- Constants

	Std_input: INTEGER = -10
	Std_output: INTEGER = -11
	Std_error: INTEGER = -12
			-- STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE.

feature {NONE} -- Externals

	c_copy (a_from, a_to: INTEGER)
			-- Copy standard handle `a_from' to `a_to' until EOF, chunk by chunk.
		external
			"C blocking inline use %"sp_test_support.h%""
		alias
			"spt_copy ((int) $a_from, (int) $a_to);"
		end

	c_write_text (a_to: INTEGER; a_text: POINTER)
			-- Write the C string `a_text' to standard handle `a_to'.
		external
			"C blocking inline use %"sp_test_support.h%""
		alias
			"spt_write_count ((int) $a_to, (const char *) $a_text, (int) strlen ((const char *) $a_text));"
		end

	c_write_count (a_to: INTEGER; a_data: POINTER; a_count: INTEGER)
			-- Write `a_count' bytes at `a_data' to standard handle `a_to'.
		external
			"C blocking inline use %"sp_test_support.h%""
		alias
			"spt_write_count ((int) $a_to, (const char *) $a_data, (int) $a_count);"
		end

	c_flood (a_to, a_count: INTEGER)
			-- Write `a_count' bytes of a repeating pattern to standard handle `a_to'.
		external
			"C blocking inline use %"sp_test_support.h%""
		alias
			"spt_flood ((int) $a_to, (int) $a_count);"
		end

	c_cat (a_path: POINTER; a_to, a_chunk, a_pause_ms: INTEGER): INTEGER
			-- Write the bytes of file `a_path' (a NATIVE_STRING) to standard handle `a_to',
			-- `a_chunk' bytes per write, pausing `a_pause_ms' after each. 0 on success.
		external
			"C blocking inline use %"sp_test_support.h%""
		alias
			"return spt_cat ((void *) $a_path, (int) $a_to, (int) $a_chunk, (int) $a_pause_ms);"
		end

end
