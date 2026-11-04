@tool
class_name GDEditorUi
extends RefCounted

## 设计系统：所有页面共用的令牌和控件工厂。
##
## 三条规则：
## 1. 颜色只从 tone() 取。它跟随编辑器主题，亮色和暗色主题下都可读。
## 2. 按钮默认用原生样式，不逐个覆写 StyleBox。整页只有主操作用强调色。
## 3. 图标优先用编辑器内置图标；没有编辑器（测试、运行时）时退回文字符号。

const GAP := 6
const PAD := 8
const ROW_HEIGHT := 26

## 没有编辑器主题时的兜底符号。
const GLYPHS := {
	&"Add": "+", &"Remove": "×", &"Save": "存", &"UndoRedo": "↶", &"Redo": "↷", &"Reload": "⟳",
	&"Play": "▶", &"Pause": "Ⅱ", &"Stop": "■", &"Search": "⌕", &"Close": "×", &"Duplicate": "⧉",
	&"Rename": "✎", &"Tools": "⋯", &"GuiTabMenuHl": "⋯", &"Terminal": ">_", &"ZoomLess": "−", &"ZoomMore": "+",
	&"ZoomReset": "1:1", &"CenterView": "⛶", &"GridLayout": "▦", &"Load": "开", &"New": "新",
	&"MoveUp": "↑", &"MoveDown": "↓", &"Filesystem": "▣", &"Debug": "◎", &"DebugStep": "↳", &"DebugSkipBreakpointsOff": "⇥",
	&"StatusError": "✕", &"StatusWarning": "!", &"StatusSuccess": "✓",
	&"Snap": "∩",
	&"DebugNext": "⇥", &"ArrowRight": "→",
}

static var _palette: Dictionary = {}


## 编辑器主题变化时调用，下次取色重新计算。
static func invalidate_theme() -> void:
	_palette.clear()


## 语义色：surface raised sunken border text muted accent on_accent danger warn ok
static func tone(token: StringName) -> Color:
	if _palette.is_empty():
		_palette = _build_palette()
	return _palette.get(token, Color.MAGENTA)


static func is_dark_theme() -> bool:
	return tone(&"surface").get_luminance() < 0.5


static func _build_palette() -> Dictionary:
	var theme := _editor_theme()
	var pick := func(color_name: StringName, fallback: Color) -> Color:
		return theme.get_color(color_name, &"Editor") if theme != null and theme.has_color(color_name, &"Editor") else fallback
	var surface: Color = pick.call(&"base_color", Color(0.15, 0.16, 0.18))
	var text: Color = pick.call(&"font_color", Color(0.88, 0.89, 0.91))
	var accent: Color = pick.call(&"accent_color", Color(0.36, 0.6, 0.95))
	var dark := surface.get_luminance() < 0.5
	return {
		&"surface": surface,
		&"raised": surface.lerp(text, 0.05),
		&"sunken": surface.lerp(Color.BLACK if dark else Color.WHITE, 0.28),
		&"border": Color(text, 0.14),
		&"text": text,
		&"muted": Color(text, 0.62),
		&"accent": accent,
		&"on_accent": Color.WHITE if accent.get_luminance() < 0.62 else Color.BLACK,
		&"danger": pick.call(&"error_color", Color(0.93, 0.36, 0.36)),
		&"warn": pick.call(&"warning_color", Color(0.95, 0.72, 0.28)),
		&"ok": pick.call(&"success_color", Color(0.38, 0.8, 0.5)),
	}


static func _editor_theme() -> Theme:
	return EditorInterface.get_editor_theme() if Engine.is_editor_hint() else null


static func icon(icon_name: StringName) -> Texture2D:
	var theme := _editor_theme()
	return theme.get_icon(icon_name, &"EditorIcons") if theme != null and theme.has_icon(icon_name, &"EditorIcons") else null


static func key(keycode: Key, ctrl: bool = false, shift: bool = false) -> Shortcut:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.command_or_control_autoremap = ctrl
	event.shift_pressed = shift
	var shortcut := Shortcut.new()
	shortcut.events = [event]
	return shortcut


static func spacer() -> Control:
	var control := Control.new()
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control


static func title_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.custom_minimum_size.x = 1
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", tone(&"text"))
	return label


static func muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", tone(&"muted"))
	return label


