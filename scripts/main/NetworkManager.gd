extends Node
## Autoload: register as "NetworkManager" in Project Settings > Globals.
##
## Online play through Firebase Realtime Database (REST, no ENet, no ports).
##
## Flow:
##   host_game()  -> creates rooms/CODE, emits room_created(code), waits
##   join_game()  -> reads the room, claims the guest slot
##   both sides   -> build the same match config from the room data and emit
##                   match_ready(config)
##
## While a room is active this node polls it once per second and publishes
## the latest snapshot as `room` / room_updated. OnlineSync reads moves,
## ready flags and timeouts from that snapshot.

signal opponent_connected
signal match_ready(config: Dictionary)
signal connection_failed(reason: String)
signal opponent_left
signal room_created(code: String)
signal room_updated(room: Dictionary)

const DB_URL := "https://morphicchess-default-rtdb.firebaseio.com"  # no trailing slash
const MAX_NAME_LENGTH := 24
const CODE_LENGTH := 6
## No 0/O or 1/I, so codes are easy to read out loud.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

const POLL_INTERVAL := 1.0
const HEARTBEAT_INTERVAL := 4.0
## No sign of life from the opponent (or from Firebase) for this long = gone.
const STALE_SECONDS := 25.0
const WRITE_RETRIES := 5
const MAX_CREATE_ATTEMPTS := 6

var is_online := false
var is_host := false
var match_started := false
var room_code := ""
## Latest snapshot of rooms/CODE (empty until the first poll).
var room: Dictionary = {}

var _role := "host"  # "host" or "guest"
var _my_name := ""
var _base_config: Dictionary = {}
var _live := false  # polling is active
var _session := 0  # bumped on shutdown so old retries can tell they are stale

var _poll_http: HTTPRequest
var _write_http: HTTPRequest
var _polling := false
var _poll_timer := 0.0
var _heartbeat_timer := 0.0

var _queue: Array[Dictionary] = []
var _writing := false

var _opp_presence: Variant = null
var _opp_presence_at := 0.0
var _failing_since := -1.0
var _opponent_reported := false
var _create_attempts := 0


func _ready() -> void:
	_poll_http = HTTPRequest.new()
	_poll_http.timeout = 10.0
	add_child(_poll_http)
	_poll_http.request_completed.connect(_on_poll_done)

	_write_http = HTTPRequest.new()
	_write_http.timeout = 10.0
	add_child(_write_http)
	_write_http.request_completed.connect(_on_write_done)


func _process(delta: float) -> void:
	if not is_online or not _live:
		return

	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL and not _polling:
		_poll()

	if match_started:
		_heartbeat_timer += delta
		if _heartbeat_timer >= HEARTBEAT_INTERVAL:
			_send_heartbeat()


# --------------------------------------------------
# PUBLIC API
# --------------------------------------------------

## Creates a room. Emits room_created(code) when it exists, then
## opponent_connected + match_ready when someone joins.
func host_game(player_name: String, base_config: Dictionary) -> void:
	shutdown()

	is_online = true
	is_host = true
	_role = "host"
	_my_name = _clean_name(player_name, "Host")

	# JSON numbers come back as floats, which can't hold a 19-digit seed.
	_base_config = base_config.duplicate(true)
	_base_config["seed"] = str(int(_base_config.get("seed", 0)))

	_create_attempts = 0
	_try_create_room()


func join_game(code: String, player_name: String) -> void:
	shutdown()

	var clean := code.strip_edges().to_upper()
	if not _valid_code(clean):
		connection_failed.emit("INVALID ROOM CODE / IT HAS %d LETTERS AND NUMBERS" % CODE_LENGTH)
		return

	is_online = true
	is_host = false
	_role = "guest"
	_my_name = _clean_name(player_name, "Guest")
	room_code = clean

	read_once("rooms/%s" % room_code, _on_join_room_fetched)


