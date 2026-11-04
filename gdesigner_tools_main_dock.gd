@tool
class_name GdesignerToolsMainDock
extends VBoxContainer

## GdesignerTools 主工作台（集成四大编辑器 + 原子创建器 + 统一 CLI 控制台）
## 页签：
##   0. 关卡编辑器 (Level Editor)
##   1. 演员编辑器 (Actor Editor)
##   2. 技能编辑器 (Skill Editor)
##   3. 新手引导编辑器 (Guide Editor)
##   4. CLI 控制台 & 原子工具 (CLI Console & Atom Creator)

var level_editor: GDLevelEditorWindow = null
var actor_editor: GDActorEditorWindow = null
var skill_editor: GDSkillEditorWindow = null
var guide_editor: GDGuideEditorWindow = null
var cli_console: GDCliConsoleWindow = null
var _tab_container: TabContainer = null
var _atom_creator_win: GDCoreAtomEditorWidgets.AtomCreatorWindow = null

func _init() -> void:
	name = "GdesignerTools"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()

func switch_to_tab(tab_index: int) -> void:
	if _tab_container != null and tab_index >= 0 and tab_index < _tab_container.get_tab_count():
		_tab_container.current_tab = tab_index

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	add_child(header)

	var brand_box := VBoxContainer.new()
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_box.add_theme_constant_override("separation", 0)
	header.add_child(brand_box)

	var brand := Label.new()
	brand.text = "GdesignerTools"
	brand.add_theme_font_size_override("font_size", 16)
	brand_box.add_child(brand)

	var subtitle := GDEditorUi.muted("关卡、演员、技能、引导。关卡原型可以拖进旁边的 3D / 2D 视口。")
	brand_box.add_child(subtitle)

	var atom_btn := Button.new()
	atom_btn.text = "新建原子"
	atom_btn.tooltip_text = "创建一个原子模板"
	GDEditorUi.style_button(atom_btn, "primary")
	atom_btn.pressed.connect(func() -> void:
		if _atom_creator_win == null:
			_atom_creator_win = GDCoreAtomEditorWidgets.AtomCreatorWindow.new()
			add_child(_atom_creator_win)
		_atom_creator_win.popup_centered()
	)
	header.add_child(atom_btn)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tab_container)

	level_editor = GDLevelEditorWindow.new()
	level_editor.name = "关卡"
	_tab_container.add_child(level_editor)

	actor_editor = GDActorEditorWindow.new()
	actor_editor.name = "演员"
	_tab_container.add_child(actor_editor)

	skill_editor = GDSkillEditorWindow.new()
	skill_editor.name = "技能"
	_tab_container.add_child(skill_editor)

	guide_editor = GDGuideEditorWindow.new()
	guide_editor.name = "引导"
	_tab_container.add_child(guide_editor)

	cli_console = GDCliConsoleWindow.new(Callable(self, "dispatch_unified_cli"))
	cli_console.name = "控制台"
	_tab_container.add_child(cli_console)

	_tab_container.clip_contents = true

static func dispatch_unified_cli(command_line: String) -> String:
	var parts := GDCliRoot.split_command_line(command_line)
	if parts.is_empty():
		return JSON.stringify({"ok": false, "code": "BAD_ARG", "message": "empty command"})
	var cmd := parts[0]
	var args: Array = []
	for i in range(1, parts.size()):
		args.append(parts[i])

	if cmd.begins_with("keywords.") or cmd.begins_with("layout.") or cmd.begins_with("scaffold.") or cmd.begins_with("sceneeditor."):
		return GDSceneEditorCli.run(cmd, args)
	if cmd.begins_with("skill."):
		return GDSkillForgeAndCli.run_cli(cmd, args)
	if cmd.begins_with("guide."):
		return GDGuideEditingAndCli.GuideCli.run(cmd, args)
	var core_res := GDCliRoot.execute(parts)
	return core_res.to_json_line()
