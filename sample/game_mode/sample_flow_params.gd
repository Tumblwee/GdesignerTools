@tool
extends Resource

## 参数脚本只存储数据，因此允许在编辑器中实例化。
@export var title: String = "欢迎进入示例"
@export var next_state: StringName = &"game"
@export var accent: Color = Color(0.30, 0.74, 0.86)
@export_range(0.0, 60.0, 0.1) var auto_advance_seconds: float = 0.0
