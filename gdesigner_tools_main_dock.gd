@tool
class_name GdesignerToolsMainDock
extends VBoxContainer

## 工作台外壳：顶部页签、当前页面、底部状态栏、可收起的控制台。

const TAB_CONSOLE := 4
const TITLES: PackedStringArray = ["关卡", "演员", "技能", "引导"]

var level_editor: GDLevelPage = null
var actor_editor: GDActorPage = null
var skill_editor: GDSkillPage = null
var guide_editor: GDGuidePage = null
var cli_console: GDConsolePanel = null

var _pages: Array[GDPage] = []
var _tabs: TabBar = null
var _page_host: Control = null
var _status: Label = null


func _init() -> void:
	name = "GdesignerTools"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", GDEditorUi.GAP)
	_build_header()
	_build_pages()
	_build_footer()
	# 只设可见性。页面的 activate 会加载资产，要等窗口真正打开时再做。
	_pages[0].visible = true


var current_page: GDPage:
	get:
		return _pages[_tabs.current_tab]


## tab_index 超出页面范围时打开控制台。
func switch_to_tab(tab_index: int) -> void:
	if tab_index >= _pages.size():
		_set_console_open(true)
	else:
		_tabs.current_tab = clampi(tab_index, 0, _pages.size() - 1)
		_show_page(_tabs.current_tab)


func activate_current() -> void:
	current_page.activate()


func save_all() -> void:
	for page in [actor_editor, level_editor, skill_editor, guide_editor]:
		page.save_all()


func unsaved_titles() -> PackedStringArray:
	var titles := PackedStringArray()
	for page in _pages:
		titles.append_array(page.unsaved_titles())
	return titles


func _build_header() -> void:
	var header := HBoxContainer.new()
	add_child(header)
	_tabs = TabBar.new()
	_tabs.clip_tabs = false
	for title in TITLES:
		_tabs.add_tab(title)
	_tabs.tab_changed.connect(_show_page)
	header.add_child(_tabs)
	header.add_child(GDEditorUi.spacer())
	header.add_child(GDEditorUi.tool_button(&"Terminal", "控制台", func() -> void: _set_console_open(not cli_console.visible), GDEditorUi.key(KEY_QUOTELEFT, true)))
	header.add_child(GDEditorUi.menu_button("", &"GuiTabMenuHl", "更多", [
		{"text": "新建原子…", "do": func() -> void: GDAtomCreatorDialog.open(self, _on_atom_result)},
		{"text": "保存全部", "do": save_all, "shortcut": GDEditorUi.key(KEY_S, true, true)},
	]))


func _build_pages() -> void:
	level_editor = GDLevelPage.new()
	actor_editor = GDActorPage.new()
	actor_editor.level_provider = level_editor.get_current_layout
	skill_editor = GDSkillPage.new()
	guide_editor = GDGuidePage.new()
	_pages = [level_editor, actor_editor, skill_editor, guide_editor]
	_page_host = VBoxContainer.new()
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_page_host)
	for page in _pages:
		page.visible = false
		page.status_changed.connect(_show_status)
		page.document_state_changed.connect(_refresh_tab_titles)
		_page_host.add_child(page)


func _build_footer() -> void:
	cli_console = GDConsolePanel.new()
	cli_console.visible = false
	cli_console.context_provider = func(command: String) -> PackedStringArray: return current_page.cli_context(command)
	cli_console.close_requested.connect(func() -> void: _set_console_open(false))
	add_child(cli_console)
	_status = GDEditorUi.muted_label("")
	_status.clip_text = true
	_status.custom_minimum_size.x = 1
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_status)


func _show_page(index: int) -> void:
	for i in range(_pages.size()):
		_pages[i].visible = i == index
	_pages[index].activate()


func _set_console_open(open: bool) -> void:
	cli_console.visible = open
	if open:
		cli_console.focus_input()


func _show_status(text: String, tone: StringName) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", GDEditorUi.tone(tone))


func _refresh_tab_titles() -> void:
	if _tabs == null:
		return
	for i in range(_pages.size()):
		_tabs.set_tab_title(i, "%s ●" % TITLES[i] if _pages[i].is_dirty() else TITLES[i])


func _on_atom_result(message: String, tone: StringName) -> void:
	_show_status(message, tone)
