extends Node
## CameraZone — sets the player camera's bounds for the level it lives in (Godot 4.7).
## Drop one instance into each level scene and set the four limit values plus the
## zoom in the Inspector. On load it finds the player's Camera2D (via the "player"
## group) and applies these settings, so each level defines its own camera bounds.
##
## Scrolling levels: set the limits to the level's pixel bounds so the camera
## follows the player but never scrolls past the tiles.
## Boss room: set the limits a little wider than the arena so the camera can pan
## slightly with the player rather than sitting perfectly still.

# --- Camera bounds (world pixel coordinates) ---
@export var limit_left: int = 0
@export var limit_top: int = -2000        # generous headroom by default
@export var limit_right: int = 2000
@export var limit_bottom: int = 1000

# --- Optional per-level camera tuning (applied only if override is enabled) ---
@export var override_zoom: bool = false
@export var zoom: Vector2 = Vector2(3, 3)
@export var override_smoothing: bool = false
@export var smoothing_speed: float = 5.0

# If the player might not exist yet on _ready (e.g. spawned later), retry briefly.
@export var retry_until_found: bool = true


func _ready() -> void:
	# Wait a frame so the player and its camera are in the tree, then apply.
	await get_tree().process_frame
	_apply()


func _apply() -> void:
	var cam := _find_player_camera()
	if cam == null:
		if retry_until_found:
			# Player/camera not ready yet — try again next frame.
			await get_tree().process_frame
			_apply()
		return

	cam.limit_left = limit_left
	cam.limit_top = limit_top
	cam.limit_right = limit_right
	cam.limit_bottom = limit_bottom

	if override_zoom:
		cam.zoom = zoom
	if override_smoothing:
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = smoothing_speed


func _find_player_camera() -> Camera2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var player := players[0] as Node
	return _first_camera_under(player)


func _first_camera_under(node: Node) -> Camera2D:
	# Recursively search node's descendants for the first Camera2D.
	for child in node.get_children():
		if child is Camera2D:
			return child
		var deeper := _first_camera_under(child)
		if deeper != null:
			return deeper
	return null
