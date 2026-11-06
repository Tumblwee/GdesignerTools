@tool
class_name GDGameFramework
extends RefCounted

## Lifecycle primitives shared by the manual API and configured GameModes.
static var _instance_counter: int = 0

static func next_instance_serial() -> int:
	_instance_counter += 1
	return _instance_counter


class GameModeContext extends RefCounted:
	var current_state_id: int = -1
	var services: GDCoreServices.ServiceLocator = null

	func _init(p_state_id: int = -1, p_services: GDCoreServices.ServiceLocator = null) -> void:
		current_state_id = p_state_id
		services = p_services if p_services != null else GDCoreServices.get_locator()


class SystemContext extends RefCounted:
	var owner_module: GameModuleBase = null
	var services: GDCoreServices.ServiceLocator = null

	func _init(p_owner: GameModuleBase, p_services: GDCoreServices.ServiceLocator) -> void:
		owner_module = p_owner
		services = p_services


class BaseSystem extends RefCounted:
	var _context: SystemContext = null
	var is_constructed: bool = false
	var is_begun_play: bool = false
	var is_disposed: bool = false
	var _subscriptions: Array[Dictionary] = []
	var _provided_services: Array[Dictionary] = []

	var event_bus: GDCoreServices.EventBus:
		get:
			return GDCoreServices.get_event_bus()

	func listen(event_name: String, callback: Callable) -> void:
		event_bus.subscribe(event_name, callback)
		_subscriptions.append({"bus": event_bus, "name": event_name, "callback": callback})

	func provide_service(key: String, instance: Object) -> void:
		var locator := _context.services if _context != null else GDCoreServices.get_locator()
		locator.register_service(key, instance)
		_provided_services.append({"locator": locator, "key": key, "instance": instance})

	func construct(ctx: SystemContext) -> void:
		if is_constructed:
			return
		_context = ctx
		is_constructed = true
		is_disposed = false
		on_construct(ctx)

	func begin_play(ctx: SystemContext) -> void:
		if is_begun_play or is_disposed:
			return
		is_begun_play = true
		on_begin_play(ctx)

	func dispose() -> void:
		if is_disposed:
			return
		is_disposed = true
		on_dispose()
		GDGameFramework.cleanup_owned(_subscriptions, _provided_services)
		_context = null
		is_constructed = false
		is_begun_play = false

	func on_construct(_ctx: SystemContext) -> void:
		pass
	func on_begin_play(_ctx: SystemContext) -> void:
		pass
	func on_dispose() -> void:
		pass
	func on_update(_delta_time: float) -> void:
		pass
	func on_late_update(_delta_time: float) -> void:
		pass
	func on_fixed_update(_fixed_delta_time: float) -> void:
		pass


static func cleanup_owned(subscriptions: Array[Dictionary], services: Array[Dictionary]) -> void:
	for entry in subscriptions:
		entry.bus.unsubscribe(entry.name, entry.callback)
	subscriptions.clear()
	for entry in services:
		if entry.locator.resolve(entry.key) == entry.instance:
			entry.locator.unregister_service(entry.key)
	services.clear()


