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


fn is_valid_ws_url(url string) bool {
    // Check if the URL starts with ws:// or wss://
    if !(url.starts_with('ws://') || url.starts_with('wss://')) {
        return false
    }

    // Split the URL into parts
    parts := url.split('://')
    if parts.len != 2 {
        return false
    }

    // Check if there's a valid host part
    host_part := parts[1].split('/')
    if host_part.len == 0 || host_part[0].len == 0 {
        return false
    }

    // Validate the host (IP or domain)
    host := host_part[0]
    if !is_valid_host(host) {
        return false
    }

    return true
}

fn is_valid_host(host string) bool {
    // Check for valid IP address (IPv4 or IPv6) or domain name
    return is_valid_ipv4(host) || host.contains('.')
}

fn is_valid_ipv4(ip string) bool {
    octets := ip.split('.')
    if octets.len != 4 {
        return false
    }

    for octet in octets {
        if !octet.is_int() {
            return false
        }
        num := octet.int()
        if num < 0 || num > 255 {
            return false
        }
    }

    return true
}
