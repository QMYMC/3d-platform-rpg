extends Node

# Run progress survives scene reloads. Nothing is written to disk.
signal progress_changed

const CHECKPOINTS: Array[StringName] = [&"", &"ruins", &"courtyard", &"boss"]
const RUNE_IDS: Array[StringName] = [&"camp", &"ruins", &"courtyard"]
var checkpoint_id: StringName = &""
var collected_rune_ids: Array[StringName] = []
var double_jump_unlocked := false
var elapsed_seconds := 0.0
var death_count := 0
var clock_running := false

func _process(delta: float) -> void:
	if clock_running:
		elapsed_seconds += delta

func collect_rune(id: StringName) -> bool:
	if id not in RUNE_IDS or id in collected_rune_ids:
		return false
	collected_rune_ids.append(id)
	progress_changed.emit()
	return true

func unlock_double_jump() -> bool:
	if double_jump_unlocked:
		return false
	double_jump_unlocked = true
	progress_changed.emit()
	return true

func reset_progress() -> void:
	checkpoint_id = &""
	collected_rune_ids.clear()
	double_jump_unlocked = false
	elapsed_seconds = 0.0
	death_count = 0
	clock_running = false
	progress_changed.emit()

func is_activated(id: StringName) -> bool:
	return CHECKPOINTS.find(id) > 0 and CHECKPOINTS.find(id) <= CHECKPOINTS.find(checkpoint_id)
