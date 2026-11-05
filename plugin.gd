@tool
extends EditorPlugin

## GdesignerTools 入口。
## 工具是辅助窗口，不是主屏：主屏会替换 2D/3D 视图，原型就无法拖进正在编辑的场景。
## 这里开一个非模态窗口，并用 force-draw 把拖拽接到 3D/2D 视口上。
## 不实现 _handles()，避免抢走当前节点的检查器。

const MENU_PREFIX := "GdesignerTools: "
const MENU_ITEMS := ["关卡编辑器", "演员编辑器", "技能编辑器", "引导编辑器", "控制台"]

var _window: GdesignerToolsWindow = null
var _drop_host: GDLevelSceneDrop.Host = null
var _toolbar_btn: Button = null
var _previous_scene: WeakRef = null


func _enter_tree() -> void:
	GDCoreServices.ensure_exists()
	set_process(true)
	set_force_draw_over_forwarding_enabled()
	set_input_event_forwarding_always_enabled()
	var base := EditorInterface.get_base_control()
	_drop_host = GDLevelSceneDrop.Host.new()
	_drop_host.name = "GdesignerDropHost"
	base.add_child(_drop_host)
	GDLevelSceneDrop.bind_plugin(self, _drop_host)
	_window = GdesignerToolsWindow.new()
	base.add_child(_window)
	var current_scene := EditorInterface.get_edited_scene_root()
	_previous_scene = weakref(current_scene) if current_scene != null else null
	scene_changed.connect(_on_scene_changed)
	_toolbar_btn = Button.new()
	_toolbar_btn.text = "GdesignerTools"
	_toolbar_btn.flat = true
	_toolbar_btn.tooltip_text = "打开策划工具窗口"
	_toolbar_btn.pressed.connect(_open.bind(0))
	add_control_to_container(CONTAINER_TOOLBAR, _toolbar_btn)
	for i in range(MENU_ITEMS.size()):
		add_tool_menu_item(MENU_PREFIX + MENU_ITEMS[i], _open.bind(i))


func _exit_tree() -> void:
	for item in MENU_ITEMS:
		remove_tool_menu_item(MENU_PREFIX + item)
	GDLevelSceneDrop.shutdown()
	remove_control_from_container(CONTAINER_TOOLBAR, _toolbar_btn)
	_toolbar_btn.queue_free()
	_window.queue_free()
	_drop_host.queue_free()


func _process(_delta: float) -> void:
	GDLevelSceneDrop.poll()


func _on_scene_changed(scene_root: Node) -> void:
	var previous: Node = _previous_scene.get_ref() as Node if _previous_scene != null else null
	if previous != null:
		_window.dock.level_editor.capture_scene(previous)
	GDLevelSceneDrop.scene_changed()
	_previous_scene = weakref(scene_root) if scene_root != null else null


func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	GDLevelSceneDrop.ensure_catcher(overlay)


func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	GDLevelSceneDrop.ensure_catcher(overlay)


func _get_plugin_name() -> String:
	return "GdesignerTools"


## 编辑器“保存全部”和运行游戏前会调用。
func _save_external_data() -> void:
	_window.dock.save_all()


## 关闭编辑器时，把未保存的资产交给原生确认框。
func _get_unsaved_status(for_scene: String) -> String:
	if not for_scene.is_empty():
		return ""
	var titles := _window.dock.unsaved_titles()
	return "" if titles.is_empty() else "GdesignerTools 有未保存的改动：\n%s\n\n要保存吗？" % "\n".join(titles)


func _open(tab: int) -> void:
	# 菜单回调里直接弹窗，会被正在关闭的菜单吞掉。延后到本帧结束。
	_window.present.call_deferred(tab)
