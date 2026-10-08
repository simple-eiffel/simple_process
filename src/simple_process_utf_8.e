note
	description: "[
		UTF-8 for the bytes that cross a child process's pipes (1.1.0).

		`text' decodes what a child wrote. A well-formed UTF-8 sequence
		becomes the one character it encodes. A byte that does not start
		a well-formed sequence becomes the character with that byte's
		value (its Latin-1 reading) - exactly what EVERY byte became
		before 1.1.0. So output in an ANSI or OEM code page reads as it
		always did, and nothing is ever replaced or lost. NUL bytes are
		dropped from the text, also as before 1.1.0 (a child that writes
		UTF-16 still reads as text); the raw bytes keep them.

		Before 1.1.0 every byte became one character, so the two bytes
		of Hebrew bet (D7 91) came back as two Latin-1 characters and
		0 of 1000 Hebrew replies parsed (F3-C spike, 2026-10-06).

		`bytes' encodes text for a child's stdin.

		Well-formed means RFC 3629: no overlong forms, no surrogates,
		nothing above U+10FFFF.
	]"
	author: "Larry Rix"
	date: "$Date$"
	revision: "$Revision$"

class
	SIMPLE_PROCESS_UTF_8

feature -- Conversion

	text (a_bytes: READABLE_STRING_8): STRING_32
			-- `a_bytes' decoded as UTF-8; a byte that starts no
			-- well-formed sequence becomes its Latin-1 character; NUL
			-- bytes are dropped.
		local
			i, n, l_length: INTEGER
			l_code: NATURAL_32
		do
			n := a_bytes.count
			create Result.make (n)
			from
				i := 1
			until
				i > n
			loop
				l_length := sequence_length (a_bytes, i)
				if l_length = 0 then
					Result.append_code (a_bytes.code (i))
					i := i + 1
				else
					l_code := decoded_at (a_bytes, i, l_length)
					if l_code /= 0 then
						Result.append_code (l_code)
					end
					i := i + l_length
				end
			variant
				n + 1 - i
			end
		ensure
			never_longer: Result.count <= a_bytes.count
			empty_to_empty: a_bytes.is_empty implies Result.is_empty
		end

	bytes (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' encoded as UTF-8. A surrogate code point or one above
			-- U+10FFFF, which UTF-8 cannot carry, becomes U+FFFD.
		local
			i, n: INTEGER
			l_code: NATURAL_32
		do
			n := a_text.count
			create Result.make (n)
			from
				i := 1
			until
				i > n
			loop
				l_code := a_text.code (i)
				if (l_code >= 0xD800 and l_code <= 0xDFFF) or l_code > 0x10FFFF then
					l_code := Replacement_character
				end
				if l_code <= 0x7F then
					Result.append_code (l_code)
				elseif l_code <= 0x7FF then
					Result.append_code (0xC0 | (l_code |>> 6))
					Result.append_code (0x80 | (l_code & 0x3F))
				elseif l_code <= 0xFFFF then
					Result.append_code (0xE0 | (l_code |>> 12))
					Result.append_code (0x80 | ((l_code |>> 6) & 0x3F))
					Result.append_code (0x80 | (l_code & 0x3F))
				else
					Result.append_code (0xF0 | (l_code |>> 18))
					Result.append_code (0x80 | ((l_code |>> 12) & 0x3F))
					Result.append_code (0x80 | ((l_code |>> 6) & 0x3F))
					Result.append_code (0x80 | (l_code & 0x3F))
				end
				i := i + 1
			variant
				n + 1 - i
			end
		ensure
			at_least_one_byte_each: Result.count >= a_text.count
			at_most_four_bytes_each: Result.count <= 4 * a_text.count
		end

feature -- Measurement

	sequence_length (a_bytes: READABLE_STRING_8; a_index: INTEGER): INTEGER
			-- Length of the well-formed UTF-8 sequence that starts at
			-- `a_index' in `a_bytes', or 0 when none starts there.
		require
			valid_index: a_bytes.valid_index (a_index)
		local
			l_lead: NATURAL_32
			l_needed, k: INTEGER
			l_ok: BOOLEAN
		do
			l_lead := a_bytes.code (a_index)
			if l_lead <= 0x7F then
				Result := 1
			else
				l_needed := needed_length (l_lead)
				if l_needed > 0 and then a_index + l_needed - 1 <= a_bytes.count then
					l_ok := in_range (a_bytes.code (a_index + 1), second_low (l_lead), second_high (l_lead))
					from
						k := 2
					until
						not l_ok or k >= l_needed
					loop
						l_ok := in_range (a_bytes.code (a_index + k), 0x80, 0xBF)
						k := k + 1
					variant
						l_needed - k
					end
					if l_ok then
						Result := l_needed
					end
				end
			end
		ensure
			zero_to_four: Result >= 0 and Result <= 4
			fits: Result > 0 implies a_index + Result - 1 <= a_bytes.count
			ascii_is_one: a_bytes.code (a_index) <= 0x7F implies Result = 1
		end

	unfinished_tail_count (a_bytes: READABLE_STRING_8): INTEGER
			-- How many bytes at the very end of `a_bytes' are the start of
			-- a well-formed sequence that more bytes could still complete
			-- (0 to 3). A reader that receives a stream in chunks holds
			-- these back until the next chunk, so a character split across
			-- two reads is not decoded as two broken halves.
		local
			k, n, l_lead_index, l_needed, j: INTEGER
			l_lead: NATURAL_32
			l_ok: BOOLEAN
		do
			n := a_bytes.count
			from
				k := 1
			until
				Result > 0 or k > 3 or k > n
			loop
				l_lead_index := n - k + 1
				l_lead := a_bytes.code (l_lead_index)
				l_needed := needed_length (l_lead)
				if l_needed > k then
					l_ok := True
					if k >= 2 then
						l_ok := in_range (a_bytes.code (l_lead_index + 1), second_low (l_lead), second_high (l_lead))
					end
					from
						j := 2
					until
						not l_ok or j >= k
					loop
						l_ok := in_range (a_bytes.code (l_lead_index + j), 0x80, 0xBF)
						j := j + 1
					variant
						k - j + 1
					end
					if l_ok then
						Result := k
					end
				end
				k := k + 1
			variant
				4 - k
			end
		ensure
			at_most_three: Result >= 0 and Result <= 3
			within: Result <= a_bytes.count
		end

feature -- Constants

	Replacement_character: NATURAL_32 = 0xFFFD
			-- U+FFFD, for code points UTF-8 cannot carry.

feature {NONE} -- Implementation

	decoded_at (a_bytes: READABLE_STRING_8; a_index, a_length: INTEGER): NATURAL_32
			-- The code point of the well-formed `a_length'-byte sequence at `a_index'.
		require
			well_formed: sequence_length (a_bytes, a_index) = a_length
			not_empty: a_length >= 1
		local
			k: INTEGER
		do
			inspect
				a_length
			when 1 then
				Result := a_bytes.code (a_index)
			when 2 then
				Result := a_bytes.code (a_index) & 0x1F
			when 3 then
				Result := a_bytes.code (a_index) & 0x0F
			else
				Result := a_bytes.code (a_index) & 0x07
			end
			from
				k := 1
			until
				k >= a_length
			loop
				Result := (Result |<< 6) | (a_bytes.code (a_index + k) & 0x3F)
				k := k + 1
			variant
				a_length - k
			end
		ensure
			in_unicode: Result <= 0x10FFFF
		end

	needed_length (a_lead: NATURAL_32): INTEGER
			-- Bytes in a sequence led by `a_lead', or 0 if it leads none.
			-- C0, C1 (overlong) and F5..FF never lead.
		do
			if a_lead <= 0x7F then
				Result := 1
			elseif a_lead >= 0xC2 and a_lead <= 0xDF then
				Result := 2
			elseif a_lead >= 0xE0 and a_lead <= 0xEF then
				Result := 3
			elseif a_lead >= 0xF0 and a_lead <= 0xF4 then
				Result := 4
			end
		ensure
			zero_to_four: Result >= 0 and Result <= 4
		end

	second_low (a_lead: NATURAL_32): NATURAL_32
			-- Lowest legal second byte after `a_lead' (RFC 3629 table).
		do
			if a_lead = 0xE0 then
				Result := 0xA0
			elseif a_lead = 0xF0 then
				Result := 0x90
			else
				Result := 0x80
			end
		end

	second_high (a_lead: NATURAL_32): NATURAL_32
			-- Highest legal second byte after `a_lead' (RFC 3629 table).
		do
			if a_lead = 0xED then
				Result := 0x9F
			elseif a_lead = 0xF4 then
				Result := 0x8F
			else
				Result := 0xBF
			end
		end

	in_range (a_code, a_low, a_high: NATURAL_32): BOOLEAN
			-- Is `a_code' within `a_low' .. `a_high'?
		do
			Result := a_code >= a_low and a_code <= a_high
		end

end
