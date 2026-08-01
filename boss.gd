extends CharacterBody2D
## Boss — the big skeleton brute (Godot 4.7). A three-attack state machine:
##   - atk1: close-range melee swing (the default pressure)
##   - atk3: a ranged barrage — the boss leaps back to open space, then rains
##           arcing projectiles that fall from above
## Melee is favored; the ranged barrage comes up less often. On reaching 0 HP the
## first time, the boss fakes death and resurrects enraged (faster, more ranged);
## the second time it dies for real.
## Emits boss_health_changed(current, max) so a dedicated boss health bar can track it.
## Physics tags (search "Newton") match the rest of the project.
##
## Dialogue: plays three sets of lines through a DialogueBox — a pre-fight taunt
## when the player first enters (the fight starts when it closes), a boast after
## the fake-death resurrect, and a final line before the real death resolves.

# --- Signals (for the boss health bar and win/level logic) ---
signal boss_health_changed(current: int, max_health: int)
signal boss_died

# --- Animation names (match the SpriteFrames exactly) ---
const ANIM_IDLE         := "idle"
const ANIM_WALK         := "walk"
const ANIM_HURT         := "hurt"
const ANIM_DEATH        := "death"
const ANIM_RESURRECT    := "resurrect"       # death-fakeout revive (Loop OFF)
const ANIM_ATK1         := "atk1"            # melee swing, recovery frames baked in (Loop OFF)
const ANIM_ATK3_START   := "atk3_start"      # barrage wind-up (Loop OFF)
const ANIM_ATK3_LOOP    := "atk3_loop"       # barrage firing (Loop ON)
const ANIM_ATK3_RETURN  := "atk3_return"     # barrage recovery (Loop OFF)

# --- Stats ---
@export var mass: float = 4.0                # very heavy: barely flinches from hits
@export var max_health: int = 40
@export var revive_health: int = 20          # HP it comes back with after the fakeout
@export var walk_speed: float = 60.0
@export var chase_speed: float = 95.0
@export var gravity: float = 1200.0
@export var friction: float = 1200.0

# --- Attack selection ---
@export var melee_range: float = 60.0        # swings when the player is within this
@export var ranged_weight: float = 0.25      # chance to pick the barrage on a fresh decision when off cooldown
@export var enraged_ranged_weight: float = 0.4  # higher barrage chance after the revive
@export var cast_cooldown: float = 6.0       # min seconds between casts — keeps melee as the primary
@export var decision_pause: float = 0.4      # brief think time between actions

# --- Melee (atk1) ---
@export var melee_damage: int = 4
@export var melee_time: float = 0.9          # swing duration (match anim)
@export var melee_active_start: float = 0.35
@export var melee_active_end: float = 0.65
@export var melee_knockback: float = 320.0
@export var melee_hitbox_reach: float = 44.0
@export var melee_cooldown: float = 1.2      # pause after a swing before he can act again

# --- Ranged barrage (atk3) ---
@export var projectile_scene: PackedScene
@export var jump_back_speed_x: float = 220.0 # horizontal leap speed away from player
@export var jump_back_speed_y: float = 380.0 # upward leap impulse
@export var atk3_start_time: float = 0.5     # wind-up / pre-cast duration (match atk3_start anim)
@export var atk3_shot_count: int = 5         # how many meteors drop in the volley
@export var atk3_shot_interval: float = 0.4  # seconds between meteors (spaced so the player can move)
@export var atk3_return_time: float = 0.5    # recovery duration (match atk3_return anim)
@export var atk3_spread_x: float = 40.0      # small random X scatter so meteors don't stack in one column

# --- Feel / corpse ---
@export var hurt_time: float = 0.25
@export var hurt_lock_enabled: bool = false  # full stagger on hit (can interrupt his attacks)
@export var hurt_flash_enabled: bool = true  # flash the hurt anim for feedback without staggering
@export var knockback_drag: float = 400.0
@export var knockback_hold_time: float = 0.12
@export var corpse_linger_time: float = 3.0
@export_flags_2d_physics var floor_mask_bit: int = 4

