extends CanvasLayer
## DialogueBox — a reusable letter-by-letter text box (Godot 4.7).
## Shows a sequence of lines one at a time, each revealed character by character.
## The advance action finishes a still-typing line instantly, or moves to the
## next line once fully shown. Emits "finished" when the last line closes, which
## callers use to trigger what comes next (start a fight, unfreeze, load a scene).
##
## While open it freezes the player (via a dialogue_active flag on the player) so
## input can't leak through the box. The box hides itself when idle.

signal finished          # emitted once the whole sequence closes
signal line_advanced     # emitted each time a new line starts (for one-shot cues)

# --- Input ---
@export var advance_action: String = "jump"   # the action that reveals/advances

# --- Typewriter ---
@export var chars_per_second: float = 30.0    # reveal speed
@export var type_sfx_path: NodePath           # optional AudioStreamPlayer, blips per character
@export var freeze_player: bool = true        # stop player movement while the box is up

# --- Nodes ---
@onready var panel: Control = $Panel
@onready var name_label: Label = $Panel/NameLabel
@onready var text_label: Label = $Panel/TextLabel

var lines: Array = []            # queue of { "name": String, "text": String }
var line_index: int = 0
var full_text: String = ""       # the current line's complete text
var revealed: float = 0.0        # how many characters are currently shown (float for smooth timing)
var typing: bool = false         # true while a line is still revealing
var active: bool = false         # true while the box is open


func _ready() -> void:
	# Start hidden and idle.
	visible = false
	panel.visible = false
	set_process(false)


func start(new_lines: Array) -> void:
	# Open the box with a list of lines. Each entry is either a plain String
	# (no speaker name) or a Dictionary { "name": ..., "text": ... }.
	if new_lines.is_empty():
		return
	lines = new_lines
	line_index = 0
	active = true
	visible = true
	panel.visible = true
	set_process(true)
	_freeze_player(true)
	_show_line(line_index)


func _show_line(index: int) -> void:
	var entry: Variant = lines[index]
	var speaker := ""
	var body := ""
	# Accept either a bare string or a { name, text } dictionary.
	if typeof(entry) == TYPE_DICTIONARY:
		speaker = entry.get("name", "")
		body = entry.get("text", "")
	else:
		body = str(entry)

	name_label.text = speaker
	name_label.visible = speaker != ""
	full_text = body
	text_label.text = ""
	revealed = 0.0
	typing = true
	line_advanced.emit()


func _process(delta: float) -> void:
	if not typing:
		return
	# Reveal characters over time.
	revealed += chars_per_second * delta
	var shown := int(revealed)
	if shown >= full_text.length():
		# Line fully revealed.
		text_label.text = full_text
		typing = false
	else:
		var prev_len := text_label.text.length()
		text_label.text = full_text.substr(0, shown)
		# Play a blip only when a new character actually appeared this frame.
		if text_label.text.length() > prev_len:
			_play_type_sfx()


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed(advance_action):
		_advance()
		# Consume the press so the same tap can't also make the player jump.
		get_viewport().set_input_as_handled()


func _advance() -> void:
	if typing:
		# First press finishes the current line instantly.
		text_label.text = full_text
		typing = false
		return
	# Line is fully shown — move to the next one, or close if it was the last.
	line_index += 1
	if line_index >= lines.size():
		_close()
	else:
		_show_line(line_index)


func _close() -> void:
	active = false
	typing = false
	visible = false
	panel.visible = false
	set_process(false)
	_freeze_player(false)
	finished.emit()


func _play_type_sfx() -> void:
	var sfx := get_node_or_null(type_sfx_path)
	if sfx != null and sfx is AudioStreamPlayer:
		sfx.play()


func _freeze_player(frozen: bool) -> void:
	if not freeze_player:
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p := players[0]
	# The player checks this flag and skips input while it's true.
	if "dialogue_active" in p:
		p.dialogue_active = frozen
