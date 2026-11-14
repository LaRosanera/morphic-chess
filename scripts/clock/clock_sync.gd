class_name ClockSync
extends Node
## Host-authoritative clock sync. The node path must be identical on host and
## guest (the board adds it as "ClockSync").

signal synced
signal timed_out(color: String)

var clock: ChessClock


func setup(c: ChessClock) -> void:
	clock = c


func _online() -> bool:
	return multiplayer.has_multiplayer_peer()


## Guest -> host: "send me the clock".
func ask_host() -> void:
	if _online() and not multiplayer.is_server():
		_host_request_state.rpc_id(1)


## Host -> guest: current clock (call after every move).
func broadcast() -> void:
	if not (_online() and multiplayer.is_server()):
		return

	for id in multiplayer.get_peers():
		_send_state(id)


func send_timeout(color: String) -> void:
	if not (_online() and multiplayer.is_server()):
		return

	for id in multiplayer.get_peers():
		_receive_timeout.rpc_id(id, color)


func _send_state(id: int) -> void:
	_receive_state.rpc_id(
		id, clock.initial, clock.increment,
		clock.remaining["white"], clock.remaining["black"],
		clock.active, clock.running
	)


@rpc("any_peer", "call_remote", "reliable")
func _host_request_state() -> void:
	if multiplayer.is_server():
		_send_state(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func _receive_state(
	initial: int, increment: int,
	white: float, black: float, active: String, running: bool
) -> void:
	clock.apply_state(initial, increment, white, black, active, running)
	synced.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_timeout(color: String) -> void:
	timed_out.emit(color)
