module main

import term.ui as tui
import net.websocket
import time

struct App {
mut:
    tui                 &tui.Context = unsafe { nil }
    input               string
    input_height        int = 1
    groups              map[string]Group
    current_group_id    string
    messages            []TermMessage
    last_commands       []string
    msg_channel         chan TermMessage
    max_messages        int = 100 // We only keep 100 messages in the buffer
    ws                  &websocket.Client = unsafe { nil }
}

pub const default_format = '\x00'.bytes()[0]
pub const blue_format = '\x10'.bytes()[0]
pub const yellow_format = '\x20'.bytes()[0]
pub const red_format = '\x30'.bytes()[0]
pub const bold_default_format = '\x80'.bytes()[0]
pub const bold_blue_format = '\x90'.bytes()[0]
pub const bold_yellow_format = '\xA0'.bytes()[0]
pub const bold_red_format = '\xB0'.bytes()[0]

pub const color_black = tui.Color{r: 0, g: 0, b: 0}
pub const color_green = tui.Color{r: 0, g: 228, b: 54}
pub const color_blue = tui.Color{r: 41, g: 173, b: 255}
pub const color_yellow = tui.Color{r: 255, g: 236, b: 39} 
pub const color_red = tui.Color{r: 255, g: 0, b: 77} 

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
        label string
        message string
        header string  // Should only be single byte
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

fn main() {
    mut app := &App{
        last_commands: []string{}
    }

    app.msg_channel = chan TermMessage{cap: 100}

    app.tui = tui.init(
        user_data:      app
        event_fn:       event
        frame_fn:       frame
        hide_cursor:    false
        frame_rate:     30
    )

    spawn connect(mut app)

    app.tui.run() or { 
        panic(err)
    }
}

fn event(e &tui.Event, a voidptr) {
    mut app := unsafe { &App(a) }
    if e.typ == .key_down {
        match e.code {
            .escape {
                exit(0) 
            }
            .enter {
                if app.input.starts_with('/') {
                    handle_command(mut app, app.input)
                } else {

                    app.msg_channel <- TermMessage{
                        label: '[ ${time.now().hhmm12()}]'
                        message: app.input.trim_space()
                        header: '\x90' // Bold green
                    }
                    app.input = ''
                }

            }
            .backspace {
                if app.input.len > 0 {
                    app.input = app.input[..app.input.len - 1]
                    app.tui.clear()
                    // app.tui.flush()
                }
            }
            else {
                if e.utf8.len > 0 {
                    if e.code !in [.left, .right] {
                        app.input += e.utf8
                    }
                    if e.code == .up {
                        if app.last_commands.len > 0 {
                            app.input = app.last_commands.last()
                        }
                    }
                    if e.code == .down {
                        app.input = ''
                    }
                }
            }
        }
    } else if e.typ == .resized {
        app.tui.clear()
        app.tui.flush()
        //frame(app)
    }
}

