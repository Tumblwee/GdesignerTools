extends Node

var _status: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var background := ColorRect.new()
	background.color = Color(0.06, 0.08, 0.12)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	layer.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := Label.new()
	title.text = "GdesignerTools · 游戏进程示例"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	var hint := Label.new()
	hint.text = "在游戏进程页面查看全局模块、状态实例、切换连线和时间线。\n点击按钮由业务代码切换；停止游戏后可编辑配置。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	_status = Label.new()
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_status)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_button(buttons, "进入游戏", func() -> void: _switch(&"game"))
	_button(buttons, "返回登录", func() -> void: _switch(&"login"))
	_button(buttons, "重启当前状态", func() -> void:
		if GDGameMode.current != null:
			GDGameMode.current.restart_state())
	_button(buttons, "发送 ping", func() -> void: GDCoreServices.get_event_bus().publish(&"sample_ping", {}))


func _process(_delta: float) -> void:
	if _status == null:
		return
	if GDGameMode.current == null:
		_status.text = "等待 GameMode 启动…"
		return
	var snapshot := GDGameMode.current.capture_snapshot()
	var lines := PackedStringArray(["当前状态：%s" % snapshot.get("current_state_key", "")])
	for module in snapshot.get("modules", []):
		if int(module.get("instance_serial", 0)) > 0:
			lines.append("%s · 实例 #%s · %s" % [module.get("display_name", ""), module.get("instance_serial", 0), module.get("lifecycle", "")])
	_status.text = "\n".join(lines)


func _switch(key: StringName) -> void:
	if GDGameMode.current != null:
		GDGameMode.current.switch_state(key)


func _button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
