extends SceneTree

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_cast_checks_and_single_charge()
	_test_missing_and_invalid_attributes()
	_test_cast_reentrancy()
	_test_disposal_during_charge()
	_test_tag_matching_and_blocking()
	_test_effect_event_duration_and_source()
	_test_effect_tag_lifetimes()
	_test_effect_reentrancy()
	print("TOTAL PASSED: %d  FAILED: %d" % [_passed, _failed])
	quit(_failed)


func _test_cast_checks_and_single_charge() -> void:
	var bus := GDCoreServices.EventBus.new()
	var runtime := GDSkillRuntime.SkillRuntimeService.new(bus, func() -> float: return 10.0)
	var attributes := GDAttributeSystem.AttributeSet.new()
	attributes.set_base(GDSkillTypes.AttributeKind.MANA, 100.0)
	runtime.register_attribute_set(1, attributes)
	var skill := _skill()
	skill.set_cost("Mana", 25.0)
	skill.set_cooldown("test", 4.0)
	_check(runtime.try_cast(1, 2, skill), "valid cast succeeds")
	_check(attributes.get_current(GDSkillTypes.AttributeKind.MANA) == 75.0, "valid cast charges once")
	_check(not runtime.try_cast(1, 2, skill), "cooldown rejects recast")
	_check(attributes.get_current(GDSkillTypes.AttributeKind.MANA) == 75.0, "cooldown rejection preserves balance")
	var gated := _skill()
	gated.set_cost("Mana", 25.0)
	gated.required_tags = [_tag("Ready")]
	_check(not runtime.try_cast(1, 2, gated), "missing required tag rejects cast")
	_check(attributes.get_current(GDSkillTypes.AttributeKind.MANA) == 75.0, "tag rejection preserves balance")
	gated.required_tags = [null]
	_check(not runtime.try_cast(1, 2, gated), "invalid tag reference rejects cast")
	_check(attributes.get_current(GDSkillTypes.AttributeKind.MANA) == 75.0, "invalid tag rejection preserves balance")
	var blocked := _tag("State.Stunned")
	runtime.tag_store.add_tag(1, _tag("State.Stunned.Hard"))
	gated.required_tags.clear()
	gated.blocked_tags = [blocked]
	_check(not runtime.try_cast(1, 2, gated), "blocked parent tag rejects paid cast")
	_check(attributes.get_current(GDSkillTypes.AttributeKind.MANA) == 75.0, "blocked tag rejection preserves balance")
	runtime.dispose()
	_check(not runtime.try_cast(1, 2, skill), "disposed service rejects cast")
	bus.clear()


func _test_missing_and_invalid_attributes() -> void:
	var bus := GDCoreServices.EventBus.new()
	var fake_changes: Array = []
	bus.subscribe(GDSkillRuntime.EVENT_ATTRIBUTE_CHANGED, func(evt: Variant) -> void: fake_changes.append(evt))
	var runtime := GDSkillRuntime.SkillRuntimeService.new(bus)
	var skill := _skill()
	skill.set_cost("Mana", 10.0)
	_check(not runtime.try_cast(1, 2, skill), "paid cast rejects missing attribute set")
	runtime.register_attribute_set(1, null)
	_check(not runtime.try_cast(1, 2, skill), "paid cast rejects null attribute set")
	var attributes := GDAttributeSystem.AttributeSet.new()
	runtime.register_attribute_set(1, attributes)
	_check(not runtime.try_cast(1, 2, skill), "paid cast rejects missing attribute")
	attributes.set_base(GDSkillTypes.AttributeKind.MANA, 100.0)
	skill.set_cost("UnmappedAttribute", 10.0)
	_check(not runtime.try_cast(1, 2, skill), "paid cast rejects unknown attribute name")
	_check(attributes.get_current(GDSkillTypes.AttributeKind.MANA) == 100.0, "invalid attribute rejection preserves balance")
	skill.set_cost("Mana", NAN)
	_check(not runtime.try_cast(1, 2, skill), "nonfinite cost rejects cast")
	skill.set_cost("Mana", -10.0)
	_check(not runtime.try_cast(1, 2, skill), "negative cost rejects cast")
	var damage := GDSkillClips.DealDamageClip.new()
	damage.base_damage = 30
	_check(runtime.try_cast(1, 2, _skill(damage)), "free cast can dispatch without target attributes")
	_check(fake_changes.is_empty(), "missing attributes never fabricate attribute change events")
	runtime.dispose()
	bus.clear()


