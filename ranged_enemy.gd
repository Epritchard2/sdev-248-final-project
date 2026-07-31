extends CharacterBody2D
## RangedEnemy (Skeleton Mage) — casts a slow homing orb, then backs away
## a short distance so the player can close in and get an opening (Godot 4.7).
## Physics tags (search "Newton") match the rest of the project.

# --- Animation names (match SpriteFrames exactly) ---
const ANIM_IDLE   := "idle"
const ANIM_WALK   := "walk"
const ANIM_HURT   := "hurt"
const ANIM_DEATH  := "death"
# Orb cast is a 3-stage sequence: windup -> brief loop -> release (orb fires).
const ANIM_CAST_WINDUP  := "cast_windup"    # atk1-initial stage (Loop OFF)
const ANIM_CAST_LOOP    := "cast_loop"      # atk1-loopable      (Loop ON)
const ANIM_CAST_RELEASE := "cast_release"   # atk1-final stage   (Loop OFF)

# --- Stats ---
@export var mass: float = 1.2
@export var max_health: int = 4
@export var patrol_speed: float = 40.0
@export var chase_speed: float = 70.0
@export var retreat_speed: float = 90.0
@export var gravity: float = 1200.0
@export var friction: float = 1200.0
@export var patrol_distance: float = 100.0

# --- Ranged combat ---
@export var cast_range: float = 220.0        # starts casting when player is within this
@export var retreat_distance: float = 100.0  # fixed distance to back up after casting
@export var cast_windup_time: float = 0.5    # windup stage length (match anim)
@export var cast_loop_time: float = 0.4      # how long the charge loop holds
@export var cast_release_time: float = 0.5   # release stage length (match anim)
@export var cast_cooldown: float = 1.8
@export var orb_scene: PackedScene           # the projectile scene spawned on cast

# --- Corpse / knockback (shared feel with melee enemies) ---
@export var hurt_time: float = 0.3
@export var knockback_drag: float = 300.0
@export var knockback_hold_time: float = 0.15
@export var corpse_linger_time: float = 2.5
@export_flags_2d_physics var floor_mask_bit: int = 4

# --- Nodes ---
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle          # where the orb spawns
@onready var detector: Area2D = $PlayerDetector

# --- State ---
enum State { PATROL, CHASE, CAST, RETREAT, HURT, DEAD }
var state: int = State.PATROL
var facing: int = 1
var health: int = 0
var start_x: float = 0.0
var target: Node2D = null
var cooldown_timer: float = 0.0
var hurt_timer: float = 0.0
var knockback_hold: float = 0.0
var cast_elapsed: float = 0.0
var cast_stage: int = 0        # 0 windup, 1 loop, 2 release
var orb_fired: bool = false
var retreat_start_x: float = 0.0
var retreat_dir: int = 1


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	start_x = global_position.x
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
			if knockback_hold > 0.0:
				knockback_hold -= delta
			else:
				velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
			if hurt_timer <= 0.0:
				state = State.CHASE if target != null else State.PATROL
		State.CAST:
			_process_cast(delta)
		State.RETREAT:
			_process_retreat(delta)
		State.CHASE:
			_process_chase(delta)
		State.PATROL:
			_process_patrol(delta)

	move_and_slide()
	_update_animation()


func _process_patrol(delta: float) -> void:
	if global_position.x > start_x + patrol_distance:
		facing = -1
	elif global_position.x < start_x - patrol_distance:
		facing = 1
	velocity.x = move_toward(velocity.x, facing * patrol_speed, 400.0 * delta)


func _process_chase(delta: float) -> void:
	if target == null:
		state = State.PATROL
		return
	var dx := target.global_position.x - global_position.x
	facing = -1 if dx < 0.0 else 1
	var dist: float = absf(dx)

	if dist <= cast_range and cooldown_timer == 0.0:
		_start_cast()
	elif dist > cast_range:
		# Move toward the player to get in range.
		velocity.x = move_toward(velocity.x, facing * chase_speed, 500.0 * delta)
	else:
		# In range but on cooldown — hold position and face the player.
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _start_cast() -> void:
	state = State.CAST
	cast_elapsed = 0.0
	cast_stage = 0
	orb_fired = false
	velocity.x = 0.0
	sprite.play(ANIM_CAST_WINDUP)


func _process_cast(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	cast_elapsed += delta

	match cast_stage:
		0:  # Windup
			if cast_elapsed >= cast_windup_time:
				cast_stage = 1
				cast_elapsed = 0.0
				sprite.play(ANIM_CAST_LOOP)
		1:  # Charge loop (holds briefly)
			if cast_elapsed >= cast_loop_time:
				cast_stage = 2
				cast_elapsed = 0.0
				sprite.play(ANIM_CAST_RELEASE)
		2:  # Release — fire the orb at the start of this stage
			if not orb_fired:
				orb_fired = true
				_fire_orb()
			if cast_elapsed >= cast_release_time:
				cooldown_timer = cast_cooldown
				_start_retreat()


func _fire_orb() -> void:
	if orb_scene == null or target == null:
		return
	var orb := orb_scene.instantiate()
	get_parent().add_child(orb)
	# Mirror the muzzle's local X offset by facing so the orb spawns from the
	# side the mage is facing, not always the right.
	var muzzle_offset := muzzle.position
	muzzle_offset.x = absf(muzzle_offset.x) * facing
	orb.global_position = global_position + muzzle_offset
	# Vector: initial direction from the spawn point toward the player.
	if orb.has_method("launch"):
		var dir: Vector2 = (target.global_position - orb.global_position)
		orb.launch(dir)


func _start_retreat() -> void:
	state = State.RETREAT
	# Record where we start so we can back up a fixed distance from here.
	retreat_start_x = global_position.x
	# Decide which way is away from the player, lock it in for the whole retreat.
	if target != null:
		retreat_dir = -1 if (target.global_position.x - global_position.x) > 0.0 else 1
	else:
		retreat_dir = -facing


func _process_retreat(delta: float) -> void:
	# Move a FIXED distance away, then stop and face the player. No kiting,
	# no distance-to-player checks (which caused the state flicker).
	var traveled := absf(global_position.x - retreat_start_x)
	if traveled < retreat_distance:
		facing = retreat_dir
		velocity.x = move_toward(velocity.x, retreat_dir * retreat_speed, 500.0 * delta)
	else:
		# Done backing up: stop, turn to face the player, go idle until cooldown.
		velocity.x = 0.0
		if target != null:
			facing = -1 if (target.global_position.x - global_position.x) < 0.0 else 1
		state = State.CHASE if target != null else State.PATROL


func _on_detector_body_entered(body: Node) -> void:
	if body.has_method("take_hit"):
		target = body
		if state == State.PATROL:
			state = State.CHASE


func _on_detector_body_exited(body: Node) -> void:
	if body == target:
		target = null
		if state == State.CHASE:
			state = State.PATROL


func take_hit(damage: int, knockback: Vector2) -> void:
	if state == State.DEAD:
		return
	health = maxi(0, health - damage)
	apply_knockback(knockback)
	knockback_hold = knockback_hold_time
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
		State.DEAD:
			pass
		State.HURT:
			pass  # hurt anim set in take_hit
		State.CAST:
			pass  # cast anim set in _start_cast
		State.RETREAT, State.CHASE, State.PATROL:
			if absf(velocity.x) > 15.0:
				sprite.play(ANIM_WALK)
			else:
				sprite.play(ANIM_IDLE)