func shutdown() -> void:
	if is_online and room_code != "":
		_say_goodbye()

	_session += 1
	_live = false
	_poll_http.cancel_request()
	_write_http.cancel_request()
	_queue.clear()
	_writing = false
	_polling = false

	is_online = false
	is_host = false
	match_started = false
	room_code = ""
	room = {}
	_opponent_reported = false
	_opp_presence = null
	_failing_since = -1.0


## Queued write (one at a time, in order, with retries on network errors).
## callback(ok: bool, http_code: int, data: Variant)
func write(
	path: String,
	data: Variant,
	callback: Callable = Callable(),
	retries: int = WRITE_RETRIES,
	if_empty: bool = false
) -> void:
	_enqueue(HTTPClient.METHOD_PUT, path, JSON.stringify(data), callback, retries, if_empty)


func read_once(path: String, callback: Callable) -> void:
	_enqueue(HTTPClient.METHOD_GET, path, "", callback, WRITE_RETRIES)


## Used by OnlineSync when something is unrecoverable (a move could not be
## saved, or the opponent sent an illegal move).
func report_connection_lost(reason: String = "") -> void:
	if reason != "":
		push_warning("NetworkManager: " + reason)
	_report_opponent_left()


# --------------------------------------------------
# ROOM CREATE / JOIN
# --------------------------------------------------

func _try_create_room() -> void:
	if _create_attempts >= MAX_CREATE_ATTEMPTS:
		_fail("COULD NOT CREATE A ROOM / CHECK THE DATABASE RULES")
		return

	_create_attempts += 1
	room_code = _random_code()

	write("rooms/%s" % room_code, {
		"host_name": _my_name,
		"host_is_white": randi() % 2 == 0,
		"config": _base_config,
		"created": {".sv": "timestamp"},
	}, _on_room_created, 2, true)


func _on_room_created(ok: bool, code: int, _data: Variant) -> void:
	if not ok:
		if code == 412:
			# This code was claimed by another host; try a different one.
			_try_create_room()
		else:
			_fail("FIREBASE ROOM CREATE FAILED / HTTP %d" % code)
		return

	_start_polling()
	room_created.emit(room_code)


func _on_join_room_fetched(ok: bool, code: int, data: Variant) -> void:
	if not ok:
		if code == 401:
			_fail("DATABASE RULES BLOCKED THE REQUEST")
		else:
			_fail("FIREBASE ROOM LOOKUP FAILED / HTTP %d" % code)
		return

	if not (data is Dictionary):
		_fail("ROOM %s NOT FOUND / CHECK THE CODE" % room_code)
		return

	var found: Dictionary = data

	if found.has("guest_name"):
		_fail("THAT ROOM IS ALREADY FULL")
		return

	var left: Variant = found.get("left")
	if left is Dictionary and not (left as Dictionary).is_empty():
		_fail("THAT GAME HAS ALREADY ENDED")
		return

	room = found
	write("rooms/%s/guest_name" % room_code, _my_name, _on_guest_written, 2, true)


func _on_guest_written(ok: bool, code: int, _data: Variant) -> void:
	if not ok:
		# The rules only let the first guest in.
		_fail(
			"THAT ROOM IS ALREADY FULL"
			if code == 412
			else "FIREBASE ROOM JOIN FAILED / HTTP %d" % code
		)
		return

	room["guest_name"] = _my_name
	_start_polling()
	opponent_connected.emit()
	_begin_match()


func _begin_match() -> void:
	if match_started:
		return

	match_started = true
	_opponent_reported = false
	_opp_presence = null
	_opp_presence_at = _now()
	_send_heartbeat()
	match_ready.emit(_make_config())


