@tool
class_name GDSkillRuntime
extends RefCounted

## 技能运行时驱动与服务（对应 SkillRunner / SkillRuntimeService / SkillCooldownTable / GameplayEffectApplier / ActiveEffect / SkillContext / CastInstanceId）
## 核心不变量：
##   1. 校验顺序：Cost -> Cooldown -> RequiredTags/BlockedTags
##   2. 同 caster 重复施法打断旧运行（广播 SkillEndedEvent("interrupted-by-recast")）
##   3. 全局派发顺序 BuildDispatchOrder：合并所有 Group 下所有 Track 的 Clip，按 StartMs 升序 + 同刻 tie-break（逻辑先于表现 -> 全局 track 序 -> clip 序）

const EVENT_SKILL_CAST_REQUEST := "SkillCastRequestEvent"
const EVENT_SKILL_CASTED := "SkillCastedEvent"
const EVENT_SKILL_NODE_FIRED := "SkillNodeFiredEvent"
const EVENT_SKILL_ENDED := "SkillEndedEvent"
const EVENT_SKILL_COOLDOWN_STARTED := "SkillCooldownStartedEvent"
const EVENT_SKILL_COOLDOWN_ENDED := "SkillCooldownEndedEvent"
const EVENT_ATTRIBUTE_CHANGED := "AttributeChangedEvent"
const EVENT_GAMEPLAY_EFFECT_APPLIED := "GameplayEffectAppliedEvent"
const EVENT_GAMEPLAY_EFFECT_EXPIRED := "GameplayEffectExpiredEvent"
const EVENT_GAMEPLAY_TAG_ADDED := "GameplayTagAddedEvent"
const EVENT_GAMEPLAY_TAG_REMOVED := "GameplayTagRemovedEvent"


class CastInstanceId extends RefCounted:
	static var _next_value: int = 0
	var value: int = 0

	func _init(v: int = 0) -> void:
		value = v

	var is_valid: bool:
		get:
			return value > 0

	static func next() -> CastInstanceId:
		_next_value += 1
		return CastInstanceId.new(_next_value)


class SkillContext extends RefCounted:
	var caster_id: int = 0
	var caster_node: Node = null
	var target_id: int = 0
	var target_node: Node = null
	var skill: GDSkillRes = null
	var start_time: float = 0.0
	var cast_instance_id: CastInstanceId = null

	func _init(
		p_caster_id: int,
		p_caster_node: Node,
		p_target_id: int,
		p_target_node: Node,
		p_skill: GDSkillRes,
		p_start_time: float,
		p_cast_id: CastInstanceId
	) -> void:
		caster_id = p_caster_id
		caster_node = p_caster_node
		target_id = p_target_id
		target_node = p_target_node
		skill = p_skill
		start_time = p_start_time
		cast_instance_id = p_cast_id


class SkillCooldownTable extends RefCounted:
	var _end_times: Dictionary = {} # "ownerId::cdGroup" -> {"owner_id": int, "cd_group": String, "end_time": float}

	func start(owner_id: int, cd_group: String, duration_sec: float, now_sec: float) -> void:
		if duration_sec <= 0.0:
			return
		var key := "%d::%s" % [owner_id, cd_group]
		_end_times[key] = {
			"owner_id": owner_id,
			"cd_group": cd_group,
			"end_time": now_sec + duration_sec,
		}

	func is_on_cooldown(owner_id: int, cd_group: String, now_sec: float) -> bool:
		var key := "%d::%s" % [owner_id, cd_group]
		if not _end_times.has(key):
			return false
		var entry: Dictionary = _end_times[key]
		return now_sec < float(entry.get("end_time", 0.0))

	func drain_expired(now_sec: float) -> Array[Dictionary]:
		var expired: Array[Dictionary] = []
		var keys_to_remove: Array[String] = []
		for k in _end_times.keys():
			var entry: Dictionary = _end_times[k]
			if now_sec >= float(entry.get("end_time", 0.0)):
				expired.append({
					"owner_id": int(entry["owner_id"]),
					"cd_group": str(entry["cd_group"]),
				})
				keys_to_remove.append(k)
		for k in keys_to_remove:
			_end_times.erase(k)
		return expired

	func clear() -> void:
		_end_times.clear()


