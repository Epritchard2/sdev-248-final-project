extends Node
## LevelManager — drives the win/lose flow for a level (Godot 4.7).
## Counts enemies in the "enemies" group, updates the HUD kill counter, unlocks
## the exit door when every enemy is dead, and sends the player to the lose
## cutscene when they die. One instance per level scene.
##
## Works with every enemy type in the project: they all add themselves to the
## "enemies" group in _ready() and queue_free() on death, so the count tracks
## automatically with no per-enemy wiring.
##
## Save: uses the refill-on-clear model. When the level is cleared, it records
## the NEXT level (the door's next_scene) via the SaveManager, so a Continue
## resumes at the following level, always at full health.
# --- Scene links (set per level in the Inspector) ---
@export_file("*.tscn") var lose_scene: String = ""   # cutscene/scene loaded on player death
# --- Node links ---
@export var door_path: NodePath          # the level's Door node (optional; boss room may differ)
@export var hud_path: NodePath           # the level's HUD (optional)
# --- Tuning ---
@export var enemy_group: String = "enemies"
@export var player_group: String = "player"
# When on, the level is NOT cleared by killing enemies — something else (e.g. an
# NPC finishing its dialogue) unlocks the door. Used for talk-only rooms with no
# enemies, so the empty-level auto-clear doesn't open the door on its own.
@export var manual_clear: bool = false
# Small delay after the last enemy dies before unlocking, so the kill visibly
# lands before the door opens. Set to 0 for instant.
@export var unlock_delay: float = 0.4
var total_enemies: int = 0
var door: Node = null
var hud: Node = null
var level_cleared: bool = false
func _ready() -> void:
	# Wait a frame so all enemies and the player have registered their groups.
	await get_tree().process_frame
	# Record the level being played so the lose screen can restart it. Uses the
	# current scene's own file path, so no per-level Inspector field is needed.
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("set_playing_level"):
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path != "":
			sm.set_playing_level(scene.scene_file_path)
	door = get_node_or_null(door_path)
	hud = get_node_or_null(hud_path)
	# Count the enemies present at the start — that's the total to clear.
	var enemies_at_start := get_tree().get_nodes_in_group(enemy_group)
	total_enemies = enemies_at_start.size()
	# TEMP debug: list exactly what's in the group so an unexpected count can be
	# traced to the specific nodes. Remove once the count is confirmed correct.
	print("[LevelManager] total enemies at start = ", total_enemies)
	for e in enemies_at_start:
		print("   - ", e.name, " (", e.get_class(), ") path=", e.get_path())
	# Hook the player's death signal for the lose flow.
	var players := get_tree().get_nodes_in_group(player_group)
	if not players.is_empty():
		var player := players[0]
		if player.has_signal("died"):
			player.died.connect(_on_player_died)
	# Make sure the door starts locked.
	if door != null and door.has_method("lock"):
		door.lock()
	_update_hud()
	# Edge case: a level with no enemies is already clear — unless this is a
	# manual-clear room, where the door is opened by something else (an NPC).
	if total_enemies == 0 and not manual_clear:
		_clear_level()
func _process(_delta: float) -> void:
	if level_cleared:
		return
	# Track how many enemies remain. When the group empties, the level is clear.
	var remaining := get_tree().get_nodes_in_group(enemy_group).size()
	_update_hud_from_remaining(remaining)
	if remaining == 0 and total_enemies > 0 and not manual_clear:
		_clear_level()
func _update_hud() -> void:
	var remaining := get_tree().get_nodes_in_group(enemy_group).size()
	_update_hud_from_remaining(remaining)
func _update_hud_from_remaining(remaining: int) -> void:
	if hud != null and hud.has_method("set_kills"):
		var killed := total_enemies - remaining
		hud.set_kills(killed, total_enemies)
func _clear_level() -> void:
	if level_cleared:
		return
	level_cleared = true
	# Final HUD update so it reads killed == total.
	if hud != null and hud.has_method("set_kills"):
		hud.set_kills(total_enemies, total_enemies)
	# Auto-save on clear (refill-on-clear model): record the NEXT level so a
	# Continue resumes there at full health. The next level is the door's
	# next_scene. Skipped if there's no door or no next scene set (e.g. the boss
	# room door points at the win cutscene, which is fine to store as "next").
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and door != null and "next_scene" in door:
		var next_path: String = door.next_scene
		if next_path != "":
			sm.save_progress(next_path)
	# Brief beat, then unlock the exit.
	if unlock_delay > 0.0:
		await get_tree().create_timer(unlock_delay).timeout
	if door != null and door.has_method("unlock"):
		door.unlock()
func _on_player_died() -> void:
	# Load the lose cutscene/scene. Short delay lets the death animation start.
	await get_tree().create_timer(0.6).timeout
	if lose_scene != "":
		get_tree().change_scene_to_file(lose_scene)
