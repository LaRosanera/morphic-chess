extends Control

const TITLE_SCENE := "res://Scenes/Main/title_screen.tscn"
const GAME_SCENE := "res://Scenes/Chess/chess_board.tscn"
const DAILY_SEED := 20261102
const DEFAULT_PORT := 7777

const TIME_OPTIONS := [
	{"label": "Untimed", "seconds": 0, "increment": 0},
	{"label": "Bullet — 1 + 0", "seconds": 60, "increment": 0},
	{"label": "Blitz — 3 + 2", "seconds": 180, "increment": 2},
	{"label": "Blitz — 5 + 0", "seconds": 300, "increment": 0},
	{"label": "Rapid — 10 + 0", "seconds": 600, "increment": 0},
	{"label": "Rapid — 15 + 10", "seconds": 900, "increment": 10}
]

enum Role { HOST, JOIN }

# --- Audio ---
@onready var button_audio: AudioStreamPlayer2D = $ButtonAudio

# --- local fields ---
@onready var white_field: Control = $Center/Panel/Margin/Content/Fields/WhiteField
@onready var black_field: Control = $Center/Panel/Margin/Content/Fields/BlackField
@onready var time_field: Control = $Center/Panel/Margin/Content/Fields/TimeField
@onready var orientation_field: Control = $Center/Panel/Margin/Content/Fields/OrientationField
@onready var seed_field: Control = $Center/Panel/Margin/Content/Fields/SeedField
@onready var daily_field: Control = $Center/Panel/Margin/Content/Fields/DailyField

@onready var white_name: LineEdit = $Center/Panel/Margin/Content/Fields/WhiteField/WhiteName
@onready var black_name: LineEdit = $Center/Panel/Margin/Content/Fields/BlackField/BlackName

@onready var time_control: OptionButton = $Center/Panel/Margin/Content/Fields/TimeField/TimeControl
@onready var orientation: OptionButton = $Center/Panel/Margin/Content/Fields/OrientationField/Orientation

@onready var seed_input: LineEdit = $Center/Panel/Margin/Content/Fields/SeedField/SeedInput
@onready var daily_seed: CheckButton = $Center/Panel/Margin/Content/Fields/DailyField/DailySeed

# --- mode tabs + online fields ---
@onready var fields_grid: GridContainer = $Center/Panel/Margin/Content/Fields
@onready var subtitle: Label = $Center/Panel/Margin/Content/Header/Subtitle
@onready var local_tab: Button = $Center/Panel/Margin/Content/ModeTabs/LocalTab
@onready var online_tab: Button = $Center/Panel/Margin/Content/ModeTabs/OnlineTab

@onready var online_fields: Control = $Center/Panel/Margin/Content/OnlineFields
@onready var online_name: LineEdit = $Center/Panel/Margin/Content/OnlineFields/NameField/OnlineName
@onready var role_select: OptionButton = $Center/Panel/Margin/Content/OnlineFields/RoleField/RoleSelect
@onready var ip_field: Control = $Center/Panel/Margin/Content/OnlineFields/IpField
@onready var ip_input: LineEdit = $Center/Panel/Margin/Content/OnlineFields/IpField/IpInput
@onready var port_input: LineEdit = $Center/Panel/Margin/Content/OnlineFields/PortField/PortInput

@onready var summary: Label = $Center/Panel/Margin/Content/SummaryPanel/Summary
@onready var status_label: Label = $Center/Panel/Margin/Content/StatusLabel

@onready var start_button: Button = $Center/Panel/Margin/Content/Buttons/StartButton
@onready var back_button: Button = $Center/Panel/Margin/Content/Buttons/BackButton

@onready var panel: PanelContainer = $Center/Panel
@onready var summary_panel: PanelContainer = $Center/Panel/Margin/Content/SummaryPanel

var transitioning := false
var waiting := false  # hosting/joining in progress, waiting on the network


func _ready() -> void:
	_build_options()
	_apply_styles()
	_connect_signals()
	_connect_button_sounds(self)
	_restore_settings()
	_restore_online_prefs()
	_update_seed()
	_refresh_layout()

	white_name.grab_focus()


func _build_options() -> void:
	for option in TIME_OPTIONS:
		time_control.add_item(option.label)

	orientation.add_item("White at the bottom")
	orientation.add_item("Black at the bottom")

	role_select.add_item("Host a game")
	role_select.add_item("Join a game")

	var group := ButtonGroup.new()
	local_tab.button_group = group
	online_tab.button_group = group


