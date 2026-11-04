@tool
class_name GdesignerToolsWindow
extends Window

## 非模态的独立窗口：不占用编辑器主屏，也不锁定编辑器输入，
## 可以挪到视口旁边或第二块屏幕，原型才能拖进 3D / 2D 视口。

const DEFAULT_SIZE := Vector2i(1200, 760)
const MIN_SIZE := Vector2i(720, 480)
const MARGIN := 8

var dock: GdesignerToolsMainDock = null


func _init() -> void:
	title = "GdesignerTools"
	min_size = MIN_SIZE
	size = DEFAULT_SIZE
	exclusive = false
	transient = false
	visible = false
	wrap_controls = false
	close_requested.connect(hide)
	focus_entered.connect(func() -> void: dock.activate_current())

	# 用 PanelContainer 铺底，窗口背景和编辑器主题一致。
	var backdrop := PanelContainer.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_theme_stylebox_override("panel", GDEditorUi.flat_box(GDEditorUi.tone(&"surface"), Color(0, 0, 0, 0), 0, 0, MARGIN, MARGIN))
	add_child(backdrop)
	dock = GdesignerToolsMainDock.new()
	backdrop.add_child(dock)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		GDEditorUi.invalidate_theme()


func present(tab_index: int) -> void:
	if not is_inside_tree():
		push_error("GdesignerTools 窗口还没有挂进编辑器，无法打开。")
		return
	if Engine.is_editor_hint():
		theme = EditorInterface.get_editor_theme()
	if visible:
		grab_focus()
		DisplayServer.window_move_to_foreground(get_window_id())
	else:
		popup_centered(_fit_to_screen(DEFAULT_SIZE))
	dock.switch_to_tab(tab_index)


func _fit_to_screen(wanted: Vector2i) -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect().size - Vector2i(64, 64)
	return Vector2i(clampi(wanted.x, MIN_SIZE.x, maxi(MIN_SIZE.x, usable.x)), clampi(wanted.y, MIN_SIZE.y, maxi(MIN_SIZE.y, usable.y)))
