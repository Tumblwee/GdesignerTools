@tool
class_name GDAudioEngine
extends RefCounted

## 纯逻辑音频引擎与语音池系统
## 对应 TimiMiniGame.Core.Audio:
##   AudioBus / AudioActionType / AudioContainerMode / AudioVoiceLimitBehavior /
##   AudioPlayingId / AudioPostOptions / AudioEventDef / AudioEngineSettings /
##   AudioBusMixer / AudioContainerSelector / AudioBankRegistry / AudioEngine

enum AudioBus {
	MASTER = 0,
	BGM = 1,
	SFX = 2,
	UI = 3,
	VOICE = 4,
	AMBIENT = 5,
}

enum AudioActionType {
	PLAY = 0,
	STOP = 1,
	PAUSE = 2,
	RESUME = 3,
}

enum AudioContainerMode {
	SINGLE = 0,
	RANDOM = 1,
	RANDOM_NO_REPEAT = 2,
	SEQUENCE = 3,
}

enum AudioVoiceLimitBehavior {
	REJECT_NEW = 0,
	STOP_OLDEST = 1,
	STOP_QUIETEST = 2,
}


class AudioPlayingId extends RefCounted:
	var slot: int = -1
	var generation: int = 0

	func _init(p_slot: int = -1, p_gen: int = 0) -> void:
		slot = p_slot
		generation = p_gen

	var is_valid: bool:
		get:
			return slot >= 0 and generation > 0

	static func invalid() -> AudioPlayingId:
		return AudioPlayingId.new(-1, 0)


class AudioPostOptions extends RefCounted:
	var volume_scale: float = 1.0
	var pitch_scale: float = 1.0
	var delay_seconds: float = 0.0
	var follow: Node3D = null
	var position: Vector3 = Vector3.ZERO
	var has_position: bool = false
	var on_end: Callable = Callable()

	static func default_options() -> AudioPostOptions:
		return AudioPostOptions.new()


class AudioEventDef extends Resource:
	@export var event_name: String = ""
	@export var action_type: int = AudioActionType.PLAY
	@export var target_event: String = ""
	@export var bus: int = AudioBus.SFX
	@export var container_mode: int = AudioContainerMode.SINGLE
	@export var res_paths: PackedStringArray = PackedStringArray()
	@export var volume: float = 1.0
	@export var volume_random: float = 0.0
	@export var pitch: float = 1.0
	@export var pitch_random: float = 0.0
	@export var loop: bool = false
	@export var spatial: bool = false
	@export var min_distance: float = 1.0
	@export var max_distance: float = 30.0
	@export var fade_in_ms: int = 0
	@export var fade_out_ms: int = 0
	@export var cooldown_ms: int = 0
	@export var max_instances: int = 0
	@export var limit_behavior: int = AudioVoiceLimitBehavior.REJECT_NEW
	@export var priority: int = 50


class AudioEngineSettings extends RefCounted:
	var max_voices: int = 16
	var master_volume: float = 1.0
	var bgm_volume: float = 1.0
	var sfx_volume: float = 1.0
	var ui_volume: float = 1.0
	var voice_volume: float = 1.0
	var ambient_volume: float = 1.0


