extends CharacterBody2D
## PotEnemy — an ambush MOB that sits disguised as a pot until the player gets
## close, then reveals and fights (Godot 4.7). Hybrid attacker: lobs a splashing
## projectile at range, swings with two melee attacks up close.
## Physics tags (search "Newton") match the rest of the project.

# --- Animation names (match the SpriteFrames exactly) ---
const ANIM_IDLE        := "idle"                # dormant pot / active idle
const ANIM_REVEAL      := "pot_reveal"          # one-shot wake-up (Loop OFF)
const ANIM_WALK        := "walk"
const ANIM_HURT        := "hurt"
const ANIM_DEATH       := "death"
const ANIM_PROJECTILE  := "projectile_attack"   # ranged throw (Loop OFF)
const ANIM_ATTACK      := "attack_one"          # single melee swing (Loop OFF)

# --- Stats ---
@export var mass: float = 1.5
@export var max_health: int = 4
@export var move_speed: float = 55.0            # repositions toward the player when active
@export var gravity: float = 1200.0
@export var friction: float = 1200.0

# --- Ranged attack (lobbed projectile) ---
@export var projectile_scene: PackedScene       # the pot_projectile scene
@export var ranged_min_distance: float = 90.0   # only lobs when player is at least this far
# The throw is one 23-frame animation (windup -> release -> recovery). At the
# SpriteFrames default of ~10 fps that runs ~2.3s; set projectile_time to match
# your actual anim length, and projectile_release to the frame the orb leaves.
@export var projectile_time: float = 2.3        # total throw duration (match the 23-frame anim)
@export var projectile_release: float = 1.5     # seconds into the throw when the orb leaves the head
@export var projectile_arc_height: float = 120.0

# --- Melee attacks (two swings) ---
@export var melee_range: float = 40.0           # swings when player is within this
@export var attack_damage: int = 2
@export var attack_time: float = 0.8            # total swing duration (match anim)
@export var attack_active_start: float = 0.3
@export var attack_active_end: float = 0.6
@export var attack_knockback: float = 240.0
@export var hitbox_reach: float = 26.0

# --- Shared timing / feel ---
@export var attack_cooldown: float = 1.2
@export var hurt_time: float = 0.3
@export var knockback_drag: float = 300.0
@export var knockback_hold_time: float = 0.15
@export var corpse_linger_time: float = 2.5
@export_flags_2d_physics var floor_mask_bit: int = 4

# --- Nodes ---
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $AttackHitbox
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var muzzle: Marker2D = $Muzzle          # where the lobbed projectile spawns
@onready var detector: Area2D = $PlayerDetector

# --- State ---
enum State { DORMANT, REVEAL, IDLE_ACTIVE, MELEE, RANGED, HURT, DEAD }
var state: int = State.DORMANT
var facing: int = 1
var health: int = 0
var target: Node2D = null
var cooldown_timer: float = 0.0
var hurt_timer: float = 0.0
var knockback_hold: float = 0.0
var attack_elapsed: float = 0.0
var hit_landed: bool = false
var shot_fired: bool = false


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	hitbox_shape.disabled = true
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	detector.body_entered.connect(_on_detector_body_entered)
	detector.body_exited.connect(_on_detector_body_exited)
	# Dormant: show the disguised pot by holding on the first frame of the reveal
	# animation. speed_scale = 0 freezes frame advancement without the sticky
	# paused state that pause() leaves behind (which would freeze later attacks).
	sprite.play(ANIM_REVEAL)
	sprite.frame = 0
	sprite.speed_scale = 0.0


func _physics_process(delta: float) -> void:
	cooldown_timer = maxf(0.0, cooldown_timer - delta)
	hurt_timer = maxf(0.0, hurt_timer - delta)

	# Newton's 2nd law (F = ma): gravity is a constant acceleration each frame.
	if not is_on_floor():
		velocity.y += gravity * delta

	match state:
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		State.DORMANT:
			velocity.x = 0.0   # a pot doesn't move
		State.REVEAL:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		State.HURT:
			if knockback_hold > 0.0:
				knockback_hold -= delta
			else:
				velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
			if hurt_timer <= 0.0:
				state = State.IDLE_ACTIVE
		State.MELEE:
			_process_melee(delta)
		State.RANGED:
			_process_ranged(delta)
		State.IDLE_ACTIVE:
			_process_active(delta)

	move_and_slide()
	_update_animation()


func _process_active(delta: float) -> void:
	# Awake and deciding what to do based on range to the player.
	if target == null or not is_instance_valid(target):
		target = null
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		return

	var dx := target.global_position.x - global_position.x
	facing = -1 if dx < 0.0 else 1
	var dist: float = absf(dx)

	if cooldown_timer > 0.0:
		# On cooldown: hold ground and face the player.
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		return

	if dist <= melee_range:
		_start_melee()
	elif dist >= ranged_min_distance and projectile_scene != null:
		_start_ranged()
	else:
		# Out of melee range (or no projectile assigned): close in on the player.
		# This is the semi-chase — the pot pursues once it has woken up.
		velocity.x = move_toward(velocity.x, facing * move_speed, 500.0 * delta)


