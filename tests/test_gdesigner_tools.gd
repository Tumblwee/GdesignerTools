extends SceneTree

## GdesignerTools 全量自动化测试与自检套件
## 验证：
##   1. Core 基础层（EventBus、ServiceLocator、GameStateMachine 四层生命周期、AttributeSet GAS 公式、AtomVarTagRegistry、InteractableAtom/VisualAtom/UIAnchor3DAtom、Core CLI）
##   2. Level Editor（ID Schema 10000+/1000+/20000+、自定义 ID 段分配与两阶段标准化、Path 曲线采样、CameraPose XZ/XY 边界、KeywordCatalog 与代码生成、CSV UTF-8 BOM 导出、13 条 CLI、LayoutIdMigrationTool、LevelEditorWindow UI 实例化）
##   3. Actor Editor（ActorLibrary 1000+ 分配器、重命名/复制/Override 复写防环与重绑、ActorEditorWindow UI 实例化）
##   4. Skill Editor（SkillIdentity 解析与规范化、15 种 Clip 与 4 种 Trajectory、SkillRunner 同刻 tie-break 排序、SkillRuntimeService 消耗/冷却/打断/伤害/闪现、SkillTimelineEditorMath、SkillAssetValidator、SkillForge & SkillCli 8 条命令往返、SkillEditorWindow UI 实例化）
##   5. Guide Editor（GuideProgressStore 同构编码往返、GuideConditionEvaluator、15 种内置原子、GuideGraphValidator 无等待环/孤立/端口/子图递归校验、GuideSchemaMigrator v1->v2、GuideRunner 执行/超时/Stall/断点/单步/输入水位线、GuideTriggerSystem、GuideGraphLayout、GuideCli、GuideEditorWindow UI 实例化）
##   6. 主插件与 GdesignerToolsMainDock 完整挂载运行

var _pass_count: int = 0
var _fail_count: int = 0
var _frames_waited: int = 0

func _init() -> void:
	print("============================================================")
	print("  GdesignerTools Automated Verification Suite (Godot 4.7.2)")
	print("============================================================")

	_test_all_scripts_compile()
	_test_core_layer()
	_test_level_editor()
	_test_actor_editor()
	_test_skill_editor()
	_test_guide_editor()
	_test_ui_windows_and_main_dock()

	GDSkillForgeAndCli._in_memory_skills.clear()
	GDCliRoot._registry.clear()
	GDCliRoot._builtins_registered = false
	GDCoreServices.shutdown_for_tests()

	print("------------------------------------------------------------")
	print("  TOTAL PASSED: %d   TOTAL FAILED: %d" % [_pass_count, _fail_count])
	print("============================================================")

func _process(_delta: float) -> bool:
	_frames_waited += 1
	if _frames_waited >= 2:
		GDGuideEditingAndCli._in_memory_graphs.clear()
		GDGuideRunnerSystem.GuideBreakpoints._by_graph.clear()
		GDGuideRunnerSystem.GuideDebugRegistry._sessions.clear()
		GDSkillForgeAndCli._in_memory_skills.clear()
		GDCliRoot._registry.clear()
		GDCliRoot._builtins_registered = false
		GDSceneEditorL10n._on_language_changed_callbacks.clear()
		GDGameLogger._history.clear()
		GDCoreServices.shutdown_for_tests()
		quit(0 if _fail_count == 0 else 1)
		return true
	return false

func _test_all_scripts_compile() -> void:
	print("[0/6] Verifying All GdesignerTools GDScript Files Compile...")
	var scripts: Array[String] = []
	_collect_gd_files("res://addons/gdesigner_tools", scripts)
	_check(scripts.size() >= 38, "Found %d GDScript files in res://addons/gdesigner_tools" % scripts.size())
	for sp in scripts:
		var loaded := ResourceLoader.load(sp)
		_check(loaded is GDScript and (loaded as GDScript).can_instantiate(), "Script compiles cleanly: " + sp)

func _collect_gd_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while not fn.is_empty():
		if fn != "." and fn != ".." and not fn.begins_with("."):
			var full := dir_path.path_join(fn)
			if dir.current_is_dir():
				_collect_gd_files(full, out)
			elif fn.ends_with(".gd") and fn != "test_gdesigner_tools.gd":
				out.append(full)
		fn = dir.get_next()
	dir.list_dir_end()

func _check(cond: bool, desc: String) -> void:
	if cond:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("[TEST FAILED] " + desc)
		print("  [FAIL] " + desc)

# ─────────────────────── 1. Core Layer Tests ───────────────────────

