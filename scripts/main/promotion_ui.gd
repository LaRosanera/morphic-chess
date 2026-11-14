
class_name PromotionUI
extends RefCounted

## Wraps UI/PromotionPicker. Builds styled buttons with piece icons
## and emits `chosen` with the piece type when one is pressed.

signal chosen(piece_type: String)

const BLACK_PIECE_SCENE := preload("res://Scenes/Chess/classic_black_piece.tscn")
const WHITE_PIECE_SCENE := preload("res://Scenes/Chess/classic_white_piece.tscn")

const BUTTON_SIZE := Vector2(100, 110)
const ICON_SIZE := Vector2(64, 64)
const GRID_COLUMNS := 4

var _picker: Control
var _grid: GridContainer

var _black_frames: SpriteFrames
var _white_frames: SpriteFrames


func _init(picker: Control) -> void:
	_picker = picker
	_picker.hide()

	_black_frames = _extract_sprite_frames(BLACK_PIECE_SCENE)
	_white_frames = _extract_sprite_frames(WHITE_PIECE_SCENE)

	_picker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	# Create a grid inside the existing picker.
	_grid = GridContainer.new()
	_grid.name = "PromotionGrid"
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS

	_picker.add_child(_grid)


func show_options(options: Array[String], is_white: bool = true) -> void:
	# Remove previous promotion buttons.
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	var frames: SpriteFrames = _white_frames if is_white else _black_frames
	var color_prefix := "white_" if is_white else "black_"

	for piece_type in options:
		var anim_name := color_prefix + piece_type.to_lower()
		var button := _create_piece_button(piece_type, frames, anim_name)
		_grid.add_child(button)

	_picker.show()
	_recenter.call_deferred()


func hide() -> void:
	_picker.hide()


func _create_piece_button(
	piece_type: String,
	frames: SpriteFrames,
	anim_name: String
) -> Button:
	var button := Button.new()
	button.name = piece_type.capitalize()
	button.custom_minimum_size = BUTTON_SIZE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_pressed.bind(piece_type))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(vbox)

	# Piece icon.
	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	if frames != null and frames.has_animation(anim_name):
		icon.texture = frames.get_frame_texture(anim_name, 0)

	vbox.add_child(icon)

	# Piece name.
	var label := Label.new()
	label.text = piece_type.capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(label)

	return button


func _extract_sprite_frames(scene: PackedScene) -> SpriteFrames:
	if scene == null:
		return null

	var instance := scene.instantiate()

	var sprite := instance as AnimatedSprite2D

	if sprite == null:
		sprite = instance.find_child("*", true, false) as AnimatedSprite2D

	var frames: SpriteFrames = sprite.sprite_frames if sprite != null else null

	instance.free()

	return frames


func _recenter() -> void:
	_picker.reset_size()

	var viewport_center := _picker.get_viewport_rect().get_center()

	var local_center := (
		_picker.get_global_transform_with_canvas().affine_inverse()
		* viewport_center
	)

	_picker.position += local_center - _picker.size * 0.5


func _on_pressed(piece_type: String) -> void:
	chosen.emit(piece_type)