## SkillRunner 对应：全局排序 BuildDispatchOrder + 时间轴推进
class SkillRunner extends RefCounted:
	const TAIL_BUFFER_SECONDS := 0.5

	var context: SkillContext = null
	var bus: GDCoreServices.EventBus = null
	var is_completed: bool = false

	var _ordered_clips: Array[GDSkillClips.SkillClip] = []
	var _next_index: int = 0
	var _elapsed_ms: float = 0.0
	var _end_ms: float = 0.0

	func _init(p_ctx: SkillContext, p_bus: GDCoreServices.EventBus) -> void:
		context = p_ctx
		bus = p_bus
		if context != null and context.skill != null:
			_ordered_clips = build_dispatch_order(context.skill)
			var last_clip_ms := float(_ordered_clips[_ordered_clips.size() - 1].start_ms) if not _ordered_clips.is_empty() else 0.0
			_end_ms = maxf(float(context.skill.duration_ms), last_clip_ms + TAIL_BUFFER_SECONDS * 1000.0)

	var skill: GDSkillRes:
		get:
			return context.skill if context != null else null

	static func build_dispatch_order(p_skill: GDSkillRes) -> Array[GDSkillClips.SkillClip]:
		var result: Array[GDSkillClips.SkillClip] = []
		if p_skill == null:
			return result
		var entries: Array[Dictionary] = []
		var global_track_idx := 0
		for g in range(p_skill.groups.size()):
			var grp = p_skill.groups[g]
			if grp == null:
				continue
			for t in range(grp.tracks.size()):
				var trk = grp.tracks[t]
				if trk != null:
					for c in range(trk.clips.size()):
						var clip = trk.clips[c]
						if clip != null:
							entries.append({
								"clip": clip,
								"logic_rank": 0 if clip.is_logic_clip() else 1,
								"track_index": global_track_idx,
								"clip_index": c,
							})
				global_track_idx += 1

		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ca: GDSkillClips.SkillClip = a["clip"]
			var cb: GDSkillClips.SkillClip = b["clip"]
			if ca.start_ms != cb.start_ms:
				return ca.start_ms < cb.start_ms
			var ra := int(a["logic_rank"])
			var rb := int(b["logic_rank"])
			if ra != rb:
				return ra < rb
			var ta := int(a["track_index"])
			var tb := int(b["track_index"])
			if ta != tb:
				return ta < tb
			return int(a["clip_index"]) < int(b["clip_index"])
		)

		for e in entries:
			result.append(e["clip"])
		return result

	func start_immediate_check() -> void:
		if context == null or context.skill == null or bus == null:
			_publish_ended("no-binding")
			is_completed = true
			return
		if _ordered_clips.is_empty():
			_publish_ended("no-nodes")
			is_completed = true
			return
		# 立即派发 0ms 的 clip
		tick_ms(0.0)

	func tick_ms(delta_ms: float) -> void:
		if is_completed:
			return
		_elapsed_ms += maxf(0.0, delta_ms)
		while _next_index < _ordered_clips.size():
			var clip := _ordered_clips[_next_index]
			if _elapsed_ms >= float(clip.start_ms):
				_dispatch(clip)
				_next_index += 1
			else:
				break
		if _next_index >= _ordered_clips.size() and _elapsed_ms >= _end_ms:
			_publish_ended("completed")
			is_completed = true

	func stop() -> void:
		is_completed = true

	func _dispatch(clip: GDSkillClips.SkillClip) -> void:
		if bus == null or context == null:
			return
		bus.publish(EVENT_SKILL_NODE_FIRED, {
			"caster_id": context.caster_id,
			"target_id": context.target_id,
			"skill": context.skill,
			"clip": clip,
			"start_ms": clip.start_ms,
			"cast_instance_id": context.cast_instance_id,
		})

	func _publish_ended(reason: String) -> void:
		if bus == null or context == null:
			return
		bus.publish(EVENT_SKILL_ENDED, {
			"caster_id": context.caster_id,
			"skill": context.skill,
			"reason": reason,
			"cast_instance_id": context.cast_instance_id,
		})