class AudioBusMixer extends RefCounted:
	var _volumes: Dictionary = {}
	var _muted: Dictionary = {}
	var _paused: Dictionary = {}

	func _init(settings: AudioEngineSettings = null) -> void:
		var s := settings if settings != null else AudioEngineSettings.new()
		_volumes[AudioBus.MASTER] = clampf(s.master_volume, 0.0, 1.0)
		_volumes[AudioBus.BGM] = clampf(s.bgm_volume, 0.0, 1.0)
		_volumes[AudioBus.SFX] = clampf(s.sfx_volume, 0.0, 1.0)
		_volumes[AudioBus.UI] = clampf(s.ui_volume, 0.0, 1.0)
		_volumes[AudioBus.VOICE] = clampf(s.voice_volume, 0.0, 1.0)
		_volumes[AudioBus.AMBIENT] = clampf(s.ambient_volume, 0.0, 1.0)

	func set_volume(bus: int, vol: float) -> void:
		_volumes[bus] = clampf(vol, 0.0, 1.0)

	func get_volume(bus: int) -> float:
		return float(_volumes.get(bus, 1.0))

	func set_muted(bus: int, muted: bool) -> void:
		_muted[bus] = muted

	func is_muted(bus: int) -> bool:
		return bool(_muted.get(bus, false))

	func set_paused(bus: int, paused: bool) -> void:
		_paused[bus] = paused

	func is_paused(bus: int) -> bool:
		return bool(_paused.get(bus, false))

	func evaluate(bus: int) -> float:
		if is_muted(AudioBus.MASTER) or is_muted(bus):
			return 0.0
		var master_v := get_volume(AudioBus.MASTER)
		if bus == AudioBus.MASTER:
			return master_v
		return master_v * get_volume(bus)


class AudioContainerSelector extends RefCounted:
	var _last_index: Dictionary = {}

	func select(def: AudioEventDef) -> int:
		if def == null or def.res_paths.is_empty():
			return -1
		var count := def.res_paths.size()
		if count == 1 or def.container_mode == AudioContainerMode.SINGLE:
			return 0
		match def.container_mode:
			AudioContainerMode.RANDOM:
				return randi() % count
			AudioContainerMode.RANDOM_NO_REPEAT:
				return _select_random_no_repeat(def.event_name, count)
			AudioContainerMode.SEQUENCE:
				return _select_sequence(def.event_name, count)
			_:
				return 0

	func reset() -> void:
		_last_index.clear()

	func _select_random_no_repeat(event_name: String, count: int) -> int:
		if count <= 1:
			return 0
		var last := int(_last_index.get(event_name, -1))
		var pick := randi() % (count - 1)
		if last >= 0 and pick >= last:
			pick += 1
		_last_index[event_name] = pick
		return pick

	func _select_sequence(event_name: String, count: int) -> int:
		if not _last_index.has(event_name):
			_last_index[event_name] = 0
			return 0
		var nxt := (int(_last_index[event_name]) + 1) % count
		_last_index[event_name] = nxt
		return nxt


