extends Control
## TitleMenu — the main menu / title screen (Godot 4.7).
## New Game clears any old save and starts at the first scene (intro cutscene or
## level 1). Continue resumes the saved level via the SaveManager and disables
## itself when there's no save. Options opens the volume panel. Quit closes.


# --- Where a New Game begins (intro cutscene or level 1) ---
@export_file("*.tscn") var first_scene: String = ""


@export_file("*.tscn") var options_scene: String = ""
@export var options_panel_path: NodePath


@export var new_game_button_path: NodePath = ^"NewGameButton"
@export var continue_button_path: NodePath = ^"ContinueButton"
@export var options_button_path: NodePath = ^"OptionsButton"
@export var quit_button_path: NodePath = ^"QuitButton"

var new_game_button: BaseButton = null
var continue_button: BaseButton = null
var options_button: BaseButton = null
var quit_button: BaseButton = null
var options_panel: Control = null


func _ready() -> void:
	new_game_button = get_node_or_null(new_game_button_path)
	continue_button = get_node_or_null(continue_button_path)
	options_button = get_node_or_null(options_button_path)
	quit_button = get_node_or_null(quit_button_path)
	options_panel = get_node_or_null(options_panel_path)

	# Options panel (if used) starts hidden.
	if options_panel != null:
		options_panel.visible = false

	# Auto-connect the buttons if they exist and aren't already connected.
	if new_game_button != null and not new_game_button.pressed.is_connected(_on_new_game_pressed):
		new_game_button.pressed.connect(_on_new_game_pressed)
	if continue_button != null and not continue_button.pressed.is_connected(_on_continue_pressed):
		continue_button.pressed.connect(_on_continue_pressed)
	if options_button != null and not options_button.pressed.is_connected(_on_options_pressed):
		options_button.pressed.connect(_on_options_pressed)
	if quit_button != null and not quit_button.pressed.is_connected(_on_quit_pressed):
		quit_button.pressed.connect(_on_quit_pressed)

	_refresh_continue_button()


func _refresh_continue_button() -> void:
	# Grey out Continue when there's no resumable save.
	if continue_button == null:
		return
	var sm := get_node_or_null("/root/SaveManager")
	var can_continue: bool = sm != null and sm.has_save()
	continue_button.disabled = not can_continue


func _on_new_game_pressed() -> void:
	# Fresh run: wipe any old progress so Continue won't resume a stale level,
	# then head to the first scene.
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.clear_save()
	if first_scene != "":
		get_tree().change_scene_to_file(first_scene)


func _on_continue_pressed() -> void:
	# Resume the saved level. Guarded so a missing save does nothing.
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_save():
		sm.load_game()


func _on_options_pressed() -> void:
	# Prefer a child panel (toggle visible); otherwise switch to a standalone scene.
	if options_panel != null:
		options_panel.visible = true
	elif options_scene != "":
		get_tree().change_scene_to_file(options_scene)


func _on_quit_pressed() -> void:
	get_tree().quit()
