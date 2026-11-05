extends SceneTree

## 关卡页的独立测试：真实实例化页面，驱动列表、平面图输入、属性栏、撤销与保存重载。
## 运行：godot --headless --path D:/GodotTemplate -s res://addons/gdesigner_tools/tests/test_level_page.gd

const SAVE_PATH := "user://level_page_test.tres"
const Kind := GDLevelPage.Kind

class TestLevelPage extends GDLevelPage:
	var edit_scene_active := true

	func can_edit_scene() -> bool:
		return edit_scene_active and layout != null


var _passed := 0
var _failed := 0
var page: TestLevelPage = null
var plan: GDPlanView = null
var layout: GDLevelSceneRes = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	page = TestLevelPage.new()
	root.add_child(page)
	page.position = Vector2.ZERO
	page.size = Vector2(1280, 800)
	plan = page._plan
	layout = GDSampleFactory.build_level_scene()
	page.set_layout(layout)
	await _frames(4)
	page.fit_plan()
	await _frames(1)
	_check(page.get_current_layout() == layout and page.doc != null, "set_layout opens a document")
	_check(page._archetype_list._tree.get_root().get_child_count() == 2, "archetypes are grouped by type")

	_test_select_and_edit_position()
	_test_edit_scene_gate()
	_test_stale_instance_callbacks()
	_test_delete_instance()
	_test_archetypes()
	await _frames(1)
	await _test_overrides_and_replace()
	_test_reset_id()
	_test_paths()
	_test_cameras()
	_test_save_reload()
	await _frames(1)
	await _test_plan_input()
	_test_drag_payload_and_drop_status()
	_test_cli_context()

	page.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("TOTAL PASSED: %d  FAILED: %d" % [_passed, _failed])
	quit(_failed)


# ── 用例 ──

func _test_edit_scene_gate() -> void:
	var id: int = layout.placements[0].instance_id
	var inst: GDPlacementData.PlacementInstance = page.find_placement(id)
	var count := layout.placements.size()
	var steps := page.doc._cursor
	page.select_placement(id)
	page.commands.rename_item(Kind.PLACEMENT, id)
	var rename := _last_dialog()
	_check(rename != null, "instance rename opens in the edit scene")
	if rename != null:
		_find_line_edit(rename).text = "Must not rename outside editor"
	page.edit_scene_active = false
	page.on_scene_changed()
	_check(page.selected_placement() == 0 and page._lists[0]._tree.get_selected() == null, "leaving the edit scene clears instance and list selection")
	_check(_vector_spins("位置").is_empty(), "leaving the edit scene removes the instance inspector")
	page.select_placement(id)
	page._lists[0].item_selected.emit(id)
	page._on_plan_picked(GDPlanView.MARK, id)
	_check(page.selected_placement() == 0, "direct, list and plan picks cannot select outside the edit scene")
	page._on_plan_moved(GDPlanView.MARK, id, 0, Vector2(99, 99))
	page.commands.duplicate_item(Kind.PLACEMENT, id)
	page.commands.delete_item(Kind.PLACEMENT, id)
	page.commands.replace_archetype(id, layout.archetypes[1].stable_id)
	page.commands._move_instance(id, 2)
	page.commands.standardize_instance_ids(layout.archetypes[0])
	page._inspector._set_transform(id, Vector3(99, 99, 99), Vector3.ZERO, Vector3.ONE)
	page._inspector._write_override(id, layout.archetypes[0].custom_attributes[0], 99.0)
	if rename != null:
		rename.confirmed.emit()
		rename.hide()
	_check(layout.placements.size() == count and page.find_placement(id) == inst and page.doc._cursor == steps, "commands, plan moves, inspector writes and an already-open rename leave the model and history unchanged outside the edit scene")
	page.commands.rename_item(Kind.PLACEMENT, id)
	page.commands.reset_instance_id(id)
	_check(_last_dialog() == null, "instance dialogs cannot open outside the edit scene")
	page.edit_scene_active = true
	page.on_scene_changed()
	page.select_placement(id)
	_check(page.selected_placement() == id and _vector_spins("位置").size() == 3, "returning to the edit scene enables selection and the inspector")
	page.commands.reset_instance_id(id)
	var reset := _last_dialog()
	_check(reset != null, "reset ID opens in the edit scene")
	if reset != null:
		_find_line_edit(reset).text = "999"
		page.edit_scene_active = false
		page.on_scene_changed()
		reset.confirmed.emit()
		reset.hide()
		_check(page.find_placement(id) == inst and page.find_placement(999) == null and page.doc._cursor == steps, "an already-open reset ID dialog rechecks the edit scene before changing the model")
	page.edit_scene_active = true
	page.on_scene_changed()


