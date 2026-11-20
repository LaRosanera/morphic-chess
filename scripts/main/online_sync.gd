class_name OnlineSync
extends Node
## Moves are submitted through the Firebase room; the host validates and
## publishes each accepted move for both boards to apply in order.

signal move_approved(from: Vector2i, to: Vector2i, promo: String)
signal move_rejected

const REQUEST_TIMEOUT := 12.0
const MAX_REQUEST_ATTEMPTS := 3
const PROCESSING_RETRY_DELAY := 3.0

var _state: GameState
var _pending_request_id := ""
var _pending_elapsed := 0.0
var _pending_attempts := 0
var _pending_from := Vector2i.ZERO
var _pending_to := Vector2i.ZERO
var _pending_promo := ""
var _request_counter := 0
var _last_processed := {"host": "", "guest": ""}
var _processing_requests := {}
var _processing_retry_at := {"host": 0.0, "guest": 0.0}
var _failed := false


func setup(state: GameState) -> void:
	_state = state
	if not NetworkManager.room_updated.is_connected(_on_room_updated):
		NetworkManager.room_updated.connect(_on_room_updated)


## Called by the board when the local player makes a move.
func submit(from: Vector2i, to: Vector2i, promo: String) -> void:
	if _failed:
		push_warning("[SYNC] Submit blocked: sync failed")
		return

	if _pending_request_id != "":
		push_warning("[SYNC] Submit blocked: request still pending %s" % _pending_request_id)
		return

	_request_counter += 1
	var role := "host" if NetworkManager.is_host else "guest"
	_pending_request_id = "%s-%d-%d" % [
		role, Time.get_ticks_usec(), _request_counter
	]
	_pending_elapsed = 0.0
	_pending_attempts = 1
	_pending_from = from
	_pending_to = to
	_pending_promo = promo

	print("[SYNC] Submit move | From=", from, " | To=", to, " | ID=", _pending_request_id)
	_write_pending_request()


func _process(delta: float) -> void:
	if _pending_request_id == "" or _failed:
		return

	_pending_elapsed += delta
	if _pending_elapsed < REQUEST_TIMEOUT:
		return

	if _pending_attempts >= MAX_REQUEST_ATTEMPTS:
		_fail("Move request timed out after multiple attempts")
		return

	print("[SYNC] Request timeout; retrying | ID=", _pending_request_id)
	_pending_attempts += 1
	_write_pending_request()


func _write_pending_request() -> void:
	var role := "host" if NetworkManager.is_host else "guest"
	var request_id := _pending_request_id
	_pending_elapsed = 0.0
	NetworkManager.write(
		"rooms/%s/moves/requests/%s" % [NetworkManager.room_code, role],
		{
			"id": request_id,
			"from": [_pending_from.x, _pending_from.y],
			"to": [_pending_to.x, _pending_to.y],
			"promo": _pending_promo
		},
		_on_request_written.bind(request_id)
	)


func _on_request_written(
	ok: bool,
	_code: int,
	_data: Variant,
	request_id: String
) -> void:
	print("[SYNC] Request write | ID=", request_id, " | OK=", ok, " | HTTP=", _code)
	if not ok and request_id == _pending_request_id:
		push_warning("[SYNC] Request write failed; it will be retried")


func _on_room_updated(room: Dictionary) -> void:
	if _failed:
		return

	_process_approved(room)
	_process_rejection(room)
	if NetworkManager.is_host:
		_process_requests(room)


func _process_requests(room: Dictionary) -> void:
	var moves_value: Variant = room.get("moves", {})
	if not (moves_value is Dictionary):
		return
	var moves: Dictionary = moves_value
	var requests_value: Variant = moves.get("requests", {})
	if not (requests_value is Dictionary):
		return
	var requests: Dictionary = requests_value

	for role in ["host", "guest"]:
		var request_value: Variant = requests.get(role)
		if not (request_value is Dictionary):
			continue
		var request: Dictionary = request_value
		var request_id := str(request.get("id", ""))
		if request_id == "":
			continue

		if request_id == str(_last_processed[role]):
			continue

		if _request_has_response(room, role, request_id):
			_last_processed[role] = request_id
			_processing_requests.erase(role)
			_processing_retry_at[role] = 0.0
			continue

		if _now_seconds() < float(_processing_retry_at[role]):
			continue
		if str(_processing_requests.get(role, "")) != "":
			continue

		print("[SYNC] Processing request | Role=", role, " | ID=", request_id)
		_processing_requests[role] = request_id
		_validate_and_publish(role, request, request_id, room)


