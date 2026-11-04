@tool
class_name GDAtomCreatorDialog
extends RefCounted

## “新建原子”对话框：生成 AtomBase 脚本和一份 AtomTemplateRes 模板。


## on_result(message, tone)
static func open(host: Node, on_result: Callable) -> void:
	GDDialogs.form(host, "新建原子", [
		{"key": "script_name", "label": "脚本名", "value": "SampleAtom", "placeholder": "英文标识符"},
		{"key": "display_name", "label": "显示名", "value": "示例原子"},
		{"key": "atom_type", "label": "类别", "value": GDCoreTypes.AtomType.LOGIC, "items": [
			["逻辑", GDCoreTypes.AtomType.LOGIC], ["表现", GDCoreTypes.AtomType.VISUAL], ["UI", GDCoreTypes.AtomType.UI],
		]},
		{"key": "description", "label": "说明", "value": ""},
		{"key": "script_dir", "label": "脚本目录", "value": "res://project_atoms/scripts"},
		{"key": "template_dir", "label": "模板目录", "value": GDCliRoot.AtomCreator.DEFAULT_TEMP_DIR},
	], func(values: Dictionary) -> void:
		var result := GDCliRoot.AtomCreator.create_atom(values)
		if bool(result.get("ok", false)):
			on_result.call("已创建原子：%s" % str(result.get("script_path", "")), &"ok")
		else:
			on_result.call("创建失败：%s" % str(result.get("error_message", "")), &"danger")
	, func(values: Dictionary) -> String:
		return "脚本名不能为空" if str(values["script_name"]).is_empty() else ""
	)
