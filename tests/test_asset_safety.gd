extends SceneTree

var _failed: int = 0
var _passed: int = 0
var _root: String


class ConcurrentDocument extends GDDocument:
	var original_path: String

	func save(path: String = "", allow_overwrite: bool = false) -> Error:
		var err := super(path, allow_overwrite)
		if err == OK:
			var file := FileAccess.open(original_path, FileAccess.WRITE)
			file.store_string("external edit during save")
			file.close()
		return err


class TrashFailurePage extends GDSkillPage:
	func _trash(_path: String) -> Error:
		return FAILED


func _initialize() -> void:
	_root = "user://asset_safety_%d" % Time.get_ticks_usec()
	_run.call_deferred()


func _run() -> void:
	_test_document_ownership()
	_test_conflict_dialog_target()
	_test_actor_library_name()
	_test_actor_library_picker()
	_test_skill_undo_conflict()
	_test_skill_external_edit()
	_test_skill_trash_failure()
	_test_guide_undo_conflict()
	_test_cli_collisions()
	GDSkillForge._in_memory_skills.clear()
	GDGuideEditing._in_memory_graphs.clear()
	GDCoreServices.shutdown_for_tests()
	await process_frame
	_cleanup(ProjectSettings.globalize_path(_root))
	print("TOTAL PASSED: %d  FAILED: %d" % [_passed, _failed])
	quit(_failed)


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error(label)


func _cleanup(directory: String) -> void:
	var allowed := ProjectSettings.globalize_path(_root).simplify_path()
	if directory.simplify_path() != allowed and not directory.simplify_path().begins_with(allowed + "/"):
		return
	for subdirectory in DirAccess.get_directories_at(directory):
		_cleanup(directory.path_join(subdirectory))
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)


func _test_document_ownership() -> void:
	var path := _root.path_join("ownership.tres")
	var original := GDActorLibraryRes.new()
	original.display_name = "original"
	var owner := GDDocument.new(original)
	_check(owner.save(path) == OK and owner.owns_path(path), "first save establishes document ownership")
	original.display_name = "updated"
	owner.commit("edit")
	_check(owner.save() == OK, "document can save its owned path")
	var claimant := GDDocument.new(GDActorLibraryRes.new())
	_check(claimant.save(path) == ERR_ALREADY_EXISTS, "new document refuses an occupied path")
	_check(claimant.save(path, true) == ERR_ALREADY_EXISTS, "explicit overwrite refuses another loaded document")
	if OS.has_feature("windows"):
		var uppercase := ProjectSettings.globalize_path(path).to_upper()
		_check(claimant.save(uppercase, true) == ERR_ALREADY_EXISTS, "Windows case alias refuses another document owner")
	_check(original.resource_path == path and claimant.resource.resource_path.is_empty(), "collision keeps both resource paths")
	owner = null
	original = null
	_check(not ResourceLoader.has_cached(path), "released file can be explicitly overwritten")
	_check(claimant.save(path, true) == OK, "explicit overwrite of an unowned uncached file succeeds")
	var alias := ProjectSettings.globalize_path(path.get_base_dir().path_join("sub/../ownership.tres"))
	_check(claimant.can_save(alias) == OK, "path aliases preserve ownership")
	var loaded_path := _root.path_join("loaded_without_document.tres")
	ResourceSaver.save(GDActorLibraryRes.new(), loaded_path)
	var loaded := ResourceLoader.load(loaded_path)
	var other := GDDocument.new(GDActorLibraryRes.new())
	if OS.has_feature("windows"):
		var uppercase := ProjectSettings.globalize_path(loaded_path).to_upper()
		_check(other.save(uppercase, true) == ERR_ALREADY_EXISTS and loaded.resource_path == loaded_path, "Windows case alias refuses a ResourceLoader owner without a document")


