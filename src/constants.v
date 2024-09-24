module main

import term.ui as tui

// const default_format = '\x00'.bytes()[0]
// const blue_format = '\x10'.bytes()[0]
// const yellow_format = '\x20'.bytes()[0]
// const red_format = '\x30'.bytes()[0]
// const bold_default_format = '\x80'.bytes()[0]
// const bold_blue_format = '\x90'.bytes()[0]
// const bold_yellow_format = '\xA0'.bytes()[0]
// const bold_red_format = '\xB0'.bytes()[0]

const color_black = tui.Color{
	r: 0
	g: 0
	b: 0
}
const color_green = tui.Color{
	r: 0
	g: 228
	b: 54
}
const color_blue = tui.Color{
	r: 41
	g: 173
	b: 255
}
const color_yellow = tui.Color{
	r: 255
	g: 236
	b: 39
}
const color_red = tui.Color{
	r: 255
	g: 0
	b: 77
}