## 可换行的说明文字。
static func hint_label(text: String) -> Label:
	var label := muted_label(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 1
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## 工具栏上的扁平图标按钮。tip 里不用写快捷键，原生 tooltip 会带上。
static func tool_button(icon_name: StringName, tip: String, on_pressed: Callable, shortcut: Shortcut = null) -> Button:
	var btn := Button.new()
	btn.theme_type_variation = &"FlatButton"
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = tip
	btn.shortcut = shortcut
	_apply_icon(btn, icon_name)
	btn.pressed.connect(on_pressed)
	return btn


## kind: normal / flat（工具栏上用）/ primary / danger
static func text_button(text: String, on_pressed: Callable, kind: StringName = &"normal", icon_name: StringName = &"") -> Button:
	var btn := Button.new()
	btn.text = text
	if not icon_name.is_empty() and icon(icon_name) != null:
		btn.icon = icon(icon_name)
	btn.pressed.connect(on_pressed)
	style_kind(btn, kind)
	return btn


static func style_kind(btn: BaseButton, kind: StringName) -> void:
	match kind:
		&"flat":
			btn.theme_type_variation = &"FlatButton"
			btn.focus_mode = Control.FOCUS_NONE
		&"primary":
			var accent := tone(&"accent")
			var make := func(color: Color) -> StyleBoxFlat: return flat_box(color, Color(0, 0, 0, 0), 3, 0, 10, 4)
			btn.add_theme_stylebox_override("normal", make.call(accent))
			btn.add_theme_stylebox_override("hover", make.call(accent.lightened(0.1)))
			btn.add_theme_stylebox_override("pressed", make.call(accent.darkened(0.12)))
			btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				btn.add_theme_color_override(state, tone(&"on_accent"))
		&"danger":
			for state in ["font_color", "font_hover_color", "font_pressed_color"]:
				btn.add_theme_color_override(state, tone(&"danger"))


## items: [{"text", "do": Callable, "icon"?, "shortcut"?, "disabled"?}, 或 null 表示分隔线]
## {"text", "items": [...]} 是子菜单。
static func menu_button(text: String, icon_name: StringName, tip: String, items: Array) -> MenuButton:
	var btn := MenuButton.new()
	btn.flat = true
	btn.text = text
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	if not icon_name.is_empty():
		_apply_icon(btn, icon_name)
	fill_menu(btn.get_popup(), items)
	return btn


static func fill_menu(popup: PopupMenu, items: Array) -> void:
	popup.clear()
	for old_submenu in popup.get_children():
		if old_submenu is PopupMenu:
			old_submenu.queue_free()
	for handler_conn: Dictionary in popup.id_pressed.get_connections():
		popup.id_pressed.disconnect(handler_conn["callable"])
	var handlers: Array[Callable] = []
	for entry: Variant in items:
		if entry == null:
			popup.add_separator()
			continue
		if entry.has("items"):
			var submenu := PopupMenu.new()
			fill_menu(submenu, entry["items"])
			popup.add_submenu_node_item(str(entry["text"]), submenu, 100000 + popup.item_count)
			continue
		var id := handlers.size()
		handlers.append(entry["do"])
		var tex := icon(entry.get("icon", &"")) if entry.has("icon") else null
		if tex != null:
			popup.add_icon_item(tex, str(entry["text"]), id)
		else:
			popup.add_item(str(entry["text"]), id)
		var index := popup.get_item_index(id)
		if entry.get("shortcut") != null:
			popup.set_item_shortcut(index, entry["shortcut"])
		popup.set_item_disabled(index, bool(entry.get("disabled", false)))
	popup.id_pressed.connect(func(id: int) -> void: handlers[id].call())


## 在鼠标位置弹出一次性右键菜单。
static func context_menu(host: Control, items: Array) -> PopupMenu:
	var popup := PopupMenu.new()
	fill_menu(popup, items)
	host.add_child(popup)
	popup.popup_hide.connect(popup.queue_free, CONNECT_DEFERRED)
	popup.popup(Rect2i(Vector2i(host.get_screen_position() + host.get_local_mouse_position()), Vector2i.ZERO))
	return popup


## 一句说明 + 一个主操作。不写操作手册。
static func empty_state(title: String, hint: String = "", action_text: String = "", on_action: Callable = Callable()) -> Control:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", GAP)
	box.custom_minimum_size.x = 200
	center.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	if not hint.is_empty():
		var line := hint_label(hint)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)
	if not action_text.is_empty():
		var action := text_button(action_text, on_action, &"primary")
		action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(action)
	return center


## 工作区面板：带内边距的底板。
static func pane(content: Control, padding: int = PAD) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", flat_box(tone(&"raised"), Color(0, 0, 0, 0), 3, 0, padding, padding))
	panel.add_child(content)
	return panel


## 竖向滚动区，内容撑满宽度。
static func scroll_of(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	configure_vertical_scroll(scroll, content)
	return scroll


static func _apply_icon(btn: Button, icon_name: StringName) -> void:
	var tex := icon(icon_name)
	if tex != null:
		btn.icon = tex
	elif btn.text.is_empty():
		btn.text = str(GLYPHS.get(icon_name, String(icon_name).left(1)))


class ToolbarScroll extends ScrollContainer:
	func _init() -> void:
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, 30)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _get_minimum_size() -> Vector2:
		return Vector2(48, 30)


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


static func search_field(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.clear_button_enabled = true
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.y = 30
	return edit


static func matches_query(haystack: String, query: String) -> bool:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return true
	return haystack.to_lower().contains(q)


static func hue_color(seed: int) -> Color:
	var hues: Array[float] = [0.56, 0.12, 0.33, 0.74, 0.02, 0.46, 0.83, 0.22]
	return Color.from_hsv(hues[absi(seed) % hues.size()], 0.52, 0.9)


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
