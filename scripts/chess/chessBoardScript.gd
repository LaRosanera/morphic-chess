extends Node2D
## Main board coordinator.
## Game rules/state, visuals, spawning, promotion UI, logging, and networking
## are handled by the helper classes.

const MOVE_GUIDE := preload("res://Scenes/Chess/move_guide.tscn")

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
const SETUP_SCENE := "res://Scenes/Main/game_setup.tscn"
const PRESET_DIR := "res://assets/board/board_layouts/"

## Only set when the player picks a file manually. Empty = random from the folder.
## Static so it survives restart() reloading the scene.
static var preset_path := ""
var current_preset := ""

## Set by restart() so the reloaded scene skips the guide exactly once.
static var skip_intro_once := false

const DESIGN_SIZE := Vector2(768, 552)
@onready var guide: Button = $UI/Guide
@onready var background_rect: ColorRect = $background/ColorRect
@onready var tiles: TileMapLayer = $TileMapLayer
@onready var pieces: Node2D = $Pieces
@onready var highlights: Node2D = $Highlights
@onready var status: Label = $UI/Status
@onready var picker: Control = $UI/PromotionPicker
@onready var log_box: RichTextLabel = $UI/Terminal/Log
@onready var piano_key_player: AudioStreamPlayer2D = $piano_key_player
@onready var button_audio: AudioStreamPlayer2D = $ButtonAudio
@onready var white_clock: Label = $UI/WhiteClock
@onready var black_clock: Label = $UI/BlackClock

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


var _clock: ChessClock
var _clock_sync: ClockSync
var _clock_labels := {}
var _clock_synced := true
var _sync_retry := 0.0
var time_expired := false

# --- Move guide intro ---
var _guide: Control
var _game_started := false
var _ready_colors := {"white": false, "black": false}
var _ready_resend := 0.0

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

var promo_pool: Array[String]:
	get:
		return _state.promo_pool if _state != null else []

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
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()
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

	_spawner = PieceSpawner.new(
		white_piece_scene,
		black_piece_scene,
		back_rank,
		_state,
		_view
	)
	var presets := list_presets()
	current_preset = ""

	if not presets.is_empty():
		current_preset = presets[rng.randi_range(0, presets.size() - 1)]

	# A manually picked file overrides the random choice (offline only).
	if not _online and preset_path != "":
		current_preset = preset_path

	_pending_name = _spawner.spawn_all(current_preset)

	var has_promoter := false
	for piece in _state.grid.values():
		var rule: MoveRule = _state.rules.get(MoveRule.type_of(piece))
		if rule != null and rule.promotes:
			has_promoter = true
			break

	if has_promoter:
		_state.promo_pool = RuleSetup.pick_promo_pool(_state.rules, game_seed)
	else:
		_state.promo_pool = []

	var allowed := {}
	for color in _state.game_types:
		for t in _state.game_types[color]:
			allowed[t] = true
	for t in _state.promo_pool:
		allowed[t] = true

	_state.castle_types = RuleSetup.apply_seeded(
		_state.rules,
		rng,
		_log_writer,
		allowed
	)
	if has_promoter:
		var line := "Promotion options: %s" % ", ".join(
			_state.promo_pool.map(func(t): return t.capitalize())
		)
		RuleSetup.changes.append(line)
		_log(line, GameLog.GOLD)
	else:
		RuleSetup.changes.append("Promotion disabled (no pawns on the board)")
		_log("No pawns on the board: promotion disabled", GameLog.GOLD)

	_promotion_ui.chosen.connect(_on_promo_chosen)

	# RPC node path must be identical on host and guest.
	_online_sync = OnlineSync.new()
	_online_sync.name = "OnlineSync"
	add_child(_online_sync)
	_online_sync.setup(_state, local_color)
	_online_sync.move_approved.connect(_apply_move)
	_online_sync.move_rejected.connect(_on_move_rejected)

	_clock = ChessClock.new()
	_clock.setup(_config.initial_time, _config.increment)
	_clock.expired.connect(_on_clock_expired)
	_build_clock_ui()

	if _online:
		_clock_sync = ClockSync.new()
		_clock_sync.name = "ClockSync"
		add_child(_clock_sync)
		_clock_sync.setup(_clock)
		_clock_sync.timed_out.connect(_on_clock_timed_out)
		_clock_sync.synced.connect(func() -> void:
			_clock_synced = true
			_update_status()
		)

		if not multiplayer.is_server():
			_clock_synced = false
			_clock.enabled = false  # until the host tells us
			_clock.running = false
			_clock_sync.ask_host()
	_log("MORPHIC CHESS v0.1")
	_log("------------------")
	_log("No check rules. Capture the enemy king to win.")
	_log("!!!CLICK READY TO START!!!")
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

	_begin_intro()


