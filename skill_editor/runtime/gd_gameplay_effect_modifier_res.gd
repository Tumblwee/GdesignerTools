@tool
class_name GDGameplayEffectModifierRes
extends Resource

## 效果对单个属性的一次修改。

@export var attribute_name: String = ""
@export var op: int = GDSkillTypes.ModifierOp.ADD
@export var magnitude: float = 0.0


func _init(p_attribute: String = "", p_op: int = GDSkillTypes.ModifierOp.ADD, p_magnitude: float = 0.0) -> void:
	attribute_name = p_attribute
	op = p_op
	magnitude = p_magnitude