class SystemContainer extends RefCounted:
	enum Phase { IDLE = 0, CONSTRUCTED = 1, BEGUN_PLAY = 2, DISPOSED = 3 }
	var _owner: GameModuleBase = null
	var _systems: Array[BaseSystem] = []
	var _phase: int = Phase.IDLE
	var _sys_context: SystemContext = null

	func _init(owner: GameModuleBase) -> void:
		_owner = owner

	func add(sys: BaseSystem) -> BaseSystem:
		if sys == null or _systems.has(sys) or _phase == Phase.DISPOSED:
			return sys
		_systems.append(sys)
		if _phase >= Phase.CONSTRUCTED and _sys_context != null:
			sys.construct(_sys_context)
		if _phase == Phase.BEGUN_PLAY and _sys_context != null:
			sys.begin_play(_sys_context)
		return sys

	func construct_all(ctx: SystemContext) -> void:
		_sys_context = ctx
		_phase = Phase.CONSTRUCTED
		for sys in _systems.duplicate():
			sys.construct(ctx)

	func begin_play_all(ctx: SystemContext) -> void:
		_sys_context = ctx
		_phase = Phase.BEGUN_PLAY
		for sys in _systems.duplicate():
			sys.begin_play(ctx)

	func dispose_all_reverse() -> void:
		_phase = Phase.DISPOSED
		for i in range(_systems.size() - 1, -1, -1):
			_systems[i].dispose()
		_systems.clear()
		_sys_context = null
		_owner = null

	func tick_update(dt: float) -> void:
		_tick(&"on_update", dt)
	func tick_late_update(dt: float) -> void:
		_tick(&"on_late_update", dt)
	func tick_fixed_update(dt: float) -> void:
		_tick(&"on_fixed_update", dt)

	func _tick(method: StringName, dt: float, should_skip: Callable = Callable()) -> void:
		if _phase != Phase.BEGUN_PLAY:
			return
		for sys in _systems.duplicate():
			if _owner == null or _owner.is_disposed or _owner.is_faulted or (should_skip.is_valid() and should_skip.call()):
				break
			if sys.is_begun_play and not sys.is_disposed:
				sys.call(method, dt)


class GameModuleBase extends RefCounted:
	var systems: SystemContainer = null
	var category: int = GDCoreTypes.ModuleCategory.MISC
	var is_constructed: bool = false
	var is_begun_play: bool = false
	var is_disposed: bool = false
	var is_faulted: bool = false
	var last_fault: Dictionary = {}
	var module_id: int = -1
	var display_name: String = ""
	var scope: String = "manual"
	var script_path: String = ""
	var config_order: int = -1
	var initialization_order: int = -1
	var tick_enabled: bool = true
	var debug_restartable: bool = false
	var instance_serial: int = 0
	var params: Resource = null
	var _cached_bus: GDCoreServices.EventBus = null
	var _services: GDCoreServices.ServiceLocator = null
	var _subscriptions: Array[Dictionary] = []
	var _provided_services: Array[Dictionary] = []
	var _fault_hook: Callable
	var _factory: Callable

	func _init() -> void:
		instance_serial = GDGameFramework.next_instance_serial()
		systems = SystemContainer.new(self)

	var event_bus: GDCoreServices.EventBus:
		get:
			if _cached_bus == null:
				_cached_bus = GDCoreServices.get_event_bus()
			return _cached_bus

	func configure(value: Resource) -> void:
		# Config factories pass an isolated duplicate; overrides receive that same copy.
		params = value

	func listen(event_name: String, callback: Callable) -> void:
		event_bus.subscribe(event_name, callback)
		_subscriptions.append({"bus": event_bus, "name": event_name, "callback": callback})

	func provide_service(key: String, instance: Object) -> void:
		var locator := _services if _services != null else GDCoreServices.get_locator()
		locator.register_service(key, instance)
		_provided_services.append({"locator": locator, "key": key, "instance": instance})

	func report_fault(phase: StringName, message: String) -> void:
		if is_faulted:
			return
		is_faulted = true
		last_fault = {"phase": String(phase), "message": message, "frame": Engine.get_process_frames()}
		if _fault_hook.is_valid():
			_fault_hook.call(self)

	func construct(ctx: GameModeContext) -> void:
		if is_constructed:
			return
		if systems == null or systems._phase == SystemContainer.Phase.DISPOSED:
			systems = SystemContainer.new(self)
		_services = ctx.services
		is_constructed = true
		is_disposed = false
		var sys_ctx := SystemContext.new(self, ctx.services)
		systems.construct_all(sys_ctx)
		on_construct(ctx)

	func begin_play(ctx: GameModeContext) -> void:
		if is_begun_play or is_faulted or is_disposed:
			return
		is_begun_play = true
		var sys_ctx := SystemContext.new(self, ctx.services)
		systems.begin_play_all(sys_ctx)
		if not is_faulted:
			on_begin_play(ctx)

	func dispose() -> void:
		if is_disposed:
			return
		is_disposed = true
		on_dispose()
		systems.dispose_all_reverse()
		GDGameFramework.cleanup_owned(_subscriptions, _provided_services)
		is_constructed = false
		is_begun_play = false
		_services = null
		_fault_hook = Callable()

	func on_construct(_ctx: GameModeContext) -> void:
		pass
	func on_begin_play(_ctx: GameModeContext) -> void:
		pass
	func on_dispose() -> void:
		pass
	func on_update(_dt: float) -> void:
		pass
	func on_late_update(_dt: float) -> void:
		pass
	func on_fixed_update(_dt: float) -> void:
		pass


