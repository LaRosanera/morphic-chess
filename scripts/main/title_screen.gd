
extends Control

const SETUP_SCENE := "res://scenes/main/game_setup.tscn"
const WHITE_PIECE_SCENE := "res://Scenes/Chess/classic_white_piece.tscn"
const BLACK_PIECE_SCENE := "res://Scenes/Chess/classic_black_piece.tscn"
const SETTINGS_SCENE = preload("res://Scenes/Main/settings.tscn")
const DAILY_SEED_PATH := "user://daily_seed.json"

const COPIES_PER_PIECE := 3
const COLUMNS := 9
const EXPECTED_ANIMATIONS := 13

@export var motion_speed: float = 0.65

@onready var piece_layer: Node2D = $PieceLayer
@onready var play_button: Button = $MenuCanvas/Panel/Margin/Content/PlayButton
@onready var motion_button: CheckButton = $MenuCanvas/Panel/Margin/Content/MotionButton
@onready var quit_button: Button = $MenuCanvas/Panel/Margin/Content/QuitButton
@onready var status_label: Label = get_node_or_null("MenuCanvas/Panel/Margin/Content/StatusLabel")
@onready var panel: PanelContainer = $MenuCanvas/Panel
@onready var seed_label: Label = $MenuCanvas/Panel/Margin/Content/SeedLabel
@onready var button_audio: AudioStreamPlayer2D = $ButtonAudio

var elapsed := 0.0
var reduced_motion := false
var transitioning := false

var rng := RandomNumberGenerator.new()
var daily_seed: int

var pieces: Array[Node2D] = []
var origins: Array[Vector2] = []
var phases: Array[float] = []
var scales: Array[float] = []


func _ready() -> void:
	_generate_daily_seed()

	reduced_motion = get_tree().get_meta("reduced_motion", false)
	motion_button.button_pressed = reduced_motion

	_apply_styles()

	play_button.pressed.connect(_open_setup)
	motion_button.toggled.connect(_set_reduced_motion)
	quit_button.pressed.connect(_quit_game)

	play_button.grab_focus()

	_create_pieces()


func _generate_daily_seed() -> void:
	var date := Time.get_date_dict_from_system()

	daily_seed = int("%02d%02d%04d" % [
		date["month"],
		date["day"],
		date["year"]
	])

	rng.seed = daily_seed

	var seed_file := FileAccess.open(DAILY_SEED_PATH, FileAccess.WRITE)

	if seed_file:
		seed_file.store_string(JSON.stringify({
			"daily_seed": daily_seed
		}))
		seed_file.close()
	else:
		push_warning("Could not save daily seed: " + DAILY_SEED_PATH)

	get_tree().set_meta("daily_seed", daily_seed)

	seed_label.text = "DAILY SEED: %08d" % daily_seed


func _apply_styles() -> void:
	var panel_style := StyleBoxFlat.new()

	panel_style.bg_color = Color("#100D16")
	panel_style.border_color = Color("#514052")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(0)

	panel.add_theme_stylebox_override("panel", panel_style)


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
	else:
		push_warning(message)


# Find an AnimatedSprite2D even if nested inside another node.
func _find_animated_sprite(node: Node) -> AnimatedSprite2D:
	if node is AnimatedSprite2D:
		return node as AnimatedSprite2D

	for child in node.get_children():
		var found := _find_animated_sprite(child)

		if found != null:
			return found

	return null


