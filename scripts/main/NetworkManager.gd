extends Node
## Autoload: register as "NetworkManager" in Project Settings > Globals.
##
## Flow:
##   host_game()  -> waits for one guest
##   join_game()  -> connects, sends its name to the host
##   host receives the name, randomizes colors, builds a config for each side,
##   sends the guest theirs via RPC, and both sides emit match_ready(config).

signal opponent_connected
signal match_ready(config: Dictionary)
signal connection_failed(reason: String)
signal opponent_left

const DEFAULT_PORT := 7777
const MAX_NAME_LENGTH := 24

var is_online := false
var is_host := false
var match_started := false

var _client_id := 0
var _my_name := ""
var _base_config: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --------------------------------------------------
# PUBLIC API
# --------------------------------------------------

func host_game(port: int, player_name: String, base_config: Dictionary) -> Error:
	shutdown()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = true
	_my_name = _clean_name(player_name, "Host")
	_base_config = base_config.duplicate(true)
	return OK


func join_game(address: String, port: int, player_name: String) -> Error:
	shutdown()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = false
	_my_name = _clean_name(player_name, "Guest")
	return OK


func shutdown() -> void:
	is_online = false
	is_host = false
	match_started = false
	_client_id = 0

	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 \
				and not address.begins_with("127.") \
				and not address.begins_with("169.254."):
			result.append(address)
	return result


# --------------------------------------------------
# HANDSHAKE
# --------------------------------------------------

@rpc("any_peer", "reliable")
func _submit_name(player_name: String) -> void:
	if not is_host or match_started:
		return

	if multiplayer.get_remote_sender_id() != _client_id:
		return

	var guest := _clean_name(player_name, "Guest")
	var host_is_white := randi() % 2 == 0

	match_started = true
	_start_match.rpc_id(_client_id, _make_config(guest, host_is_white, false))
	match_ready.emit(_make_config(guest, host_is_white, true))


@rpc("authority", "reliable")
func _start_match(config: Dictionary) -> void:
	match_started = true
	match_ready.emit(config)


func _make_config(guest_name: String, host_is_white: bool, for_host: bool) -> Dictionary:
	var config := _base_config.duplicate(true)
	var local_is_white := (host_is_white == for_host)

	config["mode"] = "online"
	config["is_host"] = for_host
	config["white_name"] = _my_name if host_is_white else guest_name
	config["black_name"] = guest_name if host_is_white else _my_name
	config["local_color"] = "white" if local_is_white else "black"
	config["local_name"] = _my_name if for_host else guest_name
	config["board_flipped"] = not local_is_white  # your side is always at the bottom
	return config


func _clean_name(value: String, fallback: String) -> String:
	var cleaned := value.strip_edges().substr(0, MAX_NAME_LENGTH)
	return fallback if cleaned.is_empty() else cleaned


# --------------------------------------------------
# CONNECTION EVENTS
# --------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_online or not is_host:
		return

	if _client_id != 0 or match_started:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return

	_client_id = id
	opponent_connected.emit()


func _on_peer_disconnected(id: int) -> void:
	if not is_online or not is_host or id != _client_id:
		return

	_client_id = 0
	if match_started:
		opponent_left.emit()
	# Otherwise: guest dropped during the lobby, keep waiting for another.


func _on_connected_to_server() -> void:
	if not is_online:
		return

	opponent_connected.emit()
	_submit_name.rpc_id(1, _my_name)


func _on_connection_failed() -> void:
	if not is_online:
		return

	shutdown()
	connection_failed.emit("COULD NOT REACH HOST / CHECK IP, PORT AND FIREWALL")


func _on_server_disconnected() -> void:
	if not is_online:
		return

	if match_started:
		opponent_left.emit()  # board decides what to show; it should call shutdown()
	else:
		shutdown()
		connection_failed.emit("HOST CLOSED THE CONNECTION")
