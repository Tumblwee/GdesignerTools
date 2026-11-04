extends SceneTree

## 技能页的独立测试：真实实例化页面，驱动时间轴输入、撤销、保存与重载。
## 运行：godot --headless --path D:/GodotTemplate -s res://addons/gdesigner_tools/tests/test_skill_page.gd

const ROOT := "user://skill_page_test"

var _passed := 0
var _failed := 0
var page: GDSkillPage = null
var view: GDSkillTimelineView = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_wipe(ROOT)
	GDSkillForge._in_memory_skills.clear()
	page = GDSkillPage.new()
	page.skills_root = ROOT
	root.add_child(page)
	page.position = Vector2.ZERO
	page.size = Vector2(1280, 760)
	view = page._view
	page.refresh_library()
	_check(page.skill == null and page._skills.is_empty(), "empty root shows no skill")

	_test_create_save_reload()
	await _frames(3)
	_test_add_clips()
	await _frames(2)
	_test_drag_move_snap_cancel()
	_test_trim()
	_test_move_across_tracks_and_undo()
	_test_scrub()
	_test_end_marker()
	_test_zoom()
	_test_playback()
	_test_keyboard()
	_test_filtered_menu()
	_test_context_menu()
	_test_inspector()
	await _test_validation()
	_test_rename_duplicate_delete()

	page.queue_free()
	_wipe(ROOT)
	print("TOTAL PASSED: %d  FAILED: %d" % [_passed, _failed])
	quit(_failed)


# ── 用例 ──

func _test_create_save_reload() -> void:
	var created := page.create_skill("Fireball", page._next_id(), "火球")
	var path := ROOT + "/skill/Skill_Fireball_1001.tres"
	_check(created.skill_id == 1001, "new skill gets next free id")
	_check(FileAccess.file_exists(path), "new skill saved immediately to <root>/skill")
	_check(page.skill == created and not page.doc.dirty, "new skill selected and clean")
	_check(created.duration_ms == 1000 and created.groups.size() == 1 and created.groups[0].group_name == "Cast" and created.groups[0].tracks.size() == 1, "new skill: 1000 ms, Cast group, one track")
	_check(page._list._tree.get_root().get_child_count() == 1, "library lists the new skill")