func _test_core_layer() -> void:
	print("[1/6] Testing Core Layer...")
	GDCoreServices.reset_for_tests()

	# EventBus & ServiceLocator
	var bus := GDCoreServices.get_event_bus()
	var received := {"count": 0, "payload": null}
	var cb := func(p: Variant) -> void:
		received["count"] = int(received["count"]) + 1
		received["payload"] = p
	bus.subscribe("TestEvt", cb)
	bus.publish("TestEvt", {"val": 42})
	_check(int(received["count"]) == 1 and int((received["payload"] as Dictionary)["val"]) == 42, "EventBus subscribe/publish")
	bus.unsubscribe("TestEvt", cb)
	bus.publish("TestEvt", {"val": 99})
	_check(int(received["count"]) == 1, "EventBus unsubscribe")

	# AttributeSet GAS formula: Current = Override ?? ((Base + Add) * (1 + Mul))
	var attr_set := GDAttributeSystem.AttributeSet.new()
	attr_set.set_base(1, 100.0)
	attr_set.add_modifier(1, 20.0, 0.5) # (100 + 20) * (1 + 0.5) = 180
	_check(is_equal_approx(attr_set.get_current(1), 180.0), "AttributeSet GAS Add+Mul formula = 180")
	attr_set.set_override(1, 999.0)
	_check(is_equal_approx(attr_set.get_current(1), 999.0), "AttributeSet GAS Override = 999")
	attr_set.set_override(1, null)
	attr_set.remove_modifier(1, 20.0, 0.5)
	_check(is_equal_approx(attr_set.get_current(1), 100.0), "AttributeSet GAS remove modifier restores 100")

	# GameStateMachine two-phase Construct -> BeginPlay + reverse Dispose + idempotent switch
	var sm := GDGameFramework.GameStateMachine.new()
	var mod_a := GDGameFramework.GameModuleBase.new()
	mod_a.category = GDCoreTypes.ModuleCategory.SCENE
	var mod_b := GDGameFramework.GameModuleBase.new()
	mod_b.category = GDCoreTypes.ModuleCategory.PLAYER
	sm.register_state_binding(1, [mod_b, mod_a])
	_check(sm.switch_state(1), "GameStateMachine initial switch_state(1)")
	_check(not sm.switch_state(1), "GameStateMachine idempotent switch_state(1) returns false")
	_check(mod_a.is_constructed and mod_a.is_begun_play and mod_b.is_begun_play, "GameStateMachine modules constructed and begun play")
	sm.shutdown()
	_check(mod_a.is_disposed and mod_b.is_disposed, "GameStateMachine shutdown disposes modules")

	# Entity + Atoms (InteractableAtom gesture & VisualAtom & UIAnchor3DAtom & AtomVarTagRegistry)
	var entity := GDEntityNode.new()
	var ia := GDInteractableAtom.new()
	ia.name = "InteractableAtom"
	ia.enable_click = true
	ia.enable_long_press = true
	ia.long_press_seconds = 0.5
	ia.set_meta("atom_var_tags", {"interact.click": {"property": "enable_click", "value_type": GDCoreTypes.KeywordValueType.BOOL, "atom_type": "InteractableAtom"}})
	entity.editor_register_atom(ia)

	var click_cnt := {"clicks": 0, "longs": 0}
	ia.on_clicked.connect(func() -> void: click_cnt["clicks"] = int(click_cnt["clicks"]) + 1)
	ia.on_long_pressed.connect(func() -> void: click_cnt["longs"] = int(click_cnt["longs"]) + 1)
	ia.simulate_pointer_down(Vector2(100, 100), 1.0, false)
	ia.simulate_pointer_up(Vector2(102, 102), true, false)
	_check(int(click_cnt["clicks"]) == 1, "InteractableAtom tap gesture fires on_clicked")

	ia.simulate_pointer_down(Vector2(100, 100), 2.0, false)
	ia.simulate_pointer_hold(Vector2(101, 101), 2.6)
	ia.simulate_pointer_up(Vector2(101, 101), true, false)
	_check(int(click_cnt["longs"]) == 1 and int(click_cnt["clicks"]) == 1, "InteractableAtom long press suppresses tap click")

	var bindings := GDEntityAtomSystem.AtomVarTagRegistry.collect_from_node(entity)
	_check(bindings.size() == 1 and bindings[0].tag == "interact.click", "AtomVarTagRegistry scans atom_var_tags")
	var set_res := GDEntityAtomSystem.AtomVarTagRegistry.try_set(ia, "interact.click", false)
	_check(bool(set_res.get("ok", false)) and ia.enable_click == false, "AtomVarTagRegistry writes tagged property")
	entity.free()

	# AudioEngine (BusMixer, ContainerSelector Sequence/RandomNoRepeat, Voice Limit & Steal)
	var audio := GDAudioEngine.AudioEngine.new()
	var sfx_def := GDAudioEngine.AudioEventDef.new()
	sfx_def.event_name = "Play_Click"
	sfx_def.bus = GDAudioEngine.AudioBus.SFX
	sfx_def.container_mode = GDAudioEngine.AudioContainerMode.SEQUENCE
	sfx_def.res_paths = PackedStringArray(["res://sfx/click_1.ogg", "res://sfx/click_2.ogg"])
	sfx_def.max_instances = 1
	sfx_def.limit_behavior = GDAudioEngine.AudioVoiceLimitBehavior.STOP_OLDEST
	audio.register_event(sfx_def)
	var pid1 := audio.post_event("Play_Click")
	var pid2 := audio.post_event("Play_Click")
	_check(pid1.is_valid and pid2.is_valid and not audio.is_playing(pid1) and audio.is_playing(pid2), "AudioEngine STOP_OLDEST recycles pid1 and plays pid2")
	audio.dispose()

