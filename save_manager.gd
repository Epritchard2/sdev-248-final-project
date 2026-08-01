extends Node
## SaveManager — a project autoload (singleton) that persists progress and
## settings to disk (Godot 4.7). Stores which level the player has reached and
## the audio volumes, so a Continue on the title screen resumes at that level and
## the options menu remembers its sliders across runs.
##
## Register this as an autoload named "SaveManager":
##   Project > Project Settings > Globals/Autoload > add save_manager.gd, name it
##   SaveManager. Then any script can call SaveManager.save_progress(...) etc.
##
## Progress model: refill-on-clear. Progress is saved when a level is CLEARED,
## recording the NEXT level to play. A resumed level therefore always starts at
## full health; mid-level healing is handled by pickups (walk-through potions).
## Health is not persisted per level — only which level to resume.

const SAVE_PATH := "user://save.json"

# --- Audio bus names (match the buses in the Audio panel) ---
const BUS_MASTER := "Master"
const BUS_MUSIC  := "Music"
const BUS_SFX    := "SFX"

# --- Live save data (kept in memory, mirrored to disk) ---
var current_level: String = ""   # scene path to RESUME at (next level), for Continue

# --- The level actually being played right now (set by each level on load).
# Used by the lose screen's Restart to reload the exact level the player died on.
# Not persisted — it's only meaningful during a live session.
var current_playing_level: String = ""

# --- Settings (0.0 to 1.0 linear; applied to the audio buses) ---
var volume_master: float = 1.0
var volume_music: float = 1.0
var volume_sfx: float = 1.0

var _loaded: bool = false        # have we read the file this session yet


func _ready() -> void:
	# Load settings on startup and push the volumes onto the audio buses so the
	# saved levels take effect immediately, before any menu opens.
	_load_from_disk()
	apply_all_volumes()


func has_save() -> bool:
	# A save is resumable only if the file exists AND names a level to load.
	_ensure_loaded()
	return current_level != ""


func save_progress(next_level: String) -> void:
	# Called when a level is cleared: store the NEXT level to resume at. This is
	# the auto-save. A resumed level starts at full health by design.
	current_level = next_level
	_write_to_disk()


func load_game() -> void:
	# Resume the stored level. No-op if there's no save.
	if not has_save():
		return
	SceneTransition.change_scene(current_level)


func set_playing_level(path: String) -> void:
	# Called by each level on load to record what's currently being played, so the
	# lose screen can restart the exact level the player died on.
	current_playing_level = path


func restart_level() -> void:
	# Reload the level currently being played (the one the player died on).
	if current_playing_level != "":
		SceneTransition.change_scene(current_playing_level)


func clear_save() -> void:
	# Wipe progress for a New Game. Leaves volume settings intact (those are
	# preferences, not run progress) and rewrites the file so they persist.
	current_level = ""
	_write_to_disk()


# --- Volume control (called by the options menu) ---
func set_volume(bus_name: String, linear: float) -> void:
	# Store and apply a single bus volume, then persist. linear is 0.0 to 1.0.
	linear = clampf(linear, 0.0, 1.0)
	match bus_name:
		BUS_MASTER: volume_master = linear
		BUS_MUSIC:  volume_music = linear
		BUS_SFX:    volume_sfx = linear
	_apply_bus(bus_name, linear)
	_write_to_disk()


func apply_all_volumes() -> void:
	# Push all stored volumes onto their buses. Called on startup and after load.
	_apply_bus(BUS_MASTER, volume_master)
	_apply_bus(BUS_MUSIC, volume_music)
	_apply_bus(BUS_SFX, volume_sfx)


func get_volume(bus_name: String) -> float:
	match bus_name:
		BUS_MASTER: return volume_master
		BUS_MUSIC:  return volume_music
		BUS_SFX:    return volume_sfx
	return 1.0


func _apply_bus(bus_name: String, linear: float) -> void:
	# Convert the 0..1 linear value to decibels and set it on the matching bus.
	# A linear value of 0 mutes the bus outright (linear_to_db(0) is -inf).
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return   # bus doesn't exist yet — skip quietly so this is safe to call
	if linear <= 0.0:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


# --- Disk I/O ---
func _ensure_loaded() -> void:
	if not _loaded:
		_load_from_disk()


func _write_to_disk() -> void:
	var data := {
		"current_level": current_level,
		"volume_master": volume_master,
		"volume_music": volume_music,
		"volume_sfx": volume_sfx,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not open save file for writing.")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _load_from_disk() -> void:
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: could not open save file for reading.")
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: save file was not valid JSON.")
		return
	current_level = parsed.get("current_level", "")
	volume_master = float(parsed.get("volume_master", 1.0))
	volume_music = float(parsed.get("volume_music", 1.0))
	volume_sfx = float(parsed.get("volume_sfx", 1.0))
