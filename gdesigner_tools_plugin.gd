@tool
extends EditorPlugin

## GdesignerTools 入口。
## 策划工具是辅视口，不是主屏：主屏会替换 2D/3D 视图，原型无法拖进正在编辑的场景。
## 这里开一个非模态独立 Window，并用 force-draw 把拖拽接到 3D/2D 视口上。
## 不实现 _handles()，避免抢走当前节点的检查器。

const MENU_LEVEL := "GdesignerTools: 打开关卡编辑器 (Level Editor)"
const MENU_ACTOR := "GdesignerTools: 打开演员编辑器 (Actor Editor)"
const MENU_SKILL := "GdesignerTools: 打开技能编辑器 (Skill Editor)"
const MENU_GUIDE := "GdesignerTools: 打开新手引导编辑器 (Guide Editor)"
const MENU_CLI := "GdesignerTools: 打开 CLI 控制台 (CLI Console)"

var _window: GdesignerToolsWindow = null
var _drop_host: GDLevelSceneDrop.Host = null
var _toolbar_btn: Button = null
var _pending_tab: int = 0
var _open_queued: bool = false

func _enter_tree() -> void:
	GDCoreServices.ensure_exists()
	set_process(true)
	if not Engine.is_editor_hint():
		return
	set_force_draw_over_forwarding_enabled()
	set_input_event_forwarding_always_enabled()
	var base := EditorInterface.get_base_control()
	_drop_host = GDLevelSceneDrop.Host.new()
	_drop_host.name = "GdesignerDropHost"
	base.add_child(_drop_host)
	GDLevelSceneDrop.bind_plugin(self, _drop_host)
	_window = GdesignerToolsWindow.new()
	base.add_child(_window)
	_toolbar_btn = Button.new()
	_toolbar_btn.text = "GdesignerTools"
	_toolbar_btn.tooltip_text = "打开策划工具窗口（关卡 / 演员 / 技能 / 引导）"
	_toolbar_btn.pressed.connect(func() -> void: _open_tab(0))
	add_control_to_container(CONTAINER_TOOLBAR, _toolbar_btn)
	add_tool_menu_item(MENU_LEVEL, func() -> void: _open_tab(0))
	add_tool_menu_item(MENU_ACTOR, func() -> void: _open_tab(1))
	add_tool_menu_item(MENU_SKILL, func() -> void: _open_tab(2))
	add_tool_menu_item(MENU_GUIDE, func() -> void: _open_tab(3))
	add_tool_menu_item(MENU_CLI, func() -> void: _open_tab(4))

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		remove_tool_menu_item(MENU_LEVEL)
		remove_tool_menu_item(MENU_ACTOR)
		remove_tool_menu_item(MENU_SKILL)
		remove_tool_menu_item(MENU_GUIDE)
		remove_tool_menu_item(MENU_CLI)
	GDLevelSceneDrop.shutdown()
	if _toolbar_btn != null:
		remove_control_from_container(CONTAINER_TOOLBAR, _toolbar_btn)
		_toolbar_btn.queue_free()
		_toolbar_btn = null
	if _window != null:
		_window.queue_free()
		_window = null
	if _drop_host != null:
		_drop_host.queue_free()
		_drop_host = null

func _process(_delta: float) -> void:
	GDLevelSceneDrop.poll()

func _has_main_screen() -> bool:
	# 主屏会盖住 3D/2D 视口。这个工具必须和场景同时存在。
	return false

func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	GDLevelSceneDrop.ensure_catcher(overlay)

func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	GDLevelSceneDrop.ensure_catcher(overlay)

func _get_plugin_name() -> String:
	return "GdesignerTools"

func _get_plugin_icon() -> Texture2D:
	if Engine.is_editor_hint() and EditorInterface.get_editor_theme() != null:
		return EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")
	return null

func _open_tab(idx: int) -> void:
	# 菜单回调里直接 popup 会被正在关闭的菜单吞掉，窗口闪一下就消失。延后到本帧结束再弹。
	_pending_tab = idx
	if _open_queued:
		return
	_open_queued = true
	call_deferred("_present_pending")

func _present_pending() -> void:
	_open_queued = false
	if _window == null or not is_instance_valid(_window):
		push_error("GdesignerTools 窗口不存在。")
		return
	_window.present(_pending_tab)