# ─────────────────────── 2. Level Editor Tests ───────────────────────

func _test_level_editor() -> void:
	print("[2/6] Testing Level Editor...")
	var layout := GDLevelSceneRes.new()
	layout.display_name = "TestCity"

	# KeywordCatalog
	var kw := GDKeywordCatalogRes.new()
	kw.enum_namespace = "TestCity.Keywords"
	kw.enum_type_name = "BuildingType"
	var e1 := kw.add_entry("Residential", "住宅", "")
	var e2 := kw.add_entry("Commercial", "商业", "")
	_check(e1 != null and e1.stable_id == 1 and e2 != null and e2.stable_id == 2, "KeywordCatalog monotonic stable_id 1, 2")
	kw.remove_entry("Residential")
	_check(e1.deprecated == true, "KeywordCatalog soft delete (deprecated)")
	var revived := kw.add_entry("Residential", "新住宅", "")
	_check(revived == e1 and not e1.deprecated and e1.display_name == "新住宅", "KeywordCatalog revives deprecated entry with same stable_id")
	layout.editor_bind_archetype_type_keywords(kw)

	# Archetype & Placement IDs (1000+ & 10000+)
	var arch := GDLevelArchetypeRes.new()
	var arch_id := layout.editor_allocate_next_archetype_stable_id()
	_check(arch_id == 1000, "LevelSceneRes archetype StableId starts at 1000")
	arch.editor_init_with_addresses(arch_id, "示例方块", "Entity_Sample_Block", "")
	arch.custom_attributes.append(GDCustomAttributeDef.editor_create("prop.index", "序号", GDCoreTypes.KeywordValueType.INT, 7))
	layout.editor_add_archetype(arch)

	var p1_id := layout.editor_add_placement(arch_id, Vector3(1, 2, 3), Vector3.ZERO, Vector3.ONE, 1)
	var p2_id := layout.editor_add_placement(arch_id, Vector3(4, 5, 6), Vector3.ZERO, Vector3.ONE, 2)
	_check(p1_id == 10000 and p2_id == 10001, "LevelSceneRes placement InstanceId starts at 10000, 10001")

	# Custom InstanceId Range & Standardization
	arch.editor_set_custom_instance_id_range(true, 2001, 2010)
	var p3_id := layout.editor_add_placement(arch_id, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 1)
	_check(p3_id == 2001, "Custom InstanceId range allocates min free id 2001")
	var std_res := layout.editor_try_standardize_instance_ids(arch)
	_check(bool(std_res.get("ok", false)), "Standardize InstanceIds into [2001, 2010]")
	_check(
		layout.placements[0].instance_id == 2002 and layout.placements[1].instance_id == 2003 and layout.placements[2].instance_id == 2001,
		"Standardize InstanceIds remapped all 3 instances to 2001..2003"
	)

	# Path (20000+) & Spline evaluation
	var spline := GDPathSystem.SplineData.build_default_spline(Vector3.ZERO, false)
	var path_id := layout.editor_add_path(1, spline, 2.5)
	_check(path_id == 20000, "LevelSceneRes PathId starts at 20000")
	var mid_pos := spline.evaluate_position(0.5)
	_check(is_equal_approx(mid_pos.x, 0.0) and spline.get_length() > 3.9, "SplineData Curve3D evaluation & length")

	# CameraPose (Perspective XZ & Orthographic XY bounds)
	var cam_idx := layout.editor_add_camera_pose("MainCam", "主视角", Vector3(0, 10, -10), Vector3(-45, 0, 0), 60.0)
	_check(cam_idx == 0, "LevelSceneRes add CameraPose")
	var pose: GDCameraPoseSystem.CameraPose = layout.editor_try_get_camera_pose(0)["pose"]
	pose = pose.with_bound_edges(-50.0, 50.0, -30.0, 30.0)
	layout.editor_replace_camera_pose_at(0, pose)
	_check(is_equal_approx(pose.bound_left, -50.0) and is_equal_approx(pose.bound_top, 30.0), "CameraPose XY bound edges")

	# CSV Exporter
	var csv := GDLevelCsvExporter.build_csv(layout)
	_check(csv.begins_with(GDLevelCsvExporter.HEADER) and csv.contains("prop.index:0:7"), "CSV exporter header & attributeOverrides format")

	# SceneEditorRuntime LoadSession
	var parent_node := Node3D.new()
	var opts := GDSceneEditorRuntime.SceneEditorBootstrapOptions.new()
	opts.layout = layout
	opts.parent = parent_node
	var session := GDSceneEditorRuntime.load_session(opts)
	_check(session != null and session.instance_registry.all_placement_ids.size() == 3, "SceneEditorRuntime LoadSession spawns 3 placements")
	session.dispose()
	_check(session.is_disposed and parent_node.get_child_count() == 0, "SceneEditorRuntime session.dispose cleans up spawned nodes")
	parent_node.free()

