module main

import ismyhc.vnostr
import term.ui as tui
import term
import os

struct App {
mut:
    tui                 &tui.Context = unsafe { nil }

    show_title          bool = true
    input               string
    input_height        int = 1
    show_spinner        bool
    spinner_frame       string
    frame               int

    messages            []TermMessage
    msg_channel         chan TermMessage
    max_messages        int = 100 // We only keep 100 messages in the buffer

    last_commands       []string

    chat_ws             ChatWsConnection

    pk                  ?vnostr.VNKeyPair
}

const spinner_frames = ['|', '|', '/', '/', '-', '-', '\\', '\\']

const commands = {
    '/clear': '/clear : (Clears the screen)',
    '/home': '/home : (Brings you back to main screen)',
    '/connect ': '/connect <nip29 websocket url> : (Connects to nip29 server)',
    '/reconnect': '/reconnect : (Trys reconnecting to the last url)'
    '/disconnect ': '/disconnect : (Disconnects nip29 server)',
    '/join ': '/join <group_id> : (Joins the group as member)',
    '/leave ': '/leave <group_id> : (Removes you as a member from the group)',
    '/quit': '/quit : (Quits the application)',
    '/view ': '/view <group_id> : (Views the group without joining)',
    '/listg': '/listg : (Lists all groups on server)',
    '/help' : '/help : (Lists all commands)'
}

fn main() {
    mut app := &App{
        last_commands: []string{}
        chat_ws: ChatWsConnection.new('')
    }

    app.msg_channel = chan TermMessage{cap: 100}

    app.tui = tui.init(
        user_data:      app
        event_fn:       event
        frame_fn:       frame
        hide_cursor:    false
        frame_rate:     30
        capture_events: false
    )

    app.msg_channel <- TermMessage.new(system: true, message: 'Welcome to seer_tui!! Get started by checking out the commands. Type /help', 
                                        label_bold: true, label_color: term.bright_yellow)

    args := os.args
    if args.len == 2 {
        pk := vnostr.VNKeyPair.from_private_key_nsec(args[1]) or { panic('You sucks')}
        app.pk = pk

        if private_key := app.pk {
            app.msg_channel <- TermMessage.new(system: true, message: 'Successfuly imported ${private_key.public_key_npub}', 
                                            label_bold: true, label_color: term.bright_yellow)
        }
    }

    app.tui.set_window_title('seer_tui')

    app.tui.run() or { 
        eprintln(err)
        panic(err)
    }
}

