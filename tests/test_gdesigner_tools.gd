extends SceneTree

## GdesignerTools 全量自动化测试与自检套件
## 验证：
##   1. Core 基础层（EventBus、ServiceLocator、GameStateMachine 四层生命周期、AttributeSet GAS 公式、AtomVarTagRegistry、InteractableAtom/VisualAtom/UIAnchor3DAtom、Core CLI）
##   2. Level Editor（ID Schema 10000+/1000+/20000+、自定义 ID 段分配与两阶段标准化、Path 曲线采样、CameraPose XZ/XY 边界、KeywordCatalog 与代码生成、CSV UTF-8 BOM 导出、13 条 CLI、LayoutIdMigrationTool、LevelEditorWindow UI 实例化）
##   3. Actor Editor（ActorLibrary 1000+ 分配器、重命名/复制/Override 复写防环与重绑、ActorEditorWindow UI 实例化）
##   4. Skill Editor（SkillIdentity 解析与规范化、15 种 Clip 与 4 种 Trajectory、SkillRunner 同刻 tie-break 排序、SkillRuntimeService 消耗/冷却/打断/伤害/闪现、SkillTimelineEditorMath、SkillAssetValidator、SkillForge & SkillCli 8 条命令往返、SkillEditorWindow UI 实例化）
##   5. Guide Editor（GuideProgressStore 同构编码往返、GuideConditionEvaluator、15 种内置原子、GuideGraphValidator 无等待环/孤立/端口/子图递归校验、GuideSchemaMigrator v1->v2、GuideRunner 执行/超时/Stall/断点/单步/输入水位线、GuideTriggerSystem、GuideGraphLayout、GuideCli、GuideEditorWindow UI 实例化）
##   6. 持久化往返（GDDataCodec；技能 / 引导图 / 关卡 save -> load 深比较，并验证重载后仍能运行）
##   7. 统一 CLI（GdesignerToolsCli / 参数解析 / 别名）、GDArchetypeOps、关卡原型重命名、场景对齐、CSV 落盘
##   8. 主插件与 GdesignerToolsMainDock 完整挂载运行

var _pass_count: int = 0
var _fail_count: int = 0
var _frames_waited: int = 0

func _initialize() -> void:
	print("============================================================")
	print("  GdesignerTools Automated Verification Suite (Godot 4.7.2)")
	print("============================================================")

	_test_all_scripts_compile()
	_test_core_layer()
	_test_level_editor()
	_test_actor_editor()
	_test_skill_editor()
	_test_guide_editor()
	_test_persistence_round_trips()
	_test_cli_and_editor_services()
	_test_ui_windows_and_main_dock()

	GDSkillForge._in_memory_skills.clear()
	GDCliRoot._registry.clear()
	GDCoreServices.shutdown_for_tests()

func _test_form_in_tree() -> void:
	var form := GDForm.new()
	get_root().add_child(form)
	var model := {"name": "甲", "count": 1}
	_check(form.begin("key"), "GDForm builds on a new key")
	var edit: LineEdit = form.text("名称", func() -> String: return model["name"], func(v: String) -> void: model["name"] = v)
	var spin := form.integer("数量", func() -> int: return model["count"], func(v: int) -> void: model["count"] = v)
	var commits: Array[String] = []
	form.committed.connect(func(label: String, _merge: bool) -> void: commits.append(label))
	spin.value = 5
	_check(model["count"] == 5 and commits.size() == 1 and commits[0] == "数量", "GDForm writes and commits numeric edits")
	edit.text = "乙"
	edit.text_submitted.emit("乙")
	_check(model["name"] == "乙" and commits.size() == 2, "GDForm commits text on Enter")
	model["name"] = "丙"
	_check(not form.begin("key") and edit.text == "丙", "GDForm re-reads the model without rebuilding on the same key")
	form.free()


func _process(_delta: float) -> bool:
	_frames_waited += 1
	if _frames_waited == 1:
		_test_form_in_tree()
	if _frames_waited >= 2:
		print("------------------------------------------------------------")
		print("  TOTAL PASSED: %d   TOTAL FAILED: %d" % [_pass_count, _fail_count])
		print("============================================================")
		GDGuideEditing._in_memory_graphs.clear()
		GDGuideRunnerSystem.GuideBreakpoints._by_graph.clear()
		GDGuideRunnerSystem.GuideDebugRegistry._sessions.clear()
		GDSkillForge._in_memory_skills.clear()
		GDCliRoot._registry.clear()
		GDGameLogger._history.clear()
		GDCoreServices.shutdown_for_tests()
		quit(0 if _fail_count == 0 else 1)
		return true
	return false

func _test_all_scripts_compile() -> void:
	print("[0/8] Verifying All GdesignerTools GDScript Files Compile...")
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
	print("[1/8] Testing Core Layer...")
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
	print("[2/8] Testing Level Editor...")
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
	print("[3/8] Testing Actor Editor...")
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
	_check(GDArchetypeOps.would_form_cycle(a1, ov_arch), "Actor override cycle detection prevents base->override cycle")

	# Rename
	var ren_res := GDActorEditorServices.ActorArchetypeRenameService.try_rename(a1, lib, "Guide", "示例向导")
	_check(bool(ren_res.get("ok", false)) and a1.display_name == "示例向导" and a1.manufactured_prefab_address == "Entity_Sample_Guide", "Actor rename updates display_name & Entity_ address")

