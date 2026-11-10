class_name GameState
extends RefCounted
## Everything that defines the current position, plus the rules questions
## asked about it ("where can this piece go?", "is this move legal?").
## No drawing and no networking in here.

## Promotion display order. Other custom types are appended afterward.
const PROMO_ORDER := [
	"queen", "amazon", "empress", "princess",
	"rook", "bishop", "knight", "camel",
	"elephant", "minister", "man"
]

var grid := {}  # Vector2i -> piece node
var rules := {}  # piece type -> MoveRule node

## Piece types spawned in this game, recorded separately per color.
## Capturing a piece does not remove its type from promotion options.
var game_types := {
	"white": {},
	"black": {},
}

var turn := "white"
var over := false
var move_count := 0


func in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= 0 and cell.y >= 0
		and cell.x < MoveRule.SIZE and cell.y < MoveRule.SIZE
	)


## Target cells for a piece (ordinary move/capture rules only).
func targets(p: AnimatedSprite2D, from: Vector2i) -> Array[Vector2i]:
	var rule: MoveRule = rules[MoveRule.type_of(p)]
	var has_moved: bool = p.get_meta("moved", false)

	return rule.get_targets(grid, from, MoveRule.color_of(p), has_moved)


## True if moving this piece to `to` triggers a promotion.
func promotes_on(p: AnimatedSprite2D, to: Vector2i) -> bool:
	var rule: MoveRule = rules[MoveRule.type_of(p)]
	var victim = grid.get(to)
	var captures_king: bool = (
		victim != null and MoveRule.type_of(victim) == "king"
	)
	var far_rank := 0 if MoveRule.color_of(p) == "white" else MoveRule.SIZE - 1

	return rule.promotes and to.y == far_rank and not captures_king


func promo_options(color: String) -> Array[String]:
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


## Host-side validation. Returns {"ok": bool, "promo": String}.
## The returned promo is authoritative; a client's choice is only a request.
func check_move(
	color: String,
	from: Vector2i,
	to: Vector2i,
	promo: String
) -> Dictionary:
	var fail := {"ok": false, "promo": ""}

	if over or color != turn:
		return fail

	if not in_bounds(from) or not in_bounds(to):
		return fail

	var p = grid.get(from)

	if p == null or MoveRule.color_of(p) != color:
		return fail

	if not rules.has(MoveRule.type_of(p)):
		return fail

	if not targets(p, from).has(to):
		return fail

	var final_promo := ""

	if promotes_on(p, to):
		var options := promo_options(color)

		if options.size() == 1:
			final_promo = options[0]
		elif options.size() > 1:
			if not options.has(promo):
				return fail

			final_promo = promo

	return {"ok": true, "promo": final_promo}


## Moves a piece in the grid, removes any captured piece, and returns the
## captured type ("" if none). Capturing a king ends the game.
func move_piece(from: Vector2i, to: Vector2i) -> String:
	var p: AnimatedSprite2D = grid[from]
	var victim = grid.get(to)
	var victim_type := ""

	grid.erase(from)

	if victim != null:
		victim_type = MoveRule.type_of(victim)
		victim.queue_free()
		over = victim_type == "king"

	grid[to] = p
	p.set_meta("moved", true)

	return victim_type


func end_turn() -> void:
	if not over:
		turn = "black" if turn == "white" else "white"
