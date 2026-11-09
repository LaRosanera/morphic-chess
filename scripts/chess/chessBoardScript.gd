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
##
## ONLINE PLAY (host-authoritative):
##   1. The player whose turn it is clicks a target cell.
##   2. The move (plus the chosen promotion, if any) is sent to the host.
##   3. The host validates it with MoveRule and broadcasts it.
##   4. Every peer, host included, applies the broadcast move identically.
## Offline play uses the same code and skips steps 2-3.

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
const SETUP_SCENE := "res://Scenes/Main/game_setup.tscn"
const DEFAULT_PRESET := "res://assets/board/board_layouts/everything.json"

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
static var preset_path := DEFAULT_PRESET

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
var over := false

## Set while the promotion picker is open: {"from": Vector2i, "to": Vector2i}.
## The move has NOT been sent or applied yet.
var pending_promo := {}

var _pending_name := "Classic"
var player1_name := "White"
var player2_name := "Black"

var game_seed: int = 0
var rng := RandomNumberGenerator.new()

# --- online state ---
var _online := false
var local_color := "white"  # the color this peer controls (host's color on the host)
var flipped := false  # board drawn from black's side
var awaiting_result := false  # request sent, waiting for the host's verdict
var disconnected := false


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

	if _online:
		_log("ONLINE MATCH: you are %s.\n" % local_color.capitalize(), "#ffd166")
		NetworkManager.opponent_left.connect(_on_opponent_left)

		# Restarting makes no sense online; the button leaves the match instead.
		var restart_button := get_node_or_null("UI/Restart")
		if restart_button is Button:
			(restart_button as Button).text = "Leave"

	_update_status()

	if _pending_name != "":
		_log("Preset: %s\n" % _pending_name, "#ffd166")


func _load_game_configuration() -> void:
	var config: Dictionary = get_tree().get_meta("chess_config", {})

	player1_name = str(config.get("white_name", "White"))
	player2_name = str(config.get("black_name", "Black"))

	_online = str(config.get("mode", "local")) == "online"
	local_color = str(config.get("local_color", "white"))
	flipped = bool(config.get("board_flipped", false))

	if _online:
		# Both peers must build the exact same game: always use the seed that
		# came through the lobby, and the same default layout.
		game_seed = int(config.get("seed", 0))
		preset_path = DEFAULT_PRESET
	else:
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
	# Everything random happens HERE, once, from the shared seed, before any
	# move. Both peers run this in the same order and get the same result.

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
	p.position = _cell_pos(cell)

	grid[cell] = p
	game_types[color][piece_type] = true


func _set_piece_sprite(
	p: AnimatedSprite2D,
	color: String,
	piece_type: String
) -> void:
	p.animation = StringName("%s_%s" % [color, piece_type])
	p.flip_v = piece_type in FLIPPED_TYPES


# --------------------------------------------------
# BOARD ORIENTATION
# Logic always uses "white's view" cells. Only drawing and mouse input go
# through _vis(), which rotates the board 180 degrees when flipped.
# --------------------------------------------------

func _vis(cell: Vector2i) -> Vector2i:
	if not flipped:
		return cell

	return Vector2i(MoveRule.SIZE - 1 - cell.x, MoveRule.SIZE - 1 - cell.y)


func _cell_pos(cell: Vector2i) -> Vector2:
	return pieces.to_local(
		tiles.to_global(tiles.map_to_local(_vis(cell)))
	)


func _mouse_cell() -> Vector2i:
	# _vis() is its own inverse for a 180 degree rotation.
	return _vis(tiles.local_to_map(tiles.get_local_mouse_position()))


func _in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= 0 and cell.y >= 0
		and cell.x < MoveRule.SIZE and cell.y < MoveRule.SIZE
	)


# --------------------------------------------------
# INPUT
# --------------------------------------------------

func restart() -> void:
	# Connected to UI/Restart in the scene.
	if _online:
		_leave_match()
		return

	get_tree().reload_current_scene()


func _leave_match() -> void:
	NetworkManager.shutdown()
	get_tree().change_scene_to_file(SETUP_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if over or not pending_promo.is_empty() or awaiting_result:
		return

	# Online: you may only act on your own turn.
	if _online and turn != local_color:
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton

	if not mouse_event.pressed:
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := _mouse_cell()

	if selected != null and moves.has(cell):
		_on_target_chosen(grid.find_key(selected), cell)
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
		tiles.to_global(tiles.map_to_local(_vis(cell)))
	) - marker.size / 2.0

	marker.add_to_group("markers")
	marker.show()


# --------------------------------------------------
# MOVE FLOW: choose -> (promotion) -> submit -> validate -> apply
# --------------------------------------------------

## Local player clicked a legal-looking target. Resolve promotion first so the
## request carries everything the host needs.
func _on_target_chosen(from: Vector2i, to: Vector2i) -> void:
	var p: AnimatedSprite2D = grid[from]
	var rule: MoveRule = rules[MoveRule.type_of(p)]
	var far_rank := 0 if turn == "white" else MoveRule.SIZE - 1

	var victim = grid.get(to)
	var captures_king: bool = (
		victim != null and MoveRule.type_of(victim) == "king"
	)

	if rule.promotes and to.y == far_rank and not captures_king:
		var options := _promo_options(turn)

		if options.size() == 1:
			# Only one available type: promote automatically.
			_submit_move(from, to, options[0])
			return

		if options.size() > 1:
			pending_promo = {"from": from, "to": to}
			_deselect()
			_show_picker(options)
			status.text = "Promote to:"
			return

		# No eligible types: the piece stays as-is.

	_submit_move(from, to, "")


