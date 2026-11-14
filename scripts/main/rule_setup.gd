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
) -> Dictionary:
	# FEATURE 1: Randomize a standard sliding piece's range.
	var sliding_pieces := ["rook", "bishop", "queen", "king", "elephant"]
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
		# FEATURE 4: a random piece can also step one square any direction.
	var stepper_pool := ["knight", "bishop", "rook"]
	var stepper: String = stepper_pool[rng.randi_range(0, stepper_pool.size() - 1)]
	var step_roll := rng.randf()

	if step_roll < 0.5 and rules.has(stepper):
		var step_rule: MoveRule = rules[stepper]
		step_rule.leap_directions.append_array(ORTHO)
		step_rule.leap_directions.append_array(DIAG)
		game_log.write(
			"%s can also step one square any direction" % stepper.capitalize(),
			GameLog.GOLD
		)

	# FEATURE 5: pawns can capture sideways.
	var side_roll := rng.randf()

	if side_roll < 0.4 and rules.has("pawn"):
		var side_rule: MoveRule = rules["pawn"]
		side_rule.capture_only_directions.append(Vector2i(1, 0))
		side_rule.capture_only_directions.append(Vector2i(-1, 0))
		game_log.write("Pawns can capture sideways", GameLog.GOLD)

	# FEATURE 6: castling. 15% off, 50% rook + empress, 35% those plus one
	# random extra piece type.
	var extra_pool := [
		"bishop", "knight", "queen", "amazon", "princess",
		"camel", "elephant", "minister", "man"
	]
	var extra: String = extra_pool[rng.randi_range(0, extra_pool.size() - 1)]
	var castle_roll := rng.randi_range(0, 99)
	var castle_types := {}

	if castle_roll < 15:
		game_log.write("Castling is disabled", GameLog.GOLD)
	else:
		for t in ["rook", "empress"]:
			if rules.has(t):
				castle_types[t] = true

		if castle_roll >= 65 and rules.has(extra):
			castle_types[extra] = true

		var names: Array[String] = []
		for t in castle_types:
			names.append(String(t).capitalize())

		game_log.write("Castling: king + %s" % " / ".join(names), GameLog.GOLD)

	return castle_types
