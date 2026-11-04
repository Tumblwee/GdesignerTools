@tool
class_name GDGuideGraphList
extends GDLibraryList

## 左侧引导图列表：项目里的图；项目还没有图（或从 ⋯ 打开过示例）时再列出示例。
## 新建、复制、删除的对话在这里；打开、登记、保存交给页面。

signal open_requested(graph: GDGuideGraphRes)
## 新建或复制出来的图，页面负责登记、打开并保存。
signal created(graph: GDGuideGraphRes)
## 已从注册表移除。
signal removed(graph: GDGuideGraphRes)
signal rename_confirmed(graph: GDGuideGraphRes, new_name: String)
signal said(text: String)

var show_samples: bool = false


func _init() -> void:
	super("引导图", "搜索名称或 ID")
	header.add_child(GDEditorUi.tool_button(&"Add", "新建引导图", new_graph))
	set_empty_state(GDEditorUi.empty_state("还没有引导图", "", "新建引导图", new_graph))
	item_selected.connect(func(key: Variant) -> void: open_requested.emit(key))
	context_requested.connect(_show_menu)
	rename_requested.connect(rename)
	duplicate_requested.connect(duplicate_graph)
	delete_requested.connect(delete_graph)


func refresh(current: GDGuideGraphRes) -> void:
	GDGuideEditing.reindex()
	var project: Array = []
	var samples: Array = []
	for g in GDGuideEditing.find_all_graphs():
		(samples if GDGuideSamples.is_sample(g) else project).append(_row_of(g))
	if not project.is_empty() and not show_samples and not GDGuideSamples.is_sample(current):
		samples.clear()
	var groups: Array = [{"title": "", "items": project}]
	if not samples.is_empty():
		groups.append({"title": "示例", "key": &"samples", "items": samples})
	set_items(groups)
	select_key(current)


## 可以打开的图，示例排在最后。
func shown_graphs() -> Array[GDGuideGraphRes]:
	var shown: Array[GDGuideGraphRes] = []
	for g in GDGuideEditing.find_all_graphs():
		if not GDGuideSamples.is_sample(g):
			shown.append(g)
	if shown.is_empty() or show_samples:
		for g in GDGuideSamples.ensure_registered():
			if GDGuideSamples.is_sample(g):
				shown.append(g)
	return shown


func _row_of(g: GDGuideGraphRes) -> Dictionary:
	var tip := "示例，只在内存里；保存后成为项目引导图" if GDGuideSamples.is_sample(g) else (g.resource_path if not g.resource_path.is_empty() else "尚未保存")
	return {"key": g, "text": g.display_name, "detail": "#%d" % g.graph_id, "color": GDEditorUi.hue_color(g.graph_id), "tooltip": tip}


func _show_menu(key: Variant) -> void:
	if key == null:
		GDEditorUi.context_menu(self, [{"text": "新建引导图…", "do": new_graph}])
		return
	var g: GDGuideGraphRes = key
	var items: Array = [
		{"text": "重命名…", "do": rename.bind(g), "shortcut": GDEditorUi.key(KEY_F2)},
		{"text": "复制", "do": duplicate_graph.bind(g), "shortcut": GDEditorUi.key(KEY_D, true)},
	]
	if not GDGuideSamples.is_sample(g):
		items.append(null)
		items.append({"text": "从磁盘删除…" if not g.resource_path.is_empty() else "丢弃…", "do": delete_graph.bind(g), "shortcut": GDEditorUi.key(KEY_DELETE)})
	GDEditorUi.context_menu(self, items)


func new_graph() -> void:
	GDDialogs.prompt(self, "新建引导图", "名称", "新引导", func(value: String) -> void:
		var g := GDGuideGraphRes.new()
		g.set_graph_id(GDGuideEditing.suggest_graph_id())
		g.set_display_name(value)
		g.add_default_skeleton()
		created.emit(g)
	, func(value: String) -> String: return "名称不能为空" if value.strip_edges().is_empty() else "")


func rename(g: GDGuideGraphRes) -> void:
	GDDialogs.prompt(self, "重命名引导图", "名称", g.display_name, func(value: String) -> void: rename_confirmed.emit(g, value))


func duplicate_graph(g: GDGuideGraphRes) -> void:
	var copy := g.duplicate() as GDGuideGraphRes
	copy.set_graph_id(GDGuideEditing.suggest_graph_id())
	copy.set_display_name("%s 副本" % g.display_name)
	created.emit(copy)


## 删除碰磁盘、无法撤销，所以要确认。示例图不能删。
func delete_graph(g: GDGuideGraphRes) -> void:
	if GDGuideSamples.is_sample(g):
		said.emit("示例图不能删除")
	elif g.resource_path.is_empty():
		GDDialogs.confirm(self, "丢弃引导图", "「%s」还没保存，丢弃后找不回来。" % g.display_name, "丢弃", _forget.bind(g))
	else:
		GDDialogs.confirm(self, "从磁盘删除", "删除 %s？这一步无法撤销。" % g.resource_path, "删除", func() -> void:
			var path := g.resource_path
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if Engine.is_editor_hint():
				EditorInterface.get_resource_filesystem().scan()
			_forget(g)
			said.emit("已删除 %s" % path)
		)


func _forget(g: GDGuideGraphRes) -> void:
	GDGuideEditing.unregister_graph(g)
	GDGuideRunnerSystem.GuideBreakpoints.clear(g)
	removed.emit(g)
