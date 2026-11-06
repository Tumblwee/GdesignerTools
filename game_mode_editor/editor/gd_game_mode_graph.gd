@tool
class_name GDGameModeGraph
extends GraphEdit

## Configuration has no authored edges. Monitoring draws observed transitions only.
signal picked(state_key: String, module_id: int)
signal source_requested(module_id: int)
signal positions_changed(positions: Dictionary)
signal layout_requested
signal default_state_requested(state_key: String)
signal module_create_requested(state_key: String)
signal module_add_requested(state_key: String)

var layout_enabled := false

var _nodes: Dictionary = {}
var _edges: Array = []
var _labels: Control
var _building := false
var _readonly := false
var _default_state_key := ""


func _init() -> void:

	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(280, 220)
	show_arrange_button = false
	minimap_enabled = false
	right_disconnects = false
	node_selected.connect(_selected)
	end_node_move.connect(_moved)
	popup_request.connect(_show_context_menu)
	_labels = Control.new()
	_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_labels.draw.connect(_draw_labels)
	add_child(_labels)
	scroll_offset_changed.connect(func(_offset: Vector2) -> void: _labels.queue_redraw())


func _show_context_menu(at: Vector2) -> void:
	var items: Array = []
	var key := _node_key_at(at)
	if key == "@global" or (not key.is_empty() and not key.begins_with("@")):
		items.append_array([
			{"text": "新建模块…", "do": module_create_requested.emit.bind(key), "disabled": not layout_enabled or _readonly},
			{"text": "添加已有模块…", "do": module_add_requested.emit.bind(key), "disabled": not layout_enabled or _readonly},
			null,
		])
	if not key.is_empty() and not key.begins_with("@"):
		var is_default := key == _default_state_key
		items.append({
			"text": "已是默认状态" if is_default else "设为默认状态",
			"do": default_state_requested.emit.bind(key),
			"disabled": is_default or not layout_enabled or _readonly,
		})
		items.append(null)
	items.append_array([
		{"text": "整理", "do": layout_requested.emit, "disabled": not layout_enabled or _readonly},
		{"text": "适配", "do": frame_all, "disabled": _nodes.is_empty()},
	])
	GDEditorUi.context_menu(self, items)


func _node_context_input(event: InputEvent, control: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var canvas_position: Vector2 = control.get_global_transform_with_canvas() * event.position
		_show_context_menu(get_global_transform_with_canvas().affine_inverse() * canvas_position)
		control.accept_event()


func _node_key_at(at: Vector2) -> String:
	var canvas_position := get_global_transform_with_canvas() * at
	var children := get_children()
	children.reverse()
	for child: Node in children:
		if child is GraphNode and child.is_visible_in_tree() and child.has_meta("state_key"):
			var local_position: Vector2 = child.get_global_transform_with_canvas().affine_inverse() * canvas_position
			if Rect2(Vector2.ZERO, child.size).has_point(local_position):
				return str(child.get_meta("state_key"))
	return ""


func display(states: Array, global_modules: Array, transitions: Array, current: String, readonly: bool, global_position_value: Vector2 = Vector2(40, 40), global_issues: int = 0, default_state_key: String = "") -> void:
	_building = true
	_readonly = readonly
	_default_state_key = default_state_key
	clear_connections()
	for node: GraphNode in _nodes.values():
		remove_child(node)
		node.queue_free()
	_nodes.clear()
	_edges = transitions.duplicate(true)
	_add_node("@global", "全局模块", global_modules, global_position_value, false, global_issues)
	for index in range(states.size()):
		var state: Dictionary = states[index]
		var key := str(state.get("key", ""))
		_add_node(key, "%s  [%s]" % [state.get("display_name", key), key], state.get("modules", []), state.get("position", Vector2(340 + (index % 3) * 290, 40 + (index / 3) * 230)), key == current, int(state.get("issues", 0)))
	var latest_sequence := -1
	for edge: Dictionary in _edges:
		latest_sequence = maxi(latest_sequence, int(edge.get("last_sequence", edge.get("frame", -1))))
	for edge: Dictionary in _edges:
		var from_key := str(edge.get("from", ""))
		var to_key := str(edge.get("to", ""))
		if _nodes.has(from_key) and _nodes.has(to_key):
			connect_node(_nodes[from_key].name, 0, _nodes[to_key].name, 0)
			if int(edge.get("last_sequence", edge.get("frame", -1))) == latest_sequence:
				set_connection_activity(_nodes[from_key].name, 0, _nodes[to_key].name, 0, 1.0)
	move_child(_labels, get_child_count() - 1)
	_labels.queue_redraw()
	_building = false


func _add_node(key: String, caption: String, modules: Array, at: Vector2, current: bool, issues: int) -> void:
	var node := GraphNode.new()
	node.name = "gm_%d" % _nodes.size()
	node.title = ("● " if current else "") + caption + (" · 默认" if key == _default_state_key and key != "@global" else "") + ("  ⚠ %d" % issues if issues > 0 else "")
	node.position_offset = at
	node.draggable = not _readonly
	node.custom_minimum_size.x = 240
	node.set_meta("state_key", key)
	node.gui_input.connect(_node_context_input.bind(node))
	var summary := Label.new()
	summary.text = "%d 个模块%s" % [modules.size(), " · 当前" if current else ""]
	node.add_child(summary)
	if key != "@global" and _readonly:
		node.set_slot(0, true, 0, Color(0.45, 0.8, 0.9), true, 0, Color(0.45, 0.8, 0.9))
	for module: Dictionary in modules:
		var row := Button.new()
		row.flat = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var module_id := int(module.get("id", -1))
		row.text = "#%d %s%s" % [module_id, module.get("display_name", "模块"), " · " + str(module.lifecycle) if module.has("lifecycle") else ""]
		if int(module.get("issues", 0)) > 0:
			row.text += "  ⚠"
		row.pressed.connect(func() -> void: picked.emit(key, module_id))
		row.gui_input.connect(_node_context_input.bind(row))
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
				source_requested.emit(module_id)
		)
		node.add_child(row)
	if current:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.11, 0.24, 0.28)
		style.border_color = Color(0.3, 0.85, 0.9)
		style.set_border_width_all(2)
		node.add_theme_stylebox_override("panel", style)
	add_child(node)
	if key == "@global":
		_apply_global_style(node)
	var storage_key := key if not _nodes.has(key) else "%s#duplicate%d" % [key, _nodes.size()]
	_nodes[storage_key] = node
	node.position_offset_changed.connect(func() -> void: _labels.queue_redraw())