func _test_conflict_dialog_target() -> void:
	var occupied := _root.path_join("dialog/occupied.tres")
	var owner := GDDocument.new(GDActorLibraryRes.new())
	owner.save(occupied)
	var page := GDPage.new()
	root.add_child(page)
	var draft := GDActorLibraryRes.new()
	var target := page.open_document(draft)
	draft.display_name = "draft"
	target.commit("edit draft")
	page._report_save(target, ERR_ALREADY_EXISTS, occupied)
	var dialogs := page.get_children().filter(func(child: Node) -> bool: return child is ConfirmationDialog)
	var dialog: ConfirmationDialog = dialogs.back()
	dialog.canceled.emit()
	dialog.hide()
	_check(draft.resource_path.is_empty() and target.dirty and owner.resource.resource_path == occupied, "cancel retains both documents and the unsaved draft")
	page._report_save(target, ERR_ALREADY_EXISTS, occupied)
	dialogs = page.get_children().filter(func(child: Node) -> bool: return child is ConfirmationDialog)
	dialog = dialogs.back()
	var other := GDActorLibraryRes.new()
	page.open_document(other)
	dialog.custom_action.emit(&"unique")
	_check(draft.resource_path.ends_with("occupied_2.tres") and other.resource_path.is_empty(), "alternative save stays bound to the requested document after switching selection")
	_check(not target.dirty and page.doc.resource == other, "saving another document preserves current selection")
	page.free()


func _test_actor_library_name() -> void:
	var page := GDActorPage.new()
	var library := GDActorLibraryRes.new()
	library.resource_name = "ActorLibrary_Safety"
	page.set_library(library)
	_check(not page._library_name_error("Safety").is_empty(), "actor library creation rejects an already open name")
	_check(not page._library_name_error("../escape").is_empty(), "actor library creation rejects path separators")
	page.free()


func _test_actor_library_picker() -> void:
	var scan_root := _root.path_join("actor_picker")
	var alpha := GDActorLibraryRes.new()
	alpha.display_name = "Alpha Picker"
	var beta := GDActorLibraryRes.new()
	beta.display_name = "Beta Picker"
	_check(GDDocument.new(alpha).save(scan_root.path_join("nested/alpha.tres")) == OK and GDDocument.new(beta).save(scan_root.path_join("beta.res")) == OK, "actor picker fixtures save in text and binary formats")
	GDDocument.new(GDLevelSceneRes.new()).save(scan_root.path_join("not_a_library.tres"))
	for directory in [".hidden", "ignored", "other_project"]:
		var path := scan_root.path_join(directory)
		GDDocument.new(GDActorLibraryRes.new()).save(path.path_join("excluded.tres"))
		if directory == "ignored":
			FileAccess.open(path.path_join(".gdignore"), FileAccess.WRITE).store_string("")
		elif directory == "other_project":
			FileAccess.open(path.path_join("project.godot"), FileAccess.WRITE).store_string("config_version=5\n")
	_check(GDActorLibraryPicker.scan_libraries(scan_root) == [alpha, beta], "actor picker discovers nested libraries, sorts names, and excludes levels, hidden folders and other projects")
	_check(GDActorLibraryPicker.scan_libraries(scan_root.path_join("missing")).is_empty(), "missing library directory produces an empty list")
	var page := GDActorPage.new()
	root.add_child(page)
	page.set_library(alpha)
	alpha.display_name = "Alpha Picker Edited"
	page.doc.commit("edit alpha")
	var edited_doc := page.doc
	page.set_library(beta)
	var draft := GDActorLibraryRes.new()
	draft.display_name = "Unsaved Picker Draft"
	page.set_library(draft)
	page._open_library()
	var dialog := page.get_children().filter(func(child: Node) -> bool: return child is GDActorLibraryPicker).back() as GDActorLibraryPicker
	_check(dialog != null and not (dialog as Node) is FileDialog and dialog.get_ok_button().disabled, "open actor library presents an asset list and requires selection")
	if dialog == null:
		page.free()
		return
	dialog._list._search.text = "Picker"
	dialog._list._search.text_changed.emit("Picker")
	_check(dialog._list._tree.get_root().get_child_count() == 3, "picker includes open saved libraries and unsaved drafts without duplicates")
	dialog._list._tree.get_root().get_first_child().select(0)
	_check(dialog._list.selected_library() == alpha and not dialog.get_ok_button().disabled, "selecting a library enables opening")
	dialog._list._search.text = "Beta Picker"
	dialog._list._search.text_changed.emit("Beta Picker")
	dialog._open_selected()
	_check(dialog.get_ok_button().disabled and page.library == draft, "filtering out the selection cannot open a hidden library")
	dialog._list._tree.get_root().get_first_child().select(0)
	dialog.confirmed.emit()
	_check(page.library == beta and edited_doc.dirty, "opening another library preserves edits in the previous document")
	page._open_library()
	dialog = page.get_children().filter(func(child: Node) -> bool: return child is GDActorLibraryPicker).back() as GDActorLibraryPicker
	dialog._list._search.text = "Alpha Picker"
	dialog._list._search.text_changed.emit("Alpha Picker")
	dialog._list._tree.get_root().get_first_child().select(0)
	dialog._list.item_activated.emit(alpha)
	_check(page.library == alpha and page.doc == edited_doc and page.doc.can_undo, "double-click reopens the original library with its edits and undo history")
	page._open_library()
	dialog = page.get_children().filter(func(child: Node) -> bool: return child is GDActorLibraryPicker).back() as GDActorLibraryPicker
	dialog.canceled.emit()
	dialog.hide()
	_check(page.library == alpha and page.doc == edited_doc and page.doc.dirty, "cancel keeps the current library and pending edits")
	page.free()


