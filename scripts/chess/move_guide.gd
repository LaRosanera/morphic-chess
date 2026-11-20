
extends Control
## Overlay that shows how every piece moves on a centered demo board.

signal player_ready(color: String)

const WHITE_PIECE_SCENE: PackedScene = preload("res://Scenes/Chess/classic_white_piece.tscn")
const BLACK_PIECE_SCENE: PackedScene = preload("res://Scenes/Chess/classic_black_piece.tscn")

const CELL := 64
const BOARD_SIZE := 7
const PIECE_FILL := 54.0
const FLIP_TYPES := ["camel", "minister", "man"]

const MOVE_COLOR := Color(0.1, 0.7, 0.2, 0.55)
const CAPTURE_COLOR := Color(0.9, 0.15, 0.15, 0.6)

@onready var tiles: TileMapLayer = %Tiles
@onready var highlights: Node2D = %Highlights
@onready var pieces: Node2D = %Pieces
@onready var piece_list: ItemList = %PieceList
@onready var obstacles_check: CheckButton = %ObstaclesCheck
@onready var first_move_check: CheckButton = %FirstMoveCheck
@onready var info: RichTextLabel = %Info
@onready var tabs: TabContainer = %Tabs
@onready var changes_text: RichTextLabel = %ChangesText
@onready var close_button: Button = %Close
@onready var button_audio: AudioStreamPlayer2D = %ButtonAudio

var chess_board: Node2D
var _rules: Dictionary = {}
var _types: Array[String] = []
var _white_frames: SpriteFrames
var _black_frames: SpriteFrames
var _board_size := BOARD_SIZE
var _center := Vector2i(BOARD_SIZE / 2, BOARD_SIZE / 2)

var _allowed_colors: Array[String] = []
var _ready_colors: Dictionary = {}
var _status_text := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_white_frames = _frames_from(WHITE_PIECE_SCENE)
	_black_frames = _frames_from(BLACK_PIECE_SCENE)
	_paint_board()

	piece_list.item_selected.connect(_on_piece_selected)

	obstacles_check.toggled.connect(func(_on: bool) -> void:
		_play_button_audio()
		_redraw()
	)

	first_move_check.toggled.connect(func(_on: bool) -> void:
		_play_button_audio()
		_redraw()
	)

	tabs.tab_changed.connect(func(_tab: int) -> void:
		_play_button_audio()
	)


# --------------------------------------------------
# OPEN / CLOSE
# --------------------------------------------------

func open(board: Node2D = null) -> void:
	chess_board = board
	_rules = board.rules if is_instance_valid(board) else {}

	_allowed_colors = ["white", "black"]
	_ready_colors.clear()

	_build_list()
	tabs.current_tab = 0
	visible = true
	close_button.grab_focus()


## Called by the main board coordinator.
## Offline: both players must click READY.
## Online: only the local player's READY button is shown.
func open_intro(board: Node2D = null, colors: Array = ["white", "black"]) -> void:
	chess_board = board
	_rules = board.rules if is_instance_valid(board) else {}

	_allowed_colors.clear()
	_ready_colors.clear()

	for color in colors:
		var normalized := str(color).to_lower()
		if normalized in ["white", "black"] and not _allowed_colors.has(normalized):
			_allowed_colors.append(normalized)
			_ready_colors[normalized] = false

	_build_list()
	tabs.current_tab = 0
	visible = true
	_update_ready_ui()
	close_button.grab_focus()


func close() -> void:
	print("trying to close")
	visible = false
	chess_board = null


func set_status(message: String) -> void:
	_status_text = message
	_update_ready_ui()


func _on_close_pressed() -> void:
	visible = false
	_play_button_audio()
	# Closing the guide is not the same as confirming readiness.


func _on_ready_pressed() -> void:
	_play_button_audio()

	for color in _allowed_colors:
		if not _ready_colors.get(color, false):
			_ready_colors[color] = true
			player_ready.emit(color)

	_update_ready_ui()


