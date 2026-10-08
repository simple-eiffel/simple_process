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

		THE GUARANTEE (1.0.1). A child process monitored here never stops
		another processor's allocator. `c_sp_start_async',
		`c_sp_wait_timeout' and `c_sp_read_output' each sit in the kernel,
		and each is declared `external "C blocking inline"' so ISE's
		garbage collector can collect while they do. A bounded wait is
		still a wait: unmarked, `wait (120_000)' cost every other
		processor every millisecond the child actually took. See
		testing/scoop/ for the assault that proves it.

		OUTPUT IS UTF-8 (1.1.0). Output text is decoded as UTF-8
		(SIMPLE_PROCESS_UTF_8); before 1.1.0 every byte became one
		character. A character whose bytes straddle two reads is held back
		until its last byte arrives, so it is never decoded as two broken
		halves. `accumulated_bytes' keeps the raw bytes. This class still
		cannot write to the child: SIMPLE_PIPED_PROCESS can.
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
			create accumulated_bytes.make_empty
			create undecoded_tail.make_empty
		ensure
			not_started: not is_started
			no_output: accumulated_output.is_empty
			no_bytes: accumulated_bytes.is_empty
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
			-- All output read so far, decoded as UTF-8.

	accumulated_bytes: STRING_8
			-- All output read so far, as the raw bytes the child wrote.

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
			accumulated_bytes.wipe_out
			undecoded_tail.wipe_out
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
			-- Appends to `accumulated_output' (decoded) and
			-- `accumulated_bytes' (raw). While the child runs, the bytes of
			-- a character not yet complete wait for the next call.
		require
			started: is_started
		local
			l_ptr: POINTER
			l_len: INTEGER
			l_was_running: BOOLEAN
			l_held, l_ready: INTEGER
			l_chunk: STRING_32
		do
				-- Sampled BEFORE the read: a child that had already exited
				-- has written everything, so this read gets all of it and no
				-- unfinished character can still be completed.
			l_was_running := is_running
			l_ptr := c_sp_read_output (async_handle, $l_len)
			if l_ptr /= default_pointer then
				if l_len > 0 then
					append_raw (l_ptr, l_len)
				end
				-- Free the returned buffer
				c_free (l_ptr)
			end
			if l_was_running then
				l_held := utf_8.unfinished_tail_count (undecoded_tail)
			end
			l_ready := undecoded_tail.count - l_held
			if l_ready > 0 then
				l_chunk := utf_8.text (undecoded_tail.substring (1, l_ready))
				undecoded_tail.remove_head (l_ready)
				accumulated_output.append (l_chunk)
				if not l_chunk.is_empty then
					Result := l_chunk
				end
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
				-- The child may still run: what it wrote is all there is.
				if not undecoded_tail.is_empty then
					accumulated_output.append (utf_8.text (undecoded_tail))
					undecoded_tail.wipe_out
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

	undecoded_tail: STRING_8
			-- Bytes read but not yet decoded: at most the start of one
			-- character whose remaining bytes have not arrived.

	append_raw (a_ptr: POINTER; a_count: INTEGER)
			-- Append the `a_count' bytes at `a_ptr' to `accumulated_bytes'
			-- and `undecoded_tail'.
		require
			pointer_valid: a_ptr /= default_pointer
			positive: a_count > 0
		local
			l_bytes: STRING_8
		do
			create l_bytes.make_from_c_byte_array (a_ptr, a_count)
			accumulated_bytes.append (l_bytes)
			undecoded_tail.append (l_bytes)
		ensure
			bytes_kept: accumulated_bytes.count = old accumulated_bytes.count + a_count
		end

feature {NONE} -- String conversion

	utf_8: SIMPLE_PROCESS_UTF_8
			-- The codec.
		once
			create Result
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
			--
			-- BLOCKING. CreateProcess is not instant: the loader maps an image,
			-- and an anti-virus filter driver can scan it first. Tens to hundreds
			-- of milliseconds is normal, and every one of them was a millisecond
			-- no other processor could allocate in.
			--
			-- Safe to mark: both string arguments are C_STRING buffers on the C
			-- heap, and the result is a malloc'd sp_async_process read only after
			-- the call returns.
		external
			"C blocking inline use %"simple_process.h%""
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
			--
			-- BLOCKING. A bounded wait is still a wait: WaitForSingleObject sits
			-- in the kernel for however much of `a_timeout_ms' the child actually
			-- takes, and callers pass whole minutes.
			--
			-- Safe to mark: `a_proc' is a malloc'd structure this library owns and
			-- `a_timeout_ms' is a value, so nothing Eiffel-collected is touched.
		external
			"C blocking inline use %"simple_process.h%""
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
			--
			-- BLOCKING. Each ReadFile is guarded by PeekNamedPipe, but the loop
			-- keeps reading for as long as a chatty child keeps writing, and a
			-- pipe read is a kernel call either way.
			--
			-- Safe to mark: `a_len' is the address of a LOCAL INTEGER of the sole
			-- caller, `read_available_output', which lives in that routine's own C
			-- stack frame - never the address of an attribute in an object the
			-- collector may move. `a_proc' is a malloc'd structure this library
			-- owns, and the returned buffer is malloc'd and read after the return.
		external
			"C blocking inline use %"simple_process.h%""
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
	bytes_exist: accumulated_bytes /= Void
	tail_is_one_character_at_most: undecoded_tail.count <= 3

end