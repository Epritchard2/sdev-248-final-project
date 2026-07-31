extends Area2D
## Door — the level exit (Godot 4.7). Starts locked; the LevelManager unlocks it
## when every enemy is dead. Once unlocked, touching it loads the next scene.
##
## Set next_scene per level in the Inspector: the platformer levels point at the
## following level, and the boss room's door points at the win cutscene.
signal unlocked
signal used
# --- Scene to load when the player walks through the unlocked door ---
@export_file("*.tscn") var next_scene: String = ""
# --- Save progress when the player leaves through this door. Off by default, so
# enemy-clear levels (where the LevelManager already saves on clear) aren't
# double-saving. Turn on for rooms that clear without the LevelManager's win
# path, like a talk-only NPC room. ---
@export var save_on_use: bool = false
# --- Optional visuals (assign if the door has an AnimatedSprite2D) ---
@export var locked_anim: String = "locked"
@export var unlocked_anim: String = "unlocked"
@export var use_animations: bool = false
# --- Optional lock collision: a solid body that physically blocks the exit while
# locked. Assign a StaticBody2D (or CollisionShape2D) to disable it on unlock.
@export var block_path: NodePath
@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
var is_unlocked: bool = false
var block: Node = null
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	block = get_node_or_null(block_path)
	lock()
func lock() -> void:
	is_unlocked = false
	if use_animations and sprite != null:
		sprite.play(locked_anim)
	# Re-enable the physical block (a CollisionShape2D) so the player can't leave.
	_set_block_disabled(false)
func unlock() -> void:
	if is_unlocked:
		return
	is_unlocked = true
	if use_animations and sprite != null:
		sprite.play(unlocked_anim)
	# Drop the physical block so the player can pass through.
	_set_block_disabled(true)
	unlocked.emit()
func _set_block_disabled(disabled: bool) -> void:
	# The block is expected to be a CollisionShape2D (child of a StaticBody2D that
	# walls off the exit). Toggling its disabled flag opens/closes the way.
	if block == null:
		return
	if block is CollisionShape2D:
		block.set_deferred("disabled", disabled)
func _on_body_entered(body: Node) -> void:
	# Only the player triggers the exit, and only once unlocked.
	if not is_unlocked:
		return
	if not body.is_in_group("player"):
		return
	used.emit()
	# Save the destination as the resume point before loading it, for rooms that
	# don't go through the LevelManager's clear-and-save path.
	if save_on_use and next_scene != "":
		var sm := get_node_or_null("/root/SaveManager")
		if sm != null and sm.has_method("save_progress"):
			sm.save_progress(next_scene)
	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)
