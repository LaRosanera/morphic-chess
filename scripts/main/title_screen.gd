
extends Control

const SETUP_SCENE := "res://scenes/main/game_setup.tscn"
const PIECE_TEXTURE_PATH := "res://assets/pieces/classic/Chess_Pieces_Sprite.svg"

@export var motion_speed: float = 0.65

@onready var piece_layer: Node2D = $PieceLayer
@onready var play_button: Button = $MenuCanvas/Panel/Margin/Content/PlayButton
@onready var motion_button: CheckButton = $MenuCanvas/Panel/Margin/Content/MotionButton
@onready var quit_button: Button = $MenuCanvas/Panel/Margin/Content/QuitButton
@onready var status_label: Label = $MenuCanvas/Panel/Margin/Content/StatusLabel
@onready var panel: PanelContainer = $MenuCanvas/Panel

var elapsed := 0.0
var reduced_motion := false
var transitioning := false

var rng := RandomNumberGenerator.new()

var pieces: Array[Sprite2D] = []
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


func _create_pieces() -> void:
	var atlas := load(PIECE_TEXTURE_PATH) as Texture2D

	if atlas == null:
		status_label.text = "ARTWORK ERROR / CHECK SPRITESHEET PATH"
		return

	# King, queen, bishop, knight, rook, pawn.
	var army_columns: Array[int] = [
		4, 3, 2, 1, 0, 2, 3, 4,
		5, 5, 5, 5, 5, 5, 5, 5
	]

	# Shuffle 64 positions.
	var cells: Array[int] = []

	for i in range(64):
		cells.append(i)

	for i in range(63, 0, -1):
		var other := rng.randi_range(0, i)
		var temp := cells[i]
		cells[i] = cells[other]
		cells[other] = temp

	for i in range(64):
		var side := (i / 16) % 2
		var column := army_columns[i % 16]

		var texture := AtlasTexture.new()
		texture.atlas = atlas
		texture.region = Rect2(
			column * 45.0,
			side * 45.0,
			45.0,
			45.0
		)

		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.modulate = Color(
			0.8,
			0.9,
			1.0,
			rng.randf_range(0.22, 0.48)
		)

		piece_layer.add_child(sprite)

		var cell := cells[i]

		pieces.append(sprite)

		origins.append(Vector2(
			(float(cell % 8) + rng.randf_range(0.15, 0.85)) / 8.0,
			(float(cell / 8) + rng.randf_range(0.15, 0.85)) / 8.0
		))

		phases.append(rng.randf_range(0.0, TAU))
		scales.append(rng.randf_range(0.85, 1.65))

	_update_pieces()


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
