extends SceneTree

var failed := 0
var passed := 0
var fixture := "user://level_libraries_%d" % Time.get_ticks_usec()

func _initialize() -> void:
	GDLevelLibraries.storage_root = fixture
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func _run() -> void:
	var page := GDLevelPage.new()
	root.add_child(page)
	var first := GDSampleFactory.build_level_scene()
	var original: GDArchetypeRes = first.archetypes[0]
	var original_id := original.stable_id
	var instance_count := first.placements.size()
	page.set_layout(first)
	check(first.archetype_library != null and first.archetypes[0] == original and original.stable_id == original_id and first.placements.size() == instance_count, "legacy migration preserves prototypes and placement identities")
	var lib := first.archetype_library
	var second := GDLevelSceneRes.new()
	second.resource_name = "Second"
	page.set_layout(second)
	check(second.archetype_library == lib, "new level reuses selected library")
	check(second.placement_archetype_type_keywords == first.placement_archetype_type_keywords, "levels share global type catalog")
	page.commands.new_archetype()
	var added: GDArchetypeRes = second.archetypes[-1]
	check(first.archetypes.has(added), "prototype created in one level is available in the other")
	page.library_doc.undo()
	check(not first.archetypes.has(added) and not second.archetypes.has(added), "library undo is shared")
	page.library_doc.redo()
	var shared_id := second.editor_add_placement(added.stable_id, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 1)
	check(not page.library_doc.undo() and first.archetypes.has(added), "library undo cannot remove a prototype placed in another level")
	second.editor_remove_placement(shared_id)
	page.doc.commit("level change")
	added.display_name = "Shared edit"
	page.commit_library("rename shared prototype")
	page.doc.undo()
	check(added.display_name == "Shared edit", "level undo cannot revert shared prototype edits")
	var other_library := GDLevelLibraryRes.new()
	other_library.resource_name = "OtherLibrary"
	other_library.display_name = "另一个库"
	check(page.bind_library(other_library), "empty level can select another library")
	check(second.archetypes.is_empty() and first.archetypes.has(added), "libraries remain separate collections")
	page.doc.undo()
	check(second.archetype_library == lib and second.archetypes.has(added), "undo library selection restores reference")
	page.set_layout(first)
	check(not page.bind_library(other_library) and first.archetype_library == lib, "switching cannot silently rebind existing placement IDs")
	page.commands.delete_archetype(original)
	check(lib.archetypes.has(original) and first.placements.size() == instance_count, "used shared prototypes cannot be deleted")
	page.commands.delete_archetype(added)
	check(not lib.archetypes.has(added), "unused shared prototype can be deleted")
	page.library_doc.undo()
	check(lib.archetypes.has(added), "unused prototype deletion is undoable")

	var legacy := GDSampleFactory.build_level_scene()
	legacy.placement_archetype_type_keywords.entries[0].entry_name = "Enemy"
	legacy.placement_archetype_type_keywords.entries[0].display_name = "敌人"
	page.set_layout(legacy)
	check(legacy.archetypes[0].archetype_type_stable_id != original.archetype_type_stable_id, "colliding old type IDs are remapped without changing meaning")
	check(legacy.placement_archetype_type_keywords == first.placement_archetype_type_keywords, "migrated independent libraries share global types")
	var reused := GDLevelSceneRes.new()
	reused.placement_archetype_type_keywords = GDSampleFactory.build_level_scene().placement_archetype_type_keywords
	reused.archetypes.append(legacy.archetypes[0])
	var mapped_type := legacy.archetypes[0].archetype_type_stable_id
	page.set_layout(reused)
	check(reused.archetypes[0].archetype_type_stable_id == mapped_type, "shared external prototype is never remapped twice during legacy migration")

	page.set_layout(second)
	var types := GDLevelLibraries.catalog()
	page.edit_global_types()
	var dialog: GDKeywordCatalogDialog = null
	for child in page.get_children():
		if child is GDKeywordCatalogDialog:
			dialog = child
	dialog._new_edit.text = "建筑"
	dialog._add_entry()
	var entry: Resource = types.entries[-1]
	check(entry.display_name == "建筑" and types.generated_file_path.is_empty(), "adding a Chinese type needs no code generation or output path")
	var count := types.entries.size()
	dialog._new_edit.text = "建筑"
	dialog._add_entry()
	check(types.entries.size() == count, "duplicate displayed type is not added")
	types.remove_entry(entry.entry_name)
	dialog._add_entry()
	check(not entry.deprecated and types.entries.size() == count, "readding a disabled type preserves its stable ID")
	dialog._new_edit.text = "NONE"
	dialog._add_entry()
	check(types.entries[-1].entry_name != "NONE", "reserved enum zero name is sanitized")
	# Use a fresh catalog for the exact missing-output regression, then clean up its generated file.
	var blank := GDKeywordCatalogRes.new()
	blank.enum_type_name = "RegressionTypes_%d" % Time.get_ticks_usec()
	var generator := GDKeywordCatalogDialog.new()
	generator._catalog = blank
	generator._build()
	page.add_child(generator)
	generator._generate()
	check(not blank.generated_file_path.is_empty() and FileAccess.file_exists(blank.generated_file_path), "first Generate supplies a valid output path")
	check((load(blank.generated_file_path) as GDScript).can_instantiate(), "generated GDScript compiles")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blank.generated_file_path))
	if FileAccess.file_exists(blank.generated_file_path + ".uid"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(blank.generated_file_path + ".uid"))
	generator.queue_free()
	types.editor_set_generated_output_folder(fixture)
	dialog._generate()
	check((load(types.generated_file_path) as GDScript).can_instantiate(), "global Chinese and reserved-name types generate valid GDScript")
	dialog.queue_free()

	# Also verify writes to independently stored prototype resources, not just embedded ones.
	var external_path := fixture.path_join("External.tres")
	check(GDDocument.new(added).save(external_path) == OK, "external prototype fixture saves")
	added.display_name = "Persisted library edit"
	page.commit_library("edit external prototype")
	var a_path := fixture.path_join("First.tres")
	var b_path := fixture.path_join("Second.tres")
	check(page._save_as(page._docs[first], a_path) == OK and page._save_as(page._docs[second], b_path) == OK, "saving levels persists shared dependencies first")
	var text := FileAccess.get_file_as_string(a_path)
	check(text.contains("archetype_library = ExtResource") and not text.contains("\narchetypes ="), "level stores external library reference instead of embedded prototype array")
	var loaded_a := ResourceLoader.load(a_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as GDLevelSceneRes
	var loaded_b := ResourceLoader.load(b_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as GDLevelSceneRes
	check(loaded_a.archetype_library.resource_path == loaded_b.archetype_library.resource_path and loaded_a.archetypes.size() == lib.archetypes.size(), "both saved levels resolve the same persistent library")
	check(loaded_b.find_archetype_by_stable_id(added.stable_id).display_name == "Persisted library edit", "external prototype edits survive a fresh reload")
	check(loaded_b.placement_archetype_type_keywords.find_any_by_name(entry.entry_name) != null, "global types survive a fresh reload")
	page.queue_free()
	await process_frame
	GDLevelSceneDrop.shutdown()
	print("TOTAL PASSED: %d  FAILED: %d" % [passed, failed])
	quit(failed)
