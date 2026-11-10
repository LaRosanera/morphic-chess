class_name GameConfig
extends RefCounted
## Reads the "chess_config" meta written by the setup screen
## (local or online) into plain fields.

var white_name := "White"
var black_name := "Black"
var online := false
var local_color := "white"  # the color this peer controls
var flipped := false  # draw the board from black's side
var game_seed := 0


static func from_tree(tree: SceneTree) -> GameConfig:
	var data: Dictionary = tree.get_meta("chess_config", {})
	var config := GameConfig.new()

	config.white_name = str(data.get("white_name", "White"))
	config.black_name = str(data.get("black_name", "Black"))
	config.online = str(data.get("mode", "local")) == "online"
	config.local_color = str(data.get("local_color", "white"))
	config.flipped = bool(data.get("board_flipped", false))

	if config.online:
		# Both peers must build the same game: always use the lobby's seed.
		config.game_seed = int(data.get("seed", 0))
	else:
		var seed_path := "res://daily_seed.json"

		if FileAccess.file_exists(seed_path):
			var seed_text := FileAccess.get_file_as_string(seed_path).strip_edges()

			if seed_text.is_valid_int():
				config.game_seed = int(seed_text)
			else:
				config.game_seed = int(data.get("seed", 0))
		else:
			config.game_seed = int(
				data.get("seed", tree.get_meta("game_seed", 0))
			)

	return config


func name_of(color: String) -> String:
	return white_name if color == "white" else black_name
