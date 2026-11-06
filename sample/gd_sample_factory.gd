@tool
class_name GDSampleFactory
extends RefCounted

## 通用示例实例：演员库、关卡，以及可摆放的实体预制。
## 这些资源不带任何具体玩法，编辑器在没有打开资产时用它们做起点。

const ACTOR_LIBRARY_PATH := "res://game_res/sample/actors/ActorLibrary_Sample.tres"
const LEVEL_SCENE_PATH := "res://game_res/sample/level/LevelScene_Sample.tres"
const PREFAB_DIR := "res://game_res/sample/prefabs"
const GAME_MODE_CONFIG_PATH := "res://game_res/sample/game_mode/GameMode_Sample.tres"
const GAME_MODE_SCENE_PATH := "res://game_res/sample/game_mode/GameMode_Sample.tscn"

const ADDR_UNIT := "Entity_Sample_Unit"
const ADDR_GUIDE := "Entity_Sample_Guide"
const ADDR_BLOCK := "Entity_Sample_Block"
const ADDR_BEACON := "Entity_Sample_Beacon"


static func ensure_sample_assets() -> void:
	_ensure_prefab(ADDR_UNIT, "capsule", Color(0.32, 0.58, 0.92), Vector3(0.7, 1.6, 0.7))
	_ensure_prefab(ADDR_GUIDE, "capsule", Color(0.30, 0.74, 0.52), Vector3(0.6, 1.7, 0.6))
	_ensure_prefab(ADDR_BLOCK, "box", Color(0.86, 0.52, 0.26), Vector3(1.2, 1.0, 1.2))
	_ensure_prefab(ADDR_BEACON, "cylinder", Color(0.93, 0.78, 0.22), Vector3(0.45, 1.8, 0.45))
	if not ResourceLoader.exists(ACTOR_LIBRARY_PATH):
		_save_resource(build_actor_library(), ACTOR_LIBRARY_PATH)
	if not ResourceLoader.exists(LEVEL_SCENE_PATH):
		_save_resource(build_level_scene(), LEVEL_SCENE_PATH)


static func load_actor_library() -> GDActorLibraryRes:
	ensure_sample_assets()
	var loaded := ResourceLoader.load(ACTOR_LIBRARY_PATH)
	if loaded is GDActorLibraryRes:
		return loaded as GDActorLibraryRes
	return build_actor_library()


static func load_level_scene() -> GDLevelSceneRes:
	ensure_sample_assets()
	var loaded := ResourceLoader.load(LEVEL_SCENE_PATH)
	if loaded is GDLevelSceneRes:
		return loaded as GDLevelSceneRes
	return build_level_scene()


## 单独生成游戏进程示例，不修改工程主场景，也不覆盖用户已编辑的示例。
static func ensure_game_mode_assets() -> void:
	if not ResourceLoader.exists(GAME_MODE_CONFIG_PATH):
		_save_resource(build_game_mode_config(), GAME_MODE_CONFIG_PATH)
	if not ResourceLoader.exists(GAME_MODE_SCENE_PATH):
		var root := Node.new()
		root.name = "GameModeSample"
		root.set_script(load("res://addons/gdesigner_tools/sample/game_mode/sample_game_mode_scene.gd"))
		var bootstrap := Node.new()
		bootstrap.name = "GameModeBootstrap"
		bootstrap.set_script(load("res://addons/gdesigner_tools/game_mode_editor/runtime/gd_game_mode_bootstrap.gd"))
		bootstrap.set("config_path", GAME_MODE_CONFIG_PATH)
		root.add_child(bootstrap)
		bootstrap.owner = root
		var packed := PackedScene.new()
		var err := packed.pack(root)
		root.free()
		if err == OK:
			_save_resource(packed, GAME_MODE_SCENE_PATH)
		else:
			push_error("游戏进程示例打包失败：%s" % error_string(err))


static func load_game_mode_config() -> GDGameModeConfigRes:
	ensure_game_mode_assets()
	var loaded := ResourceLoader.load(GAME_MODE_CONFIG_PATH)
	return loaded as GDGameModeConfigRes if loaded is GDGameModeConfigRes else build_game_mode_config()


static func build_game_mode_config() -> GDGameModeConfigRes:
	var config := GDGameModeConfigRes.new()
	config.resource_name = "GameMode_Sample"
	config.display_name = "游戏进程示例"
	config.default_state_key = &"login"
	config.global_graph_position = Vector2(40, 40)
	config.next_module_id = 4
	var global := _game_mode_module(1, "会话服务", "sample_global_module.gd")
	config.global_modules.append(global)
	var login := GDGameStateBindingRes.new()
	login.key = &"login"
	login.display_name = "登录"
	login.graph_position = Vector2(40, 260)
	var login_module := _game_mode_module(2, "登录流程", "sample_login_module.gd")
	login_module.params = load("res://addons/gdesigner_tools/sample/game_mode/sample_flow_params.gd").new()
	login.modules.append(login_module)
	config.states.append(login)
	var game := GDGameStateBindingRes.new()
	game.key = &"game"
	game.display_name = "游戏"
	game.graph_position = Vector2(420, 260)
	game.modules.append(_game_mode_module(3, "游戏流程（可重启）", "sample_game_module.gd"))
	config.states.append(game)
	config.prepare_save()
	return config


