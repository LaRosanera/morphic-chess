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

var grid := {}            # Vector2i -> piece node
var rules := {}           # piece type -> MoveRule node
var moves := {}           # legal target cells of the selected piece
var turn := "white"
var selected: AnimatedSprite2D
var promoting: AnimatedSprite2D
var over := false


func _ready() -> void:
	for y in MoveRule.SIZE:
		for x in MoveRule.SIZE:
			tiles.set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 2, 0))
	for r: MoveRule in $Rules.get_children():
		rules[r.piece_type] = r
	_spawn_pieces()
	for b: Button in picker.get_children():
		b.pressed.connect(_promote.bind(String(b.name).to_lower()))
	_update_status()


func _spawn_pieces() -> void:
	for x in MoveRule.SIZE:
		_spawn("black", back_rank[x], Vector2i(x, 0))
		_spawn("black", "pawn", Vector2i(x, 1))
		_spawn("white", "pawn", Vector2i(x, 6))
		_spawn("white", back_rank[x], Vector2i(x, 7))


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
	var victim = grid.get(to)
	grid.erase(grid.find_key(p))
	if victim:
		victim.queue_free()
		over = MoveRule.type_of(victim) == "king"
	grid[to] = p
	p.set_meta("moved", true)
	create_tween().tween_property(p, "position", tiles.map_to_local(to), 0.15)
	_deselect()

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
	_end_turn()


func _end_turn() -> void:
	if not over:
		turn = "black" if turn == "white" else "white"
	_update_status()


func _update_status() -> void:
	status.text = ("%s wins!" if over else "%s to move") % turn.capitalize()
