note
	description: "Test application for SIMPLE_PROCESS"
	author: "Larry Rix"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run the tests.
		do
			print ("Running SIMPLE_PROCESS tests...%N%N")
			passed := 0
			failed := 0

			run_lib_tests
			run_simple_process_tests
			run_piped_process_tests

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")

			if failed > 0 then
				print ("TESTS FAILED%N")
			else
				print ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- Test Runners

	run_lib_tests
		do
			create lib_tests
			run_test (agent lib_tests.test_output_of_command, "test_output_of_command")
			run_test (agent lib_tests.test_has_file_in_path, "test_has_file_in_path")
			run_test (agent lib_tests.test_show_process_flag, "test_show_process_flag")
			run_test (agent lib_tests.test_wait_for_exit_flag, "test_wait_for_exit_flag")
			run_test (agent lib_tests.test_simple_process_make, "test_simple_process_make")
			run_test (agent lib_tests.test_simple_process_show_window, "test_simple_process_show_window")
			run_test (agent lib_tests.test_async_process_make, "test_async_process_make")
			run_test (agent lib_tests.test_output_with_directory, "test_output_with_directory")
		end

	run_simple_process_tests
		do
			create process_tests
			run_test (agent process_tests.test_output_of_command_echo, "test_output_of_command_echo")
			run_test (agent process_tests.test_output_of_command_dir, "test_output_of_command_dir")
			run_test (agent process_tests.test_has_file_in_path_cmd, "test_has_file_in_path_cmd")
			run_test (agent process_tests.test_has_file_in_path_nonexistent, "test_has_file_in_path_nonexistent")
			run_test (agent process_tests.test_output_of_command_with_directory, "test_output_of_command_with_directory")
			run_test (agent process_tests.test_show_process_toggle, "test_show_process_toggle")
			run_test (agent process_tests.test_wait_for_exit_toggle, "test_wait_for_exit_toggle")
			run_test (agent process_tests.test_output_of_command_where, "test_output_of_command_where")
			run_test (agent process_tests.test_output_of_command_multi_arg, "test_output_of_command_multi_arg")
		end

	run_piped_process_tests
			-- 1.1.0: stdin, UTF-8, no pipe deadlock. Needs the echo child
			-- (ec.sh test -config simple_process.ecf -target simple_process_echo).
		do
			create piped_tests
			run_test (agent piped_tests.test_utf_8_round_trips_every_script, "test_utf_8_round_trips_every_script")
			run_test (agent piped_tests.test_utf_8_bytes_outside_utf_8_read_as_latin_1, "test_utf_8_bytes_outside_utf_8_read_as_latin_1")
			run_test (agent piped_tests.test_utf_8_unfinished_tail, "test_utf_8_unfinished_tail")
			run_test (agent piped_tests.test_execute_output_is_utf_8, "test_execute_output_is_utf_8")
			run_test (agent piped_tests.test_async_output_is_utf_8_across_reads, "test_async_output_is_utf_8_across_reads")
			run_test (agent piped_tests.test_execute_with_input_round_trips_text, "test_execute_with_input_round_trips_text")
			run_test (agent piped_tests.test_execute_with_input_large_both_ways, "test_execute_with_input_large_both_ways")
			run_test (agent piped_tests.test_execute_with_input_against_a_flooding_child, "test_execute_with_input_against_a_flooding_child")
			run_test (agent piped_tests.test_execute_with_input_exit_code_and_failure, "test_execute_with_input_exit_code_and_failure")
			run_test (agent piped_tests.test_piped_line_exchange, "test_piped_line_exchange")
			run_test (agent piped_tests.test_piped_close_input_is_eof, "test_piped_close_input_is_eof")
			run_test (agent piped_tests.test_piped_separate_stderr, "test_piped_separate_stderr")
			run_test (agent piped_tests.test_piped_large_write_before_any_read, "test_piped_large_write_before_any_read")
			run_test (agent piped_tests.test_piped_read_line_times_out, "test_piped_read_line_times_out")
			run_test (agent piped_tests.test_piped_kill, "test_piped_kill")
			run_test (agent piped_tests.test_piped_start_failure, "test_piped_start_failure")
			run_test (agent piped_tests.test_piped_unicode_command_line, "test_piped_unicode_command_line")
		end

feature {NONE} -- Implementation

	lib_tests: LIB_TESTS
	piped_tests: TEST_PIPED_PROCESS
	process_tests: TEST_SIMPLE_PROCESS

	passed: INTEGER
	failed: INTEGER

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run a single test and update counters.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				print ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			if attached (create {EXCEPTION_MANAGER}).last_exception as l_ex and then attached l_ex.description as l_d then
				print ("        " + l_d.to_string_8 + "%N")
			end
			failed := failed + 1
			l_retried := True
			retry
		end

end
