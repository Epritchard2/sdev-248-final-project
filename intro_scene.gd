extends Node2D
## IntroScene — the opening: fades in from black, the camera pans down onto Husk
## standing by the open casket, holds a beat so his idle reads, then plays the
## intro dialogue (story + controls). When the dialogue closes it moves on to the
## first level (Godot 4.7). The player is frozen for the whole scene.

@export_file("*.tscn") var next_scene: String = ""   # the first level

# --- Fade in ---
@export var fade_rect_path: NodePath           # a full-screen black ColorRect (on a CanvasLayer)
@export var fade_hold: float = 0.4             # black-screen beat before the fade starts
@export var fade_time: float = 1.0             # how long the fade from black takes

# --- Camera pan ---
@export var camera_path: NodePath              # the intro's own Camera2D
@export var pan_start_offset: Vector2 = Vector2(0, -300)  # where the camera begins, relative to its end
@export var pan_time: float = 2.5              # how long the pan down takes
@export var hold_after_pan: float = 1.0        # beat to watch Husk idle before dialogue

# --- Dialogue ---
@export var dialogue_box_path: NodePath        # the intro's DialogueBox
@export var speaker_name: String = "Husk"
@export_multiline var lines: PackedStringArray = []

@onready var camera: Camera2D = get_node_or_null(camera_path)
@onready var dialogue_box: Node = get_node_or_null(dialogue_box_path)
@onready var fade_rect: ColorRect = get_node_or_null(fade_rect_path)

var pan_end: Vector2 = Vector2.ZERO   # the camera's resting position (its editor position)


func _ready() -> void:
	# Freeze the player for the whole intro.
	_freeze_player(true)
	# Start on a black screen.
	if fade_rect != null:
		fade_rect.color.a = 1.0
	# Record where the camera should end (its placed position), then start it
	# offset so it can pan into place.
	if camera != null:
		camera.make_current()
		pan_end = camera.global_position
		camera.global_position = pan_end + pan_start_offset
	_run_intro()


func _run_intro() -> void:
	# Hold on black a moment, then fade in as the camera begins panning down.
	if fade_hold > 0.0:
		await get_tree().create_timer(fade_hold).timeout
	# Fade from black and pan the camera at the same time.
	if fade_rect != null:
		var fade := create_tween()
		fade.tween_property(fade_rect, "color:a", 0.0, fade_time)
	if camera != null:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(camera, "global_position", pan_end, pan_time)
		await tween.finished
	if hold_after_pan > 0.0:
		await get_tree().create_timer(hold_after_pan).timeout
	_start_dialogue()


func _start_dialogue() -> void:
	if dialogue_box == null or not dialogue_box.has_method("start"):
		# No dialogue set up — just move on to the level.
		_finish()
		return
	var built: Array = []
	for l in lines:
		built.append({ "name": speaker_name, "text": l })
	if not dialogue_box.finished.is_connected(_on_dialogue_finished):
		dialogue_box.finished.connect(_on_dialogue_finished)
	dialogue_box.start(built)


func _on_dialogue_finished() -> void:
	_finish()


func _finish() -> void:
	# Unfreeze (harmless since we're leaving), fade back to black, then load the
	# first level so the transition isn't an abrupt cut.
	_freeze_player(false)
	if fade_rect != null:
		var fade := create_tween()
		fade.tween_property(fade_rect, "color:a", 1.0, fade_time)
		await fade.finished
	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)


func _freeze_player(frozen: bool) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p := players[0]
	if "dialogue_active" in p:
		p.dialogue_active = frozen