# Create three copies of every animation for both piece sets.
func _create_pieces() -> void:
	var packed_scenes: Array[PackedScene] = []

	# Load both piece scenes.
	for path in [WHITE_PIECE_SCENE, BLACK_PIECE_SCENE]:
		if not ResourceLoader.exists(path):
			_set_status("ARTWORK ERROR / MISSING SCENE: " + path)
			return

		var packed := load(path) as PackedScene

		if packed == null:
			_set_status("ARTWORK ERROR / COULD NOT LOAD PIECE SCENE")
			return

		packed_scenes.append(packed)

	# Collect animation names from both scenes.
	var specs: Array[Dictionary] = []

	for scene_index in range(packed_scenes.size()):
		var probe := packed_scenes[scene_index].instantiate()
		var animated_sprite := _find_animated_sprite(probe)

		if animated_sprite == null:
			probe.free()
			_set_status("ARTWORK ERROR / ANIMATED SPRITE NOT FOUND")
			return

		if animated_sprite.sprite_frames == null:
			probe.free()
			_set_status("ARTWORK ERROR / SPRITE FRAMES NOT FOUND")
			return

		var names := animated_sprite.sprite_frames.get_animation_names()

		if names.size() != EXPECTED_ANIMATIONS:
			probe.free()
			_set_status("ARTWORK ERROR / UNEXPECTED ANIMATION COUNT")
			print("Scene %d has %d animations: %s" % [
				scene_index,
				names.size(),
				names
			])
			return

		for anim_name in names:
			for copy in range(COPIES_PER_PIECE):
				specs.append({
					"scene": scene_index,
					"anim": anim_name
				})

		probe.free()

	var total := specs.size()
	var rows := int(ceil(float(total) / float(COLUMNS)))

	# Randomize grid cell assignments.
	var cells: Array[int] = []

	for i in range(total):
		cells.append(i)

	for i in range(total - 1, 0, -1):
		var other := rng.randi_range(0, i)

		var temp := cells[i]
		cells[i] = cells[other]
		cells[other] = temp

	# Spawn all pieces.
	for i in range(total):
		var spec: Dictionary = specs[i]

		var piece := packed_scenes[spec["scene"]].instantiate() as Node2D

		if piece == null:
			_set_status("ARTWORK ERROR / PIECE ROOT MUST BE NODE2D")
			return

		var sprite := _find_animated_sprite(piece)

		if sprite == null:
			piece.free()
			_set_status("ARTWORK ERROR / SPRITE NOT FOUND")
			return

		sprite.animation = spec["anim"]
		sprite.stop()

		# Subtle monochromatic purple tint.
		piece.modulate = Color(
			rng.randf_range(0.72, 0.88),
			rng.randf_range(0.62, 0.76),
			rng.randf_range(0.78, 0.92),
			rng.randf_range(0.22, 0.42)
		)

		piece_layer.add_child(piece)
		pieces.append(piece)

		# Assign randomized grid positions.
		var cell := cells[i]
		var row := floori(float(cell) / float(COLUMNS))

		origins.append(Vector2(
			(float(cell % COLUMNS) + rng.randf_range(0.15, 0.85))
				/ float(COLUMNS),

			(float(row) + rng.randf_range(0.15, 0.85))
				/ float(rows)
		))

		phases.append(rng.randf_range(0.0, TAU))
		scales.append(rng.randf_range(0.85, 1.65))

	_update_pieces()


func _process(delta: float) -> void:
	if not reduced_motion:
		elapsed += delta * motion_speed

	_update_pieces()


# Update positions and floating animations.
func _update_pieces() -> void:
	var view_size := size

	for i in range(pieces.size()):
		var phase := phases[i]

		var drift := Vector2.ZERO
		var angle := 0.0

		if not reduced_motion:
			drift = Vector2(
				sin(elapsed * 0.32 + phase) * 28.0,
				cos(elapsed * 0.26 + phase) * 24.0
			)

			angle = sin(elapsed * 0.18 + phase) * 0.16

		# Convert Control coordinates into PieceLayer coordinates.
		var control_position := origins[i] * view_size + drift
		var global_position := get_global_transform() * control_position

		pieces[i].position = piece_layer.to_local(global_position)
		pieces[i].rotation = angle
		pieces[i].scale = Vector2.ONE * scales[i]


func _set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	get_tree().set_meta("reduced_motion", enabled)


func _play_click() -> void:
	if button_audio.stream != null:
		button_audio.play()


# Play the click, fade the screen, then execute the action.
func _transition_then(action: Callable) -> void:
	if transitioning:
		return

	transitioning = true

	play_button.disabled = true
	quit_button.disabled = true
	motion_button.disabled = true

	_play_click()

	Transition.fade()
	await Transition.on_transition_finished

	action.call()


func _open_setup() -> void:
	_transition_then(_change_to_setup)


func _change_to_setup() -> void:
	var error := get_tree().change_scene_to_file(SETUP_SCENE)

	if error != OK:
		transitioning = false

		play_button.disabled = false
		quit_button.disabled = false
		motion_button.disabled = false

		_set_status("Could not open game setup. Check the scene path.")


func _quit_game() -> void:
	_transition_then(get_tree().quit)


func _on_settings_pressed() -> void:
	var settings = SETTINGS_SCENE.instantiate()
	get_tree().root.add_child(settings)
	Settings.open()
