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
			async.start_in_directory ("ec.exe -batch -config lib.ecf -c_compile", "D:\prod\lib")
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
		another processor's allocator. Since 1.1.0 this class runs its
		child through SIMPLE_PIPED_PROCESS, every one of whose waiting
		externals - the start, the bounded wait, the output reads - is
		declared `external "C blocking inline"'. A bounded wait is still a
		wait: unmarked, `wait (120_000)' cost every other processor every
		millisecond the child actually took. See testing/scoop/.

		OUTPUT IS UTF-8 (1.1.0). Output text is decoded as UTF-8
		(SIMPLE_PROCESS_UTF_8); before 1.1.0 every byte became one
		character. A character whose bytes straddle two reads is held back
		until its last byte arrives, so it is never decoded as two broken
		halves. `accumulated_bytes' keeps the raw bytes.

		OUTPUT IS ALWAYS DRAINED (1.1.0). The child's output is collected
		from the moment it starts, so a child whose output is never read no
		longer blocks on a full pipe; what it wrote waits in memory until
		`read_available_output'.

		STDIN AND COMMAND LINE (1.1.0). The child gets an empty stdin unless
		`set_inherits_standard_input (True)' hands it this process's own;
		before 1.1.0 it always got this process's own. Commands and
		directories may hold any characters (CreateProcessW). This class
		cannot write to the child: SIMPLE_PIPED_PROCESS can.

		ENDS WITH ITS OWNER (1.2.0). `set_ends_with_owner (True)' ties the
		child to this program: if the program ends without `kill' - crashed,
		killed from Task Manager - Windows ends the child too, instead of
		leaving it running with its files and devices held.
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
			stdin_empty: not inherits_standard_input
		end

feature -- Access

	process_id: NATURAL_32
			-- Process ID (PID) of running process.
			-- 0 if not started.
		require
			started: is_started
		do
			if attached child as al_child and then al_child.is_started then
				Result := al_child.process_id
			end
		end

	exit_code: INTEGER
			-- Exit code of finished process.
			-- -1 if still running.
		require
			started: is_started
		do
			if attached child as al_child then
				Result := al_child.exit_code
			else
				Result := -1
			end
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
			-- Has `start' been called (successfully or not) since the last `close'?

	is_running: BOOLEAN
			-- Is the process still running?
		do
			Result := attached child as al_child and then al_child.is_running
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
			Result := attached child as al_child and then al_child.is_started
		end

feature -- Settings

	show_window: BOOLEAN
			-- Show process window during execution? (A console child never
			-- gets a console window either way, as before 1.1.0.)

	set_show_window (a_value: BOOLEAN)
			-- Set whether to show process window.
		require
			not_started: not is_started
		do
			show_window := a_value
		ensure
			set: show_window = a_value
		end

	inherits_standard_input: BOOLEAN
			-- Does the child read this process's own stdin? Default False: its
			-- stdin is empty, so a read sees end of file.

	set_inherits_standard_input (a_value: BOOLEAN)
			-- Set `inherits_standard_input' to `a_value'.
		require
			not_started: not is_started
		do
			inherits_standard_input := a_value
		ensure
			set: inherits_standard_input = a_value
		end

	ends_with_owner: BOOLEAN
			-- Does the child end when this program ends, however it ends? (1.2.0;
			-- see SIMPLE_PIPED_PROCESS.ends_with_owner.) Default False.

	set_ends_with_owner (a_value: BOOLEAN)
			-- Set `ends_with_owner' to `a_value'.
		require
			not_started: not is_started
		do
			ends_with_owner := a_value
		ensure
			set: ends_with_owner = a_value
		end

	is_bound_to_owner: BOOLEAN
			-- Did the started child join the owner job?
		do
			Result := attached child as al_child and then al_child.is_bound_to_owner
		ensure
			only_when_asked: Result implies ends_with_owner
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
			-- Start process with `a_command' in `a_directory' (Void or empty:
			-- the current one). Does not wait for completion.
		require
			command_not_empty: not a_command.is_empty
			not_started: not is_started
		local
			l_child: SIMPLE_PIPED_PROCESS
			l_directory: detachable READABLE_STRING_GENERAL
			l_now: SIMPLE_DATE_TIME
		do
			last_error := Void
			accumulated_output.wipe_out
			accumulated_bytes.wipe_out
			undecoded_tail.wipe_out
			create l_now.make_now
			start_time := l_now.to_timestamp

			if attached a_directory as al_dir and then not al_dir.is_empty then
				l_directory := al_dir
			end
			create l_child.make
			l_child.set_show_window (show_window)
			l_child.set_suppresses_console (True)
			l_child.set_inherits_standard_input (inherits_standard_input)
			l_child.set_ends_with_owner (ends_with_owner)
			l_child.start_in_directory (a_command, l_directory)
			if l_child.is_started then
				if l_child.is_input_open then
					l_child.close_input
				end
			elseif attached l_child.last_error as l_reason then
				last_error := l_reason
			else
				last_error := {STRING_32} "Failed to start process"
			end
			child := l_child
			is_started := True
		ensure
			started_or_error: is_started or last_error /= Void
			error_iff_failed: was_started_successfully = (last_error = Void)
		end

	read_available_output: detachable STRING_32
			-- Read any available output (non-blocking).
			-- Returns Void if no output available.
			-- Appends to `accumulated_output' (decoded) and
			-- `accumulated_bytes' (raw). Until the child's output ends, the
			-- bytes of a character not yet complete wait for the next call.
		require
			started: is_started
		local
			l_held, l_ready: INTEGER
			l_chunk: STRING_32
		do
			if attached child as al_child and then al_child.is_started then
				al_child.receive_output
				if not al_child.pending_output.is_empty then
					accumulated_bytes.append (al_child.pending_output)
					undecoded_tail.append (al_child.pending_output)
					al_child.discard_pending_output
				end
				if not al_child.is_output_ended then
					l_held := utf_8.unfinished_tail_count (undecoded_tail)
				end
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
			if attached child as al_child and then al_child.is_started then
				al_child.wait_for_exit (a_timeout_ms)
				if al_child.has_exited then
					Result := 1
				end
			else
				Result := -1
			end
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
			if attached child as al_child and then al_child.is_started then
				al_child.kill
				Result := True
			end
		ensure
			still_started: is_started
		end

	close
			-- Close and cleanup process handle.
			-- Must be called when done with process.
			-- Does not kill a child that is still running.
		do
			if is_started then
				-- Read any remaining output first
				if attached read_available_output then
					-- Output captured
				end
				-- What the child wrote is all there is now.
				if not undecoded_tail.is_empty then
					accumulated_output.append (utf_8.text (undecoded_tail))
					undecoded_tail.wipe_out
				end
				if attached child as al_child then
					al_child.close
				end
				child := Void
				is_started := False
			end
		ensure
			closed: not is_started
		end

feature {NONE} -- Implementation

	child: detachable SIMPLE_PIPED_PROCESS
			-- The child, from `start' to `close'.

	start_time: INTEGER_64
			-- Time when process was started (epoch seconds).

	undecoded_tail: STRING_8
			-- Bytes read but not yet decoded: at most the start of one
			-- character whose remaining bytes have not arrived.

	utf_8: SIMPLE_PROCESS_UTF_8
			-- The codec.
		once
			create Result
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
	child_while_started: is_started implies attached child

end
