extends Area2D
## SawTrap — a spinning ground hazard that damages the player on contact (Godot 4.7).
## Spins in place (animation only, no movement). While the player overlaps it,
## it deals damage on a repeating cooldown and knocks them away from its center.
## Physics tags (search "Newton") match the rest of the project.

@export var damage: int = 1
@export var knockback: float = 260.0
@export var damage_interval: float = 0.6   # seconds between hits while stood on

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

var player_inside: Node2D = null   # the player while they overlap the saw
var damage_timer: float = 0.0      # counts down; a hit lands when it reaches 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if sprite != null:
		sprite.play("spin")   # continuous spin animation (Loop ON)


func _physics_process(delta: float) -> void:
	if player_inside == null or not is_instance_valid(player_inside):
		return
	damage_timer = maxf(0.0, damage_timer - delta)
	if damage_timer <= 0.0:
		_hit_player()
		damage_timer = damage_interval


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if not body.has_method("take_hit"):
		return
	player_inside = body
	# First hit lands immediately on contact, then repeats on the interval.
	_hit_player()
	damage_timer = damage_interval


func _on_body_exited(body: Node) -> void:
	if body == player_inside:
		player_inside = null
		damage_timer = 0.0


func _hit_player() -> void:
	if player_inside == null or not is_instance_valid(player_inside):
		return
	# Vector: knock the player away from the saw's center, angled slightly up so
	# they get lifted off the blade rather than shoved straight sideways.
	var dir := (player_inside.global_position - global_position).normalized()
	dir.y = -0.4
	dir = dir.normalized()
	# Newton's 3rd law: the saw drives the player back as the reaction to contact.
	player_inside.take_hit(damage, dir * knockback)
