@tool
class_name GDLibraryList
extends VBoxContainer

## 可搜索、可分组的资产列表，基于原生 Tree（键盘导航、框选高亮、虚拟滚动都是现成的）。
##
## set_items 的数据格式：
##   [{"title": "组名", "key": 组键, "items": [
##       {"key": 任意, "text": "名字", "detail": "#1001", "color": Color, "tooltip": "", "tone": &"warn"}
##   ]}]
## 组的 title 为空表示不分组。

signal item_selected(key: Variant)
signal item_activated(key: Variant)
## key 为 null 表示点在空白处。
signal context_requested(key: Variant)
signal delete_requested(key: Variant)
signal rename_requested(key: Variant)
signal duplicate_requested(key: Variant)

## func(key) -> Variant：返回拖拽数据，null 表示这一项不能拖。
var drag_provider: Callable = Callable()
## 标题栏右侧的按钮放这里。
var header: HBoxContainer = null

var _title_text: String = ""
var _title: Label = null
var _search: LineEdit = null
var _tree: Tree = null
var _empty_host: VBoxContainer = null
var _groups: Array = []
var _collapsed: Dictionary = {}
var _selected_key: Variant = null
var _rebuilding: bool = false

static var _swatches: Dictionary = {}


func _init(title_text: String = "", search_placeholder: String = "搜索") -> void:
	_title_text = title_text
	add_theme_constant_override("separation", GDEditorUi.GAP)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	add_child(header)
	_title = GDEditorUi.title_label(title_text)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)

	_search = GDEditorUi.search_field(search_placeholder)
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	add_child(_search)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.columns = 2
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_rmb_select = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 64)
	_tree.add_theme_constant_override("draw_relationship_lines", 0)
	_tree.add_theme_constant_override("draw_guides", 0)
	_tree.item_selected.connect(_on_tree_selected)
	_tree.item_activated.connect(func() -> void:
		var key: Variant = _key_of(_tree.get_selected())
		if key != null:
			item_activated.emit(key)
	)
	_tree.item_collapsed.connect(_on_group_toggled)
	_tree.item_mouse_selected.connect(func(_at: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_RIGHT:
			context_requested.emit(_key_of(_tree.get_selected()))
	)
	_tree.empty_clicked.connect(func(_at: Vector2, button: int) -> void:
		_tree.deselect_all()
		_selected_key = null
		if button == MOUSE_BUTTON_RIGHT:
			context_requested.emit(null)
	)
	_tree.gui_input.connect(_on_tree_key)
	_tree.set_drag_forwarding(_tree_drag_data, Callable(), Callable())
	add_child(_tree)

	_empty_host = VBoxContainer.new()
	_empty_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_host.visible = false
	add_child(_empty_host)


func set_items(groups: Array) -> void:
	_groups = groups
	_rebuild()


func set_empty_state(state: Control) -> void:
	GDEditorUi.clear_children(_empty_host)
	if state != null:
		_empty_host.add_child(state)


## 只改高亮，不发信号。
func select_key(key: Variant) -> void:
	_selected_key = key
	var item := _find(key)
	_rebuilding = true
	if item != null:
		item.select(0)
		_tree.scroll_to_item(item)
	else:
		_tree.deselect_all()
	_rebuilding = false


func focus_search() -> void:
	_search.grab_focus()


## 右侧 detail 列的宽度。默认只放得下 #1000 这类短 ID。
func set_detail_width(width: int) -> void:
	_tree.set_column_custom_minimum_width(1, width)


func _rebuild() -> void:
	_rebuilding = true
	var scroll := _tree.get_scroll()
	_tree.clear()
	var root := _tree.create_item()
	var query := _search.text.strip_edges()
	var total := 0
	var shown := 0
	var selected_item: TreeItem = null
	for group: Dictionary in _groups:
		var entries: Array = group.get("items", [])
		var parent := root
		var header_item: TreeItem = null
		for entry: Dictionary in entries:
			total += 1
			if not GDEditorUi.matches_query("%s %s %s" % [entry.get("text", ""), entry.get("detail", ""), group.get("title", "")], query):
				continue
			if header_item == null and not str(group.get("title", "")).is_empty():
				header_item = _make_group_item(root, group)
				parent = header_item
			var item := _make_item(parent, entry)
			shown += 1
			if entry.get("key") == _selected_key:
				selected_item = item
		if header_item != null:
			header_item.set_text(1, str(header_item.get_child_count()))
			header_item.collapsed = query.is_empty() and bool(_collapsed.get(group.get("key", group.get("title")), false))
	_title.text = _title_text if total == 0 else (
		"%s  %d" % [_title_text, total] if query.is_empty() else "%s  %d / %d" % [_title_text, shown, total]
	)
	if selected_item != null:
		selected_item.select(0)
	_restore_scroll(scroll.y)
	var is_empty := total == 0 and _empty_host.get_child_count() > 0
	_tree.visible = not is_empty
	_search.visible = not is_empty
	_empty_host.visible = is_empty
	_rebuilding = false


## Tree 没有公开设置滚动位置的接口，只能经由内部滚动条。
func _restore_scroll(offset: float) -> void:
	for child in _tree.get_children(true):
		if child is VScrollBar:
			child.value = offset
			return


func _make_group_item(root: TreeItem, group: Dictionary) -> TreeItem:
	var item := root.create_child()
	item.set_text(0, str(group.get("title", "")))
	item.set_selectable(0, false)
	item.set_selectable(1, false)
	item.set_custom_color(0, GDEditorUi.tone(&"muted"))
	item.set_custom_color(1, GDEditorUi.tone(&"muted"))
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	item.set_metadata(0, {"group": group.get("key", group.get("title"))})
	return item


func _make_item(parent: TreeItem, entry: Dictionary) -> TreeItem:
	var item := parent.create_child()
	item.set_text(0, str(entry.get("text", "")))
	item.set_text(1, str(entry.get("detail", "")))
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	item.set_custom_color(1, GDEditorUi.tone(&"muted"))
	item.set_tooltip_text(0, str(entry.get("tooltip", "")))
	item.set_tooltip_text(1, str(entry.get("tooltip", "")))
	item.set_metadata(0, {"key": entry.get("key")})
	if entry.has("color"):
		item.set_icon(0, _swatch(entry["color"]))
	if entry.has("tone"):
		item.set_custom_color(0, GDEditorUi.tone(entry["tone"]))
	return item


func _key_of(item: TreeItem) -> Variant:
	if item == null:
		return null
	var meta: Variant = item.get_metadata(0)
	return meta.get("key") if meta is Dictionary else null


func _find(key: Variant) -> TreeItem:
	if key == null or _tree.get_root() == null:
		return null
	var item := _tree.get_root().get_first_child()
	while item != null:
		if _key_of(item) == key:
			return item
		item = item.get_next_in_tree()
	return null


func _on_tree_selected() -> void:
	if _rebuilding:
		return
	var key: Variant = _key_of(_tree.get_selected())
	_selected_key = key
	if key != null:
		item_selected.emit(key)


func _on_group_toggled(item: TreeItem) -> void:
	var meta: Variant = item.get_metadata(0)
	if not _rebuilding and meta is Dictionary and meta.has("group"):
		_collapsed[meta["group"]] = item.collapsed


func _on_tree_key(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var key: Variant = _key_of(_tree.get_selected())
	if key == null:
		return
	match key_event.get_keycode_with_modifiers():
		KEY_DELETE:
			delete_requested.emit(key)
		KEY_F2:
			rename_requested.emit(key)
		KEY_MASK_CTRL | KEY_D:
			duplicate_requested.emit(key)
		_:
			return
	_tree.accept_event()


func _tree_drag_data(at: Vector2) -> Variant:
	if not drag_provider.is_valid():
		return null
	var item := _tree.get_item_at_position(at)
	var key: Variant = _key_of(item)
	if key == null:
		return null
	var payload: Variant = drag_provider.call(key)
	if payload != null:
		var preview := Label.new()
		preview.text = item.get_text(0)
		_tree.set_drag_preview(preview)
	return payload


static func _swatch(color: Color) -> Texture2D:
	if _swatches.has(color):
		return _swatches[color]
	var size := 10
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size - 1, size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var coverage := clampf(size * 0.5 - Vector2(x, y).distance_to(center), 0.0, 1.0)
			image.set_pixel(x, y, Color(color, color.a * coverage))
	var texture := ImageTexture.create_from_image(image)
	_swatches[color] = texture
	return texture
