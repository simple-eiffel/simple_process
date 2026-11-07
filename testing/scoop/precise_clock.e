note
	description: "[
		Milliseconds off the machine's high-resolution counter, for
		measuring a stall that a one-second clock would round away.

		`now_ms' is itself an unmarked external, deliberately: it takes
		a fraction of a microsecond, so it can never be the thing the
		assault measures.
	]"
	author: "Larry Rix"

class
	PRECISE_CLOCK

feature -- Access

	now_ms: INTEGER_64
			-- Milliseconds off the high-resolution counter.
		external
			"C inline use %"sp_test_support.h%""
		alias
			"return (EIF_INTEGER_64) spt_now_ms ();"
		end

end
