extends Area2D
## Boss projectile — meteor drop (Godot 4.7)
## Spawned during the boss atk3 loop, high in the sky directly above the player.
## Hangs in place for a short beat, then falls straight down. Damages on contact,
## plays a fizzle animation on impact/timeout before disappearing.

# --- Animation names (match the SpriteFrames exactly) ---
const ANIM_HOVER   := "hover"     # spikes hover in the sky before dropping (looping)
const ANIM_FALLING := "falling"   # descending animation (looping)
const ANIM_FIZZLE  := "fizzle"    # impact animation (one-shot, Loop OFF)

@export var spawn_height: float = 260.0  # how far above the target it appears
@export var hang_time: float = 0.5       # seconds it hovers before dropping
@export var fall_gravity: float = 1100.0 # Newton's 2nd law: constant downward accel
@export var max_fall_speed: float = 700.0
@export var damage: int = 2
@export var knockback: float = 200.0
@export var lifetime: float = 4.0        # despawn after this long if it never lands
@export_flags_2d_physics var world_mask_bit: int = 4  # floor layer (bit 3 = value 4)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shape: CollisionShape2D = $CollisionShape2D

var velocity: Vector2 = Vector2.ZERO
var life_timer: float = 0.0
var hang_timer: float = 0.0
var hanging: bool = true         # true while hovering before the drop
var fizzling: bool = false       # once true, the projectile is dying


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	hang_timer = hang_time
	# Start in the hover animation while it hangs; switches to falling on drop.
	sprite.play(ANIM_HOVER)


func spawn_above(target_pos: Vector2) -> void:
	# Appear high in the sky directly over the target's current position. The
	# X is locked here; it falls straight down from this column.
	global_position = Vector2(target_pos.x, target_pos.y - spawn_height)


func _physics_process(delta: float) -> void:
	if fizzling:
		return

	life_timer += delta
	if life_timer >= lifetime:
		_fizzle()
		return

	if hanging:
		# Hover in place, then release into the fall.
		hang_timer -= delta
		if hang_timer <= 0.0:
			hanging = false
			sprite.play(ANIM_FALLING)   # switch from hover to the falling animation
		return

	# Newton's 2nd law (F = ma): gravity accelerates it straight down.
	velocity.y = minf(velocity.y + fall_gravity * delta, max_fall_speed)
	global_position += velocity * delta


func _on_body_entered(body: Node) -> void:
	if fizzling:
		return
	if body.has_method("take_hit"):
		# Vector: a meteor drop knocks the player mostly downward/outward.
		var dir := Vector2(0.0, 1.0)
		# Newton's 3rd law: the impact pushes the player as the reaction.
		body.take_hit(damage, dir * knockback)
		_fizzle()
	else:
		# Hit something that isn't a damageable target — treat it as the ground
		# or a wall and fizzle. Covers StaticBody2D floors and TileMap bodies.
		_fizzle()


func _fizzle() -> void:
	# Play the impact animation, stop interacting, remove when it finishes.
	fizzling = true
	velocity = Vector2.ZERO
	shape.set_deferred("disabled", true)
	sprite.play(ANIM_FIZZLE)
	await sprite.animation_finished
	queue_free()
