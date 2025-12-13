note
	description: "Tests for SIMPLE_PROCESS"
	author: "Larry Rix"
	date: "$Date$"
	revision: "$Revision$"
	testing: "covers"

class
	LIB_TESTS

inherit
	TEST_SET_BASE

feature -- Test: Process Helper

	test_output_of_command
			-- Test capturing command output.
		note
			testing: "covers/{SIMPLE_PROCESS_HELPER}.output_of_command"
			testing: "execution/isolated"
		local
			helper: SIMPLE_PROCESS_HELPER
			output: STRING_32
		do
			create helper
			output := helper.output_of_command ("cmd /c echo Hello", Void)
			assert_false ("has output", output.is_empty)
			assert_string_contains ("contains hello", output, "Hello")
		end

	test_has_file_in_path
			-- Test checking if file exists in PATH.
		note
			testing: "covers/{SIMPLE_PROCESS_HELPER}.has_file_in_path"
			testing: "execution/isolated"
		local
			helper: SIMPLE_PROCESS_HELPER
		do
			create helper
			assert_true ("cmd.exe in path", helper.has_file_in_path ("cmd.exe"))
		end

	test_show_process_flag
			-- Test show_process flag toggling.
		note
			testing: "covers/{SIMPLE_PROCESS_HELPER}.show_process"
			testing: "covers/{SIMPLE_PROCESS_HELPER}.set_show_process"
		local
			helper: SIMPLE_PROCESS_HELPER
		do
			create helper
			assert_false ("default false", helper.show_process)
			helper.set_show_process (True)
			assert_true ("set to true", helper.show_process)
			helper.set_show_process (False)
			assert_false ("set to false", helper.show_process)
		end

	test_wait_for_exit_flag
			-- Test wait_for_exit flag.
		note
			testing: "covers/{SIMPLE_PROCESS_HELPER}.is_wait_for_exit"
			testing: "covers/{SIMPLE_PROCESS_HELPER}.set_do_not_wait_for_exit"
		local
			helper: SIMPLE_PROCESS_HELPER
		do
			create helper
			assert_true ("default waits", helper.is_wait_for_exit)
			helper.set_do_not_wait_for_exit
			assert_false ("no longer waits", helper.is_wait_for_exit)
		end

feature -- Test: Simple Process

	test_simple_process_make
			-- Test SIMPLE_PROCESS creation.
		note
			testing: "covers/{SIMPLE_PROCESS}.make"
		local
			process: SIMPLE_PROCESS
		do
			create process.make
			assert_attached ("process created", process)
		end

	test_simple_process_show_window
			-- Test SIMPLE_PROCESS show_window flag.
		note
			testing: "covers/{SIMPLE_PROCESS}.show_window"
			testing: "covers/{SIMPLE_PROCESS}.set_show_window"
		local
			process: SIMPLE_PROCESS
		do
			create process.make
			assert_false ("default hidden", process.show_window)
			process.set_show_window (True)
			assert_true ("now visible", process.show_window)
		end

feature -- Test: Async Process

	test_async_process_make
			-- Test SIMPLE_ASYNC_PROCESS creation.
		note
			testing: "covers/{SIMPLE_ASYNC_PROCESS}.make"
		local
			async: SIMPLE_ASYNC_PROCESS
		do
			create async.make
			assert_attached ("async process created", async)
		end

feature -- Test: Command with Directory

	test_output_with_directory
			-- Test running command in specific directory.
		note
			testing: "covers/{SIMPLE_PROCESS_HELPER}.output_of_command"
			testing: "execution/isolated"
		local
			helper: SIMPLE_PROCESS_HELPER
			output: STRING_32
		do
			create helper
			output := helper.output_of_command ("cmd /c dir", "C:\")
			assert_false ("has output", output.is_empty)
		end

end