class ModuleTickDriver extends RefCounted:
	var _active_modules: Array[GameModuleBase] = []
	var _faulted_modules: Dictionary = {}
	var _version: int = 0
	var should_skip: Callable
	var delegate: Callable

	func clear() -> void:
		_version += 1
		_active_modules.clear()
		_faulted_modules.clear()

	func rebuild(modules: Array[GameModuleBase]) -> void:
		_version += 1
		_active_modules.clear()
		_faulted_modules.clear()
		for mod in modules:
			if mod != null and mod.tick_enabled:
				_active_modules.append(mod)
				if mod.is_faulted:
					_faulted_modules[mod] = true

	func fault_module(mod: GameModuleBase, reason: String) -> void:
		_faulted_modules[mod] = true
		if not mod.is_faulted:
			mod.report_fault(&"tick", reason)

	func is_ticking(mod: GameModuleBase) -> bool:
		return _active_modules.has(mod) and not mod.is_disposed and not mod.is_faulted

	func tick_update(dt: float) -> void:
		_tick(&"on_update", dt)
	func tick_late_update(dt: float) -> void:
		_tick(&"on_late_update", dt)
	func tick_fixed_update(dt: float) -> void:
		_tick(&"on_fixed_update", dt)

	func _tick(method: StringName, dt: float) -> void:
		if delegate.is_valid():
			delegate.call(method, dt)
			return
		var start_ver := _version
		var skip_systems := func() -> bool:
			return _version != start_ver or (should_skip.is_valid() and should_skip.call())
		for mod in _active_modules:
			if _version != start_ver or (should_skip.is_valid() and should_skip.call()):
				break
			if mod == null or mod.is_disposed or mod.is_faulted or _faulted_modules.has(mod):
				continue
			mod.call(method, dt)
			# Systems share their module's Tick gate and state-transition safe point.
			# A fault or switch from the module callback must also stop its systems.
			if mod.systems != null:
				mod.systems._tick(method, dt, skip_systems)


