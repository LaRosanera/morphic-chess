class_name GameLog
extends RefCounted
## Writes colored lines to the in-game terminal (UI/Terminal/Log).

const GREEN := "#7cfc7c"
const GOLD := "#ffd166"
const RED := "#ff8a80"
const WHITE := "#ffffff"
const GRAY := "#9aa0a6"

var _box: RichTextLabel


func _init(box: RichTextLabel) -> void:
	_box = box


func write(text: String, color := GREEN) -> void:
	_box.append_text("[color=%s]%s[/color]\n" % [color, text])


## "e4"-style name for a cell.
static func square(cell: Vector2i) -> String:
	return "%s%d" % [char(97 + cell.x), MoveRule.SIZE - cell.y]


## Log color for the side that is moving.
static func color_for(turn: String) -> String:
	return WHITE if turn == "white" else GRAY
