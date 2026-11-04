@tool
class_name GDEditorUi
extends RefCounted

## Godot 编辑器控件的布局修正。
## ScrollContainer 在关闭横向滚动且子节点 SIZE_EXPAND_FILL 时，会把子节点拉到视口宽度（Godot 4 的原生行为）。
## 不要把子节点的 custom_minimum_size.x 设成滚动区宽度，否则最小尺寸会反向把父级越撑越宽。
## 工具条如果按按钮最小宽度计入窗口最小尺寸，窄窗口里按钮会被直接裁掉；ToolbarScroll 只报告一条矮高度。


class ToolbarScroll extends ScrollContainer:
	func _init() -> void:
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, 44)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _get_minimum_size() -> Vector2:
		return Vector2(48, 44)


static func clear_children(node: Node) -> void:
	if node == null:
		return
	# 先移出树再排队释放：同一帧里重建列表时，queue_free 的旧节点仍占布局，列表会叠成两份。
	# 不能在按钮回调里立刻 free() 自己，所以用 remove_child + queue_free。
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func configure_vertical_scroll(scroll: ScrollContainer, content: Control = null) -> void:
	if scroll == null:
		return
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target := content
	if target == null and scroll.get_child_count() > 0:
		target = scroll.get_child(0) as Control
	if target == null:
		return
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func wrap_toolbar(bar: HBoxContainer) -> void:
	if bar == null or bar.get_parent() == null:
		return
	if bar.get_parent() is ToolbarScroll:
		return
	var parent := bar.get_parent()
	var idx := bar.get_index()
	parent.remove_child(bar)
	var scroll := ToolbarScroll.new()
	parent.add_child(scroll)
	parent.move_child(scroll, idx)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bar)


static func ensure_split_usable(split: SplitContainer, min_first: int, min_second: int) -> void:
	if split == null or not is_instance_valid(split):
		return
	var vertical := split is VSplitContainer
	var avail := int(split.size.y if vertical else split.size.x)
	if avail <= min_first:
		return
	var max_first := maxi(min_first, avail - min_second)
	var clamped := clampi(split.split_offset, min_first, max_first)
	if clamped != split.split_offset:
		split.split_offset = clamped


static func make_hint(text: String) -> Label:
	var hint := Label.new()
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 1
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return hint


static func editor_color(color_name: String, fallback: Color) -> Color:
	if not Engine.is_editor_hint():
		return fallback
	var base := EditorInterface.get_base_control()
	if base != null and base.theme != null and base.theme.has_color(color_name, "Editor"):
		return base.theme.get_color(color_name, "Editor")
	return fallback


static func flat_box(bg: Color, border: Color, radius: int = 6, border_w: int = 1, pad_x: int = 8, pad_y: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	if border.a > 0.01 and border_w > 0:
		box.set_border_width_all(border_w)
		box.border_color = border
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


static func apply_panel(panel: PanelContainer, pad: int = 10) -> void:
	if panel == null:
		return
	var bg := editor_color("base_color", Color(0.145, 0.15, 0.17)).lerp(Color.WHITE, 0.035)
	panel.add_theme_stylebox_override("panel", flat_box(bg, Color(1, 1, 1, 0.07), 8, 1, pad, pad))


static func style_card(card: PanelContainer, selected: bool) -> void:
	if card == null:
		return
	var bg := editor_color("dark_color_2", Color(0.17, 0.18, 0.21))
	var accent := editor_color("accent_color", Color(0.35, 0.62, 0.95))
	if selected:
		card.add_theme_stylebox_override("panel", flat_box(accent.darkened(0.58), accent, 8, 2, 8, 8))
	else:
		card.add_theme_stylebox_override("panel", flat_box(bg.lightened(0.045), Color(1, 1, 1, 0.08), 8, 1, 8, 8))


static func style_button(btn: Button, kind: String) -> void:
	if btn == null:
		return
	var accent := editor_color("accent_color", Color(0.30, 0.55, 0.95))
	var bg := editor_color("dark_color_2", Color(0.2, 0.21, 0.24))
	var normal := bg
	var hover := bg.lightened(0.1)
	var border := Color(1, 1, 1, 0.1)
	var font := Color(0.9, 0.91, 0.94)
	match kind:
		"primary":
			normal = accent.darkened(0.12)
			hover = accent.lightened(0.06)
			border = accent.lightened(0.15)
			font = Color(0.97, 0.98, 1.0)
		"danger":
			normal = Color(0.55, 0.22, 0.24)
			hover = Color(0.72, 0.28, 0.3)
			border = Color(0.9, 0.42, 0.42)
			font = Color(1.0, 0.94, 0.94)
		"toggle_on":
			normal = accent.darkened(0.22)
			hover = accent.darkened(0.08)
			border = accent
			font = Color(0.97, 0.98, 1.0)
		_:
			pass
	btn.add_theme_stylebox_override("normal", flat_box(normal, border, 5, 1, 10, 3))
	btn.add_theme_stylebox_override("hover", flat_box(hover, border.lightened(0.08), 5, 1, 10, 3))
	btn.add_theme_stylebox_override("pressed", flat_box(normal.darkened(0.12), border, 5, 1, 10, 3))
	btn.add_theme_stylebox_override("focus", flat_box(normal, border.lightened(0.2), 5, 1, 10, 3))
	btn.add_theme_stylebox_override("disabled", flat_box(normal.darkened(0.28), Color(1, 1, 1, 0.05), 5, 1, 10, 3))
	btn.add_theme_color_override("font_color", font)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.38))


