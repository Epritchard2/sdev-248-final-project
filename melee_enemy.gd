extends CharacterBody2D


const ANIM_IDLE   := "idle"
const ANIM_WALK   := "walk"
const ANIM_ATTACK := "attack"
const ANIM_HURT   := "hurt"
const ANIM_DEATH  := "death"

# --- Stats ---
@export var mass: float = 2.0             # heavier than player: F = ma makes it feel weighty
@export var max_health: int = 6           # tanky
@export var patrol_speed: float = 40.0    # slow shuffle
@export var chase_speed: float = 70.0     # slightly faster when it sees you
@export var gravity: float = 1200.0
@export var friction: float = 1200.0

# --- Patrol ---
@export var patrol_distance: float = 120.0   # how far it walks from its start point
# --- Combat ---
@export var contact_damage: int = 0          # damage comes from the swing, not touch
@export var attack_damage: int = 2
@export var attack_range: float = 40.0       # how close before it swings
@export var attack_time: float = 1.3         # total swing duration — match the attack anim
# Active hit window (seconds into the swing): hitbox lives only between these,
# after the telegraph and around the visible strike frames.
@export var attack_active_start: float = 0.5
@export var attack_active_end: float = 0.85
@export var attack_cooldown: float = 1.2
@export var attack_knockback: float = 260.0
@export var hitbox_reach: float = 30.0       # how far forward the swing hitbox sits
@export var hurt_time: float = 0.3           # how long the hurt animation locks the zombie
@export var knockback_drag: float = 300.0    # gentle drag during hurt so knockback shows
@export var knockback_hold_time: float = 0.15  # seconds the knockback rides with no drag
@export var corpse_linger_time: float = 2.5  # seconds the body stays after death before removal
@export_flags_2d_physics var floor_mask_bit: int = 4  # which layer the floor is on (bit 3 = value 4)

# --- Nodes ---
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $AttackHitbox
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var detector: Area2D = $PlayerDetector

# --- State ---
enum State { PATROL, CHASE, ATTACK, HURT, DEAD }
var state: int = State.PATROL
var facing: int = 1
var health: int = 0
var start_x: float = 0.0
var target: Node2D = null           # the player, once detected
var cooldown_timer: float = 0.0
var attack_elapsed: float = 0.0
var knockback_hold: float = 0.0
var hurt_timer: float = 0.0
var hit_landed: bool = false
var attacking: bool = false


func _ready() -> void:
	health = max_health
	start_x = global_position.x
	hitbox_shape.disabled = true
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	detector.body_entered.connect(_on_detector_body_entered)
	detector.body_exited.connect(_on_detector_body_exited)


func _physics_process(delta: float) -> void:
	cooldown_timer = maxf(0.0, cooldown_timer - delta)
	hurt_timer = maxf(0.0, hurt_timer - delta)

	# Newton's 2nd law (F = ma): gravity is a constant acceleration each frame.
	if not is_on_floor():
		velocity.y += gravity * delta

	match state:
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		State.HURT:
			# Preserve the knockback for a moment (no drag while knockback_hold
			# is active), then let light drag settle it. This keeps the push
			# visible regardless of node processing order on the hit frame.
			if knockback_hold > 0.0:
				knockback_hold -= delta
			else:
				velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
		State.ATTACK:
			_process_attack(delta)
		State.CHASE:
			_process_chase(delta)
		State.PATROL:
			_process_patrol(delta)

	move_and_slide()
	_update_animation()


func _process_patrol(delta: float) -> void:
	# Walk between start_x - patrol_distance and start_x + patrol_distance.
	if global_position.x > start_x + patrol_distance:
		facing = -1
	elif global_position.x < start_x - patrol_distance:
		facing = 1
	# Vector: horizontal velocity in the facing direction.
	velocity.x = move_toward(velocity.x, facing * patrol_speed, 400.0 * delta)


func _process_chase(delta: float) -> void:
	if target == null:
		state = State.PATROL
		return
	# Face the player and close in.
	var dir := signf(target.global_position.x - global_position.x)
	facing = int(dir) if dir != 0.0 else facing
	var dist: float = absf(target.global_position.x - global_position.x)

	if dist <= attack_range and cooldown_timer == 0.0:
		_start_attack()
	else:
		# Vector: chase velocity toward the player.
		velocity.x = move_toward(velocity.x, facing * chase_speed, 500.0 * delta)


