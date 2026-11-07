note
	description: "[
		A processor that does nothing but wait, three ways, so the law
		behind the `blocking' marker can be measured rather than argued.

		ISE's garbage collector stops every thread of the system before
		it collects. A thread that is inside a plain `external "C inline"'
		call is where the runtime cannot see it and cannot stop it, so
		the collection WAITS for that call to return - and every other
		processor waits with it, at its very next allocation.

		  `run_eiffel_sleeps'     EXECUTION_ENVIRONMENT.sleep, which is
		                          itself marked `C blocking' in EiffelBase.
		                          Costs the other processors nothing.
		  `run_unmarked_c_sleeps' a plain `external "C inline"' Sleep -
		                          the shape SIMPLE_PROCESS.c_sp_execute_command
		                          had before 1.0.1. Costs every other
		                          processor the whole wait.
		  `run_blocking_c_sleeps' the SAME Sleep, marked
		                          `external "C blocking inline"'. Costs
		                          them nothing again. This is the fix, in
		                          one keyword.

		The three of them together are why every waiting external in this
		library is marked: running a child process to completion IS a wait,
		and an unmarked wait is a stop-the-world.
	]"
	author: "Larry Rix"

class
	BLOCKING_PROBE

create
	make

feature {NONE} -- Initialization

	make
			-- A probe that has waited for nothing yet.
		do
		ensure
			nothing_waited: waits_done = 0
		end

feature -- Access

	waits_done: INTEGER
			-- Waits completed so far.

feature -- Basic operations

	run_eiffel_sleeps (a_count, a_milliseconds: INTEGER)
			-- `a_count' waits of `a_milliseconds' through EXECUTION_ENVIRONMENT.
		require
			positive: a_count > 0 and a_milliseconds > 0
		local
			l_env: EXECUTION_ENVIRONMENT
			i: INTEGER
		do
			create l_env
			from
				i := 1
			until
				i > a_count
			loop
				l_env.sleep (a_milliseconds.to_integer_64 * 1_000_000)
				waits_done := waits_done + 1
				i := i + 1
			variant
				a_count + 1 - i
			end
		ensure
			done: waits_done = old waits_done + a_count
		end

	run_unmarked_c_sleeps (a_count, a_milliseconds: INTEGER)
			-- `a_count' waits of `a_milliseconds' inside an UNMARKED external -
			-- the shape `c_sp_execute_command' took for the whole life of a
			-- child process before 1.0.1.
		require
			positive: a_count > 0 and a_milliseconds > 0
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > a_count
			loop
				c_sleep_unmarked (a_milliseconds)
				waits_done := waits_done + 1
				i := i + 1
			variant
				a_count + 1 - i
			end
		ensure
			done: waits_done = old waits_done + a_count
		end

	run_blocking_c_sleeps (a_count, a_milliseconds: INTEGER)
			-- The same waits inside the SAME Sleep, marked `blocking'.
		require
			positive: a_count > 0 and a_milliseconds > 0
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > a_count
			loop
				c_sleep_blocking (a_milliseconds)
				waits_done := waits_done + 1
				i := i + 1
			variant
				a_count + 1 - i
			end
		ensure
			done: waits_done = old waits_done + a_count
		end

feature {NONE} -- Externals

	c_sleep_unmarked (a_milliseconds: INTEGER)
			-- Block this thread in C where the runtime cannot see it.
		external
			"C inline use %"sp_test_support.h%""
		alias
			"spt_sleep_ms ((int) $a_milliseconds);"
		end

	c_sleep_blocking (a_milliseconds: INTEGER)
			-- Block this thread in C, having told the runtime so.
		external
			"C blocking inline use %"sp_test_support.h%""
		alias
			"spt_sleep_ms ((int) $a_milliseconds);"
		end

invariant
	non_negative: waits_done >= 0

end