## SkillRuntimeService 对应
class SkillRuntimeService extends RefCounted:
	var _bus: GDCoreServices.EventBus = null
	var _now_provider: Callable = Callable()
	var _attribute_sets: Dictionary = {} # owner_id (int) -> GDAttributeSystem.AttributeSet
	var _cooldown_table: SkillCooldownTable = SkillCooldownTable.new()
	var _active_skills: Dictionary = {} # caster_id (int) -> {"cast_id": CastInstanceId, "runner": SkillRunner}
	var _teleport_origins: Dictionary = {} # "castId::recallKey" -> Vector3
	var _pending_hits: Dictionary = {} # cast_id.value (int) -> Array[int]
	var _node_lookup: Dictionary = {} # entity_id (int) -> Node3D
	var _preview_ignore_cost: bool = false
	var _preview_ignore_cooldown: bool = false
	var _disposed: bool = false
	var _cb_node_fired: Callable
	var _cb_skill_ended: Callable

	func _init(p_bus: GDCoreServices.EventBus, p_now_provider: Callable = Callable()) -> void:
		_bus = p_bus if p_bus != null else GDCoreServices.get_event_bus()
		_now_provider = p_now_provider
		_cb_node_fired = Callable(self, "_handle_node_fired")
		_cb_skill_ended = Callable(self, "_handle_skill_ended")
		_bus.subscribe(EVENT_SKILL_NODE_FIRED, _cb_node_fired)
		_bus.subscribe(EVENT_SKILL_ENDED, _cb_skill_ended)

	func register_attribute_set(owner_id: int, attr_set: GDAttributeSystem.AttributeSet) -> void:
		_attribute_sets[owner_id] = attr_set

	func register_entity_node(entity_id: int, node: Node3D) -> void:
		_node_lookup[entity_id] = node

	func set_preview_validation_bypass(ignore_cost: bool, ignore_cooldown: bool) -> void:
		_preview_ignore_cost = ignore_cost
		_preview_ignore_cooldown = ignore_cooldown

	func try_cast(caster_id: int, target_id: int, skill: GDSkillRes) -> bool:
		if skill == null:
			GDGameLogger.log_warning("[SkillRuntimeService] TryCast called with null skill")
			return false
		_bus.publish(EVENT_SKILL_CAST_REQUEST, {
			"caster_id": caster_id,
			"target_id": target_id,
			"skill": skill,
		})
		if not _validate_cost(caster_id, skill):
			return false
		if not _validate_cooldown(caster_id, skill):
			return false
		if not _validate_required_tags(caster_id, skill):
			return false

		if _active_skills.has(caster_id):
			var existing: Dictionary = _active_skills[caster_id]
			var old_runner: SkillRunner = existing.get("runner", null)
			if old_runner != null and not old_runner.is_completed:
				_interrupt_active_cast(caster_id, skill, existing)
			else:
				_active_skills.erase(caster_id)

		var start_t := _now()
		var cast_id := CastInstanceId.next()
		var ctx := SkillContext.new(
			caster_id,
			_node_lookup.get(caster_id, null),
			target_id,
			_node_lookup.get(target_id, null),
			skill,
			start_t,
			cast_id
		)
		var runner := SkillRunner.new(ctx, _bus)
		_active_skills[caster_id] = {"cast_id": cast_id, "runner": runner}

		_start_cooldown_if_needed(caster_id, skill, start_t)
		_bus.publish(EVENT_SKILL_CASTED, {
			"caster_id": caster_id,
			"target_id": target_id,
			"skill": skill,
			"start_time": start_t,
			"cast_instance_id": cast_id,
		})
		runner.start_immediate_check()
		return true

	func tick_active_runners(delta_ms: float) -> void:
		var casters := _active_skills.keys()
		for cid in casters:
			if not _active_skills.has(cid):
				continue
			var state: Dictionary = _active_skills[cid]
			var runner: SkillRunner = state.get("runner", null)
			if runner != null and not runner.is_completed:
				runner.tick_ms(delta_ms)

	func tick_cooldowns(now_override: float = -1.0) -> int:
		if _disposed:
			return 0
		var t := now_override if now_override >= 0.0 else _now()
		var expired := _cooldown_table.drain_expired(t)
		for key in expired:
			_bus.publish(EVENT_SKILL_COOLDOWN_ENDED, {
				"owner_id": int(key["owner_id"]),
				"cd_group": str(key["cd_group"]),
			})
		return expired.size()

	func cancel_all_active_casts() -> void:
		for cid in _active_skills.keys():
			var state: Dictionary = _active_skills[cid]
			var r: SkillRunner = state.get("runner", null)
			if r != null:
				r.stop()
		_active_skills.clear()
		_pending_hits.clear()

	func cancel_active_cast(caster_id: int) -> void:
		if not _active_skills.has(caster_id):
			return
		var state: Dictionary = _active_skills[caster_id]
		var r: SkillRunner = state.get("runner", null)
		var cast_id: CastInstanceId = state.get("cast_id", null)
		_bus.publish(EVENT_SKILL_ENDED, {
			"caster_id": caster_id,
			"skill": r.skill if r != null else null,
			"reason": "caster-died",
			"cast_instance_id": cast_id,
		})
		if r != null:
			r.stop()
		_active_skills.erase(caster_id)

	func dispose() -> void:
		if _disposed:
			return
		_disposed = true
		_bus.unsubscribe(EVENT_SKILL_NODE_FIRED, _cb_node_fired)
		_bus.unsubscribe(EVENT_SKILL_ENDED, _cb_skill_ended)
		cancel_all_active_casts()
		_teleport_origins.clear()

	func _now() -> float:
		if _now_provider.is_valid():
			return float(_now_provider.call())
		return float(Time.get_ticks_msec()) / 1000.0

	func _validate_cost(caster_id: int, skill: GDSkillRes) -> bool:
		var c := skill.cost
		if c == null or not c.has_cost or _preview_ignore_cost:
			return true
		if not _attribute_sets.has(caster_id):
			_bus.publish(EVENT_ATTRIBUTE_CHANGED, {
				"owner_id": caster_id,
				"attribute_name": c.attribute_name,
				"old_value": 100.0,
				"new_value": 100.0 - c.amount,
				"reason": "skill-cost",
			})
			return true
		var set_obj: GDAttributeSystem.AttributeSet = _attribute_sets[caster_id]
		var mapped := GDSkillTypes.try_map_attribute_name(c.attribute_name)
		if not bool(mapped.get("ok", false)):
			return true
		var kind := int(mapped["kind"])
		var cur := set_obj.get_current(kind)
		if cur < c.amount:
			_bus.publish(EVENT_SKILL_ENDED, {
				"caster_id": caster_id,
				"skill": skill,
				"reason": "cost-insufficient",
				"cast_instance_id": null,
			})
			return false
		set_obj.apply_delta(kind, -c.amount, "skill-cost")
		return true

	func _validate_cooldown(caster_id: int, skill: GDSkillRes) -> bool:
		var cd := skill.cooldown
		if cd == null or not cd.has_cooldown or _preview_ignore_cooldown:
			return true
		if _cooldown_table.is_on_cooldown(caster_id, cd.cd_group, _now()):
			_bus.publish(EVENT_SKILL_ENDED, {
				"caster_id": caster_id,
				"skill": skill,
				"reason": "cooldown-blocked",
				"cast_instance_id": null,
			})
			return false
		return true

	func _validate_required_tags(_caster_id: int, _skill: GDSkillRes) -> bool:
		return true

	func _start_cooldown_if_needed(caster_id: int, skill: GDSkillRes, now_t: float) -> void:
		if _preview_ignore_cooldown:
			return
		var cd := skill.cooldown
		if cd == null or not cd.has_cooldown:
			return
		_cooldown_table.start(caster_id, cd.cd_group, cd.duration_seconds, now_t)
		_bus.publish(EVENT_SKILL_COOLDOWN_STARTED, {
			"owner_id": caster_id,
			"cd_group": cd.cd_group,
			"duration_seconds": cd.duration_seconds,
		})

	func _interrupt_active_cast(caster_id: int, incoming_skill: GDSkillRes, existing_state: Dictionary) -> void:
		var old_runner: SkillRunner = existing_state.get("runner", null)
		var old_cast_id: CastInstanceId = existing_state.get("cast_id", null)
		_bus.publish(EVENT_SKILL_ENDED, {
			"caster_id": caster_id,
			"skill": incoming_skill,
			"reason": "interrupted-by-recast",
			"cast_instance_id": old_cast_id,
		})
		if old_runner != null:
			old_runner.stop()
		_active_skills.erase(caster_id)

	func _handle_node_fired(evt: Variant) -> void:
		if not (evt is Dictionary):
			return
		var d := evt as Dictionary
		var clip: GDSkillClips.SkillClip = d.get("clip", null)
		if clip == null:
			return
		if clip is GDSkillClips.DealDamageClip:
			_process_damage(d, clip as GDSkillClips.DealDamageClip)
		elif clip is GDSkillClips.ApplyEffectClip:
			_process_effect(d, clip as GDSkillClips.ApplyEffectClip)
		elif clip is GDSkillClips.TeleportClip:
			_process_teleport(d, clip as GDSkillClips.TeleportClip)

	func _process_damage(evt: Dictionary, clip: GDSkillClips.DealDamageClip) -> void:
		var caster_id := int(evt.get("caster_id", 0))
		var target_id := int(evt.get("target_id", 0))
		var atk := 0.0
		if _attribute_sets.has(caster_id):
			atk = (_attribute_sets[caster_id] as GDAttributeSystem.AttributeSet).get_current(GDSkillTypes.AttributeKind.ATTACK_POWER)
		var dmg := clip.base_damage + roundi(clip.coefficient * atk)
		var final_target := target_id if target_id != 0 else caster_id
		if _attribute_sets.has(final_target):
			(_attribute_sets[final_target] as GDAttributeSystem.AttributeSet).apply_delta(GDSkillTypes.AttributeKind.HEALTH, -float(dmg), "damage")
		else:
			_bus.publish(EVENT_ATTRIBUTE_CHANGED, {
				"owner_id": final_target,
				"attribute_name": "HP",
				"old_value": 100.0,
				"new_value": 100.0 - float(dmg),
				"reason": "damage",
			})

	func _process_effect(evt: Dictionary, clip: GDSkillClips.ApplyEffectClip) -> void:
		if clip.effect == null:
			return
		var owner_id := int(evt.get("target_id", 0))
		if owner_id == 0:
			owner_id = int(evt.get("caster_id", 0))
		var dur := 0.0 if clip.is_instant else clip.effect.duration
		_bus.publish(EVENT_GAMEPLAY_EFFECT_APPLIED, {
			"owner_id": owner_id,
			"effect": clip.effect,
			"duration": dur,
		})

	func _process_teleport(evt: Dictionary, clip: GDSkillClips.TeleportClip) -> void:
		var caster_id := int(evt.get("caster_id", 0))
		var target_id := int(evt.get("target_id", 0))
		var cast_id: CastInstanceId = evt.get("cast_instance_id", null)
		var caster_node: Node3D = _node_lookup.get(caster_id, null)
		if caster_node == null:
			return
		var key := "%d::%s" % [cast_id.value if cast_id != null else 0, clip.origin_recall_key]
		if clip.mode == GDSkillTypes.SkillTeleportModeKind.TO_TARGET_SIDE:
			_teleport_origins[key] = caster_node.position
			var target_node: Node3D = _node_lookup.get(target_id, null)
			if target_node != null:
				caster_node.position = target_node.position + Vector3(0, 0, clip.offset_from_target)
			else:
				caster_node.position += Vector3(0, 0, -clip.offset_from_target)
		elif clip.mode == GDSkillTypes.SkillTeleportModeKind.BACK_TO_ORIGIN:
			if _teleport_origins.has(key):
				caster_node.position = _teleport_origins[key]
				_teleport_origins.erase(key)

	func _handle_skill_ended(evt: Variant) -> void:
		if not (evt is Dictionary):
			return
		var d := evt as Dictionary
		var caster_id := int(d.get("caster_id", 0))
		var cast_id: CastInstanceId = d.get("cast_instance_id", null)
		if cast_id != null and _active_skills.has(caster_id):
			var cur: Dictionary = _active_skills[caster_id]
			if cur.get("cast_id", null) == cast_id:
				_active_skills.erase(caster_id)