static func _game_mode_module(id: int, title: String, script_name: String) -> GDGameModuleEntryRes:
	var entry := GDGameModuleEntryRes.new()
	entry.module_id = id
	entry.display_name = title
	entry.module_script = load("res://addons/gdesigner_tools/sample/game_mode/" + script_name)
	return entry


static func build_actor_library() -> GDActorLibraryRes:
	var lib := GDActorLibraryRes.new()
	lib.resource_name = "ActorLibrary_Sample"
	lib.display_name = "通用演员库"
	var kw := GDActorTypeKeywordsRes.new()
	kw.enum_namespace = "Sample.Actor"
	kw.enum_type_name = "ActorArchetypeTypeKind"
	kw.add_entry("Unit", "单位", "")
	kw.add_entry("Guide", "向导", "")
	lib.editor_set_actor_type_keywords(kw)

	var unit := GDActorArchetypeRes.new()
	unit.resource_name = "ActorArchetype_Sample_Unit"
	unit.editor_init_with_addresses(lib.editor_allocate_next_archetype_stable_id(), "示例单位", ADDR_UNIT, "")
	unit.editor_set_archetype_type_stable_id(1)
	unit.custom_attributes.append(GDCustomAttributeDef.editor_create(
		"actor.move_speed", "移动速度", GDCoreTypes.KeywordValueType.FLOAT, 3.5
	))
	lib.editor_add_archetype(unit)

	var guide := GDActorArchetypeRes.new()
	guide.resource_name = "ActorArchetype_Sample_Guide"
	guide.editor_init_with_addresses(lib.editor_allocate_next_archetype_stable_id(), "示例向导", ADDR_GUIDE, "")
	guide.editor_set_archetype_type_stable_id(2)
	lib.editor_add_archetype(guide)
	return lib


static func build_level_scene() -> GDLevelSceneRes:
	var layout := GDLevelSceneRes.new()
	layout.resource_name = "LevelScene_Sample"
	layout.display_name = "通用示例关卡"
	var kw := GDKeywordCatalogRes.new()
	kw.enum_namespace = "Sample.Level"
	kw.enum_type_name = "PlacementArchetypeTypeKind"
	kw.add_entry("Structure", "结构", "")
	kw.add_entry("Marker", "标记", "")
	layout.editor_bind_archetype_type_keywords(kw)

	var block := GDLevelArchetypeRes.new()
	block.resource_name = "PlacementArchetype_Sample_Block"
	block.editor_init_with_addresses(layout.editor_allocate_next_archetype_stable_id(), "示例方块", ADDR_BLOCK, "")
	block.editor_set_archetype_type_stable_id(1)
	block.custom_attributes.append(GDCustomAttributeDef.editor_create(
		"block.height", "高度", GDCoreTypes.KeywordValueType.FLOAT, 1.0
	))
	layout.editor_add_archetype(block)

	var beacon := GDLevelArchetypeRes.new()
	beacon.resource_name = "PlacementArchetype_Sample_Beacon"
	beacon.editor_init_with_addresses(layout.editor_allocate_next_archetype_stable_id(), "示例信标", ADDR_BEACON, "")
	beacon.editor_set_archetype_type_stable_id(2)
	layout.editor_add_archetype(beacon)

	layout.editor_add_placement(block.stable_id, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 1)
	layout.editor_add_placement(beacon.stable_id, Vector3(4, 0, 0), Vector3.ZERO, Vector3.ONE, 1)
	return layout


static func _ensure_prefab(stem: String, shape: String, color: Color, size: Vector3) -> void:
	var path := "%s/%s.tscn" % [PREFAB_DIR, stem]
	if ResourceLoader.exists(path):
		GDArchetypeRes.register_prefab_address(stem, path)
		return
	GDCliRoot.AtomCreator.ensure_dir(PREFAB_DIR)
	var root := GDEntityNode.new()
	root.name = stem

	var visual := GDVisualAtom.new()
	visual.name = "VisualAtom"
	root.editor_register_atom(visual)
	var visual_root := visual.ensure_visual_root()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _make_mesh(shape, size)
	body.position = Vector3(0, size.y * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	body.material_override = mat
	visual_root.add_child(body)

	var interact := GDInteractableAtom.new()
	interact.name = "InteractableAtom"
	interact.box_size = size
	interact.box_center = Vector3(0, size.y * 0.5, 0)
	root.editor_register_atom(interact)

	_assign_owners(root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		push_error("通用预制打包失败：%s (%s)" % [stem, error_string(err)])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("通用预制保存失败：%s (%s)" % [path, error_string(err)])
		return
	GDArchetypeRes.register_prefab_address(stem, path)


static func _make_mesh(shape: String, size: Vector3) -> Mesh:
	match shape:
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = size.x * 0.5
			capsule.height = size.y
			return capsule
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x * 0.35
			cylinder.bottom_radius = size.x * 0.5
			cylinder.height = size.y
			return cylinder
		_:
			var box := BoxMesh.new()
			box.size = size
			return box


static func _assign_owners(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


static func _save_resource(res: Resource, path: String) -> void:
	GDCliRoot.AtomCreator.ensure_dir(path.get_base_dir())
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("通用示例资源保存失败：%s (%s)" % [path, error_string(err)])
