@tool
extends Node
## Stores only the resource path, avoiding a scene/resource reference cycle.
## Reopening the scene directly must restore the same preview as the level page.
@export_file("*.tres", "*.res") var layout_path := ""

var _layout: GDLevelSceneRes
var _elapsed := 0.0
var _initialized := false


func _ready() -> void:
	set_process(Engine.is_editor_hint())


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	var scene_root := get_parent()
	if scene_root != EditorInterface.get_edited_scene_root():
		return
	if _layout == null or _layout.resource_path != layout_path:
		_layout = load(layout_path) as GDLevelSceneRes if ResourceLoader.exists(layout_path) else null
		_initialized = false
	if not GDLevelEditScene.is_edit_scene(_layout, scene_root):
		return
	if not _initialized:
		GDLevelSceneDrop.reconcile_scene(_layout)
		_initialized = true
	GDLevelEditScene.refresh_preview(_layout, scene_root)