## AppliedModifierHandle & ActiveEffect & GameplayEffectApplier 对应
class AppliedModifierHandle extends RefCounted:
	var kind: int = 0
	var op: int = GDSkillTypes.ModifierOp.ADD
	var magnitude: float = 0.0

	func _init(p_kind: int, p_op: int, p_mag: float) -> void:
		kind = p_kind
		op = p_op
		magnitude = p_mag


class ActiveEffect extends RefCounted:
	var effect: GDGameplayEffectRes = null
	var owner_id: int = 0
	var source_caster_id: int = 0
	var remaining_ms: float = 0.0
	var next_tick_ms: float = INF
	var handles: Array[AppliedModifierHandle] = []

	func _init(
		p_eff: GDGameplayEffectRes,
		p_owner: int,
		p_caster: int,
		p_rem_ms: float,
		p_next_tick_ms: float
	) -> void:
		effect = p_eff
		owner_id = p_owner
		source_caster_id = p_caster
		remaining_ms = p_rem_ms
		next_tick_ms = p_next_tick_ms


class GameplayEffectApplier extends RefCounted:
	var _bus: GDCoreServices.EventBus = null
	var _attribute_sets: Dictionary = {} # owner_id -> GDAttributeSystem.AttributeSet
	var _active: Array[ActiveEffect] = []
	var _disposed: bool = false
	var _cb_applied: Callable

	var active_count: int:
		get:
			return _active.size()

	func _init(p_bus: GDCoreServices.EventBus, p_attr_sets: Dictionary = {}) -> void:
		_bus = p_bus if p_bus != null else GDCoreServices.get_event_bus()
		_attribute_sets = p_attr_sets
		_cb_applied = Callable(self, "_handle_effect_applied")
		_bus.subscribe(EVENT_GAMEPLAY_EFFECT_APPLIED, _cb_applied)

	func register_attribute_set(owner_id: int, attr_set: GDAttributeSystem.AttributeSet) -> void:
		_attribute_sets[owner_id] = attr_set

	func try_apply(owner_id: int, source_caster_id: int, effect: GDGameplayEffectRes) -> bool:
		if effect == null or not _attribute_sets.has(owner_id):
			return false
		var set_obj: GDAttributeSystem.AttributeSet = _attribute_sets[owner_id]
		if set_obj == null:
			return false
		if is_zero_approx(effect.duration):
			_apply_instant(set_obj, effect)
			return true
		var rem_ms := INF if effect.duration < 0.0 else effect.duration * 1000.0
		var next_ms := effect.period * 1000.0 if effect.period > 0.0 else INF
		var active := ActiveEffect.new(effect, owner_id, source_caster_id, rem_ms, next_ms)
		_apply_durational_modifiers(set_obj, effect, active)
		_active.append(active)
		return true

	func snapshot() -> Array[ActiveEffect]:
		return _active.duplicate()

	func do_tick(delta_ms: float) -> void:
		for i in range(_active.size() - 1, -1, -1):
			var ae := _active[i]
			if not is_inf(ae.remaining_ms):
				ae.remaining_ms -= delta_ms
			ae.next_tick_ms -= delta_ms
			if ae.effect.period > 0.0 and ae.next_tick_ms <= 0.0:
				if _attribute_sets.has(ae.owner_id):
					_apply_periodic_modifiers(_attribute_sets[ae.owner_id], ae.effect)
				ae.next_tick_ms += ae.effect.period * 1000.0
			if ae.remaining_ms <= 0.0:
				if _attribute_sets.has(ae.owner_id):
					_revert_modifiers(_attribute_sets[ae.owner_id], ae)
				_bus.publish(EVENT_GAMEPLAY_EFFECT_EXPIRED, {
					"owner_id": ae.owner_id,
					"effect": ae.effect,
					"reason": "duration-expired",
				})
				_active.remove_at(i)

	func dispose() -> void:
		if _disposed:
			return
		_disposed = true
		_bus.unsubscribe(EVENT_GAMEPLAY_EFFECT_APPLIED, _cb_applied)
		_active.clear()

	func _handle_effect_applied(evt: Variant) -> void:
		if not (evt is Dictionary):
			return
		var d := evt as Dictionary
		var eff = d.get("effect", null)
		if eff is GDGameplayEffectRes:
			try_apply(int(d.get("owner_id", 0)), 0, eff)

	func _apply_instant(set_obj: GDAttributeSystem.AttributeSet, effect: GDGameplayEffectRes) -> void:
		for m in effect.modifiers:
			if m == null:
				continue
			var mapped := GDSkillTypes.try_map_attribute_name(m.attribute_name)
			if not bool(mapped.get("ok", false)):
				continue
			var kind := int(mapped["kind"])
			match m.op:
				GDSkillTypes.ModifierOp.ADD:
					set_obj.apply_delta(kind, m.magnitude, "effect-applied")
				GDSkillTypes.ModifierOp.MULTIPLY:
					set_obj.add_modifier(kind, 0.0, m.magnitude, "effect-applied")
				GDSkillTypes.ModifierOp.OVERRIDE:
					set_obj.set_base(kind, m.magnitude, "effect-applied")

	func _apply_durational_modifiers(set_obj: GDAttributeSystem.AttributeSet, effect: GDGameplayEffectRes, active: ActiveEffect) -> void:
		for m in effect.modifiers:
			if m == null:
				continue
			var mapped := GDSkillTypes.try_map_attribute_name(m.attribute_name)
			if not bool(mapped.get("ok", false)):
				continue
			var kind := int(mapped["kind"])
			match m.op:
				GDSkillTypes.ModifierOp.ADD:
					set_obj.apply_delta(kind, m.magnitude, "effect-applied")
					active.handles.append(AppliedModifierHandle.new(kind, m.op, m.magnitude))
				GDSkillTypes.ModifierOp.MULTIPLY:
					set_obj.add_modifier(kind, 0.0, m.magnitude, "effect-applied")
					active.handles.append(AppliedModifierHandle.new(kind, m.op, m.magnitude))

	func _apply_periodic_modifiers(set_obj: GDAttributeSystem.AttributeSet, effect: GDGameplayEffectRes) -> void:
		for m in effect.modifiers:
			if m != null and m.op == GDSkillTypes.ModifierOp.ADD:
				var mapped := GDSkillTypes.try_map_attribute_name(m.attribute_name)
				if bool(mapped.get("ok", false)):
					set_obj.apply_delta(int(mapped["kind"]), m.magnitude, "effect-tick")

	func _revert_modifiers(set_obj: GDAttributeSystem.AttributeSet, active: ActiveEffect) -> void:
		for i in range(active.handles.size() - 1, -1, -1):
			var h := active.handles[i]
			match h.op:
				GDSkillTypes.ModifierOp.ADD:
					set_obj.apply_delta(h.kind, -h.magnitude, "effect-expired")
				GDSkillTypes.ModifierOp.MULTIPLY:
					set_obj.remove_modifier(h.kind, 0.0, h.magnitude, "effect-expired")
		active.handles.clear()


## SkillHolderNode 对应 SkillHolderMono（按 UniqueName 查找并挂载技能资产）
class SkillHolderNode extends Node3D:
	@export var skills: Array[GDSkillRes] = []

	func find_skill(unique_or_skill_name: String) -> GDSkillRes:
		for s in skills:
			if s != null and (s.unique_name == unique_or_skill_name or s.skill_name == unique_or_skill_name):
				return s
		return null