func _connect_signals() -> void:
	white_name.text_changed.connect(_update_summary)
	black_name.text_changed.connect(_update_summary)
	seed_input.text_changed.connect(_update_summary)

	time_control.item_selected.connect(_update_summary)
	orientation.item_selected.connect(_update_summary)
	daily_seed.toggled.connect(_on_daily_seed)

	online_tab.toggled.connect(func(_pressed: bool) -> void: _refresh_layout())
	role_select.item_selected.connect(func(_i: int) -> void: _refresh_layout())
	online_name.text_changed.connect(_update_summary)
	ip_input.text_changed.connect(_update_summary)
	port_input.text_changed.connect(_update_summary)

	start_button.pressed.connect(_start_game)
	back_button.pressed.connect(_go_back)

	NetworkManager.opponent_connected.connect(_on_opponent_connected)
	NetworkManager.match_ready.connect(_on_match_ready)
	NetworkManager.connection_failed.connect(_on_connection_failed)


# --------------------------------------------------
# STYLING
# --------------------------------------------------

func _apply_styles() -> void:
	panel.add_theme_stylebox_override(
		"panel",
		_style(Color("#111923"), Color("#405568"))
	)

	summary_panel.add_theme_stylebox_override(
		"panel",
		_style(Color("#090f0c"), Color("#304b3b"))
	)

	for widget in [
		white_name,
		black_name,
		time_control,
		orientation,
		seed_input,
		daily_seed,
		back_button,
		start_button,
		local_tab,
		online_tab,
		online_name,
		role_select,
		ip_input,
		port_input
	]:
		_style_widget(widget)

	start_button.add_theme_stylebox_override(
		"normal",
		_style(Color("#203c30"), Color("#7efc7e"))
	)

	# The selected tab stays highlighted.
	var selected := _style(Color("#203c30"), Color("#7efc7e"))
	for tab in [local_tab, online_tab]:
		tab.add_theme_stylebox_override("pressed", selected)
		tab.add_theme_stylebox_override("hover_pressed", selected)


func _style_widget(widget: Control) -> void:
	var normal := _style(Color("#192330"), Color("#45596d"))
	var hover := _style(Color("#253547"), Color("#7efc7e"))
	var focus := _style(Color.TRANSPARENT, Color("#7efc7e"))

	widget.add_theme_stylebox_override("normal", normal)
	widget.add_theme_stylebox_override("hover", hover)
	widget.add_theme_stylebox_override("pressed", hover)
	widget.add_theme_stylebox_override("focus", focus)

	widget.add_theme_font_size_override("font_size", 14)
	widget.add_theme_color_override("font_color", Color("#edf3fa"))

	if widget is Button:
		widget.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


# --------------------------------------------------
# MODE / LAYOUT
# --------------------------------------------------

func _is_online() -> bool:
	return online_tab.button_pressed


func _is_hosting() -> bool:
	return _is_online() and role_select.selected == Role.HOST


func _is_joining() -> bool:
	return _is_online() and role_select.selected == Role.JOIN


func _refresh_layout() -> void:
	var online := _is_online()
	var joining := _is_joining()

	# Local-only fields. Board orientation is automatic online (your side is
	# always at the bottom), and colors are randomized by the host.
	white_field.visible = not online
	black_field.visible = not online
	orientation_field.visible = not online

	# Online-only fields.
	online_fields.visible = online
	ip_field.visible = joining

	# The host decides time control and seed; the joiner receives them.
	time_field.visible = not joining
	seed_field.visible = not joining
	daily_field.visible = not joining
	# Host: Name | Connection | Port on one row, Time | Seed | Daily on one row.
	# Join: Name | Connection, then IP | Port.
	var hosting := _is_hosting()
	online_fields.columns = 3 if hosting else 2
	fields_grid.columns = 3 if hosting else 2

	# Let the cells share the width evenly while online.
	var flag := Control.SIZE_EXPAND_FILL if online else Control.SIZE_FILL
	for grid in [online_fields, fields_grid]:
		for child in grid.get_children():
			(child as Control).size_flags_horizontal = flag
	if not online:
		subtitle.text = "LOCAL TWO-PLAYER / STANDARD STARTING POSITION"
		start_button.text = "START GAME  >"
	elif joining:
		subtitle.text = "ONLINE / JOIN A GAME"
		start_button.text = "JOIN GAME  >"
	else:
		subtitle.text = "ONLINE / HOST A GAME / COLORS ARE RANDOMIZED"
		start_button.text = "HOST GAME  >"

	_update_summary()


