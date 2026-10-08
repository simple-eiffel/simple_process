note
	description: "[
		A child process with its standard input, output and error all
		piped (1.1.0): start it, write to its stdin, close its stdin
		(the child reads EOF), and read what it writes - as raw bytes or
		as UTF-8 text - for as long as it lives.

		    l_child: SIMPLE_PIPED_PROCESS
		    create l_child.make
		    l_child.start ("helper.exe")
		    if l_child.is_started then
		        l_child.write_line ({STRING_32} "{%"id%":1}")
		        l_child.read_line (5_000)
		        if attached l_child.last_line as l_reply then ... end
		        l_child.close_input
		        l_child.wait_for_exit (5_000)
		        l_child.close
		    end

		For one-shot "run this with this input and give me the output",
		use SIMPLE_PROCESS.execute_with_input, which is built on this.

		NO PIPE DEADLOCK. A parent that writes a large input while the
		child writes a large output can deadlock: the child blocks on a
		full stdout pipe and stops reading its stdin, and the parent
		blocks on a full stdin pipe and never reads stdout. Here each
		output stream is drained from the moment the child starts, by
		its own C thread, into a C-heap buffer that grows as needed. The
		child can always finish a write, so `write_bytes' of any size
		completes as long as the child keeps reading its input. What the
		threads collected waits until `receive_output', `await_output',
		`read_line' or `close' moves it into `pending_output' and
		`pending_error'.

		TEXT. Output text is decoded as UTF-8 (SIMPLE_PROCESS_UTF_8: a
		byte that starts no well-formed sequence reads as Latin-1, NUL is
		dropped). `write_text' and `write_line' encode as UTF-8. The
		bytes are always available raw: `pending_output',
		`last_line_bytes', `write_bytes'.

		THE GUARANTEE (1.0.1, kept). Every external here that can wait -
		CreateProcess, a write to stdin, the waits for output and for
		exit, joining the pump threads, and every call that takes the
		lock the pump threads share - is `external "C blocking inline"',
		and touches only C-heap memory: the command line and directory
		are NATIVE_STRINGs, data crosses in C_STRINGs and
		MANAGED_POINTERs, and the process record is malloc'd by the C
		side. A processor waiting here never stops another processor's
		allocator. testing/scoop/ proves it.

		The child inherits exactly its own three pipe ends
		(PROC_THREAD_ATTRIBUTE_HANDLE_LIST) and nothing else this
		process has open.

		`close' must be called when done; it does not kill a child that
		is still running (`kill' does).

		Windows only. On other platforms `start' fails with a
		`last_error' that says so.
	]"
	author: "Larry Rix"
	date: "$Date$"
	revision: "$Revision$"

class
	SIMPLE_PIPED_PROCESS

create
	make

feature {NONE} -- Initialization

	make
			-- A piped process that has not been started.
		do
			create pending_output.make_empty
			create pending_error.make_empty
			merge_error_output := True
			final_exit_code := -1
		ensure
			not_started: not is_started
			nothing_pending: pending_output.is_empty and pending_error.is_empty
			window_hidden: not show_window
			error_merged: merge_error_output
		end

feature -- Constants

	Infinite: INTEGER = -1
			-- A timeout that never expires.

feature -- Settings

	show_window: BOOLEAN
			-- Give the child a visible window? (Default: hidden, and a
			-- console child gets no console window at all.)

	set_show_window (a_value: BOOLEAN)
			-- Set `show_window' to `a_value'.
		require
			not_started: not is_started
		do
			show_window := a_value
		ensure
			set: show_window = a_value
		end

	merge_error_output: BOOLEAN
			-- Does the child's stderr go into the same pipe as its stdout
			-- (into `pending_output'), as SIMPLE_PROCESS does? When False it
			-- collects separately into `pending_error' - what a protocol over
			-- stdout needs, so diagnostics cannot corrupt it. Default True.

	set_merge_error_output (a_value: BOOLEAN)
			-- Set `merge_error_output' to `a_value'.
		require
			not_started: not is_started
		do
			merge_error_output := a_value
		ensure
			set: merge_error_output = a_value
		end

feature -- Status report

	is_started: BOOLEAN
			-- Is a child running or finished under this object, not yet `close'd?
		do
			Result := handle /= default_pointer
		end

	is_running: BOOLEAN
			-- Is the child still running? Never waits.
		do
			Result := is_started and then c_is_running (handle) /= 0
		ensure
			only_when_started: Result implies is_started
		end

	has_exited: BOOLEAN
			-- Has the child exited (and not yet been `close'd)?
		do
			Result := is_started and then not is_running
		end

	is_input_open: BOOLEAN
			-- Can the child still be written to? False once `close_input'.
		do
			Result := is_started and then c_input_open (handle) /= 0
		ensure
			only_when_started: Result implies is_started
		end

	is_output_ended: BOOLEAN
			-- Has every output stream reached its end with every byte moved
			-- into `pending_output' / `pending_error'? Always True when not started.
		do
			Result := not is_started or else
				(c_drained (handle, Stdout_stream) /= 0 and c_drained (handle, Stderr_stream) /= 0)
		end

	were_bytes_lost: BOOLEAN
			-- Did a pump thread run out of memory and drop output?
		do
			Result := is_started and then c_lost (handle) /= 0
		end

	last_write_succeeded: BOOLEAN
			-- Did the last `write_bytes', `write_text' or `write_line' deliver
			-- every byte? False when the child exited or closed its stdin.

	last_error: detachable STRING_32
			-- Why the last `start' failed; Void after a successful start.

feature -- Access

	process_id: NATURAL_32
			-- The child's PID.
		require
			started: is_started
		do
			Result := c_pid (handle)
		end

	exit_code: INTEGER
			-- The child's exit code; -1 while it runs or when unknown.
			-- Still answers after `close' if the child had exited by then.
		do
			if is_started then
				Result := c_exit_code (handle)
			else
				Result := final_exit_code
			end
		end

	pending_output: STRING_8
			-- Raw bytes the child wrote to stdout (and to stderr, when
			-- `merge_error_output'), received and not yet consumed by
			-- `read_line' or `discard_pending_output'.

	pending_error: STRING_8
			-- Raw bytes the child wrote to stderr, when not `merge_error_output'.

	pending_output_text: STRING_32
			-- `pending_output' decoded as UTF-8.
		do
			Result := utf_8.text (pending_output)
		end

	pending_error_text: STRING_32
			-- `pending_error' decoded as UTF-8.
		do
			Result := utf_8.text (pending_error)
		end

	last_line: detachable STRING_32
			-- The line the last `read_line' took, UTF-8 decoded, without its
			-- line end; Void when it found none.

	last_line_bytes: detachable STRING_8
			-- The same line as raw bytes.

feature -- Basic operations: start

	start (a_command: READABLE_STRING_GENERAL)
			-- Start `a_command' in the current directory. Does not wait.
		require
			command_not_empty: not a_command.is_empty
			not_started: not is_started
		do
			start_in_directory (a_command, Void)
		ensure
			started_or_error: is_started = (last_error = Void)
		end

	start_in_directory (a_command: READABLE_STRING_GENERAL; a_directory: detachable READABLE_STRING_GENERAL)
			-- Start `a_command' in `a_directory' (Void: the current one). Does
			-- not wait. The command and directory may hold any characters.
		require
			command_not_empty: not a_command.is_empty
			not_started: not is_started
			directory_not_empty: attached a_directory as al_dir implies not al_dir.is_empty
		local
			l_command: NATIVE_STRING
			l_directory: detachable NATIVE_STRING
			l_record: POINTER
			l_reason: STRING_32
		do
			last_error := Void
			last_line := Void
			last_line_bytes := Void
			final_exit_code := -1
			create l_command.make (a_command)
			if attached a_directory as al_dir then
				create l_directory.make (al_dir)
			end
			if attached l_directory as al_native then
				l_record := c_start (l_command.item, al_native.item, show_window.to_integer, merge_error_output.to_integer)
			else
				l_record := c_start (l_command.item, default_pointer, show_window.to_integer, merge_error_output.to_integer)
			end
			if l_record = default_pointer then
				last_error := {STRING_32} "Failed to allocate the process record"
			elseif c_started (l_record) /= 0 then
				handle := l_record
			else
				l_reason := utf_8.text ((create {C_STRING}.make_by_pointer (c_error (l_record))).string)
				if l_reason.is_empty then
					l_reason := {STRING_32} "Failed to start process"
				end
				last_error := l_reason
				c_close (l_record)
			end
		ensure
			started_or_error: is_started = (last_error = Void)
		end

feature -- Basic operations: input

	write_bytes (a_bytes: READABLE_STRING_8)
			-- Write `a_bytes' to the child's stdin, exactly as they are.
			-- Waits while the pipe is full; never deadlocks against the
			-- child's output (see the class note).
		require
			input_open: is_input_open
		local
			l_data: C_STRING
		do
			if a_bytes.is_empty then
				last_write_succeeded := True
			else
				create l_data.make (a_bytes)
				last_write_succeeded := c_write (handle, l_data.item, a_bytes.count) /= 0
			end
		end

	write_text (a_text: READABLE_STRING_GENERAL)
			-- Write `a_text' to the child's stdin as UTF-8. (A STRING_8 is
			-- taken as characters, not as bytes: use `write_bytes' for bytes.)
		require
			input_open: is_input_open
		do
			write_bytes (utf_8.bytes (a_text))
		end

	write_line (a_text: READABLE_STRING_GENERAL)
			-- Write `a_text' and a LF to the child's stdin as UTF-8.
		require
			input_open: is_input_open
		local
			l_bytes: STRING_8
		do
			l_bytes := utf_8.bytes (a_text)
			l_bytes.append_character ('%N')
			write_bytes (l_bytes)
		end

	close_input
			-- Close the child's stdin: it reads end of file.
		require
			started: is_started
		do
			c_close_input (handle)
		ensure
			closed: not is_input_open
		end

feature -- Basic operations: output

	receive_output
			-- Move every byte collected so far into `pending_output' and
			-- `pending_error'. Never waits for the child.
		require
			started: is_started
		do
			receive_stream (Stdout_stream, pending_output)
			receive_stream (Stderr_stream, pending_error)
		ensure
			output_kept: pending_output.count >= old pending_output.count
			error_kept: pending_error.count >= old pending_error.count
		end

	await_output (a_timeout_ms: INTEGER)
			-- Wait up to `a_timeout_ms' (or `Infinite') until the child has
			-- written something or every output stream has ended; then
			-- `receive_output'.
		require
			started: is_started
			valid_timeout: a_timeout_ms >= 0 or a_timeout_ms = Infinite
		do
			if c_await (handle, Await_any, a_timeout_ms) = 0 then
				-- Timed out; take whatever there is anyway.
			end
			receive_output
		end

	await_output_end (a_timeout_ms: INTEGER)
			-- Wait up to `a_timeout_ms' (or `Infinite') until every output
			-- stream has ended - the child and anything it started have
			-- closed them, normally by exiting - then `receive_output'.
		require
			started: is_started
			valid_timeout: a_timeout_ms >= 0 or a_timeout_ms = Infinite
		do
			if c_await (handle, Await_end, a_timeout_ms) = 0 then
				-- Timed out; take whatever there is anyway.
			end
			receive_output
		end

	read_line (a_timeout_ms: INTEGER)
			-- Take the next line from `pending_output' into `last_line' and
			-- `last_line_bytes', without its LF or CR LF, waiting up to
			-- `a_timeout_ms' (or `Infinite') for the child to finish one.
			-- When stdout has ended, a last line without a line end is taken
			-- as it is. Void when no line came in time.
		require
			valid_timeout: a_timeout_ms >= 0 or a_timeout_ms = Infinite
		local
			l_index: INTEGER
		do
			last_line := Void
			last_line_bytes := Void
			if is_started and then not pending_output.has ('%N') then
				receive_output
				if not pending_output.has ('%N') then
					if c_await (handle, Await_line, a_timeout_ms) = 0 then
						-- Timed out; a line may still have arrived since.
					end
					receive_output
				end
			end
			l_index := pending_output.index_of ('%N', 1)
			if l_index > 0 then
				take_line (l_index - 1, l_index)
			elseif not pending_output.is_empty and then
				(not is_started or else c_drained (handle, Stdout_stream) /= 0)
			then
				take_line (pending_output.count, pending_output.count)
			end
		ensure
			both_or_neither: (last_line = Void) = (last_line_bytes = Void)
		end

	discard_pending_output
			-- Empty `pending_output' and `pending_error'.
		do
			pending_output.wipe_out
			pending_error.wipe_out
		ensure
			output_empty: pending_output.is_empty
			error_empty: pending_error.is_empty
		end

feature -- Basic operations: lifetime

	wait_for_exit (a_timeout_ms: INTEGER)
			-- Wait up to `a_timeout_ms' (or `Infinite') for the child to exit.
			-- Output keeps being collected meanwhile, so a chatty child
			-- cannot block on a full pipe while this waits.
		require
			started: is_started
			valid_timeout: a_timeout_ms >= 0 or a_timeout_ms = Infinite
		do
			if c_wait_exit (handle, a_timeout_ms) = 0 then
				-- Timed out: `has_exited' says so.
			end
		end

	kill
			-- Terminate the child (exit code 1) if it is still running.
		require
			started: is_started
		do
			if c_kill (handle) = 0 then
				-- It had already exited.
			end
		end

	close
			-- Close the child's stdin, receive whatever it wrote, and release
			-- the pipes, pump threads and handles. Does not kill a child that
			-- is still running. `pending_output', `pending_error' and
			-- `exit_code' stay readable.
		do
			if is_started then
				receive_output
				final_exit_code := c_exit_code (handle)
				c_close (handle)
				handle := default_pointer
			end
		ensure
			closed: not is_started
		end

feature {NONE} -- Implementation

	handle: POINTER
			-- The C-side process record (spp_process*).

	final_exit_code: INTEGER
			-- `exit_code' as it was at `close'.

	utf_8: SIMPLE_PROCESS_UTF_8
			-- The codec.
		once
			create Result
		end

	receive_stream (a_which: INTEGER; a_into: STRING_8)
			-- Append every collected byte of stream `a_which' to `a_into'.
		require
			started: is_started
		local
			l_available, l_taken: INTEGER
			l_buffer: MANAGED_POINTER
			l_bytes: STRING_8
		do
			l_available := c_available (handle, a_which)
			if l_available > 0 then
				create l_buffer.make (l_available)
				l_taken := c_take (handle, a_which, l_buffer.item, l_available)
				if l_taken > 0 then
					create l_bytes.make_from_c_byte_array (l_buffer.item, l_taken)
					a_into.append (l_bytes)
				end
			end
		ensure
			kept: a_into.count >= old a_into.count
		end

	take_line (a_line_count, a_consumed: INTEGER)
			-- Take the first `a_line_count' bytes of `pending_output' as the
			-- line (less a final CR) and remove the first `a_consumed'.
		require
			valid_counts: 0 <= a_line_count and a_line_count <= a_consumed and a_consumed <= pending_output.count
		local
			l_bytes: STRING_8
		do
			l_bytes := pending_output.substring (1, a_line_count)
			if not l_bytes.is_empty and then l_bytes [l_bytes.count] = '%R' then
				l_bytes.remove_tail (1)
			end
			pending_output.remove_head (a_consumed)
			last_line_bytes := l_bytes
			last_line := utf_8.text (l_bytes)
		ensure
			taken: pending_output.count = old pending_output.count - a_consumed
			line_set: attached last_line and attached last_line_bytes
		end

	Stdout_stream: INTEGER = 1
	Stderr_stream: INTEGER = 2
			-- Stream selectors (SPP_STDOUT, SPP_STDERR).

	Await_any: INTEGER = 1
	Await_line: INTEGER = 2
	Await_end: INTEGER = 3
			-- Wait conditions (SPP_AWAIT_ANY, SPP_AWAIT_LINE, SPP_AWAIT_END).

feature {NONE} -- C externals: waiting (marked `blocking')

	c_start (a_command, a_directory: POINTER; a_show_window, a_merge_error: INTEGER): POINTER
			-- Create the pipes, start the child, start the pump threads.
			--
			-- BLOCKING: CreateProcess maps an image, and an anti-virus filter
			-- may scan it first. Safe to mark: both strings are NATIVE_STRING
			-- buffers (MANAGED_POINTER, C heap) and the result is malloc'd.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"return spp_start((void*)$a_command, (void*)$a_directory, (int)$a_show_window, (int)$a_merge_error);"
		end

	c_write (a_record, a_data: POINTER; a_count: INTEGER): INTEGER
			-- Write all `a_count' bytes at `a_data' to the child's stdin.
			--
			-- BLOCKING: WriteFile waits while the pipe is full, for as long as
			-- the child takes to read. Safe to mark: `a_data' is a C_STRING
			-- buffer on the C heap.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"return spp_write((spp_process*)$a_record, (const char*)$a_data, (int)$a_count);"
		end

	c_close_input (a_record: POINTER)
			-- Close the child's stdin.
			--
			-- BLOCKING: a kernel call on a pipe; marked so no pipe operation
			-- of this class is unmarked. Touches no Eiffel memory.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"spp_close_input((spp_process*)$a_record);"
		end

	c_await (a_record: POINTER; a_mode, a_timeout_ms: INTEGER): INTEGER
			-- Wait for condition `a_mode' (1 any, 2 line, 3 end) up to `a_timeout_ms'.
			--
			-- BLOCKING: WaitForSingleObject on the pumps' event, for up to the
			-- whole timeout. Touches no Eiffel memory.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"return spp_await((spp_process*)$a_record, (int)$a_mode, (int)$a_timeout_ms);"
		end

	c_wait_exit (a_record: POINTER; a_timeout_ms: INTEGER): INTEGER
			-- Wait for the child to exit, up to `a_timeout_ms'.
			--
			-- BLOCKING: WaitForSingleObject on the process. Touches no Eiffel memory.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"return spp_wait_exit((spp_process*)$a_record, (int)$a_timeout_ms);"
		end

	c_close (a_record: POINTER)
			-- Close stdin, join the pump threads, free the record.
			--
			-- BLOCKING: joining a pump waits for its ReadFile to be cancelled.
			-- Touches no Eiffel memory.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"spp_close((spp_process*)$a_record);"
		end

	c_available (a_record: POINTER; a_which: INTEGER): INTEGER
			-- Bytes of stream `a_which' collected and not yet taken.
			--
			-- BLOCKING: takes the lock the pump threads hold while they copy a
			-- chunk in. Touches no Eiffel memory.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"return spp_available((spp_process*)$a_record, (int)$a_which);"
		end

	c_take (a_record: POINTER; a_which: INTEGER; a_buffer: POINTER; a_capacity: INTEGER): INTEGER
			-- Move up to `a_capacity' collected bytes of stream `a_which' to `a_buffer'.
			--
			-- BLOCKING: takes the pumps' lock. Safe to mark: `a_buffer' is a
			-- MANAGED_POINTER on the C heap.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"return spp_take((spp_process*)$a_record, (int)$a_which, (char*)$a_buffer, (int)$a_capacity);"
		end

	c_drained (a_record: POINTER; a_which: INTEGER): INTEGER
			-- Has stream `a_which' ended with every byte taken?
			--
			-- BLOCKING: takes the pumps' lock. Touches no Eiffel memory.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"return spp_drained((spp_process*)$a_record, (int)$a_which);"
		end

	c_lost (a_record: POINTER): INTEGER
			-- Did a pump drop bytes?
			--
			-- BLOCKING: takes the pumps' lock. Touches no Eiffel memory.
		external
			"C blocking inline use %"simple_process_pipe.h%""
		alias
			"return spp_lost((spp_process*)$a_record);"
		end

feature {NONE} -- C externals: never waiting (unmarked)

	c_started (a_record: POINTER): INTEGER
			-- Did the start succeed? A field read.
		external
			"C inline use %"simple_process_pipe.h%""
		alias
			"return spp_started((spp_process*)$a_record);"
		end

	c_error (a_record: POINTER): POINTER
			-- The UTF-8 reason a start failed. A field address.
		external
			"C inline use %"simple_process_pipe.h%""
		alias
			"return (EIF_POINTER) spp_error((spp_process*)$a_record);"
		end

	c_pid (a_record: POINTER): NATURAL_32
			-- The child's PID. A field read.
		external
			"C inline use %"simple_process_pipe.h%""
		alias
			"return (EIF_NATURAL_32) spp_pid((spp_process*)$a_record);"
		end

	c_input_open (a_record: POINTER): INTEGER
			-- Is stdin still open? A field read.
		external
			"C inline use %"simple_process_pipe.h%""
		alias
			"return spp_input_open((spp_process*)$a_record);"
		end

	c_is_running (a_record: POINTER): INTEGER
			-- Is the child running? A zero-timeout WaitForSingleObject.
		external
			"C inline use %"simple_process_pipe.h%""
		alias
			"return spp_is_running((spp_process*)$a_record);"
		end

	c_exit_code (a_record: POINTER): INTEGER
			-- Exit code or -1. A zero-timeout wait and GetExitCodeProcess.
		external
			"C inline use %"simple_process_pipe.h%""
		alias
			"return spp_exit_code((spp_process*)$a_record);"
		end

	c_kill (a_record: POINTER): INTEGER
			-- TerminateProcess, which does not wait for the child to die.
		external
			"C inline use %"simple_process_pipe.h%""
		alias
			"return spp_kill((spp_process*)$a_record);"
		end

invariant
	output_exists: pending_output /= Void
	error_exists: pending_error /= Void
	line_forms_agree: (last_line = Void) = (last_line_bytes = Void)

end