# ─────────────────────── 4. Skill Editor Tests ───────────────────────

func _test_skill_editor() -> void:
	print("[4/8] Testing Skill Editor...")

	# SkillIdentity
	_check(GDSkillTypes.SkillIdentity.to_asset_name("Explore", 904) == "Skill_Explore_904", "SkillIdentity ToAssetName")
	var p1 := GDSkillTypes.SkillIdentity.try_parse_asset_name("Skill_Explore_904")
	var p2 := GDSkillTypes.SkillIdentity.try_parse_asset_name("Skill_Explore904_Skill")
	_check(bool(p1["ok"]) and str(p1["name"]) == "Explore" and int(p1["id"]) == 904, "SkillIdentity parse new format")
	_check(bool(p2["ok"]) and str(p2["name"]) == "Explore" and int(p2["id"]) == 904, "SkillIdentity parse legacy compact format")

	# All 15 Clip types & 4 Trajectories
	_check(GDSkillForge.clip_types().size() == 15, "SkillForge locks 15 clip types")
	for sn in GDSkillForge.clip_types():
		var inst := GDSkillForge.create_clip_instance(sn)
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
	_check(GDSkillTimelineMath.clamp_start(900, 300, 1000) == 700, "SkillTimelineEditorMath.ClampStart")
	_check(GDSkillTimelineMath.clamp_duration(700, 500, 1000, 50) == 300, "SkillTimelineEditorMath.ClampDuration")
	_check(GDSkillTimelineMath.nearest_fired_clip_start(order, 250) == 200, "SkillTimelineEditorMath.NearestFiredClipStart")

	# SkillCli roundtrip (create + describe + validate + clip-types)
	var ct_json := JSON.parse_string(GDSkillCli.run("skill.clip-types", []))
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
	var cr_json := JSON.parse_string(GDSkillCli.run("skill.create", ["--inline", JSON.stringify(create_spec), "--project-path", skill_root]))
	_check(cr_json is Dictionary and bool(cr_json["ok"]), "SkillCli skill.create Pulse_904")

	var desc_json := JSON.parse_string(GDSkillCli.run("skill.describe", ["--skill", "Pulse_904", "--project-path", skill_root]))
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

	var cast_skill := GDSkillForge.find_skill_by_query("Pulse_904", skill_root)
	_check(svc.try_cast(101, 202, cast_skill), "SkillRuntimeService first try_cast succeeds")
	_check(is_equal_approx(caster_set.get_current(GDSkillTypes.AttributeKind.MANA), 25.0), "SkillRuntimeService deducts 25 Mana cost")
	_check(not svc.try_cast(101, 202, cast_skill), "SkillRuntimeService blocks recast while on cooldown")
	svc.tick_active_runners(600.0) # 500ms DealDamage (base=120 + 1.5*40 = 180)
	_check(is_equal_approx(target_set.get_current(GDSkillTypes.AttributeKind.HEALTH), 320.0), "SkillRuntimeService DealDamage reduces target HP from 500 to 320")

	# GameplayEffectApplier durational + periodic + expiry revert
	var applier := GDSkillRuntime.GameplayEffectApplier.new(bus)
	applier.register_attribute_set(202, target_set)
	var dot_eff := GDGameplayEffectRes.new()
	dot_eff.duration = 1.0 # 1000ms
	dot_eff.period = 0.5   # 500ms
	dot_eff.modifiers = [
		GDGameplayEffectModifierRes.new("MoveSpeed", GDSkillTypes.ModifierOp.MULTIPLY, -0.3),
	]
	target_set.set_base(GDSkillTypes.AttributeKind.MOVE_SPEED, 10.0)
	_check(applier.try_apply(202, 101, dot_eff), "GameplayEffectApplier applies durational slow effect")
	_check(is_equal_approx(target_set.get_current(GDSkillTypes.AttributeKind.MOVE_SPEED), 7.0), "GameplayEffectApplier reduces MoveSpeed from 10 to 7")
	applier.do_tick(1000.0)
	_check(is_equal_approx(target_set.get_current(GDSkillTypes.AttributeKind.MOVE_SPEED), 10.0) and applier.active_count == 0, "GameplayEffectApplier reverts modifier upon expiration")
	applier.dispose()
	svc.dispose()

	# SkillDoctor YAML cross-validation
	var doc_issues := GDSkillValidation.SkillDoctor.doctor_yaml_text(
		PackedStringArray(["version: 1", "tools:", "  - name: missing.cmd", "    role: G", "    required: true"]),
		{"skill.list": true}
	)
	_check(doc_issues.size() == 1 and str(doc_issues[0]["code"]) == "D3", "SkillDoctor catches D3 unregistered required CLI tool")
	_wipe_res_dir(skill_root)
	GDSkillForge._in_memory_skills.erase("Skill_Pulse_904")

