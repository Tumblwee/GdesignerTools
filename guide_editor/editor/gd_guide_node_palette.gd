@tool
class_name GDGuideNodePalette
extends PopupPanel

## “添加节点”弹窗：输入就筛，回车选第一个，方向键进列表。

signal picked(atom_type_id: String)

var _search: LineEdit = null
var _tree: Tree = null
var _needs_input: bool = false

static var _has_input_by_type: Dictionary = {}


func _init() -> void:
	size = Vector2i(260, 360)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", GDEditorUi.GAP)
	add_child(box)
	_search = GDEditorUi.search_field("搜索节点类型")
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	_search.text_submitted.connect(func(_t: String) -> void: _pick(_first_item()))
	_search.gui_input.connect(_on_search_key)
	box.add_child(_search)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_activated.connect(func() -> void: _pick(_tree.get_selected()))
	_tree.item_mouse_selected.connect(func(_at: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_pick(_tree.get_selected())
	)
	box.add_child(_tree)


## needs_input：从输出口拖到空白处时，只列出能被连入的类型。
func open_at(screen_position: Vector2, needs_input: bool) -> void:
	_needs_input = needs_input
	_search.text = ""
	_rebuild()
	popup(Rect2i(Vector2i(screen_position), size))
	_search.grab_focus()


## 当前列出的类型 id，按显示顺序。
func listed_types() -> PackedStringArray:
	var ids := PackedStringArray()
	var item := _tree.get_root().get_first_child() if _tree.get_root() != null else null
	while item != null:
		if item.get_metadata(0) is String:
			ids.append(item.get_metadata(0))
		item = item.get_next_in_tree()
	return ids


func _rebuild() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var query := _search.text.strip_edges()
	var groups := {}
	for desc in GDGuideAtoms.get_all_atom_descriptors():
		var type_id := str(desc["id"])
		if _needs_input and not _has_input(type_id):
			continue
		if not GDEditorUi.matches_query("%s %s %s" % [desc["display"], desc["category"], type_id], query):
			continue
		var category := str(desc["category"])
		if not groups.has(category):
			var header := root.create_child()
			header.set_text(0, category)
			header.set_selectable(0, false)
			header.set_custom_color(0, GDEditorUi.tone(&"muted"))
			groups[category] = header
		var item := (groups[category] as TreeItem).create_child()
		item.set_text(0, str(desc["display"]))
		item.set_tooltip_text(0, type_id)
		item.set_metadata(0, type_id)


func _first_item() -> TreeItem:
	var item := _tree.get_root().get_first_child() if _tree.get_root() != null else null
	while item != null and not (item.get_metadata(0) is String):
		item = item.get_next_in_tree()
	return item


func _pick(item: TreeItem) -> void:
	if item == null or not (item.get_metadata(0) is String):
		return
	hide()
	picked.emit(item.get_metadata(0))


func _on_search_key(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and key_event.keycode == KEY_DOWN:
		var first := _first_item()
		if first != null:
			_tree.grab_focus()
			first.select(0)
			_search.accept_event()


static func _has_input(type_id: String) -> bool:
	if not _has_input_by_type.has(type_id):
		var atom := GDGuideAtoms.create_atom_by_id(type_id)
		_has_input_by_type[type_id] = atom != null and atom.has_port(GDGuideData.GuidePortKind.EXEC_IN)
	return _has_input_by_type[type_id]
