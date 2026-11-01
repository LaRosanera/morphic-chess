class_name MoveRule
extends Node
## One of these per piece type, as children of the "Rules" node in chess_board.tscn.
## Rules are written for WHITE (white moves "up" the screen = -y). Black is mirrored automatically.
## Change any value in the Inspector, or at runtime: $Rules/Knight.max_range = 3

const SIZE := 8

@export var piece_type := "pawn"
## Move OR capture along these steps (rook, bishop, queen, knight, king).
@export var directions: Array[Vector2i] = []
## Move only, never capture (pawn forward).
@export var move_only_directions: Array[Vector2i] = []
## Capture only, never plain move (pawn diagonals).
@export var capture_only_directions: Array[Vector2i] = []
## How many times a step repeats. 1 = single step / jump, 7 = slides across the board.
@export var max_range := 1
## Range for move_only_directions on the piece's first move (pawn double step). 0 = no bonus.
@export var first_move_range := 0
## true = may leap over other pieces (knight).
@export var jumps := false
## true = piece is replaced by a chosen piece on reaching the far rank.
@export var promotes := false


static func color_of(piece: AnimatedSprite2D) -> String:
	return String(piece.animation).get_slice("_", 0)

static func type_of(piece: AnimatedSprite2D) -> String:
	return String(piece.animation).get_slice("_", 1)


## board: Dictionary of Vector2i -> piece. Returns every cell the piece may move/capture to.
func get_targets(board: Dictionary, from: Vector2i, color: String, moved: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var flip := -1 if color == "black" else 1
	for d in directions:
		_walk(board, from, Vector2i(d.x, d.y * flip), max_range, true, true, color, out)
	var first := first_move_range if (not moved and first_move_range > 0) else max_range
	for d in move_only_directions:
		_walk(board, from, Vector2i(d.x, d.y * flip), first, true, false, color, out)
	for d in capture_only_directions:
		_walk(board, from, Vector2i(d.x, d.y * flip), max_range, false, true, color, out)
	return out


func _walk(board: Dictionary, from: Vector2i, step: Vector2i, steps: int,
		can_move: bool, can_capture: bool, color: String, out: Array[Vector2i]) -> void:
	var cell := from
	for i in steps:
		cell += step
		if cell.x < 0 or cell.y < 0 or cell.x >= SIZE or cell.y >= SIZE:
			return
		if board.has(cell):
			if can_capture and color_of(board[cell]) != color:
				out.append(cell)
			if not jumps:
				return
		elif can_move:
			out.append(cell)
