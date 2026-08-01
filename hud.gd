extends CanvasLayer
## HUD — health bar + kill counter (Godot 4.7)
## Stays fixed on screen (CanvasLayer) over the scrolling level.
## Drives values only; style the ProgressBar / Label with your own UI assets.

@onready var health_bar: TextureProgressBar = $Control/HealthBar
@onready var kill_label: Label = $Control/KillLabel


func _ready() -> void:
	# Wait one full frame so every node (incl. the player) is in the tree and
	# registered in its groups before we search.
	await get_tree().process_frame
	_connect_to_player()


func _connect_to_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		push_warning("HUD: no node in 'player' group found.")
		return
	var p = players[0]
	if p.has_signal("health_changed"):
		if not p.health_changed.is_connected(_on_health_changed):
			p.health_changed.connect(_on_health_changed)
		# Initialize the bar from current values.
		if "health" in p and "max_health" in p:
			_on_health_changed(p.health, p.max_health)


# --- Called by the player's health_changed signal ---
func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func set_kills(killed: int, total: int) -> void:
	var remaining := total - killed
	if remaining <= 0:
		kill_label.text = "Level Clear!"
	else:
		kill_label.text = "Enemies Remaining: %d / %d" % [remaining, total]
