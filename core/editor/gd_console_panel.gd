@tool
class_name GDConsolePanel
extends VBoxContainer

## 控制台抽屉：一个输入框，Tab 补全，↑↓ 翻历史。
## 当前页面的资产路径会自动作为默认参数带上。

const MAX_SUGGESTIONS := 6
const MAX_HISTORY := 50

signal close_requested

## func(command) -> PackedStringArray：当前页面提供的默认参数。
var context_provider: Callable = Callable()

var _input: LineEdit = null
var _suggestions: Label = null
var _output: TextEdit = null
var _history: PackedStringArray = PackedStringArray()
var _history_cursor: int = 0


func _init() -> void:
	add_theme_constant_override("separation", GDEditorUi.GAP)
	custom_minimum_size.y = 180

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	add_child(bar)
	_input = LineEdit.new()
	_input.placeholder_text = "输入命令。Tab 补全，↑↓ 翻历史，help 看全部"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t: String) -> void: run_input())
	_input.text_changed.connect(func(_t: String) -> void: _refresh_suggestions())
	_input.gui_input.connect(_on_input_key)
	bar.add_child(_input)
	bar.add_child(GDEditorUi.text_button("运行", run_input, &"primary"))
	bar.add_child(GDEditorUi.tool_button(&"ActionCopy", "复制输出", func() -> void: DisplayServer.clipboard_set(_output.text)))
	bar.add_child(GDEditorUi.tool_button(&"Close", "收起控制台", func() -> void: close_requested.emit()))

	_suggestions = GDEditorUi.hint_label("")
	_suggestions.visible = false
	add_child(_suggestions)

	_output = TextEdit.new()
	_output.editable = false
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.placeholder_text = "命令的输出显示在这里"
	add_child(_output)


func focus_input() -> void:
	_input.grab_focus.call_deferred()


func run_input() -> String:
	var line := _input.text.strip_edges()
	if line.is_empty():
		return ""
	if _history.is_empty() or _history[-1] != line:
		_history.append(line)
		if _history.size() > MAX_HISTORY:
			_history.remove_at(0)
	_history_cursor = _history.size()
	var result := GdesignerToolsCli.run(_with_context(line))
	_output.text = "> %s\n%s" % [line, _pretty(result)]
	_input.text = ""
	_refresh_suggestions()
	return result


## 补上当前页面的默认参数；用户手写的同名参数优先。
func _with_context(line: String) -> String:
	if not context_provider.is_valid():
		return line
	var parts := line.split(" ", false)
	var context: PackedStringArray = context_provider.call(parts[0])
	for i in range(0, context.size() - 1, 2):
		if not line.contains(context[i]):
			line += " %s %s" % [context[i], context[i + 1]]
	return line


static func _pretty(json_text: String) -> String:
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null:
		return json_text
	# JSON 只有浮点数，1 会被打印成 1.0。
	var whole_numbers := RegEx.create_from_string("(: -?[0-9]+)[.]0(?=,?$)")
	var lines := PackedStringArray()
	for line in JSON.stringify(parsed, "  ", false).split("\n"):
		lines.append(whole_numbers.sub(line, "$1"))
	return "\n".join(lines)


func _matching_commands(prefix: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for command: Dictionary in GdesignerToolsCli.commands():
		if str(command["name"]).begins_with(prefix):
			matches.append(command)
	return matches


func _refresh_suggestions() -> void:
	var text := _input.text.strip_edges()
	var matches := [] if text.is_empty() or text.contains(" ") else _matching_commands(text)
	var lines := PackedStringArray()
	for command: Dictionary in matches.slice(0, MAX_SUGGESTIONS):
		lines.append("%s    %s" % [command["name"], command["summary"]])
	_suggestions.text = "\n".join(lines)
	_suggestions.visible = not lines.is_empty()


func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_TAB:
			_complete()
		KEY_UP:
			_step_history(-1)
		KEY_DOWN:
			_step_history(1)
		_:
			return
	_input.accept_event()


func _complete() -> void:
	var matches := _matching_commands(_input.text.strip_edges())
	if matches.is_empty():
		return
	var common := str(matches[0]["name"])
	for command: Dictionary in matches:
		while not str(command["name"]).begins_with(common):
			common = common.left(common.length() - 1)
	_input.text = common + (" " if matches.size() == 1 else "")
	_input.caret_column = _input.text.length()
	_refresh_suggestions()


func _step_history(direction: int) -> void:
	if _history.is_empty():
		return
	_history_cursor = clampi(_history_cursor + direction, 0, _history.size())
	_input.text = _history[_history_cursor] if _history_cursor < _history.size() else ""
	_input.caret_column = _input.text.length()
