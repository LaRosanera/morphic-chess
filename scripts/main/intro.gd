extends Control

const TITLE_SCREEN := "res://Scenes/Main/title_screen.tscn"

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var audio_player: AudioStreamPlayer = $"F#"

var transitioning := false


func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)

	# Slight delay before the intro sound.
	await get_tree().create_timer(0.8).timeout

	if is_inside_tree() and not transitioning:
		audio_player.play()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != "intro" or transitioning:
		return

	transitioning = true

	Transition.fade()
	await Transition.on_transition_finished

	var error := get_tree().change_scene_to_file(TITLE_SCREEN)

	if error != OK:
		push_error("Could not load title screen: " + TITLE_SCREEN)
		transitioning = false
