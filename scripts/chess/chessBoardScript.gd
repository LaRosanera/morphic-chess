extends Node2D
## Main board coordinator.
## Game rules/state, visuals, spawning, promotion UI, logging, and networking
## are handled by the helper classes.

@export var white_piece_scene: PackedScene
@export var black_piece_scene: PackedScene

@export var back_rank: Array[String] = [
	"rook", "knight", "bishop", "queen",
	"king", "bishop", "knight", "rook"
]
const PIECE_PITCHES := {
	"pawn": -6,      # C4
	"knight": -5,    # C#4
	"bishop": -4,    # D4
	"rook": -3,      # D#4
	"queen": -2,     # E4
	"king": -1,      # F4
	"amazon": 0,     # F#4
	"camel": 1,      # G4
	"elephant": 2,   # G#4
	"empress": 3,    # A4
	"princess": 4,   # A#4
	"man": 5,        # B4
	"minister": 6    # C5
}
const SETTINGS_SCENE = preload("res://Scenes/Main/settings.tscn")
const SETUP_SCENE := "res://Scenes/Main/game_setup.tscn"
const DEFAULT_PRESET := "res://assets/board/board_layouts/everything.json"
## Static so it survives restart() reloading the scene.
static var preset_path := DEFAULT_PRESET

@onready var tiles: TileMapLayer = $TileMapLayer
@onready var pieces: Node2D = $Pieces
@onready var highlights: Node2D = $Highlights
@onready var status: Label = $UI/Status
@onready var picker: Control = $UI/PromotionPicker
@onready var log_box: RichTextLabel = $UI/Terminal/Log
@onready var piano_key_player: AudioStreamPlayer2D = $piano_key_player
var daily_changes: Array[String] = []

var player1_name := "White"
var player2_name := "Black"
var game_seed := 0

var _config: GameConfig
var _state: GameState
var _view: BoardView
var _log_writer: GameLog
var _spawner: PieceSpawner
var _promotion_ui: PromotionUI
var _online_sync: OnlineSync

var _online := false
var local_color := "white"
var awaiting_result := false
var disconnected := false

var selected: AnimatedSprite2D
var moves: Dictionary = {}
var pending_promo: Dictionary = {}
var _pending_name := "Classic"

# Compatibility properties: existing scene scripts/settings can continue
# reading the names exposed by the previous chessBoardScript.gd.
var grid: Dictionary:
	get:
		return _state.grid if _state != null else {}

var rules: Dictionary:
	get:
		return _state.rules if _state != null else {}

var game_types: Dictionary:
	get:
		return _state.game_types if _state != null else {}

var turn: String:
	get:
		return _state.turn if _state != null else "white"
	set(value):
		if _state != null:
			_state.turn = value

var over: bool:
	get:
		return _state.over if _state != null else false
	set(value):
		if _state != null:
			_state.over = value

var move_count: int:
	get:
		return _state.move_count if _state != null else 0
	set(value):
		if _state != null:
			_state.move_count = value

var flipped: bool:
	get:
		return _config.flipped if _config != null else false

# Small forwarding methods retained for compatibility with scripts that used
# the original board coordinator's helper methods.
func _vis(cell: Vector2i) -> Vector2i:
	return _view.vis(cell) if _view != null else cell

func _cell_pos(cell: Vector2i) -> Vector2:
	return _view.cell_pos(cell) if _view != null else Vector2.ZERO

func _mouse_cell() -> Vector2i:
	return _view.mouse_cell() if _view != null else Vector2i(-1, -1)

func _in_bounds(cell: Vector2i) -> bool:
	return _state.in_bounds(cell) if _state != null else false

func _sq(cell: Vector2i) -> String:
	return GameLog.square(cell)

func _set_piece_sprite(piece: AnimatedSprite2D, color: String, piece_type: String) -> void:
	PieceSpawner.set_sprite(piece, color, piece_type)


func _ready() -> void:
	_config = GameConfig.from_tree(get_tree())
	_online = _config.online
	local_color = _config.local_color
	player1_name = _config.white_name
	player2_name = _config.black_name
	game_seed = _config.game_seed

	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed

	_state = GameState.new()
	_log_writer = GameLog.new(log_box)
	_view = BoardView.new(tiles, pieces, highlights, _config.flipped)
	_promotion_ui = PromotionUI.new(picker)

	_view.build_tiles()

	RuleSetup.register_custom($Rules)
	_state.rules = RuleSetup.collect($Rules)
	RuleSetup.apply_seeded(_state.rules, rng, _log_writer)

	_spawner = PieceSpawner.new(
		white_piece_scene,
		black_piece_scene,
		back_rank,
		_state,
		_view
	)
	_pending_name = _spawner.spawn_all(
		DEFAULT_PRESET if _online else preset_path
	)

	_promotion_ui.chosen.connect(_on_promo_chosen)

	# RPC node path must be identical on host and guest.
	_online_sync = OnlineSync.new()
	_online_sync.name = "OnlineSync"
	add_child(_online_sync)
	_online_sync.setup(_state, local_color)
	_online_sync.move_approved.connect(_apply_move)
	_online_sync.move_rejected.connect(_on_move_rejected)

	_log("MORPHIC CHESS v0.1")
	_log("------------------")
	_log("No check rules. Capture the enemy king to win.")
	_log("%s to move.\n" % player1_name)

	if _online:
		_log("ONLINE MATCH: you are %s.\n" % local_color.capitalize(), GameLog.GOLD)
		if not NetworkManager.opponent_left.is_connected(_on_opponent_left):
			NetworkManager.opponent_left.connect(_on_opponent_left)

		var restart_button := get_node_or_null("UI/Restart")
		if restart_button is Button:
			(restart_button as Button).text = "Leave"

	_update_status()

	if _pending_name != "":
		_log("Preset: %s\n" % _pending_name, GameLog.GOLD)


