extends Node2D
## Morphic Chess board. No check rules: capture the enemy king to win.
##
## Almost everything lives in the scene tree:
##   TileMapLayer - the board (filled from the two tiles)
##   Highlights   - marker templates (SelectMarker / MoveMarker / CaptureMarker)
##   Pieces       - empty container; pieces are spawned by code in _spawn_pieces()
##   Rules        - one MoveRule node per piece type; edit them to change how pieces move
##   UI           - status label, promotion buttons, restart button

## Swap these two scenes to change the sprite set. Each needs animations named "<color>_<type>"
## (white_pawn, black_king, ...).
@export var white_piece_scene: PackedScene
@export var black_piece_scene: PackedScene
## Back-rank order, a-file to h-file.
@export var back_rank: Array[String] = ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]
var daily_changes: Array[String] = []
@onready var tiles: TileMapLayer = $TileMapLayer
@onready var pieces: Node2D = $Pieces
@onready var highlights: Node2D = $Highlights
@onready var status: Label = $UI/Status
@onready var picker: Control = $UI/PromotionPicker
@onready var log_box: RichTextLabel = $UI/Terminal/Log

const LETTERS := {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook", "q": "queen", "k": "king"}
const SETTINGS_SCENE = preload("res://Scenes/Main/settings.tscn")

## static so it survives restart() reloading the scene
static var preset_path := "res://assets/board/board_layouts/classic.json"
var move_count := 0
var grid := {}            # Vector2i -> piece node
var rules := {}           # piece type -> MoveRule node
var moves := {}           # legal target cells of the selected piece
var turn := "white"
var selected: AnimatedSprite2D
var promoting: AnimatedSprite2D
var over := false
var _pending_name := ""
var player1_name := "White"
var player2_name := "Black"

var game_seed: int = 0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	_load_game_configuration()

	for y in MoveRule.SIZE:
		for x in MoveRule.SIZE:
			tiles.set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 2, 0))

	for r: MoveRule in $Rules.get_children():
		rules[r.piece_type] = r
	
	_apply_seeded_rules()
	
	_spawn_pieces()

	for b: Button in picker.get_children():
		b.pressed.connect(_promote.bind(String(b.name).to_lower()))

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

	# Read the seed from daily_seed.json
	var seed_path := "res://daily_seed.json"

	if FileAccess.file_exists(seed_path):
		var seed_text := FileAccess.get_file_as_string(seed_path).strip_edges()

		if seed_text.is_valid_int():
			game_seed = int(seed_text)
		else:
			game_seed = int(config.get("seed", 0))
	else:
		game_seed = int(config.get("seed", get_tree().get_meta("game_seed", 0)))

	rng.seed = game_seed

	_log("Seed: %d" % game_seed, "#ffd166")
	_log("Player 1 (White): %s" % player1_name)
	_log("Player 2 (Black): %s\n" % player2_name)

func _spawn_pieces() -> void:
	if preset_path != "" and _spawn_from_file(preset_path):
		return
	for x in MoveRule.SIZE:
		_spawn("black", back_rank[x], Vector2i(x, 0))
		_spawn("black", "pawn", Vector2i(x, 1))
		_spawn("white", "pawn", Vector2i(x, 6))
		_spawn("white", back_rank[x], Vector2i(x, 7))
