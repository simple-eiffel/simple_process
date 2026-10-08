note
	description: "[
		A processor whose whole job is to sit inside this library while a
		child process lives - the role simple_chat's server plays every
		time it shells out to `claude -p', reduced to the one thing that
		matters.

		It takes only integers across the processor boundary: the command
		it runs is its own constant, and the SIMPLE_PROCESS /
		SIMPLE_ASYNC_PROCESS it drives are created here, on this
		processor.

		`run_commands' is the synchronous path - SIMPLE_PROCESS.execute,
		which drains the child's stdout and then waits on the process
		handle with no timeout at all.

		`run_async_waits' is the asynchronous path - SIMPLE_ASYNC_PROCESS
		.start, .wait and .read_available_output, three more externals
		that can each sit in the kernel while the caller's processor is
		held.
	]"
	author: "Larry Rix"

class
	PROCESS_CALLER

inherit
	PRECISE_CLOCK

create
	make

feature {NONE} -- Initialization

	make
			-- A caller that has run nothing.
		do
		ensure
			nothing_attempted: attempted = 0
			nothing_completed: completed = 0
			nothing_spent: elapsed_milliseconds = 0
			not_finished: not is_finished
		end

feature -- Access

	attempted: INTEGER
			-- Child processes this caller started.

	completed: INTEGER
			-- Child processes that ran to completion.

	with_output: INTEGER
			-- Child processes whose stdout came back non-empty, so the
			-- assault can prove a real pipe was drained and not a fast
			-- failure mistaken for a run.

	elapsed_milliseconds: INTEGER_64
			-- Wall-clock time the whole run spent.

feature -- Status report

	is_finished: BOOLEAN
			-- Has the run reached its end? (Querying this joins the caller.)

feature -- Basic operations

	run_commands (a_count: INTEGER)
			-- `a_count' synchronous SIMPLE_PROCESS executions of a child
			-- that lives about `Child_life_ms'. Each one holds this
			-- processor inside `c_sp_execute_command' for the child's
			-- whole life.
		require
			positive: a_count > 0
		local
			l_process: SIMPLE_PROCESS
			i: INTEGER
			t0: INTEGER_64
		do
			t0 := now_ms
			create l_process.make
			from
				i := 1
			until
				i > a_count
			loop
				attempted := attempted + 1
				l_process.execute (Slow_command)
				if l_process.was_successful then
					completed := completed + 1
					if attached l_process.last_output as l_out and then not l_out.is_empty then
						with_output := with_output + 1
					end
				end
				i := i + 1
			variant
				a_count + 1 - i
			end
			elapsed_milliseconds := now_ms - t0
			is_finished := True
		ensure
			finished: is_finished
			all_attempted: attempted = old attempted + a_count
			timed: elapsed_milliseconds >= 0
		end

	run_async_waits (a_count: INTEGER)
			-- `a_count' SIMPLE_ASYNC_PROCESS runs, each joined through
			-- `wait' - the bounded WaitForSingleObject. Bounded is not the
			-- same as short: the bound here is `Async_wait_ms', and an
			-- unmarked wait costs the other processors every millisecond
			-- of it that it actually spends.
		require
			positive: a_count > 0
		local
			l_async: SIMPLE_ASYNC_PROCESS
			i: INTEGER
			t0: INTEGER_64
		do
			t0 := now_ms
			from
				i := 1
			until
				i > a_count
			loop
				attempted := attempted + 1
				create l_async.make
				l_async.start (Slow_command)
				if l_async.is_started and then l_async.was_started_successfully then
					if l_async.wait (Async_wait_ms) = 1 then
						completed := completed + 1
					end
					if attached l_async.read_available_output as l_out and then not l_out.is_empty then
						with_output := with_output + 1
					end
					l_async.close
				end
				i := i + 1
			variant
				a_count + 1 - i
			end
			elapsed_milliseconds := now_ms - t0
			is_finished := True
		ensure
			finished: is_finished
			all_attempted: attempted = old attempted + a_count
			timed: elapsed_milliseconds >= 0
		end

	run_commands_with_input (a_count: INTEGER)
			-- `a_count' SIMPLE_PROCESS.execute_with_input runs (1.1.0) of the
			-- slow child: CreateProcessW, a stdin write, closing stdin, the
			-- wait for the output to end and the wait for exit - each a
			-- `blocking' external of SIMPLE_PIPED_PROCESS.
		require
			positive: a_count > 0
		local
			l_process: SIMPLE_PROCESS
			i: INTEGER
			t0: INTEGER_64
		do
			t0 := now_ms
			create l_process.make
			from
				i := 1
			until
				i > a_count
			loop
				attempted := attempted + 1
				l_process.execute_with_input (Slow_command, {STRING_32} "input the child ignores%N")
				if l_process.was_successful then
					completed := completed + 1
					if attached l_process.last_output as l_out and then l_out.has_substring ("slept") then
						with_output := with_output + 1
					end
				end
				i := i + 1
			variant
				a_count + 1 - i
			end
			elapsed_milliseconds := now_ms - t0
			is_finished := True
		ensure
			finished: is_finished
			all_attempted: attempted = old attempted + a_count
			timed: elapsed_milliseconds >= 0
		end

	run_piped_line_waits (a_count: INTEGER)
			-- `a_count' SIMPLE_PIPED_PROCESS runs (1.1.0), each sitting in
			-- `read_line' - the pumps' event wait - for the whole three
			-- seconds the child takes to print its one line.
		require
			positive: a_count > 0
		local
			l_child: SIMPLE_PIPED_PROCESS
			i: INTEGER
			t0: INTEGER_64
		do
			t0 := now_ms
			from
				i := 1
			until
				i > a_count
			loop
				attempted := attempted + 1
				create l_child.make
				l_child.start (Slow_command)
				if l_child.is_started then
					l_child.close_input
					l_child.read_line (Async_wait_ms)
					if attached l_child.last_line as l_line and then l_line.has_substring ("slept") then
						with_output := with_output + 1
					end
					l_child.wait_for_exit (Async_wait_ms)
					if l_child.has_exited then
						completed := completed + 1
					end
					l_child.close
				end
				i := i + 1
			variant
				a_count + 1 - i
			end
			elapsed_milliseconds := now_ms - t0
			is_finished := True
		ensure
			finished: is_finished
			all_attempted: attempted = old attempted + a_count
			timed: elapsed_milliseconds >= 0
		end

feature -- Constants

	Slow_command: STRING_8 = "powershell -NoProfile -NonInteractive -Command Start-Sleep -Seconds 3; Write-Output slept"
			-- A child that lives about three seconds and then prints one
			-- word, so the run can be told from a failure to start.
			--
			-- Windows PowerShell 5.1 ships with every supported Windows and
			-- its directory is on the default PATH, which `ping -n 4' cannot
			-- claim on a machine whose PATH has been trimmed, and `timeout
			-- /t' cannot claim at all with stdout redirected.

	Child_life_ms: INTEGER = 3_000
			-- How long the child sleeps. Its startup adds a little more,
			-- which only makes the wait longer, never shorter.

	Async_wait_ms: INTEGER = 15_000
			-- The timeout handed to `wait'. Far over the child's life, so a
			-- timeout here means a real defect and not a slow machine.

feature -- Status report

	has_run_everything (a_count: INTEGER): BOOLEAN
			-- Did every one of `a_count' children run and print?
		do
			Result := attempted = a_count and completed = a_count and with_output = a_count
		end

invariant
	non_negative: attempted >= 0 and completed >= 0 and with_output >= 0
	non_negative_elapsed: elapsed_milliseconds >= 0
	completed_within_attempted: completed <= attempted
	output_within_attempted: with_output <= attempted

end
