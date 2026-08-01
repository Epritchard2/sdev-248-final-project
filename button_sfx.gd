extends Node
## ButtonSFX — a global autoload for menu button sounds (Godot 4.7).
## Register as an autoload named "ButtonSFX". Plays a hover sound and a click
## sound, routed to the SFX bus so the volume slider controls them. Any menu
## connects its buttons in one line: ButtonSFX.attach(button) — or attach a whole
## list with ButtonSFX.attach_all([b1, b2, ...]).
##
## Assign the two streams in the Inspector on the autoload (Project Settings >
## Autoload lets you open it), or set them here as defaults.

@export var hover_stream: AudioStream
@export var click_stream: AudioStream

var _hover: AudioStreamPlayer
var _click: AudioStreamPlayer


func _ready() -> void:
	_hover = AudioStreamPlayer.new()
	_hover.bus = "SFX"
	_hover.stream = load("res://UI Sound Effects/UI_Button_Click_1.wav")
	add_child(_hover)

	_click = AudioStreamPlayer.new()
	_click.bus = "SFX"
	_click.stream = load("res://UI Sound Effects/UI_Button_Click_4.wav")
	add_child(_click)


func attach(button: BaseButton) -> void:
	# Wire hover + click sounds onto one button.
	if button == null:
		return
	if not button.mouse_entered.is_connected(_play_hover):
		button.mouse_entered.connect(_play_hover)
	if not button.pressed.is_connected(_play_click):
		button.pressed.connect(_play_click)


func attach_all(buttons: Array) -> void:
	# Wire a whole list of buttons at once.
	for b in buttons:
		attach(b)


func _play_hover() -> void:
	if _hover != null and _hover.stream != null:
		_hover.play()


func _play_click() -> void:
	if _click != null and _click.stream != null:
		_click.play()
