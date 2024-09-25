module main

import term.ui as tui
import net.websocket
import term

struct App {
mut:
    tui                 &tui.Context = unsafe { nil }

    input               string
    input_height        int = 1

    groups              map[string]Group
    current_group_id    string

    messages            []TermMessage
    msg_channel         chan TermMessage
    max_messages        int = 100 // We only keep 100 messages in the buffer

    last_commands       []string

    uri_chat            string 
    ws_chat             &websocket.Client = unsafe { nil }
    show_title          bool = true

    // uri_metadata        string
    // ws_metadata         &websocket.Client = unsafe { nil }
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

    app.msg_channel <- TermMessage.new(system: true, message: 'Welcome to seer_tui!! Get started by checking out the commands. Type /help', 
                                        label_bold: true, label_color: term.bright_yellow)

    app.tui.set_window_title("seer_tui")

    app.tui.run() or { 
        eprintln(err)
        panic(err)
    }
}

fn event(e &tui.Event, a voidptr) {
    mut app := unsafe { &App(a) }
    if e.typ == .key_down {
        app.show_title = false
        match e.code {
            .escape {
                //exit(0) 
                // TODO: One escape maybe ask if you want to exit?
                // Also, could use it to back up.
            }
            .enter {
                if app.input.starts_with('/') {
                    handle_command(mut app, app.input)
                } else {

                    app.msg_channel <- TermMessage.new(message: app.input.trim_space(), 
                                    label_bold: true, label_color: term.bright_cyan, message_color: term.bright_cyan, message_bold: true)
                    app.input = ''
                }

            }
            .backspace {
                if app.input.len > 0 {
                    app.input = app.input[..app.input.len - 1]
                    app.tui.clear()
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

    if app.show_title {
        t := 
'
                                                █████                ███ 
                                               ░░███                ░░░  
  █████   ██████   ██████  ████████            ███████   █████ ████ ████ 
 ███░░   ███░░███ ███░░███░░███░░███          ░░░███░   ░░███ ░███ ░░███ 
░░█████ ░███████ ░███████  ░███ ░░░             ░███     ░███ ░███  ░███ 
 ░░░░███░███░░░  ░███░░░   ░███                 ░███ ███ ░███ ░███  ░███ 
 ██████ ░░██████ ░░██████  █████     █████████  ░░█████  ░░████████ █████
░░░░░░   ░░░░░░   ░░░░░░  ░░░░░     ░░░░░░░░░    ░░░░░    ░░░░░░░░ ░░░░░                                                             
'

        app.tui.set_color(color_blue)
        app.tui.draw_text(0, 4, t)
        app.tui.reset()

    }

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
        mut lines := wrap_text(msg.combined(), window_width)
        if lines.len > 1 {
            // We have to re-add the ansci bold/color stuff to the messages since
            // the wrap text screws it up.
            for i, _ in lines {
                if i > 0 {
                	if message_color := msg.message_color {
		                lines[i] = term.colorize(message_color, lines[i])
	                }
	                if msg.message_bold {
		                lines[i] = term.bold(lines[i])
	                }
                }
            }
            wrapped_messages << lines
        } else {
            wrapped_messages << lines
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
        app.tui.draw_text(0, y, all_lines[i])
        app.tui.reset() // ?? Do i need this?
        y++
    }

    // Draw top status bar
    app.tui.draw_text(0, 0, term.bg_blue(' '.repeat(window_width)))
    app.tui.draw_text(2, 0, term.bg_blue('Welcome to Seer'))

    // Draw the bottom bar
    divider_y := content_height - 2
    app.tui.draw_text(0, divider_y, term.bg_blue(' '.repeat(window_width)))
    app.tui.draw_text(2, divider_y, term.bg_blue('You are not connected'))


    // mut bg := term.format('Not connected bitch', '44', '49')
    // bg = term.white(bg)
    // app.tui.draw_text(0, divider_y, bg)

    // app.tui.set_bg_color(tui.Color{r: 184, g: 195, b: 199})
    // app.tui.set_color(color_black)
    // app.tui.bold()
    // app.tui.draw_line(0, divider_y, window_width-1, divider_y)

    // if app.ws_chat != unsafe { nil } && app.ws_chat.get_state() in [.connecting, .open] {
    //     app.tui.draw_text(2, divider_y, "Connected to ${app.ws_chat.uri}")
    // } else {
    //     app.tui.reset()
    //     app.tui.draw_text(2, divider_y, term.bright_bg_blue(term.rgb(255, 255, 255, "Not connected")))
    // }
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
        app.msg_channel <- TermMessage.new(system: true, message: message, 
                                        label_bold: true)
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
    if input.starts_with('/cc wss://') {
        sp := input.split(' ')
        if sp.len == 2 {
            app.uri_chat = sp[1]
            spawn connect(mut app)
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
        if app.ws_chat != unsafe { nil } {
            app.ws_chat.close(0, 'Disconnected') or { return }
        }
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
