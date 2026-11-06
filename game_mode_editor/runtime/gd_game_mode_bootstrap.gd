class_name GDGameModeBootstrap
extends Node

@export_file("*.tres") var config_path: String = "res://game_res/game_mode/GameMode_Default.tres"


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if is_instance_valid(GDGameMode.current):
		if GDGameMode.current.config_path != config_path:
			push_warning("已有 GameMode 使用 %s，忽略启动场景中的 %s。" % [GDGameMode.current.config_path, config_path])
		return
	var loaded := GDGameModeValidation.load_checked(config_path, true)
	if not loaded.ok:
		push_error("GameMode 启动失败：\n%s" % loaded.message)
		return
	var mode := GDGameMode.new()
	mode.config = loaded.config
	mode.config_path = config_path
	# Reserve the singleton before the deferred add, so two bootstraps in the
	# same scene cannot both create a persistent host.
	GDGameMode.current = mode
	get_tree().root.add_child.call_deferred(mode)
