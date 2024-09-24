module main

// header \x00 - Default: No bold, normal color
// header \x10 - No bold, green color
// header \x20 - No bold, yellow color
// header \x30 - No bold, red color
// header \x80 - Bold, normal color
// header \x90 - Bold, green color
// header \xA0 - Bold, yellow color
// header \xB0 - Bold, red color
struct TermMessage {
mut:
	label   string
	message string
	header  string // Should only be single byte
}

fn (tm TermMessage) combined() string {
	return '${tm.label} ${tm.message}'
}

fn (tm TermMessage) combined_with_header() string {
	return '${tm.header}${tm.label} ${tm.message}'
}

fn parse_format(header u8) (bool, int) {
	is_bold := (header & 0b10000000) != 0
	color_code := (header & 0b01110000) >> 4
	return is_bold, color_code
}
