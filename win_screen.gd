extends Control
## WinScreen — the ending / "Thanks for Playing" screen (Godot 4.7). Shown after
## the boss is beaten, over end-credits music. Two choices: return to the title
## or quit the game.

@export_file("*.tscn") var title_scene: String = ""   # where Main Menu goes

@export var main_menu_button_path: NodePath = ^"MainMenuButton"
@export var exit_button_path: NodePath = ^"ExitButton"

var main_menu_button: BaseButton = null
var exit_button: BaseButton = null


func _ready() -> void:
	main_menu_button = get_node_or_null(main_menu_button_path)
	exit_button = get_node_or_null(exit_button_path)

	if main_menu_button != null and not main_menu_button.pressed.is_connected(_on_main_menu_pressed):
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	if exit_button != null and not exit_button.pressed.is_connected(_on_exit_pressed):
		exit_button.pressed.connect(_on_exit_pressed)


func _on_main_menu_pressed() -> void:
	if title_scene != "":
		get_tree().change_scene_to_file(title_scene)


func _on_exit_pressed() -> void:
	get_tree().quit()