## Both players build the same config from the room, so nothing has to be
## sent back and forth: the host picked the colors when it made the room.
func _make_config() -> Dictionary:
	var config: Dictionary = {}
	var stored: Variant = room.get("config", {})
	if stored is Dictionary:
		config = (stored as Dictionary).duplicate(true)

	var host_name := str(room.get("host_name", "Host"))
	var guest_name := str(room.get("guest_name", "Guest"))
	var host_is_white := bool(room.get("host_is_white", true))
	var local_is_white := (host_is_white == is_host)

	# Firebase returns every number as a float; put the ints back.
	config["seed"] = str(config.get("seed", "0")).to_int()
	for key in ["time_control_index", "initial_time_seconds", "increment_seconds"]:
		if config.has(key):
			config[key] = int(config[key])

	config["mode"] = "online"
	config["is_host"] = is_host
	config["room_code"] = room_code
	config["white_name"] = host_name if host_is_white else guest_name
	config["black_name"] = guest_name if host_is_white else host_name
	config["local_color"] = "white" if local_is_white else "black"
	config["local_name"] = _my_name
	config["board_flipped"] = not local_is_white  # your side is always at the bottom
	return config


# --------------------------------------------------
# POLLING
# --------------------------------------------------

func _start_polling() -> void:
	_live = true
	_poll_timer = POLL_INTERVAL  # poll right away
	_heartbeat_timer = 0.0
	_failing_since = -1.0


func _poll() -> void:
	_polling = true
	_poll_timer = 0.0

	var err := _poll_http.request(_url("rooms/%s" % room_code))
	if err != OK:
		_polling = false
		_note_failure()