func _test_cast_reentrancy() -> void:
	var bus := GDCoreServices.EventBus.new()
	var runtime := GDSkillRuntime.SkillRuntimeService.new(bus)
	var attributes := GDAttributeSystem.AttributeSet.new()
	attributes.set_base(GDSkillTypes.AttributeKind.MANA, 100.0)
	runtime.register_attribute_set(1, attributes)
	var skill := _skill()
	skill.set_cost("Mana", 25.0)
	var nested_results: Array[bool] = []
	var request_results: Array[bool] = []
	bus.subscribe(GDSkillRuntime.EVENT_SKILL_CAST_REQUEST, func(_evt: Variant) -> void:
		request_results.append(runtime.try_cast(1, 2, skill))
	)
	attributes.attribute_changed.connect(func(_kind: int, _old: float, _new: float, reason: String) -> void:
		if reason == "skill-cost":
			nested_results.append(runtime.try_cast(1, 2, skill))
	)
	_check(runtime.try_cast(1, 2, skill), "outer cast succeeds during synchronous callbacks")
	_check(request_results == [false], "same caster reentry is rejected during request event")
	_check(nested_results == [false], "same caster reentry is rejected during charge")
	_check(attributes.get_current(GDSkillTypes.AttributeKind.MANA) == 75.0, "synchronous reentry cannot charge twice")
	runtime.dispose()
	bus.clear()


func _test_tag_matching_and_blocking() -> void:
	var bus := GDCoreServices.EventBus.new()
	var runtime := GDSkillRuntime.SkillRuntimeService.new(bus)
	var parent := _tag("State.Ready")
	var child := _tag("State.Ready.Empowered")
	child.parent_tag = parent
	var skill := _skill()
	skill.required_tags = [_tag("State.Ready")]
	_check(not runtime.try_cast(1, 2, skill), "required tag absent rejects free cast")
	runtime.tag_store.add_tag(1, child)
	_check(runtime.try_cast(1, 2, skill), "held child tag satisfies same-named parent requirement")
	child.parent_tag = null
	_check(runtime.try_cast(1, 2, skill), "dot-separated descendant satisfies parent without explicit link")
	_check(not runtime.tag_store.has_tag(1, _tag("State.Read")), "hierarchical matching respects segment boundaries")
	skill.blocked_tags = [parent]
	_check(not runtime.try_cast(1, 2, skill), "held child tag blocks parent-gated cast")
	runtime.tag_store.remove_tag(1, child)
	_check(not runtime.tag_store.has_tag(1, parent), "removing held tag clears parent match")
	skill.blocked_tags.clear()
	runtime.tag_query = func(owner_id: int, tag: GDGameplayTagRes) -> bool:
		return owner_id == 1 and tag.tag_name == "State.Ready"
	_check(runtime.try_cast(1, 2, skill), "external tag query satisfies required tag")
	skill.blocked_tags = [parent]
	_check(not runtime.try_cast(1, 2, skill), "external tag query also enforces blocked tag")
	runtime.dispose()
	bus.clear()


func _test_disposal_during_charge() -> void:
	var bus := GDCoreServices.EventBus.new()
	var runtime := GDSkillRuntime.SkillRuntimeService.new(bus)
	var attributes := GDAttributeSystem.AttributeSet.new()
	attributes.set_base(GDSkillTypes.AttributeKind.MANA, 100.0)
	runtime.register_attribute_set(1, attributes)
	var skill := _skill()
	skill.set_cost("Mana", 25.0)
	attributes.attribute_changed.connect(func(_kind: int, _old: float, _new: float, reason: String) -> void:
		if reason == "skill-cost":
			runtime.dispose()
	)
	_check(runtime.try_cast(1, 2, skill), "validated charged cast remains accepted when callback disposes service")
	_check(attributes.get_current(GDSkillTypes.AttributeKind.MANA) == 75.0 and runtime._active_skills.is_empty(), "charge callback disposal cannot revive an active cast")
	bus.clear()


func _test_effect_event_duration_and_source() -> void:
	var bus := GDCoreServices.EventBus.new()
	var runtime := GDSkillRuntime.SkillRuntimeService.new(bus)
	var applier := GDSkillRuntime.GameplayEffectApplier.new(bus)
	var attributes := GDAttributeSystem.AttributeSet.new()
	attributes.set_base(GDSkillTypes.AttributeKind.HEALTH, 100.0)
	applier.register_attribute_set(7, attributes)
	var effect := GDGameplayEffectRes.new()
	effect.duration = 3.0
	effect.modifiers = [GDGameplayEffectModifierRes.new("Health", GDSkillTypes.ModifierOp.ADD, -10.0)]
	var clip := GDSkillClips.ApplyEffectClip.new()
	clip.configure(effect, true)
	_check(runtime.try_cast(42, 7, _skill(clip)), "instant effect clip casts")
	_check(applier.active_count == 0 and attributes.get_current(GDSkillTypes.AttributeKind.HEALTH) == 90.0, "instant override applies immediately without active duration")
	_check(effect.duration == 3.0, "instant override preserves shared effect resource")
	clip = GDSkillClips.ApplyEffectClip.new()
	clip.configure(effect, false)
	_check(runtime.try_cast(42, 7, _skill(clip)), "durational effect clip casts")
	_check(applier.active_count == 1 and applier.snapshot()[0].source_caster_id == 42, "effect event preserves source caster")
	_check(applier.snapshot()[0].remaining_ms == 3000.0, "durational clip uses resource duration")
	applier.do_tick(3000.0)
	_check(attributes.get_current(GDSkillTypes.AttributeKind.HEALTH) == 90.0, "duration expiry reverts only durational application")
	bus.publish(GDSkillRuntime.EVENT_GAMEPLAY_EFFECT_APPLIED, {"owner_id": 7, "caster_id": 55, "effect": effect, "duration": 0.5})
	_check(applier.snapshot()[0].source_caster_id == 55 and applier.snapshot()[0].remaining_ms == 500.0, "external effect event accepts caster and duration override")
	_check(not applier.try_apply(7, 55, effect, NAN), "explicit nonfinite duration override rejects effect")
	_check(applier.try_apply(7, 55, effect, null), "null duration override preserves existing direct-call behavior")
	applier.dispose()
	runtime.dispose()
	bus.clear()


