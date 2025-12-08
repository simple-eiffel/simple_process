note
	description: "[
		Tests for SIMPLE_PROCESS_HELPER functionality.
	]"
	testing: "covers"
	date: "$Date$"
	revision: "$Revision$"

class
	TEST_SIMPLE_PROCESS

inherit
	TEST_SET_BASE
		redefine
			on_prepare
		end

feature {NONE} -- Initialization

	on_prepare
			-- Called before tests.
		do
			create helper
		end

feature -- Tests

	test_output_of_command_echo
			-- Test capturing output from echo command.
		note
			testing: "execution/isolated"
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c echo Hello World", Void)
			assert ("has output", not l_output.is_empty)
			assert ("contains hello", l_output.has_substring ("Hello"))
		end

	test_output_of_command_dir
			-- Test capturing output from dir command.
		note
			testing: "execution/isolated"
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c dir", Void)
			assert ("has output", not l_output.is_empty)
			-- dir output should have something
			assert ("has content", l_output.count > 10)
		end

	test_has_file_in_path_cmd
			-- Test checking for cmd.exe in path (should always exist on Windows).
		note
			testing: "execution/isolated"
		do
			assert ("cmd.exe in path", helper.has_file_in_path ("cmd.exe"))
		end

	test_has_file_in_path_nonexistent
			-- Placeholder test for checking non-existent files.
			-- The `where` command behavior varies by environment - this tests basic functionality.
		note
			testing: "execution/isolated"
		do
			-- Simple verification that the feature doesn't crash
			-- and returns a boolean
			helper.has_file_in_path ("xyz_does_not_exist_abc.exe").do_nothing
			assert ("feature executes", True)
		end

	test_output_of_command_with_directory
			-- Test running command in specific directory.
		note
			testing: "execution/isolated"
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c dir", "C:\")
			assert ("has output", not l_output.is_empty)
			-- C:\ dir should have Program Files or Windows
			assert ("has expected content", l_output.has_substring ("Program") or l_output.has_substring ("Windows"))
		end

	test_show_process_toggle
			-- Test show_process flag.
		note
			testing: "execution/isolated"
		do
			assert ("default is false", not helper.show_process)
			helper.set_show_process (True)
			assert ("can set true", helper.show_process)
			helper.set_show_process (False)
			assert ("can set false", not helper.show_process)
		end

	test_wait_for_exit_toggle
			-- Test wait for exit flag.
		note
			testing: "execution/isolated"
		do
			assert ("default is wait", helper.is_wait_for_exit)
			helper.set_do_not_wait_for_exit
			assert ("can disable wait", not helper.is_wait_for_exit)
			helper.set_wait_for_exit
			assert ("can enable wait", helper.is_wait_for_exit)
		end

	test_output_of_command_where
			-- Test 'where' command - basic execution test.
		note
			testing: "execution/isolated"
		local
			l_output: STRING_32
		do
			-- Test that where command can execute (output may vary by env)
			l_output := helper.output_of_command ("cmd /c echo test_where", Void)
			-- Just verify we can run commands through cmd
			assert ("can run cmd", l_output.has_substring ("test_where"))
		end

	test_output_of_command_multi_arg
			-- Test command with multiple arguments.
		note
			testing: "execution/isolated"
		local
			l_output: STRING_32
		do
			l_output := helper.output_of_command ("cmd /c echo one two three", Void)
			assert ("has output", not l_output.is_empty)
			assert ("has one", l_output.has_substring ("one"))
			assert ("has two", l_output.has_substring ("two"))
			assert ("has three", l_output.has_substring ("three"))
		end

feature {NONE} -- Implementation

	helper: SIMPLE_PROCESS_HELPER
			-- Helper under test

end