func _update_ready_ui() -> void:
	if not is_node_ready():
		return

	var ready_button := get_node_or_null("%Ready")
	if ready_button == null:
		return

	var button := ready_button as Button
	if button == null:
		return

	var all_ready := true
	for color in _allowed_colors:
		if not _ready_colors.get(color, false):
			all_ready = false

	button.disabled = all_ready
	button.text = "READY" if not all_ready else "READY!"

	if _status_text != "":
		info.text = _status_text


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _play_button_audio() -> void:
	if button_audio:
		button_audio.stop()
		button_audio.play()


# --------------------------------------------------
# PIECE LIST
# --------------------------------------------------

func _available_types() -> Dictionary:
	var available := {}
	if not is_instance_valid(chess_board):
		return available
	for color in chess_board.game_types:
		for piece_type in chess_board.game_types[color]:
			available[piece_type] = true
	for piece_type in chess_board.promo_pool:
		available[piece_type] = true
	return available


func _build_list() -> void:
	piece_list.clear()
	_types.clear()
	_update_changes_tab()

	var available_types := _available_types()

	for piece_type in _rules:
		if not available_types.is_empty() and not available_types.has(piece_type):
			continue
		_types.append(str(piece_type))
		var icon := _piece_texture(_white_frames, "white_%s" % piece_type)
		piece_list.add_item(str(piece_type).capitalize(), icon)

	if _types.is_empty():
		info.text = "No movement rules loaded."
		_clear_demo()
		return

	piece_list.select(0)
	_show_piece(0)


func _update_changes_tab() -> void:
	var lines: Array[String] = []
	for entry in RuleSetup.changes:
		lines.append("[color=gold]•[/color] %s" % entry)
	if lines.is_empty():
		lines.append("No changes this game.")
	changes_text.text = "\n".join(lines)


func _on_piece_selected(index: int) -> void:
	_play_button_audio()
	_show_piece(index)


func _show_piece(index: int) -> void:
	if index < 0 or index >= _types.size():
		return

	var rule = _rules[_types[index]]

	obstacles_check.set_pressed_no_signal(rule.jumps)

	var has_first_move: bool = rule.first_move_range > rule.max_range
	first_move_check.visible = has_first_move
	first_move_check.set_pressed_no_signal(false)

	_redraw()


# --------------------------------------------------
# DEMO BOARD
# --------------------------------------------------

func _paint_board() -> void:
	tiles.clear()
	for x in _board_size:
		for y in _board_size:
			tiles.set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 2, 0))


func _clear_demo() -> void:
	for child in highlights.get_children():
		child.queue_free()
	for child in pieces.get_children():
		child.queue_free()


func _redraw() -> void:
	_clear_demo()

	var index := piece_list.get_selected_items()
	if index.is_empty():
		return

	var piece_type := _types[index[0]]
	var rule = _rules[piece_type]
	_board_size = _get_movement_grid_size(rule)
	_center = Vector2i(_board_size / 2, _board_size / 2)
	_paint_board()
	_center_demo_board()

	var enemies := {}

	if obstacles_check.button_pressed:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx != 0 or dy != 0:
					enemies[_center + Vector2i(dx, dy)] = true

	for dir in rule.capture_only_directions:
		enemies[_center + dir] = true

	var result := _compute_moves(
		rule,
		enemies,
		first_move_check.button_pressed
	)

	for cell in result:
		_add_marker(
			cell,
			CAPTURE_COLOR if result[cell] == "capture" else MOVE_COLOR
		)

	for cell in enemies:
		if _in_bounds(cell):
			_add_piece(_black_frames, "black", "pawn", cell, false)

	_add_piece(
		_white_frames,
		"white",
		piece_type,
		_center,
		piece_type.to_lower() in FLIP_TYPES
	)

	_update_info(piece_type, rule)


func _get_movement_grid_size(rule: MoveRule) -> int:
	if (
		not rule.move_only_directions.is_empty()
		or not rule.capture_only_directions.is_empty()
	):
		return BOARD_SIZE

	var leap_directions: Array[Vector2i] = rule.leap_directions.duplicate()
	if rule.jumps and rule.max_range == 1:
		leap_directions.append_array(rule.directions)
	elif not rule.directions.is_empty():
		return BOARD_SIZE

	if leap_directions.is_empty():
		return BOARD_SIZE

	var max_offset := 0
	for direction in leap_directions:
		max_offset = maxi(
			max_offset,
			maxi(abs(direction.x), abs(direction.y))
		)

	return max_offset * 2 + 1


