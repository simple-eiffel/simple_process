note
	description: "[
		Tests for 1.1.0: writing to a child's stdin (SIMPLE_PIPED_PROCESS,
		SIMPLE_PROCESS.execute_with_input), UTF-8 decoding of captured
		output (SIMPLE_PROCESS_UTF_8 and every class that captures), and
		pipe-deadlock freedom with payloads well over the 64 KB pipe
		buffer in both directions.

		The child is sp_echo_child.exe (target simple_process_echo), which
		moves bytes with raw ReadFile/WriteFile, so what comes back is
		exactly what the library sent and decoded - nothing in between
		touches a code page.

		The text is Genesis 1:1's first three words in Hebrew with points
		and cantillation, John 1:1's first five words in polytonic Greek,
		a Latin-1 letter and two characters outside the BMP (4-byte UTF-8).
	]"
	testing: "covers"

class
	TEST_PIPED_PROCESS

inherit
	TEST_SET_BASE

feature -- Tests: the codec

	test_utf_8_round_trips_every_script
			-- Encoding then decoding a sample line gives it back.
		local
			l_utf: SIMPLE_PROCESS_UTF_8
			l_line: STRING_32
		do
			create l_utf
			l_line := sample_line (1)
			assert_true ("round trip", l_utf.text (l_utf.bytes (l_line)).same_string (l_line))
			assert_true ("bet is D7 91", l_utf.bytes (from_codes (<<0x05D1>>)).same_string ("%/215/%/145/"))
			assert_true ("U+10900 is F0 90 A4 80", l_utf.bytes (from_codes (<<0x10900>>)).same_string ("%/240/%/144/%/164/%/128/"))
		end

	test_utf_8_bytes_outside_utf_8_read_as_latin_1
			-- Bytes that start no well-formed sequence read as before 1.1.0.
		local
			l_utf: SIMPLE_PROCESS_UTF_8
		do
			create l_utf
			assert_true ("lone E9 is e-acute", l_utf.text ("caf%/233/").same_string (from_codes (<<0x63, 0x61, 0x66, 0xE9>>)))
			assert_true ("overlong C0 AF is two Latin-1", l_utf.text ("%/192/%/175/").same_string (from_codes (<<0xC0, 0xAF>>)))
			assert_true ("encoded surrogate ED A0 80 is three Latin-1", l_utf.text ("%/237/%/160/%/128/").same_string (from_codes (<<0xED, 0xA0, 0x80>>)))
			assert_true ("NUL dropped", l_utf.text ("a%/000/b").same_string ({STRING_32} "ab"))
			assert_true ("ASCII unchanged", l_utf.text ("plain ASCII%R%N").same_string ({STRING_32} "plain ASCII%R%N"))
		end

	test_utf_8_unfinished_tail
			-- The start of a character at the end of a chunk is held back.
		local
			l_utf: SIMPLE_PROCESS_UTF_8
		do
			create l_utf
			assert_integers_equal ("x D7", 1, l_utf.unfinished_tail_count ("x%/215/"))
			assert_integers_equal ("x E2 82", 2, l_utf.unfinished_tail_count ("x%/226/%/130/"))
			assert_integers_equal ("x F0 9F 93", 3, l_utf.unfinished_tail_count ("x%/240/%/159/%/147/"))
			assert_integers_equal ("x E2 82 AC complete", 0, l_utf.unfinished_tail_count ("x%/226/%/130/%/172/"))
			assert_integers_equal ("x C0 never leads", 0, l_utf.unfinished_tail_count ("x%/192/"))
			assert_integers_equal ("empty", 0, l_utf.unfinished_tail_count (""))
		end