class GameStateMachine extends RefCounted:
	const EVENT_GAME_STATE_CHANGED := "GameStateChangedEvent"
	const MAX_TRANSITIONS := 8
	var current_state_id: int = -1
	var state_keys: Dictionary = {}
	var lifecycle_hook: Callable
	# Legacy combined driver is retained; actual global/state drivers are independent.
	var tick_driver: ModuleTickDriver = ModuleTickDriver.new()
	var global_tick_driver: ModuleTickDriver = ModuleTickDriver.new()
	var state_tick_driver: ModuleTickDriver = ModuleTickDriver.new()
	var _bindings: Dictionary = {}
	var _factory_bindings: Dictionary = {}
	var _active_modules: Array[GameModuleBase] = []
	var _global_modules: Array[GameModuleBase] = []
	var _global_factories: Array[Callable] = []
	var _globals_initialized: bool = false
	var _queue: Array[Dictionary] = []
	var _callback_depth: int = 0
	var _draining: bool = false
	var _executing_operation: bool = false
	var _operation_depth: int = -1
	var _transitioning: bool = false
	var _skip_state_tick: bool = false
	var _closed: bool = false
	var _initialization_serial: int = 0
	var _transition_serial: int = 0
	var _transitions: Dictionary = {}
	var _configuration_previous: Dictionary = {}

	var pending_state_id: int:
		get:
			for i in range(_queue.size() - 1, -1, -1):
				if _queue[i].has("target"):
					return _queued_target(_queue[i])
			return -1
	var is_transitioning: bool:
		get:
			return _transitioning

	func _init() -> void:
		# Weak capture avoids retaining the state machine through its drivers.
		var owner := weakref(self)
		tick_driver.delegate = func(method: StringName, dt: float) -> void:
			var machine: GameStateMachine = owner.get_ref()
			if machine != null:
				machine._tick(method, dt)
		state_tick_driver.should_skip = func() -> bool:
			var machine: GameStateMachine = owner.get_ref()
			return machine == null or machine._skip_state_tick

	func register_state_binding(state_id: int, modules: Array[GameModuleBase]) -> void:
		_bindings[state_id] = modules.duplicate()
		_factory_bindings.erase(state_id)
		for index in modules.size():
			if modules[index] != null:
				modules[index].config_order = index

	func register_state_factories(state_id: int, factories: Array[Callable]) -> void:
		_factory_bindings[state_id] = factories.duplicate()
		_bindings.erase(state_id)

	func register_global_modules(modules: Array[GameModuleBase]) -> void:
		_global_modules = modules.duplicate()
		_global_factories.clear()
		for index in modules.size():
			if modules[index] != null:
				modules[index].config_order = index

	func register_global_factories(factories: Array[Callable]) -> void:
		_global_factories = factories.duplicate()
		_global_modules.clear()

	func has_state(state_id: int) -> bool:
		return state_id != -1 and (_bindings.has(state_id) or _factory_bindings.has(state_id))

	func is_callback_active() -> bool:
		return _callback_depth > 0 or _draining

	func is_operation_safe_point() -> bool:
		return _executing_operation and _callback_depth == _operation_depth

	## Replace bindings without dropping accepted requests or resetting the drain limit.
	## The host calls this from enqueue_operation(), then rebinds the new config.
	func reset_configuration() -> bool:
		if _closed or not is_operation_safe_point():
			return false
		_callback_depth += 1
		state_tick_driver.clear()
		global_tick_driver.clear()
		_configuration_previous = {"id": current_state_id, "key": String(state_keys.get(current_state_id, ""))}
		if current_state_id != -1:
			_emit(&"state_exit", {"reason": "apply"})
		_dispose_modules(_active_modules)
		_active_modules.clear()
		_dispose_modules(_global_modules)
		_global_modules.clear()
		_globals_initialized = false
		_bindings.clear()
		_factory_bindings.clear()
		_global_factories.clear()
		state_keys.clear()
		current_state_id = -1
		_initialization_serial = 0
		_transitions.clear()
		_callback_depth -= 1
		return true

	func enter_configuration_state(state_id: int, reason: StringName = &"apply") -> bool:
		if not is_operation_safe_point():
			return switch_state(state_id, reason)
		if not has_state(state_id):
			return _reject(state_id, "invalid_state")
		var previous := _configuration_previous
		_configuration_previous = {}
		_transition(state_id, reason, previous)
		return true

	func _queued_target(operation: Dictionary) -> int:
		var key := StringName(operation.get("target_key", ""))
		if key.is_empty():
			return int(operation.target)
		for id in state_keys:
			if state_keys[id] == key:
				return int(id)
		return -1

	func switch_state(new_state_id: int, reason: StringName = &"switch") -> bool:
		if _closed:
			return _reject(new_state_id, "not_running")
		if not has_state(new_state_id):
			return _reject(new_state_id, "invalid_state")
		var effective := pending_state_id
		if effective == -1:
			effective = current_state_id
		if new_state_id == effective:
			return _reject(new_state_id, "same_target")
		_queue.append({"kind": "switch", "target": new_state_id, "target_key": state_keys.get(new_state_id, ""), "reason": reason})
		_skip_state_tick = true
		_drain()
		return true

	func restart_state() -> bool:
		if _closed or current_state_id == -1:
			return _reject(current_state_id, "not_running")
		if not _factory_bindings.has(current_state_id):
			return _reject(current_state_id, "not_restartable")
		_queue.append({"kind": "switch", "target": current_state_id, "target_key": state_keys.get(current_state_id, ""), "reason": &"restart"})
		_skip_state_tick = true
		_drain()
		return true

	func restart_module(id: int) -> Error:
		if _closed or current_state_id == -1:
			return ERR_UNCONFIGURED
		var mod := _find_module(id)
		if mod == null:
			return ERR_DOES_NOT_EXIST
		if not mod.debug_restartable or not mod._factory.is_valid():
			return ERR_UNAVAILABLE
		_queue.append({"kind": "module", "module_id": id})
		_skip_state_tick = true
		_drain()
		return OK

	func enqueue_operation(callback: Callable) -> bool:
		if _closed or not callback.is_valid():
			return false
		_queue.append({"kind": "operation", "callback": callback})
		_skip_state_tick = true
		_drain()
		return true

	## Terminal cleanup must run even if preceding transitions exhaust the budget.
	func enqueue_shutdown(callback: Callable) -> bool:
		if _closed or not callback.is_valid():
			return false
		_queue.append({"kind": "shutdown", "callback": callback})
		_skip_state_tick = true
		_drain()
		return true

	func _reject(target: int, code: String) -> bool:
		_emit(&"switch_rejected", {"target": target, "result": code, "message": "State request rejected: %s (%s)" % [target, code]})
		GDGameLogger.log_error_p("GameStateMachine: %s (%s)" % [code, target])
		return false

	func _drain() -> void:
		if _callback_depth > 0 or _draining:
			return
		_draining = true
		var count := 0
		while not _queue.is_empty() and not _closed:
			if count >= MAX_TRANSITIONS:
				var terminal: Callable
				for pending in _queue:
					if pending.kind == "shutdown":
						terminal = pending.callback
						break
				var discarded := _queue.size() - (1 if terminal.is_valid() else 0)
				_queue.clear()
				if discarded > 0:
					_emit(&"reentry_overflow", {"result": "reentry_overflow", "discarded": discarded})
					GDGameLogger.log_error_p("GameStateMachine: reentry_overflow; maximum 8 queued operations")
				if terminal.is_valid():
					_execute_operation(terminal)
				break
			count += 1
			var operation: Dictionary = _queue.pop_front()
			match operation.kind:
				"switch":
					var target := _queued_target(operation)
					if has_state(target):
						_transition(target, StringName(operation.reason))
					else:
						_reject(target, "invalid_state")
				"module":
					_restart_module_now(int(operation.module_id))
				"operation", "shutdown":
					_execute_operation(operation.callback)
		_draining = false
		_skip_state_tick = false

	func _execute_operation(callback: Callable) -> void:
		_callback_depth += 1
		_executing_operation = true
		_operation_depth = _callback_depth
		callback.call()
		_executing_operation = false
		_operation_depth = -1
		_callback_depth -= 1

	func _instantiate(factories: Array) -> Array[GameModuleBase]:
		var result: Array[GameModuleBase] = []
		for factory in factories:
			var mod: GameModuleBase = factory.call() as GameModuleBase
			if mod != null:
				mod._factory = factory
				result.append(mod)
		return result

	func _ordered(modules: Array) -> Array[GameModuleBase]:
		var result: Array[GameModuleBase] = []
		for cat in [GDCoreTypes.ModuleCategory.SCENE, GDCoreTypes.ModuleCategory.PLAYER, GDCoreTypes.ModuleCategory.MISC]:
			for mod in modules:
				if mod is GameModuleBase and mod.category == cat:
					result.append(mod)
		return result

	func _initialize_modules(modules: Array[GameModuleBase]) -> void:
		var ctx := GameModeContext.new(current_state_id, GDCoreServices.get_locator())
		var owner := weakref(self)
		for mod in modules:
			mod.initialization_order = _initialization_serial
			_initialization_serial += 1
			mod._fault_hook = func(faulted: GameModuleBase) -> void:
				var machine: GameStateMachine = owner.get_ref()
				if machine != null:
					machine._on_module_fault(faulted)
			_emit_module(&"module_construct", mod)
			mod.construct(ctx)
		for mod in modules:
			if not mod.is_faulted:
				_emit_module(&"module_begin_play", mod)
				mod.begin_play(ctx)

	func _dispose_modules(modules: Array[GameModuleBase]) -> void:
		var reverse: Array[GameModuleBase] = modules.duplicate()
		reverse.sort_custom(func(a: GameModuleBase, b: GameModuleBase) -> bool: return a.initialization_order > b.initialization_order)
		for mod in reverse:
			_emit_module(&"module_dispose", mod)
			mod.dispose()

	func _transition(target: int, reason: StringName, previous: Dictionary = {}) -> void:
		_transitioning = true
		_callback_depth += 1
		var old := current_state_id
		var event_old := int(previous.get("id", old))
		state_tick_driver.clear()
		if old != -1:
			_emit(&"state_exit", {"state_key": String(state_keys.get(old, "")), "reason": String(reason)})
		_dispose_modules(_active_modules)
		_active_modules.clear()
		current_state_id = target
		_emit(&"state_enter_begin", {"reason": String(reason)})
		if not _globals_initialized:
			_globals_initialized = true
			if not _global_factories.is_empty():
				_global_modules = _instantiate(_global_factories)
			_global_modules = _ordered(_global_modules)
			_initialize_modules(_global_modules)
			global_tick_driver.rebuild(_global_modules)
		var raw: Array = _instantiate(_factory_bindings[target]) if _factory_bindings.has(target) else _bindings.get(target, [])
		_active_modules = _ordered(raw)
		_initialize_modules(_active_modules)
		state_tick_driver.rebuild(_active_modules)
		var from_key := String(previous.get("key", state_keys.get(old, "")))
		var to_key := String(state_keys.get(target, ""))
		_transition_serial += 1
		if event_old != -1:
			var transition_id := "%s:%s" % [from_key if not from_key.is_empty() else str(event_old), to_key if not to_key.is_empty() else str(target)]
			var entry: Dictionary = _transitions.get(transition_id, {"from": from_key, "to": to_key, "count": 0, "frame": 0})
			entry.count = int(entry.count) + 1
			entry.frame = Engine.get_process_frames()
			entry.last_frame = entry.frame
			entry.last_sequence = _transition_serial
			_transitions[transition_id] = entry
		_emit(&"state_enter_end", {"reason": String(reason), "old_state_key": from_key, "new_state_key": to_key, "from": from_key, "to": to_key})
		GDCoreServices.get_event_bus().publish(EVENT_GAME_STATE_CHANGED, {
			"old_state_id": event_old, "new_state_id": target, "reason": reason,
			"old_state_key": StringName(from_key), "new_state_key": StringName(to_key),
		})
		_callback_depth -= 1
		_transitioning = false

	func _find_module(id: int) -> GameModuleBase:
		if id < 0:
			return null
		for mod in _global_modules + _active_modules:
			if mod.module_id == id:
				return mod
		return null

	func _restart_module_now(id: int) -> void:
		var old := _find_module(id)
		if old == null or not old._factory.is_valid() or not old.debug_restartable:
			return
		_callback_depth += 1
		var global := _global_modules.has(old)
		var modules := _global_modules if global else _active_modules
		var index := modules.find(old)
		var driver := global_tick_driver if global else state_tick_driver
		driver._faulted_modules[old] = true
		_emit_module(&"module_dispose", old)
		old.dispose()
		var replacement: GameModuleBase = old._factory.call() as GameModuleBase
		if replacement != null:
			replacement._factory = old._factory
			modules[index] = replacement
			_initialize_modules([replacement])
		else:
			modules.remove_at(index)
		driver.rebuild(modules)
		_callback_depth -= 1

	func _on_module_fault(mod: GameModuleBase) -> void:
		var driver := global_tick_driver if _global_modules.has(mod) else state_tick_driver
		driver.fault_module(mod, str(mod.last_fault.get("message", "")))
		_emit_module(&"module_fault", mod, {"fault": mod.last_fault.duplicate(), "phase": mod.last_fault.get("phase", ""), "message": mod.last_fault.get("message", "")})

	func tick_update(dt: float) -> void:
		_tick(&"on_update", dt)
	func tick_late_update(dt: float) -> void:
		_tick(&"on_late_update", dt)
	func tick_fixed_update(dt: float) -> void:
		_tick(&"on_fixed_update", dt)

	func _tick(method: StringName, dt: float) -> void:
		if _closed or current_state_id == -1 or is_callback_active():
			return
		_callback_depth += 1
		_skip_state_tick = false
		global_tick_driver._tick(method, dt)
		state_tick_driver._tick(method, dt)
		_callback_depth -= 1
		_drain()

	func shutdown() -> void:
		if _closed:
			return
		# Disposal cannot interrupt a callback that still owns a module on its stack.
		if _callback_depth > 0 and not is_operation_safe_point():
			enqueue_shutdown(_shutdown_now)
			return
		_shutdown_now()

	func _shutdown_now() -> void:
		_closed = true
		_callback_depth += 1
		state_tick_driver.clear()
		global_tick_driver.clear()
		if current_state_id != -1:
			_emit(&"state_exit", {"reason": "shutdown"})
		_dispose_modules(_active_modules)
		_active_modules.clear()
		_dispose_modules(_global_modules)
		_global_modules.clear()
		_globals_initialized = false
		current_state_id = -1
		_queue.clear()
		_configuration_previous.clear()
		_bindings.clear()
		_factory_bindings.clear()
		_global_factories.clear()
		_callback_depth -= 1

	func capture_snapshot() -> Dictionary:
		var modules: Array[Dictionary] = []
		for mod in _global_modules + _active_modules:
			var driver := global_tick_driver if _global_modules.has(mod) else state_tick_driver
			var lifecycle := "faulted" if mod.is_faulted else ("disposed" if mod.is_disposed else ("running" if mod.is_begun_play else ("constructed" if mod.is_constructed else "idle")))
			var path := mod.script_path
			if path.is_empty() and mod.get_script() != null:
				path = mod.get_script().resource_path
			var identity: Variant = mod.module_id
			if mod.module_id < 0:
				identity = "manual:%s:%s" % ["global" if _global_modules.has(mod) else str(current_state_id), mod.config_order]
			modules.append({"id": identity, "module_id": mod.module_id, "display_name": mod.display_name,
				"scope": mod.scope, "script_path": path, "category": mod.category,
				"config_order": mod.config_order, "initialization_order": mod.initialization_order,
				"lifecycle": lifecycle, "tick_enabled": mod.tick_enabled, "is_ticking": driver.is_ticking(mod),
				"debug_restartable": mod.debug_restartable and mod._factory.is_valid(),
				"instance_serial": mod.instance_serial, "last_fault": mod.last_fault.duplicate(true)})
		return {"current_state_id": current_state_id, "pending_state_id": pending_state_id,
			"is_transitioning": is_transitioning, "modules": modules, "transitions": _transitions.values().duplicate(true)}

	func _emit_module(kind: StringName, mod: GameModuleBase, extra: Dictionary = {}) -> void:
		var detail := {"module_id": mod.module_id, "instance_serial": mod.instance_serial, "scope": mod.scope}
		detail.merge(extra, true)
		_emit(kind, detail)

	func _emit(kind: StringName, detail: Dictionary = {}) -> void:
		if not detail.has("state_key"):
			detail.state_key = String(state_keys.get(current_state_id, ""))
		if lifecycle_hook.is_valid():
			lifecycle_hook.call(kind, detail)