fn frame(a voidptr) {
    mut app := unsafe { &App(a) }

    // Receive all available messages from the channel
    for {
        select {
            msg := <-app.msg_channel {
                add_message(mut app, msg)
                app.tui.clear()
            }
            else {
                break
            }
        }
    }

    // Get window dimensions
    window_width := app.tui.window_width
    window_height := app.tui.window_height

    // Calculate input area height based on input lines
    mut input_lines := app.input.split('\n')
    app.input_height = input_lines.len

    // Limit the maximum input height
    max_input_height := 5
    if app.input_height > max_input_height {
        app.input_height = max_input_height
        // Trim input lines to fit
        input_lines = input_lines[input_lines.len - max_input_height..].clone()
    }

    // Recalculate content area height
    content_height := window_height - app.input_height

    // Prepare wrapped messages
    mut wrapped_messages := [][]string{}
    for msg in app.messages {
        lines := wrap_text(msg.combined(), window_width)
        if msg.header == '' {
            wrapped_messages << lines.map('\x00${it}')
        } else {
            wrapped_messages << lines.map('${msg.header}${it}')
        }
    }

    // Flatten wrapped messages and keep track of total lines
    mut all_lines := []string{}
    for lines in wrapped_messages {
        all_lines << lines
    }

    // Determine how many lines to display
    max_lines := content_height - 3  // Subtract 1 to account for the divider
    total_lines := all_lines.len
    lines_to_display := if total_lines > max_lines {
        max_lines
    } else {
        total_lines
    }

    // Calculate the starting y position
    start_y := content_height - 3 - lines_to_display

    // Calculate the starting index in all_lines
    start_line := total_lines - lines_to_display

    // Draw the content area (messages)
    mut y := start_y
    for i in start_line .. total_lines {
        header := all_lines[i][0]

        match header {
            default_format {
                app.tui.reset()
            }
            blue_format {
                app.tui.set_color(color_blue)
            }
            yellow_format {
                app.tui.set_color(color_yellow)
            }
            red_format {
                app.tui.set_color(color_red)
            }
            bold_blue_format {
                app.tui.bold()
                app.tui.set_color(color_blue)
            }
            bold_yellow_format {
                app.tui.bold()
                app.tui.set_color(color_yellow)
            }
            bold_red_format {
                app.tui.bold()
                app.tui.set_color(color_red)
            }
            else {
                app.tui.reset()
            }
        }

        app.tui.draw_text(0, y, all_lines[i][1..])
        app.tui.reset()
        y++
    }

    // Draw the horizontal divider
    divider_y := content_height - 2 

    if app.ws.get_state() in [.connecting, .open] {
        app.tui.set_bg_color(tui.Color{r: 184, g: 195, b: 199})
        app.tui.set_color(color_black)
        app.tui.bold()
        app.tui.draw_line(0, divider_y, window_width-1, divider_y)
        app.tui.draw_text(2, divider_y, "Connected to ${app.ws.uri}")
    } else {
        app.tui.set_bg_color(color_red)
        app.tui.set_color(color_black)
        app.tui.bold()
        app.tui.draw_line(0, divider_y, window_width-1, divider_y)
        app.tui.draw_text(2, divider_y, "Not connected")
    }
    app.tui.reset_bg_color()
    app.tui.reset()

    // Draw the input area
    prompt := '> '
    for i, line in input_lines {
        input_y := content_height + i
        if i == 0 {
            app.tui.draw_text(0, input_y, prompt + line)
        } else {
            app.tui.draw_text(0, input_y, '  ' + line)
        }
    }

    // Set the cursor position
    cursor_line := content_height + input_lines.len - 1

    // Determine the base cursor x position
    base_x := if input_lines.len == 1 {
        prompt.len
    } else {
        2  // Indentation for subsequent lines
    }

    // Calculate the cursor x position
    cursor_x := base_x + input_lines.last().len

    app.tui.set_cursor_position(cursor_x + 1, cursor_line)
    app.tui.reset()
    app.tui.flush()
}

fn handle_command(mut app App, input string) {
    if input == '/home' {
        // unsub group
        unsubscrib_group(app.current_group_id, mut app)
        app.current_group_id = ''
        app.last_commands << input
        app.input = ''
        app.tui.clear()
        app.tui.flush()
        mut message := ''
		for _, g in app.groups {
			message += '#${g.id} (${g.name}) | '
		}
		app.msg_channel <- TermMessage{
			label: '[ ${time.now().hhmm12()}] [ Avaibile Groups at ${app.ws.uri} ]'
			message: message
			header: '\x20'
		}
    }
    if input.starts_with('/view') {
        sp := input.split(' ')
        if sp.len == 2 {
            subscribe_group(sp[1], mut app)
            app.current_group_id = sp[1]
            app.last_commands << input
            app.input = ''
            app.tui.clear()
            app.tui.flush()
        }
    } 
    if input == '/exit' {
        app.last_commands << input
        exit(0)
    }
    if input == '/disconnect' {
        app.input = ''
        app.last_commands << input
        app.ws.close(0, 'Disconnected') or { return }
    }
    if input == '/connect' {
        app.input = ''
        app.last_commands << input
        spawn connect(mut app) 
        app.tui.clear()
        app.tui.flush()
    }
    if input == '/clear' {
        app.input = ''
        app.last_commands << input
        app.messages = []
        app.tui.clear()
        app.tui.flush()
    }
}

fn add_message(mut app App, new_message TermMessage) {
    app.messages << new_message 
    if app.messages.len > app.max_messages {
        app.messages = app.messages[app.messages.len - app.max_messages ..]
    }
}

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
                        end := if start + max_width <= word.len { start + max_width } else { word.len }
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
