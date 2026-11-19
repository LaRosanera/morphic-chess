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

## Piece types allowed to castle with the king. Empty = castling disabled.
var castle_types := {}

## Piece types pawns may promote to this game. Empty = promotion disabled
## this game.
var promo_pool: Array[String] = []

## Set by move_piece(): {"rook_from", "rook_to"} if the last move was a castle.
var last_castle := {}

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


## Target cells for a piece (ordinary move/capture rules, plus castling).
func targets(p: AnimatedSprite2D, from: Vector2i) -> Array[Vector2i]:
	var rule: MoveRule = rules[MoveRule.type_of(p)]
	var has_moved: bool = p.get_meta("moved", false)
	var out := rule.get_targets(grid, from, MoveRule.color_of(p), has_moved)

	if MoveRule.type_of(p) == "king":
		for dir in [-1, 1]:
			var to := Vector2i(from.x + 2 * dir, from.y)
			if in_bounds(to) and not out.has(to) and not castle_for(from, to).is_empty():
				out.append(to)

	return out


## True if moving this piece to `to` triggers a promotion.
func promotes_on(p: AnimatedSprite2D, to: Vector2i) -> bool:
	var rule: MoveRule = rules[MoveRule.type_of(p)]
	var victim = grid.get(to)
	var captures_king: bool = (
		victim != null and MoveRule.type_of(victim) == "king"
	)
	var far_rank := 0 if MoveRule.color_of(p) == "white" else MoveRule.SIZE - 1

	return rule.promotes and to.y == far_rank and not captures_king


func promo_options(_color: String) -> Array[String]:
	var options: Array[String] = []

	for piece_type in PROMO_ORDER:
		if promo_pool.has(piece_type) and rules.has(piece_type):
			options.append(piece_type)
	for piece_type in promo_pool:
		if rules.has(piece_type) and not options.has(piece_type):
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



func move_piece(from: Vector2i, to: Vector2i) -> String:
	var castle := castle_for(from, to)  # must be read before the grid changes
	var p: AnimatedSprite2D = grid[from]
	var victim = grid.get(to)
	var victim_type := ""

	last_castle = {}
	grid.erase(from)

	if victim != null:
		victim_type = MoveRule.type_of(victim)
		victim.queue_free()
		over = victim_type == "king"

	grid[to] = p
	p.set_meta("moved", true)

	if not castle.is_empty():
		var r = grid[castle["rook_from"]]
		grid.erase(castle["rook_from"])
		grid[castle["rook_to"]] = r
		r.set_meta("moved", true)
		last_castle = castle

	return victim_type
## If moving the king from -> to is a castle, returns
## {"rook_from": cell, "rook_to": cell}. Otherwise returns {}.
## The king steps two cells toward the nearest piece on its rank. That piece
## must be a friendly, unmoved castler at least 3 cells away, and the king
## must be unmoved too. No check rules, so attacked cells don't matter.
func castle_for(from: Vector2i, to: Vector2i) -> Dictionary:
	var king = grid.get(from)

	if king == null or castle_types.is_empty():
		return {}
	if MoveRule.type_of(king) != "king" or king.get_meta("moved", false):
		return {}
	if to.y != from.y or absi(to.x - from.x) != 2:
		return {}

	var dir := signi(to.x - from.x)
	var color := MoveRule.color_of(king)
	var x := from.x + dir

	while x >= 0 and x < MoveRule.SIZE:
		var cell := Vector2i(x, from.y)
		var other = grid.get(cell)

		if other != null:
			var ok: bool = (
				absi(x - from.x) >= 3
				and MoveRule.color_of(other) == color
				and castle_types.has(MoveRule.type_of(other))
				and not other.get_meta("moved", false)
			)
			if ok:
				return {"rook_from": cell, "rook_to": Vector2i(from.x + dir, from.y)}
			return {}

		x += dir

	return {}

func end_turn() -> void:
	if not over:
		turn = "black" if turn == "white" else "white"