feature -- Tests: captured output is UTF-8 (D14 part 2)

	test_execute_output_is_utf_8
			-- SIMPLE_PROCESS.execute of a child that writes 1000 UTF-8 lines:
			-- every line comes back intact (0/1000 before 1.1.0).
		local
			l_process: SIMPLE_PROCESS
			l_bytes: STRING_8
			l_path: STRING_32
			l_intact: INTEGER
		do
			require_echo_child
			l_bytes := utf_8.bytes (sample_text (Line_count))
			l_path := temporary_file ("sp_utf8_lines.txt", l_bytes)
			create l_process.make
			l_process.execute (echo_command ({STRING_32} "cat %"" + l_path + {STRING_32} "%""))
			assert_true ("ran", l_process.was_successful)
			if attached l_process.last_output as l_out and attached l_process.last_output_bytes as l_raw then
				l_intact := intact_lines (l_out, Line_count)
				print ("      SIMPLE_PROCESS.execute: lines intact " + l_intact.out + "/" + Line_count.out
					+ ", raw bytes identical " + l_raw.same_string (l_bytes).out + "%N")
				assert_integers_equal ("every line intact", Line_count, l_intact)
				assert_true ("raw bytes kept", l_raw.same_string (l_bytes))
			else
				assert_true ("output captured", False)
			end
		end

	test_async_output_is_utf_8_across_reads
			-- SIMPLE_ASYNC_PROCESS reading the same 1000 lines in whatever
			-- chunks the pipe delivers: a character split between two reads
			-- is not broken.
		local
			l_async: SIMPLE_ASYNC_PROCESS
			l_bytes: STRING_8
			l_path: STRING_32
			l_reads, l_splits, l_intact: INTEGER
			l_done: BOOLEAN
		do
			require_echo_child
			l_bytes := utf_8.bytes (sample_text (Line_count))
			l_path := temporary_file ("sp_utf8_async.txt", l_bytes)
			create l_async.make
				-- 4093 bytes per write, 2 ms apart: the reads end wherever
				-- the writes did, mostly inside a multi-byte character.
			l_async.start (echo_command ({STRING_32} "cat %"" + l_path + {STRING_32} "%" 4093 2"))
			assert_true ("started", l_async.was_started_successfully)
			from
			until
				l_done
			loop
				l_done := not l_async.is_running
				if attached l_async.read_available_output then
					l_reads := l_reads + 1
				end
				if utf_8.unfinished_tail_count (l_async.accumulated_bytes) > 0 then
					l_splits := l_splits + 1
				end
				(create {EXECUTION_ENVIRONMENT}).sleep (1_000_000)
			end
			l_async.close
			l_intact := intact_lines (l_async.accumulated_output, Line_count)
			print ("      SIMPLE_ASYNC_PROCESS: " + l_reads.out + " non-empty reads, " + l_splits.out
				+ " polls ended inside a character, lines intact " + l_intact.out + "/" + Line_count.out + "%N")
			assert_greater_than ("a read really did end inside a character", l_splits, 0)
			assert_integers_equal ("every line intact", Line_count, l_intact)
			assert_true ("raw bytes kept", l_async.accumulated_bytes.same_string (l_bytes))
		end