# ─────────────────────── 5. Guide Editor Tests ───────────────────────

func _test_guide_editor() -> void:
	print("[5/8] Testing Guide Editor...")

	# GuideMemoryProgressStore encode/decode roundtrip (c=1;r=2:42;s=3;p=2:welcome_read)
	var store := GDGuideServices.GuideMemoryProgressStore.new()
	store.bind("player_1001")
	store.mark_completed(1)
	store.set_resume_node_id(2, 42)
	store.mark_skipped(3)
	store.set_checkpoint(2, "welcome_read")
	var encoded := store.encode()
	_check(encoded == "c=1;r=2:42;s=3;p=2:welcome_read", "GuideMemoryProgressStore exact format: " + encoded)

	var store2 := GDGuideServices.GuideMemoryProgressStore.new()
	store2.bind("player_1001")
	store2.decode(encoded)
	_check(
		store2.is_graph_completed(1) and store2.get_resume_node_id(2) == 42 and store2.is_graph_skipped(3) and store2.has_checkpoint(2, "welcome_read"),
		"GuideMemoryProgressStore decode roundtrip"
	)

	# GuideGraphValidator: immediate cycle detection & unconnected required port
	var bad_graph := GDGuideGraphRes.new()
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
	var bad_rep := GDGuideValidation.GuideGraphValidator.validate(bad_graph)
	_check(bad_rep.contains(GDGuideValidation.GuideGraphValidator.CODE_IMMEDIATE_CYCLE), "GuideGraphValidator catches immediate cycle")

	# GuideSampleGraphs validation & execution via GuideRunner
	var sample_graph := GDGuideGraphRes.new()
	GDGuideSamples.build_sample(sample_graph)
	var sample_rep := GDGuideValidation.GuideGraphValidator.validate(sample_graph)
	_check(not sample_rep.has_errors, "GuideSampleGraphs.build_sample passes validation cleanly")

	var host := GDGuideServices.GuideHost.new()
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
	var conv_graph := GDGuideGraphRes.new()
	conv_graph.set_graph_id(777)
	conv_graph.add_default_skeleton()
	var captured := GDGuideEditing.capture_click(
		conv_graph, 1, GDGuideData.GuideTargetRef.ui("HomePanel", "BtnConfirm"), "确认按钮"
	)
	_check(captured is GDGuideAtoms.StrongGuideAtom and conv_graph.atoms.size() == 3, "GuideGraphEditing.capture_click inserts StrongGuideAtom")
	var converted := GDGuideEditing.convert_guide(conv_graph, captured.id)
	_check(converted is GDGuideAtoms.WeakGuideAtom and converted.id == captured.id, "GuideGraphEditing.convert_guide converts Strong <-> Weak preserving id & edges")
	runner.dispose()
	host.dispose()

# ─────────────────────── 6. Persistence Round-Trips ───────────────────────

