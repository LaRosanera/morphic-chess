class_name ChessClock
extends RefCounted
## Two-sided chess clock. Pure logic, no drawing and no networking.

signal expired(color: String)

var enabled := false
var running := false
var initial := 0
var increment := 0
var active := "white"
var remaining := {"white": 0.0, "black": 0.0}


func setup(initial_seconds: int, increment_seconds: int) -> void:
	initial = initial_seconds
	increment = increment_seconds
	enabled = initial > 0
	running = enabled
	active = "white"
	remaining = {"white": float(initial), "black": float(initial)}


func tick(delta: float) -> void:
	if not enabled or not running:
		return

	remaining[active] -= delta

	if remaining[active] <= 0.0:
		remaining[active] = 0.0
		running = false
		expired.emit(active)


## The side that just moved gets the increment, then the other side's clock runs.
func switch_to(color: String) -> void:
	if not enabled:
		return

	remaining[active] += increment
	active = color


func stop() -> void:
	running = false


## Used by the guest to copy the host's clock.
func apply_state(
	initial_seconds: int, increment_seconds: int,
	white: float, black: float, active_color: String, is_running: bool
) -> void:
	initial = initial_seconds
	increment = increment_seconds
	enabled = initial > 0
	remaining = {"white": white, "black": black}
	active = active_color
	running = is_running and enabled


static func format(seconds: float) -> String:
	seconds = maxf(seconds, 0.0)

	if seconds < 10.0:
		return "0:%04.1f" % seconds

	var total := int(ceil(seconds))
	return "%d:%02d" % [floori(total / 60.0), total % 60]