# Centers the board/UI in the window and stretches the backdrop to fill it.
func _fit_to_viewport() -> void:
	var view := get_viewport_rect().size
	var offset := ((view - DESIGN_SIZE) / 2.0).max(Vector2.ZERO).floor()

	position = offset

	# The backdrop is a child of this node, so counter the shift and
	# cover the whole window.
	background_rect.position = -offset
	background_rect.size = view


# --------------------------------------------------
# MOVE GUIDE INTRO
# --------------------------------------------------

func _begin_intro() -> void:
	if skip_intro_once:
		skip_intro_once = false
		_game_started = true
		return

	_ensure_guide()

	var colors: Array[String] = ["white", "black"]
	if _online:
		colors = [local_color]

	_guide.open_intro(self, colors)


func _ensure_guide() -> void:
	if _guide != null and is_instance_valid(_guide):
		return

	# CanvasLayer so the overlay ignores this node's centering offset.
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	_guide = MOVE_GUIDE.instantiate()
	layer.add_child(_guide)
	_guide.player_ready.connect(_on_player_ready)


func _on_guide_pressed() -> void:
	play_button_audio()
	_ensure_guide()
	_guide.open(self)


func _on_player_ready(color: String) -> void:
	_ready_colors[color] = true

	if _online:
		_send_ready(false)

	_check_start()


func _check_start() -> void:
	if _game_started:
		return

	if _ready_colors["white"] and _ready_colors["black"]:
		_start_game()
		return

	if _guide == null:
		return

	if _online:
		if _ready_colors[local_color]:
			_guide.set_status("Waiting for your opponent to click READY...")
	else:
		var missing := "Black" if _ready_colors["white"] else "White"
		if _ready_colors["white"] or _ready_colors["black"]:
			_guide.set_status("Waiting for %s to click READY..." % missing)


func _start_game() -> void:
	if _game_started:
		return

	_game_started = true

	if _guide != null:
		_guide.close()

	_log("Both players ready. Game on!\n", GameLog.GOLD)
	_update_status()