static func global_color() -> Color:
	return Color(0.65, 0.58, 0.92) if GDEditorUi.is_dark_theme() else Color(0.43, 0.34, 0.7)


func _apply_global_style(node: GraphNode) -> void:
	var surface := GDEditorUi.tone(&"raised")
	var tint := global_color()
	for style_name: String in ["panel", "panel_selected", "titlebar", "titlebar_selected"]:
		var style := node.get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
		if style == null:
			style = GDEditorUi.flat_box(surface, tint, 4, 1, 10, 6)
		var is_title := style_name.begins_with("titlebar")
		var is_selected := style_name.ends_with("selected")
		style.bg_color = surface.lerp(tint, 0.4 if is_title else 0.16)
		style.border_color = GDEditorUi.tone(&"accent") if is_selected else tint
		style.set_border_width_all(2 if is_selected else 1)
		style.border_width_bottom = 0 if is_title else style.border_width_bottom
		style.border_width_top = style.border_width_top if is_title else 0
		node.add_theme_stylebox_override(style_name, style)


func _selected(node: Node) -> void:
	if not _building and node.has_meta("state_key"):
		picked.emit(str(node.get_meta("state_key")), -1)


func select_state(key: String, follow: bool = false) -> void:
	_building = true
	for state_key: String in _nodes:
		_nodes[state_key].selected = state_key == key
	if follow and _nodes.has(key):
		scroll_offset = _nodes[key].position_offset * zoom - size * 0.5 + _nodes[key].size * zoom * 0.5
	_building = false


func frame_all() -> void:
	if _nodes.is_empty() or size.x < 1 or size.y < 1:
		return
	var bounds := Rect2()
	var first := true
	for node: GraphNode in _nodes.values():
		var rect := Rect2(node.position_offset, node.size.max(Vector2(240, 140)))
		bounds = rect if first else bounds.merge(rect)
		first = false
	bounds = bounds.grow(35)
	zoom = clampf(minf(size.x / bounds.size.x, size.y / bounds.size.y), zoom_min, 1.0)
	scroll_offset = bounds.position * zoom - (size - bounds.size * zoom) * 0.5
	_labels.queue_redraw()


func _moved() -> void:
	if _readonly or _building:
		return
	var positions := {}
	for key: String in _nodes:
		positions[key] = _nodes[key].position_offset
	positions_changed.emit(positions)


func _draw_labels() -> void:
	var font := get_theme_default_font()
	for edge: Dictionary in _edges:
		var from_key := str(edge.get("from", ""))
		var to_key := str(edge.get("to", ""))
		if not _nodes.has(from_key) or not _nodes.has(to_key):
			continue
		var from_node: GraphNode = _nodes[from_key]
		var to_node: GraphNode = _nodes[to_key]
		var at := ((from_node.position_offset + from_node.size * 0.5 + to_node.position_offset + to_node.size * 0.5) * 0.5) * zoom - scroll_offset
		if from_key == to_key:
			at += Vector2(0, -45)
		_labels.draw_string(font, at, "×%s" % edge.get("count", 1), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.6, 0.9, 1.0))
