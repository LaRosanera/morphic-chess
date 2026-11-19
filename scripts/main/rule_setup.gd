class_name RuleSetup
extends RefCounted
## Builds the rule set at game start:
##   1. register_custom()  adds MoveRule nodes for custom pieces
##   2. collect()          gathers all MoveRule nodes by piece type
##   3. apply_seeded()     applies the seed-driven random changes
##
## All randomness happens in apply_seeded(), once, before any move. Every
## peer runs it in the same order with the same seed, so rules stay in sync.

static var changes: Array[String] = []


static func _say(game_log: GameLog, text: String) -> void:
	changes.append(text)
	game_log.write(text, GameLog.GOLD)


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

const ZEBRA: Array[Vector2i] = [
	Vector2i(2, 3),
	Vector2i(3, 2),
	Vector2i(-2, 3),
	Vector2i(-3, 2),
	Vector2i(2, -3),
	Vector2i(3, -2),
	Vector2i(-2, -3),
	Vector2i(-3, -2),
]

const DABBABA: Array[Vector2i] = [
	Vector2i(2, 0),
	Vector2i(-2, 0),
	Vector2i(0, 2),
	Vector2i(0, -2),
]

const MUTATIONS: Array[String] = [
	"range",
	"pawn_first",
	"jump",
	"stepper",
	"side_capture",
	"borrow",
	"extra_leap",
	"leap_range",
]


static func _add_unique(
	target: Array[Vector2i],
	offsets: Array[Vector2i]
) -> void:
	for offset in offsets:
		if not target.has(offset):
			target.append(offset)


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
			rule.snapshot()
			rules[rule.piece_type] = rule

	return rules


static func _sub_rng(base_seed: int, tag: String) -> RandomNumberGenerator:
	var sub_rng := RandomNumberGenerator.new()
	sub_rng.seed = hash("%d:%s" % [base_seed, tag])
	return sub_rng


## Picks from `pool`, keeping only types in `allowed`. Returns "" if none.
static func _pick(
	pool: Array,
	allowed: Dictionary,
	r: RandomNumberGenerator
) -> String:
	var valid: Array = []
	for t in pool:
		if allowed.has(t):
			valid.append(t)
	if valid.is_empty():
		return ""
	return valid[r.randi_range(0, valid.size() - 1)]


