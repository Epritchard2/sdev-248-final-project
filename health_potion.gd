extends Area2D
## HealthPotion — a walk-through pickup that restores player health (Godot 4.7).
## Heals a set amount on contact. If the player is already at full health it is
## left in place, so it can be saved and collected later when it would help.

# --- Animation names (match the SpriteFrames exactly, if one is present) ---
const ANIM_IDLE    := "idle"       # resting bob/shimmer (looping)
const ANIM_CONSUME := "consume"    # optional pop on pickup (one-shot, Loop OFF)

@export var heal_amount: int = 2       # how much health a pickup restores
@export var use_consume_anim: bool = false  # play ANIM_CONSUME before vanishing
@export var heal_sfx_path: NodePath    # optional AudioStreamPlayer to play on pickup

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")

var consumed: bool = false     # once used, ignore further overlaps while it frees


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if sprite != null:
		sprite.play(ANIM_IDLE)


func _on_body_entered(body: Node) -> void:
	if consumed:
		return
	# Player only: skip anything that isn't in the player group.
	if not body.is_in_group("player"):
		return
	if not body.has_method("heal"):
		return
	# heal() returns true only if it actually restored health. When the player is
	# already full it returns false and the potion stays untouched.
	var healed: bool = body.heal(heal_amount)
	if healed:
		_consume()


func _consume() -> void:
	consumed = true
	# Stop further pickups immediately while the pop plays / it frees.
	if shape != null:
		shape.set_deferred("disabled", true)
	var sfx := get_node_or_null(heal_sfx_path)
	if sfx != null and sfx is AudioStreamPlayer:
		sfx.play()
	if use_consume_anim and sprite != null:
		sprite.play(ANIM_CONSUME)
		await sprite.animation_finished
	queue_free()