feature -- Tests: writing to stdin (D14 part 1)

	test_execute_with_input_round_trips_text
			-- 1000 lines of Hebrew and Greek into the child's stdin as UTF-8,
			-- back out of its stdout, decoded: every line intact.
		local
			l_process: SIMPLE_PROCESS
			l_text, l_out: STRING_32
			l_intact: INTEGER
		do
			require_echo_child
			l_text := sample_text (Line_count)
			create l_process.make
			l_out := l_process.output_of_command_with_input (echo_command (""), l_text)
			l_intact := intact_lines (l_out, Line_count)
			print ("      execute_with_input: " + utf_8.bytes (l_text).count.out + " bytes in, lines intact "
				+ l_intact.out + "/" + Line_count.out + "%N")
			assert_true ("ran", l_process.was_successful)
			assert_integers_equal ("exit code", 0, l_process.last_exit_code)
			assert_integers_equal ("every line intact", Line_count, l_intact)
			assert_true ("identical", l_out.same_string (l_text))
		end

	test_execute_with_input_large_both_ways
			-- 1.5 MB of every byte value in and out at once - over twenty
			-- times the pipe buffer each way - with no deadlock.
		local
			l_process: SIMPLE_PROCESS
			l_payload: STRING_8
		do
			require_echo_child
			l_payload := byte_payload (Large_size)
			create l_process.make
			l_process.execute_with_input_bytes (echo_command (""), l_payload)
			assert_true ("ran", l_process.was_successful)
			if attached l_process.last_output_bytes as l_raw then
				print ("      execute_with_input_bytes: " + l_payload.count.out + " bytes in, "
					+ l_raw.count.out + " bytes out, identical " + l_raw.same_string (l_payload).out + "%N")
				assert_true ("identical bytes", l_raw.same_string (l_payload))
			else
				assert_true ("output captured", False)
			end
		end

	test_execute_with_input_against_a_flooding_child
			-- The classic deadlock: the child writes 1 MB before it reads a
			-- byte while the parent writes 1 MB before it reads a byte.
		local
			l_process: SIMPLE_PROCESS
			l_payload: STRING_8
		do
			require_echo_child
			l_payload := byte_payload (Flood_size)
			create l_process.make
			l_process.execute_with_input_bytes (echo_command ("flood " + Flood_size.out), l_payload)
			assert_true ("ran", l_process.was_successful)
			if attached l_process.last_output_bytes as l_raw then
				print ("      flooding child: " + l_payload.count.out + " bytes in, " + l_raw.count.out + " bytes out%N")
				assert_integers_equal ("flood then echo", 2 * Flood_size, l_raw.count)
				assert_true ("echo part identical", l_raw.substring (Flood_size + 1, l_raw.count).same_string (l_payload))
			else
				assert_true ("output captured", False)
			end
		end

	test_execute_with_input_exit_code_and_failure
			-- The exit code comes back; a missing program is a failure with a reason.
		local
			l_process: SIMPLE_PROCESS
		do
			require_echo_child
			create l_process.make
			l_process.execute_with_input (echo_command ("exit 7"), {STRING_32} "x")
			assert_true ("ran", l_process.was_successful)
			assert_integers_equal ("exit code", 7, l_process.last_exit_code)
			assert_true ("echoed", attached l_process.last_output as l_o and then l_o.same_string ({STRING_32} "x"))
			l_process.execute_with_input ("no_such_program_sp_1_1_0.exe", {STRING_32} "x")
			assert_false ("failed", l_process.was_successful)
			if attached l_process.last_error as l_reason then
				print ("      missing program: " + utf_8.bytes (l_reason) + "%N")
				assert_false ("has reason", l_reason.is_empty)
			else
				assert_true ("reason given", False)
			end
		end

