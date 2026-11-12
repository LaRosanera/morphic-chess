
extends Control

const SETUP_SCENE := "res://scenes/main/game_setup.tscn"
const WHITE_PIECE_SCENE := "res://Scenes/Chess/classic_white_piece.tscn"
const BLACK_PIECE_SCENE := "res://Scenes/Chess/classic_black_piece.tscn"

const COPIES_PER_PIECE := 3
const COLUMNS := 9
const EXPECTED_ANIMATIONS := 13

@export var motion_speed: float = 0.65

@onready var piece_layer: Node2D = $PieceLayer
@onready var play_button: Button = $MenuCanvas/Panel/Margin/Content/PlayButton
@onready var motion_button: CheckButton = $MenuCanvas/Panel/Margin/Content/MotionButton
@onready var quit_button: Button = $MenuCanvas/Panel/Margin/Content/QuitButton
@onready var status_label: Label = $MenuCanvas/Panel/Margin/Content/StatusLabel
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
	# Generate today's seed using MMDDYYYY.
	var date := Time.get_date_dict_from_system()

	daily_seed = int("%02d%02d%04d" % [
		date["month"],
		date["day"],
		date["year"]
	])

	# Use the date as the random number generator seed.
	rng.seed = daily_seed

	# Make the seed accessible to other scenes.
	get_tree().set_meta("daily_seed", daily_seed)

	seed_label.text = " DAILY SEED: %08d" % daily_seed

	_apply_styles()

	reduced_motion = get_tree().get_meta("reduced_motion", false)
	motion_button.button_pressed = reduced_motion

	play_button.pressed.connect(_open_setup)
	motion_button.toggled.connect(_set_reduced_motion)
	quit_button.pressed.connect(_quit_game)

	

	play_button.grab_focus()
	
	_create_pieces()


func _apply_styles() -> void:
	panel.add_theme_stylebox_override(
		"panel",
		_style(Color("#111923"), Color("#405568"))
	)

	_style_button(play_button, true)
	_style_button(quit_button, false)


func _style_button(button: Button, primary: bool) -> void:
	var fill := Color("#203c30") if primary else Color("#192330")
	var border := Color("#7efc7e") if primary else Color("#45596d")

	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 16)

	button.add_theme_color_override("font_color", Color("#e8f0f7"))
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("#7efc7e"))

	button.add_theme_stylebox_override(
		"normal", _style(fill, border)
	)
	button.add_theme_stylebox_override(
		"hover", _style(fill.lightened(0.12), Color("#7efc7e"))
	)
	button.add_theme_stylebox_override(
		"pressed", _style(fill.darkened(0.2), Color("#7efc7e"))
	)
	button.add_theme_stylebox_override(
		"focus", _style(Color(0, 0, 0, 0), Color("#eef8ff"))
	)


func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


# Find an AnimatedSprite2D even if it is nested inside another node.
func _find_animated_sprite(node: Node) -> AnimatedSprite2D:
	if node is AnimatedSprite2D:
		return node as AnimatedSprite2D

	for child in node.get_children():
		var found := _find_animated_sprite(child)
		if found != null:
			return found

	return null


# Create 3 copies of every animation for both piece sets.
func _create_pieces() -> void:
	
	var packed_scenes: Array[PackedScene] = []
	
	# Load both piece scenes.
	for path in [WHITE_PIECE_SCENE, BLACK_PIECE_SCENE]:
		var packed := load(path) as PackedScene

		if packed == null:
			status_label.text = "ARTWORK ERROR / CHECK PIECE SCENE PATHS"
			return

		packed_scenes.append(packed)
	
	# Collect all animation names from both scenes.
	var specs: Array[Dictionary] = []
	for scene_index in range(packed_scenes.size()):
		var probe := packed_scenes[scene_index].instantiate()
		var animated_sprite := _find_animated_sprite(probe)

		if animated_sprite == null:
			probe.free()
			return
		
		var names := animated_sprite.sprite_frames.get_animation_names()

		if names.size() != EXPECTED_ANIMATIONS:
			probe.free()
			print("Scene %d has %d animations: %s" % [scene_index, names.size(), names])
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
			status_label.text = "ARTWORK ERROR / PIECE ROOT MUST BE NODE2D"
			return

		var sprite := _find_animated_sprite(piece)

		if sprite == null:
			piece.free()
			status_label.text = "ARTWORK ERROR / SPRITE NOT FOUND"
			return

		sprite.animation = spec["anim"]
		sprite.stop()

		# Keep pieces subtle in the background.
		piece.modulate = Color(
			0.8,
			0.9,
			1.0,
			rng.randf_range(0.22, 0.48)
		)
		
		piece_layer.add_child(piece)

		pieces.append(piece)

		# Assign a randomized grid position.
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


# Plays the click, starts the fade, and runs `action` once the screen is black.
func _transition_then(action: Callable) -> void:
	if transitioning:
		return

	transitioning = true
	play_button.disabled = true
	quit_button.disabled = true
	motion_button.disabled = true

	_play_click()

	# Don't await fade(): it also waits on the audio-fade loop.
	# Wait for the signal instead, which fires when fade_to_black ends.
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
		status_label.text = "Could not open game setup. Check the scene path."


func _quit_game() -> void:
	_transition_then(get_tree().quit)
