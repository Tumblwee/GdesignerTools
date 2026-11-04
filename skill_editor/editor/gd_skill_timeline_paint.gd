@tool
class_name GDSkillTimelinePaint
extends RefCounted

## 时间轴的绘制原语：片段条、菱形、刻度、折叠箭头、加号。只画给定的几何，不知道技能和视图状态。

## 轨道类别的色相：动画 位移 判定 效果 音频 相机 特效
const KIND_HUES: Array[float] = [0.58, 0.36, 0.01, 0.75, 0.1, 0.5, 0.88]
const TICK_STEPS: Array[int] = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 30000, 60000]
const DIAMOND_R := 6.5


## 语义色相固定，明度跟随编辑器主题。
static func kind_color(kind: int) -> Color:
	var hue: float = KIND_HUES[clampi(kind, 0, KIND_HUES.size() - 1)]
	return Color.from_hsv(hue, 0.5, 0.66) if GDEditorUi.is_dark_theme() else Color.from_hsv(hue, 0.32, 0.93)


## 1 秒以下用 ms，以上用 s。
static func format_ms(ms: float) -> String:
	return "%d ms" % roundi(ms) if absf(ms) < 1000.0 else "%s s" % String.num(ms / 1000.0, 2)


## 主刻度间距至少 64 像素，标签不会挤在一起。
static func major_step(pixels_per_ms: float) -> float:
	for step in TICK_STEPS:
		if step * pixels_per_ms >= 64.0:
			return float(step)
	return float(TICK_STEPS.back())


## 片段上的文字色：正文色和底色里与填充对比更强的那个。
static func ink(fill: Color) -> Color:
	var text := GDEditorUi.tone(&"text")
	var surface := GDEditorUi.tone(&"surface")
	var lum := fill.get_luminance()
	return text if absf(text.get_luminance() - lum) >= absf(surface.get_luminance() - lum) else surface


## fired：播放头已经扫过，底色提亮并在底边画一道细线。
static func span(canvas: CanvasItem, box: Rect2, fill: Color, selected: bool, fired: bool, text: String, text_x: float, text_room: float, font: Font, font_size: int) -> void:
	if fired:
		fill = fill.lerp(GDEditorUi.tone(&"text"), 0.28)
	GDEditorUi.paint_round_rect(canvas, box, fill, GDEditorUi.tone(&"accent") if selected else Color(0, 0, 0, 0), 3, 2)
	if fired:
		canvas.draw_rect(Rect2(box.position.x + 3.0, box.end.y - 3.0, box.size.x - 6.0, 1.5), Color(ink(fill), 0.55))
	if text_room >= 20.0:
		font.draw_string(canvas.get_canvas_item(), Vector2(text_x, _baseline(box.get_center().y, font, font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, text_room, font_size, ink(fill))


## 瞬时片段：菱形，名字写在右边，最多占 room 像素。
static func diamond(canvas: CanvasItem, center: Vector2, fill: Color, selected: bool, fired: bool, text: String, room: float, font: Font, font_size: int) -> void:
	var r := DIAMOND_R
	var points := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)])
	canvas.draw_colored_polygon(points, fill.lerp(GDEditorUi.tone(&"text"), 0.28) if fired else fill)
	if selected:
		points.append(points[0])
		canvas.draw_polyline(points, GDEditorUi.tone(&"accent"), 2.0, true)
	if room >= 24.0:
		font.draw_string(canvas.get_canvas_item(), Vector2(center.x + r + 4.0, _baseline(center.y, font, font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, minf(room, 140.0), font_size, GDEditorUi.tone(&"text"))


## 标尺刻度。x_of: func(ms) -> x。avoid_x 处有总时长手柄，挡住它的标签不画。
static func ticks(canvas: CanvasItem, x_of: Callable, first_ms: float, right_x: float, pixels_per_ms: float, bottom: float, avoid_x: float, font: Font, font_size: int) -> void:
	var major := major_step(pixels_per_ms)
	var divisions := 4 if str(roundi(major)).begins_with("2") else 5
	var minor := major / divisions
	var color := GDEditorUi.tone(&"muted")
	var i := floori(first_ms / minor)
	while float(x_of.call(i * minor)) <= right_x:
		var x: float = x_of.call(i * minor)
		var is_major := posmod(i, divisions) == 0
		canvas.draw_line(Vector2(x, bottom - (9.0 if is_major else 4.0)), Vector2(x, bottom), color)
		var text := format_ms(i * minor)
		var clear := x > avoid_x + 4.0 or x + 8.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x < avoid_x
		if is_major and clear:
			font.draw_string(canvas.get_canvas_item(), Vector2(x + 4, bottom - 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		i += 1


static func fold_arrow(canvas: CanvasItem, center: Vector2, folded: bool) -> void:
	var points := PackedVector2Array([Vector2(-2.4, -4), Vector2(3.2, 0), Vector2(-2.4, 4)]) if folded \
		else PackedVector2Array([Vector2(-4, -2.4), Vector2(4, -2.4), Vector2(0, 3.2)])
	canvas.draw_set_transform(center)
	canvas.draw_colored_polygon(points, GDEditorUi.tone(&"muted"))
	canvas.draw_set_transform(Vector2.ZERO)


static func plus(canvas: CanvasItem, box: Rect2) -> void:
	GDEditorUi.paint_round_rect(canvas, box, GDEditorUi.tone(&"surface").lerp(GDEditorUi.tone(&"text"), 0.12), Color(0, 0, 0, 0), 3, 0)
	var c := box.get_center()
	canvas.draw_multiline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(4, 0), c + Vector2(0, -4), c + Vector2(0, 4)]), GDEditorUi.tone(&"text"), 1.5)


static func _baseline(center_y: float, font: Font, font_size: int) -> float:
	return center_y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5


## 没有改过名的轨道显示中文类别，改过名的显示用户起的名字。
static func track_label(track: GDSkillRes.SkillTrack) -> String:
	return GDSkillTypes.track_kind_label(track.kind) if track.track_name == GDSkillTypes.track_kind_name(track.kind) else track.track_name
