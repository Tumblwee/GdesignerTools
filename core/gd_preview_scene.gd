@tool
class_name GDPreviewScene
extends RefCounted

## 和 Godot 编辑器一样保留 @tool 初始化，禁止普通游戏脚本、处理循环和碰撞。
## 必须先 prepare 再入树，入树后再 freeze，以覆盖工具脚本生成的子节点。
static func prepare(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	var script := node.get_script() as Script
	if script != null and not script.is_tool():
		node.set_script(null)
	if node is CollisionObject3D or node is CollisionObject2D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is RigidBody3D or node is RigidBody2D:
		node.freeze = true
	if node is Camera2D:
		node.enabled = false
	if node is Camera3D:
		node.current = false
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.autoplay = false
		node.stop()
	if node is AnimationPlayer:
		node.autoplay = ""
		node.stop()
	for child in node.get_children():
		prepare(child)

static func freeze(node: Node) -> void:
	prepare(node)

static func bounds_2d(node: Node, parent_transform := Transform2D.IDENTITY) -> Rect2:
	var transform := parent_transform
	var rect := Rect2()
	if node is CanvasItem:
		if not node.visible:
			return rect
		transform *= node.get_transform()
	if node is Sprite2D:
		rect = node.get_rect()
	elif node is AnimatedSprite2D and node.sprite_frames != null:
		var frames: SpriteFrames = node.sprite_frames
		if frames.has_animation(node.animation) and frames.get_frame_count(node.animation) > node.frame:
			var texture := frames.get_frame_texture(node.animation, node.frame)
			if texture != null:
				var dimensions := texture.get_size()
				rect = Rect2(node.offset - (dimensions * 0.5 if node.centered else Vector2.ZERO), dimensions)
	elif node is Control:
		rect = Rect2(Vector2.ZERO, node.size)
	elif node is Polygon2D:
		for point in node.polygon:
			rect = Rect2(point + node.offset, Vector2(0.001, 0.001)) if not rect.has_area() else rect.expand(point + node.offset)
	elif node is Line2D:
		for point in node.points:
			rect = Rect2(point, Vector2(0.001, 0.001)) if not rect.has_area() else rect.expand(point)
		rect = rect.grow(node.width * 0.5)
	if rect.has_area():
		rect = transform * rect
	for child in node.get_children():
		var inner := bounds_2d(child, transform)
		if inner.has_area():
			rect = inner if not rect.has_area() else rect.merge(inner)
	return rect