func _test_stale_instance_callbacks() -> void:
	var id: int = layout.placements[0].instance_id
	var original := page.find_placement(id)
	page.select_placement(id)
	var stale_position: SpinBox = _vector_spins("位置")[0]
	var stale_name := _row_control("名称") as LineEdit
	var stale_level := _spin_after("等级")
	var stale_height := _spin_after("高度")
	var stale_archetype := _choice("原型")
	page.commands.rename_item(Kind.PLACEMENT, id)
	var rename := _last_dialog()
	if rename != null:
		_find_line_edit(rename).text = "Wrong level callback"
	var replacement := GDSampleFactory.build_level_scene()
	page.set_layout(replacement)
	var target := page.find_placement(id)
	var steps := page.doc._cursor
	# The old form is detached and queued for deletion; callbacks may still arrive this frame.
	stale_position.value = 101.0
	stale_name.text = "Wrong level name"
	stale_name.text_submitted.emit(stale_name.text)
	stale_level.value = 101.0
	stale_height.value = 101.0
	stale_archetype.select(1)
	stale_archetype.item_selected.emit(1)
	page._inspector._set_transform(id, Vector3.ONE * 101.0, Vector3.ZERO, Vector3.ONE, layout)
	page._inspector._write_override(id, layout.archetypes[0].custom_attributes[0], 101.0, layout)
	if rename != null:
		rename.confirmed.emit()
		rename.hide()
	_check(page.find_placement(id) == target and layout.editor_try_get_placement(id).get("inst") == original, "stale fields and dialogs cannot change either level after switching to an asset with the same instance ID")
	_check(page.doc._cursor == steps and not page.doc.dirty, "stale callbacks do not dirty the newly opened document")
	page.set_layout(layout)
	page.select_placement(id)
	_check(page.selected_placement() == id, "switching back restores editable instance selection")


func _test_select_and_edit_position() -> void:
	var id: int = layout.placements[0].instance_id
	page.select_placement(id)
	_check(page.selected_placement() == id, "select_placement selects the instance")
	_check(page._lists[0]._tree.get_selected() != null, "instance row is highlighted")
	_check(plan.marks.filter(func(m: GDPlanView.Mark) -> bool: return m.selected).map(func(m: GDPlanView.Mark) -> int: return m.id) == [id], "plan highlights the selected dot")
	var spins := _vector_spins("位置")
	_check(spins.size() == 3, "inspector shows a position vector")
	spins[0].value = 5.0
	_check(is_equal_approx(page.find_placement(id).position.x, 5.0), "editing position writes the model")
	_check(page.doc.undo_label == "修改位置", "position edit is committed")
	spins[2].value = -2.0
	_check(page.doc.undo_label == "修改位置" and page.doc._cursor == 1, "consecutive position edits merge into one step")
	page.doc.undo()
	_check(page.find_placement(id).position == Vector3.ZERO and is_equal_approx(spins[0].value, 0.0), "undo restores position and the field")
	page.doc.redo()
	_check(page.find_placement(id).position.is_equal_approx(Vector3(5, 0, -2)), "redo reapplies position")


func _test_delete_instance() -> void:
	var id: int = layout.placements[1].instance_id
	page.select_placement(id)
	page._lists[0].delete_requested.emit(id)
	_check(page.find_placement(id) == null and page.selected_placement() == 0, "Delete removes the instance and clears selection")
	page.doc.undo()
	_check(page.find_placement(id) != null, "undo brings the instance back")


