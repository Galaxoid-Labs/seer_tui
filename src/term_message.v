module main
import term
import time

struct TermMessage {
mut:
	label   string
	message string
	message_color ?fn (string) string
	message_bold bool
}

@[params]
pub struct TermMessageParams {
pub:
	system bool
	error bool
	label ?string
	message string
	label_bold bool
	label_color ?fn (string) string
	message_color ?fn (string) string
	message_bold bool
}

pub fn TermMessage.new(tmp TermMessageParams) TermMessage {
	mut label := tmp.label or { '[ ${time.now().hhmm()} ]' }
	if tmp.system {
		label = '[ ${time.now().hhmm()} ] [ -!- ]'
		label = term.colorize(term.bright_yellow, label)
	}

	if label_color := tmp.label_color {
		label = term.colorize(label_color, label)
	} else if tmp.error {
		label = term.colorize(term.bright_red, label)
	}

	if tmp.label_bold {
		label = term.bold(label)
	}

	mut message := tmp.message

	if message_color := tmp.message_color {
		message = term.colorize(message_color, message)
	} else if tmp.error {
		message = term.colorize(term.bright_red, message)
	}

	if tmp.message_bold {
		message = term.bold(message)
	}

	return TermMessage{
		label: label,
		message: message
		message_color: tmp.message_color
		message_bold: tmp.message_bold
	}
}

fn (tm TermMessage) combined() string {
	return '${tm.label} ${tm.message}'
}