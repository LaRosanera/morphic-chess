class_name ClockSync
extends Node
## The host stores authoritative clock snapshots in the Firebase room.

signal synced
signal timed_out(color: String)

var clock: ChessClock
var _timeout_reported := false


func setup(c: ChessClock) -> void:
	clock = c
	if not NetworkManager.room_updated.is_connected(_on_room_updated):
		NetworkManager.room_updated.connect(_on_room_updated)


## Guest: immediately apply the latest clock snapshot, if one is available.
func ask_host() -> void:
	if not NetworkManager.is_host:
		_apply_room_clock(NetworkManager.room)


## Host: publish the current clock for the guest.
func broadcast() -> void:
	if not NetworkManager.is_online or not NetworkManager.is_host:
		return

	NetworkManager.write(
		"rooms/%s/clock" % NetworkManager.room_code,
		{
			"initial": clock.initial,
			"increment": clock.increment,
			"white": clock.remaining["white"],
			"black": clock.remaining["black"],
			"active": clock.active,
			"running": clock.running
		},
		_on_clock_written
	)


func send_timeout(color: String) -> void:
	if not NetworkManager.is_online or not NetworkManager.is_host:
		return
	NetworkManager.write(
		"rooms/%s/timeout" % NetworkManager.room_code,
		color,
		_on_clock_written
	)


func _on_clock_written(ok: bool, _code: int, _data: Variant) -> void:
	if not ok:
		NetworkManager.report_connection_lost("Could not synchronize the game clock")


func _on_room_updated(room: Dictionary) -> void:
	_apply_room_clock(room)

	if _timeout_reported:
		return
	var timeout: Variant = room.get("timeout", "")
	if timeout is String and timeout in ["white", "black"]:
		_timeout_reported = true
		timed_out.emit(timeout)


func _apply_room_clock(room: Dictionary) -> void:
	if NetworkManager.is_host:
		return

	var value: Variant = room.get("clock", {})
	if not (value is Dictionary):
		return
	var state: Dictionary = value
	if not state.has("initial") or not state.has("increment") \
			or not state.has("white") or not state.has("black") \
			or not state.has("active") or not state.has("running"):
		return

	clock.apply_state(
		int(state["initial"]),
		int(state["increment"]),
		float(state["white"]),
		float(state["black"]),
		str(state["active"]),
		bool(state["running"])
	)
	synced.emit()