func _test_archetypes() -> void:
	var count := layout.archetypes.size()
	page.commands.new_archetype()
	var created: GDArchetypeRes = layout.archetypes[-1]
	_check(layout.archetypes.size() == count + 1 and created.display_name == "新原型_1" and page._archetype == created, "+ creates 新原型_1 and selects it")
	_check(page._form.get_child_count() > 0 and _find_preview() != null, "archetype inspector shows the preview")
	var preview := _find_preview()
	_check(preview != null and preview.size_flags_vertical == Control.SIZE_SHRINK_BEGIN and preview.custom_minimum_size.y == GDLevelInspector.PREVIEW_HEIGHT, "preview has a fixed height")
	var block: GDArchetypeRes = layout.archetypes[0]
	page.commands.duplicate_archetype(block)
	var copy: GDArchetypeRes = layout.archetypes[-1]
	_check(copy != block and copy.stable_id != block.stable_id and copy.display_name == "示例方块 副本" and page._archetype == copy, "duplicate archetype gets a new id and is selected")
	page.commands.rename_archetype(copy)
	var rename_dialog := _last_dialog()
	_check(rename_dialog != null, "rename opens a form")
	rename_dialog.confirmed.emit()
	rename_dialog.hide()
	var uses := layout.editor_count_placements_by_archetype_stable_id(block.stable_id)
	page.commands.delete_archetype(block)
	var dialog := _last_dialog()
	_check(uses > 0 and dialog != null and str(dialog.dialog_text).contains(str(uses)), "deleting a used archetype asks first and states the count")
	dialog.confirmed.emit()
	dialog.hide()
	_check(not layout.archetypes.has(block) and layout.editor_count_placements_by_archetype_stable_id(block.stable_id) == 0, "delete cascades to its instances")
	page.doc.undo()
	_check(layout.archetypes.has(block) and layout.editor_count_placements_by_archetype_stable_id(block.stable_id) == uses, "undo restores archetype and instances")
	page.commands.delete_archetype(created)
	_check(not layout.archetypes.has(created) and _last_dialog() == null, "unused archetype is deleted without a dialog")


func _test_overrides_and_replace() -> void:
	var block: GDArchetypeRes = layout.archetypes[0]
	var inst: GDPlacementData.PlacementInstance = null
	for candidate in layout.placements:
		if candidate.archetype_stable_id == block.stable_id:
			inst = candidate
	var id := inst.instance_id
	page.select_placement(id)
	var height := _spin_after("高度")
	_check(height != null and is_equal_approx(height.value, 1.0), "custom attribute shows the archetype default")
	height.value = 3.5
	_check(is_equal_approx(page.find_placement(id).attribute_overrides.filter(func(o: Variant) -> bool: return o.tag == "block.height")[0].float_value, 3.5), "editing an attribute writes an override")
	var reset := height.get_parent().get_child(height.get_parent().get_child_count() - 1) as Button
	_check(reset != null and not reset.disabled, "overridden attribute offers 恢复默认")
	reset.pressed.emit()
	_check(is_equal_approx(GDLevelInspector._override_value(page.find_placement(id), block.custom_attributes[0]), 1.0) and page.doc.undo_label == "恢复默认值", "恢复默认 writes the default back")
	var beacon: GDArchetypeRes = layout.archetypes[1]
	var row := _choice("原型")
	await _drop_on(row, page._archetype_list.drag_provider.call(beacon))
	_check(page.find_placement(id).archetype_stable_id == beacon.stable_id and page.doc.undo_label == "替换原型", "dropping an archetype on the 原型 row replaces it")
	_check(not GDLevelSceneDrop.is_active() or GDLevelSceneDrop.session.suppress, "drop on the row does not also place into the viewport")
	GDLevelSceneDrop.cancel()
	page.doc.undo()
	_check(page.find_placement(id).archetype_stable_id == block.stable_id, "undo restores the archetype")


func _test_reset_id() -> void:
	var id: int = layout.placements[0].instance_id
	page.select_placement(id)
	page.commands.reset_instance_id(id)
	var dialog := _last_dialog()
	var edit := _find_line_edit(dialog)
	edit.text = "abc"
	edit.text_changed.emit("abc")
	_check(dialog.get_ok_button().disabled, "reset id rejects non-integers")
	edit.text = str(layout.placements[1].instance_id)
	edit.text_changed.emit(edit.text)
	_check(dialog.get_ok_button().disabled, "reset id rejects ids in use")
	edit.text = "777"
	edit.text_changed.emit("777")
	_check(not dialog.get_ok_button().disabled, "reset id accepts a free positive id")
	dialog.confirmed.emit()
	dialog.hide()
	_check(page.find_placement(777) != null and page.find_placement(id) == null and page.selected_placement() == 777, "reset id renames and keeps the selection")
	_check(page.find_placement(777).display_name.contains("777"), "reset id rewrites the id inside the display name")
	page.doc.undo()
	_check(page.find_placement(id) != null, "undo restores the old id")


