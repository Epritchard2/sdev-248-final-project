extends Control
## OptionsMenu — volume settings panel (Godot 4.7).
## Three sliders (Master, Music, SFX) bound to the audio buses through the
## SaveManager, plus a Back button. Values load from the SaveManager on open and
## save live as the sliders move, so changes persist across runs.

# --- Slider paths 
@export var master_slider_path: NodePath = ^"MasterSlider"
@export var music_slider_path: NodePath = ^"MusicSlider"
@export var sfx_slider_path: NodePath = ^"SFXSlider"
@export var back_button_path: NodePath = ^"BackButton"


@export_file("*.tscn") var back_scene: String = ""

var master_slider: HSlider = null
var music_slider: HSlider = null
var sfx_slider: HSlider = null
var back_button: BaseButton = null


func _ready() -> void:
	master_slider = get_node_or_null(master_slider_path)
	music_slider = get_node_or_null(music_slider_path)
	sfx_slider = get_node_or_null(sfx_slider_path)
	back_button = get_node_or_null(back_button_path)

	var sm := get_node_or_null("/root/SaveManager")

	# Seed each slider from the saved value, then connect it. Setting the value
	# before connecting avoids a spurious save from the initial assignment.
	if master_slider != null:
		if sm != null:
			master_slider.value = sm.get_volume(sm.BUS_MASTER)
		if not master_slider.value_changed.is_connected(_on_master_changed):
			master_slider.value_changed.connect(_on_master_changed)
	if music_slider != null:
		if sm != null:
			music_slider.value = sm.get_volume(sm.BUS_MUSIC)
		if not music_slider.value_changed.is_connected(_on_music_changed):
			music_slider.value_changed.connect(_on_music_changed)
	if sfx_slider != null:
		if sm != null:
			sfx_slider.value = sm.get_volume(sm.BUS_SFX)
		if not sfx_slider.value_changed.is_connected(_on_sfx_changed):
			sfx_slider.value_changed.connect(_on_sfx_changed)

	if back_button != null and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)
	ButtonSFX.attach(back_button)


func _on_master_changed(value: float) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.set_volume(sm.BUS_MASTER, value)


func _on_music_changed(value: float) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.set_volume(sm.BUS_MUSIC, value)


func _on_sfx_changed(value: float) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.set_volume(sm.BUS_SFX, value)


func _on_back_pressed() -> void:
	# Standalone scene: change back to back_scene. Child panel: just hide.
	if back_scene != "":
		get_tree().change_scene_to_file(back_scene)
	else:
		visible = false