func _validate_and_publish(
	role: String,
	request: Dictionary,
	request_id: String,
	room: Dictionary
) -> void:
	print("[SYNC] Validating request | Role=", role, " | ID=", request_id)
	var from_value: Variant = request.get("from", [])
	var to_value: Variant = request.get("to", [])
	if not (from_value is Array) or not (to_value is Array):
		_reject_request(role, request_id)
		return

	var from_data: Array = from_value
	var to_data: Array = to_value
	if from_data.size() != 2 or to_data.size() != 2:
		_reject_request(role, request_id)
		return
	if not _is_integer(from_data[0]) or not _is_integer(from_data[1]) \
			or not _is_integer(to_data[0]) or not _is_integer(to_data[1]):
		_reject_request(role, request_id)
		return

	var host_color := "white" if bool(room.get("host_is_white", true)) else "black"
	var color := host_color if role == "host" else (
		"black" if host_color == "white" else "white"
	)
	var result := _state.check_move(
		color,
		Vector2i(int(from_data[0]), int(from_data[1])),
		Vector2i(int(to_data[0]), int(to_data[1])),
		str(request.get("promo", ""))
	)
	if not bool(result.get("ok", false)):
		_reject_request(role, request_id)
		return

	var move_index := _state.move_count + 1
	var move_from := Vector2i(int(from_data[0]), int(from_data[1]))
	var move_to := Vector2i(int(to_data[0]), int(to_data[1]))
	var final_promo := str(result.get("promo", ""))
	# Firebase serializes contiguous numeric child keys as an array.
	NetworkManager.write(
		"rooms/%s/moves/approved/move_%d" % [NetworkManager.room_code, move_index],
		{
			"from": from_data,
			"to": to_data,
			"promo": str(result.get("promo", "")),
			"request_role": role,
			"request_id": request_id
		},
		_on_approved_written.bind(
			role, request_id, move_index, move_from, move_to, final_promo
		)
	)


func _reject_request(role: String, request_id: String) -> void:
	print("[SYNC] Rejecting request | Role=", role, " | ID=", request_id)
	NetworkManager.write(
		"rooms/%s/moves/rejected/%s" % [NetworkManager.room_code, role],
		request_id,
		_on_rejection_written.bind(role, request_id)
	)


func _on_approved_written(
	ok: bool,
	_code: int,
	_data: Variant,
	role: String,
	request_id: String,
	move_index: int,
	move_from: Vector2i,
	move_to: Vector2i,
	promo: String
) -> void:
	print("[SYNC] Approved write | Move=", move_index, " | ID=", request_id, " | OK=", ok, " | HTTP=", _code)
	if str(_processing_requests.get(role, "")) == request_id:
		_processing_requests.erase(role)

	if not ok:
		push_warning("[SYNC] Approval write failed; host will retry processing")
		_processing_retry_at[role] = _now_seconds() + PROCESSING_RETRY_DELAY
		return

	_last_processed[role] = request_id
	_processing_retry_at[role] = 0.0
	if _local_role() == role and _pending_request_id == request_id:
		_clear_pending_request()

	if _state.move_count + 1 == move_index:
		move_approved.emit(move_from, move_to, promo)


func _on_rejection_written(
	ok: bool,
	_code: int,
	_data: Variant,
	role: String,
	request_id: String
) -> void:
	print("[SYNC] Rejection write | ID=", request_id, " | OK=", ok, " | HTTP=", _code)
	if str(_processing_requests.get(role, "")) == request_id:
		_processing_requests.erase(role)

	if not ok:
		push_warning("[SYNC] Rejection write failed; host will retry processing")
		_processing_retry_at[role] = _now_seconds() + PROCESSING_RETRY_DELAY
		return

	_last_processed[role] = request_id
	_processing_retry_at[role] = 0.0


