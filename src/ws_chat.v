module main

import net.websocket
import ismyhc.vnostr
import time

struct Group {
	id   string
	name string
}

const group_list_subscription_id = 'group_list'

fn connect(mut app App) {
	if app.uri_chat == '' {
		return
	}

	if app.ws_chat != unsafe { nil } {
		app.ws_chat.reset_state() or {
			app.msg_channel <- TermMessage{
				label:   '[ ${time.now().hhmm12()}]'
				message: '${err.str()}'
			}
		}
	}
	app.ws_chat = websocket.new_client(app.uri_chat) or {
		app.msg_channel <- TermMessage{
			label:   '[ ${time.now().hhmm12()}]'
			message: '${err.str()}'
			header:  '\xB0'
		}
		panic(err)
	}
	app.ws_chat.logger.set_level(.disabled)
	app.ws_chat.on_open_ref(on_open_callback, app)
	app.ws_chat.on_close_ref(on_close_callback, app)
	app.ws_chat.on_error_ref(on_err_callback, app)
	app.ws_chat.on_message_ref(on_message_callback, app)
	app.ws_chat.connect() or {
		app.msg_channel <- TermMessage{
			label:   '${time.now()}'
			message: '${err.str()}'
			header:  '\xB0'
		}
	}
	spawn app.ws_chat.listen()
}

fn on_open_callback(mut ws websocket.Client, a voidptr) ! {
	mut app := unsafe { &App(a) }
	group_list_filter := vnostr.VNFilter.new(kinds: [u16(39000)])
	group_list_sub := vnostr.VNSubscription.new(id: group_list_subscription_id, filters: [
		group_list_filter,
	])
	ws.write_string(group_list_sub.subscribe()) or {
		app.msg_channel <- TermMessage{
			label:   '[ ${time.now().hhmm12()}]'
			message: '${err.str()}'
			header:  '\xB0'
		}
	}
}

fn on_message_callback(mut ws websocket.Client, msg &websocket.Message, a voidptr) ! {
	mut app := unsafe { &App(a) }
	match msg.opcode {
		.text_frame {
			if msg.payload.len > 0 {
				relay_message := vnostr.get_relay_message(msg.payload) or { return }

				match relay_message {
					vnostr.RelayMessageEvent {
						match relay_message.event.kind {
							u16(39000) {
								d_tag := relay_message.event.filter_tags_by_name('d')
								if d_tag.len == 0 || d_tag[0].len < 2 {
									return
								}
								group_id := d_tag[0][1]

								name_tag := relay_message.event.filter_tags_by_name('name')
								if name_tag.len == 0 || name_tag[0].len < 2 {
									return
								}
								group_name := name_tag[0][1]

								group := Group{
									id:   group_id
									name: group_name
								}
								app.groups[group_id] = group
							}
							u16(9) {
								app.msg_channel <- TermMessage{
									label:   '[ ${time.unix(relay_message.event.created_at).local().hhmm()} ] [ ${relay_message.event.pubkey[..8]} ]'
									message: relay_message.event.content.trim_space()
								}
							}
							else {}
						}
					}
					vnostr.RelayMessageEOSE {
						if relay_message.subscription_id == group_list_subscription_id {
							mut message := ''
							for _, g in app.groups {
								message += '#${g.id} (${g.name}) | '
							}
							app.msg_channel <- TermMessage{
								label:   '[ ${time.now().hhmm12()}] [ Avaibile Groups at ${ws.uri} ]'
								message: message
								header:  '\x20'
							}
						}
					}
					else {}
				}
			}
		}
		.close {
			app.msg_channel <- TermMessage{
				label:   '[ ${time.now().hhmm12()}]'
				message: '${ws.uri} closed'
				header:  '\x20'
			}
		}
		.binary_frame {
			app.msg_channel <- TermMessage{
				label:   '[ ${time.now().hhmm12()}]'
				message: '${ws.uri} binary frame'
			}
		}
		.ping {}
		.pong {}
		else {
			app.msg_channel <- TermMessage{
				label:   '[ ${time.now().hhmm12()}]'
				message: '${msg.opcode}'
			}
		}
	}
}

fn on_err_callback(mut ws websocket.Client, err string, a voidptr) ! {
	mut app := unsafe { &App(a) }
	app.msg_channel <- TermMessage{
		label:   '[ ${time.now().hhmm12()}]'
		message: '${err.str()}'
		header:  '\x20'
	}
	spawn connect(mut app) // Try reconnect
}

fn on_close_callback(mut ws websocket.Client, code int, reason string, a voidptr) ! {
	mut app := unsafe { &App(a) }
	app.msg_channel <- TermMessage{
		label:   '[ ${time.now().hhmm12()}]'
		message: 'received close from ${ws.uri} ${code} ${reason}'
		header:  '\x20'
	}
}

fn subscribe_group(id string, mut app App) {
	filter := vnostr.VNFilter.new(kinds: [u16(9)], tags: [['#h', id]])
	sub := vnostr.VNSubscription.new(id: 'group', filters: [filter])
	app.ws_chat.write_string(sub.subscribe()) or {
		app.msg_channel <- TermMessage{
			label:   '[ ${time.now().hhmm12()}]'
			message: '${err.str()}'
			header:  '\xB0'
		}
	}
}

fn unsubscrib_group(id string, mut app App) {
	sub := vnostr.VNSubscription.new(id: id)
	app.ws_chat.write_string(sub.unsubscribe()) or {
		app.msg_channel <- TermMessage{
			label:   '[ ${time.now().hhmm12()}]'
			message: '${err.str()}'
			header:  '\xB0'
		}
	}
}
