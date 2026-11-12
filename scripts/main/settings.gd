
extends Control

const MAIN_MENU_PATH := "res://Scenes/Main/title_screen.tscn"

var chess_board: Node2D

const WHITE_PIECE_SCENE: PackedScene = preload("res://Scenes/Chess/classic_white_piece.tscn")
@onready var master_slider: HSlider = $Center/Panel/Margin/Main/Tabs/Audio/MasterSlider
@onready var music_slider: HSlider = $Center/Panel/Margin/Main/Tabs/Audio/MusicSlider
@onready var sfx_slider: HSlider = $Center/Panel/Margin/Main/Tabs/Audio/SFXSlider
@onready var resolution_option: OptionButton = $Center/Panel/Margin/Main/Tabs/Display/ResolutionOption
@onready var fullscreen_check: CheckButton = $Center/Panel/Margin/Main/Tabs/Display/FullscreenCheck
@onready var tabs: TabContainer = $Center/Panel/Margin/Main/Tabs
@onready var close_button: Button = $Center/Panel/Margin/Main/Header/Close
@onready var main_menu_button: Button = $Center/Panel/Margin/Main/Footer/MainMenu

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(768, 552),
	Vector2i(1152, 828),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const ICON_SIZE := 56

@onready var game_info: RichTextLabel = $Center/Panel/Margin/Main/Tabs/Game/GameScroll/GameContent/GameInfo
@onready var rules_list: VBoxContainer = $Center/Panel/Margin/Main/Tabs/Game/GameScroll/GameContent/RulesList
var _sizes: Array[Vector2i] = []

func setup(board: Node2D) -> void:
	chess_board = board
	_refresh_game_info()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_audio()
	_setup_display()
## USED DURING THE GAME
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

	game_info.text = "\n".join(lines)
	_build_rules_list()
## USED OUTSDIE
func _refresh_display_state() -> void:
	# No-signal version, so setting the checkbox doesn't toggle fullscreen again.
	fullscreen_check.set_pressed_no_signal(_is_fullscreen())
	_sync_resolution_option()
	


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

func _setup_display() -> void:
	# Only offer sizes that fit on this monitor.
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())

	resolution_option.clear()
	_sizes.clear()
	for size in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y:
			_sizes.append(size)
			resolution_option.add_item("%d x %d" % [size.x, size.y])

	# Show the current state before connecting, so it doesn't trigger a change.
	fullscreen_check.button_pressed = _is_fullscreen()
	_sync_resolution_option()

	resolution_option.item_selected.connect(_on_resolution_selected)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)


func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _sync_resolution_option() -> void:
	resolution_option.disabled = _is_fullscreen()
	resolution_option.select(_sizes.find(DisplayServer.window_get_size()))


func _on_resolution_selected(index: int) -> void:
	var size := _sizes[index]
	var screen := DisplayServer.window_get_current_screen()
	var origin := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)

	DisplayServer.window_set_size(size)
	# Re-center so the window doesn't hang off the screen edge.
	DisplayServer.window_set_position(origin + (screen_size - size) / 2)


func _on_fullscreen_toggled(enabled: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if enabled
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	# The window size can take a frame to update after a mode change.
	await get_tree().process_frame
	_sync_resolution_option()
func _build_rules_list() -> void:
	for child in rules_list.get_children():
		child.queue_free()

	var frames := _get_piece_frames()

	for piece_type in chess_board.rules:
		var rule = chess_board.rules[piece_type]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.texture = _piece_texture(frames, piece_type)
		row.add_child(icon)

		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.scroll_active = false
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.text = "\n".join([
			"[color=CADET_BLUE]%s[/color]" % piece_type.capitalize(),
			"Maximum range: %d" % rule.max_range,
			"First move range: %d" % rule.first_move_range,
			"Can jump: %s" % str(rule.jumps),
			"Can promote: %s" % str(rule.promotes),
			"Movement directions: %s" % str(rule.directions),
			"Move-only directions: %s" % str(rule.move_only_directions),
			"Capture-only directions: %s" % str(rule.capture_only_directions),
		])
		row.add_child(info)

		rules_list.add_child(row)
		rules_list.add_child(HSeparator.new())


# Grabs the SpriteFrames from the white piece scene the board already uses.
func _get_piece_frames() -> SpriteFrames:
	var probe: Node = WHITE_PIECE_SCENE.instantiate()
	var frames: SpriteFrames = null

	if probe is AnimatedSprite2D:
		frames = (probe as AnimatedSprite2D).sprite_frames

	probe.free()
	return frames


func _piece_texture(frames: SpriteFrames, piece_type: String) -> Texture2D:
	var anim := "white_%s" % piece_type
	if frames == null or not frames.has_animation(anim):
		return null
	return frames.get_frame_texture(anim, 0)
	
## OPEN AND CLOSING
func open(board: Node2D = null) -> void:
	
	chess_board = board
	var in_game := is_instance_valid(board)

	# Make sure it's above the siblings
	get_parent().move_child(self, -1)
	# The Game tab and Main Menu button only make sense during a game.
	tabs.set_tab_hidden(0, not in_game)
	main_menu_button.visible = in_game
	tabs.current_tab = 0 if in_game else 2  # 2 = Display

	if in_game:
		_refresh_game_info()
	var online_match := in_game and NetworkManager.is_online

	main_menu_button.text = "Leave Match" if online_match else "Main Menu"
	main_menu_button.visible = in_game
	_refresh_display_state()
	visible = true

	# Keyboard focus may still be on a button in the scene underneath,
	# so Enter or Space would press it. Take focus here.
	close_button.grab_focus()
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	visible = false
	chess_board = null
	
func _on_close_pressed() -> void:
	close()


func _on_main_menu_pressed() -> void:
	NetworkManager.shutdown()
	close()
	get_tree().change_scene_to_file(MAIN_MENU_PATH)

func _on_quit_pressed() -> void:
	var tree := get_tree()

	print("QUIT 1: handler entered; host=", NetworkManager.is_host)

	NetworkManager.shutdown()
	print("QUIT 2: shutdown returned")

	tree.quit()
	print("QUIT 3: exit requested")