func _process_approved(room: Dictionary) -> void:
	var moves_value: Variant = room.get("moves", {})
	if not (moves_value is Dictionary):
		return
	var approved_value: Variant = (moves_value as Dictionary).get("approved", {})
	if not (approved_value is Dictionary) and not (approved_value is Array):
		return

	while true:
		var move_index := _state.move_count + 1
		var entry_value: Variant = _approved_move(approved_value, move_index)
		if entry_value == null:
			return
		if not (entry_value is Dictionary):
			_fail("The room contains a malformed approved move")
			return
		var entry: Dictionary = entry_value
		var from_value: Variant = entry.get("from", [])
		var to_value: Variant = entry.get("to", [])
		if not (from_value is Array) or not (to_value is Array):
			_fail("The room contains a malformed approved move")
			return
		var from_data: Array = from_value
		var to_data: Array = to_value
		if from_data.size() != 2 or to_data.size() != 2 \
				or not _is_integer(from_data[0]) or not _is_integer(from_data[1]) \
				or not _is_integer(to_data[0]) or not _is_integer(to_data[1]):
			_fail("The room contains a malformed approved move")
			return

		var request_role := str(entry.get("request_role", ""))
		var request_id := str(entry.get("request_id", ""))
		if request_role in ["host", "guest"] and request_id != "":
			_last_processed[request_role] = request_id
			if str(_processing_requests.get(request_role, "")) == request_id:
				_processing_requests.erase(request_role)
			_processing_retry_at[request_role] = 0.0

		if request_role == ("host" if NetworkManager.is_host else "guest") \
				and request_id == _pending_request_id:
			_clear_pending_request()

		print("[SYNC] Applying approved move #", move_index,
			" | From=", from_data, " | To=", to_data)
		move_approved.emit(
			Vector2i(int(from_data[0]), int(from_data[1])),
			Vector2i(int(to_data[0]), int(to_data[1])),
			str(entry.get("promo", ""))
		)


func _approved_move(approved: Variant, index: int) -> Variant:
	# Read sparse arrays created by older numeric-key rooms as well.
	if approved is Array:
		var moves: Array = approved
		return moves[index] if index < moves.size() else null

	if approved is Dictionary:
		var moves: Dictionary = approved
		if moves.has("move_%d" % index):
			return moves["move_%d" % index]
		return moves.get(str(index))

	return null


func _request_has_response(room: Dictionary, role: String, request_id: String) -> bool:
	var moves_value: Variant = room.get("moves", {})
	if not (moves_value is Dictionary):
		return false

	var moves: Dictionary = moves_value
	var rejected_value: Variant = moves.get("rejected", {})
	if rejected_value is Dictionary \
			and str((rejected_value as Dictionary).get(role, "")) == request_id:
		return true

	var approved_value: Variant = moves.get("approved", {})
	var approved_entries: Array = []
	if approved_value is Array:
		approved_entries = approved_value
	elif approved_value is Dictionary:
		approved_entries = (approved_value as Dictionary).values()

	for index in approved_entries.size():
		var entry: Variant = approved_entries[index]
		if _is_matching_response(entry, role, request_id):
			return true

	return false


func _is_matching_response(entry: Variant, role: String, request_id: String) -> bool:
	if not (entry is Dictionary):
		return false
	var move: Dictionary = entry
	return str(move.get("request_role", "")) == role \
			and str(move.get("request_id", "")) == request_id


func _process_rejection(room: Dictionary) -> void:
	if _pending_request_id == "":
		return
	var moves_value: Variant = room.get("moves", {})
	if not (moves_value is Dictionary):
		return
	var rejected_value: Variant = (moves_value as Dictionary).get("rejected", {})
	if not (rejected_value is Dictionary):
		return

	var role := "host" if NetworkManager.is_host else "guest"
	var rejected: Dictionary = rejected_value
	if str(rejected.get(role, "")) == _pending_request_id:
		print("[SYNC] Move rejected | ID=", _pending_request_id)
		_last_processed[role] = _pending_request_id
		_clear_pending_request()
		move_rejected.emit()


func _clear_pending_request() -> void:
	_pending_request_id = ""
	_pending_elapsed = 0.0
	_pending_attempts = 0
	_pending_from = Vector2i.ZERO
	_pending_to = Vector2i.ZERO
	_pending_promo = ""


func _local_role() -> String:
	return "host" if NetworkManager.is_host else "guest"


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_equal_approx(float(value), round(float(value)))


func _fail(reason: String) -> void:
	_failed = true
	NetworkManager.report_connection_lost(reason)
