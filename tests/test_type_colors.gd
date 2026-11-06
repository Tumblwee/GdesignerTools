extends SceneTree

## 用真实页面验证类型改色、三处显示、撤销和保存，设计文件只写入测试目录。
var passed := 0
var failed := 0
var fixture := "user://type_colors_%d" % Time.get_ticks_usec()


func _initialize() -> void:
	GDLevelLibraries.storage_root = fixture
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(message)


func _run() -> void:
	var page := GDLevelPage.new()
	root.add_child(page)
	var first := GDSampleFactory.build_level_scene()
	# 模拟没有颜色字段的旧目录。
	first.placement_archetype_type_keywords.entries[0].display_color = Color(0, 0, 0, 0)
	var peer := GDLevelArchetypeRes.new()
	peer.stable_id = 1042
	peer.display_name = "同类型的另一原型"
	peer.archetype_type_stable_id = first.archetypes[0].archetype_type_stable_id
	first.editor_add_archetype(peer)
	first.editor_add_placement(peer.stable_id, Vector3(2, 0, 3), Vector3.ZERO, Vector3.ONE, 1)
	page.set_layout(first)
	var catalog := GDLevelLibraries.catalog()
	var entry = catalog.find_active_by_stable_id(peer.archetype_type_stable_id)
	var old_color: Color = entry.get_display_color()
	var other: GDArchetypeRes = first.archetypes[1]
	var other_color := page.archetype_color(other.stable_id)
	check(old_color.a == 1.0 and old_color != other_color, "legacy types get visible, distinct default colors")
	check(page.archetype_color(first.archetypes[0].stable_id) == page.archetype_color(peer.stable_id), "different prototypes of one type share the same color")
	var expected := {first.archetypes[0].stable_id: old_color, peer.stable_id: old_color, other.stable_id: other_color}
	check_surfaces(page, expected)

	page.edit_global_types()
	var dialog: GDKeywordCatalogDialog = null
	for child in page.get_children():
		if child is GDKeywordCatalogDialog:
			dialog = child
	var picker := dialog._rows.get_child(0).get_child(0) as ColorPickerButton
	check(picker != null and picker.color == old_color and not picker.edit_alpha, "global types exposes an opaque color picker matching the displayed color")
	var types_doc: GDDocument = page._docs[catalog]
	types_doc.mark_saved()
	var cursor := types_doc._cursor
	var chosen := Color("3b9de0")
	picker.color_changed.emit(chosen)
	check(entry.display_color == chosen and types_doc.dirty and types_doc._cursor == cursor + 1, "choosing a color edits the global type and records one undo step")
	expected[first.archetypes[0].stable_id] = chosen
	expected[peer.stable_id] = chosen
	check_surfaces(page, expected)
	types_doc.undo()
	check(picker.color == old_color and not types_doc.dirty, "undo restores the type picker and saved state")
	expected[first.archetypes[0].stable_id] = old_color
	expected[peer.stable_id] = old_color
	check_surfaces(page, expected)
	types_doc.redo()
	check(picker.color == chosen, "redo restores the type picker")
	expected[first.archetypes[0].stable_id] = chosen
	expected[peer.stable_id] = chosen
	check_surfaces(page, expected)
	cursor = types_doc._cursor
	picker.color_changed.emit(chosen)
	check(types_doc._cursor == cursor, "choosing the current color does not add history")

	peer.editor_set_archetype_type_stable_id(other.archetype_type_stable_id)
	page.commit_library("修改原型类型")
	expected[peer.stable_id] = other_color
	check_surfaces(page, expected)
	page.library_doc.undo()
	expected[peer.stable_id] = chosen
	check_surfaces(page, expected)

	var second := GDLevelSceneRes.new()
	second.resource_name = "Second"
	page.set_layout(second)
	second.editor_add_placement(peer.stable_id, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 1)
	page.doc.commit("摆放共享原型")
	check_surfaces(page, expected)
	check(page._save_as(page.doc, fixture.path_join("Second.tres")) == OK, "saving a level saves its type colors")
	var loaded := ResourceLoader.load(fixture.path_join("Second.tres"), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as GDLevelSceneRes
	check(loaded.placement_archetype_type_keywords.find_active_by_stable_id(entry.stable_id).display_color.is_equal_approx(chosen), "type color survives a fresh reload")
	catalog.remove_entry(entry.entry_name)
	check(GDEditorUi.type_color(catalog, entry.stable_id) == chosen, "disabling a type preserves colors of its existing prototypes")
	catalog.add_entry(entry.entry_name, entry.display_name)
	check(entry.display_color == chosen, "restoring a type keeps its chosen color")
	check(page.archetype_color(-1) == GDEditorUi.type_color(catalog, 0) and GDEditorUi.type_color(catalog, 99999) == GDEditorUi.type_color(null, 0), "missing prototypes, missing types and unclassified items use a neutral color")

	var legacy := GDKeywordCatalogRes.new()
	var legacy_entry := legacy.add_entry("DifferentType", "旧类型")
	legacy_entry.display_color = Color(0, 0, 0, 0)
	var legacy_color := legacy_entry.get_display_color()
	var legacy_arch := GDLevelArchetypeRes.new()
	legacy_arch.archetype_type_stable_id = legacy_entry.stable_id
	GDLevelLibraries.merge_types(legacy, [legacy_arch], catalog)
	check(legacy_arch.archetype_type_stable_id != legacy_entry.stable_id and GDEditorUi.type_color(catalog, legacy_arch.archetype_type_stable_id) == legacy_color, "migration preserves legacy colors when colliding type IDs are remapped")
	dialog.hide()
	await process_frame

	var actors := GDActorPage.new()
	root.add_child(actors)
	actors.set_library(GDSampleFactory.build_actor_library())
	actors._edit_types()
	for child in actors.get_children():
		if child is GDKeywordCatalogDialog:
			var actor_picker := child._rows.get_child(0).get_child(0) as ColorPickerButton
			actor_picker.color_changed.emit(chosen)
	check(actors._row_of(actors.library.archetypes[0]).color == chosen, "the shared type dialog also updates actor list colors")
	actors.doc.undo()
	check(actors._row_of(actors.library.archetypes[0]).color != chosen, "actor type colors support undo")
	actors.queue_free()
	page.queue_free()
	await process_frame
	GDLevelSceneDrop.shutdown()
	print("TOTAL PASSED: %d  FAILED: %d" % [passed, failed])
	quit(failed)


func check_surfaces(page: GDLevelPage, expected: Dictionary) -> void:
	var prototypes_ok := true
	for group in page._archetype_list._groups:
		for row in group.items:
			prototypes_ok = prototypes_ok and row.color == expected[row.key.stable_id]
	check(prototypes_ok, "prototype list uses the expected type colors")
	var instances_ok := true
	for row in page._lists[0]._groups[0].items:
		var placement := page.find_placement(row.key)
		instances_ok = instances_ok and row.color == expected[placement.archetype_stable_id]
	check(instances_ok, "instance list uses the expected type colors")
	var marks_ok := true
	for mark in page._plan.marks:
		var placement := page.find_placement(mark.id)
		marks_ok = marks_ok and mark.color == expected[placement.archetype_stable_id]
	check(marks_ok, "plan markers use the expected type colors")