# --- Melee ---
func _start_melee() -> void:
	state = State.MELEE
	attack_elapsed = 0.0
	hit_landed = false
	velocity.x = 0.0
	hitbox.scale.x = 1
	hitbox.position.x = hitbox_reach * facing
	hitbox_shape.set_deferred("disabled", true)
	sprite.play(ANIM_ATTACK)


func _process_melee(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	attack_elapsed += delta

	var in_active := attack_elapsed >= attack_active_start and attack_elapsed <= attack_active_end
	hitbox_shape.set_deferred("disabled", not in_active)

	if in_active and not hit_landed:
		for body in hitbox.get_overlapping_bodies():
			if body.has_method("take_hit"):
				hit_landed = true
				# Vector: knockback from the pot toward the player.
				var dir := Vector2(facing, -0.2).normalized()
				# Newton's 3rd law: the swing pushes the player (reaction).
				body.take_hit(attack_damage, dir * attack_knockback)
				break

	if attack_elapsed >= attack_time:
		hitbox_shape.set_deferred("disabled", true)
		cooldown_timer = attack_cooldown
		state = State.IDLE_ACTIVE


# --- Ranged (lobbed projectile) ---
func _start_ranged() -> void:
	state = State.RANGED
	attack_elapsed = 0.0
	shot_fired = false
	velocity.x = 0.0
	sprite.play(ANIM_PROJECTILE)


func _process_ranged(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	attack_elapsed += delta

	# Release the lobbed shot partway through the throw animation.
	if not shot_fired and attack_elapsed >= projectile_release:
		shot_fired = true
		_lob_projectile()

	if attack_elapsed >= projectile_time:
		cooldown_timer = attack_cooldown
		state = State.IDLE_ACTIVE


func _lob_projectile() -> void:
	if projectile_scene == null or target == null:
		return
	var shot := projectile_scene.instantiate()
	get_parent().add_child(shot)
	# Mirror the muzzle X by facing so the throw comes from the correct side.
	var muzzle_offset := muzzle.position
	muzzle_offset.x = absf(muzzle_offset.x) * facing
	var from_pos := global_position + muzzle_offset
	if shot.has_method("launch_at"):
		shot.launch_at(from_pos, target.global_position, projectile_arc_height)
	else:
		shot.global_position = from_pos


# --- Reveal / detection ---
func _on_detector_body_entered(body: Node) -> void:
	if body.has_method("take_hit"):
		target = body
		if state == State.DORMANT:
			_reveal()


func _on_detector_body_exited(body: Node) -> void:
	# An ambush pot that has woken up keeps chasing the player even after they
	# leave the detector bubble — it does NOT drop the target and go inert.
	# (Detection only matters for the initial reveal; after that the pot commits.)
	pass


func _reveal() -> void:
	state = State.REVEAL
	velocity.x = 0.0
	# Restore normal playback speed (was frozen at 0 while dormant) and play the
	# reveal from the start.
	sprite.speed_scale = 1.0
	sprite.frame = 0
	sprite.play(ANIM_REVEAL)
	await sprite.animation_finished
	if state == State.REVEAL:   # not interrupted by a hit mid-reveal
		state = State.IDLE_ACTIVE


func _on_hitbox_body_entered(_body: Node) -> void:
	# Hits are handled by the active overlap check in _process_melee.
	pass


# --- Damage taken ---
func take_hit(damage: int, knockback: Vector2) -> void:
	if state == State.DEAD:
		return
	# A dormant pot still takes damage — reveal it if it's hit before aggro.
	# Restore playback speed in case it's still frozen from the dormant state,
	# otherwise the hurt/death anim would sit on one frame.
	sprite.speed_scale = 1.0
	health = maxi(0, health - damage)
	apply_knockback(knockback)
	knockback_hold = knockback_hold_time
	# Getting hit interrupts an in-progress swing.
	hit_landed = true
	hitbox_shape.set_deferred("disabled", true)
	if health == 0:
		_die()
	else:
		state = State.HURT
		hurt_timer = hurt_time
		sprite.play(ANIM_HURT)


func apply_knockback(impulse: Vector2) -> void:
	# Newton's 2nd law (F = ma): mass scales how far the impulse moves it.
	velocity += impulse / mass


func _die() -> void:
	state = State.DEAD
	hitbox_shape.set_deferred("disabled", true)
	sprite.play(ANIM_DEATH)
	detector.set_deferred("monitoring", false)
	collision_layer = 0
	collision_mask = floor_mask_bit
	await get_tree().create_timer(corpse_linger_time).timeout
	queue_free()


func _update_animation() -> void:
	if sprite == null:
		return
	sprite.flip_h = facing < 0
	match state:
		State.DORMANT:
			pass  # idle pot anim already playing
		State.REVEAL:
			pass  # reveal anim playing, awaited in _reveal
		State.DEAD, State.HURT, State.MELEE, State.RANGED:
			pass  # these anims are set where the state starts
		State.IDLE_ACTIVE:
			if absf(velocity.x) > 15.0:
				sprite.play(ANIM_WALK)
			else:
				sprite.play(ANIM_IDLE)