func _test_skill_undo_conflict() -> void:
	GDSkillForge._in_memory_skills.clear()
	var page := GDSkillPage.new()
	_check(page.skill == null and page._skills.is_empty(), "skill page construction leaves library loading until activation")
	page.skills_root = _root.path_join("skills")
	root.add_child(page)
	page.activate()
	var first := page.create_skill("Original", 4101, "original data")
	var original_path := first.resource_path
	page.rename_skill(first, "Renamed", 4102, "renamed data")
	var renamed_path := first.resource_path
	var replacement := page.create_skill("Original", 4101, "replacement data")
	var replacement_hash := FileAccess.get_sha256(original_path)
	page.select_skill(first)
	page.doc.undo()
	_check(GDSkillForge.find_skill_by_query("Skill_Renamed_4102", page.skills_root) == null, "undo removes the old skill lookup key")
	_check(GDSkillForge.get_all_known_skills(page.skills_root).has(first) and GDSkillForge.get_all_known_skills(page.skills_root).has(replacement), "conflicting skills remain visible")
	var issues := GDSkillValidation.SkillAssetValidator.validate(first, page._skills)
	_check(issues.any(func(issue: GDSkillValidation.SkillValidationIssue) -> bool: return issue.code == "skill.identity.conflict"), "undo identity collision is a validation issue")
	page.save_current()
	_check(FileAccess.get_sha256(original_path) == replacement_hash and FileAccess.file_exists(renamed_path), "saving undo collision preserves both existing files")
	var alternative := page._alternative_save_path(page.doc, original_path)
	_check(alternative.ends_with("Skill_Original_2_4101.tres"), "skill alternative name keeps the original numeric ID")
	_check(page._save_as(page.doc, alternative) == OK and first.unique_name == "Skill_Original_2_4101", "save alternative uses a matching skill identity")
	_check(first.resource_path == alternative and not page.doc.dirty and FileAccess.get_sha256(original_path) == replacement_hash, "save alternative resolves dirty state without overwriting the other document")
	var blocker := _root.path_join("save_blocker")
	FileAccess.open(blocker, FileAccess.WRITE).store_string("blocks a directory")
	var old_identity := first.unique_name
	var old_resource_name := first.resource_name
	var old_undo := page.doc.undo_label
	var failed_path := blocker.path_join("Skill_Failed_4101.tres")
	var printed_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	var save_error := page._save_as(page.doc, failed_path)
	Engine.print_error_messages = printed_errors
	_check(save_error != OK, "Save As reports an I/O failure")
	_check(first.unique_name == old_identity and first.resource_name == old_resource_name and first.resource_path == alternative and page.doc.undo_label == old_undo, "failed Save As restores identity, path and undo history")
	page.doc.undo()
	page.doc.redo()
	_check(GDSkillForge.find_skill_by_query(first.unique_name, page.skills_root) == first, "redo reindexes the skill lookup")
	page.free()
	GDSkillForge._in_memory_skills.clear()


func _test_skill_external_edit() -> void:
	var page := GDSkillPage.new()
	page.skills_root = _root.path_join("external")
	var skill := GDSkillRes.new()
	skill.configure_header("Before", 4201, "before", "")
	var document := ConcurrentDocument.new(skill)
	var old_path := page.skills_root.path_join("skill/Skill_Before_4201.tres")
	_check(GDDocument.new(skill).save(old_path) == OK, "external-edit fixture is saved")
	document.original_path = old_path
	skill.skill_name = "After"
	document.commit("rename")
	page._save(document)
	_check(FileAccess.get_file_as_string(old_path) == "external edit during save", "renaming preserves an old file changed externally during save")
	_check(FileAccess.file_exists(page.skills_root.path_join("skill/Skill_After_4201.tres")), "rename saves its new file alongside the external edit")
	page.free()
	GDSkillForge._in_memory_skills.clear()


