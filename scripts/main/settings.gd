
extends Control

const MAIN_MENU_PATH := "res://Scenes/Main/title_screen.tscn"

var chess_board: Node2D

@onready var game_info: RichTextLabel = $Center/Panel/Margin/Main/Tabs/Game/GameScroll/GameInfo

@onready var master_slider: HSlider = $Center/Panel/Margin/Main/Tabs/Audio/MasterSlider
@onready var music_slider: HSlider = $Center/Panel/Margin/Main/Tabs/Audio/MusicSlider
@onready var sfx_slider: HSlider = $Center/Panel/Margin/Main/Tabs/Audio/SFXSlider


func setup(board: Node2D) -> void:
	chess_board = board
	_refresh_game_info()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	_setup_audio()

func _refresh_game_info() -> void:
	if not is_instance_valid(chess_board):
		return

	var lines: Array[String] = []
	lines.append("[b]DAILY MODIFICATIONS[/b]")

	for change in chess_board.daily_changes:
		lines.append("• " + change)

	lines.append("")
	lines.append("[b]DAILY SEED[/b]")
	lines.append("Seed: %d" % chess_board.game_seed)
	lines.append("")

	lines.append("[b]BOARD[/b]")
	lines.append("Board size: 8 × 8")
	lines.append("Starting layout: %s" % chess_board.preset_path)
	lines.append("")

	lines.append("[b]PLAYERS[/b]")
	lines.append("White: %s" % chess_board.player1_name)
	lines.append("Black: %s" % chess_board.player2_name)
	lines.append("White piece color: White")
	lines.append("Black piece color: Black")
	lines.append("")

	lines.append("[b]ACTIVE MOVEMENT RULES[/b]")
	lines.append("The following values include today's modifications.")
	lines.append("")

	for piece_type in chess_board.rules:
		var rule = chess_board.rules[piece_type]

		lines.append("[color=yellow]%s[/color]" % piece_type.capitalize())
		lines.append("Maximum range: %d" % rule.max_range)
		lines.append("First move range: %d" % rule.first_move_range)
		lines.append("Can jump: %s" % str(rule.jumps))
		lines.append("Can promote: %s" % str(rule.promotes))
		lines.append("Movement directions: %s" % str(rule.directions))
		lines.append("Move-only directions: %s" % str(rule.move_only_directions))
		lines.append("Capture-only directions: %s" % str(rule.capture_only_directions))
		lines.append("")

	game_info.text = "\n".join(lines)


func _setup_audio() -> void:
	_connect_audio_slider(master_slider, "Master")
	_connect_audio_slider(music_slider, "Music")
	_connect_audio_slider(sfx_slider, "SFX")


func _connect_audio_slider(slider: HSlider, bus_name: String) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)

	if bus_index == -1:
		slider.editable = false
		return

	slider.value = AudioServer.get_bus_volume_linear(bus_index)

	slider.value_changed.connect(
		func(value: float):
			AudioServer.set_bus_volume_linear(bus_index, value)
	)


func _on_close_pressed() -> void:
	queue_free()


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()