# --- Dialogue ---
@export var dialogue_box_path: NodePath          # the boss room's DialogueBox
@export var speaker_name: String = "The Brute"
@export_multiline var prefight_lines: PackedStringArray = []   # before the fight; closing starts it
@export_multiline var resurrect_lines: PackedStringArray = []  # boast after the fake-death revive
@export_multiline var predeath_lines: PackedStringArray = []   # final words before the real death

# --- Nodes ---
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $AttackHitbox
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var detector: Area2D = $PlayerDetector
@onready var dialogue_box: Node = get_node_or_null(dialogue_box_path)

# --- State ---
enum State { IDLE, CHASE, MELEE, JUMP_BACK, ATK3, HURT, DYING, RESURRECT, DEAD }
var state: int = State.IDLE
var facing: int = 1
var health: int = 0
var target: Node2D = null
var enraged: bool = false
var has_revived: bool = false
var active: bool = false        # gate: stays dormant until activate() is called (e.g. after dialogue)
var prefight_done: bool = false  # the pre-fight dialogue only plays once

var decision_timer: float = 0.0
var cast_timer: float = 0.0      # counts down; boss can only cast when this hits 0
var hurt_flash_timer: float = 0.0  # brief window where the hurt anim shows without staggering
var hurt_timer: float = 0.0
var knockback_hold: float = 0.0

# melee bookkeeping
var attack_elapsed: float = 0.0
var hit_landed: bool = false

# atk3 bookkeeping
var atk3_stage: int = 0        # 0 start, 1 firing, 2 return
var atk3_elapsed: float = 0.0
var shot_timer: float = 0.0
var shots_fired: int = 0       # counts meteors dropped this volley
var jump_back_dir: int = -1
var melee_sfx: AudioStreamPlayer
var cast_sfx: AudioStreamPlayer


func _ready() -> void:
	melee_sfx = AudioStreamPlayer.new()
	melee_sfx.bus = "SFX"
	melee_sfx.stream = load("res://Sound Effects/heavyattack.wav")
	add_child(melee_sfx)
	cast_sfx = AudioStreamPlayer.new()
	cast_sfx.bus = "SFX"
	cast_sfx.stream = load("res://Sound Effects/lightattack.wav")
	add_child(cast_sfx)
	add_to_group("enemies")
	add_to_group("boss")
	health = max_health
	hitbox_shape.disabled = true
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	detector.body_entered.connect(_on_detector_body_entered)
	detector.body_exited.connect(_on_detector_body_exited)
	# Announce starting health so a bar can size itself.
	boss_health_changed.emit(health, max_health)
	# Note: no activate() here — the boss stays dormant until the pre-fight
	# dialogue finishes (or activates immediately if no lines are set).


func _physics_process(delta: float) -> void:
	decision_timer = maxf(0.0, decision_timer - delta)
	cast_timer = maxf(0.0, cast_timer - delta)
	hurt_flash_timer = maxf(0.0, hurt_flash_timer - delta)
	hurt_timer = maxf(0.0, hurt_timer - delta)

	# Newton's 2nd law (F = ma): gravity is a constant acceleration each frame.
	if not is_on_floor():
		velocity.y += gravity * delta

	# Dormant until activated (e.g. by a pre-fight dialogue). Stand in idle,
	# ignore the player entirely, but still settle onto the floor with gravity.
	if not active:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		move_and_slide()
		if sprite != null:
			sprite.flip_h = facing < 0
			sprite.play(ANIM_IDLE)
		return

	match state:
		State.DEAD, State.DYING, State.RESURRECT:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		State.HURT:
			if knockback_hold > 0.0:
				knockback_hold -= delta
			else:
				velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
			if hurt_timer <= 0.0:
				state = State.CHASE if target != null else State.IDLE
		State.MELEE:
			_process_melee(delta)
		State.JUMP_BACK:
			_process_jump_back(delta)
		State.ATK3:
			_process_atk3(delta)
		State.CHASE:
			_process_chase(delta)
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	move_and_slide()
	_update_animation()


