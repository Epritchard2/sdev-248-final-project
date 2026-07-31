extends CharacterBody2D
## Husk — player controller (Godot 4.7), MELEE build
## Covers proposal section 5.6 physics. Each law is tagged so it's easy to
## point to: search "Newton" to find all four.

# --- Animation names: change these to match your asset pack ---
const ANIM_IDLE   := "idle"
const ANIM_RUN    := "run"
const ANIM_JUMP   := "jump"        # single air anim (no separate fall)
const ANIM_LIGHT  := "attack_light"
const ANIM_HEAVY  := "attack_heavy"
const ANIM_HURT   := "hurt"
const ANIM_DEATH  := "death"

# --- Movement tunables ---
@export var mass: float = 1.0            # used by F = ma so knockback/feel scale with it
@export var move_speed: float = 180.0
@export var accel: float = 1600.0
@export var air_accel: float = 900.0
@export var friction: float = 2000.0
@export var jump_velocity: float = -430.0
@export var gravity: float = 1200.0

# --- Combat tunables ---
@export var has_weapon: bool = true      # armed from the start
@export var max_health: int = 5
@export var light_damage: int = 1
@export var heavy_damage: int = 3
@export var light_time: float = 1.0     # swing duration (rooted this long)
@export var heavy_time: float = 1.3
@export var light_knockback: float = 180.0
@export var heavy_knockback: float = 380.0
@export var recoil_factor: float = 0.15  # how much the swing kicks Husk back (3rd law)
@export var hurt_time: float = 0.3       # how long the hurt animation locks the player
@export var knockback_hold_time: float = 0.15  # seconds knockback rides before hurt friction
# Active hit window (seconds into the swing) — hitbox only lives between these.
# Centered on the mid-swing strike so the hit lands as the arm crosses the enemy,
# not after it has swept past. Widen if hits feel unreliable between swings.
@export var light_active_start: float = 0.3
@export var light_active_end: float = 0.7
@export var heavy_active_start: float = 0.4
@export var heavy_active_end: float = 0.9
# How far forward (local X) the hitbox sits per attack. Heavy reaches further.
# Set these to match where each strike lands in the animation.
@export var light_hitbox_x: float = 20.0
@export var heavy_hitbox_x: float = 40.0

# --- Nodes ---
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $AttackHitbox                 # child of player, holds the swing shape
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var jump_sfx: AudioStreamPlayer = $JumpSFX
@onready var light_sfx: AudioStreamPlayer = $LightSFX
@onready var heavy_sfx: AudioStreamPlayer = $HeavySFX
@onready var hurt_sfx: AudioStreamPlayer = $HurtSFX

# --- State ---
var facing: int = 1
var health: int = 0
var is_attacking: bool = false
var is_dead: bool = false
var is_hurt: bool = false
var hurt_timer: float = 0.0
var knockback_hold: float = 0.0
var attack_timer: float = 0.0
var attack_elapsed: float = 0.0
var active_start: float = 0.0
var active_end: float = 0.0
var recoil_done: bool = false
var current_damage: int = 0
var current_knockback: float = 0.0
var already_hit: Array = []              # so one swing hits each enemy only once

signal health_changed(current: int, maximum: int)   # HUD listens to this
signal died


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)
	# Hitbox starts disabled; only "on" during the active part of a swing.
	hitbox_shape.disabled = true
	hitbox.body_entered.connect(_on_hitbox_body_entered)


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		return

	# Newton's 2nd law (F = ma): gravity is a constant acceleration each frame.
	if not is_on_floor():
		velocity.y += gravity * delta

	hurt_timer = maxf(0.0, hurt_timer - delta)
	if hurt_timer == 0.0:
		is_hurt = false

	if is_hurt:
		# Let the knockback ride briefly before hurt-friction settles it, so a
		# hit landed the same frame (e.g. both attacking) still shoves visibly.
		if knockback_hold > 0.0:
			knockback_hold -= delta
		else:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	elif is_attacking:
		_process_attack(delta)
	else:
		_process_normal(delta)

	move_and_slide()
	_resolve_body_collisions()   # 3rd law
	_update_animation()


