
extends Control

const TITLE_SCENE := "res://scenes/main/title_screen.tscn"
const GAME_SCENE := "res://Scenes/Chess/chess_board.tscn"
const DAILY_SEED := 20261102

const TIME_OPTIONS := [
	{"label": "Untimed", "seconds": 0, "increment": 0},
	{"label": "Bullet — 1 + 0", "seconds": 60, "increment": 0},
	{"label": "Blitz — 3 + 2", "seconds": 180, "increment": 2},
	{"label": "Blitz — 5 + 0", "seconds": 300, "increment": 0},
	{"label": "Rapid — 10 + 0", "seconds": 600, "increment": 0},
	{"label": "Rapid — 15 + 10", "seconds": 900, "increment": 10}
]

@onready var white_name: LineEdit = $Center/Panel/Margin/Content/Fields/WhiteField/WhiteName
@onready var black_name: LineEdit = $Center/Panel/Margin/Content/Fields/BlackField/BlackName

@onready var time_control: OptionButton = $Center/Panel/Margin/Content/Fields/TimeField/TimeControl
@onready var orientation: OptionButton = $Center/Panel/Margin/Content/Fields/OrientationField/Orientation

@onready var seed_input: LineEdit = $Center/Panel/Margin/Content/Fields/SeedField/SeedInput
@onready var daily_seed: CheckButton = $Center/Panel/Margin/Content/Fields/DailyField/DailySeed

@onready var summary: Label = $Center/Panel/Margin/Content/SummaryPanel/Summary
@onready var status_label: Label = $Center/Panel/Margin/Content/StatusLabel

@onready var start_button: Button = $Center/Panel/Margin/Content/Buttons/StartButton
@onready var back_button: Button = $Center/Panel/Margin/Content/Buttons/BackButton

@onready var panel: PanelContainer = $Center/Panel
@onready var summary_panel: PanelContainer = $Center/Panel/Margin/Content/SummaryPanel

var transitioning := false


func _ready() -> void:
	_build_options()
	_apply_styles()
	_connect_signals()
	_restore_settings()
	_update_seed()
	_update_summary()

	white_name.grab_focus()


func _build_options() -> void:
	for option in TIME_OPTIONS:
		time_control.add_item(option.label)

	orientation.add_item("White at the bottom")
	orientation.add_item("Black at the bottom")


func _connect_signals() -> void:
	white_name.text_changed.connect(_update_summary)
	black_name.text_changed.connect(_update_summary)
	seed_input.text_changed.connect(_update_summary)

	time_control.item_selected.connect(_update_summary)
	orientation.item_selected.connect(_update_summary)
	daily_seed.toggled.connect(_on_daily_seed)

	start_button.pressed.connect(_start_game)
	back_button.pressed.connect(_go_back)


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
		start_button
	]:
		_style_widget(widget)

	start_button.add_theme_stylebox_override(
		"normal",
		_style(Color("#203c30"), Color("#7efc7e"))
	)


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
	if not is_node_ready():
		return

	var seed_text := "DAILY / %d" % DAILY_SEED if daily_seed.button_pressed \
		else "CUSTOM / %s" % seed_input.text

	summary.text = "%s vs %s\n%s  |  SEED: %s" % [
		_player_name(white_name, "White"),
		_player_name(black_name, "Black"),
		TIME_OPTIONS[time_control.selected].label,
		seed_text
	]


func _on_daily_seed(enabled: bool) -> void:
	seed_input.editable = not enabled
	seed_input.modulate = Color.WHITE if not enabled else Color("#777777")
	_update_summary()


func _update_seed() -> void:
	seed_input.editable = not daily_seed.button_pressed
	seed_input.modulate = Color.WHITE if not daily_seed.button_pressed else Color("#777777")


# --------------------------------------------------
# SETTINGS
# --------------------------------------------------

func _restore_settings() -> void:
	var config: Dictionary = get_tree().get_meta("chess_config", {})

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


# --------------------------------------------------
# SCENE TRANSITIONS
# --------------------------------------------------

func _start_game() -> void:
	if transitioning:
		return

	if not daily_seed.button_pressed and not seed_input.text.strip_edges().is_valid_int():
		status_label.text = "INVALID SEED / ENTER A VALID INTEGER"
		return

	if not ResourceLoader.exists(GAME_SCENE, "PackedScene"):
		status_label.text = "GAME SCENE NOT FOUND / CHECK GAME_SCENE PATH"
		return

	var config := _get_configuration()

	get_tree().set_meta("chess_config", config)
	get_tree().set_meta("game_seed", config.seed)

	_set_transitioning(true)

	var error := get_tree().change_scene_to_file(GAME_SCENE)

	if error != OK:
		_set_transitioning(false)
		status_label.text = "COULD NOT LOAD THE GAME SCENE"


func _go_back() -> void:
	if transitioning:
		return

	get_tree().set_meta("chess_config", _get_configuration())

	_set_transitioning(true)

	var error := get_tree().change_scene_to_file(TITLE_SCENE)

	if error != OK:
		_set_transitioning(false)
		status_label.text = "COULD NOT RETURN TO TITLE SCREEN"
	


func _set_transitioning(value: bool) -> void:
	transitioning = value
	start_button.disabled = value
	back_button.disabled = value


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()
