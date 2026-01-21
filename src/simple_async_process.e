note
	description: "[
		Asynchronous process execution with monitoring capabilities.

		Allows starting processes without blocking, checking status,
		reading output incrementally, and killing hung processes.

		Designed for process monitoring scenarios where you need to:
		- Start a process and continue doing other work
		- Poll for completion with timeout
		- Read output as it becomes available
		- Kill processes that exceed time limits

		Usage:
			async: SIMPLE_ASYNC_PROCESS
			create async.make
			async.start ("ec.exe -batch -config lib.ecf -c_compile", "D:\prod\lib")
			from until not async.is_running or async.elapsed_seconds > 300 loop
				sleep (1_000_000_000) -- 1 second
				if attached async.read_available_output as out then
					print (out)
				end
			end
			if async.is_running then
				async.kill
			end
			print (async.exit_code)
			async.close
	]"
	author: "Larry Rix"
	date: "$Date$"
	revision: "$Revision$"

class
	SIMPLE_ASYNC_PROCESS

create
	make

feature {NONE} -- Initialization

	make
			-- Initialize async process.
		do
			show_window := False
			create accumulated_output.make_empty
		ensure
			not_started: not is_started
			no_output: accumulated_output.is_empty
			window_hidden: not show_window
		end

feature -- Access

	process_id: NATURAL_32
			-- Process ID (PID) of running process.
			-- 0 if not started.
		require
			started: is_started
		do
			Result := c_sp_get_pid (async_handle)
		end

	exit_code: INTEGER
			-- Exit code of finished process.
			-- -1 if still running.
		require
			started: is_started
		do
			Result := c_sp_get_exit_code (async_handle)
		end

	last_error: detachable STRING_32
			-- Error message if start failed.

	accumulated_output: STRING_32
			-- All output read so far.

	elapsed_seconds: INTEGER
			-- Seconds since process started.
		local
			l_now: SIMPLE_DATE_TIME
		do
			if is_started then
				create l_now.make_now
				Result := (l_now.to_timestamp - start_time).to_integer_32
			end
		end

feature -- Status

	is_started: BOOLEAN
			-- Has process been started?
		do
			Result := async_handle /= default_pointer
		end

	is_running: BOOLEAN
			-- Is the process still running?
		do
			if is_started then
				Result := c_sp_is_running (async_handle) /= 0
			end
		end

	has_finished: BOOLEAN
			-- Has the process finished?
		do
			Result := is_started and then not is_running
		ensure
			definition: Result = (is_started and then not is_running)
		end

	was_started_successfully: BOOLEAN
			-- Did the process start without error?
		do
			if is_started then
				Result := c_sp_async_started (async_handle) /= 0
			end
		end

feature -- Settings

	show_window: BOOLEAN
			-- Show process window during execution?

	set_show_window (a_value: BOOLEAN)
			-- Set whether to show process window.
		require
			not_started: not is_started
		do
			show_window := a_value
		ensure
			set: show_window = a_value
		end