func _test_effect_tag_lifetimes() -> void:
	var bus := GDCoreServices.EventBus.new()
	var runtime := GDSkillRuntime.SkillRuntimeService.new(bus)
	var applier := GDSkillRuntime.GameplayEffectApplier.new(bus)
	var attributes := GDAttributeSystem.AttributeSet.new()
	attributes.set_base(GDSkillTypes.AttributeKind.MOVE_SPEED, 10.0)
	applier.register_attribute_set(1, attributes)
	var tag := _tag("State.Ready")
	var effect := GDGameplayEffectRes.new()
	effect.duration = 1.0
	effect.granted_tags = [tag]
	effect.modifiers = [GDGameplayEffectModifierRes.new("MoveSpeed", GDSkillTypes.ModifierOp.MULTIPLY, -0.3)]
	var skill := _skill()
	skill.required_tags = [tag]
	_check(runtime.tag_store == applier.tag_store, "runtime and effects share bus tag store")
	_check(applier.try_apply(1, 3, effect, 0.5) and applier.try_apply(1, 4, effect), "overlapping tagged effects apply")
	_check(runtime.try_cast(1, 2, skill), "effect granted tag unlocks skill")
	applier.do_tick(500.0)
	_check(runtime.tag_store.has_tag(1, tag), "tag survives first overlapping effect expiry")
	applier.do_tick(500.0)
	_check(not runtime.tag_store.has_tag(1, tag) and not runtime.try_cast(1, 2, skill), "last effect expiry removes tag and relocks skill")
	_check(is_equal_approx(attributes.get_current(GDSkillTypes.AttributeKind.MOVE_SPEED), 10.0), "overlapping modifier expiry restores attributes")
	_check(applier.try_apply(1, 3, effect), "tagged effect can be applied again")
	applier.dispose()
	_check(not runtime.tag_store.has_tag(1, tag), "disposing effects removes granted tags")
	_check(is_equal_approx(attributes.get_current(GDSkillTypes.AttributeKind.MOVE_SPEED), 10.0), "disposing effects reverts temporary modifiers")
	_check(not applier.try_apply(1, 3, effect), "disposed effect applier rejects new effects")
	runtime.dispose()
	bus.clear()


func _test_effect_reentrancy() -> void:
	var bus := GDCoreServices.EventBus.new()
	var applier := GDSkillRuntime.GameplayEffectApplier.new(bus)
	var attributes := GDAttributeSystem.AttributeSet.new()
	attributes.set_base(GDSkillTypes.AttributeKind.MOVE_SPEED, 10.0)
	applier.register_attribute_set(1, attributes)
	var effect := GDGameplayEffectRes.new()
	effect.duration = 1.0
	effect.granted_tags = [_tag("Ready"), _tag("Empowered")]
	effect.modifiers = [GDGameplayEffectModifierRes.new("MoveSpeed", GDSkillTypes.ModifierOp.MULTIPLY, -0.3)]
	bus.subscribe(GDSkillRuntime.EVENT_GAMEPLAY_TAG_ADDED, func(_evt: Variant) -> void: applier.dispose())
	_check(not applier.try_apply(1, 3, effect), "effect disposal from synchronous tag callback cancels application")
	_check(not applier.tag_store.has_tag(1, effect.granted_tags[0]) and not applier.tag_store.has_tag(1, effect.granted_tags[1]), "synchronous effect disposal leaves no granted tags")
	_check(is_equal_approx(attributes.get_current(GDSkillTypes.AttributeKind.MOVE_SPEED), 10.0) and applier.active_count == 0, "synchronous effect disposal restores modifiers")
	bus.clear()


func _skill(clip: GDSkillClips.SkillClip = null) -> GDSkillRes:
	var skill := GDSkillRes.new()
	var group := GDSkillRes.SkillTrackGroup.new("Cast")
	var track := GDSkillRes.SkillTrack.new()
	track.add_clip(clip if clip != null else GDSkillClips.PlayAnimationClip.new())
	group.add_track(track)
	skill.add_group(group)
	return skill


func _tag(name: String) -> GDGameplayTagRes:
	var tag := GDGameplayTagRes.new()
	tag.tag_name = name
	return tag


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS ", message)
	else:
		_failed += 1
		push_error("FAIL " + message)