func _test_add_clips() -> void:
	var s := page.skill
	var anim := page.add_clip(0, 0, "PlayAnimation", 100)
	_check(anim.start_ms == 100 and anim.duration_ms == 200, "add clip at given time with default 200 ms")
	_check(page.get_selection() == PackedInt32Array([0, 0, 0]), "new clip selected")
	var hit := page.add_clip(0, 0, "DealDamage")
	_check(hit.start_ms == 0 and hit.duration_ms == 0, "instant clip lands at playhead with 0 ms")
	page.add_track(0, GDSkillTypes.SkillTrackKind.EFFECT)
	_check(s.groups[0].tracks.size() == 2 and page.get_selection() == PackedInt32Array([0, 1]), "add track selects it")
	_check(page.doc.dirty and page.is_dirty(), "edits make the document dirty")
	page.save_current()
	_check(not page.doc.dirty, "save clears dirty")
	var reloaded := ResourceLoader.load(s.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDSkillRes
	_check(reloaded != null and reloaded.groups[0].tracks.size() == 2 and reloaded.groups[0].tracks[0].clips.size() == 2, "reload keeps tracks and clips")
	_check(reloaded.groups[0].tracks[0].clips[0].start_ms == 100 and reloaded.groups[0].tracks[0].clips[0] is GDSkillClips.PlayAnimationClip, "reload keeps clip type and timing")
	GDSkillForge._in_memory_skills.clear()
	var known := GDSkillForge.get_all_known_skills(ROOT).map(func(k: GDSkillRes) -> String: return k.unique_name)
	_check(known.has("Skill_Fireball_1001"), "get_all_known_skills finds saved skills without the in-memory registry")
	var default_known := GDSkillForge.get_all_known_skills()
	_check(default_known is Array, "get_all_known_skills defaults to the module root")
	GDSkillForge.register_in_memory_skill(s)


func _test_drag_move_snap_cancel() -> void:
	var clip := _clip(0, 0, 0)
	view.pixels_per_ms = 0.5
	view.refresh()
	var steps := page.doc._cursor
	var box := view.clip_rect(PackedInt32Array([0, 0, 0]))
	_check(box.size.x == 100.0, "clip drawn 200 ms * 0.5 px/ms wide")
	var from := box.get_center()
	_drag(from, from + Vector2(37, 0))
	_check(clip.start_ms == 170, "drag moves start and snaps to the 10 ms grid (got %d)" % clip.start_ms)
	_check(page.doc._cursor == steps + 1 and page.doc.undo_label == "移动片段", "one commit per drag")

	view.set_playhead(400.0)
	from = view.clip_rect(PackedInt32Array([0, 0, 0])).get_center()
	_drag(from, from + Vector2((398 - 170) * 0.5, 0))
	_check(clip.start_ms == 400, "start snaps to the playhead within 6 px (got %d)" % clip.start_ms)

	from = view.clip_rect(PackedInt32Array([0, 0, 0])).get_center()
	_drag(from, from + Vector2(-11.5, 0), true)
	_check(clip.start_ms == 377, "Shift disables snapping (got %d)" % clip.start_ms)

	steps = page.doc._cursor
	from = view.clip_rect(PackedInt32Array([0, 0, 0])).get_center()
	_press(from)
	_motion(from + Vector2(60, 0))
	_key(KEY_ESCAPE)
	_release(from + Vector2(60, 0))
	_check(clip.start_ms == 377 and page.doc._cursor == steps, "Esc cancels a drag without committing")

	from = view.clip_rect(PackedInt32Array([0, 0, 0])).get_center()
	_drag(from, from + Vector2(2000, 0))
	_check(clip.start_ms == 800, "move clamps so the clip ends at the skill duration")
	page.doc.undo()
	_clip(0, 0, 0).set_timing(100, 200)
	page.doc.commit("测试复位")


func _test_trim() -> void:
	var box := view.clip_rect(PackedInt32Array([0, 0, 0]))
	view.set_playhead(0.0)
	_drag(Vector2(box.end.x - 2, box.get_center().y), Vector2(box.end.x - 2 + 52, box.get_center().y))
	_check(_clip(0, 0, 0).duration_ms == 300, "right edge trim extends duration (got %d)" % _clip(0, 0, 0).duration_ms)
	box = view.clip_rect(PackedInt32Array([0, 0, 0]))
	_drag(Vector2(box.position.x + 2, box.get_center().y), Vector2(box.position.x + 2 + 50, box.get_center().y))
	_check(_clip(0, 0, 0).start_ms == 200 and _clip(0, 0, 0).duration_ms == 200, "left edge trim keeps the end fixed")
	box = view.clip_rect(PackedInt32Array([0, 0, 0]))
	_drag(Vector2(box.end.x - 2, box.get_center().y), Vector2(box.end.x + 5000, box.get_center().y))
	_check(_clip(0, 0, 0).start_ms + _clip(0, 0, 0).duration_ms == 1000, "trim clamps at the skill duration")
	_check(page.doc.undo_label == "调整片段时长", "trim commits with its own label")
	page.doc.undo()


func _test_move_across_tracks_and_undo() -> void:
	var s := page.skill
	var from := view.clip_rect(PackedInt32Array([0, 0, 0])).get_center()
	var target_y := view.row_rect(PackedInt32Array([0, 1])).get_center().y
	_drag(from, Vector2(from.x, target_y))
	_check(s.groups[0].tracks[1].clips.size() == 1 and s.groups[0].tracks[0].clips.size() == 1, "vertical drag moves clip to another track")
	_check(page.get_selection() == PackedInt32Array([0, 1, 0]), "selection follows the moved clip")
	page.doc.undo()
	_check(s.groups[0].tracks[0].clips.size() == 2 and s.groups[0].tracks[1].clips.is_empty(), "undo restores the clip to its track")
	page.doc.redo()
	_check(s.groups[0].tracks[1].clips.size() == 1, "redo moves it again")
	page.doc.undo()

	page.select_path(PackedInt32Array([0, 0, 0]))
	var before := _clip(0, 0, 0)
	from = view.clip_rect(PackedInt32Array([0, 0, 0])).get_center()
	_drag(from, from + Vector2(50, 0))
	page.doc.undo()
	var after := _clip(0, 0, 0)
	_check(after != before, "undo rebuilds clip objects")
	_check(page.get_selection() == PackedInt32Array([0, 0, 0]) and after.start_ms == 200, "selection path survives undo")
	_check(page._inspector.form._key is Array and page._inspector.form._key[0] == after, "inspector rebinds to the rebuilt clip")
	page.doc.undo()
	page.doc.redo()
	_check(_clip(0, 0, 0).start_ms == 200, "redo restores the reset state")


func _test_scrub() -> void:
	_press(Vector2(view.ms_to_x(300), 10))
	_check(is_equal_approx(page.get_playhead(), 300.0), "pressing the ruler moves the playhead")
	_motion(Vector2(view.ms_to_x(450), 10))
	_check(is_equal_approx(page.get_playhead(), 450.0), "dragging keeps scrubbing")
	_motion(Vector2(view.ms_to_x(5000), 10))
	_check(is_equal_approx(page.get_playhead(), 1000.0), "scrub clamps at the duration")
	_release(Vector2(view.ms_to_x(5000), 10))
	_check(page._time_label.text == "1.00 s / 1.00 s", "time read-out follows the playhead")
	page.stop()


func _test_end_marker() -> void:
	var s := page.skill
	view.pixels_per_ms = 0.4
	view.refresh()
	var steps := page.doc._cursor
	var end_x := view.ms_to_x(1000)
	_drag(Vector2(end_x, 12), Vector2(view.ms_to_x(1503), 12))
	_check(s.duration_ms == 1500, "end marker drag sets duration (got %d)" % s.duration_ms)
	_check(page.doc._cursor == steps + 1 and page.doc.undo_label == "修改总时长", "end marker commits once")
	_drag(Vector2(view.ms_to_x(1500), 12), Vector2(view.ms_to_x(50), 12))
	_check(s.duration_ms == 400, "end marker cannot cut clips off (got %d)" % s.duration_ms)
	page.doc.undo()
	page.doc.undo()
	_check(s.duration_ms == 1000, "undo restores duration")


func _test_zoom() -> void:
	view.fit()
	var end_x := view.ms_to_x(page.skill.duration_ms)
	_check(end_x > view.size.x * 0.6 and end_x < view.size.x, "fit shows the whole skill")
	var anchor := view.ms_to_x(500)
	var ppm := view.pixels_per_ms
	view.zoom_by(2.0, anchor)
	_check(is_equal_approx(view.pixels_per_ms, ppm * 2.0), "zoom doubles pixels per ms")
	_check(absf(view.x_to_ms(anchor) - 500.0) < 0.5, "zoom keeps the time under the cursor")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.ctrl_pressed = true
	wheel.position = Vector2(anchor, 60)
	view._gui_input(wheel)
	_check(view.pixels_per_ms < ppm * 2.0 and absf(view.x_to_ms(anchor) - 500.0) < 0.5, "Ctrl+wheel zooms about the cursor")
	view.zoom_by(1000.0)
	_check(view.pixels_per_ms == GDSkillTimelineView.MAX_PPM, "zoom is clamped")
	view.fit()


func _test_playback() -> void:
	var clock := GDSkillTypes.SkillClock.now_seconds
	page.stop()
	page.toggle_play()
	_check(page.is_playing() and page.is_processing(), "play starts processing")
	page._process(0.25)
	_check(is_equal_approx(page.get_playhead(), 250.0), "playhead advances with time")
	_check(view.show_fired and view.playhead_ms == 250.0, "view renders fired clips during preview")
	page.toggle_play()
	_check(not page.is_playing() and not page.is_processing() and is_equal_approx(page.get_playhead(), 250.0), "pause keeps the playhead where it is")
	page.toggle_play()
	page._process(5.0)
	_check(not page.is_playing() and is_equal_approx(page.get_playhead(), 1000.0), "playback stops at the end")
	page.toggle_play()
	_check(page.is_playing() and page.get_playhead() == 0.0, "play at the end restarts")
	page.stop()
	_check(not page.is_playing() and page.get_playhead() == 0.0 and not view.show_fired, "stop returns to 0")
	_check(GDSkillTypes.SkillClock.now_seconds == clock, "preview leaves SkillClock alone")


func _test_keyboard() -> void:
	var track: GDSkillRes.SkillTrack = page.skill.groups[0].tracks[0]
	var count := track.clips.size()
	_press(view.clip_rect(PackedInt32Array([0, 0, 0])).get_center())
	_release(view.clip_rect(PackedInt32Array([0, 0, 0])).get_center())
	_check(page.get_selection() == PackedInt32Array([0, 0, 0]) and view.has_focus(), "click selects the clip and focuses the view")
	var start := _clip(0, 0, 0).start_ms
	_key(KEY_RIGHT)
	_key(KEY_RIGHT, false, true)
	_check(_clip(0, 0, 0).start_ms == start + 110, "arrow keys nudge 10 ms, Shift 100 ms")
	_key(KEY_D, true)
	_check(track.clips.size() == count + 1 and page.get_selection() == PackedInt32Array([0, 0, 1]), "Ctrl+D duplicates the clip")
	_key(KEY_DELETE)
	_check(track.clips.size() == count and page.get_selection() == PackedInt32Array([0, 0]), "Delete removes the selected clip")
	page.doc.undo()
	_check(page.skill.groups[0].tracks[0].clips.size() == count + 1, "undo brings the deleted clip back")
	page.doc.undo()
	page.doc.undo()
	_key(KEY_END)
	_check(page.get_playhead() == page.skill.duration_ms, "End moves the playhead to the end")
	_key(KEY_HOME)
	_check(page.get_playhead() == 0.0, "Home moves the playhead to 0")


func _test_filtered_menu() -> void:
	var items := page.clip_menu_items(0, 0, 0)
	_check(items[0]["text"] == "播放动画" and items[1] == null and items[2]["text"] == "其他", "animation track recommends PlayAnimation first")
	_check(items[2]["items"].size() == GDSkillForge.clip_types().size() - 1, "other clip types under 其他")
	var hitbox := GDSkillForge.clip_types_for_kind(GDSkillTypes.SkillTrackKind.HITBOX)
	_check(hitbox.has("CheckHit") and hitbox.has("SpawnProjectile") and not hitbox.has("PlaySfx"), "clip type to track kind mapping")
	var menu := PopupMenu.new()
	GDEditorUi.fill_menu(menu, items)
	_check(menu.item_count == 3 and menu.is_item_separator(1), "menu shows recommended, separator, submenu")
	menu.free()

	var row := view.row_rect(PackedInt32Array([0, 1]))
	var at := Vector2(view.ms_to_x(600), row.get_center().y)
	var count := _menus().size()
	_press(at)
	_release(at)
	_press(at, true)
	_release(at)
	var popups := _menus()
	_check(popups.size() == count + 1, "double-click on empty track area opens the add-clip menu")
	var popup: PopupMenu = popups.back()
	var effect_types := GDSkillForge.clip_types_for_kind(GDSkillTypes.SkillTrackKind.EFFECT)
	_check(popup.get_item_text(0) == GDSkillForge.get_display_name(effect_types[0]) and popup.get_item_text(effect_types.size() + 1) == "其他", "effect track menu lists effect clips first")
	popup.id_pressed.emit(popup.get_item_id(0))
	var added := _clip(0, 1, 0)
	_check(added.get_clip_short_name() == effect_types[0] and added.start_ms == 600, "menu adds the clip at the clicked time")
	_check(page.get_selection() == PackedInt32Array([0, 1, 0]), "added clip is selected")
	popup.hide()


func _test_context_menu() -> void:
	var count := _menus().size()
	var at := view.clip_rect(PackedInt32Array([0, 1, 0])).get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = at
	view._gui_input(press)
	var popup: PopupMenu = _menus().back()
	_check(_menus().size() == count + 1 and popup.item_count == 2 and popup.get_item_text(0) == "复制", "right-click on a clip offers 复制 / 删除")
	popup.hide()
	press.position = Vector2(20, view.row_rect(PackedInt32Array([0, 0])).get_center().y)
	view._gui_input(press)
	popup = _menus().back()
	_check(popup.get_item_text(0) == "添加片段" and popup.get_item_submenu_node(0) != null, "track menu has 添加片段 submenu")
	popup.hide()
	press.position = Vector2(600, view.size.y - 30)
	view._gui_input(press)
	popup = _menus().back()
	_check(popup.get_item_text(0) == "添加组" and page.get_selection().is_empty(), "empty area menu offers 添加组")
	popup.id_pressed.emit(popup.get_item_id(0))
	_check(page.skill.groups.size() == 2 and page.get_selection() == PackedInt32Array([1]), "添加组 adds and selects a group")
	page.doc.undo()


func _test_inspector() -> void:
	page.select_path(PackedInt32Array())
	_check(page._inspector.form._key == [page.skill, &"header"], "nothing selected shows the skill header")
	var cam := page.add_clip(0, 1, "CameraEffect", 0) as GDSkillClips.CameraEffectClip
	_check(page._inspector.form._key == [cam, cam.mode], "camera inspector key includes the mode")
	var labels := _form_labels()
	_check(labels.has("推拉程度") and not labels.has("振幅"), "push mode hides shake fields")
	cam.mode = GDSkillTypes.SkillCameraEffectMode.SHAKE
	page.doc.commit("修改模式")
	labels = _form_labels()
	_check(labels.has("振幅") and not labels.has("推拉程度"), "shake mode shows only shake fields")
	page.doc.undo()
	page.doc.undo()
	var projectile := page.add_clip(0, 1, "SpawnProjectile", 0) as GDSkillClips.SpawnProjectileClip
	_check(_form_labels().has("轨迹"), "projectile inspector has 轨迹")
	projectile.trajectory = GDSkillClips.ParabolaTrajectory.new()
	page.doc.commit("修改轨迹")
	_check(_form_labels().has("弧高"), "parabola shows its fields")
	page.doc.undo()
	page.doc.undo()

	var clip := _clip(0, 0, 0)
	page.select_path(PackedInt32Array([0, 0, 0]))
	var start_spin := _form_control("起始") as SpinBox
	start_spin.value = 5000
	_check(_clip(0, 0, 0).start_ms + _clip(0, 0, 0).duration_ms <= page.skill.duration_ms, "inspector start is clamped")
	page.doc.undo()
	_check(clip != null, "inspector edit commits through the document")


func _test_validation() -> void:
	_check(page._badge.text == "✓ 校验通过", "badge shows a passing skill")
	page.add_clip(0, 1, "ApplyEffect", 300)
	_check(page._badge.text == "✕ 1 个问题", "badge counts issues")
	page._badge.pressed.emit()
	_check(page._issues_tree.visible, "badge toggles the issues panel")
	page.select_path(PackedInt32Array())
	var item := page._issues_tree.get_root().get_first_child()
	item.select(0)
	await process_frame
	_check(page.get_selection() == PackedInt32Array([0, 1, 1]), "clicking an issue selects its clip")
	page._badge.pressed.emit()
	page.doc.undo()


func _test_rename_duplicate_delete() -> void:
	var s := page.skill
	var old_path := s.resource_path
	page.rename_skill(s, "Meteor", 1001, "流星")
	_check(s.resource_path == ROOT + "/skill/Skill_Meteor_1001.tres" and FileAccess.file_exists(s.resource_path), "rename saves to the new file")
	_check(not FileAccess.file_exists(old_path), "rename moves the old file away")
	_check(page.identity_error(null, "Meteor", "1001") != "", "taken identity is rejected")
	_check(page.identity_error(null, "9bad", "1") != "" and page.identity_error(null, "Good", "x") != "", "invalid identity is rejected")
	var copy := page.duplicate_skill(s)
	_check(copy.skill_id == 1002 and FileAccess.file_exists(copy.resource_path) and page.skill == copy, "duplicate gets next id, is saved and selected")
	_check(copy.groups[0].tracks[0].clips.size() == s.groups[0].tracks[0].clips.size() and copy.groups[0] != s.groups[0], "duplicate deep-copies tracks")
	var copy_path := copy.resource_path
	page.delete_skill_from_disk(copy)
	_check(not FileAccess.file_exists(copy_path), "delete removes the file")
	_check(page.skill == s and page._skills.size() == 1, "delete selects a remaining skill")
	_check(not GDSkillForge.get_all_known_skills(ROOT).has(copy), "deleted skill is no longer known")
	page.refresh_library()
	_check(page._skills.size() == 1, "refresh after rename lists each skill once")


# ── 工具 ──

func _clip(g: int, t: int, c: int) -> GDSkillClips.SkillClip:
	return page.skill.groups[g].tracks[t].clips[c]


func _press(at: Vector2, double_click: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = double_click
	ev.position = at
	view._gui_input(ev)


func _release(at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = at
	view._gui_input(ev)


func _motion(at: Vector2, shift: bool = false) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.shift_pressed = shift
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(ev)


func _drag(from: Vector2, to: Vector2, shift: bool = false) -> void:
	_press(from)
	_motion(from.lerp(to, 0.5), shift)
	_motion(to, shift)
	_release(to)


func _key(keycode: Key, ctrl: bool = false, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	view._gui_input(ev)


func _menus() -> Array:
	return page.get_children().filter(func(n: Node) -> bool: return n is PopupMenu and not n.is_queued_for_deletion())


func _form_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for node in page._inspector.form.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
	return labels


func _form_control(label: String) -> Control:
	for node in page._inspector.form.find_children("*", "Label", true, false):
		if (node as Label).text == label:
			var line := node.get_parent()
			return line.get_child(1) as Control
	return null


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: %s" % label)


static func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_wipe(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
