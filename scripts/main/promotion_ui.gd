class_name PromotionUI
extends RefCounted
## Wraps UI/PromotionPicker. Builds one button per option and emits
## `chosen` with the piece type when one is pressed.

signal chosen(piece_type: String)

var _picker: Control


func _init(picker: Control) -> void:
	_picker = picker
	_picker.hide()


func show_options(options: Array[String]) -> void:
	# Remove buttons from the previous promotion.
	for child in _picker.get_children():
		_picker.remove_child(child)
		child.queue_free()

	for piece_type in options:
		var button := Button.new()
		button.name = piece_type.capitalize()
		button.text = piece_type.capitalize()
		button.pressed.connect(_on_pressed.bind(piece_type))
		_picker.add_child(button)

	_picker.show()


func hide() -> void:
	_picker.hide()


func _on_pressed(piece_type: String) -> void:
	chosen.emit(piece_type)