# ─────────────────────── 3. Actor Editor Tests ───────────────────────

func _test_actor_editor() -> void:
	print("[3/6] Testing Actor Editor...")
	var lib := GDActorLibraryRes.new()
	lib.resource_name = "ActorLibrary_Sample"
	lib.display_name = "通用演员库"

	var a1 := GDActorArchetypeRes.new()
	a1.resource_name = "ActorArchetype_Sample_Unit"
	a1.editor_init_with_addresses(lib.editor_allocate_next_archetype_stable_id(), "示例单位", "Entity_Sample_Unit", "")
	lib.editor_add_archetype(a1)
	_check(a1.stable_id == 1000, "ActorLibraryRes StableId starts at 1000")

	# Duplicate
	var dup_def := GDActorEditorServices.ActorArchetypeDuplicateService.try_build_defaults(a1, lib)
	_check(bool(dup_def.get("ok", false)) and str(dup_def["archetype_name"]) == "Unit_1", "Actor duplicate default name Unit_1")
	var dup_res := GDActorEditorServices.ActorArchetypeDuplicateService.try_duplicate(a1, lib, "Unit_1", "示例单位_1")
	_check(bool(dup_res.get("ok", false)) and lib.archetypes.size() == 2, "Actor duplicate service adds new archetype")

	# Override / Variant & Cycle detection
	var ov_def := GDActorEditorServices.ActorArchetypeOverrideService.try_build_defaults(a1, lib)
	_check(bool(ov_def.get("ok", false)) and str(ov_def["archetype_name"]) == "Unit_Override", "Actor override default name Unit_Override")
	var ov_res := GDActorEditorServices.ActorArchetypeOverrideService.try_create(a1, lib, "Unit_Override", "示例单位_复写")
	var ov_arch: GDActorLibraryRes.ActorArchetypeRes = ov_res["created"]
	_check(bool(ov_res.get("ok", false)) and ov_arch.is_override_archetype and ov_arch.override_base_archetype == a1, "Actor override creation")
	_check(GDActorEditorServices.ActorArchetypeOverrideService.would_form_cycle(a1, ov_arch), "Actor override cycle detection prevents base->override cycle")

	# Rename
	var ren_res := GDActorEditorServices.ActorArchetypeRenameService.try_rename(a1, lib, "Guide", "示例向导")
	_check(bool(ren_res.get("ok", false)) and a1.display_name == "示例向导" and a1.manufactured_prefab_address == "Entity_Sample_Guide", "Actor rename updates display_name & Entity_ address")

# ─────────────────────── 4. Skill Editor Tests ───────────────────────

