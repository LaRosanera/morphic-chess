class_name FirebaseSync
extends Node

const HOST := "https://morphicchess-default-rtdb.firebaseio.com"  # no trailing slash

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)


## Writes `data` to a path, e.g. put("games/ABCD/moves/0", {...}).
func put(path: String, data: Dictionary) -> void:
	var url := "%s/%s.json" % [HOST, path]
	_http.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_PUT,
		JSON.stringify(data)
	)