feature -- Operations

	start (a_command: READABLE_STRING_GENERAL)
			-- Start process with `a_command'.
			-- Does not wait for completion.
		require
			command_not_empty: not a_command.is_empty
			not_started: not is_started
		do
			start_in_directory (a_command, Void)
		ensure
			started_or_error: is_started or last_error /= Void
		end

	start_in_directory (a_command: READABLE_STRING_GENERAL; a_directory: detachable READABLE_STRING_GENERAL)
			-- Start process with `a_command' in `a_directory'.
			-- Does not wait for completion.
		require
			command_not_empty: not a_command.is_empty
			not_started: not is_started
		local
			l_cmd: C_STRING
			l_dir: detachable C_STRING
			l_now: SIMPLE_DATE_TIME
			l_error_ptr: POINTER
		do
			-- Reset state
			last_error := Void
			accumulated_output.wipe_out
			create l_now.make_now
			start_time := l_now.to_timestamp

			-- Convert strings to C
			create l_cmd.make (a_command.to_string_8)
			if attached a_directory as al_dir then
				create l_dir.make (al_dir.to_string_8)
			end

			-- Start process
			if attached l_dir then
				async_handle := c_sp_start_async (l_cmd.item, l_dir.item, show_window.to_integer)
			else
				async_handle := c_sp_start_async (l_cmd.item, default_pointer, show_window.to_integer)
			end

			-- Check for start errors
			if async_handle /= default_pointer then
				if c_sp_async_started (async_handle) = 0 then
					l_error_ptr := c_sp_async_error (async_handle)
					if l_error_ptr /= default_pointer then
						last_error := pointer_to_string (l_error_ptr)
					else
						last_error := {STRING_32} "Failed to start process"
					end
				end
			else
				last_error := {STRING_32} "Failed to allocate process structure"
			end
		ensure
			started_or_error: is_started or last_error /= Void
		end

	read_available_output: detachable STRING_32
			-- Read any available output (non-blocking).
			-- Returns Void if no output available.
			-- Appends to `accumulated_output'.
		require
			started: is_started
		local
			l_ptr: POINTER
			l_len: INTEGER
			l_managed: MANAGED_POINTER
			l_chunk: STRING_32
		do
			l_ptr := c_sp_read_output (async_handle, $l_len)
			if l_ptr /= default_pointer and l_len > 0 then
				create l_managed.share_from_pointer (l_ptr, l_len)
				l_chunk := utf8_to_string_32 (l_managed, l_len)
				accumulated_output.append (l_chunk)
				Result := l_chunk
				-- Free the returned buffer
				c_free (l_ptr)
			end
		end

	wait (a_timeout_ms: INTEGER): INTEGER
			-- Wait for process to finish with timeout.
			-- Returns: 1 if finished, 0 if timeout, -1 on error.
		require
			started: is_started
			positive_timeout: a_timeout_ms >= 0
		do
			Result := c_sp_wait_timeout (async_handle, a_timeout_ms.to_natural_32)
		ensure
			valid_result: Result >= -1 and Result <= 1
		end

	wait_seconds (a_timeout_seconds: INTEGER): BOOLEAN
			-- Wait for process to finish with timeout in seconds.
			-- Returns True if finished, False if timeout or error.
		require
			started: is_started
			positive_timeout: a_timeout_seconds >= 0
		do
			Result := wait (a_timeout_seconds * 1000) = 1
		end

	kill: BOOLEAN
			-- Kill the running process.
			-- Returns True on success.
		require
			started: is_started
			running: is_running
		do
			Result := c_sp_kill (async_handle) /= 0
		ensure
			still_started: is_started
		end

	close
			-- Close and cleanup process handle.
			-- Must be called when done with process.
		do
			if async_handle /= default_pointer then
				-- Read any remaining output first
				if attached read_available_output then
					-- Output captured
				end
				c_sp_async_close (async_handle)
				async_handle := default_pointer
			end
		ensure
			closed: not is_started
		end

feature {NONE} -- Implementation

	async_handle: POINTER
			-- Handle to async process structure.

	start_time: INTEGER_64
			-- Time when process was started (epoch seconds).

feature {NONE} -- String conversion

	utf8_to_string_32 (a_data: MANAGED_POINTER; a_length: INTEGER): STRING_32
			-- Convert UTF-8 data to STRING_32.
		local
			i: INTEGER
			c: NATURAL_8
		do
			create Result.make (a_length)
			from
				i := 0
			until
				i >= a_length
			loop
				c := a_data.read_natural_8 (i)
				if c /= 0 then
					Result.append_character (c.to_character_32)
				end
				i := i + 1
			end
		end

	pointer_to_string (a_ptr: POINTER): STRING_32
			-- Convert C string pointer to STRING_32.
		local
			l_c_string: C_STRING
		do
			create l_c_string.make_by_pointer (a_ptr)
			Result := l_c_string.string.to_string_32
		end

feature {NONE} -- C externals

	c_sp_start_async (a_command, a_working_dir: POINTER; a_show_window: INTEGER): POINTER
			-- Start async process and return handle.
		external
			"C inline use %"simple_process.h%""
		alias
			"return sp_start_async((const char*)$a_command, (const char*)$a_working_dir, (int)$a_show_window);"
		end

	c_sp_is_running (a_proc: POINTER): INTEGER
			-- Check if process is running.
		external
			"C inline use %"simple_process.h%""
		alias
			"return sp_is_running((sp_async_process*)$a_proc);"
		end

	c_sp_get_pid (a_proc: POINTER): NATURAL_32
			-- Get process ID.
		external
			"C inline use %"simple_process.h%""
		alias
			"return (EIF_NATURAL_32)sp_get_pid((sp_async_process*)$a_proc);"
		end

	c_sp_wait_timeout (a_proc: POINTER; a_timeout_ms: NATURAL_32): INTEGER
			-- Wait with timeout.
		external
			"C inline use %"simple_process.h%""
		alias
			"return sp_wait_timeout((sp_async_process*)$a_proc, (unsigned int)$a_timeout_ms);"
		end

	c_sp_kill (a_proc: POINTER): INTEGER
			-- Kill process.
		external
			"C inline use %"simple_process.h%""
		alias
			"return sp_kill((sp_async_process*)$a_proc);"
		end

	c_sp_get_exit_code (a_proc: POINTER): INTEGER
			-- Get exit code.
		external
			"C inline use %"simple_process.h%""
		alias
			"return sp_get_exit_code((sp_async_process*)$a_proc);"
		end

	c_sp_read_output (a_proc: POINTER; a_len: TYPED_POINTER [INTEGER]): POINTER
			-- Read available output.
		external
			"C inline use %"simple_process.h%""
		alias
			"return sp_read_output((sp_async_process*)$a_proc, (int*)$a_len);"
		end

	c_sp_async_close (a_proc: POINTER)
			-- Close async process handle.
		external
			"C inline use %"simple_process.h%""
		alias
			"sp_async_close((sp_async_process*)$a_proc);"
		end

	c_sp_async_started (a_proc: POINTER): INTEGER
			-- Check if process started successfully.
		external
			"C inline use %"simple_process.h%""
		alias
			"return ((sp_async_process*)$a_proc)->started;"
		end

	c_sp_async_error (a_proc: POINTER): POINTER
			-- Get error message from async process.
		external
			"C inline use %"simple_process.h%""
		alias
			"return ((sp_async_process*)$a_proc)->error_message;"
		end

	c_free (a_ptr: POINTER)
			-- Free C memory.
		external
			"C inline use <stdlib.h>"
		alias
			"free($a_ptr);"
		end

feature -- Model Queries

	output_byte_count: INTEGER
			-- Total bytes of output accumulated.
			-- Model query for tracking output accumulation.
		do
			Result := accumulated_output.count
		ensure
			non_negative: Result >= 0
			consistent: Result = accumulated_output.count
		end

invariant
	output_exists: accumulated_output /= Void
	output_count_consistent: output_byte_count = accumulated_output.count

end