func _test_skill_trash_failure() -> void:
	var page := TrashFailurePage.new()
	page.skills_root = _root.path_join("trash_failure")
	var skill := page.create_skill("Before", 4301, "before")
	var old_path := skill.resource_path
	page.rename_skill(skill, "After", 4301, "after")
	_check(FileAccess.file_exists(old_path) and FileAccess.file_exists(skill.resource_path), "failed trash leaves the old file and the saved rename intact")
	var path := skill.resource_path
	page.delete_skill_from_disk(skill)
	_check(skill.resource_path == path and page.skill == skill and page._skills.has(skill) and FileAccess.file_exists(path), "failed delete retains file, document and selection")
	page.free()
	GDSkillForge._in_memory_skills.clear()


func _test_guide_undo_conflict() -> void:
	GDGuideEditing._in_memory_graphs.clear()
	var page := GDGuidePage.new()
	root.add_child(page)
	var graph := GDGuideGraphRes.new()
	graph.set_graph_id(5101)
	graph.set_display_name("first graph")
	graph.add_default_skeleton()
	var first_path := _root.path_join("guide/Guide_5101.tres")
	_check(GDDocument.new(graph).save(first_path) == OK, "guide first asset is saved")
	page.load_graph(graph)
	page._set_graph_id(5102)
	page.doc.commit("change ID")
	page.save_current()
	_check(graph.resource_path == first_path and not FileAccess.file_exists(_root.path_join("guide/Guide_5102.tres")), "guide ID edit preserves its first saved filename")
	var second := GDGuideGraphRes.new()
	second.set_graph_id(5101)
	second.set_display_name("second graph")
	second.add_default_skeleton()
	GDGuideEditing.register_in_memory_graph(second)
	page.doc.undo()
	_check(GDGuideEditing.find_all_graphs().size() == 2, "undo graph ID conflict preserves both registered graphs")
	_check(page.get_report().contains("library.duplicate_id"), "graph ID conflict is shown in validation")
	_check(page._save_as(page.doc, _root.path_join("guide/copy.tres")) == ERR_INVALID_DATA, "Save As requires resolving graph IDs before choosing a new path")
	page.doc.redo()
	_check(GDGuideEditing.find_graph(5102) == graph and GDGuideEditing.find_graph(5101) == second, "redo restores registry keys")
	var id_root := _root.path_join("guide_ids")
	DirAccess.make_dir_recursive_absolute(id_root)
	FileAccess.open(id_root.path_join("Guide_5103.tres"), FileAccess.WRITE).store_string("occupied")
	_check(GDGuideEditing.suggest_graph_id(id_root) == 5104, "new guide IDs skip occupied filenames")
	graph.set_graph_id(5103)
	_check(GDGuideEditing.suggest_save_path(graph, id_root).ends_with("Guide_5103_2.tres"), "first-save suggestion skips occupied filenames")
	page.free()
	GDGuideEditing._in_memory_graphs.clear()


func _test_cli_collisions() -> void:
	var guide_path := _root.path_join("cli/guide.tres")
	var args := ["--id", "6101", "--name", "first", "--asset", guide_path]
	var first: Dictionary = JSON.parse_string(GDGuideCli.run("guide.create", args))
	_check(bool(first["ok"]), "guide CLI creates a new file")
	GDGuideEditing._in_memory_graphs.clear()
	var hash := FileAccess.get_sha256(guide_path)
	var second: Dictionary = JSON.parse_string(GDGuideCli.run("guide.create", ["--id", "6102", "--name", "second", "--asset", guide_path]))
	_check(not bool(second["ok"]) and FileAccess.get_sha256(guide_path) == hash and GDGuideEditing.find_graph(6102) == null, "guide CLI collision preserves file and registry")
	var effect_args := ["--name", "Safety", "--project-path", _root.path_join("effects")]
	var effect_first: Dictionary = JSON.parse_string(GDSkillCli.run("skill.effect.create", effect_args))
	var effect_second: Dictionary = JSON.parse_string(GDSkillCli.run("skill.effect.create", effect_args))
	_check(bool(effect_first["ok"]) and not bool(effect_second["ok"]), "effect CLI reports path collisions")
