module main

import net.websocket
import time
import term
import ismyhc.vnostr

struct Group {
	id   string
	name string
}

struct Member {
	group_id   string
	pubkey     string
	created_at u64
	kind       u16
}

const group_list_sub_id = 'group_list_sub_id'
const group_join_leave_sub_id = 'group_join_leave_sub_id'
const group_messages_sub_id = 'group_messages_sub_id'

@[heap]
struct ChatWsConnection {
mut:
	uri                string
	ws                 &websocket.Client = unsafe { nil }
	groups             map[string]Group
	selected_group     ?Group
	group_eose_reached bool
	messages           []vnostr.VNEvent
	members            []Member
}

fn (mut cwc ChatWsConnection) is_member(gid string, pubkey string) bool {
	mut filterd := cwc.members.filter(it.group_id == gid && it.pubkey == pubkey)
	filterd.sort(a.created_at > b.created_at)
	if filterd.len > 0 {
		return filterd[0].kind == u16(9000)
	}
	return false
}

fn ChatWsConnection.new(uri string) ChatWsConnection {
	return ChatWsConnection{
		uri: uri
	}
}

fn (mut cwc ChatWsConnection) connect(mut app App) {
	if cwc.uri == '' {
		app.msg_channel <- TermMessage.new(
			system:  true
			message: 'Please connect with /connect <relay_url>'
		)
		return
	}

	if cwc.ws != unsafe { nil } {
		cwc.ws.reset_state() or {
			app.msg_channel <- TermMessage{
				label:   '[ ${time.now().hhmm12()}]'
				message: '${err.str()}'
			}
		}
	}
	app.show_spinner = true

	cwc.ws = websocket.new_client(cwc.uri) or {
		app.msg_channel <- TermMessage.new(
			message:       err.str()
			label_bold:    true
			label_color:   term.bright_red
			message_color: term.bright_red
		)
		panic(err)
	}

	cwc.ws.logger.set_level(.disabled)
	cwc.ws.on_open_ref(cwc.on_open_callback, app)
	cwc.ws.on_close_ref(cwc.on_close_callback, app)
	cwc.ws.on_error_ref(cwc.on_err_callback, app)
	cwc.ws.on_message_ref(cwc.on_message_callback, app)
	cwc.ws.connect() or {
		app.show_spinner = false
		app.msg_channel <- TermMessage.new(
			message:       '${err} Try /reconnect'
			label_bold:    true
			label_color:   term.bright_red
			message_color: term.bright_red
		)
	}

	spawn cwc.ws.listen()
}

fn (cwc ChatWsConnection) on_open_callback(mut ws websocket.Client, a voidptr) ! {
	mut app := unsafe { &App(a) }
	app.show_spinner = false
	group_list_filter := vnostr.VNFilter.new(kinds: [u16(39000)])
	group_list_sub := vnostr.VNSubscription.new(
		id:      group_list_sub_id
		filters: [
			group_list_filter,
		]
	)
	ws.write_string(group_list_sub.subscribe()) or {
		app.msg_channel <- TermMessage.new(
			message:       err.str()
			label_bold:    true
			label_color:   term.bright_red
			message_color: term.bright_red
		)
	}
}

