
extends Control

const SETUP_SCENE := "res://scenes/main/game_setup.tscn"
const white_piece_scene = "res://Scenes/Chess/classic_white_piece.tscn"
const black_piece_scene = "res://Scenes/Chess/classic_black_piece.tscn"
const daily_seed_path = "res://data/daily_seed.json"
@export var motion_speed: float = 0.65

@onready var piece_layer: Node2D = $PieceLayer
@onready var play_button: Button = $MenuCanvas/Panel/Margin/Content/PlayButton
@onready var motion_button: CheckButton = $MenuCanvas/Panel/Margin/Content/MotionButton
@onready var quit_button: Button = $MenuCanvas/Panel/Margin/Content/QuitButton
@onready var status_label: Label = $MenuCanvas/Panel/Margin/Content/StatusLabel
@onready var panel: PanelContainer = $MenuCanvas/Panel
@onready var seed_label: Label = $MenuCanvas/Panel/Margin/Content/SeedLabel
var elapsed := 0.0
var reduced_motion := false
var transitioning := false

var rng := RandomNumberGenerator.new()

var pieces: Array[Node2D] = []
var origins: Array[Vector2] = []
var phases: Array[float] = []
var scales: Array[float] = []


func _ready() -> void:
	rng.randomize()

	_apply_styles()

	reduced_motion = get_tree().get_meta("reduced_motion", false)
	motion_button.button_pressed = reduced_motion

	play_button.pressed.connect(_open_setup)
	motion_button.toggled.connect(_set_reduced_motion)
	quit_button.pressed.connect(_quit_game)

	_create_pieces()

	play_button.grab_focus()
	var data = JSON.parse_string(FileAccess.get_file_as_string(daily_seed_path))
	seed_label.text = " DAILY SEED: %s" % str(data)

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

# There are 12 pieces in an animated sprite for both classic black pieces and white ones. I need you to edit this file so it loads 12 x 3. just everything in the file and have them randomly positoned. it should be around 72 in total because you double for black pieces. 
func _create_pieces() -> void:
	var copies_per_piece := 3

	# Load both scenes once.
	var packed_scenes: Array[PackedScene] = []
	for path in [white_piece_scene, black_piece_scene]:
		var packed := load(path) as PackedScene
		if packed == null:
			status_label.text = "ARTWORK ERROR / CHECK PIECE SCENE PATHS"
			return
		packed_scenes.append(packed)

	# Build (scene index, animation name) specs from each scene's own animations.
	var specs: Array[Dictionary] = []
	for scene_index in range(packed_scenes.size()):
		var probe := packed_scenes[scene_index].instantiate() as AnimatedSprite2D
		var names: PackedStringArray = probe.sprite_frames.get_animation_names()
		probe.free()

		for anim_name in names:
			for copy in range(copies_per_piece):
				specs.append({"scene": scene_index, "anim": anim_name})

	var total := specs.size()

	# Shuffle grid cells so the layout is random but doesn't clump.
	var columns := 9
	var rows := int(ceil(float(total) / columns))
	var cells: Array[int] = []
	for i in range(total):
		cells.append(i)

	for i in range(total - 1, 0, -1):
		var other := rng.randi_range(0, i)
		var temp := cells[i]
		cells[i] = cells[other]
		cells[other] = temp

	for i in range(total):
		var spec := specs[i]
		var sprite := packed_scenes[spec["scene"]].instantiate() as AnimatedSprite2D
		sprite.animation = spec["anim"]
		sprite.stop()
		sprite.modulate = Color(0.8, 0.9, 1.0, rng.randf_range(0.22, 0.48))
		piece_layer.add_child(sprite)

		var cell := cells[i]
		pieces.append(sprite)

		origins.append(Vector2(
			(float(cell % columns) + rng.randf_range(0.15, 0.85)) / float(columns),
			(float(cell / columns) + rng.randf_range(0.15, 0.85)) / float(rows)
		))

		phases.append(rng.randf_range(0.0, TAU))
		scales.append(rng.randf_range(0.85, 1.65))

	_update_pieces()

func _find_animated_sprite(node: Node) -> AnimatedSprite2D:
	if node is AnimatedSprite2D:
		return node
	for child in node.get_children():
		var found := _find_animated_sprite(child)
		if found != null:
			return found
	return null

func _process(delta: float) -> void:
	if not reduced_motion:
		elapsed += delta * motion_speed

	_update_pieces()


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

		pieces[i].position = origins[i] * view_size + drift
		pieces[i].rotation = angle
		pieces[i].scale = Vector2.ONE * scales[i]


func _set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	get_tree().set_meta("reduced_motion", enabled)


func _open_setup() -> void:
	if transitioning:
		return

	transitioning = true
	play_button.disabled = true

	var error := get_tree().change_scene_to_file(SETUP_SCENE)

	if error != OK:
		transitioning = false
		play_button.disabled = false
		status_label.text = "Could not open game setup. Check the scene path."


func _quit_game() -> void:
	get_tree().quit()
# ERROR: They are being spawned in, but not moving and being positioned. 
