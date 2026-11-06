@tool
class_name GDArchetypePreviewPanel
extends SubViewportContainer

## 原型的真实 3D / 2D 预览：实例化 Prefab，放进独立世界渲染。
## 左键环绕，右键或中键平移，滚轮缩放，双击重新取景。

const DEFAULT_YAW := 145.0
const DEFAULT_PITCH := 25.0

var _viewport: SubViewport = null
var _stage: Node3D = null
var _camera: Camera3D = null
var _archetype: GDArchetypeRes = null
var _source_address: String = ""
var _focus: Vector3 = Vector3.ZERO
var _distance: float = 4.0
var _fit_distance: float = 4.0
var _yaw: float = DEFAULT_YAW
var _pitch: float = DEFAULT_PITCH
var _stage_2d: Node2D = null
var _is_2d := false
var _center_2d := Vector2.ZERO
var _zoom_2d := 1.0
var _fit_zoom_2d := 1.0
var _message: Label = null


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(160, 160)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "左键环绕 · 右键平移 · 滚轮缩放 · 双击重新取景"

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.world_2d = World2D.new()
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = GDEditorUi.tone(&"sunken")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	_viewport.add_child(sun)

	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	_stage_2d = Node2D.new()
	_viewport.add_child(_stage_2d)
	_message = Label.new()
	_message.text = "选择演员查看预览"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message)
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(func() -> void: frame_all.call_deferred())
	_update_camera()


func show_archetype(archetype: GDArchetypeRes) -> void:
	var address := ""
	if archetype != null:
		address = archetype.preview_prefab_address if not archetype.preview_prefab_address.is_empty() else archetype.manufactured_prefab_address
	if archetype == _archetype and address == _source_address:
		return
	_archetype = archetype
	_source_address = address
	GDEditorUi.clear_children(_stage)
	GDEditorUi.clear_children(_stage_2d)
	var packed := archetype.editor_get_catalog_thumbnail_prefab() if archetype != null else null
	var instance := packed.instantiate() if packed != null else null
	_message.text = "选择演员查看预览" if archetype == null else "尚未配置可用的预览或实例 Prefab"
	_message.visible = instance == null
	if instance != null:
		_is_2d = instance is Node2D or instance is Control
		GDPreviewScene.prepare(instance)
		if _is_2d:
			_stage_2d.add_child(instance)
		else:
			_stage.add_child(instance)
		GDPreviewScene.freeze(instance)
	_viewport.disable_3d = _is_2d
	_viewport.transparent_bg = _is_2d
	tooltip_text = "拖动平移 · 滚轮缩放 · 双击重新取景" if _is_2d else "左键环绕 · 右键平移 · 滚轮缩放 · 双击重新取景"
	frame_all()
	# 工具脚本可能在 ready 或 deferred 中构建几何，尺寸稳定后再取景。
	frame_all.call_deferred()
	if instance != null:
		_finish_preview.call_deferred(instance)


func _finish_preview(instance: Node) -> void:
	if is_instance_valid(instance) and is_ancestor_of(instance):
		GDPreviewScene.freeze(instance)
		frame_all()


## 按实例的渲染包围盒取景。
func frame_all() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if _is_2d:
		var rect := GDPreviewScene.bounds_2d(_stage_2d)
		if not rect.has_area():
			rect = Rect2(Vector2(-32, -32), Vector2(64, 64))
		_center_2d = rect.get_center()
		_fit_zoom_2d = clampf(minf(maxf(size.x, 160) / rect.size.x, maxf(size.y, 160) / rect.size.y) * 0.75, 0.01, 100)
		_zoom_2d = _fit_zoom_2d
		_update_2d()
		return
	_viewport.canvas_transform = Transform2D.IDENTITY
	var bounds := _bounds_of(_stage, Transform3D.IDENTITY)
	if bounds.size == Vector3.ZERO:
		bounds = AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	_focus = bounds.get_center()
	var aspect := maxf(0.1, size.x / maxf(1.0, size.y))
	_fit_distance = maxf(0.5, bounds.size.length() * 0.6 / tan(deg_to_rad(_camera.fov * 0.5)) / minf(1.0, aspect))
	_distance = _fit_distance
	_yaw = DEFAULT_YAW
	_pitch = DEFAULT_PITCH
	_update_camera()


func _gui_input(event: InputEvent) -> void:
	if _is_2d:
		_input_2d(event)
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance = maxf(_fit_distance * 0.1, _distance * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = minf(_fit_distance * 8.0, _distance / 0.9)
			MOUSE_BUTTON_LEFT:
				if event.double_click:
					frame_all()
			_:
				return
		_update_camera()
		accept_event()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_yaw -= event.relative.x * 0.5
			_pitch = clampf(_pitch + event.relative.y * 0.5, -89.0, 89.0)
		elif event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			var pixel_world := _distance / maxf(1.0, size.y)
			_focus += _camera.global_basis * Vector3(-event.relative.x, event.relative.y, 0.0) * pixel_world
		else:
			return
		_update_camera()
		accept_event()


func _update_camera() -> void:
	var orbit := Basis.from_euler(Vector3(deg_to_rad(-_pitch), deg_to_rad(_yaw), 0.0))
	_camera.transform = Transform3D(orbit, _focus + orbit * Vector3(0.0, 0.0, _distance))
	_camera.current = true


func _update_2d() -> void:
	_viewport.canvas_transform = Transform2D(Vector2(_zoom_2d, 0), Vector2(0, _zoom_2d), Vector2(_viewport.size) * 0.5 - _center_2d * _zoom_2d)


func _input_2d(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_2d = clampf(_zoom_2d * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), _fit_zoom_2d * 0.1, _fit_zoom_2d * 10.0)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			frame_all()
		else:
			return
	elif event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
		_center_2d -= event.relative / _zoom_2d
	else:
		return
	_update_2d()
	accept_event()


static func _bounds_of(node: Node, parent_transform: Transform3D) -> AABB:
	var current := parent_transform
	var bounds := AABB()
	if node is Node3D:
		current = parent_transform * (node as Node3D).transform
	if node is VisualInstance3D:
		bounds = current * (node as VisualInstance3D).get_aabb()
	for child in node.get_children():
		var inner := _bounds_of(child, current)
		if inner.size != Vector3.ZERO:
			bounds = inner if bounds.size == Vector3.ZERO else bounds.merge(inner)
	return bounds


## 预览里不跑游戏逻辑。
static func _strip_behaviour(node: Node) -> void:
	GDPreviewScene.prepare(node)