func _on_poll_done(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_polling = false

	if not is_online or not _live:
		return

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_note_failure()
		return

	_failing_since = -1.0

	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		# "null": the room was deleted (the opponent left and cleaned up).
		if match_started:
			_report_opponent_left()
		return

	room = data

	if is_host and not match_started and room.has("guest_name"):
		opponent_connected.emit()
		_begin_match()

	# Subscribers apply moves first; only then do we look at "left", so a
	# final move followed by an instant Leave still counts as a result.
	room_updated.emit(room)
	_check_presence()


func _note_failure() -> void:
	var now := _now()

	if _failing_since < 0.0:
		_failing_since = now
		return

	if now - _failing_since > STALE_SECONDS:
		_failing_since = now
		if match_started:
			_report_opponent_left()
		else:
			_fail("LOST CONNECTION")


# --------------------------------------------------
# PRESENCE
# --------------------------------------------------

func _send_heartbeat() -> void:
	_heartbeat_timer = 0.0

	# Don't pile heartbeats up behind a slow connection.
	if _queue.size() > 2:
		return

	write(
		"rooms/%s/presence/%s" % [room_code, _role],
		{".sv": "timestamp"},
		Callable(),
		1
	)


func _check_presence() -> void:
	if not match_started or _opponent_reported:
		return

	var opponent := "guest" if is_host else "host"

	if _sub("left").has(opponent):
		_report_opponent_left()
		return

	# Compare the opponent's heartbeat with the previous one using OUR clock,
	# so differences between the two computers' clocks don't matter.
	var value: Variant = _sub("presence").get(opponent)
	var now := _now()

	if value != _opp_presence:
		_opp_presence = value
		_opp_presence_at = now
	elif now - _opp_presence_at > STALE_SECONDS:
		_report_opponent_left()


func _report_opponent_left() -> void:
	if _opponent_reported:
		return

	_opponent_reported = true
	opponent_left.emit()


func _say_goodbye() -> void:
	var other := "host" if _role == "guest" else "guest"

	if match_started:
		if _sub("left").has(other):
			# Both sides are gone: remove the room.
			_fire(HTTPClient.METHOD_DELETE, "rooms/%s" % room_code)
		else:
			_fire(HTTPClient.METHOD_PUT, "rooms/%s/left/%s" % [room_code, _role], "true")
	elif is_host and _live:
		# Host cancelled while waiting in the lobby.
		_fire(HTTPClient.METHOD_DELETE, "rooms/%s" % room_code)


# --------------------------------------------------
# REQUEST QUEUE
# --------------------------------------------------

func _enqueue(
	method: int,
	path: String,
	body: String,
	callback: Callable,
	retries: int,
	if_empty: bool = false
) -> void:
	_queue.append({
		"method": method,
		"path": path,
		"body": body,
		"cb": callback,
		"retries": retries,
		"if_empty": if_empty,
	})
	_pump()


func _pump() -> void:
	if _writing or _queue.is_empty():
		return

	_writing = true
	_send_head()


func _send_head() -> void:
	var item: Dictionary = _queue[0]
	var method: int = item["method"]
	print(
		"[NET] Sending | Method=", method,
		" | Path=", _diagnostic_path(str(item["path"])),
		" | Retries left=", item["retries"]
	)
	var conditional := bool(item.get("if_empty", false))
	var url := _url(
		item["path"],
		method != HTTPClient.METHOD_GET and not conditional
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if bool(item.get("if_empty", false)):
		headers.append("If-Match: null_etag")

	var err := _write_http.request(url, headers, method, item["body"])
	if err != OK:
		_on_write_done(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _on_write_done(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if _queue.is_empty():
		_writing = false
		return

	var item: Dictionary = _queue[0]
	var reached := result == HTTPRequest.RESULT_SUCCESS
	var ok := reached and code >= 200 and code < 300
	var refused := reached and code >= 400 and code < 500  # retrying won't help
	print(
		"[NET] Write response | Result=", result,
		" | HTTP=", code,
		" | OK=", ok,
		" | Path=", _diagnostic_path(str(item["path"]))
	)

	if not ok and not refused and int(item["retries"]) > 0:
		push_warning(
			"[NET] Retrying request | Path=%s | HTTP=%d | Retries remaining=%d"
			% [_diagnostic_path(str(item["path"])), code, int(item["retries"])]
		)
		item["retries"] = int(item["retries"]) - 1
		var session := _session
		await get_tree().create_timer(1.0).timeout

		if session != _session or _queue.is_empty():
			_writing = false
			return

		_send_head()
		return

	var expected_conflict := code == 412 and bool(item.get("if_empty", false))
	if not ok and not expected_conflict:
		push_error(
			"[NET] Write failed permanently | Path=%s | HTTP=%d | Result=%d"
			% [_diagnostic_path(str(item["path"])), code, result]
		)

	_queue.pop_front()
	_writing = false

	var parsed: Variant = null
	if ok and body.size() > 0:
		parsed = JSON.parse_string(body.get_string_from_utf8())

	var callback: Callable = item["cb"]
	if callback.is_valid():
		callback.call(ok, code, parsed)

	_pump()


## One-off request that outlives shutdown() (used for "I left" / cleanup).
func _fire(method: int, path: String, body: String = "") -> void:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(
		func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
			http.queue_free()
	)

	var err := http.request(
		_url(path, true),
		PackedStringArray(["Content-Type: application/json"]),
		method,
		body
	)
	if err != OK:
		http.queue_free()


# --------------------------------------------------
# HELPERS
# --------------------------------------------------

func _fail(reason: String) -> void:
	shutdown()
	connection_failed.emit(reason)


## Every REST path needs ".json" on the end. print=silent makes writes
## return an empty 204 instead of echoing the data back.
func _url(path: String, silent: bool = false) -> String:
	return "%s/%s.json%s" % [DB_URL, path, "?print=silent" if silent else ""]


func _diagnostic_path(path: String) -> String:
	return path.replace(room_code, "<room>") if room_code != "" else path


func _sub(key: String) -> Dictionary:
	var value: Variant = room.get(key, {})
	return value as Dictionary if value is Dictionary else {}


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _random_code() -> String:
	var code := ""
	for i in CODE_LENGTH:
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code


func _valid_code(code: String) -> bool:
	if code.length() != CODE_LENGTH:
		return false

	for ch in code:
		if not CODE_ALPHABET.contains(ch):
			return false

	return true


func _clean_name(value: String, fallback: String) -> String:
	var cleaned := value.strip_edges().substr(0, MAX_NAME_LENGTH)
	return fallback if cleaned.is_empty() else cleaned