static func style_list_button(btn: Button, selected: bool) -> void:
	if btn == null:
		return
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := editor_color("dark_color_2", Color(0.18, 0.19, 0.22))
	var accent := editor_color("accent_color", Color(0.35, 0.62, 0.95))
	if selected:
		btn.add_theme_stylebox_override("normal", flat_box(accent.darkened(0.45), accent, 6, 1, 10, 6))
		btn.add_theme_stylebox_override("hover", flat_box(accent.darkened(0.32), accent.lightened(0.08), 6, 1, 10, 6))
		btn.add_theme_stylebox_override("pressed", flat_box(accent.darkened(0.55), accent, 6, 1, 10, 6))
		btn.add_theme_stylebox_override("focus", flat_box(accent.darkened(0.4), accent, 6, 1, 10, 6))
	else:
		btn.add_theme_stylebox_override("normal", flat_box(bg, Color(1, 1, 1, 0.07), 6, 1, 10, 6))
		btn.add_theme_stylebox_override("hover", flat_box(bg.lightened(0.08), Color(1, 1, 1, 0.16), 6, 1, 10, 6))
		btn.add_theme_stylebox_override("pressed", flat_box(bg.darkened(0.04), accent.darkened(0.15), 6, 1, 10, 6))
		btn.add_theme_stylebox_override("focus", flat_box(bg.lightened(0.04), accent.darkened(0.2), 6, 1, 10, 6))
	btn.add_theme_color_override("font_color", Color(0.94, 0.95, 0.97))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


static func style_context_label(lbl: Label) -> void:
	if lbl == null:
		return
	var accent := editor_color("accent_color", Color(0.55, 0.78, 1.0))
	lbl.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.35))
	lbl.add_theme_font_size_override("font_size", 14)


static func section_title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.clip_text = true
	lbl.custom_minimum_size.x = 1
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))
	return lbl


static func muted(text: String) -> Label:
	var hint := make_hint(text)
	hint.add_theme_color_override("font_color", editor_color("font_placeholder_color", Color(0.64, 0.68, 0.74)))
	hint.add_theme_font_size_override("font_size", 12)
	return hint


static func search_field(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.clear_button_enabled = true
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.y = 30
	return edit


static func fold_button(title: String, count: int, open: bool) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "%s   %s     %d" % ["▾" if open else "▸", title, count]
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 13)
	var accent := editor_color("accent_color", Color(0.45, 0.72, 1.0))
	btn.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.4))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	return btn