feature -- Tests: plain execute, 1.1.0 (stdin, no 1 MB cap, any command line)

	test_execute_gives_the_child_an_empty_stdin
			-- A child that reads stdin until EOF finishes at once: its stdin is
			-- empty. (Before 1.1.0 it read this process's own stdin, and waited
			-- on it for as long as that stayed open.)
		local
			l_process: SIMPLE_PROCESS
		do
			require_echo_child
			create l_process.make
			assert_false ("default: empty stdin", l_process.inherits_standard_input)
			l_process.execute (echo_command (""))
			assert_true ("ran", l_process.was_successful)
			assert_integers_equal ("exit code", 0, l_process.last_exit_code)
			assert_true ("read nothing", attached l_process.last_output as l_o and then l_o.is_empty)
		end

	test_execute_can_hand_the_child_its_own_stdin
			-- With `inherits_standard_input' the grandchild reads the stdin
			-- its parent was given; without it, nothing.
		local
			l_process: SIMPLE_PROCESS
		do
			require_echo_child
			create l_process.make
			l_process.execute_with_input (echo_command ("inherit 1"), {STRING_32} "through two generations")
			print ("      inherit 1: %"" + utf_8.bytes (output_of (l_process)) + "%"%N")
			assert_true ("grandchild read the parent's stdin", output_of (l_process).same_string ("through two generations"))
			l_process.execute_with_input (echo_command ("inherit 0"), {STRING_32} "through two generations")
			print ("      inherit 0: %"" + utf_8.bytes (output_of (l_process)) + "%"%N")
			assert_true ("grandchild read an empty stdin", output_of (l_process).is_empty)
		end

	test_execute_output_is_not_cut_at_1_mb
			-- 3 MB of output all arrives (before 1.1.0: silently cut at 1 MB).
		local
			l_process: SIMPLE_PROCESS
		do
			require_echo_child
			create l_process.make
			l_process.execute (echo_command ("flood 3000000"))
			if attached l_process.last_output_bytes as l_raw then
				print ("      execute of a 3000000-byte flood: " + l_raw.count.out + " bytes, truncated "
					+ l_process.was_output_truncated.out + "%N")
				assert_integers_equal ("every byte", 3_000_000, l_raw.count)
			else
				assert_true ("output captured", False)
			end
			assert_false ("not truncated", l_process.was_output_truncated)
		end

	test_execute_output_limit_reports_the_cut
			-- With a limit, output is cut there, the cut is reported, and the
			-- child is still drained to its end.
		local
			l_process: SIMPLE_PROCESS
		do
			require_echo_child
			create l_process.make
			l_process.set_output_limit (100_000)
			l_process.execute (echo_command ("flood 3000000"))
			assert_true ("ran", l_process.was_successful)
			assert_integers_equal ("child finished", 0, l_process.last_exit_code)
			if attached l_process.last_output_bytes as l_raw then
				print ("      limit 100000: " + l_raw.count.out + " bytes kept, truncated "
					+ l_process.was_output_truncated.out + "%N")
				assert_integers_equal ("kept the limit", 100_000, l_raw.count)
			else
				assert_true ("output captured", False)
			end
			assert_true ("cut reported", l_process.was_output_truncated)
		end

	test_execute_takes_any_command_line
			-- A Hebrew file name in the command (before 1.1.0: a to_string_8
			-- precondition violation), and in a PATH query.
		local
			l_process: SIMPLE_PROCESS
			l_path: STRING_32
		do
			require_echo_child
			l_path := temporary_file_named (from_codes (<<0x05E9, 0x05DC, 0x05D5, 0x05DD, 0x5F, 0x31, 0x2E, 0x74, 0x78, 0x74>>),
				utf_8.bytes (sample_line (3)))
			create l_process.make
			l_process.execute (echo_command ({STRING_32} "cat %"" + l_path + {STRING_32} "%""))
			assert_true ("ran", l_process.was_successful)
			assert_integers_equal ("child found the file", 0, l_process.last_exit_code)
			assert_true ("contents", output_of (l_process).same_string (sample_line (3)))
			assert_false ("Hebrew name not on PATH, and no crash", l_process.has_command (from_codes (<<0x05E9, 0x05DC, 0x05D5, 0x05DD>>)))
			assert_true ("cmd is on PATH", l_process.has_command ("cmd"))
		end

	test_async_takes_any_command_line_and_gives_an_empty_stdin
			-- SIMPLE_ASYNC_PROCESS: the stdin-reading child ends at once, and a
			-- Hebrew file name reaches its child.
		local
			l_async: SIMPLE_ASYNC_PROCESS
			l_path: STRING_32
		do
			require_echo_child
			create l_async.make
			l_async.start (echo_command (""))
			assert_true ("started", l_async.was_started_successfully)
			assert_integers_equal ("finished at once", 1, l_async.wait (5_000))
			assert_integers_equal ("exit code", 0, l_async.exit_code)
			l_async.close
			l_path := temporary_file_named (from_codes (<<0x05E9, 0x05DC, 0x05D5, 0x05DD, 0x5F, 0x32, 0x2E, 0x74, 0x78, 0x74>>),
				utf_8.bytes (sample_line (4)))
			create l_async.make
			l_async.start (echo_command ({STRING_32} "cat %"" + l_path + {STRING_32} "%""))
			assert_integers_equal ("finished", 1, l_async.wait (5_000))
			l_async.close
			assert_true ("contents", l_async.accumulated_output.same_string (sample_line (4)))
		end

	test_async_start_failure_keeps_its_shape
			-- A failed start is still `is_started' with `last_error', as in 1.0.
		local
			l_async: SIMPLE_ASYNC_PROCESS
		do
			create l_async.make
			l_async.start ("no_such_program_sp_1_1_0.exe")
			assert_true ("started (attempted)", l_async.is_started)
			assert_false ("not successfully", l_async.was_started_successfully)
			assert_attached ("reason", l_async.last_error)
			assert_false ("not running", l_async.is_running)
			assert_integers_equal ("no exit code", -1, l_async.exit_code)
			assert_integers_equal ("wait is an error", -1, l_async.wait (0))
			l_async.close
			assert_false ("closed", l_async.is_started)
		end