func _on_promo_chosen(piece_type: String) -> void:
	if pending_promo.is_empty():
		return

	var from: Vector2i = pending_promo["from"]
	var to: Vector2i = pending_promo["to"]

	pending_promo = {}
	picker.hide()

	_submit_move(from, to, piece_type)


func _submit_move(from: Vector2i, to: Vector2i, promo: String) -> void:
	if not _online:
		_apply_move(from, to, promo)
		return

	awaiting_result = true
	_deselect()

	if multiplayer.is_server():
		_host_handle_move(1, from, to, promo)
	else:
		_request_move.rpc_id(1, from, to, promo)


## Client -> host.
@rpc("any_peer", "reliable")
func _request_move(from: Vector2i, to: Vector2i, promo: String) -> void:
	if not multiplayer.is_server():
		return

	_host_handle_move(multiplayer.get_remote_sender_id(), from, to, promo)


## Runs on the host only (for its own moves and for the guest's requests).
func _host_handle_move(
	sender: int,
	from: Vector2i,
	to: Vector2i,
	promo: String
) -> void:
	var result := _check_move(_color_of_peer(sender), from, to, promo)

	if not result["ok"]:
		if sender == 1:
			_on_move_rejected()
		else:
			_move_rejected.rpc_id(sender)
		return

	# call_local: the host applies it too, so everyone runs the same code.
	_apply_move_rpc.rpc(from, to, result["promo"])


## Host -> everyone (including itself).
@rpc("authority", "call_local", "reliable")
func _apply_move_rpc(from: Vector2i, to: Vector2i, promo: String) -> void:
	_apply_move(from, to, promo)


## Host -> the guest whose request was refused.
@rpc("authority", "reliable")
func _move_rejected() -> void:
	_on_move_rejected()


func _on_move_rejected() -> void:
	awaiting_result = false
	_deselect()
	_update_status()


func _color_of_peer(peer_id: int) -> String:
	# On the host, local_color is the host's color; the guest has the other.
	if peer_id == 1:
		return local_color

	return "black" if local_color == "white" else "white"


## Host-side validation. Returns {"ok": bool, "promo": String}.
## The returned promo is authoritative; the client's choice is only a request.
func _check_move(
	color: String,
	from: Vector2i,
	to: Vector2i,
	promo: String
) -> Dictionary:
	var fail := {"ok": false, "promo": ""}

	if over or color != turn:
		return fail

	if not _in_bounds(from) or not _in_bounds(to):
		return fail

	var p = grid.get(from)

	if p == null or MoveRule.color_of(p) != color:
		return fail

	var piece_type := MoveRule.type_of(p)

	if not rules.has(piece_type):
		return fail

	var rule: MoveRule = rules[piece_type]
	var has_moved: bool = p.get_meta("moved", false)

	if not rule.get_targets(grid, from, color, has_moved).has(to):
		return fail

	var final_promo := ""
	var victim = grid.get(to)
	var captures_king: bool = (
		victim != null and MoveRule.type_of(victim) == "king"
	)
	var far_rank := 0 if color == "white" else MoveRule.SIZE - 1

	if rule.promotes and to.y == far_rank and not captures_king:
		var options := _promo_options(color)

		if options.size() == 1:
			final_promo = options[0]
		elif options.size() > 1:
			if not options.has(promo):
				return fail

			final_promo = promo

	return {"ok": true, "promo": final_promo}


## Runs on every peer with identical inputs, so every board stays identical.
func _apply_move(from: Vector2i, to: Vector2i, promo: String) -> void:
	var p: AnimatedSprite2D = grid.get(from)

	if p == null:
		return

	awaiting_result = false
	pending_promo = {}
	picker.hide()

	var victim = grid.get(to)
	var victim_type := ""

	grid.erase(from)

	if victim != null:
		victim_type = MoveRule.type_of(victim)
		victim.queue_free()
		over = victim_type == "king"

	grid[to] = p
	p.set_meta("moved", true)

	create_tween().tween_property(
		p,
		"position",
		_cell_pos(to),
		0.15
	)

	_deselect()
	_log_move(p, from, to, victim_type)

	if promo != "":
		var previous_type := MoveRule.type_of(p)

		_set_piece_sprite(p, turn, promo)

		_log(
			"   %s promoted to %s" % [previous_type, promo],
			_turn_color()
		)

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
		button.pressed.connect(_on_promo_chosen.bind(piece_type))
		picker.add_child(button)

	picker.show()


func _end_turn() -> void:
	if not over:
		turn = "black" if turn == "white" else "white"

	_update_status()


# --------------------------------------------------
# DISCONNECTS
# --------------------------------------------------

func _on_opponent_left() -> void:
	if disconnected or over:
		return

	disconnected = true
	over = true
	awaiting_result = false
	pending_promo = {}
	picker.hide()
	_deselect()

	_log("\nOpponent disconnected.", "#ff8a80")
	NetworkManager.shutdown()
	_update_status()


# --------------------------------------------------
# LOGGING / STATUS
# --------------------------------------------------

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
	# Disabled online: both peers must use the same layout.
	if _online:
		return

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
	if disconnected:
		status.text = "Opponent disconnected"
		return

	if over:
		status.text = "%s wins!" % _current_player_name()
		return

	var text := "%s's turn (%s)" % [
		_current_player_name(),
		turn.capitalize()
	]

	if _online:
		text += "  -  YOUR MOVE" if turn == local_color else "  -  waiting..."

	status.text = text


func _on_settings_pressed() -> void:
	var settings = SETTINGS_SCENE.instantiate()
	get_tree().root.add_child(settings)
	settings.call("setup", self)