func _test_paths() -> void:
	page.commands.add_item(Kind.PATH)
	_check(layout.paths.size() == 1 and page._kind == Kind.PATH and page._tabs.current_tab == 1, "+ creates a path, selects it and shows the 路径 tab")
	var pid: int = layout.paths[0].path_id
	_check(page.find_path(pid).knot_count == 2, "new path has a default spline")
	var add_knot := _button("添加节点")
	add_knot.pressed.emit()
	_check(page.find_path(pid).knot_count == 3 and page.doc.undo_label == "添加路径节点", "添加节点 appends a knot")
	var knot_spins := _vector_spins("位置")
	knot_spins[2].value = 4.0
	_check(is_equal_approx(page.find_path(pid).spline.knots[0].position.z, 4.0), "knot position edits write the spline")
	var slider := _find(page._form, func(n: Node) -> bool: return n is HSlider) as HSlider
	slider.value = 0.5
	_check(page.has_probe() and plan.probe is Vector2, "sample slider shows a marker on the plan")
	_check(page.doc.undo_label != "采样预览", "sampling is not committed")
	page.commands.duplicate_item(Kind.PATH, pid)
	_check(layout.paths.size() == 2 and page._id != pid, "Ctrl+D duplicates a path")
	page.commands.delete_item(Kind.PATH, page._id)
	_check(layout.paths.size() == 1, "Delete removes the path")


func _test_cameras() -> void:
	page.commands.add_item(Kind.CAMERA)
	_check(layout.camera_poses.size() == 1 and page._kind == Kind.CAMERA, "记录主相机 adds a pose without an editor viewport")
	var proj := _choice("投影")
	proj.select(1)
	proj.item_selected.emit(1)
	_check(page.find_pose(0).projection == GDCameraPoseSystem.CameraProjectionMode.ORTHOGRAPHIC and _spin_after("最小尺寸") != null, "switching to 正交 rebuilds the form")
	_check(page.find_pose(0).bound_plane == GDCameraPoseSystem.CameraBoundPlane.XY, "orthographic uses the XY bound plane")
	proj = _choice("投影")
	proj.select(0)
	proj.item_selected.emit(0)
	var bound := _toggle("启用边界")
	bound.button_pressed = true
	_check(page.find_pose(0).has_bound and page.find_pose(0).bound_half_extents == GDLevelInspector.DEFAULT_BOUND_HALF, "enabling bounds fills a default bound")
	_check(plan.cameras[0].selected and plan.cameras[0].bound.size() == 4, "plan draws the selected camera bound")
	_spin_after("FOV").value = 42.0
	_check(is_equal_approx(page.find_pose(0).fov, 42.0), "FOV edits the pose")


func _test_save_reload() -> void:
	var pid: int = layout.paths[0].path_id
	var knot := page.find_path(pid).spline.knots[0].position
	_check(page.doc.save(SAVE_PATH) == OK and not page.doc.dirty, "level saves to user://")
	var loaded := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GDLevelSceneRes
	_check(loaded != null and loaded.paths.size() == 1 and loaded.paths[0].knot_count == 3 and loaded.paths[0].spline.knots[0].position.is_equal_approx(knot), "paths and knots survive reload")
	_check(loaded.camera_poses.size() == 1 and is_equal_approx(loaded.camera_poses[0].fov, 42.0) and loaded.camera_poses[0].has_bound, "cameras survive reload")
	_check(loaded.placements.size() == layout.placements.size(), "instances survive reload")


