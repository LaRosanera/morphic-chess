extends Node2D
## Morphic Chess board. No check rules: capture the enemy king to win.
##
## Scene tree:
##   TileMapLayer - board tiles
##   Highlights   - SelectMarker / MoveMarker / CaptureMarker templates
##   Pieces       - container for spawned pieces
##   Rules        - MoveRule nodes
##   UI           - status, promotion picker, restart, terminal
##
## PromotionPicker should be an HBoxContainer, VBoxContainer,
## or another Container that lays out its buttons automatically.

## Each scene needs animations named "<color>_<type>".
## Examples: white_pawn, black_king, white_amazon.
## For placeholder art, keep the custom animation name but reuse
## the standard piece's frames:
##   camel -> knight art
##   man -> king art
##   minister -> queen art
@export var white_piece_scene: PackedScene
@export var black_piece_scene: PackedScene

## Back-rank order, a-file to h-file.
@export var back_rank: Array[String] = [
	"rook", "knight", "bishop", "queen",
	"king", "bishop", "knight", "rook"
]

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

const SETTINGS_SCENE = preload("res://Scenes/Main/settings.tscn")

## Custom types whose placeholder sprites are displayed upside down.
const FLIPPED_TYPES := ["camel", "man", "minister"]

## Promotion display order. Other custom types are appended afterward.
const PROMO_ORDER := [
	"queen", "amazon", "empress", "princess",
	"rook", "bishop", "knight", "camel",
	"elephant", "minister", "man"
]

const ORTHO: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

const DIAG: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

const KNIGHT: Array[Vector2i] = [
	Vector2i(1, 2),
	Vector2i(2, 1),
	Vector2i(-1, 2),
	Vector2i(-2, 1),
	Vector2i(1, -2),
	Vector2i(2, -1),
	Vector2i(-1, -2),
	Vector2i(-2, -1),
]

const CAMEL: Array[Vector2i] = [
	Vector2i(1, 3),
	Vector2i(3, 1),
	Vector2i(-1, 3),
	Vector2i(-3, 1),
	Vector2i(1, -3),
	Vector2i(3, -1),
	Vector2i(-1, -3),
	Vector2i(-3, -1),
]

const ALFIL: Array[Vector2i] = [
	Vector2i(2, 2),
	Vector2i(2, -2),
	Vector2i(-2, 2),
	Vector2i(-2, -2),
]

## Static so it survives restart() reloading the scene.
static var preset_path := "res://assets/board/board_layouts/everything.json"

@onready var tiles: TileMapLayer = $TileMapLayer
@onready var pieces: Node2D = $Pieces
@onready var highlights: Node2D = $Highlights
@onready var status: Label = $UI/Status
@onready var picker: Control = $UI/PromotionPicker
@onready var log_box: RichTextLabel = $UI/Terminal/Log

var daily_changes: Array[String] = []

var move_count := 0
var grid := {}  # Vector2i -> piece node
var rules := {}  # Piece type -> MoveRule node
var moves := {}  # Available target cells of the selected piece

## Piece types spawned in this game, recorded separately per color.
## Capturing a piece does not remove its type from promotion options.
var game_types := {
	"white": {},
	"black": {},
}

var turn := "white"
var selected: AnimatedSprite2D
var promoting: AnimatedSprite2D
var over := false

var _pending_name := "Classic"
var player1_name := "White"
var player2_name := "Black"

var game_seed: int = 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	picker.hide()
	_load_game_configuration()

	for y in range(MoveRule.SIZE):
		for x in range(MoveRule.SIZE):
			tiles.set_cell(
				Vector2i(x, y),
				0,
				Vector2i((x + y) % 2, 0)
			)

	_register_custom_rules()

	for child in $Rules.get_children():
		if child is MoveRule:
			var rule := child as MoveRule
			rules[rule.piece_type] = rule

	_apply_seeded_rules()
	_spawn_pieces()

	# Promotion buttons are created dynamically by _show_picker().
	# Do not connect the old static buttons here.

	_log("MORPHIC CHESS v0.1")
	_log("------------------")
	_log("No check rules. Capture the enemy king to win.")
	_log("%s to move.\n" % player1_name)

	_update_status()

	if _pending_name != "":
		_log("Preset: %s\n" % _pending_name, "#ffd166")


func _load_game_configuration() -> void:
	var config: Dictionary = get_tree().get_meta("chess_config", {})

	player1_name = str(config.get("white_name", "White"))
	player2_name = str(config.get("black_name", "Black"))

	var seed_path := "res://daily_seed.json"

	if FileAccess.file_exists(seed_path):
		var seed_text := FileAccess.get_file_as_string(seed_path).strip_edges()

		if seed_text.is_valid_int():
			game_seed = int(seed_text)
		else:
			game_seed = int(config.get("seed", 0))
	else:
		game_seed = int(
			config.get("seed", get_tree().get_meta("game_seed", 0))
		)

	rng.seed = game_seed

	_log("Seed: %d" % game_seed, "#ffd166")
	_log("Player 1 (White): %s" % player1_name)
	_log("Player 2 (Black): %s\n" % player2_name)