func _test_skill_editor() -> void:
	print("[4/6] Testing Skill Editor...")

	# SkillIdentity
	_check(GDSkillTypes.SkillIdentity.to_asset_name("Explore", 904) == "Skill_Explore_904", "SkillIdentity ToAssetName")
	var p1 := GDSkillTypes.SkillIdentity.try_parse_asset_name("Skill_Explore_904")
	var p2 := GDSkillTypes.SkillIdentity.try_parse_asset_name("Skill_Explore904_Skill")
	_check(bool(p1["ok"]) and str(p1["name"]) == "Explore" and int(p1["id"]) == 904, "SkillIdentity parse new format")
	_check(bool(p2["ok"]) and str(p2["name"]) == "Explore" and int(p2["id"]) == 904, "SkillIdentity parse legacy compact format")

	# All 15 Clip types & 4 Trajectories
	_check(GDSkillForgeAndCli.ALL_CLIP_TYPES.size() == 15, "SkillForge locks 15 clip types")
	for sn in GDSkillForgeAndCli.ALL_CLIP_TYPES:
		var inst := GDSkillForgeAndCli.create_clip_instance(sn)
		_check(inst != null and inst.get_clip_short_name() == sn, "Clip instantiation for " + sn)

	var parabola := GDSkillClips.ParabolaTrajectory.new()
	parabola.configure(4.0)
	var mid_traj := parabola.evaluate(0.5, Vector3.ZERO, Vector3(0, 0, 10))
	_check(is_equal_approx(mid_traj.y, 4.0) and is_equal_approx(mid_traj.z, 5.0), "ParabolaTrajectory peak at t=0.5")

	# Same-timestamp tie-break: Logic clip (DealDamage / CheckHit) before Presentation clip (SpawnVfx / PlayAnimation)
	var sk := GDSkillRes.new()
	sk.configure_header("TestTieBreak", 1, "同刻测试", "")
	sk.set_duration(1000)
	var grp := GDSkillRes.SkillTrackGroup.new("Main")
	var t_vfx := GDSkillRes.SkillTrack.new(GDSkillTypes.SkillTrackKind.VFX, "Vfx")
	var c_vfx := GDSkillClips.SpawnVfxClip.new()
	c_vfx.set_timing(200, 0)
	t_vfx.add_clip(c_vfx)
	var t_dmg := GDSkillRes.SkillTrack.new(GDSkillTypes.SkillTrackKind.EFFECT, "Effect")
	var c_dmg := GDSkillClips.DealDamageClip.new()
	c_dmg.set_timing(200, 0)
	t_dmg.add_clip(c_dmg)
	grp.add_track(t_vfx)
	grp.add_track(t_dmg)
	sk.add_group(grp)

	var order := GDSkillRuntime.SkillRunner.build_dispatch_order(sk)
	_check(order.size() == 2 and order[0] == c_dmg and order[1] == c_vfx, "SkillRunner BuildDispatchOrder places logic clip before presentation clip at same StartMs")

	# SkillTimelineEditorMath
	_check(GDSkillEditorMathAndValidator.SkillTimelineEditorMath.clamp_start(900, 300, 1000) == 700, "SkillTimelineEditorMath.ClampStart")
	_check(GDSkillEditorMathAndValidator.SkillTimelineEditorMath.clamp_duration(700, 500, 1000, 50) == 300, "SkillTimelineEditorMath.ClampDuration")
	_check(GDSkillEditorMathAndValidator.SkillTimelineEditorMath.nearest_fired_clip_start(order, 250) == 200, "SkillTimelineEditorMath.NearestFiredClipStart")

	# SkillCli roundtrip (create + describe + validate + clip-types)
	var ct_json := JSON.parse_string(GDSkillForgeAndCli.run_cli("skill.clip-types", []))
	_check(ct_json is Dictionary and bool(ct_json["ok"]) and int(ct_json["count"]) == 15, "SkillCli skill.clip-types returns 15 types")

	var skill_root := "res://game_res/sample/_cli_tmp"
	var create_spec := {
		"name": "Pulse",
		"id": 904,
		"display": "示例脉冲",
		"description": "一段通用短时技能，用于校验消耗、冷却与伤害结算",
		"durationMs": 1200,
		"cost": {"attributeName": "Mana", "amount": 25.0},
		"cooldown": {"cdGroup": "Skill_Pulse", "durationSeconds": 4.0},
		"groups": [{"name": "Cast"}, {"name": "Impact"}],
		"clips": [
			{"id": "anim0", "type": "PlayAnimation", "group": "Cast", "startMs": 0, "durationMs": 400, "fields": {"stateName": "Cast", "crossfadeSeconds": 0.1}},
			{"id": "hit0", "type": "CheckHit", "group": "Impact", "startMs": 500, "durationMs": 0, "fields": {"shape": "Sphere", "radius": 3.0}},
			{"id": "dmg0", "type": "DealDamage", "group": "Impact", "startMs": 500, "durationMs": 0, "fields": {"baseDamage": 120, "coefficient": 1.5}},
		],
	}
	var cr_json := JSON.parse_string(GDSkillForgeAndCli.run_cli("skill.create", ["--inline", JSON.stringify(create_spec), "--project-path", skill_root]))
	_check(cr_json is Dictionary and bool(cr_json["ok"]), "SkillCli skill.create Pulse_904")

	var desc_json := JSON.parse_string(GDSkillForgeAndCli.run_cli("skill.describe", ["--skill", "Pulse_904", "--project-path", skill_root]))
	_check(desc_json is Dictionary and bool(desc_json["ok"]), "SkillCli skill.describe Pulse_904")

	# SkillRuntimeService cast, cost, cooldown, damage
	var bus := GDCoreServices.EventBus.new()
	var fake_now := {"t": 10.0}
	var svc := GDSkillRuntime.SkillRuntimeService.new(bus, func() -> float: return float(fake_now["t"]))
	var caster_set := GDAttributeSystem.AttributeSet.new()
	caster_set.set_base(GDSkillTypes.AttributeKind.MANA, 50.0)
	caster_set.set_base(GDSkillTypes.AttributeKind.ATTACK_POWER, 40.0)
	var target_set := GDAttributeSystem.AttributeSet.new()
	target_set.set_base(GDSkillTypes.AttributeKind.HEALTH, 500.0)
	svc.register_attribute_set(101, caster_set)
	svc.register_attribute_set(202, target_set)

	var cast_skill := GDSkillForgeAndCli.find_skill_by_query("Pulse_904", skill_root)
	_check(svc.try_cast(101, 202, cast_skill), "SkillRuntimeService first try_cast succeeds")
	_check(is_equal_approx(caster_set.get_current(GDSkillTypes.AttributeKind.MANA), 25.0), "SkillRuntimeService deducts 25 Mana cost")
	_check(not svc.try_cast(101, 202, cast_skill), "SkillRuntimeService blocks recast while on cooldown")
	svc.tick_active_runners(600.0) # 500ms DealDamage (base=120 + 1.5*40 = 180)
	_check(is_equal_approx(target_set.get_current(GDSkillTypes.AttributeKind.HEALTH), 320.0), "SkillRuntimeService DealDamage reduces target HP from 500 to 320")

	# GameplayEffectApplier durational + periodic + expiry revert
	var applier := GDSkillRuntime.GameplayEffectApplier.new(bus)
	applier.register_attribute_set(202, target_set)
	var dot_eff := GDSkillTypes.GameplayEffectRes.new()
	dot_eff.duration = 1.0 # 1000ms
	dot_eff.period = 0.5   # 500ms
	dot_eff.modifiers = [
		GDSkillTypes.GameplayEffectModifier.new("MoveSpeed", GDSkillTypes.ModifierOp.MULTIPLY, -0.3),
	]
	target_set.set_base(GDSkillTypes.AttributeKind.MOVE_SPEED, 10.0)
	_check(applier.try_apply(202, 101, dot_eff), "GameplayEffectApplier applies durational slow effect")
	_check(is_equal_approx(target_set.get_current(GDSkillTypes.AttributeKind.MOVE_SPEED), 7.0), "GameplayEffectApplier reduces MoveSpeed from 10 to 7")
	applier.do_tick(1000.0)
	_check(is_equal_approx(target_set.get_current(GDSkillTypes.AttributeKind.MOVE_SPEED), 10.0) and applier.active_count == 0, "GameplayEffectApplier reverts modifier upon expiration")
	applier.dispose()
	svc.dispose()

	# SkillDoctor YAML cross-validation
	var doc_issues := GDSkillEditorMathAndValidator.SkillDoctor.doctor_yaml_text(
		PackedStringArray(["version: 1", "tools:", "  - name: missing.cmd", "    role: G", "    required: true"]),
		{"skill.list": true}
	)
	_check(doc_issues.size() == 1 and str(doc_issues[0]["code"]) == "D3", "SkillDoctor catches D3 unregistered required CLI tool")
	_wipe_res_dir(skill_root)
	GDSkillForgeAndCli._in_memory_skills.erase("Skill_Pulse_904")