func _center_demo_board() -> void:
	var board := tiles.get_parent() as Node2D
	var holder := board.get_parent() as Control
	var displayed_size := Vector2(_board_size * CELL, _board_size * CELL) * board.scale
	board.position = (holder.size - displayed_size) / 2


func _compute_moves(rule, enemies: Dictionary, first_move: bool) -> Dictionary:
	var result := {}

	var reach: int = maxi(1, rule.max_range)
	if first_move:
		reach = maxi(reach, rule.first_move_range)

	var capture_dirs: Array[Vector2i] = []
	var move_dirs: Array[Vector2i] = []

	for d in rule.directions:
		capture_dirs.append(d)
		move_dirs.append(d)

	for d in rule.move_only_directions:
		move_dirs.append(d)

	for dir in move_dirs:
		var can_capture := dir in capture_dirs

		for step in range(1, reach + 1):
			var cell: Vector2i = _center + dir * step

			if not _in_bounds(cell):
				break

			if enemies.has(cell):
				if can_capture:
					result[cell] = "capture"

				if rule.jumps:
					continue

				break

			result[cell] = "move"

	for dir in rule.capture_only_directions:
		var cell: Vector2i = _center + dir

		if _in_bounds(cell) and enemies.has(cell):
			result[cell] = "capture"

	for dir in rule.leap_directions:
		var cell: Vector2i = _center + dir
		if _in_bounds(cell):
			result[cell] = "capture" if enemies.has(cell) else "move"

	return result


func _in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < _board_size
		and cell.y < _board_size
	)


func _add_marker(cell: Vector2i, color: Color) -> void:
	var marker := ColorRect.new()
	marker.color = color
	marker.size = Vector2(CELL, CELL)
	marker.position = Vector2(cell * CELL)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlights.add_child(marker)


func _add_piece(
	frames: SpriteFrames,
	prefix: String,
	piece_type: String,
	cell: Vector2i,
	flip: bool
) -> void:
	if frames == null:
		return

	var anim := "%s_%s" % [prefix, piece_type]

	if not frames.has_animation(anim):
		anim = "%s_pawn" % prefix

	if not frames.has_animation(anim):
		return

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = anim
	sprite.frame = 0
	sprite.stop()
	sprite.flip_v = flip
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.position = (Vector2(cell) + Vector2(0.5, 0.5)) * CELL

	var tex := frames.get_frame_texture(anim, 0)

	if tex != null:
		var biggest := maxf(tex.get_width(), tex.get_height())
		sprite.scale = Vector2.ONE * (PIECE_FILL / biggest)

	pieces.add_child(sprite)


# --------------------------------------------------
# INFO TEXT
# --------------------------------------------------

func _update_info(piece_type: String, rule) -> void:
	var lines: Array[String] = []

	lines.append("[color=MAGENTA]%s[/color]" % piece_type.capitalize())
	lines.append("")
	lines.append("[color=lime]■[/color] can move   [color=red]■[/color] can capture")
	lines.append("")
	lines.append("Maximum range: %d" % rule.max_range)
	lines.append("First move range: %d" % rule.first_move_range)
	lines.append("Can jump: %s" % ("yes" if rule.jumps else "no"))
	lines.append("Can promote: %s" % ("yes" if rule.promotes else "no"))

	if not rule.move_only_directions.is_empty():
		lines.append("")
		lines.append("Moves (but never captures) forward.")

	if not rule.capture_only_directions.is_empty():
		lines.append("Captures only on its diagonals/sides.")

	if rule.jumps:
		lines.append("")
		lines.append("Pieces in the way don't block it.")

	info.text = "\n".join(lines)


# --------------------------------------------------
# SPRITE HELPERS
# --------------------------------------------------

func _frames_from(scene: PackedScene) -> SpriteFrames:
	var probe: Node = scene.instantiate()
	var frames: SpriteFrames = null

	if probe is AnimatedSprite2D:
		frames = (probe as AnimatedSprite2D).sprite_frames

	probe.free()
	return frames


func _piece_texture(frames: SpriteFrames, anim: String) -> Texture2D:
	if frames == null or not frames.has_animation(anim):
		return null

	return frames.get_frame_texture(anim, 0)