func _send_ready(is_reply: bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_remote_ready.rpc(is_reply)


@rpc("any_peer", "call_remote", "reliable")
func _remote_ready(is_reply: bool) -> void:
	var other := "black" if local_color == "white" else "white"
	_ready_colors[other] = true

	# We already started but the opponent is still waiting on us (their
	# message to us arrived before our scene was ready): tell them again.
	if _game_started and not is_reply:
		_send_ready(true)

	_check_start()


# TIME
func _process(delta: float) -> void:
	# The clock doesn't run while players are reading the guide.
	if _game_started:
		_clock.tick(delta)
	_update_clock_labels()

	# Guest: keep asking until the host's board has loaded and answered.
	if _online and not _clock_synced:
		_sync_retry += delta
		if _sync_retry >= 0.5:
			_sync_retry = 0.0
			_clock_sync.ask_host()

	# Our READY click may arrive before the opponent's board exists, so
	# keep re-sending it until the game starts.
	if _online and not _game_started and _ready_colors[local_color]:
		_ready_resend += delta
		if _ready_resend >= 0.5:
			_ready_resend = 0.0
			_send_ready(false)


func _build_clock_ui() -> void:
	_clock_labels = {"white": white_clock, "black": black_clock}

	# Keep the bottom player's clock on the left when the board is flipped.
	if flipped:
		var left_pos := white_clock.position
		white_clock.position = black_clock.position
		black_clock.position = left_pos


func _update_clock_labels() -> void:
	for color in _clock_labels:
		var label: Label = _clock_labels[color]
		label.visible = _clock.enabled
		if not _clock.enabled:
			continue

		var t: float = _clock.remaining[color]
		var is_active: bool = _clock.running and _clock.active == color
		var tint := Color("9aa0a6")

		if is_active:
			tint = Color("ffd166")
		if t < 10.0 and (is_active or t <= 0.0):
			tint = Color("ff8a80")

		label.text = "%s %s" % [String(color).left(1).to_upper(), ChessClock.format(t)]
		label.add_theme_color_override("font_color", tint)


func _on_clock_expired(color: String) -> void:
	# Only the host (or an offline game) decides timeouts.
	if _online and not multiplayer.is_server():
		return

	if _online:
		_clock_sync.broadcast()
		_clock_sync.send_timeout(color)

	_end_on_time(color)


func _on_clock_timed_out(color: String) -> void:
	_clock.remaining[color] = 0.0
	_end_on_time(color)


func _end_on_time(color: String) -> void:
	if over or disconnected or time_expired:
		return

	time_expired = true
	_state.over = true
	awaiting_result = false
	pending_promo.clear()
	_promotion_ui.hide()
	_deselect()
	_clock.stop()

	_log(
		"\n%s ran out of time. Both players lose." % _config.name_of(color),
		GameLog.RED
	)
	_update_status()

# --------------------------------------------------
# INPUT / SELECTION
# --------------------------------------------------

func restart() -> void:
	play_button_audio()
	if _online:
		_leave_match()
		return

	skip_intro_once = true
	get_tree().reload_current_scene()


func _leave_match() -> void:
	NetworkManager.shutdown()
	get_tree().change_scene_to_file(SETUP_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if not _game_started:
		return

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

## Every .json in PRESET_DIR, sorted so both peers see the same order.
static func list_presets() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(PRESET_DIR)

	if dir == null:
		return out

	for file_name in dir.get_files():
		# Exported builds can list resources with a .remap suffix.
		var clean := file_name.trim_suffix(".remap")

		if clean.ends_with(".json") and not out.has(PRESET_DIR + clean):
			out.append(PRESET_DIR + clean)

	out.sort()
	return out
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
			_promotion_ui.show_options(options, turn == "white")
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
	if not _state.last_castle.is_empty():
		var castle_to: Vector2i = _state.last_castle["rook_to"]
		var castled_rook: AnimatedSprite2D = grid[castle_to]
		_view.slide(castled_rook, castle_to)
		_log("   castled with %s" % MoveRule.type_of(castled_rook), _turn_color())
	if promo != "":
		var previous_type := MoveRule.type_of(piece)
		PieceSpawner.set_sprite(piece, turn, promo)
		_log(
			"   %s promoted to %s" % [previous_type, promo],
			_turn_color()
		)

	_deselect()
	_state.end_turn()

	if over:
		_clock.stop()
	elif not (_online and not multiplayer.is_server()):
		_clock.switch_to(turn)
	else:
		_clock.switch_to(turn)

	if _online and multiplayer.is_server():
		_clock_sync.broadcast()

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
	_clock.stop()

	# Don't leave the player stuck behind the intro guide.
	if _guide != null and is_instance_valid(_guide):
		_guide.close()

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
	if time_expired:
		status.text = "Time out - both lose"
		return
	if over:
		status.text = "%s wins!" % _current_player_name()
		return
	if not _game_started:
		status.text = "Waiting for players to be ready..."
		return

	var status_text := "%s's turn (%s)" % [
		_current_player_name(),
		turn.capitalize()
	]

	if _online:
		if _clock.enabled:
			status_text = "%s (%s)" % ["Your move" if turn == local_color else "Waiting...", turn.capitalize()]
		else:
			status_text += "  -  YOUR MOVE" if turn == local_color else "  -  waiting..."

	status.text = status_text


# --------------------------------------------------
# PRESETS / SETTINGS
# --------------------------------------------------
func play_button_audio() -> void:
	if button_audio:
		button_audio.play()

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
	play_button_audio()
	Settings.open(self)
