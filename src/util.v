module main

fn wrap_text(text string, max_width int) []string {
	mut lines := []string{}
	// Split the text into paragraphs based on newlines
	for paragraph in text.split('\n') {
		mut current_line := ''
		for word in paragraph.split(' ') {
			// Determine if we need to add a space before the word
			space_needed := if current_line.len > 0 { 1 } else { 0 }
			if current_line.len + word.len + space_needed <= max_width {
				if current_line.len > 0 {
					current_line += ' '
				}
				current_line += word
			} else {
				if current_line.len > 0 {
					lines << current_line
				}
				// Handle words longer than max_width
				if word.len > max_width {
					// Split the word
					mut start := 0
					for start < word.len {
						end := if start + max_width <= word.len {
							start + max_width
						} else {
							word.len
						}
						lines << word[start..end]
						start = end
					}
					current_line = ''
				} else {
					current_line = word
				}
			}
		}
		// Add the last line of the paragraph
		if current_line.len > 0 {
			lines << current_line
		}
		// Add an empty line to represent the newline character
		lines << ''
	}
	// Remove the last empty line if it exists
	if lines.len > 0 && lines.last() == '' {
		lines = lines[..lines.len - 1].clone()
	}
	return lines
}