fn (mut cwc ChatWsConnection) on_message_callback(mut ws websocket.Client, msg &websocket.Message, a voidptr) ! {
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
								cwc.groups[group_id] = group
							}
							u16(9) {
								if !cwc.group_eose_reached {
									cwc.messages << relay_message.event
								} else {
									if pk := app.pk {
										your_public_key := pk.public_key_hex
										if relay_message.event.pubkey == your_public_key {
											label := '[ ${time.unix(relay_message.event.created_at).local().hhmm()} ] [ ${relay_message.event.pubkey[..8]} ]'
											app.msg_channel <- TermMessage.new(
												label:       label
												message:     relay_message.event.content.trim_space()
												label_bold:  true
												label_color: term.bright_cyan
											)
										}
									} else {
										label := '[ ${time.unix(relay_message.event.created_at).local().hhmm()} ] [ ${relay_message.event.pubkey[..8]} ]'
										app.msg_channel <- TermMessage.new(
											label:   label
											message: relay_message.event.content.trim_space()
										)
									}
								}
							}
							u16(9000), u16(9001) {
								// label := '[ ${relay_message.event.kind} ${time.unix(relay_message.event.created_at).local().hhmm()} ] [ ${relay_message.event.pubkey[..8]} ]'
								// app.msg_channel <- TermMessage.new(
								// 	label:   label
								// 	message: relay_message.event.str()
								// )
								h_tag := relay_message.event.filter_tags_by_name('h')
								if h_tag.len == 0 || h_tag[0].len < 2 {
									return
								}
								group_id := h_tag[0][1]

								pubkey_tag := relay_message.event.filter_tags_by_name('p')
								if pubkey_tag.len == 0 || pubkey_tag[0].len < 2 {
									return
								}
								pubkey := pubkey_tag[0][1]
								cwc.members << Member{
									group_id:   group_id
									pubkey:     pubkey
									created_at: relay_message.event.created_at
									kind:       relay_message.event.kind
								}

								// label := '[ ${relay_message.event.kind} ${time.unix(relay_message.event.created_at).local().hhmm()} ] [ ${relay_message.event.pubkey[..8]} ]'
								// app.msg_channel <- TermMessage.new(label: label, message: relay_message.event.str())
							}
							else {
								// label := '[ ${relay_message.event.kind} ${time.unix(relay_message.event.created_at).local().hhmm()} ] [ ${relay_message.event.pubkey[..8]} ]'
								// app.msg_channel <- TermMessage.new(label: label, message: relay_message.event.str())
							}
						}
					}
					vnostr.RelayMessageEOSE {
						if relay_message.subscription_id == group_list_sub_id {
							app.messages = []
							cwc.list_groups(mut app)
							cwc.subscribe_member_list(mut app)
						}
						if relay_message.subscription_id == group_messages_sub_id
							&& cwc.group_eose_reached == false {
							app.show_spinner = false
							cwc.messages.reverse_in_place()
							for e in cwc.messages {
								if pk := app.pk {
									your_public_key := pk.public_key_hex
									if e.pubkey == your_public_key {
										label := '[ ${time.unix(e.created_at).local().hhmm()} ] [ ${e.pubkey[..8]} ]'
										app.msg_channel <- TermMessage.new(
											label:       label
											message:     e.content.trim_space()
											label_bold:  true
											label_color: term.bright_cyan
										)
									}
								} else {
									label := '[ ${time.unix(e.created_at).local().hhmm()} ] [ ${e.pubkey[..8]} ]'
									app.msg_channel <- TermMessage.new(
										label:   label
										message: e.content.trim_space()
									)
								}
							}
							cwc.messages = []
							cwc.group_eose_reached = true
						}
						if relay_message.subscription_id == group_join_leave_sub_id {
							app.show_spinner = false
						}
					}
					vnostr.RelayMessageOK {
						if !relay_message.accepted {
							app.msg_channel <- TermMessage.new(
								system:  true
								error:   true
								message: relay_message.message
							)
						}
					}
					vnostr.RelayMessageClosed {
						app.msg_channel <- TermMessage.new(
							system:  true
							error:   true
							message: relay_message.message
						)
					}
					else {}
				}
			}
		}
		.close {
			app.msg_channel <- TermMessage.new(
				message:       '${ws.uri} closed'
				label_bold:    true
				label_color:   term.bright_yellow
				message_color: term.bright_yellow
			)
		}
		.binary_frame {
			app.msg_channel <- TermMessage.new(
				message:       '${ws.uri} binary frame'
				label_bold:    true
				label_color:   term.bright_yellow
				message_color: term.bright_yellow
			)
		}
		.ping {}
		.pong {}
		else {
			app.msg_channel <- TermMessage.new(
				message:       '${msg.opcode}'
				label_bold:    true
				label_color:   term.bright_yellow
				message_color: term.bright_yellow
			)
		}
	}
}

fn (mut cwc ChatWsConnection) on_err_callback(mut ws websocket.Client, err string, a voidptr) ! {
	mut app := unsafe { &App(a) }
	app.show_spinner = false
	app.tui.clear()
	app.tui.flush()
	app.msg_channel <- TermMessage.new(
		message:       err.str()
		label_bold:    true
		label_color:   term.bright_red
		message_color: term.bright_red
	)
}

fn (cwc ChatWsConnection) on_close_callback(mut ws websocket.Client, code int, reason string, a voidptr) ! {
	mut app := unsafe { &App(a) }
	app.msg_channel <- TermMessage.new(
		message:       'received close from ${ws.uri} ${code} ${reason}'
		label_bold:    true
		label_color:   term.bright_red
		message_color: term.bright_red
	)
}

fn (mut cwc ChatWsConnection) subscribe_member_list(mut app App) {
	app.show_spinner = true
	mut tags := []string{}
	tags << ['#h']
	for k, _ in cwc.groups {
		tags << k
	}

	group_join_leave_filter := vnostr.VNFilter.new(
		kinds: [u16(9000), u16(9001)]
		tags:  [
			tags,
		]
	)
	group_join_leave_sub := vnostr.VNSubscription.new(
		id:      group_join_leave_sub_id
		filters: [
			group_join_leave_filter,
		]
	)
	cwc.ws.write_string(group_join_leave_sub.subscribe()) or {
		app.msg_channel <- TermMessage.new(
			message:       err.str()
			label_bold:    true
			label_color:   term.bright_red
			message_color: term.bright_red
		)
	}
}

