extends Control
## LoseScreen — shown when the player dies (Godot 4.7). Offers three choices:
## return to the title, restart the exact level they died on, or quit the game.
## One reusable scene used as the lose_scene for every level.

@export_file("*.tscn") var title_scene: String = ""   # where Main Menu goes

@export var main_menu_button_path: NodePath = ^"MainMenuButton"
@export var restart_button_path: NodePath = ^"RestartButton"
@export var exit_button_path: NodePath = ^"ExitButton"

var main_menu_button: BaseButton = null
var restart_button: BaseButton = null
var exit_button: BaseButton = null


func _ready() -> void:
	main_menu_button = get_node_or_null(main_menu_button_path)
	restart_button = get_node_or_null(restart_button_path)
	exit_button = get_node_or_null(exit_button_path)

	if main_menu_button != null and not main_menu_button.pressed.is_connected(_on_main_menu_pressed):
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	if restart_button != null and not restart_button.pressed.is_connected(_on_restart_pressed):
		restart_button.pressed.connect(_on_restart_pressed)
	if exit_button != null and not exit_button.pressed.is_connected(_on_exit_pressed):
		exit_button.pressed.connect(_on_exit_pressed)
	ButtonSFX.attach_all([main_menu_button, restart_button, exit_button])


func _on_main_menu_pressed() -> void:
	if title_scene != "":
		SceneTransition.change_scene(title_scene)


func _on_restart_pressed() -> void:
	# Reload the exact level the player died on, tracked by the SaveManager.
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("restart_level"):
		sm.restart_level()


func _on_exit_pressed() -> void:
	get_tree().quit()