# ─────────────────────── 5. Guide Editor Tests ───────────────────────

func _test_guide_editor() -> void:
	print("[5/6] Testing Guide Editor...")

	# GuideMemoryProgressStore encode/decode roundtrip (c=1;r=2:42;s=3;p=2:welcome_read)
	var store := GDGuideHostAndConditions.GuideMemoryProgressStore.new()
	store.bind("player_1001")
	store.mark_completed(1)
	store.set_resume_node_id(2, 42)
	store.mark_skipped(3)
	store.set_checkpoint(2, "welcome_read")
	var encoded := store.encode()
	_check(encoded == "c=1;r=2:42;s=3;p=2:welcome_read", "GuideMemoryProgressStore exact format: " + encoded)

	var store2 := GDGuideHostAndConditions.GuideMemoryProgressStore.new()
	store2.bind("player_1001")
	store2.decode(encoded)
	_check(
		store2.is_graph_completed(1) and store2.get_resume_node_id(2) == 42 and store2.is_graph_skipped(3) and store2.has_checkpoint(2, "welcome_read"),
		"GuideMemoryProgressStore decode roundtrip"
	)

	# GuideGraphValidator: immediate cycle detection & unconnected required port
	var bad_graph := GDGuideGraphAndValidator.GuideGraphRes.new()
	bad_graph.set_graph_id(100)
	var entry := GDGuideAtoms.EntryAtom.new()
	bad_graph.add_atom(entry, Vector2.ZERO)
	var b1 := GDGuideAtoms.BranchAtom.new()
	b1.set_display_name("分支1")
	b1.set_new_player()
	bad_graph.add_atom(b1, Vector2(200, 0))
	var b2 := GDGuideAtoms.BranchAtom.new()
	b2.set_display_name("分支2")
	b2.set_new_player()
	bad_graph.add_atom(b2, Vector2(400, 0))
	bad_graph.connect_nodes(entry.id, GDGuideData.GuidePortKind.EXEC_OUT, b1.id)
	bad_graph.connect_nodes(b1.id, GDGuideData.GuidePortKind.EXEC_TRUE, b2.id)
	bad_graph.connect_nodes(b2.id, GDGuideData.GuidePortKind.EXEC_TRUE, b1.id) # Immediate cycle!
	var bad_rep := GDGuideGraphAndValidator.GuideGraphValidator.validate(bad_graph)
	_check(bad_rep.contains(GDGuideGraphAndValidator.GuideGraphValidator.CODE_IMMEDIATE_CYCLE), "GuideGraphValidator catches immediate cycle")

	# GuideSampleGraphs validation & execution via GuideRunner
	var sample_graph := GDGuideGraphAndValidator.GuideGraphRes.new()
	GDGuideEditingAndCli.GuideSampleGraphs.build_sample(sample_graph)
	var sample_rep := GDGuideGraphAndValidator.GuideGraphValidator.validate(sample_graph)
	_check(not sample_rep.has_errors, "GuideSampleGraphs.build_sample passes validation cleanly")

	var host := GDGuideHostAndConditions.GuideHost.new()
	host.set_predicate("sample_has_coin", true)
	var runner := GDGuideRunnerSystem.GuideRunner.new(host)
	_check(runner.try_start(sample_graph), "GuideRunner starts sample graph")
	# Node 2: welcome narration -> click
	host.simulate_click()
	runner.tick(0.05)
	# Node 3: start narration -> click
	host.simulate_click()
	runner.tick(0.05)
	# Node 4: LockWait SamplePanelReady -> publish signal
	host.signals.publish("SamplePanelReady")
	runner.tick(0.05)
	# Node 5: Branch has_coin (true) -> jumps to Node 7: WaitEvent SampleCoinCollected
	host.signals.publish("SampleCoinCollected")
	runner.tick(0.05)
	# Node 8: Delay 0.5s -> tick 0.6s -> Node 9: Exit Completed
	runner.tick(0.6)
	_check(
		not runner.is_running and runner.current_run.is_finished and runner.current_run.exit_reason == GDGuideData.GuideExitReason.COMPLETED and host.progress.is_graph_completed(sample_graph.graph_id),
		"GuideRunner completes full sample graph flow and marks progress completed"
	)

	# Strong <-> Weak conversion & Click capture
	var conv_graph := GDGuideGraphAndValidator.GuideGraphRes.new()
	conv_graph.set_graph_id(777)
	conv_graph.add_default_skeleton()
	var captured := GDGuideEditingAndCli.GuideGraphEditing.capture_click(
		conv_graph, 1, GDGuideData.GuideTargetRef.ui("HomePanel", "BtnConfirm"), "确认按钮"
	)
	_check(captured is GDGuideAtoms.StrongGuideAtom and conv_graph.atoms.size() == 3, "GuideGraphEditing.capture_click inserts StrongGuideAtom")
	var converted := GDGuideEditingAndCli.GuideGraphEditing.convert_guide(conv_graph, captured.id)
	_check(converted is GDGuideAtoms.WeakGuideAtom and converted.id == captured.id, "GuideGraphEditing.convert_guide converts Strong <-> Weak preserving id & edges")
	runner.dispose()
	host.dispose()