feature -- Tests: SIMPLE_PIPED_PROCESS

	test_piped_line_exchange
			-- One child, 1000 request/reply lines over stdin/stdout.
		local
			l_child: SIMPLE_PIPED_PROCESS
			i, l_intact: INTEGER
		do
			require_echo_child
			create l_child.make
			l_child.start (echo_command (""))
			assert_true ("started", l_child.is_started)
			from
				i := 1
			until
				i > Line_count
			loop
				l_child.write_line (sample_line (i))
				l_child.read_line (5_000)
				if attached l_child.last_line as l_line and then l_line.same_string (sample_line (i)) then
					l_intact := l_intact + 1
				end
				i := i + 1
			end
			l_child.close_input
			l_child.wait_for_exit (5_000)
			print ("      SIMPLE_PIPED_PROCESS line exchange: replies intact " + l_intact.out + "/" + Line_count.out
				+ ", exit code " + l_child.exit_code.out + "%N")
			assert_integers_equal ("every reply intact", Line_count, l_intact)
			assert_true ("exited after EOF", l_child.has_exited)
			assert_integers_equal ("exit code", 0, l_child.exit_code)
			l_child.close
			assert_false ("closed", l_child.is_started)
			assert_integers_equal ("exit code kept after close", 0, l_child.exit_code)
		end

	test_piped_close_input_is_eof
			-- Closing stdin is the child's end of file.
		local
			l_child: SIMPLE_PIPED_PROCESS
		do
			require_echo_child
			create l_child.make
			l_child.start (echo_command (""))
			l_child.write_text ({STRING_32} "abc")
			assert_true ("written", l_child.last_write_succeeded)
			l_child.close_input
			assert_false ("input closed", l_child.is_input_open)
			l_child.wait_for_exit (5_000)
			assert_true ("exited", l_child.has_exited)
			l_child.await_output_end (5_000)
			assert_true ("output ended", l_child.is_output_ended)
			assert_true ("echoed", l_child.pending_output.same_string ("abc"))
			l_child.read_line (0)
			assert_true ("last line without a line end", attached l_child.last_line as l_l and then l_l.same_string ({STRING_32} "abc"))
			l_child.read_line (0)
			assert_void ("nothing more", l_child.last_line)
			l_child.close
		end

	test_piped_separate_stderr
			-- With stderr kept apart, a protocol on stdout stays clean.
		local
			l_child: SIMPLE_PIPED_PROCESS
		do
			require_echo_child
			create l_child.make
			l_child.set_merge_error_output (False)
			l_child.start (echo_command ("stderr"))
			l_child.write_text ({STRING_32} "to-err")
			l_child.close_input
			l_child.await_output_end (5_000)
			assert_true ("stderr apart", l_child.pending_error.same_string ("to-err"))
			assert_true ("stdout clean", l_child.pending_output.same_string ("OUT%N"))
			l_child.close
		end

	test_piped_large_write_before_any_read
			-- 1.5 MB written before a single read: the pumps keep the child moving.
		local
			l_child: SIMPLE_PIPED_PROCESS
			l_payload: STRING_8
		do
			require_echo_child
			l_payload := byte_payload (Large_size)
			create l_child.make
			l_child.start (echo_command (""))
			l_child.write_bytes (l_payload)
			assert_true ("all written", l_child.last_write_succeeded)
			l_child.close_input
			l_child.await_output_end ({SIMPLE_PIPED_PROCESS}.Infinite)
			assert_true ("identical", l_child.pending_output.same_string (l_payload))
			l_child.close
		end

	test_piped_read_line_times_out
			-- No line within the timeout answers Void, and the child lives on.
		local
			l_child: SIMPLE_PIPED_PROCESS
		do
			require_echo_child
			create l_child.make
			l_child.start (echo_command (""))
			l_child.read_line (200)
			assert_void ("no line yet", l_child.last_line)
			assert_true ("still running", l_child.is_running)
			l_child.close_input
			l_child.read_line (5_000)
			assert_void ("EOF and nothing written", l_child.last_line)
			l_child.close
		end

	test_piped_kill
			-- A child that would sleep a minute is killed.
		local
			l_child: SIMPLE_PIPED_PROCESS
		do
			require_echo_child
			create l_child.make
			l_child.start (echo_command ("sleep 60000"))
			assert_true ("running", l_child.is_running)
			l_child.kill
			l_child.wait_for_exit (5_000)
			assert_true ("exited", l_child.has_exited)
			assert_integers_equal ("killed with 1", 1, l_child.exit_code)
			l_child.close
		end

	test_piped_start_failure
			-- A missing program does not start, and says why.
		local
			l_child: SIMPLE_PIPED_PROCESS
		do
			create l_child.make
			l_child.start ("no_such_program_sp_1_1_0.exe")
			assert_false ("not started", l_child.is_started)
			assert_attached ("reason", l_child.last_error)
		end

	test_piped_unicode_command_line
			-- The command line is passed as UTF-16: a Hebrew file name reaches the child.
		local
			l_child: SIMPLE_PIPED_PROCESS
			l_bytes: STRING_8
			l_path: STRING_32
		do
			require_echo_child
			l_bytes := utf_8.bytes (sample_line (7))
			l_path := temporary_file_named (from_codes (<<0x05E9, 0x05DC, 0x05D5, 0x05DD, 0x2E, 0x74, 0x78, 0x74>>), l_bytes)
			create l_child.make
			l_child.start (echo_command ({STRING_32} "cat %"" + l_path + {STRING_32} "%""))
			assert_true ("started", l_child.is_started)
			l_child.await_output_end (5_000)
			l_child.wait_for_exit (5_000)
			assert_integers_equal ("child found the file", 0, l_child.exit_code)
			assert_true ("contents", l_child.pending_output_text.same_string (sample_line (7)))
			l_child.close
		end