func _set_waiting(value: bool) -> void:
	waiting = value
	back_button.text = "< CANCEL" if value else "< BACK"
	start_button.disabled = value

	for widget in [
		local_tab, online_tab, role_select, time_control,
		online_name, ip_input, port_input, seed_input, daily_seed
	]:
		if widget is LineEdit:
			widget.editable = not value
		else:
			widget.disabled = value

	if not value:
		_update_seed()


# --------------------------------------------------
# CONFIGURATION
# --------------------------------------------------

func _player_name(field: LineEdit, fallback: String) -> String:
	var value := field.text.strip_edges()
	return fallback if value.is_empty() else value


func _selected_seed() -> int:
	if daily_seed.button_pressed:
		return DAILY_SEED

	return seed_input.text.strip_edges().to_int()


func _get_configuration() -> Dictionary:
	var clock: Dictionary = TIME_OPTIONS[time_control.selected]

	return {
		"mode": "local",
		"variant": "standard",
		"white_name": _player_name(white_name, "White"),
		"black_name": _player_name(black_name, "Black"),
		"time_control_index": time_control.selected,
		"initial_time_seconds": clock.seconds,
		"increment_seconds": clock.increment,
		"timed": clock.seconds > 0,
		"board_flipped": orientation.selected == 1,
		"seed": _selected_seed(),
		"custom_seed": seed_input.text,
		"daily_seed": daily_seed.button_pressed
	}


# --------------------------------------------------
# DISPLAY
# --------------------------------------------------

func _update_summary(_value = null) -> void:
	if summary == null:
		return

	if _is_online():
		summary.text = _online_summary()
		return

	var seed_text := "DAILY / %d" % DAILY_SEED if daily_seed.button_pressed \
		else "CUSTOM / %s" % seed_input.text

	summary.text = "%s vs %s\n%s  |  SEED: %s" % [
		_player_name(white_name, "White"),
		_player_name(black_name, "Black"),
		TIME_OPTIONS[time_control.selected].label,
		seed_text
	]


func _online_summary() -> String:
	var player := _player_name(online_name, "Player")
	var port := port_input.text.strip_edges()

	if _is_joining():
		return "%s  >  %s:%s\nTime control, seed and colors are set by the host" % [
			player, ip_input.text.strip_edges(), port
		]

	var seed_text := "DAILY / %d" % DAILY_SEED if daily_seed.button_pressed \
		else "CUSTOM / %s" % seed_input.text

	return "%s hosting on port %s\n%s  |  SEED: %s  |  COLOR: RANDOM" % [
		player, port, TIME_OPTIONS[time_control.selected].label, seed_text
	]


func _on_daily_seed(_enabled: bool) -> void:
	_update_seed()
	_update_summary()


func _update_seed() -> void:
	seed_input.editable = not daily_seed.button_pressed
	seed_input.modulate = Color.WHITE if not daily_seed.button_pressed else Color("#777777")


# --------------------------------------------------
# SETTINGS
# --------------------------------------------------

func _restore_settings() -> void:
	var config: Dictionary = get_tree().get_meta("chess_config", {})

	# After an online match the stored config holds the online names/colors;
	# don't let those leak into the local fields.
	if config.get("mode", "local") == "online":
		config = {}

	white_name.text = config.get("white_name", "")
	black_name.text = config.get("black_name", "")

	time_control.select(
		clampi(int(config.get("time_control_index", 0)), 0, TIME_OPTIONS.size() - 1)
	)

	orientation.select(
		1 if config.get("board_flipped", false) else 0
	)

	seed_input.text = str(config.get("custom_seed", "12345"))
	daily_seed.button_pressed = config.get("daily_seed", false)


func _restore_online_prefs() -> void:
	var prefs: Dictionary = get_tree().get_meta("online_prefs", {})

	online_name.text = prefs.get("name", "")
	ip_input.text = prefs.get("ip", "")
	port_input.text = str(prefs.get("port", DEFAULT_PORT))
	role_select.select(clampi(int(prefs.get("role", Role.HOST)), 0, 1))

	if prefs.get("online", false):
		online_tab.button_pressed = true


func _save_online_prefs() -> void:
	get_tree().set_meta("online_prefs", {
		"name": online_name.text,
		"ip": ip_input.text,
		"port": port_input.text,
		"role": role_select.selected,
		"online": _is_online()
	})


