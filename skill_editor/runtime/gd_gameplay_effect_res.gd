@tool
class_name GDGameplayEffectRes
extends Resource

## 玩法效果。duration = 0 表示瞬发；period > 0 表示周期生效。

@export var duration: float = 0.0
@export var period: float = 0.0
@export var modifiers: Array[GDGameplayEffectModifierRes] = []
@export var granted_tags: Array[GDGameplayTagRes] = []
