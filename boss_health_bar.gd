extends CanvasLayer
## BossHealthBar — fixed on-screen health bar for the boss fight (Godot 4.7).
## Finds the boss through the "boss" group, tracks its boss_health_changed
## signal, and drives a ProgressBar. Hidden until the boss reports its health,
## so it only shows during the fight. On the boss's real death it runs the end
## sequence: a placeholder beat now, later a short dialogue, then the win scene.
##
## The bar naturally reflects the resurrect: the boss re-emits boss_health_changed
## with its revive health when it comes back, so the bar drops to 0, then rises
## to the revive amount, then drains again on the second death.

# --- Where the fight goes after the boss is beaten (set once the win scene
# exists; left blank, the end sequence just holds without changing scenes). ---
@export_file("*.tscn") var win_scene: String = ""

# --- How long to wait after the real death before moving on. Later this beat is
# where the pre-death dialogue plays instead of a plain timer. ---
@export var end_delay: float = 1.5

@onready var bar: ProgressBar = $Control/BossBar

var boss: Node = null
var ending: bool = false     # guards the end sequence so it runs once


func _ready() -> void:
	# Hidden until the boss reports in, so it stays off during the approach.
	visible = false
	# Wait a frame so the boss has registered its group in its own _ready().
	await get_tree().process_frame
	_connect_to_boss()


func _connect_to_boss() -> void:
	var bosses := get_tree().get_nodes_in_group("boss")
	if bosses.is_empty():
		return   # no boss in this scene — the bar simply never shows
	boss = bosses[0]
	if boss.has_signal("boss_health_changed"):
		if not boss.boss_health_changed.is_connected(_on_boss_health_changed):
			boss.boss_health_changed.connect(_on_boss_health_changed)
	if boss.has_signal("boss_died"):
		if not boss.boss_died.is_connected(_on_boss_died):
			boss.boss_died.connect(_on_boss_died)


func _on_boss_health_changed(current: int, max_health: int) -> void:
	# First report reveals the bar and sizes it; later reports (including the
	# revive bump) just move the value.
	bar.max_value = max_health
	bar.value = current
	if not visible:
		visible = true


func _on_boss_died() -> void:
	# Fired at the start of the boss's REAL death (after the resurrect is spent).
	# Drain the bar to empty, then run the end sequence.
	if ending:
		return
	ending = true
	bar.value = 0
	_run_end_sequence()


func _run_end_sequence() -> void:
	# Placeholder end: hold a beat, then move to the win scene. Later, replace the
	# timer with the pre-death dialogue, then the same scene change.
	await get_tree().create_timer(end_delay).timeout
	if win_scene != "":
		get_tree().change_scene_to_file(win_scene)
