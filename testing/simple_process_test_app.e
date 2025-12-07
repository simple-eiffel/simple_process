note
	description: "Test runner for simple_process"
	date: "$Date$"
	revision: "$Revision$"

class
	SIMPLE_PROCESS_TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run tests.
		do
			print ("simple_process test runner%N")
			print ("============================%N%N")

			run_test (agent test_output_of_command_echo, "test_output_of_command_echo")
			run_test (agent test_output_of_command_dir, "test_output_of_command_dir")
			run_test (agent test_has_file_in_path_cmd, "test_has_file_in_path_cmd")
			run_test (agent test_has_file_in_path_nonexistent, "test_has_file_in_path_nonexistent")
			run_test (agent test_output_of_command_with_directory, "test_output_of_command_with_directory")
			run_test (agent test_show_process_toggle, "test_show_process_toggle")
			run_test (agent test_wait_for_exit_toggle, "test_wait_for_exit_toggle")
			run_test (agent test_output_of_command_where, "test_output_of_command_where")
			run_test (agent test_output_of_command_multi_arg, "test_output_of_command_multi_arg")
			run_test (agent test_simple_process_direct, "test_simple_process_direct")
			run_test (agent test_file_exists_in_path, "test_file_exists_in_path")

			print ("%N============================%N")
			print ("Results: " + passed_count.out + " passed, " + failed_count.out + " failed%N")
			if failed_count = 0 then
				print ("ALL TESTS PASSED%N")
			end
		end

feature -- Tests

	test_output_of_command_echo
			-- Test capturing output from echo command.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c echo Hello World", Void)
			check_true ("has output", not l_output.is_empty)
			check_true ("contains hello", l_output.has_substring ("Hello"))
		end

	test_output_of_command_dir
			-- Test capturing output from dir command.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c dir", Void)
			check_true ("has output", not l_output.is_empty)
			check_true ("has content", l_output.count > 10)
		end

	test_has_file_in_path_cmd
			-- Test checking for cmd.exe in path.
		do
			check_true ("cmd.exe in path", helper.has_file_in_path ("cmd.exe"))
		end

	test_has_file_in_path_nonexistent
			-- Test checking for non-existent file.
		do
			check_true ("nonexistent not in path", not helper.has_file_in_path ("xyz_does_not_exist_abc.exe"))
		end

	test_output_of_command_with_directory
			-- Test running command in specific directory.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c dir", "C:\")
			check_true ("has output", not l_output.is_empty)
			check_true ("has expected content", l_output.has_substring ("Program") or l_output.has_substring ("Windows"))
		end

	test_show_process_toggle
			-- Test show_process flag.
		do
			check_true ("default is false", not helper.show_process)
			helper.set_show_process (True)
			check_true ("can set true", helper.show_process)
			helper.set_show_process (False)
			check_true ("can set false", not helper.show_process)
		end

	test_wait_for_exit_toggle
			-- Test wait for exit flag.
		do
			check_true ("default is wait", helper.is_wait_for_exit)
			helper.set_do_not_wait_for_exit
			check_true ("can disable wait", not helper.is_wait_for_exit)
			helper.set_wait_for_exit
			check_true ("can enable wait", helper.is_wait_for_exit)
		end

	test_output_of_command_where
			-- Test 'where' command - basic execution.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c echo test_where", Void)
			check_true ("can run cmd", l_output.has_substring ("test_where"))
		end

	test_output_of_command_multi_arg
			-- Test command with multiple arguments.
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c echo one two three", Void)
			check_true ("has output", not l_output.is_empty)
			check_true ("has one", l_output.has_substring ("one"))
			check_true ("has two", l_output.has_substring ("two"))
			check_true ("has three", l_output.has_substring ("three"))
		end

	test_simple_process_direct
			-- Test SIMPLE_PROCESS class directly.
		local
			l_process: SIMPLE_PROCESS
		do
			create l_process.make
			l_process.execute ("cmd /c echo direct test")
			check_true ("was successful", l_process.was_successful)
			check_true ("has output", attached l_process.last_output as l_out and then l_out.has_substring ("direct"))
		end

	test_file_exists_in_path
			-- Test file_exists_in_path on SIMPLE_PROCESS directly.
		local
			l_process: SIMPLE_PROCESS
		do
			create l_process.make
			check_true ("notepad exists", l_process.file_exists_in_path ("notepad.exe"))
			check_true ("fake not exists", not l_process.file_exists_in_path ("fake_program_xyz.exe"))
		end

feature {NONE} -- Test Infrastructure

	helper: SIMPLE_PROCESS_HELPER
			-- Helper under test
		once
			create Result
		end

	passed_count: INTEGER
	failed_count: INTEGER

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run a test and report result.
		local
			l_failed: BOOLEAN
		do
			current_test_failed := False
			if not l_failed then
				a_test.call (Void)
			end
			if current_test_failed then
				print ("  FAIL: " + a_name + "%N")
				failed_count := failed_count + 1
			else
				print ("  PASS: " + a_name + "%N")
				passed_count := passed_count + 1
			end
		rescue
			l_failed := True
			current_test_failed := True
			retry
		end

	current_test_failed: BOOLEAN

	check_true (a_tag: STRING; a_condition: BOOLEAN)
			-- Check that condition is true.
		do
			if not a_condition then
				print ("    ASSERTION FAILED: " + a_tag + "%N")
				current_test_failed := True
			end
		end

end
