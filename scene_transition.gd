extends CanvasLayer
## SceneTransition — a global fade-through-black for every scene change (Godot 4.7).
## Register as an autoload named "SceneTransition". It draws a full-screen black
## overlay on top of everything and, on change_scene(), fades to black, swaps the
## scene, then fades back in. Any script calls SceneTransition.change_scene(path)
## instead of get_tree().change_scene_to_file(path) to get a smooth transition.
##
## It also fades in on game start, so the very first scene eases in from black.

@export var fade_time: float = 0.5   # seconds for each half of the fade

var _rect: ColorRect
var _busy: bool = false   # guards against overlapping transitions


func _ready() -> void:
	# Draw above everything else.
	layer = 128
	# Build a full-screen black rect that covers the viewport at any resolution.
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 1)   # start opaque so the first scene fades in
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	# Fade in the first scene on startup.
	_fade_to(0.0)


func change_scene(path: String) -> void:
	# Fade out, swap the scene, fade back in. Ignores repeat calls while a
	# transition is already running.
	if _busy or path == "":
		return
	_busy = true
	# Fade to black.
	await _fade_to(1.0)
	# Swap the scene while the screen is black.
	get_tree().change_scene_to_file(path)
	# Wait a frame so the new scene is in the tree before fading in.
	await get_tree().process_frame
	# Fade back in.
	await _fade_to(0.0)
	_busy = false


func _fade_to(target_alpha: float) -> void:
	if _rect == null:
		return
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", target_alpha, fade_time)
	await tween.finished
