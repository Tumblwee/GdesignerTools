@tool
class_name GDCliConsoleWindow
extends VBoxContainer

## 统一 CLI 控制台面板（对应 EditorCliWindow + SceneEditorCli + SkillCli + GuideCli）
## 支持运行 Core `atom.*`、LevelEditor `keywords.* / layout.* / scaffold.*`、SkillEditor `skill.*`、GuideEditor `guide.*` 命令。

var _input_edit: LineEdit = null
var _output_edit: TextEdit = null
var _commands_list: VBoxContainer = null
var _external_dispatcher: Callable = Callable()

func _init(external_dispatcher: Callable = Callable()) -> void:
	_external_dispatcher = external_dispatcher
	_build_ui()

func set_external_dispatcher(dispatcher: Callable) -> void:
	_external_dispatcher = dispatcher

func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	var cmd_lbl := Label.new()
	cmd_lbl.text = "Command (支持 Core atom.* / LevelEditor keywords.*|layout.*|scaffold.* / Skill skill.* / Guide guide.*):"
	add_child(cmd_lbl)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	add_child(input_row)

	_input_edit = LineEdit.new()
	_input_edit.text = "skill.clip-types"
	_input_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_edit.text_submitted.connect(func(_t: String) -> void: run_input())
	input_row.add_child(_input_edit)

	var run_btn := Button.new()
	run_btn.text = "Run"
	run_btn.pressed.connect(run_input)
	input_row.add_child(run_btn)

	var copy_btn := Button.new()
	copy_btn.text = "Copy Output"
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_output_edit.text)
	)
	input_row.add_child(copy_btn)

	var out_lbl := Label.new()
	out_lbl.text = "Output (JSON Line):"
	add_child(out_lbl)

	_output_edit = TextEdit.new()
	_output_edit.editable = false
	_output_edit.custom_minimum_size.y = 110
	_output_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_output_edit)

	var reg_lbl := Label.new()
	reg_lbl.text = "Registered Commands:"
	add_child(reg_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_commands_list = VBoxContainer.new()
	_commands_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_commands_list)
	GDEditorUi.configure_vertical_scroll(scroll, _commands_list)

	_populate_help_list()

func run_input() -> String:
	var raw := _input_edit.text.strip_edges()
	var out := execute_command_line(raw)
	_output_edit.text = out
	return out

func execute_command_line(raw: String) -> String:
	if raw.is_empty():
		return JSON.stringify({"ok": false, "code": "BAD_ARG", "message": "empty command"})
	if _external_dispatcher.is_valid():
		var res = _external_dispatcher.call(raw)
		if res is String and not res.is_empty():
			return res
	var core_res := GDCliRoot.execute_line(raw)
	return core_res.to_json_line()

func _populate_help_list() -> void:
	var all_entries := [
		["atom.create", "创建 AtomBase 脚本与 AtomTemplateRes 模板"],
		["atom.list-templates", "列出工程内所有 AtomTemplateRes 模板"],
		["keywords.list / add / rename / remove / regenerate / validate", "关卡编辑器 KeywordCatalog 管理与代码生成"],
		["layout.list / add / remove / preview-all-min-max", "关卡编辑器布局实例增删改查与预览"],
		["scaffold.create-module / create-manufactured / add-example-logic", "关卡编辑器模块与制成品脚手架"],
		["skill.list / clip-types / describe / create / validate / effect.create / preview.setup / preview.cast", "技能编辑器 GAS 技能装配与校验"],
		["guide.list / guide.validate / guide.create", "新手引导编辑器图目录、校验与创建"],
	]
	for item in all_entries:
		var lbl := Label.new()
		lbl.text = "  • %s  —  %s" % [item[0], item[1]]
		_commands_list.add_child(lbl)
