class_name PieceSpawner
extends RefCounted
## Creates the starting pieces, from a preset JSON file or the default
## layout, and registers them in the GameState grid.

const LETTERS := {
	"p": "pawn",
	"n": "knight",
	"b": "bishop",
	"r": "rook",
	"q": "queen",
	"k": "king",
	"a": "amazon",
	"c": "camel",
	"l": "elephant",
	"s": "empress",
	"x": "princess",
	"m": "man",
	"i": "minister",
}

## Custom types whose placeholder sprites are displayed upside down.
const FLIPPED_TYPES := ["camel", "man", "minister"]

## Name shown in the log: the preset's name, or "Classic" for the default.
var preset_name := "Classic"

var _white_scene: PackedScene
var _black_scene: PackedScene
var _back_rank: Array[String]
var _state: GameState
var _view: BoardView


func _init(
	white_scene: PackedScene,
	black_scene: PackedScene,
	back_rank: Array[String],
	state: GameState,
	view: BoardView
) -> void:
	_white_scene = white_scene
	_black_scene = black_scene
	_back_rank = back_rank
	_state = state
	_view = view


## Spawns the preset if it loads, otherwise the default layout.
## Returns the name to show in the log.
func spawn_all(preset_path: String) -> String:
	if preset_path != "" and _spawn_from_file(preset_path):
		return preset_name

	for x in range(MoveRule.SIZE):
		spawn("black", _back_rank[x], Vector2i(x, 0))
		spawn("black", "pawn", Vector2i(x, 1))
		spawn("white", "pawn", Vector2i(x, 6))
		spawn("white", _back_rank[x], Vector2i(x, 7))

	return preset_name


func spawn(color: String, piece_type: String, cell: Vector2i) -> void:
	var scene: PackedScene = (
		_white_scene if color == "white" else _black_scene
	)
	var p := scene.instantiate() as AnimatedSprite2D

	set_sprite(p, color, piece_type)

	_view.pieces.add_child(p)
	p.position = _view.cell_pos(cell)

	_state.grid[cell] = p
	_state.game_types[color][piece_type] = true


static func set_sprite(
	p: AnimatedSprite2D,
	color: String,
	piece_type: String
) -> void:
	p.animation = StringName("%s_%s" % [color, piece_type])
	p.flip_v = piece_type in FLIPPED_TYPES


func _spawn_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var data = JSON.parse_string(FileAccess.get_file_as_string(path))

	if not (data is Dictionary):
		return false

	if not (data.get("board") is Array):
		return false

	var rows: Array = data["board"]

	# Validate rows before spawning anything.
	for y in range(mini(rows.size(), MoveRule.SIZE)):
		if not (rows[y] is String):
			return false

	for y in range(mini(rows.size(), MoveRule.SIZE)):
		var row: String = rows[y]

		for x in range(mini(row.length(), MoveRule.SIZE)):
			var ch := row.substr(x, 1)
			var piece_type: String = LETTERS.get(ch.to_lower(), "")

			if piece_type == "":
				continue

			var color := "white" if ch == ch.to_upper() else "black"
			var cell := Vector2i(x, y)

			spawn(color, piece_type, cell)

			# Pawns off their home rank do not receive the first-move bonus.
			if piece_type == "pawn":
				var home_rank := 6 if color == "white" else 1

				if y != home_rank:
					_state.grid[cell].set_meta("moved", true)

	preset_name = str(data.get("name", path.get_file()))
	return true