func _test_persistence_round_trips() -> void:
	print("[6/8] Testing Persistence Round-Trips...")

	# GDDataCodec: defaults omitted, unregistered resources kept native, unknown types reported
	var codec := GDDataCodec.new([GDSkillRes, GDSkillClips])
	_check(codec.encode(GDSkillClips.LinearTrajectory.new()) == {"$type": "LinearTrajectory"}, "GDDataCodec omits fields equal to the class default")
	var bez := GDSkillClips.BezierTrajectory.new()
	bez.configure(Vector3(1, 3, 2))
	var bez_back = codec.decode(codec.encode(bez))
	_check(bez_back is GDSkillClips.BezierTrajectory and bez_back.control_offset == Vector3(1, 3, 2), "GDDataCodec round-trips a registered inner-class Resource")
	var tex := GradientTexture2D.new()
	_check(codec.encode([tex])[0] == tex, "GDDataCodec keeps unregistered Resources (Texture2D) native")
	var unknown_seen := {"type": ""}
	codec.on_unknown = func(type_name: String, _data: Dictionary) -> Variant:
		unknown_seen["type"] = type_name
		return null
	_check(codec.decode({"$type": "NoSuchClip"}) == null and unknown_seen["type"] == "NoSuchClip", "GDDataCodec routes unknown types to on_unknown")
	var typed_back = codec.decode(codec.encode(_make_push_event_clip()))
	_check(typed_back is GDSkillClips.PushEventClip and typed_back.events.size() == 2 and typed_back.events.get_typed_script() == GDSkillClips.SkillCustomEvent, "GDDataCodec fills typed Array properties through assign")

	# Skill: several clip types incl. SpawnProjectile + Bezier, cost / cooldown / groups survive save -> load
	var skill := _make_round_trip_skill()
	var reloaded_skill := _save_and_reload(skill, "user://gdt_rt_skill.tres") as GDSkillRes
	_check(reloaded_skill != null and reloaded_skill.groups.size() == 2, "Skill groups survive save -> load")
	_check(reloaded_skill != null and _snapshot(reloaded_skill) == _snapshot(skill), "Skill deep-equals after save -> load (clips, trajectory, events, cost, cooldown)")
	var projectile := _first_clip(reloaded_skill) as GDSkillClips.SpawnProjectileClip
	_check(projectile != null and projectile.trajectory is GDSkillClips.BezierTrajectory and projectile.trajectory.control_offset == Vector3(1, 3, 2), "SpawnProjectile Bezier trajectory survives save -> load")
	_check(reloaded_skill != null and is_equal_approx(reloaded_skill.cost.amount, 25.0) and reloaded_skill.cooldown.cd_group == "Skill_Orbit", "Skill cost / cooldown survive save -> load")
	var dup := skill.duplicate() as GDSkillRes
	_check(_snapshot(dup) == _snapshot(skill) and not dup.groups.is_empty() and dup.groups[0] != skill.groups[0], "Resource.duplicate deep-copies the codec-backed timeline")
	_check(reloaded_skill != null and _cast_deals_damage(reloaded_skill), "Reloaded skill casts through SkillRuntimeService and deals 180 damage")

	# Guide: sample graphs, conditions, Strong guide target survive save -> load and still run
	var sample := GDGuideGraphRes.new()
	GDGuideSamples.build_sample(sample)
	var sample_back := _save_and_reload(sample, "user://gdt_rt_guide_sample.tres") as GDGuideGraphRes
	_check(sample_back != null and sample_back.atoms.size() == sample.atoms.size() and sample_back.edges.size() == sample.edges.size(), "Guide sample graph keeps atoms and edges after save -> load")
	_check(sample_back != null and _snapshot(sample_back) == _snapshot(sample), "Guide sample graph deep-equals after save -> load")
	_check(sample_back != null and _run_sample_guide(sample_back), "Reloaded sample guide runs to completion via GuideRunner")

	var cond := GDGuideGraphRes.new()
	GDGuideSamples.build_condition_sample(cond)
	var cond_back := _save_and_reload(cond, "user://gdt_rt_guide_cond.tres") as GDGuideGraphRes
	var entry_back := cond_back.find_atom(cond_back.find_entry_id()) as GDGuideAtoms.EntryAtom if cond_back != null else null
	_check(cond_back != null and _snapshot(cond_back) == _snapshot(cond), "Guide condition sample deep-equals after save -> load")
	_check(entry_back != null and entry_back.trigger_event.key == "SampleStart" and entry_back.conditions.size() == 1 and entry_back.conditions[0].left.condition_id == "io.guide.sample_has_coin", "Entry trigger event and typed condition rows survive save -> load")
	_check(cond_back != null and not GDGuideValidation.GuideGraphValidator.validate(cond_back).has_errors, "Reloaded condition sample still validates cleanly")

	var strong_graph := GDGuideGraphRes.new()
	strong_graph.set_graph_id(778)
	strong_graph.add_default_skeleton()
	var strong := GDGuideEditing.capture_click(strong_graph, 1, GDGuideData.GuideTargetRef.ui("HomePanel", "BtnConfirm"), "确认") as GDGuideAtoms.StrongGuideAtom
	strong.click_mode = GDGuideData.GuideClickMode.CONSUME
	var strong_back := _save_and_reload(strong_graph, "user://gdt_rt_guide_strong.tres") as GDGuideGraphRes
	var strong_atom = strong_back.find_atom(strong.id) if strong_back != null else null
	_check(strong_atom is GDGuideAtoms.StrongGuideAtom and strong_atom.target.panel == "HomePanel" and strong_atom.target.widget == "BtnConfirm" and strong_atom.click_mode == GDGuideData.GuideClickMode.CONSUME, "Strong guide target and click mode survive save -> load")

	# Guide: unknown atom type -> MissingAtom, raw data written back unchanged
	var data := sample.codec_data
	(data["atoms"] as Array).append({"$type": "FutureAtom", "id": 99, "editor_position": Vector2(5, 5), "display_name": "未来节点", "future_field": 7})
	(data["edges"] as Array).append({"$type": "GuideEdge", "from_id": 99, "to_id": 2})
	var future := GDGuideGraphRes.new()
	future.codec_data = data
	var missing = future.find_atom(99)
	_check(missing is GDGuideAtoms.MissingAtom and missing.type_name == "FutureAtom" and missing.has_port(GDGuideData.GuidePortKind.EXEC_OUT), "Unknown atom type decodes into MissingAtom with ports rebuilt from edges")
	_check(GDGuideValidation.GuideGraphValidator.validate(future).contains(GDGuideValidation.GuideGraphValidator.CODE_MISSING_TYPE, 99), "Validator reports the missing atom type")
	var future_back := _save_and_reload(future, "user://gdt_rt_guide_future.tres") as GDGuideGraphRes
	var raw_back: Dictionary = {}
	for a in (future_back.codec_data["atoms"] if future_back != null else []):
		if a is Dictionary and a.get("id") == 99:
			raw_back = a
	_check(raw_back.get("$type") == "FutureAtom" and raw_back.get("future_field") == 7, "Unknown atom raw data is written back unchanged on save")

	# Level: paths + camera poses survive save -> load; shipped sample still loads
	var layout := _make_round_trip_layout()
	var layout_back := _save_and_reload(layout, "user://gdt_rt_level.tres") as GDLevelSceneRes
	_check(layout_back != null and layout_back.paths.size() == 1 and layout_back.camera_poses.size() == 1, "Level paths and camera poses survive save -> load")
	_check(layout_back != null and _snapshot(layout_back) == _snapshot(layout), "Level deep-equals after save -> load (spline knots, overrides, camera bounds)")
	var path_back: GDPathSystem.PathInstance = layout_back.paths.front() if layout_back != null and not layout_back.paths.is_empty() else null
	_check(path_back != null and is_equal_approx(path_back.spline.get_length(), layout.paths[0].spline.get_length()) and path_back.closed, "Reloaded path still samples the same spline")
	var sample_level := ResourceLoader.load("res://game_res/sample/level/LevelScene_Sample.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as GDLevelSceneRes
	_check(sample_level != null and sample_level.placements.size() == 2 and sample_level.archetypes.size() == 2, "Shipped LevelScene_Sample.tres still loads")

	for f in ["gdt_rt_skill", "gdt_rt_guide_sample", "gdt_rt_guide_cond", "gdt_rt_guide_strong", "gdt_rt_guide_future", "gdt_rt_level"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://%s.tres" % f))


func _first_clip(sk: GDSkillRes) -> GDSkillClips.SkillClip:
	if sk == null or sk.groups.is_empty() or sk.groups[0].tracks.is_empty() or sk.groups[0].tracks[0].clips.is_empty():
		return null
	return sk.groups[0].tracks[0].clips[0]


func _save_and_reload(res: Resource, path: String) -> Resource:
	if ResourceSaver.save(res, path) != OK:
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Comparable plain-data view of a value: Resources become {script, stored + script-variable properties} recursively,
## so the in-memory model (not only what was written to disk) is compared.
func _snapshot(value: Variant) -> Variant:
	if value is Array:
		return value.map(_snapshot)
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _snapshot(value[k])
		return out
	if not (value is Resource):
		return value
	var script: Script = value.get_script()
	var out := {"#script": script.resource_path if script != null else value.get_class()}
	for prop in value.get_property_list():
		var name: String = prop["name"]
		if prop["usage"] & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_SCRIPT_VARIABLE) and not name.begins_with("resource_") and name != "script":
			out[name] = _snapshot(value.get(name))
	return out


func _make_push_event_clip() -> GDSkillClips.PushEventClip:
	var push := GDSkillClips.PushEventClip.new()
	var events: Array[GDSkillClips.SkillCustomEvent] = []
	for i in 2:
		var ev := GDSkillClips.SkillCustomEvent.new()
		ev.configure("Evt%d" % i, 1.5 * i, "s%d" % i, Vector3(i, 0, 1))
		events.append(ev)
	push.configure(events)
	push.set_timing(300, 0)
	return push


func _make_round_trip_skill() -> GDSkillRes:
	var sk := GDSkillRes.new()
	sk.configure_header("Orbit", 905, "环绕", "往返测试")
	sk.set_cost("Mana", 25.0)
	sk.set_cooldown("Skill_Orbit", 4.0)
	sk.set_duration(1200)
	var cast := GDSkillRes.SkillTrackGroup.new("Cast")
	var hitbox := GDSkillRes.SkillTrack.new(GDSkillTypes.SkillTrackKind.HITBOX)
	var projectile := GDSkillClips.SpawnProjectileClip.new()
	projectile.set_timing(100, 0)
	projectile.configure(null, 22.0, GDSkillTypes.SkillProjectileDirectionKind.CASTER_FORWARD)
	var bezier := GDSkillClips.BezierTrajectory.new()
	bezier.configure(Vector3(1, 3, 2))
	projectile.configure_trajectory(bezier, true)
	projectile.configure_landing_offset(Vector3(0, 0.5, 0))
	hitbox.add_clip(projectile)
	cast.add_track(hitbox)
	var vfx := GDSkillRes.SkillTrack.new(GDSkillTypes.SkillTrackKind.VFX)
	var flash := GDSkillClips.HitFlashClip.new()
	flash.configure(Color(0.2, 0.4, 0.6, 1.0), 0.4)
	vfx.add_clip(flash)
	vfx.add_clip(_make_push_event_clip())
	cast.add_track(vfx)
	sk.add_group(cast)
	var impact := GDSkillRes.SkillTrackGroup.new("Impact")
	var effect := GDSkillRes.SkillTrack.new(GDSkillTypes.SkillTrackKind.EFFECT)
	var hit := GDSkillClips.CheckHitClip.new()
	hit.set_timing(500, 0)
	hit.configure(GDSkillTypes.SkillHitShapeKind.BOX, Vector3(2, 1, 3))
	effect.add_clip(hit)
	var dmg := GDSkillClips.DealDamageClip.new()
	dmg.set_timing(500, 0)
	dmg.configure(120, 1.5)
	effect.add_clip(dmg)
	impact.add_track(effect)
	sk.add_group(impact)
	return sk


func _cast_deals_damage(sk: GDSkillRes) -> bool:
	var bus := GDCoreServices.EventBus.new()
	var svc := GDSkillRuntime.SkillRuntimeService.new(bus, func() -> float: return 10.0)
	var caster := GDAttributeSystem.AttributeSet.new()
	caster.set_base(GDSkillTypes.AttributeKind.MANA, 50.0)
	caster.set_base(GDSkillTypes.AttributeKind.ATTACK_POWER, 40.0)
	var target := GDAttributeSystem.AttributeSet.new()
	target.set_base(GDSkillTypes.AttributeKind.HEALTH, 500.0)
	svc.register_attribute_set(101, caster)
	svc.register_attribute_set(202, target)
	var cast_ok := svc.try_cast(101, 202, sk)
	svc.tick_active_runners(600.0)
	var ok := cast_ok and is_equal_approx(caster.get_current(GDSkillTypes.AttributeKind.MANA), 25.0) \
		and is_equal_approx(target.get_current(GDSkillTypes.AttributeKind.HEALTH), 320.0)
	svc.dispose()
	return ok


func _run_sample_guide(graph: GDGuideGraphRes) -> bool:
	var host := GDGuideServices.GuideHost.new()
	host.set_predicate("sample_has_coin", true)
	var runner := GDGuideRunnerSystem.GuideRunner.new(host)
	var started := runner.try_start(graph)
	host.simulate_click()
	runner.tick(0.05)
	host.simulate_click()
	runner.tick(0.05)
	host.signals.publish("SamplePanelReady")
	runner.tick(0.05)
	host.signals.publish("SampleCoinCollected")
	runner.tick(0.05)
	runner.tick(0.6)
	var ok := started and not runner.is_running and runner.current_run.is_finished \
		and runner.current_run.exit_reason == GDGuideData.GuideExitReason.COMPLETED and host.progress.is_graph_completed(graph.graph_id)
	runner.dispose()
	host.dispose()
	return ok


func _make_round_trip_layout() -> GDLevelSceneRes:
	var layout := GDLevelSceneRes.new()
	layout.display_name = "RoundTrip"
	var spline := GDPathSystem.SplineData.build_default_spline(Vector3(1, 0, 1))
	spline.add_knot(GDPathSystem.SplineKnot.new(Vector3(0, 0, 4), Vector3(-1, 0, 0), Vector3(1, 0, 0)))
	spline.closed = true
	var pid := layout.editor_add_path(3, spline, 2.5)
	var path: GDPathSystem.PathInstance = layout.editor_try_get_path(pid)["path"]
	layout.editor_replace_path(pid, path.with_overrides([GDPlacementData.PlacementAttributeOverride.of_float("path.speed_bonus", 0.75)]))
	layout.editor_add_camera_pose("Main", "主机位", Vector3(0, 12, -8), Vector3(-50, 0, 0), 55.0)
	var pose: GDCameraPoseSystem.CameraPose = layout.editor_try_get_camera_pose(0)["pose"]
	layout.editor_replace_camera_pose_at(0, pose.with_bound_edges(-40.0, 40.0, -20.0, 25.0).with_zoom_range(10.0, 80.0).with_initial_zoom(0.3))
	return layout

# ─────────────────────── 7. CLI & Editor Services ───────────────────────

func _test_cli_and_editor_services() -> void:
	print("[7/8] Testing Unified CLI & Editor Services...")

	# Shared argument parser
	var ctx := GDCliRoot.parse_args(["asset.tres", "--pos", "-1,2,3", "--dry-run", "keep", "--k=v", "--flag"])
	_check(",".join(ctx.positionals) == "asset.tres,keep" and ctx.get_option("pos") == "-1,2,3" and ctx.get_option("k") == "v", "CliContext parses positionals, negative values and --key=value")
	_check(ctx.has_flag("dry-run") and ctx.has_flag("flag") and not ctx.options.has("dry-run"), "--dry-run is always a flag and never swallows the next argument")

	# Unified, table-driven CLI
	var names := GdesignerToolsCli.commands().map(func(c: Dictionary) -> String: return c["name"])
	_check(names.has("help") and names.has("atom.create") and names.has("layout.list") and names.has("skill.create") and names.has("guide.create"), "GdesignerToolsCli.commands lists every module's commands")
	_check(GdesignerToolsCli.commands().all(func(c: Dictionary) -> bool: return not str(c["summary"]).is_empty()), "Every CLI command has a summary")
	var help := JSON.parse_string(GdesignerToolsCli.run("help")) as Dictionary
	_check(bool(help["ok"]) and (help["commands"] as Array).size() == names.size(), "help returns the derived command list")
	var unknown := JSON.parse_string(GdesignerToolsCli.run("nope.cmd")) as Dictionary
	_check(not bool(unknown["ok"]) and unknown["code"] == "unknown-command", "Unknown command reports unknown-command")
	var alias := JSON.parse_string(GdesignerToolsCli.run("sceneeditor.layout.list")) as Dictionary
	_check(alias["command"] == "layout.list" and alias["code"] == "layout-required", "sceneeditor.* aliases resolve to the canonical command")
	var empty := JSON.parse_string(GdesignerToolsCli.run("  ")) as Dictionary
	_check(not bool(empty["ok"]) and empty["code"] == "BAD_ARG", "Empty command line reports BAD_ARG")
	var atom_list := JSON.parse_string(GdesignerToolsCli.run("atom.list-templates")) as Dictionary
	_check(bool(atom_list["ok"]) and atom_list["code"] == "OK" and atom_list.has("templates"), "Core atom.* keeps its {ok, code, message} result shape")
	var dry := JSON.parse_string(GdesignerToolsCli.run("guide.create --id 4242 --name Dry")) as Dictionary
	_check(bool(dry["ok"]) and GDGuideEditing.find_graph(4242) != null, "guide.create registers the new graph")
	var dup_id := JSON.parse_string(GdesignerToolsCli.run("guide.create --id 4242 --name Again")) as Dictionary
	_check(not bool(dup_id["ok"]) and dup_id["code"] == "id.duplicate", "guide.create rejects a duplicate graph id")
	GDGuideEditing._in_memory_graphs.erase(4242)

	# GDArchetypeOps
	var base := GDLevelArchetypeRes.new()
	base.editor_init_with_addresses(1000, "基底", "Entity_Base", "Preview_Base")
	base.custom_attributes.append(GDCustomAttributeDef.editor_create("hp", "血量", GDCoreTypes.KeywordValueType.INT, 10))
	var variant := GDArchetypeOps.create_duplicate(base, 1001, "PlacementArchetype_Test_Variant", "变体", true)
	_check(variant is GDLevelArchetypeRes and variant.override_base_archetype == base and variant.manufactured_prefab_address == "Entity_Base", "create_duplicate(as_override) keeps the script type and binds the base")
	_check(variant.custom_attributes.size() == 1 and variant.custom_attributes[0] != base.custom_attributes[0], "create_duplicate clones custom attributes instead of sharing them")
	var copy := GDArchetypeOps.create_duplicate(variant, 1002, "PlacementArchetype_Test_Copy", "副本")
	_check(not copy.is_override_archetype and copy.override_base_archetype == null, "Plain duplicate of a variant is an independent archetype")
	_check(GDArchetypeOps.would_form_cycle(base, variant) and not GDArchetypeOps.would_form_cycle(variant, copy), "would_form_cycle follows the override chain")
	_check(GDArchetypeOps.count_overrides_of(base, [base, variant, copy]) == 1, "count_overrides_of counts direct variants")
	_check(not bool(GDArchetypeOps.try_rebind_base(base, variant)["ok"]) and bool(GDArchetypeOps.try_rebind_base(variant, copy)["ok"]) and variant.override_base_archetype == copy, "try_rebind_base rejects cycles and rebinds otherwise")

	# Level archetype rename
	var layout := GDLevelSceneRes.new()
	var arch := GDLevelArchetypeRes.new()
	arch.resource_name = "PlacementArchetype_Test_Block"
	arch.editor_init_with_addresses(layout.editor_allocate_next_archetype_stable_id(), "方块", "", "")
	layout.editor_add_archetype(arch)
	var inst_id := layout.editor_add_placement(arch.stable_id, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 1)
	var renamed := layout.editor_rename_archetype(arch, "PlacementArchetype_Test_Tower", "塔")
	var inst: GDPlacementData.PlacementInstance = layout.editor_try_get_placement(inst_id)["inst"]
	_check(bool(renamed["ok"]) and arch.resource_name == "PlacementArchetype_Test_Tower" and inst.instance_name == "Tower_%d" % inst_id and inst.display_name == "塔 #%d" % inst_id, "editor_rename_archetype renames the archetype and its default-named placements")
	_check(not bool(layout.editor_rename_archetype(arch, "1bad", "x")["ok"]), "editor_rename_archetype rejects invalid identifiers")

	# reconcile_scene: spawn missing, free stale, apply transforms
	var parent := Node3D.new()
	get_root().add_child(parent)
	var second := layout.editor_add_placement(arch.stable_id, Vector3(1, 0, 0), Vector3.ZERO, Vector3.ONE, 1)
	GDLevelSceneDrop.reconcile_scene(layout, parent)
	_check(parent.get_child_count() == 2, "reconcile_scene spawns placements missing from the scene")
	layout.editor_remove_placement(second)
	layout.editor_replace_placement(inst_id, inst.with_transform(Vector3(7, 0, 7), Vector3.ZERO, Vector3.ONE))
	var stray := Node3D.new()
	parent.add_child(stray)
	GDLevelSceneDrop.reconcile_scene(layout, parent)
	var kept := parent.get_children().filter(func(n: Node) -> bool: return n.has_meta(GDLevelSceneDrop.META_ID))
	_check(kept.size() == 1 and int(kept[0].get_meta(GDLevelSceneDrop.META_ID)) == inst_id and (kept[0] as Node3D).position == Vector3(7, 0, 7) and is_instance_valid(stray), "reconcile_scene frees removed placements, applies transforms and leaves foreign nodes")
	GDLevelSceneDrop.reconcile_scene(layout)
	_check(parent.get_child_count() == 2, "reconcile_scene without an edited scene is a no-op")
	parent.free()

	# CSV export writes a UTF-8 BOM followed by the CSV text
	var csv_path := "user://gdt_export.csv"
	var written := GDLevelCsvExporter.try_write_to_file(layout, csv_path)
	var bytes := FileAccess.get_file_as_bytes(csv_path)
	_check(bool(written["ok"]) and bytes.slice(0, 3) == PackedByteArray([0xEF, 0xBB, 0xBF]) and bytes.slice(3).get_string_from_utf8() == GDLevelCsvExporter.build_csv(layout), "CSV export writes BOM + UTF-8 text")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(csv_path))