# --------------------------------------------------
# SCENE TRANSITIONS
# --------------------------------------------------

func _start_game() -> void:
	if transitioning or waiting:
		return

	if _is_online():
		_start_online()
		return

	if not daily_seed.button_pressed and not seed_input.text.strip_edges().is_valid_int():
		status_label.text = "INVALID SEED / ENTER A VALID INTEGER"
		return

	if not ResourceLoader.exists(GAME_SCENE, "PackedScene"):
		status_label.text = "GAME SCENE NOT FOUND / CHECK GAME_SCENE PATH"
		return

	var config := _get_configuration()
	_load_game(config)


func _load_game(config: Dictionary) -> void:
	get_tree().set_meta("chess_config", config)
	get_tree().set_meta("game_seed", config.seed)

	_change_scene_with_transition(GAME_SCENE, "COULD NOT LOAD THE GAME SCENE")


func _go_back() -> void:
	if transitioning:
		return

	# While hosting/joining, "back" cancels the connection instead of leaving.
	if waiting:
		NetworkManager.shutdown()
		_set_waiting(false)
		status_label.text = ""
		return

	get_tree().set_meta("chess_config", _get_configuration())
	_save_online_prefs()

	_change_scene_with_transition(TITLE_SCENE, "COULD NOT RETURN TO TITLE SCREEN")
func _play_click() -> void:
	if button_audio.stream != null:
		button_audio.play()


# Hooks up the click sound to every button in the scene, however deeply nested.
func _connect_button_sounds(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(_play_click)

	# Dropdowns also click when you pick an item.
	if node is OptionButton:
		node.item_selected.connect(func(_i: int) -> void: _play_click())

	for child in node.get_children():
		_connect_button_sounds(child)
		

# Locks the UI, fades to black, then swaps scenes behind the black screen.
func _change_scene_with_transition(path: String, error_text: String) -> void:
	if transitioning:
		return

	_set_transitioning(true)

	# Don't await fade() itself, since it also waits on the audio-fade loop.
	# The signal fires when fade_to_black ends.
	Transition.fade()
	await Transition.on_transition_finished

	var error := get_tree().change_scene_to_file(path)

	if error != OK:
		_set_transitioning(false)
		status_label.text = error_text


func _set_transitioning(value: bool) -> void:
	transitioning = value
	start_button.disabled = value or waiting
	back_button.disabled = value


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_play_click()
			_go_back()


# --------------------------------------------------
# ONLINE
# --------------------------------------------------

func _start_online() -> void:
	_save_online_prefs()

	var port_text := port_input.text.strip_edges()
	if not port_text.is_valid_int() or int(port_text) < 1024 or int(port_text) > 65535:
		status_label.text = "INVALID PORT / USE A NUMBER FROM 1024 TO 65535"
		return

	var port := int(port_text)
	var player := _player_name(online_name, "Player")

	if _is_hosting():
		if not daily_seed.button_pressed and not seed_input.text.strip_edges().is_valid_int():
			status_label.text = "INVALID SEED / ENTER A VALID INTEGER"
			return

		var err := NetworkManager.host_game(port, player, _get_configuration())
		if err != OK:
			status_label.text = "COULD NOT HOST / PORT %d MAY ALREADY BE IN USE" % port
			return

		_set_waiting(true)

		var addresses := NetworkManager.local_addresses()
		var share := ", ".join(addresses) if not addresses.is_empty() else "your IP"
		status_label.text = "WAITING FOR OPPONENT ON PORT %d (UDP)\nLAN ADDRESS: %s  |  FOR INTERNET PLAY, SHARE YOUR PUBLIC IP AND FORWARD THE PORT" % [port, share]
	else:
		var address := ip_input.text.strip_edges()
		if address.is_empty():
			status_label.text = "ENTER THE HOST'S IP ADDRESS"
			return

		var err := NetworkManager.join_game(address, port, player)
		if err != OK:
			status_label.text = "COULD NOT START CONNECTION / CHECK THE ADDRESS"
			return

		_set_waiting(true)
		status_label.text = "CONNECTING TO %s:%d ..." % [address, port]


func _on_opponent_connected() -> void:
	if waiting:
		status_label.text = "OPPONENT CONNECTED / STARTING MATCH ..."


func _on_match_ready(config: Dictionary) -> void:
	if transitioning:
		return

	_load_game(config)

func _on_connection_failed(reason: String) -> void:
	if transitioning:
		return

	_set_waiting(false)
	status_label.text = reason
