class_name OnlineSync
extends Node
## The only place the chess board touches RPCs. Added as a child of the board
## (named "OnlineSync") on both peers, so the RPC path matches.
##
##   submit()  -> client sends the request to the host (host handles it directly)
##   host validates with GameState.check_move()
##   host broadcasts -> every peer emits move_approved
##   or the requester gets move_rejected

signal move_approved(from: Vector2i, to: Vector2i, promo: String)
signal move_rejected

var _state: GameState
var _local_color := "white"  # on the host this is the host's color


func setup(state: GameState, local_color: String) -> void:
	_state = state
	_local_color = local_color


## Called by the board when the local player makes a move.
func submit(from: Vector2i, to: Vector2i, promo: String) -> void:
	if multiplayer.is_server():
		_handle(1, from, to, promo)
	else:
		_request_move.rpc_id(1, from, to, promo)


## Client -> host.
@rpc("any_peer", "reliable")
func _request_move(from: Vector2i, to: Vector2i, promo: String) -> void:
	if not multiplayer.is_server():
		return

	_handle(multiplayer.get_remote_sender_id(), from, to, promo)


## Runs on the host only (for its own moves and the guest's requests).
func _handle(sender: int, from: Vector2i, to: Vector2i, promo: String) -> void:
	var result := _state.check_move(_color_of_peer(sender), from, to, promo)

	if not result["ok"]:
		if sender == 1:
			move_rejected.emit()
		else:
			_reject.rpc_id(sender)
		return

	# call_local: the host applies it too, so everyone runs the same code.
	_approve.rpc(from, to, result["promo"])


## Host -> everyone (including itself).
@rpc("authority", "call_local", "reliable")
func _approve(from: Vector2i, to: Vector2i, promo: String) -> void:
	move_approved.emit(from, to, promo)


## Host -> the guest whose request was refused.
@rpc("authority", "reliable")
func _reject() -> void:
	move_rejected.emit()


func _color_of_peer(peer_id: int) -> String:
	if peer_id == 1:
		return _local_color

	return "black" if _local_color == "white" else "white"