func _test_plan_input() -> void:
	page.select_item(Kind.NONE, 0)
	page.fit_plan()
	var inst: GDPlacementData.PlacementInstance = layout.placements[0]
	var id := inst.instance_id
	var at := plan.to_screen(Vector2(inst.position.x, inst.position.z))
	_mouse(at, MOUSE_BUTTON_LEFT, true)
	_check(page.selected_placement() == id, "pressing on a dot selects it")
	var steps := page.doc._cursor
	_motion(at + Vector2(10, 0))
	_motion(at + Vector2(40, 20))
	var world := plan.to_world(at + Vector2(40, 20))
	_check(is_equal_approx(page.find_placement(id).position.x, world.x) and is_equal_approx(page.find_placement(id).position.z, world.y), "dragging a dot moves the instance live")
	_check(is_equal_approx(page.find_placement(id).position.y, inst.position.y), "dragging keeps Y")
	_check(page.doc._cursor == steps, "nothing is committed while dragging")
	_mouse(at + Vector2(40, 20), MOUSE_BUTTON_LEFT, false)
	_check(page.doc._cursor == steps + 1 and page.doc.undo_label == "移动实例", "release commits one step")
	page.doc.undo()
	_check(page.find_placement(id).position.is_equal_approx(inst.position), "undo puts the dot back")

	var pid: int = layout.paths[0].path_id
	var last := page.find_path(pid).spline.knots[2].position
	var last_at := plan.to_screen(Vector2(last.x, last.z))
	_mouse(last_at, MOUSE_BUTTON_LEFT, true)
	_mouse(last_at, MOUSE_BUTTON_LEFT, false)
	_check(page._kind == Kind.PATH and page._id == pid, "pressing on a knot selects its path")
	# 节点 2 和一个实例重叠：路径选中后，它的节点优先于实例被点中。
	var knot := page.find_path(pid).spline.knots[1].position
	var knot_at := plan.to_screen(Vector2(knot.x, knot.z))
	_check(plan.hit_test(knot_at).kind == GDPlanView.PATH, "selected path knots win over instances underneath")
	_mouse(knot_at, MOUSE_BUTTON_LEFT, true)
	_motion(knot_at + Vector2(6, 0))
	_motion(knot_at + Vector2(30, 0))
	_mouse(knot_at + Vector2(30, 0), MOUSE_BUTTON_LEFT, false)
	_check(page.find_path(pid).spline.knots[1].position.x > knot.x + 0.1 and is_equal_approx(page.find_path(pid).spline.knots[1].position.y, knot.y) and page.doc.undo_label == "移动路径节点", "dragging a knot handle moves that knot")

	var empty := _empty_spot()
	_mouse(empty, MOUSE_BUTTON_LEFT, true)
	_mouse(empty, MOUSE_BUTTON_LEFT, false)
	_check(page._kind == Kind.NONE, "clicking empty space clears the selection")
	_check(_find(page._form, func(n: Node) -> bool: return n is Label and str(n.text).contains("个实例")) != null, "nothing selected shows level info")

	var scale_before := plan._scale
	var anchor := plan.size * 0.5 + Vector2(37, 11)
	var world_before := plan.to_world(anchor)
	_mouse(anchor, MOUSE_BUTTON_WHEEL_UP, true)
	_check(plan._scale > scale_before and plan.to_world(anchor).is_equal_approx(world_before), "wheel zooms about the cursor")
	var pan_before := plan._pan
	_mouse(anchor, MOUSE_BUTTON_MIDDLE, true)
	_motion(anchor + Vector2(25, 5), Vector2(25, 5))
	_mouse(anchor + Vector2(25, 5), MOUSE_BUTTON_MIDDLE, false)
	_check(plan._pan.is_equal_approx(pan_before + Vector2(25, 5)), "middle drag pans")
	var hit_label := plan._get_tooltip(plan.to_screen(Vector2(layout.placements[0].position.x, layout.placements[0].position.z)))
	_check(hit_label == page.placement_title(layout.placements[0]), "hovering a dot shows its name as tooltip")


func _test_drag_payload_and_drop_status() -> void:
	var block: GDArchetypeRes = layout.archetypes[0]
	var payload: Variant = page._archetype_list.drag_provider.call(block)
	_check(GDLevelSceneDrop.is_payload(payload) and int(payload["stable_id"]) == block.stable_id and GDLevelSceneDrop.is_active(), "drag_provider begins a viewport drag with the archetype id")
	GDLevelSceneDrop.cancel()
	var parent := Node3D.new()
	root.add_child(parent)
	var steps := page.doc._cursor
	var placed := GDLevelSceneDrop.place_archetype(layout, block, Vector3(2, 0, 3), parent)
	var id := int(placed["instance_id"])
	_check(page.doc._cursor == steps + 1 and page.doc.undo_label == "摆放原型", "a viewport drop is committed through the status callback")
	GDLevelSceneDrop.erase_placed(layout, id)
	GDLevelSceneDrop.notify_ui("已撤销摆放")
	_check(page.find_placement(id) == null and page.doc._cursor == steps + 2, "editor undo of a drop is recorded too")
	GDLevelSceneDrop.notify_ui("场景里已经有全部实例。")
	_check(page.doc._cursor == steps + 2, "status without a layout change commits nothing")
	parent.free()


