note
	description: "[
		The commands and paths the tests use, per platform: a shell to run
		text through, a directory listing, a folder every machine has, and
		a program always on PATH.
	]"
	author: "Larry Rix"

class
	SP_TEST_COMMANDS

feature -- Access

	shell_command (a_text: STRING): STRING
			-- Command line running `a_text' through the system shell.
		do
			if {PLATFORM}.is_windows then
				Result := "cmd /c " + a_text
			else
				Result := "sh -c %"" + a_text + "%""
			end
		end

	listing_command: STRING
			-- Command line listing the current directory.
		do
			if {PLATFORM}.is_windows then
				Result := "cmd /c dir"
			else
				Result := "ls -la"
			end
		end

	root_folder: STRING
			-- A folder every machine has.
		do
			if {PLATFORM}.is_windows then
				Result := "C:\"
			else
				Result := "/"
			end
		end

	shell_program: STRING
			-- The shell's name as `has_file_in_path' finds it.
		do
			if {PLATFORM}.is_windows then
				Result := "cmd.exe"
			else
				Result := "sh"
			end
		end

end
