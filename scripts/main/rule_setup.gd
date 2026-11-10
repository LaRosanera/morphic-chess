class_name RuleSetup
extends RefCounted
## Builds the rule set at game start:
##   1. register_custom()  adds MoveRule nodes for custom pieces
##   2. collect()          gathers all MoveRule nodes by piece type
##   3. apply_seeded()     applies the seed-driven random changes
##
## All randomness happens in apply_seeded(), once, before any move. Every
## peer runs it in the same order with the same seed, so rules stay in sync.

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


static func register_custom(rules_node: Node) -> void:
	var existing := {}

	for child in rules_node.get_children():
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

		rules_node.add_child(rule)


## Returns {piece type -> MoveRule}.
static func collect(rules_node: Node) -> Dictionary:
	var rules := {}

	for child in rules_node.get_children():
		if child is MoveRule:
			var rule := child as MoveRule
			rules[rule.piece_type] = rule

	return rules


static func apply_seeded(
	rules: Dictionary,
	rng: RandomNumberGenerator,
	game_log: GameLog
) -> void:
	# FEATURE 1: Randomize a standard sliding piece's range.
	var sliding_pieces := ["rook", "bishop", "queen"]
	var chosen_piece: String = sliding_pieces[
		rng.randi_range(0, sliding_pieces.size() - 1)
	]

	if rules.has(chosen_piece):
		var rule: MoveRule = rules[chosen_piece]
		rule.max_range = rng.randi_range(2, 7)

		game_log.write(
			"%s range: %d" % [chosen_piece.capitalize(), rule.max_range],
			GameLog.GOLD
		)

	# FEATURE 2: Randomize the pawn's first move distance.
	if rules.has("pawn"):
		var pawn_rule: MoveRule = rules["pawn"]
		pawn_rule.first_move_range = rng.randi_range(2, 3)

		game_log.write(
			"Pawn first move range: %d" % pawn_rule.first_move_range,
			GameLog.GOLD
		)

	# FEATURE 3: Give a standard sliding piece the ability to jump.
	var jump_pieces := ["rook", "bishop"]
	var jump_piece: String = jump_pieces[
		rng.randi_range(0, jump_pieces.size() - 1)
	]

	if rules.has(jump_piece):
		var jump_rule: MoveRule = rules[jump_piece]
		jump_rule.jumps = true

		game_log.write(
			"%s can jump over pieces!" % jump_piece.capitalize(),
			GameLog.GOLD
		)
