note
	description: "[
		The child the stdin/UTF-8 tests run (target simple_process_echo,
		executable sp_echo_child.exe). Byte-exact: it moves bytes with
		ReadFile/WriteFile on the raw standard handles, so no text-mode
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
			"C blocking inline use <windows.h>"
		alias
			"[
				HANDLE l_in = GetStdHandle ((DWORD) $a_from);
				HANDLE l_out = GetStdHandle ((DWORD) $a_to);
				char l_buffer [65536];
				DWORD l_n = 0, l_w = 0, l_done = 0;
				while (ReadFile (l_in, l_buffer, sizeof (l_buffer), &l_n, NULL) && l_n > 0) {
					for (l_done = 0; l_done < l_n; l_done += l_w) {
						if (!WriteFile (l_out, l_buffer + l_done, l_n - l_done, &l_w, NULL) || l_w == 0) return;
					}
				}
			]"
		end

	c_write_text (a_to: INTEGER; a_text: POINTER)
			-- Write the C string `a_text' to standard handle `a_to'.
		external
			"C blocking inline use <windows.h>"
		alias
			"[
				DWORD l_w = 0;
				WriteFile (GetStdHandle ((DWORD) $a_to), (const char *) $a_text, (DWORD) strlen ((const char *) $a_text), &l_w, NULL);
			]"
		end

	c_flood (a_to, a_count: INTEGER)
			-- Write `a_count' bytes of a repeating pattern to standard handle `a_to'.
		external
			"C blocking inline use <windows.h>"
		alias
			"[
				HANDLE l_out = GetStdHandle ((DWORD) $a_to);
				char l_buffer [4096];
				int l_i, l_left = (int) $a_count;
				DWORD l_w = 0, l_chunk;
				for (l_i = 0; l_i < 4096; l_i++) l_buffer [l_i] = (char) ('a' + (l_i % 26));
				while (l_left > 0) {
					l_chunk = l_left > 4096 ? 4096 : (DWORD) l_left;
					if (!WriteFile (l_out, l_buffer, l_chunk, &l_w, NULL) || l_w == 0) return;
					l_left -= (int) l_w;
				}
			]"
		end

	c_cat (a_path: POINTER; a_to, a_chunk, a_pause_ms: INTEGER): INTEGER
			-- Write the bytes of file `a_path' (UTF-16) to standard handle `a_to',
			-- `a_chunk' bytes per write, pausing `a_pause_ms' after each. 0 on success.
		external
			"C blocking inline use <windows.h>"
		alias
			"[
				HANDLE l_file = CreateFileW ((LPCWSTR) $a_path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
				HANDLE l_out = GetStdHandle ((DWORD) $a_to);
				char l_buffer [65536];
				DWORD l_n = 0, l_w = 0, l_done;
				if (l_file == INVALID_HANDLE_VALUE) return 2;
				DWORD l_chunk = ($a_chunk > 0 && $a_chunk < 65536) ? (DWORD) $a_chunk : 65536;
				while (ReadFile (l_file, l_buffer, l_chunk, &l_n, NULL) && l_n > 0) {
					for (l_done = 0; l_done < l_n; l_done += l_w) {
						if (!WriteFile (l_out, l_buffer + l_done, l_n - l_done, &l_w, NULL) || l_w == 0) { CloseHandle (l_file); return 3; }
					}
					if ($a_pause_ms > 0) Sleep ((DWORD) $a_pause_ms);
				}
				CloseHandle (l_file);
				return 0;
			]"
		end

end