func _register_custom_rules() -> void:
	var existing := {}

	for child in $Rules.get_children():
		if child is MoveRule:
			var rule := child as MoveRule
			existing[rule.piece_type] = true

	var slide := MoveRule.SIZE - 1
	var all8: Array[Vector2i] = []
	all8.append_array(ORTHO)
	all8.append_array(DIAG)

	# Type: [ordinary directions, range, leap offsets]
	var definitions := {
		"minister": [DIAG, 1, []],
		"elephant": [[], 1, ALFIL],
		"camel": [[], 1, CAMEL],
		"man": [all8, 1, []],
		"princess": [DIAG, slide, KNIGHT],
		"empress": [ORTHO, slide, KNIGHT],
		"amazon": [all8, slide, KNIGHT],
	}

	for piece_type in definitions:
		# Keep any rule already configured in the scene.
		if existing.has(piece_type):
			continue

		var definition: Array = definitions[piece_type]
		var rule := MoveRule.new()

		rule.name = String(piece_type).capitalize()
		rule.piece_type = String(piece_type)
		rule.directions.assign(definition[0])
		rule.max_range = int(definition[1])
		rule.leap_directions.assign(definition[2])

		# Only leap_directions jump for these mixed-movement pieces.
		rule.jumps = false

		$Rules.add_child(rule)


func _apply_seeded_rules() -> void:
	# FEATURE 1: Randomize a standard sliding piece's range.
	var sliding_pieces := ["rook", "bishop", "queen"]
	var chosen_piece: String = sliding_pieces[
		rng.randi_range(0, sliding_pieces.size() - 1)
	]

	if rules.has(chosen_piece):
		var rule: MoveRule = rules[chosen_piece]
		rule.max_range = rng.randi_range(2, 7)

		_log(
			"%s range: %d" % [
				chosen_piece.capitalize(),
				rule.max_range
			],
			"#ffd166"
		)

	# FEATURE 2: Randomize the pawn's first move distance.
	if rules.has("pawn"):
		var pawn_rule: MoveRule = rules["pawn"]
		pawn_rule.first_move_range = rng.randi_range(2, 3)

		_log(
			"Pawn first move range: %d" % pawn_rule.first_move_range,
			"#ffd166"
		)

	# FEATURE 3: Give a standard sliding piece the ability to jump.
	var jump_pieces := ["rook", "bishop"]
	var jump_piece: String = jump_pieces[
		rng.randi_range(0, jump_pieces.size() - 1)
	]

	if rules.has(jump_piece):
		var jump_rule: MoveRule = rules[jump_piece]
		jump_rule.jumps = true

		_log(
			"%s can jump over pieces!" % jump_piece.capitalize(),
			"#ffd166"
		)


func _spawn_pieces() -> void:
	if preset_path != "" and _spawn_from_file(preset_path):
		return

	for x in range(MoveRule.SIZE):
		_spawn("black", back_rank[x], Vector2i(x, 0))
		_spawn("black", "pawn", Vector2i(x, 1))
		_spawn("white", "pawn", Vector2i(x, 6))
		_spawn("white", back_rank[x], Vector2i(x, 7))


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

			_spawn(color, piece_type, cell)

			# Pawns off their home rank do not receive the first-move bonus.
			if piece_type == "pawn":
				var home_rank := 6 if color == "white" else 1

				if y != home_rank:
					grid[cell].set_meta("moved", true)

	_pending_name = str(data.get("name", path.get_file()))
	return true


func _spawn(color: String, piece_type: String, cell: Vector2i) -> void:
	var scene: PackedScene = (
		white_piece_scene if color == "white" else black_piece_scene
	)
	var p := scene.instantiate() as AnimatedSprite2D

	_set_piece_sprite(p, color, piece_type)

	pieces.add_child(p)
	p.position = pieces.to_local(
		tiles.to_global(tiles.map_to_local(cell))
	)

	grid[cell] = p
	game_types[color][piece_type] = true


func _set_piece_sprite(
	p: AnimatedSprite2D,
	color: String,
	piece_type: String
) -> void:
	p.animation = StringName("%s_%s" % [color, piece_type])
	p.flip_v = piece_type in FLIPPED_TYPES


func restart() -> void:
	# Connected to UI/Restart in the scene.
	get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if over or promoting != null:
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton

	if not mouse_event.pressed:
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := tiles.local_to_map(tiles.get_local_mouse_position())

	if selected != null and moves.has(cell):
		_move(selected, cell)
	elif grid.has(cell) and MoveRule.color_of(grid[cell]) == turn:
		_select(grid[cell])
	else:
		_deselect()


func _select(p: AnimatedSprite2D) -> void:
	_deselect()

	var piece_type := MoveRule.type_of(p)

	if not rules.has(piece_type):
		return

	selected = p

	var from: Vector2i = grid.find_key(p)
	_mark($Highlights/SelectMarker, from)

	var rule: MoveRule = rules[piece_type]
	var has_moved: bool = p.get_meta("moved", false)

	for cell in rule.get_targets(grid, from, turn, has_moved):
		# Avoid duplicate markers if movement definitions overlap.
		if moves.has(cell):
			continue

		moves[cell] = true

		if grid.has(cell):
			_mark($Highlights/CaptureMarker, cell)
		else:
			_mark($Highlights/MoveMarker, cell)