func _apply_seeded_rules() -> void:

	# FEATURE 1: Randomize a sliding piece's range.
	var sliding_pieces := ["rook", "bishop", "queen"]
	var chosen_piece: String = sliding_pieces[rng.randi_range(0, 2)]

	if rules.has(chosen_piece):
		var rule: MoveRule = rules[chosen_piece]
		rule.max_range = rng.randi_range(2, 7)

		_log(
			"%s range: %d" % [chosen_piece.capitalize(), rule.max_range],
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

	# FEATURE 3: Give a randomly selected sliding piece the ability to jump.
	var jump_pieces := ["rook", "bishop"]
	var jump_piece: String = jump_pieces[rng.randi_range(0, 1)]

	if rules.has(jump_piece):
		var jump_rule: MoveRule = rules[jump_piece]
		jump_rule.jumps = true

		_log(
			"%s can jump over pieces!" % jump_piece.capitalize(),
			"#ffd166"
		)

func _spawn_from_file(path: String) -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary and data.get("board") is Array):
		return false
	var rows: Array = data["board"]
	for y in mini(rows.size(), MoveRule.SIZE):
		var row: String = rows[y]
		for x in mini(row.length(), MoveRule.SIZE):
			var ch := row[x]
			var type: String = LETTERS.get(ch.to_lower(), "")
			if type == "":
				continue
			var color := "white" if ch == ch.to_upper() else "black"
			var cell := Vector2i(x, y)
			_spawn(color, type, cell)
			# pawns off their home rank shouldn't get the double step
			if type == "pawn" and y != (6 if color == "white" else 1):
				grid[cell].set_meta("moved", true)
	_pending_name = str(data.get("name", path.get_file()))
	return true


func _spawn(color: String, type: String, cell: Vector2i) -> void:
	var p: AnimatedSprite2D = (white_piece_scene if color == "white" else black_piece_scene).instantiate()
	p.animation = StringName("%s_%s" % [color, type])
	p.position = tiles.map_to_local(cell)
	pieces.add_child(p)
	grid[cell] = p


func restart() -> void: # connected to UI/Restart in the scene
	get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if over or promoting or not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var cell := tiles.local_to_map(get_local_mouse_position())
	if selected and moves.has(cell):
		_move(selected, cell)
	elif grid.has(cell) and MoveRule.color_of(grid[cell]) == turn:
		_select(grid[cell])
	else:
		_deselect()


func _select(p: AnimatedSprite2D) -> void:
	_deselect()
	var type := MoveRule.type_of(p)
	if not rules.has(type):
		return
	selected = p
	var from: Vector2i = grid.find_key(p)
	_mark($Highlights/SelectMarker, from)
	var rule: MoveRule = rules[type]
	for cell in rule.get_targets(grid, from, turn, p.get_meta("moved", false)):
		moves[cell] = true
		_mark($Highlights/CaptureMarker if grid.has(cell) else $Highlights/MoveMarker, cell)


func _deselect() -> void:
	selected = null
	moves.clear()
	get_tree().call_group("markers", "queue_free")


func _mark(template: ColorRect, cell: Vector2i) -> void:
	var m := template.duplicate() as ColorRect
	m.position = tiles.map_to_local(cell) - m.size / 2.0
	m.add_to_group("markers")
	m.show()
	highlights.add_child(m)


func _move(p: AnimatedSprite2D, to: Vector2i) -> void:
	var from: Vector2i = grid.find_key(p)
	var victim = grid.get(to)
	var victim_type := ""
	grid.erase(from)
	if victim:
		victim_type = MoveRule.type_of(victim)
		victim.queue_free()
		over = victim_type == "king"
	grid[to] = p
	p.set_meta("moved", true)
	create_tween().tween_property(p, "position", tiles.map_to_local(to), 0.15)
	_deselect()
	_log_move(p, from, to, victim_type)

	var rule: MoveRule = rules[MoveRule.type_of(p)]
	var far_rank := 0 if turn == "white" else MoveRule.SIZE - 1
	if rule.promotes and to.y == far_rank and not over:
		promoting = p
		picker.show()
		status.text = "Promote to:"
		return
	_end_turn()


func _promote(type: String) -> void:
	promoting.animation = StringName("%s_%s" % [turn, type])
	promoting = null
	picker.hide()
	_log("   pawn promoted to %s" % type, _turn_color())
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
		_log("\n%s wins! King captured." % _current_player_name(), "#ffd166")
func open_preset_picker() -> void: # connect a "Load" button's pressed signal to this
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = ["*.json ; Board presets"]
	dlg.use_native_dialog = true
	dlg.file_selected.connect(func(path: String):
		preset_path = path
		restart())
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)
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