func _process_chase(delta: float) -> void:
	if target == null:
		state = State.IDLE
		return
	var dx := target.global_position.x - global_position.x
	facing = -1 if dx < 0.0 else 1
	var dist: float = absf(dx)

	if decision_timer > 0.0:
		# Brief think pause between actions — hold ground, face the player.
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		return

	# Decide the next action. Melee is the primary; the barrage is an occasional
	# option gated behind cast_cooldown so it can't be spammed.
	var rweight := enraged_ranged_weight if enraged else ranged_weight
	var can_cast := projectile_scene != null and cast_timer <= 0.0

	if dist <= melee_range:
		# In melee range: almost always swing. Only occasionally break off to cast,
		# and only if the cast is off cooldown.
		if can_cast and randf() < rweight:
			_start_jump_back()
		else:
			_start_melee()
	else:
		# Out of melee range: default to closing the distance. Cast only if it's
		# off cooldown and the roll passes — otherwise chase. This stops the
		# jump-back/cast loop, since a fresh cast can't happen until the cooldown
		# expires, so the boss spends that time pressuring with melee.
		if can_cast and randf() < rweight:
			_start_jump_back()
		else:
			velocity.x = move_toward(velocity.x, facing * chase_speed, 500.0 * delta)


# --- Melee (atk1) ---
func _start_melee() -> void:
	state = State.MELEE
	attack_elapsed = 0.0
	hit_landed = false
	velocity.x = 0.0
	# Single melee swing. The recovery frames are baked onto the end of atk1, so
	# melee_time should span the whole swing including recovery.
	hitbox.scale.x = 1
	hitbox.position.x = melee_hitbox_reach * facing
	hitbox_shape.set_deferred("disabled", true)
	sprite.play(ANIM_ATK1)
	if melee_sfx: melee_sfx.play()