static func empty_state(title: String, lines: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent := editor_color("accent_color", Color(0.35, 0.62, 0.95))
	var bg := editor_color("dark_color_1", Color(0.12, 0.13, 0.16))
	panel.add_theme_stylebox_override("panel", flat_box(bg, accent.darkened(0.28), 10, 1, 14, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(section_title(title))
	for i in range(lines.size()):
		box.add_child(muted("%d    %s" % [i + 1, str(lines[i])]))
	return panel


static func matches_query(haystack: String, query: String) -> bool:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return true
	return haystack.to_lower().contains(q)


static func hue_color(seed: int) -> Color:
	var hues: Array[float] = [0.56, 0.12, 0.33, 0.74, 0.02, 0.46, 0.83, 0.22]
	return Color.from_hsv(hues[absi(seed) % hues.size()], 0.52, 0.9)


static func swatch(color: Color, wide: int = 10) -> ColorRect:
	var chip := ColorRect.new()
	chip.color = color
	chip.custom_minimum_size = Vector2(wide, 18)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip


static func icon_button(mark: String, tip: String, kind: String = "quiet") -> Button:
	var btn := Button.new()
	btn.text = mark
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(28, 28)
	var accent := editor_color("accent_color", Color(0.30, 0.55, 0.95))
	var bg := editor_color("dark_color_2", Color(0.2, 0.21, 0.24))
	var normal := bg
	var border := Color(1, 1, 1, 0.12)
	var font := Color(0.92, 0.93, 0.96)
	if kind == "primary":
		normal = accent.darkened(0.12)
		border = accent
		font = Color.WHITE
	elif kind == "danger":
		normal = Color(0.5, 0.2, 0.22)
		border = Color(0.85, 0.38, 0.38)
		font = Color(1, 0.94, 0.94)
	btn.add_theme_stylebox_override("normal", flat_box(normal, border, 5, 1, 2, 2))
	btn.add_theme_stylebox_override("hover", flat_box(normal.lightened(0.1), border.lightened(0.1), 5, 1, 2, 2))
	btn.add_theme_stylebox_override("pressed", flat_box(normal.darkened(0.12), border, 5, 1, 2, 2))
	btn.add_theme_stylebox_override("disabled", flat_box(normal.darkened(0.25), Color(1, 1, 1, 0.05), 5, 1, 2, 2))
	btn.add_theme_color_override("font_color", font)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	return btn


class XZMark extends RefCounted:
	var id: int = 0
	var x: float = 0.0
	var z: float = 0.0
	var color: Color = Color.WHITE
	var label: String = ""
	var selected: bool = false


## 俯视平面图。圆点是实例，单击选中，拖动改 XZ。Y 保持不变。
class XZBoard extends Control:
	signal picked(id: int)
	signal moved(id: int, x: float, z: float)

	var marks: Array = []
	var movable: bool = true
	var _drag_id: int = -1
	var _dragged: bool = false
	var _press: Vector2 = Vector2.ZERO
	var _frozen: Dictionary = {}

	func _init() -> void:
		custom_minimum_size = Vector2(0, 168)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		resized.connect(queue_redraw)

	func _fit() -> Dictionary:
		if not _frozen.is_empty():
			return _frozen
		var min_x := -4.0
		var max_x := 4.0
		var min_z := -4.0
		var max_z := 4.0
		for item in marks:
			var mark := item as XZMark
			if mark == null:
				continue
			min_x = minf(min_x, mark.x)
			max_x = maxf(max_x, mark.x)
			min_z = minf(min_z, mark.z)
			max_z = maxf(max_z, mark.z)
		min_x -= 1.0
		max_x += 1.0
		min_z -= 1.0
		max_z += 1.0
		var span_x := maxf(6.0, max_x - min_x)
		var span_z := maxf(6.0, max_z - min_z)
		var pad := 18.0
		var scale := minf((maxf(40.0, size.x) - pad * 2.0) / span_x, (maxf(40.0, size.y) - pad * 2.0) / span_z)
		return {"min_x": min_x, "min_z": min_z, "scale": scale, "pad": pad}

	func _to_screen(x: float, z: float) -> Vector2:
		var fit := _fit()
		var pad := float(fit["pad"])
		var scale := float(fit["scale"])
		return Vector2(pad + (x - float(fit["min_x"])) * scale, size.y - pad - (z - float(fit["min_z"])) * scale)

	func _to_world(screen: Vector2) -> Vector2:
		var fit := _fit()
		var pad := float(fit["pad"])
		var scale := maxf(0.001, float(fit["scale"]))
		var x := float(fit["min_x"]) + (screen.x - pad) / scale
		var z := float(fit["min_z"]) + (size.y - pad - screen.y) / scale
		return Vector2(x, z)

	func _mark_by_id(id: int) -> XZMark:
		for item in marks:
			var mark := item as XZMark
			if mark != null and mark.id == id:
				return mark
		return null

	func _hit(local_pos: Vector2) -> int:
		var best := -1
		var best_d := 14.0
		for item in marks:
			var mark := item as XZMark
			if mark == null:
				continue
			var dist := local_pos.distance_to(_to_screen(mark.x, mark.z))
			if dist < best_d:
				best_d = dist
				best = mark.id
		return best

	func _draw() -> void:
		var bg := Color(0.09, 0.1, 0.12, 1.0)
		GDEditorUi.paint_round_rect(self, Rect2(Vector2.ZERO, size), bg, Color(1, 1, 1, 0.08), 8, 1)
		var fit := _fit()
		var scale := float(fit["scale"])
		if scale >= 6.0 and scale <= 48.0:
			var origin := _to_screen(0.0, 0.0)
			var grid := Color(1, 1, 1, 0.06)
			var min_x := float(fit["min_x"])
			var min_z := float(fit["min_z"])
			var x := floorf(min_x)
			while x < min_x + (size.x / maxf(0.001, scale)) + 2.0:
				var sx := _to_screen(x, 0.0).x
				draw_line(Vector2(sx, 8), Vector2(sx, size.y - 8), grid, 1.0)
				x += 1.0
			var z := floorf(min_z)
			while z < min_z + (size.y / maxf(0.001, scale)) + 2.0:
				var sy := _to_screen(0.0, z).y
				draw_line(Vector2(8, sy), Vector2(size.x - 8, sy), grid, 1.0)
				z += 1.0
			draw_line(Vector2(origin.x, 8), Vector2(origin.x, size.y - 8), Color(0.45, 0.7, 0.95, 0.35), 1.0)
			draw_line(Vector2(8, origin.y), Vector2(size.x - 8, origin.y), Color(0.45, 0.85, 0.55, 0.35), 1.0)
		var font := get_theme_default_font()
		for item in marks:
			var mark := item as XZMark
			if mark == null:
				continue
			var at := _to_screen(mark.x, mark.z)
			var radius := 8.0 if mark.selected else 5.5
			draw_circle(at, radius, mark.color)
			if mark.selected:
				draw_arc(at, radius + 3.0, 0.0, TAU, 24, Color.WHITE, 1.5)
				if font != null and not mark.label.is_empty():
					font.draw_string(get_canvas_item(), at + Vector2(10, -8), mark.label, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 12, Color(0.95, 0.96, 0.98))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mb.pressed:
				_drag_id = _hit(mb.position)
				_dragged = false
				_press = mb.position
				if _drag_id >= 0:
					_frozen = _fit()
			else:
				if _drag_id >= 0 and _dragged:
					var mark := _mark_by_id(_drag_id)
					if mark != null:
						moved.emit(mark.id, mark.x, mark.z)
				elif _drag_id >= 0:
					picked.emit(_drag_id)
				_drag_id = -1
				_dragged = false
				_frozen = {}
			accept_event()
		elif event is InputEventMouseMotion and _drag_id >= 0 and movable:
			var mm := event as InputEventMouseMotion
			if mm.position.distance_to(_press) > 3.0:
				_dragged = true
			if _dragged:
				var world := _to_world(mm.position)
				var mark := _mark_by_id(_drag_id)
				if mark != null:
					mark.x = world.x
					mark.z = world.y
					mark.selected = true
					queue_redraw()
			accept_event()


static func paint_round_rect(canvas: CanvasItem, rect: Rect2, bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 8, border_w: int = 1) -> void:
	if canvas == null or rect.size.x < 1.0 or rect.size.y < 1.0:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(mini(radius, int(minf(rect.size.x, rect.size.y) * 0.5)))
	if border.a > 0.01 and border_w > 0:
		box.set_border_width_all(border_w)
		box.border_color = border
	box.draw(canvas.get_canvas_item(), rect)