func _deselect() -> void:
	selected = null
	moves.clear()
	get_tree().call_group("markers", "queue_free")


func _mark(template: ColorRect, cell: Vector2i) -> void:
	var marker := template.duplicate() as ColorRect

	highlights.add_child(marker)
	marker.position = highlights.to_local(
		tiles.to_global(tiles.map_to_local(cell))
	) - marker.size / 2.0

	marker.add_to_group("markers")
	marker.show()


func _move(p: AnimatedSprite2D, to: Vector2i) -> void:
	var from: Vector2i = grid.find_key(p)
	var victim = grid.get(to)
	var victim_type := ""

	grid.erase(from)

	if victim != null:
		victim_type = MoveRule.type_of(victim)
		victim.queue_free()
		over = victim_type == "king"

	grid[to] = p
	p.set_meta("moved", true)

	var target_position := pieces.to_local(
		tiles.to_global(tiles.map_to_local(to))
	)

	create_tween().tween_property(
		p,
		"position",
		target_position,
		0.15
	)

	_deselect()
	_log_move(p, from, to, victim_type)

	var rule: MoveRule = rules[MoveRule.type_of(p)]
	var far_rank := 0 if turn == "white" else MoveRule.SIZE - 1

	if rule.promotes and to.y == far_rank and not over:
		var options := _promo_options(turn)

		if not options.is_empty():
			promoting = p

			if options.size() == 1:
				# Only one available type: promote automatically.
				_promote(options[0])
				return

			_show_picker(options)
			status.text = "Promote to:"
			return

		# No eligible types: leave the piece as-is and end the turn.

	_end_turn()


func _promo_options(color: String) -> Array[String]:
	var options: Array[String] = []
	var available: Dictionary = game_types[color]

	for piece_type in PROMO_ORDER:
		if available.has(piece_type) and rules.has(piece_type):
			options.append(piece_type)

	# Include other registered custom types not in PROMO_ORDER.
	for key in available:
		var piece_type := String(key)

		if piece_type == "pawn" or piece_type == "king":
			continue

		if not rules.has(piece_type):
			continue

		if not options.has(piece_type):
			options.append(piece_type)

	return options


func _show_picker(options: Array[String]) -> void:
	# Remove existing scene buttons or buttons from the previous promotion.
	for child in picker.get_children():
		picker.remove_child(child)
		child.queue_free()

	for piece_type in options:
		var button := Button.new()
		button.name = piece_type.capitalize()
		button.text = piece_type.capitalize()
		button.pressed.connect(_promote.bind(piece_type))
		picker.add_child(button)

	picker.show()


func _promote(piece_type: String) -> void:
	if promoting == null or over:
		return

	# Reject stale or invalid promotion requests.
	if not _promo_options(turn).has(piece_type):
		return

	var previous_type := MoveRule.type_of(promoting)

	_set_piece_sprite(promoting, turn, piece_type)

	promoting = null
	picker.hide()

	_log(
		"   %s promoted to %s" % [previous_type, piece_type],
		_turn_color()
	)

	_end_turn()


func _end_turn() -> void:
	if not over:
		turn = "black" if turn == "white" else "white"

	_update_status()


func _sq(cell: Vector2i) -> String:
	return "%s%d" % [char(97 + cell.x), MoveRule.SIZE - cell.y]


func _turn_color() -> String:
	return "#ffffff" if turn == "white" else "#9aa0a6"


func _log(text: String, color := "#7cfc7c") -> void:
	log_box.append_text("[color=%s]%s[/color]\n" % [color, text])


func _log_move(
	p: AnimatedSprite2D,
	_from: Vector2i,
	to: Vector2i,
	victim_type: String
) -> void:
	move_count += 1

	var line := "%d. %s (%s) %s -> %s" % [
		move_count,
		_current_player_name(),
		turn.capitalize(),
		MoveRule.type_of(p),
		_sq(to)
	]

	if victim_type != "":
		line += " x%s" % victim_type

	_log(line, _turn_color())

	if over:
		_log(
			"\n%s wins! King captured." % _current_player_name(),
			"#ffd166"
		)


func open_preset_picker() -> void:
	# Connect a Load button's pressed signal to this function.
	var dialog := FileDialog.new()

	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Board presets"])
	dialog.use_native_dialog = true

	dialog.file_selected.connect(
		func(path: String) -> void:
			preset_path = path
			restart()
	)

	dialog.canceled.connect(dialog.queue_free)

	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _current_player_name() -> String:
	return player1_name if turn == "white" else player2_name


func _update_status() -> void:
	if over:
		status.text = "%s wins!" % _current_player_name()
	else:
		status.text = "%s's turn (%s)" % [
			_current_player_name(),
			turn.capitalize()
		]


func _on_settings_pressed() -> void:
	var settings = SETTINGS_SCENE.instantiate()
	get_tree().root.add_child(settings)
	settings.call("setup", self)
