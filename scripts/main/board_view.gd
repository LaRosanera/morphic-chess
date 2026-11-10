class_name BoardView
extends RefCounted
## Everything visual about the board: tiles, where cells appear on screen,
## highlight markers, piece animation, and the 180-degree flip for black.
##
## Game logic always uses "white's view" cells. Only drawing and mouse input
## go through vis(), which rotates the board when flipped.

var tiles: TileMapLayer
var pieces: Node2D
var highlights: Node2D
var flipped := false

var _select_marker: ColorRect
var _move_marker: ColorRect
var _capture_marker: ColorRect

func _init(
	tile_layer: TileMapLayer,
	piece_root: Node2D,
	highlight_root: Node2D,
	is_flipped: bool
) -> void:
	tiles = tile_layer
	pieces = piece_root
	highlights = highlight_root
	flipped = is_flipped

	_select_marker = highlights.get_node("SelectMarker") as ColorRect
	_move_marker = highlights.get_node("MoveMarker") as ColorRect
	_capture_marker = highlights.get_node("CaptureMarker") as ColorRect


func build_tiles() -> void:
	for y in range(MoveRule.SIZE):
		for x in range(MoveRule.SIZE):
			tiles.set_cell(
				Vector2i(x, y),
				0,
				Vector2i((x + y) % 2, 0)
			)


# --------------------------------------------------
# COORDINATES
# --------------------------------------------------

func vis(cell: Vector2i) -> Vector2i:
	if not flipped:
		return cell

	return Vector2i(MoveRule.SIZE - 1 - cell.x, MoveRule.SIZE - 1 - cell.y)


## Where a logical cell is drawn, in the Pieces node's local space.
func cell_pos(cell: Vector2i) -> Vector2:
	return pieces.to_local(
		tiles.to_global(tiles.map_to_local(vis(cell)))
	)


## Logical cell under the mouse. vis() is its own inverse for a 180 flip.
func mouse_cell() -> Vector2i:
	return vis(tiles.local_to_map(tiles.get_local_mouse_position()))


# --------------------------------------------------
# MARKERS AND ANIMATION
# --------------------------------------------------

func show_select(cell: Vector2i) -> void:
	_mark(_select_marker, cell)


func show_move(cell: Vector2i) -> void:
	_mark(_move_marker, cell)


func show_capture(cell: Vector2i) -> void:
	_mark(_capture_marker, cell)


func clear_marks() -> void:
	tiles.get_tree().call_group("markers", "queue_free")


func slide(p: AnimatedSprite2D, cell: Vector2i) -> void:
	pieces.create_tween().tween_property(p, "position", cell_pos(cell), 0.15)


func _mark(template: ColorRect, cell: Vector2i) -> void:
	var marker := template.duplicate() as ColorRect

	highlights.add_child(marker)
	marker.position = highlights.to_local(
		tiles.to_global(tiles.map_to_local(vis(cell)))
	) - marker.size / 2.0

	marker.add_to_group("markers")
	marker.show()