func _test_cli_context() -> void:
	_check(page.cli_context("layout.list") == PackedStringArray(["--layout", SAVE_PATH]) or page.cli_context("layout.list").is_empty(), "cli context adds --layout only for res:// files")
	var saved := layout.resource_path
	layout.resource_path = "res://game_res/level/Fake.tres"
	_check(page.cli_context("layout.list") == PackedStringArray(["--layout", "res://game_res/level/Fake.tres"]), "cli context passes --layout for layout.* commands")
	_check(page.cli_context("skill.list").is_empty(), "cli context ignores other commands")
	layout.resource_path = saved


# ── 工具 ──

var _mask: int = 0


func _mouse(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = plan.get_global_rect().position + at
	event.global_position = event.position
	if button <= MOUSE_BUTTON_MIDDLE:
		var bit := 1 << (button - 1)
		_mask = (_mask | bit) if pressed else (_mask & ~bit)
	event.button_mask = _mask
	root.push_input(event)


func _motion(at: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = plan.get_global_rect().position + at
	event.global_position = event.position
	event.relative = relative
	event.button_mask = _mask
	root.push_input(event)


## 走真实的拖放流程：force_drag 发起，鼠标移到目标上松开。
func _drop_on(target: Control, payload: Variant) -> void:
	await _frames(2)
	page._archetype_list.force_drag(payload, null)
	var at := target.get_global_rect().get_center()
	for step in [Vector2(-20, 0), Vector2.ZERO]:
		var motion := InputEventMouseMotion.new()
		motion.position = at + step
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = at
	release.global_position = at
	root.push_input(release)


func _empty_spot() -> Vector2:
	for y in range(20, int(plan.size.y) - 20, 13):
		for x in range(20, int(plan.size.x) - 60, 17):
			if plan.hit_test(Vector2(x, y)) == null:
				return Vector2(x, y)
	return Vector2(5, plan.size.y - 5)


func _find(node: Node, match_fn: Callable) -> Node:
	for child in node.get_children():
		if match_fn.call(child):
			return child
		var found := _find(child, match_fn)
		if found != null:
			return found
	return null


func _find_all(node: Node, match_fn: Callable, out: Array = []) -> Array:
	for child in node.get_children():
		if match_fn.call(child):
			out.append(child)
		_find_all(child, match_fn, out)
	return out


func _caption(node: Node) -> String:
	return str(node.text) if node is Label else ""


## GDForm.vector3：标题 Label 后紧跟一行三个 SpinBox。
func _vector_spins(caption: String) -> Array:
	var label := _find(page._form, func(n: Node) -> bool: return _caption(n) == caption)
	if label == null:
		return []
	var line := label.get_parent().get_child(label.get_index() + 1)
	return line.get_children().filter(func(n: Node) -> bool: return n is SpinBox)


func _row_control(caption: String) -> Control:
	var label := _find(page._form, func(n: Node) -> bool: return _caption(n) == caption and n.get_parent() is HBoxContainer)
	return label.get_parent().get_child(1) if label != null else null


func _spin_after(caption: String) -> SpinBox:
	return _row_control(caption) as SpinBox


func _choice(caption: String) -> OptionButton:
	return _row_control(caption) as OptionButton


func _toggle(caption: String) -> CheckBox:
	return _row_control(caption) as CheckBox


func _button(text: String) -> Button:
	return _find(page._form, func(n: Node) -> bool: return n is Button and n.text == text) as Button


func _find_preview() -> GDArchetypePreviewPanel:
	return _find(page._form, func(n: Node) -> bool: return n is GDArchetypePreviewPanel) as GDArchetypePreviewPanel


func _find_line_edit(dialog: Node) -> LineEdit:
	return _find(dialog, func(n: Node) -> bool: return n is LineEdit) as LineEdit


func _last_dialog() -> ConfirmationDialog:
	var dialogs := page.get_children().filter(func(n: Node) -> bool: return n is ConfirmationDialog and n.visible)
	return dialogs[-1] if not dialogs.is_empty() else null


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: %s" % label)