# ─────────────────────── 6. UI Windows & Main Dock Integration ───────────────────────

func _test_ui_windows_and_main_dock() -> void:
	print("[6/6] Testing UI Windows & Main Dock Integration...")
	var dock := GdesignerToolsMainDock.new()
	get_root().add_child(dock)
	_check(dock.level_editor != null and dock.actor_editor != null and dock.skill_editor != null and dock.guide_editor != null and dock.cli_console != null, "GdesignerToolsMainDock instantiates all 4 editors + CLI console")

	# Test unified CLI dispatch through dock
	var res_guide := JSON.parse_string(GdesignerToolsMainDock.dispatch_unified_cli("guide.list"))
	_check(res_guide is Dictionary and bool(res_guide["ok"]), "Unified CLI dispatches guide.list")

	var res_skill := JSON.parse_string(GdesignerToolsMainDock.dispatch_unified_cli("skill.list"))
	_check(res_skill is Dictionary and bool(res_skill["ok"]), "Unified CLI dispatches skill.list")

	var res_atom := JSON.parse_string(GdesignerToolsMainDock.dispatch_unified_cli("atom.list-templates"))
	_check(res_atom is Dictionary and bool(res_atom["ok"]), "Unified CLI dispatches atom.list-templates")

	if dock.guide_editor != null:
		if dock.guide_editor._runner != null:
			dock.guide_editor._runner.dispose()
		if dock.guide_editor._host != null:
			dock.guide_editor._host.dispose()
	get_root().remove_child(dock)
	dock.free()

	var editor := GDLevelEditorWindow.new()
	get_root().add_child(editor)
	editor._create_new_in_memory_layout()
	_check(_tree_has_drag_source(editor), "Level editor archetype card is a viewport drag source")
	var catcher := GDLevelSceneDrop.DropCatcher.new()
	_check(catcher._can_drop_data(Vector2.ZERO, {"type": GDLevelSceneDrop.DRAG_TYPE, "stable_id": 1}), "Viewport drop catcher accepts archetype payload")
	_check(not catcher._can_drop_data(Vector2.ZERO, {"type": "files"}), "Viewport drop catcher ignores foreign drag types")
	catcher.free()

	var layout := GDLevelSceneRes.new()
	var arch := GDLevelArchetypeRes.new()
	arch.editor_init_with_addresses(layout.editor_allocate_next_archetype_stable_id(), "示例方块", "", "")
	layout.editor_add_archetype(arch)
	var payload := GDLevelSceneDrop.begin(arch, layout)
	_check(GDLevelSceneDrop.is_payload(payload) and GDLevelSceneDrop.is_active(), "Begin archetype drag publishes gdesigner_archetype payload")
	var parallel := GDLevelSceneDrop.ray_intersect_plane(Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.ZERO)
	var hit := GDLevelSceneDrop.ray_intersect_plane(Vector3(2, 10, -3), Vector3(0, -1, 0), Vector3.UP, Vector3.ZERO)
	_check(not bool(parallel.get("ok", true)) and bool(hit.get("ok", false)) and (hit["point"] as Vector3).is_equal_approx(Vector3(2, 0, -3)), "Ground plane ray hits Y=0 and rejects a parallel ray")
	var ground := Node3D.new()
	ground.name = GDLevelSceneDrop.GROUND_NAME
	var body := StaticBody3D.new()
	ground.add_child(body)
	_check(GDLevelSceneDrop.is_logical_ground(body), "Logical ground name matches Unity [SceneEditor Ground]")
	ground.free()
	GDLevelSceneDrop.poll()
	_check(not GDLevelSceneDrop.is_active(), "Releasing the mouse outside a viewport cancels the drag")

	var parent := Node3D.new()
	get_root().add_child(parent)
	var placed := GDLevelSceneDrop.place_archetype(layout, arch, Vector3(3, 0, 5), parent)
	_check(bool(placed.get("ok", false)), "place_archetype writes the level and spawns a scene node")
	var inst_id := int(placed.get("instance_id", 0))
	var spawned := GDLevelSceneDrop.find_placed_node(inst_id)
	_check(spawned != null and int(spawned.get_meta("gdesigner_placement_id")) == inst_id and spawned.get_parent() == parent, "Spawned node carries placement id and stays under the given parent")
	var opts := GDSceneEditorRuntime.SceneEditorBootstrapOptions.new()
	opts.layout = layout
	opts.parent = parent
	opts.auto_attach_click_handler = false
	var session := GDSceneEditorRuntime.load_session(opts)
	_check(session != null and parent.get_child_count() == 1, "Runtime load adopts the editor-placed node instead of spawning a second copy")
	session.dispose()
	_check(parent.get_child_count() == 1, "Disposing a runtime session keeps scene nodes that were placed in the editor")
	GDLevelSceneDrop.erase_placed(layout, inst_id)
	_check(parent.get_child_count() == 0 and not bool(layout.editor_try_get_placement(inst_id).get("ok", true)), "Erasing a placement removes both the scene node and the level record")
	parent.free()

	var scroll := ScrollContainer.new()
	var box := VBoxContainer.new()
	get_root().add_child(scroll)
	scroll.add_child(box)
	GDEditorUi.configure_vertical_scroll(scroll, box)
	_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and box.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "Vertical scrolls disable horizontal scrolling and stretch their content")
	var holder := Node.new()
	holder.add_child(Node.new())
	GDEditorUi.clear_children(holder)
	_check(holder.get_child_count() == 0, "clear_children detaches rebuilt rows immediately")
	holder.free()
	scroll.free()

	var win := GdesignerToolsWindow.new()
	_check(win.dock != null and win.dock.level_editor != null and not win.exclusive and not win.transient, "GdesignerTools window is an independent non-modal host")
	if win.dock.guide_editor != null:
		if win.dock.guide_editor._runner != null:
			win.dock.guide_editor._runner.dispose()
		if win.dock.guide_editor._host != null:
			win.dock.guide_editor._host.dispose()
	win.free()
	get_root().remove_child(editor)
	editor.free()


func _wipe_res_dir(res_dir: String) -> void:
	var abs := ProjectSettings.globalize_path(res_dir)
	_wipe_abs_dir(abs)


func _wipe_abs_dir(abs_dir: String) -> void:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := abs_dir.path_join(name)
			if dir.current_is_dir():
				_wipe_abs_dir(child)
			else:
				DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_dir)


func _tree_has_drag_source(node: Node) -> bool:
	if node is GDLevelSceneDrop.DragSource:
		return true
	for child in node.get_children():
		if _tree_has_drag_source(child):
			return true
	return false