# --------------------------------------------------
# INPUT / SELECTION
# --------------------------------------------------

func restart() -> void:
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

	if _online and turn != local_color:
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := _view.mouse_cell()

	if selected != null and moves.has(cell):
		_on_target_chosen(grid.find_key(selected), cell)
	elif grid.has(cell) and MoveRule.color_of(grid[cell]) == turn:
		_select(grid[cell])
	else:
		_deselect()


func _select(piece: AnimatedSprite2D) -> void:
	_deselect()

	var piece_type := MoveRule.type_of(piece)
	if not rules.has(piece_type):
		return

	selected = piece
	var from: Vector2i = grid.find_key(piece)
	_view.show_select(from)

	for cell in _state.targets(piece, from):
		if moves.has(cell):
			continue

		moves[cell] = true
		if grid.has(cell):
			_view.show_capture(cell)
		else:
			_view.show_move(cell)


func _deselect() -> void:
	selected = null
	moves.clear()
	if _view != null:
		_view.clear_marks()


# --------------------------------------------------
# MOVE FLOW
# --------------------------------------------------

func _on_target_chosen(from: Vector2i, to: Vector2i) -> void:
	var piece: AnimatedSprite2D = grid[from]

	if _state.promotes_on(piece, to):
		var options := _state.promo_options(turn)

		if options.size() == 1:
			_submit_move(from, to, options[0])
			return

		if options.size() > 1:
			pending_promo = {"from": from, "to": to}
			_deselect()
			_promotion_ui.show_options(options)
			status.text = "Promote to:"
			return

	_submit_move(from, to, "")


func _on_promo_chosen(piece_type: String) -> void:
	if pending_promo.is_empty():
		return

	var from: Vector2i = pending_promo["from"]
	var to: Vector2i = pending_promo["to"]

	pending_promo.clear()
	_promotion_ui.hide()
	_submit_move(from, to, piece_type)


func _submit_move(from: Vector2i, to: Vector2i, promo: String) -> void:
	if not _online:
		_apply_move(from, to, promo)
		return

	awaiting_result = true
	_deselect()
	_online_sync.submit(from, to, promo)

func _apply_move(from: Vector2i, to: Vector2i, promo: String) -> void:
	var piece: AnimatedSprite2D = grid.get(from)
	if piece == null:
		return

	awaiting_result = false
	pending_promo.clear()
	_promotion_ui.hide()

	var piece_type := MoveRule.type_of(piece)
	var semitones: int = PIECE_PITCHES.get(piece_type, 0)
	print(MoveRule.type_of(piece))
	piano_key_player.pitch_scale = pow(2.0, float(semitones) / 12.0)
	print(piano_key_player.pitch_scale)
	piano_key_player.play()

	var victim_type := _state.move_piece(from, to)
	_view.slide(piece, to)

	_log_move(piece, from, to, victim_type)

	if promo != "":
		var previous_type := MoveRule.type_of(piece)
		PieceSpawner.set_sprite(piece, turn, promo)
		_log(
			"   %s promoted to %s" % [previous_type, promo],
			_turn_color()
		)

	_deselect()
	_state.end_turn()
	_update_status()

func _on_move_rejected() -> void:
	awaiting_result = false
	_deselect()
	_update_status()


# --------------------------------------------------
# DISCONNECTS
# --------------------------------------------------

func _on_opponent_left() -> void:
	if disconnected or over:
		return

	disconnected = true
	_state.over = true
	awaiting_result = false
	pending_promo.clear()
	_promotion_ui.hide()
	_deselect()

	_log("\nOpponent disconnected.", GameLog.RED)
	NetworkManager.shutdown()
	_update_status()


# --------------------------------------------------
# LOGGING / STATUS
# --------------------------------------------------

func _log(message: String, color := GameLog.GREEN) -> void:
	_log_writer.write(message, color)


func _log_move(
	piece: AnimatedSprite2D,
	_from: Vector2i,
	to: Vector2i,
	victim_type: String
) -> void:
	_state.move_count += 1

	var line := "%d. %s (%s) %s -> %s" % [
		move_count,
		_current_player_name(),
		turn.capitalize(),
		MoveRule.type_of(piece),
		GameLog.square(to)
	]

	if victim_type != "":
		line += " x%s" % victim_type

	_log(line, GameLog.color_for(turn))

	if over:
		_log(
			"\n%s wins! King captured." % _current_player_name(),
			GameLog.GOLD
		)


func _current_player_name() -> String:
	return _config.name_of(turn)


func _turn_color() -> String:
	return GameLog.color_for(turn)


func _update_status() -> void:
	if disconnected:
		status.text = "Opponent disconnected"
		return

	if over:
		status.text = "%s wins!" % _current_player_name()
		return

	var status_text := "%s's turn (%s)" % [
		_current_player_name(),
		turn.capitalize()
	]

	if _online:
		status_text += "  -  YOUR MOVE" if turn == local_color else "  -  waiting..."

	status.text = status_text


# --------------------------------------------------
# PRESETS / SETTINGS
# --------------------------------------------------

func open_preset_picker() -> void:
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


func _on_settings_pressed() -> void:
	var settings = SETTINGS_SCENE.instantiate()
	get_tree().root.add_child(settings)
	settings.call("setup", self)