func _start_attack() -> void:
	state = State.ATTACK
	attacking = true
	attack_elapsed = 0.0
	hit_landed = false
	velocity.x = 0.0
	# Flip the hitbox by facing directly (not by scaling the node), so it lands
	# correctly whether the zombie faces left or right.
	hitbox.scale.x = 1
	hitbox.position.x = hitbox_reach * facing
	hitbox_shape.set_deferred("disabled", true)
	sprite.play(ANIM_ATTACK)


func _process_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	attack_elapsed += delta

	# Hitbox is live only during the active window (after the windup telegraph,
	# for a short strike period) — not the whole animation.
	var in_active := attack_elapsed >= attack_active_start and attack_elapsed <= attack_active_end
	hitbox_shape.set_deferred("disabled", not in_active)

	# Land the hit once, during the active window.
	if in_active and not hit_landed:
		for body in hitbox.get_overlapping_bodies():
			if body.has_method("take_hit"):
				hit_landed = true
				# Vector: knockback points from zombie toward the player.
				var dir := Vector2(facing, -0.2).normalized()
				# Newton's 3rd law: action on the player (recoil is the reaction).
				body.take_hit(attack_damage, dir * attack_knockback)
				break

	# End the attack after its fixed duration.
	if attack_elapsed >= attack_time:
		_end_attack()


func _end_attack() -> void:
	attacking = false
	hitbox_shape.set_deferred("disabled", true)
	cooldown_timer = attack_cooldown
	# Back to chase if player still tracked, else patrol.
	state = State.CHASE if target != null else State.PATROL


func _on_hitbox_body_entered(_body: Node) -> void:
	# Hits are handled by the active overlap check in _process_attack so that a
	# player already standing inside the box still gets hit. Left empty on purpose.
	pass


func _on_detector_body_entered(body: Node) -> void:
	# Aggro: the player entered the detection circle.
	if body.has_method("take_hit"):   # cheap way to confirm it's the player
		target = body
		if state == State.PATROL:
			state = State.CHASE


func _on_detector_body_exited(body: Node) -> void:
	if body == target:
		target = null
		if state == State.CHASE:
			state = State.PATROL


# --- Damage taken (called by the player's attack hitbox) ---
func take_hit(damage: int, knockback: Vector2) -> void:
	if state == State.DEAD:
		return
	health = maxi(0, health - damage)
	# Vector: incoming knockback applied as a velocity impulse, scaled by mass.
	apply_knockback(knockback)
	knockback_hold = knockback_hold_time
	# Getting hit interrupts an in-progress swing: kill the hitbox and attack
	# state so the cancelled attack can't still land on the player.
	attacking = false
	hit_landed = true
	hitbox_shape.set_deferred("disabled", true)
	if health == 0:
		_die()
	else:
		state = State.HURT
		hurt_timer = hurt_time
		sprite.play(ANIM_HURT)


func apply_knockback(impulse: Vector2) -> void:
	# Newton's 2nd law (F = ma): heavier zombie moves less from the same impulse.
	velocity += impulse / mass


func _die() -> void:
	state = State.DEAD
	hitbox_shape.set_deferred("disabled", true)
	sprite.play(ANIM_DEATH)
	# Stop attacking/detecting the player, but stay solid against the FLOOR so the
	# corpse rests on the ground instead of falling through. Keep the body on its
	# own layer off, but keep the floor in the mask.
	detector.set_deferred("monitoring", false)
	collision_layer = 0            # nothing needs to detect the corpse
	collision_mask = floor_mask_bit  # still collide with the floor so it doesn't fall
	# Let the death animation play, then linger a moment before removing the body.
	await get_tree().create_timer(corpse_linger_time).timeout
	queue_free()


func _update_animation() -> void:
	if sprite == null:
		return
	sprite.flip_h = facing < 0

	match state:
		State.DEAD:
			pass  # death anim already playing, don't override
		State.HURT:
			# Stay in hurt for a fixed time so the animation plays fully.
			if hurt_timer <= 0.0:
				state = State.CHASE if target != null else State.PATROL
		State.ATTACK:
			pass  # attack anim already playing
		State.CHASE, State.PATROL:
			if absf(velocity.x) > 5.0:
				sprite.play(ANIM_WALK)
			else:
				sprite.play(ANIM_IDLE)
