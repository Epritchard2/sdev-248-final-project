extends Area2D
## NPC — a survivor that talks to the player through a DialogueBox (Godot 4.7).
## Starts the conversation when the player comes within talk_range (no contact
## needed), faces the player as it begins, and can unlock the level's door when
## the conversation ends so a talk-only room advances once the talk is done.

signal talked_through    # emitted when the conversation finishes

# --- What the NPC says. Each entry is one line, shown in order. ---
@export var speaker_name: String = "Survivor"
@export_multiline var lines: PackedStringArray = []

# --- Trigger ---
@export var talk_range: float = 120.0     # player within this distance starts the talk
@export var interact_action: String = "jump"   # press to start when in range (if not auto)
@export var auto_start: bool = true       # start on approach instead of on a key

# --- Links ---
@export var dialogue_box_path: NodePath   # the scene's DialogueBox
@export var door_path: NodePath           # optional: unlocked when the talk ends

# --- Optional prompt shown while in range (e.g. a "!" or button hint) ---
@export var prompt_path: NodePath

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var dialogue_box: Node = get_node_or_null(dialogue_box_path)
@onready var door: Node = get_node_or_null(door_path)
@onready var prompt: Node = get_node_or_null(prompt_path)

var player: Node2D = null     # cached once found, for distance checks
var in_range: bool = false
var talking: bool = false
var done: bool = false        # only run the conversation once


func _ready() -> void:
	if sprite != null:
		sprite.play("idle")
	if prompt != null:
		prompt.visible = false


func _process(_delta: float) -> void:
	if done or talking:
		return
	# Find the player once, then track distance to it each frame.
	if player == null or not is_instance_valid(player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		player = players[0]

	var dist := global_position.distance_to(player.global_position)
	var was_in_range := in_range
	in_range = dist <= talk_range

	# Show/hide the prompt as the player enters/leaves range.
	if prompt != null:
		prompt.visible = in_range

	# Auto-start the moment the player comes within range.
	if in_range and auto_start:
		_begin()


func _unhandled_input(event: InputEvent) -> void:
	# Key-press trigger, used only when auto_start is off.
	if auto_start or done or talking:
		return
	if in_range and event.is_action_pressed(interact_action):
		_begin()
		get_viewport().set_input_as_handled()


func _begin() -> void:
	if dialogue_box == null or not dialogue_box.has_method("start"):
		return
	talking = true
	if prompt != null:
		prompt.visible = false
	# Face the player as the conversation starts.
	_face_player()
	# Build the { name, text } line list from the exported strings.
	var built: Array = []
	for l in lines:
		built.append({ "name": speaker_name, "text": l })
	if not dialogue_box.finished.is_connected(_on_dialogue_finished):
		dialogue_box.finished.connect(_on_dialogue_finished)
	dialogue_box.start(built)


func _face_player() -> void:
	# Flip the sprite so the NPC looks toward the player. Assumes the art faces
	# right by default; flip_h when the player is to the left.
	if sprite == null or player == null:
		return
	sprite.flip_h = player.global_position.x < global_position.x


func _on_dialogue_finished() -> void:
	talking = false
	done = true
	if prompt != null:
		prompt.visible = false
	# Unlock the door so the player can leave once they've heard it.
	if door != null and door.has_method("unlock"):
		door.unlock()
	talked_through.emit()