func _process_normal(delta: float) -> void:
	var input_dir := Input.get_axis("move_left", "move_right")

	if absf(input_dir) > 0.2:
		# Use the sign of the float directly. The old int() truncated analog
		# stick values (e.g. -0.8 -> 0), which broke facing on a controller.
		facing = -1 if input_dir < 0.0 else 1
		var a := accel if is_on_floor() else air_accel
		# Newton's 2nd law (F = ma): accel toward target speed, scaled by mass.
		velocity.x = move_toward(velocity.x, input_dir * move_speed, (a / mass) * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		# Vector: jump is a pure vertical velocity vector.
		velocity.y = jump_velocity
		if jump_sfx: jump_sfx.play()

	# Attacks only work once armed, and only from the ground (rooted swing).
	if has_weapon and is_on_floor():
		if Input.is_action_just_pressed("attack_light"):
			_start_attack(false)
		elif Input.is_action_just_pressed("attack_heavy"):
			_start_attack(true)


func _start_attack(heavy: bool) -> void:
	is_attacking = true
	already_hit.clear()
	recoil_done = false
	var reach: float
	if heavy:
		attack_timer = heavy_time
		active_start = heavy_active_start
		active_end = heavy_active_end
		current_damage = heavy_damage
		current_knockback = heavy_knockback
		reach = heavy_hitbox_x
		if heavy_sfx: heavy_sfx.play()
	else:
		attack_timer = light_time
		active_start = light_active_start
		active_end = light_active_end
		current_damage = light_damage
		current_knockback = light_knockback
		reach = light_hitbox_x
		if light_sfx: light_sfx.play()

	# Position the hitbox by facing directly (reach * facing) instead of scaling
	# the node. Scaling caused the hitbox to land in the wrong spot when facing
	# left; multiplying the offset by facing mirrors it cleanly both ways.
	hitbox.scale.x = 1
	hitbox.position.x = reach * facing
	hitbox_shape.disabled = true
	attack_elapsed = 0.0


func _process_attack(delta: float) -> void:
	# Rooted: no horizontal input during a swing, bleed velocity to a stop.
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	attack_elapsed += delta

	# The hitbox is only live during the active window (mid-swing strike),
	# not the whole animation.
	var in_active := attack_elapsed >= active_start and attack_elapsed <= active_end
	hitbox_shape.set_deferred("disabled", not in_active)

	if in_active:
		for body in hitbox.get_overlapping_bodies():
			_try_hit(body)

	attack_timer -= delta
	if attack_timer <= 0.0:
		is_attacking = false
		hitbox_shape.set_deferred("disabled", true)


func _try_hit(body: Node) -> void:
	if body in already_hit:
		return
	if body.has_method("take_hit"):
		already_hit.append(body)
		# Vector: knockback direction points from Husk toward the enemy.
		var dir := Vector2(facing, -0.2).normalized()
		# Newton's 3rd law: action on the enemy (equal/opposite to Husk's recoil).
		body.take_hit(current_damage, dir * current_knockback)
		# Reaction on Husk: the recoil kicks him back when the strike lands.
		if not recoil_done:
			recoil_done = true
			velocity.x -= facing * (current_knockback * recoil_factor)


func _on_hitbox_body_entered(body: Node) -> void:
	# Still useful for bodies that enter mid-swing.
	if not hitbox_shape.disabled and is_attacking:
		_try_hit(body)


func _resolve_body_collisions() -> void:
	# Newton's 3rd law (action/reaction): bumping an enemy body pushes both
	# apart with equal and opposite impulses, scaled by mass.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other is CharacterBody2D and other.has_method("apply_knockback"):
			var normal: Vector2 = c.get_normal()
			var impulse := 100.0
			other.apply_knockback(-normal * impulse)          # action
			velocity += normal * (impulse / mass)             # reaction


func apply_knockback(impulse: Vector2) -> void:
	velocity += impulse / mass


func take_hit(damage: int, knockback: Vector2) -> void:
	if is_dead:
		return
	health = maxi(0, health - damage)
	health_changed.emit(health, max_health)
	# Vector: incoming knockback is applied as a velocity impulse.
	apply_knockback(knockback)
	knockback_hold = knockback_hold_time
	if hurt_sfx: hurt_sfx.play()
	# Getting hit cancels any swing in progress so the interrupted attack
	# can't still land damage after the hurt animation.
	is_attacking = false
	hitbox_shape.set_deferred("disabled", true)
	if health == 0:
		_die()
	else:
		is_hurt = true
		hurt_timer = hurt_time
		sprite.play(ANIM_HURT)


func _die() -> void:
	is_dead = true
	is_attacking = false
	hitbox_shape.set_deferred("disabled", true)
	sprite.play(ANIM_DEATH)
	died.emit()


func pickup_weapon() -> void:
	has_weapon = true


func _update_animation() -> void:
	if sprite == null or is_dead:
		return
	sprite.flip_h = facing < 0
	sprite.offset.x = 15 * facing   # mirror X offset with facing so the turn stays centered
	if is_hurt:
		sprite.play(ANIM_HURT)
	elif is_attacking:
		sprite.play(ANIM_HEAVY if current_damage == heavy_damage else ANIM_LIGHT)
	elif not is_on_floor():
		sprite.play(ANIM_JUMP)
	elif absf(velocity.x) > 10.0:
		sprite.play(ANIM_RUN)
	else:
		sprite.play(ANIM_IDLE)