func _process_melee(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	attack_elapsed += delta

	var in_active := attack_elapsed >= melee_active_start and attack_elapsed <= melee_active_end
	hitbox_shape.set_deferred("disabled", not in_active)

	if in_active and not hit_landed:
		for body in hitbox.get_overlapping_bodies():
			if body.has_method("take_hit"):
				hit_landed = true
				# Vector: knockback from the boss toward the player.
				var dir := Vector2(facing, -0.25).normalized()
				# Newton's 3rd law: the swing drives the player back (reaction).
				body.take_hit(melee_damage, dir * melee_knockback)
				break

	if attack_elapsed >= melee_time:
		hitbox_shape.set_deferred("disabled", true)
		# Longer pause after a swing so he doesn't attack again immediately.
		decision_timer = melee_cooldown
		state = State.CHASE if target != null else State.IDLE


# --- Jump-back into the barrage ---
func _start_jump_back() -> void:
	state = State.JUMP_BACK
	# Lock the cast on cooldown right away so the boss can't chain casts — it
	# must spend the next cast_cooldown seconds pressuring with melee.
	cast_timer = cast_cooldown
	# Leap away from the player: opposite of the current facing.
	jump_back_dir = -facing
	# Vector: an impulse away and upward. Newton's 2nd law shapes the arc via gravity.
	velocity.x = jump_back_dir * jump_back_speed_x
	velocity.y = -jump_back_speed_y
	sprite.play(ANIM_ATK3_START)   # start the wind-up as it leaps


func _process_jump_back(_delta: float) -> void:
	# Ride the leap until it lands, then begin firing.
	if is_on_floor() and velocity.y >= 0.0:
		_start_atk3()


# --- Ranged barrage (atk3) ---
func _start_atk3() -> void:
	state = State.ATK3
	atk3_stage = 0
	atk3_elapsed = 0.0
	shot_timer = 0.0
	shots_fired = 0
	velocity.x = 0.0
	# Face the player for the barrage.
	if target != null:
		facing = -1 if (target.global_position.x - global_position.x) < 0.0 else 1
	sprite.play(ANIM_ATK3_START)


func _process_atk3(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	atk3_elapsed += delta

	match atk3_stage:
		0:  # Wind-up / pre-cast (atk3_start plays, no meteors yet)
			if atk3_elapsed >= atk3_start_time:
				atk3_stage = 1
				atk3_elapsed = 0.0
				shot_timer = 0.0   # first meteor drops right away
				sprite.play(ANIM_ATK3_LOOP)
		1:  # Firing — drop exactly atk3_shot_count meteors, spaced by the interval
			shot_timer -= delta
			if shot_timer <= 0.0 and shots_fired < atk3_shot_count:
				shot_timer = atk3_shot_interval
				shots_fired += 1
				_fire_arc_shot()
			# Move on once all meteors are fired AND the last interval has elapsed,
			# so the final meteor gets its full spacing before recovery.
			if shots_fired >= atk3_shot_count and shot_timer <= 0.0:
				atk3_stage = 2
				atk3_elapsed = 0.0
				sprite.play(ANIM_ATK3_RETURN)
		2:  # Recovery
			if atk3_elapsed >= atk3_return_time:
				decision_timer = decision_pause
				state = State.CHASE if target != null else State.IDLE


func _fire_arc_shot() -> void:
	if projectile_scene == null or target == null:
		return
	var shot := projectile_scene.instantiate()
	get_parent().add_child(shot)
	if cast_sfx: cast_sfx.play()
	# Meteor drop: spawn high above the player's current position, with a small
	# random horizontal offset so repeated shots don't stack in one exact column.
	var drop_x := target.global_position.x + randf_range(-atk3_spread_x, atk3_spread_x)
	var above_pos := Vector2(drop_x, target.global_position.y)
	if shot.has_method("spawn_above"):
		shot.spawn_above(above_pos)
	else:
		shot.global_position = above_pos


# --- Detection ---
func _on_detector_body_entered(body: Node) -> void:
	if body.has_method("take_hit"):
		# Remember the player. The first time the player is seen, run the
		# pre-fight dialogue; the fight begins when it closes.
		target = body
		if not prefight_done:
			prefight_done = true
			_run_prefight()
		elif active and state == State.IDLE:
			state = State.CHASE


func _on_detector_body_exited(_body: Node) -> void:
	# The boss commits once it's fighting — it doesn't drop the player and stand
	# down just because they briefly left the detector. Detection only seeds the
	# target; the fight is arena-bound anyway.
	pass


# --- Pre-fight dialogue, then activate ---
func _run_prefight() -> void:
	# Play the pre-fight lines (boss stays dormant/invulnerable via `active`),
	# then start the fight. If there are no lines or no box, just activate.
	await _play_dialogue_and_wait(prefight_lines)
	activate()


# --- Activation (call this to start the fight, e.g. when dialogue closes) ---
func activate() -> void:
	if active:
		return
	active = true
	# Start the fight on cast cooldown so the boss opens with melee pressure
	# rather than immediately leaping into a barrage.
	cast_timer = cast_cooldown
	# If the player is already in range, start chasing immediately; otherwise
	# wait in idle until they enter the detector.
	if target != null:
		state = State.CHASE
	else:
		state = State.IDLE


func _on_hitbox_body_entered(_body: Node) -> void:
	# Hits handled by the active overlap check in _process_melee.
	pass


# --- Damage taken ---
func take_hit(damage: int, knockback: Vector2) -> void:
	if state == State.DEAD or state == State.DYING or state == State.RESURRECT:
		return
	# Invulnerable until the fight starts, so a stray hit during dialogue can't
	# chip health or stagger the boss.
	if not active:
		return
	health = maxi(0, health - damage)
	boss_health_changed.emit(health, max_health)
	apply_knockback(knockback)
	knockback_hold = knockback_hold_time

	if health == 0:
		_begin_death_sequence()
		return

	# Universal hit feedback: briefly tint the sprite so the player always sees
	# the hit register, no matter what the boss is doing (swinging, casting, etc.).
	_flash_hit()

	# The boss is committed during a barrage or the leap into one — don't change
	# animation state then (the tint above still gives feedback).
	if state == State.ATK3 or state == State.JUMP_BACK:
		return

	if hurt_lock_enabled:
		# Full stagger: stop the AI and lock into the hurt animation for a beat.
		# This can interrupt his melee swing.
		hit_landed = true
		hitbox_shape.set_deferred("disabled", true)
		state = State.HURT
		hurt_timer = hurt_time
		sprite.play(ANIM_HURT)
	elif hurt_flash_enabled and state != State.MELEE:
		# No stagger, but play the hurt animation for extra feedback when he's not
		# mid-swing (skipped during MELEE so it doesn't cut the attack short — the
		# color tint still fires in that case).
		hurt_flash_timer = hurt_time
		sprite.play(ANIM_HURT)


func _flash_hit() -> void:
	# Briefly tint the sprite red to signal a hit landed, then clear it. Runs
	# regardless of state so feedback is always visible.
	if sprite == null:
		return
	sprite.modulate = Color(1.0, 0.4, 0.4)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(self) and sprite != null:
		sprite.modulate = Color(1.0, 1.0, 1.0)


func apply_knockback(impulse: Vector2) -> void:
	# Newton's 2nd law (F = ma): the boss's large mass makes it barely move.
	velocity += impulse / mass


# --- Death fakeout / resurrect / real death ---
func _begin_death_sequence() -> void:
	hitbox_shape.set_deferred("disabled", true)
	velocity.x = 0.0
	if not has_revived:
		_fake_death()
	else:
		_real_death()


func _fake_death() -> void:
	# Play death, lie there a beat, then resurrect enraged — boasting on the way up.
	state = State.DYING
	sprite.play(ANIM_DEATH)
	await sprite.animation_finished
	await get_tree().create_timer(0.8).timeout
	state = State.RESURRECT
	sprite.play(ANIM_RESURRECT)
	await sprite.animation_finished
	# Boast before rejoining the fight. The state stays RESURRECT during the box,
	# so the AI holds and the boss keeps its pose (no moving/attacking).
	await _play_dialogue_and_wait(resurrect_lines)
	# Come back enraged with partial health.
	has_revived = true
	enraged = true
	health = revive_health
	boss_health_changed.emit(health, max_health)
	state = State.CHASE if target != null else State.IDLE


func _real_death() -> void:
	state = State.DEAD
	sprite.play(ANIM_DEATH)
	detector.set_deferred("monitoring", false)
	collision_layer = 0
	collision_mask = floor_mask_bit
	await sprite.animation_finished
	# Final words before the win flow resolves. Emitting boss_died AFTER the
	# dialogue means the health bar's end sequence (which loads the win scene)
	# waits for the boast to finish.
	await _play_dialogue_and_wait(predeath_lines)
	boss_died.emit()
	await get_tree().create_timer(corpse_linger_time).timeout
	queue_free()


# --- Dialogue helper ---
func _play_dialogue_and_wait(dlines: PackedStringArray) -> void:
	# Start the box with these lines and wait for it to close. No-op (returns
	# immediately) if there's no box or no lines, so the fight flow is unaffected
	# when dialogue isn't set up.
	if dialogue_box == null:
		dialogue_box = get_node_or_null(dialogue_box_path)
	if dialogue_box == null or not dialogue_box.has_method("start"):
		return
	if dlines.is_empty():
		return
	var built: Array = []
	for l in dlines:
		built.append({ "name": speaker_name, "text": l })
	dialogue_box.start(built)
	await dialogue_box.finished


func _update_animation() -> void:
	if sprite == null:
		return
	sprite.flip_h = facing < 0
	# Hold the hurt flash briefly so it's visible, then resume normal anims.
	if hurt_flash_timer > 0.0:
		return
	match state:
		State.CHASE, State.IDLE:
			if absf(velocity.x) > 15.0:
				sprite.play(ANIM_WALK)
			else:
				sprite.play(ANIM_IDLE)
		_:
			pass  # all other states set their own anim where they start
