@tool
class_name GdesignerToolsWindow
extends Window

## GdesignerTools 的非模态独立窗口。
## 不占用编辑器主屏（2D / 3D / Script）。关卡编辑时主视口保持可用，原型才能拖进去。
## transient = false：不强制盖在编辑器上面，可以挪到视口旁边或第二块屏幕。
## exclusive = false：不锁住编辑器输入。

var dock: GdesignerToolsMainDock = null

func _init() -> void:
	title = "GdesignerTools"
	# 最小尺寸必须小于常见笔记本屏幕，否则 Window 拒绝弹出，看起来像“打不开”。
	min_size = Vector2i(720, 480)
	size = Vector2i(1100, 720)
	exclusive = false
	transient = false
	popup_window = false
	unresizable = false
	wrap_controls = false
	visible = false
	close_requested.connect(hide)
	dock = GdesignerToolsMainDock.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.offset_left = 8
	dock.offset_top = 8
	dock.offset_right = -8
	dock.offset_bottom = -8
	dock.clip_contents = true
	add_child(dock)

func _ready() -> void:
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.offset_left = 8
	dock.offset_top = 8
	dock.offset_right = -8
	dock.offset_bottom = -8

func _exit_tree() -> void:
	_dispose_guide_session()

func present(tab_index: int) -> void:
	if not is_inside_tree():
		push_error("GdesignerTools 窗口还没有挂进编辑器，无法打开。")
		return
	_apply_editor_theme()
	exclusive = false
	popup_window = false
	var sz := _fit_size(Vector2i(1100, 720))
	min_size = Vector2i(mini(720, sz.x), mini(480, sz.y))
	if not visible:
		# popup_centered 用当前屏幕的客户区居中，避免手写屏幕坐标把窗口推到屏幕外。
		popup_centered(sz)
	else:
		grab_focus()
		var id := get_window_id()
		if id > 0:
			DisplayServer.window_move_to_foreground(id)
	if dock != null:
		dock.switch_to_tab(tab_index)

func _fit_size(wanted: Vector2i) -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect()
	if usable.size.x < 200 or usable.size.y < 200:
		return Vector2i(mini(wanted.x, 1100), mini(wanted.y, 720))
	return Vector2i(
		clampi(wanted.x, 720, maxi(720, usable.size.x - 64)),
		clampi(wanted.y, 480, maxi(480, usable.size.y - 64))
	)

func _apply_editor_theme() -> void:
	if Engine.is_editor_hint() and EditorInterface.get_editor_theme() != null:
		theme = EditorInterface.get_editor_theme()

func _dispose_guide_session() -> void:
	if dock == null or dock.guide_editor == null:
		return
	if dock.guide_editor._runner != null:
		dock.guide_editor._runner.dispose()
		dock.guide_editor._runner = null
	if dock.guide_editor._host != null:
		dock.guide_editor._host.dispose()
		dock.guide_editor._host = null