## Picks a random subset of all piece types that pawns may promote to.
static func pick_promo_pool(rules: Dictionary, base_seed: int) -> Array[String]:
	var r := _sub_rng(base_seed, "promo_pool")

	# Sorted so the order never depends on dictionary insertion order.
	var candidates: Array[String] = []
	for key in rules:
		var t := String(key)
		if t != "pawn" and t != "king":
			candidates.append(t)
	candidates.sort()

	# Seeded Fisher-Yates (never Array.shuffle()).
	for i in range(candidates.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var count := mini(r.randi_range(2, 6), candidates.size())
	var pool: Array[String] = []
	for k in range(count):
		pool.append(candidates[k])
	return pool


static func apply_seeded(
	rules: Dictionary,
	rng: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> Dictionary:
	for rule in rules.values():
		(rule as MoveRule).restore()

	changes.clear()

	var base_seed := rng.seed
	var select := _sub_rng(base_seed, "select")
	var order: Array[String] = MUTATIONS.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := select.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp

	var count := mini(select.randi_range(3, 6), order.size())
	for k in range(count):
		var tag := order[k]
		_run_mutation(tag, rules, _sub_rng(base_seed, tag), game_log, allowed)

	return _apply_castling(rules, _sub_rng(base_seed, "castling"), game_log)


static func _run_mutation(
	tag: String,
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> void:
	match tag:
		"range":
			_mut_range(rules, r, game_log, allowed)
		"pawn_first":
			_mut_pawn_first(rules, r, game_log, allowed)
		"jump":
			_mut_jump(rules, r, game_log, allowed)
		"stepper":
			_mut_stepper(rules, r, game_log, allowed)
		"side_capture":
			_mut_side_capture(rules, r, game_log, allowed)
		"borrow":
			_mut_borrow(rules, r, game_log, allowed)
		"extra_leap":
			_mut_extra_leap(rules, r, game_log, allowed)
		"leap_range":
			_mut_leap_range(rules, r, game_log, allowed)


static func _mut_range(
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> void:
	var piece := _pick(["rook", "bishop", "queen", "king"], allowed, r)
	if piece == "" or not rules.has(piece):
		return
	var value := r.randi_range(2, 3) if piece == "king" else r.randi_range(2, 7)
	(rules[piece] as MoveRule).max_range = value
	_say(game_log, "%s range: %d" % [piece.capitalize(), value])


static func _mut_pawn_first(
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> void:
	if not allowed.has("pawn"):
		return
	var value := r.randi_range(2, 3)
	if rules.has("pawn"):
		(rules["pawn"] as MoveRule).first_move_range = value
		_say(game_log, "Pawn first move range: %d" % value)


static func _mut_jump(
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> void:
	var piece := _pick(["rook", "bishop"], allowed, r)
	if piece == "" or not rules.has(piece):
		return
	(rules[piece] as MoveRule).jumps = true
	_say(game_log, "%s can jump over pieces!" % piece.capitalize())


static func _mut_stepper(
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> void:
	var piece := _pick(["knight", "bishop", "rook"], allowed, r)
	if piece == "" or not rules.has(piece):
		return

	var rule: MoveRule = rules[piece]
	match piece:
		"rook":
			_add_unique(rule.leap_directions, DIAG)
		"bishop":
			_add_unique(rule.leap_directions, ORTHO)
		_:
			_add_unique(rule.leap_directions, ORTHO)
			_add_unique(rule.leap_directions, DIAG)
	_say(game_log, "%s can also step one square" % piece.capitalize())


static func _mut_side_capture(
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> void:
	if not allowed.has("pawn"):
		return
	r.randf()
	if rules.has("pawn"):
		var rule: MoveRule = rules["pawn"]
		_add_unique(
			rule.capture_only_directions,
			[Vector2i(1, 0), Vector2i(-1, 0)]
		)
		_say(game_log, "Pawns can capture sideways")


static func _mut_borrow(
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> void:
	var piece := _pick(["bishop", "rook", "queen", "king"], allowed, r)
	if piece == "" or not rules.has(piece):
		return
	var move_name: String
	var offsets: Array[Vector2i]
	match r.randi_range(0, 2):
		0:
			move_name = "Knight"
			offsets = KNIGHT
		1:
			move_name = "Camel"
			offsets = CAMEL
		_:
			move_name = "Zebra"
			offsets = ZEBRA

	_add_unique((rules[piece] as MoveRule).leap_directions, offsets)
	_say(game_log, "%s also moves like a %s" % [piece.capitalize(), move_name])


static func _mut_extra_leap(
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> void:
	var piece := _pick(["pawn", "knight", "man", "minister"], allowed, r)
	if piece == "" or not rules.has(piece):
		return
	var move_name: String
	var offsets: Array[Vector2i]
	if r.randi_range(0, 1) == 0:
		move_name = "Alfil"
		offsets = ALFIL
	else:
		move_name = "Dabbaba"
		offsets = DABBABA

	_add_unique((rules[piece] as MoveRule).leap_directions, offsets)
	_say(game_log, "%s also leaps like an %s" % [piece.capitalize(), move_name])


static func _mut_leap_range(
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog,
	allowed: Dictionary
) -> void:
	var piece := _pick(["elephant", "camel", "princess", "empress"], allowed, r)
	if piece == "" or not rules.has(piece):
		return
	var value := r.randi_range(2, 4)
	(rules[piece] as MoveRule).leap_range = value
	_say(game_log, "%s leap range: %d" % [piece.capitalize(), value])


static func _apply_castling(
	rules: Dictionary,
	r: RandomNumberGenerator,
	game_log: GameLog
) -> Dictionary:
	var extra_pool := [
		"bishop", "knight", "queen", "amazon", "princess",
		"camel", "elephant", "minister", "man"
	]
	var extra: String = extra_pool[r.randi_range(0, extra_pool.size() - 1)]
	var castle_roll := r.randi_range(0, 99)
	var castle_types := {}

	if castle_roll < 15:
		_say(game_log, "Castling is disabled")
		return castle_types

	for piece in ["rook", "empress"]:
		if rules.has(piece):
			castle_types[piece] = true
	if castle_roll >= 65 and rules.has(extra):
		castle_types[extra] = true

	var names: Array[String] = []
	for piece in castle_types:
		names.append(String(piece).capitalize())
	_say(game_log, "Castling: king + %s" % " / ".join(names))
	return castle_types
