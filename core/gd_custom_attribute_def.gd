@tool
class_name GDCustomAttributeDef
extends Resource

## 原型级自定义属性定义（对应 TimiMiniGame.Core.CustomAttributeDef）：
## 标签 + 展示名 + 值类型 + 默认值。
## 运行时按标签覆盖实例场景上带 AtomVarTag 的原子成员；未设标签则不覆盖。

@export var tag: String = ""
@export var display_name: String = ""
@export var value_type: int = GDCoreTypes.KeywordValueType.INT
@export var default_int: int = 0
@export var default_float: float = 0.0
@export var default_string: String = ""
@export var default_bool: bool = false

var default_value: Variant:
	get:
		match value_type:
			GDCoreTypes.KeywordValueType.INT:
				return default_int
			GDCoreTypes.KeywordValueType.FLOAT:
				return default_float
			GDCoreTypes.KeywordValueType.STRING:
				return default_string
			GDCoreTypes.KeywordValueType.BOOL:
				return default_bool
			_:
				return null

static func editor_create(
	p_tag: String,
	p_display_name: String,
	p_value_type: int,
	p_default_value: Variant
) -> GDCustomAttributeDef:
	var def := GDCustomAttributeDef.new()
	def.tag = p_tag
	def.display_name = p_display_name
	def.value_type = p_value_type
	match p_value_type:
		GDCoreTypes.KeywordValueType.INT:
			def.default_int = int(p_default_value) if p_default_value != null else 0
		GDCoreTypes.KeywordValueType.FLOAT:
			def.default_float = float(p_default_value) if p_default_value != null else 0.0
		GDCoreTypes.KeywordValueType.STRING:
			def.default_string = str(p_default_value) if p_default_value != null else ""
		GDCoreTypes.KeywordValueType.BOOL:
			def.default_bool = bool(p_default_value) if p_default_value != null else false
	return def

func clone_def() -> GDCustomAttributeDef:
	var c := GDCustomAttributeDef.new()
	c.tag = tag
	c.display_name = display_name
	c.value_type = value_type
	c.default_int = default_int
	c.default_float = default_float
	c.default_string = default_string
	c.default_bool = default_bool
	return c

func to_dict() -> Dictionary:
	return {
		"tag": tag,
		"display_name": display_name,
		"value_type": value_type,
		"default_int": default_int,
		"default_float": default_float,
		"default_string": default_string,
		"default_bool": default_bool,
	}

static func from_dict(d: Dictionary) -> GDCustomAttributeDef:
	var def := GDCustomAttributeDef.new()
	def.tag = str(d.get("tag", ""))
	def.display_name = str(d.get("display_name", ""))
	def.value_type = int(d.get("value_type", GDCoreTypes.KeywordValueType.INT))
	def.default_int = int(d.get("default_int", 0))
	def.default_float = float(d.get("default_float", 0.0))
	def.default_string = str(d.get("default_string", ""))
	def.default_bool = bool(d.get("default_bool", false))
	return def