fn event(e &tui.Event, a voidptr) {
    mut app := unsafe { &App(a) }
    if e.typ == .key_down {
        match e.code {
            .escape {
                //exit(0) 
                // TODO: One escape maybe ask if you want to exit?
                // Also, could use it to back up.
                if app.chat_ws.selected_group == none {
                    return
                }
                app.messages = []
                app.chat_ws.unsubscrib_group(mut app)
                app.chat_ws.list_groups(mut app)
            }
            .enter {
                if app.input.starts_with('/') {
                    handle_command(mut app, app.input)
                } else {
                    if app.pk != none && app.chat_ws.selected_group != none && app.input != '' {
                        message := app.input.clone()
                        app.input = ''
                        app.tui.clear()
                        app.tui.flush()
                        app.chat_ws.send_message(mut app, message)
                    } else {
                        app.msg_channel <- TermMessage.new(message: app.input.trim_space(), label_color: term.bright_cyan)
                        app.input = ''
                    }
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
    }
}

fn frame(a voidptr) {
    mut app := unsafe { &App(a) }

    if app.show_spinner {
        app.spinner_frame = spinner_frames[app.frame % spinner_frames.len]
        app.frame++
        if app.frame > 8 {
            app.frame = 0
        }
    }

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
        mut t := 
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
        t = term.bright_yellow(t)
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
    app.tui.draw_text(2, 0, term.bg_blue('seer_tui v0.1.0'))

    // Draw the bottom bar
    mut bottom_status := ''

    if app.chat_ws.ws != unsafe { nil } {
        bottom_status += '${app.chat_ws.uri}'
    }

    if selected_group := app.chat_ws.selected_group {
        bottom_status += ' | (${selected_group.id}) | ${selected_group.name}'
        if pk := app.pk {
            if app.chat_ws.is_member(selected_group.id, pk.public_key_hex) {
                bottom_status += ' | (Member)'
            } else {
                bottom_status += ' | (Not a member)'
            }
        }
    }

    divider_y := content_height - 2
    app.tui.draw_text(0, divider_y, term.bg_blue(' '.repeat(window_width)))

    if app.show_spinner {
        app.tui.draw_text(2, divider_y, term.bg_blue('${app.spinner_frame} ${bottom_status}'))
    } else {
        app.tui.draw_text(2, divider_y, term.bg_blue(bottom_status))
    }

    app.tui.reset_bg_color()
    app.tui.reset()

    // Draw the input area
    mut prompt := '> '
    if pk := app.pk {
        prompt = '(${pk.public_key_hex[..8]}) > '
    }    
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
    // Check if the input matches any command in the map
    for key, _ in commands {
        if key.ends_with(' ') {
            if input.starts_with(key) {
                split := input.split(' ')
                if split.len == 2 {
                    execute_command(mut app, key, split[1])
                    return
                }
            }
        } else {
            // Check for exact match
            if input == key {
                execute_command(mut app, key, '')
                return
            }
        }
    }

    app.input = ''
    app.msg_channel <- TermMessage.new(system: true, error: true, message: 'Unknown Command ${input}', 
                                       label_bold: true)
    app.msg_channel <- TermMessage.new(system: true, message: 'Try /help for list of commands', 
                                       label_bold: true)
}

fn execute_command(mut app App, command string, arg string) {
    defer {
        app.show_title = false
        app.last_commands << command
        app.input = ''
        app.tui.clear()
        app.tui.flush()
    }
    match command {
        '/help' {
            app.messages = []
	        app.msg_channel <- TermMessage.new(system: true, message: '-------------------------------')
	        app.msg_channel <- TermMessage.new(system: true, message: 'Available Commands')
	        app.msg_channel <- TermMessage.new(system: true, message: '-------------------------------')
            for _, help in commands {
                app.msg_channel <- TermMessage.new(system: true, message: help, 
                                                    label_bold: true)
            }
	        app.msg_channel <- TermMessage.new(system: true, message: '-------------------------------')
        }
        '/clear' {
            app.messages = []
        }
        '/home' {
            if app.chat_ws.selected_group == none {
                return
            }
            app.messages = []
            app.chat_ws.unsubscrib_group(mut app)
            app.chat_ws.list_groups(mut app)
        }
        '/connect ' {

            wss_prefix := 'wss://'
            ws_prefix := 'ws://'

            mut uri := arg
            if !arg.starts_with(wss_prefix) && !arg.starts_with(ws_prefix) {
                uri = '${wss_prefix}${arg}'
            }

            if !is_valid_ws_url(uri) {
                app.msg_channel <- TermMessage.new(system: true, error: true, message: 'Invalid uri ${arg}', 
                                                   label_bold: true)
                return
            }

            app.chat_ws.uri = uri
            spawn connect(mut app)
        }
        '/reconnect' {
            spawn connect(mut app)
        }
        '/join' {
            println('Joining: $arg')
        }
        '/leave' {
            println('Leaving: $arg')
        }
        '/quit' {
            exit(0)
        }
        '/view ' {
            if selected_group := app.chat_ws.selected_group {
                if arg == selected_group.id {
                    return
                }
            }

            if group := app.chat_ws.groups[arg] {
                app.chat_ws.selected_group = group
                app.chat_ws.subscribe_group(mut app)
                app.messages = []
                app.msg_channel <- TermMessage.new(system: true, message: 'Viewing Group (${group.id}) | ${group.name}')
            }

        }
        '/listg' {
            // TODO: Check if we are connected..
            spawn app.chat_ws.list_groups(mut app)
        }
        '/listu' {
            println('Listing users...')
        }
        else {
            println('Unknown command executed: $command')
        }
    }
}

fn connect(mut app App) {
    app.chat_ws.connect(mut app)
}

fn add_message(mut app App, new_message TermMessage) {
    app.messages << new_message 
    if app.messages.len > app.max_messages {
        app.messages = app.messages[app.messages.len - app.max_messages ..]
    }
}