fn (mut cwc ChatWsConnection) subscribe_group(mut app App) {
	if cwc.ws == unsafe { nil } {
		return
	}
	if group := cwc.selected_group {
		app.show_spinner = true
		filter := vnostr.VNFilter.new(
			kinds: [u16(9)]
			tags:  [
				['#h', group.id],
			]
			limit: 100
		)
		sub := vnostr.VNSubscription.new(id: group_messages_sub_id, filters: [filter])
		cwc.ws.write_string(sub.subscribe()) or {
			app.msg_channel <- TermMessage.new(
				message:       err.str()
				label_bold:    true
				label_color:   term.bright_red
				message_color: term.bright_red
			)
			app.show_spinner = false
		}
	}
}

fn (mut cwc ChatWsConnection) unsubscrib_group(mut app App) {
	if cwc.ws == unsafe { nil } {
		return
	}
	if group := cwc.selected_group {
		sub := vnostr.VNSubscription.new(id: group.id)
		cwc.ws.write_string(sub.unsubscribe()) or {
			app.msg_channel <- TermMessage.new(
				message:       err.str()
				label_bold:    true
				label_color:   term.bright_red
				message_color: term.bright_red
			)
		}
		cwc.selected_group = none
		cwc.group_eose_reached = false
	}
}

fn (mut cwc ChatWsConnection) leave_group(mut app App) {
	if cwc.ws == unsafe { nil } {
		return
	}

	if group := cwc.selected_group {
		if pk := app.pk {
			created_at := u64(time.now().local_to_utc().unix())
			evt := vnostr.VNEvent.new(
				pubkey:     pk.public_key_hex
				created_at: created_at
				kind:       u16(9022)
				tags:       [['h', group.id], ['p', pk.public_key_hex]]
				content:    ''
			)

			signed_event := evt.sign(pk) or {
				app.msg_channel <- TermMessage.new(
					message:       err.str()
					label_bold:    true
					label_color:   term.bright_red
					message_color: term.bright_red
				)
				return
			}

			cwc.ws.write_string(signed_event.event_client_message()) or {
				app.msg_channel <- TermMessage.new(
					message:       err.str()
					label_bold:    true
					label_color:   term.bright_red
					message_color: term.bright_red
				)
				return
			}
		}
	}
}

fn (cwc ChatWsConnection) list_groups(mut app App) {
	app.msg_channel <- TermMessage.new(system: true, message: '-------------------------------')
	app.msg_channel <- TermMessage.new(system: true, message: 'Available groups')
	app.msg_channel <- TermMessage.new(system: true, message: '-------------------------------')
	for _, g in cwc.groups {
		app.msg_channel <- TermMessage.new(system: true, message: '${g.id} - ${g.name}')
	}
	app.msg_channel <- TermMessage.new(system: true, message: '-------------------------------')
}

fn (mut cwc ChatWsConnection) send_message(mut app App, message string) {
	if cwc.ws == unsafe { nil } {
		return
	}
	if group := cwc.selected_group {
		if pk := app.pk {
			created_at := u64(time.now().local_to_utc().unix())
			evt := vnostr.VNEvent.new(
				pubkey:     pk.public_key_hex
				created_at: created_at
				kind:       u16(9)
				tags:       [['h', group.id]]
				content:    message
			)

			signed_event := evt.sign(pk) or {
				app.msg_channel <- TermMessage.new(
					message:       err.str()
					label_bold:    true
					label_color:   term.bright_red
					message_color: term.bright_red
				)
				return
			}

			cwc.ws.write_string(signed_event.event_client_message()) or {
				app.msg_channel <- TermMessage.new(
					message:       err.str()
					label_bold:    true
					label_color:   term.bright_red
					message_color: term.bright_red
				)
				return
			}
		}
	}
}

fn (mut cwc ChatWsConnection) join_group(mut app App) {
	if cwc.ws == unsafe { nil } {
		return
	}
	if group := cwc.selected_group {
		app.show_spinner = true
		if pk := app.pk {
			created_at := u64(time.now().local_to_utc().unix())
			evt := vnostr.VNEvent.new(
				pubkey:     pk.public_key_hex
				created_at: created_at
				kind:       u16(9021)
				tags:       [['h', group.id], ['p', pk.public_key_hex]]
				content:    ''
			)

			signed_event := evt.sign(pk) or {
				app.msg_channel <- TermMessage.new(
					message:       err.str()
					label_bold:    true
					label_color:   term.bright_red
					message_color: term.bright_red
				)
				return
			}

			cwc.ws.write_string(signed_event.event_client_message()) or {
				app.msg_channel <- TermMessage.new(
					message:       err.str()
					label_bold:    true
					label_color:   term.bright_red
					message_color: term.bright_red
				)
				return
			}
		}
		app.show_spinner = false
	}
}
