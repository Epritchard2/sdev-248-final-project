extends Area2D
## Orb projectile — slow homing magic bolt (Godot 4.7)
## Fired by the skeleton mage. Curves toward the player, damages on contact,
## then plays a fizzle animation before disappearing.

# --- Animation names (match the SpriteFrames exactly) ---
const ANIM_FLY    := "fly"      # traveling animation (looping) — rename to match yours
const ANIM_FIZZLE := "fizzle"   # dissipate animation (one-shot) — rename to match yours

@export var speed: float = 90.0          # slow — player can outmaneuver it
@export var turn_rate: float = 2.5       # how sharply it homes (radians/sec); lower = lazier
@export var damage: int = 2
@export var knockback: float = 180.0
@export var lifetime: float = 6.0        # despawn after this long if it never hits

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shape: CollisionShape2D = $CollisionShape2D

var velocity: Vector2 = Vector2.ZERO
var target: Node2D = null
var life_timer: float = 0.0
var fizzling: bool = false      # once true, the orb is dying — stop moving/hitting


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		target = players[0]
	sprite.play(ANIM_FLY)


func launch(dir: Vector2) -> void:
	velocity = dir.normalized() * speed


func _physics_process(delta: float) -> void:
	if fizzling:
		return   # dying — no more movement or homing

	life_timer += delta
	if life_timer >= lifetime:
		_fizzle()
		return

	# Homing: gently steer velocity toward the player's current position.
	if target != null and is_instance_valid(target):
		var desired := (target.global_position - global_position).normalized() * speed
		var new_angle := rotate_toward(velocity.angle(), desired.angle(), turn_rate * delta)
		velocity = Vector2.RIGHT.rotated(new_angle) * speed

	global_position += velocity * delta
	rotation = velocity.angle()


func _on_body_entered(body: Node) -> void:
	if fizzling:
		return
	if body.has_method("take_hit"):
		var dir := velocity.normalized()
		body.take_hit(damage, dir * knockback)
		_fizzle()
	elif body is StaticBody2D:
		_fizzle()   # hit a wall/floor — fizzle out


func _fizzle() -> void:
	# Play the fizzle animation, stop interacting, remove when it finishes.
	fizzling = true
	velocity = Vector2.ZERO
	rotation = 0.0
	shape.set_deferred("disabled", true)   # no more collisions while fizzling
	sprite.play(ANIM_FIZZLE)
	await sprite.animation_finished
	queue_free()
