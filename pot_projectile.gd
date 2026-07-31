extends Area2D
## Pot projectile — a lobbed shot that splashes when it lands (Godot 4.7)
## Thrown by the pot creature. Follows a gravity arc toward the player, then
## plays a splash animation on impact/timeout before disappearing.

# --- Animation names (match the SpriteFrames exactly) ---
const ANIM_FLY    := "pot_orb"      # in-flight animation (looping)
const ANIM_SPLASH := "pot_splash"   # landing animation (one-shot, Loop OFF)

@export var fall_gravity: float = 800.0       # Newton's 2nd law: constant downward accel
@export var damage: int = 2
@export var knockback: float = 160.0
@export var lifetime: float = 4.0        # despawn after this long if it never lands
@export_flags_2d_physics var world_mask_bit: int = 4  # floor layer (bit 3 = value 4)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shape: CollisionShape2D = $CollisionShape2D

var velocity: Vector2 = Vector2.ZERO
var life_timer: float = 0.0
var splashing: bool = false     # once true, the projectile is landing/dying


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	sprite.play(ANIM_FLY)


func launch_at(from_pos: Vector2, target_pos: Vector2, arc_height: float = 120.0) -> void:
	# Solve for the launch velocity that lobs from from_pos to target_pos with a
	# given arc height. Vector: a ballistic launch shaped by gravity.
	global_position = from_pos
	var dx := target_pos.x - from_pos.x
	# Time to fall the arc height plus the drop to the target, using the peak.
	var peak := minf(-arc_height, (target_pos.y - from_pos.y) - arc_height)
	# Upward launch speed to reach the peak: v = sqrt(2 * g * h).
	var vy := -sqrt(2.0 * fall_gravity * absf(peak))
	# Total air time: rise to peak, then fall from peak to the target's height.
	var t_up := absf(vy) / fall_gravity
	var fall_dist := absf(peak) + (target_pos.y - from_pos.y)
	var t_down := sqrt(2.0 * maxf(1.0, fall_dist) / fall_gravity)
	var total_t := t_up + t_down
	var vx := dx / maxf(0.1, total_t)
	velocity = Vector2(vx, vy)


func _physics_process(delta: float) -> void:
	if splashing:
		return

	life_timer += delta
	if life_timer >= lifetime:
		_splash()
		return

	# Newton's 2nd law (F = ma): gravity bends the throw into a lobbed arc.
	velocity.y += fall_gravity * delta
	global_position += velocity * delta
	rotation = velocity.angle()


func _on_body_entered(body: Node) -> void:
	if splashing:
		return
	if body.has_method("take_hit"):
		var dir := velocity.normalized()
		# Newton's 3rd law: impact pushes the player as the reaction.
		body.take_hit(damage, dir * knockback)
		_splash()
	else:
		# Hit something that isn't a damageable target — treat it as the ground
		# or a wall and splash. Covers StaticBody2D floors, TileMap bodies, and
		# anything else on the collision mask that isn't the player.
		_splash()


func _splash() -> void:
	# Play the splash animation, stop interacting, remove when it finishes.
	splashing = true
	velocity = Vector2.ZERO
	rotation = 0.0
	shape.set_deferred("disabled", true)
	sprite.play(ANIM_SPLASH)
	await sprite.animation_finished
	queue_free()
