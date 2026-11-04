@tool
class_name GDCoreTypes
extends RefCounted

## 跨模块通用枚举与基础类型（对应 TimiMiniGame.Core）

## 跨模块通用值类型：Keyword catalog、AttributeSet、原子标签覆盖共用同一套枚举。
## 整型序不可重排（0=Int … 3=Bool），已落盘资产按数值反序列化。
enum KeywordValueType {
	INT = 0,
	FLOAT = 1,
	STRING = 2,
	BOOL = 3,
}

## Atom 粗分类（三类）：决定「添加原子」弹窗的标签页归属。
enum AtomType {
	LOGIC = 0,
	VISUAL = 1,
	UI = 2,
}

## 模块分类（用于 GameStateMachine 按 Scene -> Player -> Misc 分趟装配）
enum ModuleCategory {
	SCENE = 0,
	PLAYER = 1,
	MISC = 2,
}

## 音频总线
enum AudioBus {
	MASTER = 0,
	MUSIC = 1,
	SFX = 2,
	VOICE = 3,
}

static func keyword_value_type_name(vt: int) -> String:
	match vt:
		KeywordValueType.INT:
			return "Int"
		KeywordValueType.FLOAT:
			return "Float"
		KeywordValueType.STRING:
			return "String"
		KeywordValueType.BOOL:
			return "Bool"
		_:
			return "Int"

static func parse_keyword_value_type(raw: Variant) -> Dictionary:
	if raw is int:
		if raw >= 0 and raw <= 3:
			return {"ok": true, "value": raw, "warn": ""}
		return {"ok": false, "value": KeywordValueType.INT, "warn": "非法 valueType：%s" % str(raw)}
	var s := str(raw).strip_edges()
	if s.is_empty():
		return {"ok": true, "value": KeywordValueType.INT, "warn": ""}
	if s.is_valid_int():
		var n := s.to_int()
		if n >= 0 and n <= 3:
			return {"ok": true, "value": n, "warn": ""}
	match s.to_lower():
		"int":
			return {"ok": true, "value": KeywordValueType.INT, "warn": ""}
		"float":
			return {"ok": true, "value": KeywordValueType.FLOAT, "warn": ""}
		"string":
			return {"ok": true, "value": KeywordValueType.STRING, "warn": ""}
		"bool":
			return {"ok": true, "value": KeywordValueType.BOOL, "warn": ""}
		_:
			return {
				"ok": false,
				"value": KeywordValueType.INT,
				"warn": "非法 valueType：%s（合法：Int|Float|String|Bool 或 0-3），已保持默认类型。" % s
			}

static func atom_type_name(at: int) -> String:
	match at:
		AtomType.LOGIC:
			return "Logic"
		AtomType.VISUAL:
			return "Visual"
		AtomType.UI:
			return "UI"
		_:
			return "Logic"