class AudioEngine extends RefCounted:
	var _events: Dictionary = {} # event_name -> AudioEventDef
	var _mixer: AudioBusMixer = null
	var _selector: AudioContainerSelector = null
	var _slots: Array[Dictionary] = []
	var _cooldown_until: Dictionary = {}
	var _parameters: Dictionary = {}
	var _states: Dictionary = {}
	var _switches: Dictionary = {}
	var _time: float = 0.0
	var _disposed: bool = false

	func _init(settings: AudioEngineSettings = null) -> void:
		var s := settings if settings != null else AudioEngineSettings.new()
		var max_v := maxi(1, s.max_voices)
		_mixer = AudioBusMixer.new(s)
		_selector = AudioContainerSelector.new()
		for i in range(max_v):
			_slots.append(_make_empty_slot(i))

	static func _make_empty_slot(idx: int) -> Dictionary:
		return {
			"index": idx,
			"occupied": false,
			"generation": 0,
			"id": AudioPlayingId.invalid(),
			"def": null,
			"event_name": "",
			"address": "",
			"volume": 1.0,
			"started_at": 0.0,
			"paused_by_bus": false,
			"paused_manually": false,
			"on_end": Callable(),
		}

	func register_event(def: AudioEventDef) -> void:
		if def != null and not def.event_name.is_empty():
			_events[def.event_name] = def

	func post_event(event_name: String, options: AudioPostOptions = null) -> AudioPlayingId:
		if _disposed or event_name.is_empty() or not _events.has(event_name):
			return AudioPlayingId.invalid()
		var def: AudioEventDef = _events[event_name]
		var opts := options if options != null else AudioPostOptions.default_options()
		match def.action_type:
			AudioActionType.STOP:
				stop_event(def.target_event, def.fade_out_ms)
				return AudioPlayingId.invalid()
			AudioActionType.PAUSE:
				_pause_event(def.target_event, true)
				return AudioPlayingId.invalid()
			AudioActionType.RESUME:
				_pause_event(def.target_event, false)
				return AudioPlayingId.invalid()
			_:
				return _post_play(def, opts)

	func _post_play(def: AudioEventDef, opts: AudioPostOptions) -> AudioPlayingId:
		if def.cooldown_ms > 0 and _cooldown_until.has(def.event_name):
			if _time < float(_cooldown_until[def.event_name]):
				return AudioPlayingId.invalid()
		var path_idx := _selector.select(def)
		if path_idx < 0 or path_idx >= def.res_paths.size():
			return AudioPlayingId.invalid()
		var slot_idx := _allocate_slot(def)
		if slot_idx < 0:
			return AudioPlayingId.invalid()
		var slot: Dictionary = _slots[slot_idx]
		var gen := int(slot["generation"]) + 1
		var pid := AudioPlayingId.new(slot_idx, gen)
		slot["occupied"] = true
		slot["generation"] = gen
		slot["id"] = pid
		slot["def"] = def
		slot["event_name"] = def.event_name
		slot["address"] = def.res_paths[path_idx]
		slot["volume"] = _mixer.evaluate(def.bus) * def.volume * opts.volume_scale
		slot["started_at"] = _time
		slot["on_end"] = opts.on_end
		if def.cooldown_ms > 0:
			_cooldown_until[def.event_name] = _time + float(def.cooldown_ms) / 1000.0
		return pid

	func _allocate_slot(def: AudioEventDef) -> int:
		var cur_cnt := get_playing_count(def.event_name)
		if def.max_instances > 0 and cur_cnt >= def.max_instances:
			match def.limit_behavior:
				AudioVoiceLimitBehavior.REJECT_NEW:
					return -1
				AudioVoiceLimitBehavior.STOP_OLDEST:
					var old_idx := _find_oldest(def.event_name)
					if old_idx >= 0:
						_recycle_slot(old_idx, true)
					return old_idx
				AudioVoiceLimitBehavior.STOP_QUIETEST:
					var q_idx := _find_quietest(def.event_name)
					if q_idx >= 0:
						_recycle_slot(q_idx, true)
					return q_idx
		for i in range(_slots.size()):
			if not bool(_slots[i]["occupied"]):
				return i
		var victim := _find_steal_victim(def.priority)
		if victim >= 0:
			_recycle_slot(victim, true)
		return victim

	func _find_oldest(event_name: String) -> int:
		var best := -1
		var best_t := INF
		for i in range(_slots.size()):
			var s: Dictionary = _slots[i]
			if bool(s["occupied"]) and str(s["event_name"]) == event_name and float(s["started_at"]) < best_t:
				best_t = float(s["started_at"])
				best = i
		return best

	func _find_quietest(event_name: String) -> int:
		var best := -1
		var best_v := INF
		for i in range(_slots.size()):
			var s: Dictionary = _slots[i]
			if bool(s["occupied"]) and str(s["event_name"]) == event_name and float(s["volume"]) < best_v:
				best_v = float(s["volume"])
				best = i
		return best

	func _find_steal_victim(incoming_prio: int) -> int:
		var best := -1
		var best_p := incoming_prio
		var best_t := INF
		for i in range(_slots.size()):
			var s: Dictionary = _slots[i]
			var d: AudioEventDef = s.get("def", null)
			if not bool(s["occupied"]) or d == null or d.priority > incoming_prio:
				continue
			if best < 0 or d.priority < best_p or (d.priority == best_p and float(s["started_at"]) < best_t):
				best = i
				best_p = d.priority
				best_t = float(s["started_at"])
		return best

	func _recycle_slot(idx: int, invoke_end: bool) -> void:
		if idx < 0 or idx >= _slots.size():
			return
		var s: Dictionary = _slots[idx]
		if not bool(s["occupied"]):
			return
		var pid: AudioPlayingId = s["id"]
		var cb: Callable = s["on_end"]
		s["occupied"] = false
		s["def"] = null
		s["event_name"] = ""
		s["address"] = ""
		s["on_end"] = Callable()
		if invoke_end and cb.is_valid():
			cb.call(pid)

	func stop(id: AudioPlayingId, _fade_out_ms: int = -1) -> void:
		if id == null or not id.is_valid:
			return
		if id.slot >= 0 and id.slot < _slots.size():
			var s: Dictionary = _slots[id.slot]
			if bool(s["occupied"]) and int(s["generation"]) == id.generation:
				_recycle_slot(id.slot, true)

	func stop_event(event_name: String, _fade_out_ms: int = -1) -> void:
		for i in range(_slots.size()):
			if bool(_slots[i]["occupied"]) and str(_slots[i]["event_name"]) == event_name:
				_recycle_slot(i, true)

	func stop_bus(bus: int, _fade_out_ms: int = -1) -> void:
		for i in range(_slots.size()):
			var d: AudioEventDef = _slots[i].get("def", null)
			if bool(_slots[i]["occupied"]) and d != null and d.bus == bus:
				_recycle_slot(i, true)

	func stop_all(_fade_out_ms: int = -1) -> void:
		for i in range(_slots.size()):
			if bool(_slots[i]["occupied"]):
				_recycle_slot(i, true)

	func _pause_event(event_name: String, paused: bool) -> void:
		for i in range(_slots.size()):
			if bool(_slots[i]["occupied"]) and str(_slots[i]["event_name"]) == event_name:
				_slots[i]["paused_manually"] = paused

	func is_playing(id: AudioPlayingId) -> bool:
		if _disposed or id == null or not id.is_valid or id.slot < 0 or id.slot >= _slots.size():
			return false
		var s: Dictionary = _slots[id.slot]
		return bool(s["occupied"]) and int(s["generation"]) == id.generation

	func get_playing_count(event_name: String) -> int:
		var cnt := 0
		for s in _slots:
			if bool(s["occupied"]) and str(s["event_name"]) == event_name:
				cnt += 1
		return cnt

	func set_bus_volume(bus: int, vol: float) -> void:
		_mixer.set_volume(bus, vol)

	func get_bus_volume(bus: int) -> float:
		return _mixer.get_volume(bus)

	func set_bus_muted(bus: int, muted: bool) -> void:
		_mixer.set_muted(bus, muted)

	func is_bus_muted(bus: int) -> bool:
		return _mixer.is_muted(bus)

	func set_parameter(p_name: String, val: float) -> void:
		if not p_name.is_empty():
			_parameters[p_name] = val

	func try_get_parameter(p_name: String) -> Dictionary:
		if _parameters.has(p_name):
			return {"ok": true, "value": float(_parameters[p_name])}
		return {"ok": false, "value": 0.0}

	func set_state(group: String, val: String) -> void:
		if not group.is_empty():
			_states[group] = val

	func try_get_state(group: String) -> Dictionary:
		if _states.has(group):
			return {"ok": true, "value": str(_states[group])}
		return {"ok": false, "value": ""}

	func set_switch(group: String, val: String) -> void:
		if not group.is_empty():
			_switches[group] = val

	func tick(delta_time: float) -> void:
		if not _disposed and delta_time > 0.0:
			_time += delta_time

	func dispose() -> void:
		if _disposed:
			return
		_disposed = true
		stop_all(0)
		_selector.reset()
		_cooldown_until.clear()
		_parameters.clear()
		_states.clear()
		_switches.clear()
