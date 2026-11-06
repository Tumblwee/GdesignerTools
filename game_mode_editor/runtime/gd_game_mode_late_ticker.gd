class_name GDGameModeLateTicker
extends Node

var mode: GDGameMode


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000


func _process(delta: float) -> void:
	if is_instance_valid(mode) and mode.should_tick():
		mode.machine.tick_late_update(delta)