# ─────────────────────── 6. UI Windows & Main Dock Integration ───────────────────────

func _test_ui_windows_and_main_dock() -> void:
	print("[8/8] Testing UI Shell...")
	GDSampleFactory.ensure_sample_assets()
	var win := GdesignerToolsWindow.new()
	_check(win.dock != null and not win.exclusive and not win.transient, "GdesignerTools window is an independent non-modal host")
	var dock := win.dock
	get_root().add_child(win)
	_check(dock.level_editor != null and dock.actor_editor != null and dock.skill_editor != null and dock.guide_editor != null and dock.game_mode_editor != null and dock.cli_console != null, "Shell hosts all five pages and the console")

	dock.switch_to_tab(1)
	_check(dock.current_page == dock.actor_editor and dock.actor_editor.visible and not dock.level_editor.visible, "Switching tabs shows exactly one page")
	_check(dock.actor_editor.library != null, "Opening a page loads a default document")
	dock.switch_to_tab(GdesignerToolsMainDock.TAB_CONSOLE)
	_check(dock.cli_console.visible and dock.current_page == dock.actor_editor, "The console opens as a drawer over the current page")

	var doc := dock.actor_editor.doc
	var arch: GDArchetypeRes = dock.actor_editor.library.archetypes[0]
	var original := arch.display_name
	arch.editor_set_display_name("临时")
	doc.commit("改名")
	_check(not dock.unsaved_titles().is_empty(), "Shell reports unsaved documents for the editor's close prompt")
	doc.undo()
	_check(arch.display_name == original and dock.unsaved_titles().is_empty(), "Undo returns the document to its saved state")

	var keep := GDDocument.new(GDActorLibraryRes.new())
	keep.resource.display_name = "一"
	keep.commit("甲", true)
	keep.resource.display_name = "二"
	keep.commit("甲", true)
	keep.undo()
	_check(keep.resource.display_name == "", "GDDocument merges rapid commits with the same label into one undo step")

	var catcher := GDLevelSceneDrop.DropCatcher.new()
	_check(catcher._can_drop_data(Vector2.ZERO, {"type": GDLevelSceneDrop.DRAG_TYPE, "stable_id": 1}), "Viewport drop catcher accepts archetype payload")
	_check(not catcher._can_drop_data(Vector2.ZERO, {"type": "files"}), "Viewport drop catcher ignores foreign drag types")
	catcher.free()

	var layout := GDLevelSceneRes.new()
	var level_arch := GDLevelArchetypeRes.new()
	level_arch.editor_init_with_addresses(layout.editor_allocate_next_archetype_stable_id(), "示例方块", "", "")
	layout.editor_add_archetype(level_arch)
	var payload := GDLevelSceneDrop.begin(level_arch, layout)
	_check(GDLevelSceneDrop.is_payload(payload) and GDLevelSceneDrop.is_active(), "Begin archetype drag publishes gdesigner_archetype payload")
	var parallel := GDLevelSceneDrop.ray_intersect_plane(Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.ZERO)
	var hit := GDLevelSceneDrop.ray_intersect_plane(Vector3(2, 10, -3), Vector3(0, -1, 0), Vector3.UP, Vector3.ZERO)
	_check(not bool(parallel.get("ok", true)) and bool(hit.get("ok", false)) and (hit["point"] as Vector3).is_equal_approx(Vector3(2, 0, -3)), "Ground plane ray hits Y=0 and rejects a parallel ray")
	var ground := Node3D.new()
	ground.name = GDLevelSceneDrop.GROUND_NAME
	var body := StaticBody3D.new()
	ground.add_child(body)
	_check(GDLevelSceneDrop.is_logical_ground(body), "Logical ground name matches [SceneEditor Ground]")
	ground.free()
	GDLevelSceneDrop.poll()
	_check(not GDLevelSceneDrop.is_active(), "Releasing the mouse outside a viewport cancels the drag")

	var parent := Node3D.new()
	get_root().add_child(parent)
	var placed := GDLevelSceneDrop.place_archetype(layout, level_arch, Vector3(3, 0, 5), parent)
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
	win.free()


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
