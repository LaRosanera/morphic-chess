extends CanvasLayer
#use this signal in other scripts. Plays when the fade_to_black animation finishes.
signal on_transition_finished

@onready var color_rect: ColorRect = $ColorRect
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var old_value = 0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	color_rect.visible = false
	
#call through other scripts. Put into auto load
func fade():
	color_rect.visible = true
	#plays animation
	animation_player.play('fade_to_black')
	var value = db_to_linear(AudioServer.get_bus_volume_db(0))
	old_value = value
	while value > 0:
		
		AudioServer.set_bus_volume_db(0,linear_to_db(value))
		await get_tree().create_timer(0.5).timeout
		value -= 0.5
	

#Checks for when the animation finishes
func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == 'fade_to_black':
		on_transition_finished.emit()
		animation_player.play('fade_to_normal')
		AudioServer.set_bus_volume_db(0,linear_to_db(old_value))
	elif anim_name == 'fade_to_normal':
		color_rect.visible = false
