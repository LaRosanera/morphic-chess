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

@onready var tiles: TileMapLayer = $TileMapLayer
@onready var pieces: Node2D = $Pieces
@onready var highlights: Node2D = $Highlights
@onready var status: Label = $UI/Status
@onready var picker: Control = $UI/PromotionPicker
@onready var log_box: RichTextLabel = $UI/Terminal/Log

const LETTERS := {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook", "q": "queen", "k": "king"}

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


func _ready() -> void:
	for y in MoveRule.SIZE:
		for x in MoveRule.SIZE:
			tiles.set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 2, 0))
	for r: MoveRule in $Rules.get_children():
		rules[r.piece_type] = r
	_spawn_pieces()
	for b: Button in picker.get_children():
		b.pressed.connect(_promote.bind(String(b.name).to_lower()))
	_log("MORPHIC CHESS v0.1")
	_log("------------------")
	_log("No check rules. Capture the enemy king to win.")
	_log("White to move.\n")
	_update_status()
	_update_status()
	if _pending_name != "":
		_log("Preset: %s\n" % _pending_name, "#ffd166")


func _spawn_pieces() -> void:
	if preset_path != "" and _spawn_from_file(preset_path):
		return
	for x in MoveRule.SIZE:
		_spawn("black", back_rank[x], Vector2i(x, 0))
		_spawn("black", "pawn", Vector2i(x, 1))
		_spawn("white", "pawn", Vector2i(x, 6))
		_spawn("white", back_rank[x], Vector2i(x, 7))


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


func _log_move(p: AnimatedSprite2D, from: Vector2i, to: Vector2i, victim_type: String) -> void:
	move_count += 1
	var line := "%d. %s %s %s -> %s" % [move_count, turn.capitalize(), MoveRule.type_of(p), _sq(from), _sq(to)]
	if victim_type != "":
		line += " x%s" % victim_type
	_log(line, _turn_color())
	if over:
		_log("\n%s wins! King captured." % turn.capitalize(), "#ffd166")
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
	
func _update_status() -> void:
	status.text = ("%s wins!" if over else "%s to move") % turn.capitalize()