feature {NONE} -- The child

	output_of (a_process: SIMPLE_PROCESS): STRING_32
			-- `a_process.last_output', or empty.
		do
			if attached a_process.last_output as l_out then
				Result := l_out
			else
				create Result.make_empty
			end
		end

	echo_child: STRING_32
			-- Full path of sp_echo_child.exe.
		local
			l_env: EXECUTION_ENVIRONMENT
		once
			create l_env
			create Result.make_from_string_general (l_env.current_working_path.name)
			Result.append ({STRING_32} "\EIFGENs\simple_process_echo\F_code\sp_echo_child.exe")
		end

	echo_command (a_arguments: READABLE_STRING_GENERAL): STRING_32
			-- Command line running `echo_child' with `a_arguments'.
		do
			Result := {STRING_32} "%"" + echo_child + {STRING_32} "%""
			if not a_arguments.is_empty then
				Result.append_character (' ')
				Result.append_string_general (a_arguments)
			end
		end

	require_echo_child
			-- Fail clearly when the child has not been built.
		do
			assert_true ("echo child built (ec.sh test -config simple_process.ecf -target simple_process_echo)",
				(create {RAW_FILE}.make_with_name (echo_child)).exists)
		end

feature {NONE} -- Sample data

	Line_count: INTEGER = 1000

	Large_size: INTEGER = 1_500_000
			-- Over twenty times a 64 KB pipe buffer.

	Flood_size: INTEGER = 1_000_000

	utf_8: SIMPLE_PROCESS_UTF_8
		once
			create Result
		end

	hebrew: STRING_32
			-- Genesis 1:1, first three words, with points and cantillation.
		once
			Result := from_codes (<<0x05D1, 0x05BC, 0x05B0, 0x05E8, 0x05B5, 0x05D0, 0x05E9, 0x05C1, 0x05B4, 0x0596, 0x05D9, 0x05EA,
				0x20, 0x05D1, 0x05BC, 0x05B8, 0x05E8, 0x05B8, 0x05A3, 0x05D0,
				0x20, 0x05D0, 0x05B1, 0x05DC, 0x05B9, 0x05D4, 0x05B4, 0x0591, 0x05D9, 0x05DD, 0x05C3>>)
		end

	greek: STRING_32
			-- John 1:1, first five words, polytonic.
		once
			Result := from_codes (<<0x1F18, 0x03BD, 0x20, 0x1F00, 0x03C1, 0x03C7, 0x1FC7, 0x20, 0x1F26, 0x03BD,
				0x20, 0x1F41, 0x20, 0x03BB, 0x03CC, 0x03B3, 0x03BF, 0x03C2>>)
		end

	sample_line (a_number: INTEGER): STRING_32
			-- Line `a_number' of the sample text (no line end).
		do
			create Result.make (80)
			Result.append_integer (a_number)
			Result.append ({STRING_32} " ")
			Result.append (hebrew)
			Result.append ({STRING_32} " | ")
			Result.append (greek)
			Result.append ({STRING_32} " | caf")
			Result.append_code (0xE9)
			Result.append ({STRING_32} " ")
			Result.append_code (0x10900)
			Result.append_code (0x1F4D6)
		end

	sample_text (a_count: INTEGER): STRING_32
			-- Lines 1 to `a_count', each ended by LF.
		local
			i: INTEGER
		do
			create Result.make (a_count * 80)
			from
				i := 1
			until
				i > a_count
			loop
				Result.append (sample_line (i))
				Result.append_character ('%N')
				i := i + 1
			end
		end

	intact_lines (a_text: READABLE_STRING_32; a_count: INTEGER): INTEGER
			-- How many of lines 1 .. `a_count' of `a_text' equal the sample line.
		local
			l_lines: LIST [READABLE_STRING_32]
			i: INTEGER
		do
			l_lines := a_text.split ('%N')
			from
				i := 1
			until
				i > a_count or i > l_lines.count
			loop
				if l_lines [i].same_string (sample_line (i)) then
					Result := Result + 1
				end
				i := i + 1
			end
		end

	byte_payload (a_size: INTEGER): STRING_8
			-- `a_size' bytes cycling through all 256 values, NUL and CR LF included.
		local
			i: INTEGER
		do
			create Result.make (a_size)
			from
				i := 0
			until
				i >= a_size
			loop
				Result.append_code (((i * 7 + i // 256) \\ 256).to_natural_32)
				i := i + 1
			end
		end

	from_codes (a_codes: ARRAY [INTEGER]): STRING_32
			-- The string of code points `a_codes'.
		do
			create Result.make (a_codes.count)
			across
				a_codes as ic_code
			loop
				Result.append_code (ic_code.to_natural_32)
			end
		end

	temporary_file (a_name: READABLE_STRING_32; a_bytes: STRING_8): STRING_32
			-- Write `a_bytes' to `a_name' in the temporary directory; its full path.
		do
			Result := temporary_file_named (a_name, a_bytes)
		end

	temporary_file_named (a_name: READABLE_STRING_32; a_bytes: STRING_8): STRING_32
			-- Write `a_bytes' to `a_name' in the temporary directory; its full path.
		local
			l_file: RAW_FILE
		do
			if attached (create {EXECUTION_ENVIRONMENT}).item ("TEMP") as l_temp then
				create Result.make_from_string_general (l_temp)
			else
				create Result.make_from_string_general (".")
			end
			Result.append_character ('\')
			Result.append (a_name)
			create l_file.make_with_name (Result)
			l_file.create_read_write
			l_file.put_string (a_bytes)
			l_file.close
		end

end
