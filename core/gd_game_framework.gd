@tool
class_name GDGameFramework
extends RefCounted

## 四层模型中的模块与系统生命周期 + GameStateMachine + ModuleTickDriver
## 对应 TimiMiniGame.Core 的 GameMode / GameStateMachine / ModuleTickDriver / GameModuleBase / BaseSystem / SystemContainer

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

	var event_bus: GDCoreServices.EventBus:
		get:
			return GDCoreServices.get_event_bus()

	func construct(ctx: SystemContext) -> void:
		if is_constructed:
			return
		_context = ctx
		is_constructed = true
		on_construct(ctx)

	func begin_play(ctx: SystemContext) -> void:
		if is_begun_play:
			return
		is_begun_play = true
		on_begin_play(ctx)

	func dispose() -> void:
		if is_disposed:
			return
		is_disposed = true
		on_dispose()
		_context = null

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


## 相位感知的系统容器：正向装配、逆序释放、BeginPlay 之后动态 Add 自动补跑
class SystemContainer extends RefCounted:
	enum Phase {
		IDLE = 0,
		CONSTRUCTED = 1,
		BEGUN_PLAY = 2,
		DISPOSED = 3,
	}

	var _owner: GameModuleBase = null
	var _systems: Array[BaseSystem] = []
	var _phase: int = Phase.IDLE
	var _sys_context: SystemContext = null

	func _init(owner: GameModuleBase) -> void:
		_owner = owner

	func add(sys: BaseSystem) -> BaseSystem:
		if sys == null or _systems.has(sys):
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
		for sys in _systems:
			sys.construct(ctx)

	func begin_play_all(ctx: SystemContext) -> void:
		_sys_context = ctx
		_phase = Phase.BEGUN_PLAY
		for sys in _systems:
			sys.begin_play(ctx)

	func dispose_all_reverse() -> void:
		_phase = Phase.DISPOSED
		for i in range(_systems.size() - 1, -1, -1):
			_systems[i].dispose()
		_systems.clear()
		_sys_context = null
		_owner = null

	func tick_update(dt: float) -> void:
		for sys in _systems:
			if not sys.is_disposed:
				sys.on_update(dt)

	func tick_late_update(dt: float) -> void:
		for sys in _systems:
			if not sys.is_disposed:
				sys.on_late_update(dt)

	func tick_fixed_update(dt: float) -> void:
		for sys in _systems:
			if not sys.is_disposed:
				sys.on_fixed_update(dt)


## 模块基类：三段模板方法（Construct -> BeginPlay -> Dispose）+ 系统容器
class GameModuleBase extends RefCounted:
	var systems: SystemContainer = null
	var category: int = GDCoreTypes.ModuleCategory.MISC
	var is_constructed: bool = false
	var is_begun_play: bool = false
	var is_disposed: bool = false
	var _cached_bus: GDCoreServices.EventBus = null

	func _init() -> void:
		systems = SystemContainer.new(self)

	var event_bus: GDCoreServices.EventBus:
		get:
			if _cached_bus == null:
				_cached_bus = GDCoreServices.get_event_bus()
			return _cached_bus

	func construct(ctx: GameModeContext) -> void:
		if is_constructed:
			return
		is_constructed = true
		is_disposed = false
		var sys_ctx := SystemContext.new(self, ctx.services)
		systems.construct_all(sys_ctx)
		on_construct(ctx)

	func begin_play(ctx: GameModeContext) -> void:
		if is_begun_play:
			return
		is_begun_play = true
		var sys_ctx := SystemContext.new(self, ctx.services)
		systems.begin_play_all(sys_ctx)
		on_begin_play(ctx)

	func dispose() -> void:
		if is_disposed:
			return
		is_disposed = true
		on_dispose()
		systems.dispose_all_reverse()
		is_constructed = false
		is_begun_play = false

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


## ModuleTickDriver：重入版本号保护 + 异常熔断剔除
class ModuleTickDriver extends RefCounted:
	var _active_modules: Array[GameModuleBase] = []
	var _faulted_modules: Dictionary = {}
	var _version: int = 0

	func clear() -> void:
		_version += 1
		_active_modules.clear()
		_faulted_modules.clear()

	func rebuild(modules: Array[GameModuleBase]) -> void:
		_version += 1
		_active_modules = modules.duplicate()
		_faulted_modules.clear()

	func fault_module(mod: GameModuleBase, reason: String) -> void:
		_faulted_modules[mod] = true
		GDGameLogger.log_error_p("[ModuleTickDriver] 模块异常熔断剔除：%s" % reason)

	func tick_update(dt: float) -> void:
		var start_ver := _version
		for mod in _active_modules:
			if _version != start_ver:
				break
			if mod == null or mod.is_disposed or _faulted_modules.has(mod):
				continue
			mod.on_update(dt)

	func tick_late_update(dt: float) -> void:
		var start_ver := _version
		for mod in _active_modules:
			if _version != start_ver:
				break
			if mod == null or mod.is_disposed or _faulted_modules.has(mod):
				continue
			mod.on_late_update(dt)

	func tick_fixed_update(dt: float) -> void:
		var start_ver := _version
		for mod in _active_modules:
			if _version != start_ver:
				break
			if mod == null or mod.is_disposed or _faulted_modules.has(mod):
				continue
			mod.on_fixed_update(dt)


## GameStateMachine：逆序 Dispose + 按 Category (Scene->Player->Misc) 两阶段装配（Construct 全趟 -> BeginPlay 全趟）+ 幂等切换
class GameStateMachine extends RefCounted:
	const EVENT_GAME_STATE_CHANGED := "GameStateChangedEvent"

	var current_state_id: int = -1
	var tick_driver: ModuleTickDriver = ModuleTickDriver.new()
	var _bindings: Dictionary = {} # state_id (int) -> Array[GameModuleBase]
	var _active_modules: Array[GameModuleBase] = []
	var _global_modules: Array[GameModuleBase] = []
	var _globals_initialized: bool = false

	func register_state_binding(state_id: int, modules: Array[GameModuleBase]) -> void:
		_bindings[state_id] = modules.duplicate()

	func register_global_modules(modules: Array[GameModuleBase]) -> void:
		_global_modules = modules.duplicate()

	func switch_state(new_state_id: int) -> bool:
		# 幂等切换：若 newState == CurrentState 立刻 return，不触发任何生命周期，也不派发事件
		if new_state_id == current_state_id and current_state_id != -1:
			return false

		var old_state_id := current_state_id
		# 1. 清空 Tick 队列
		tick_driver.clear()

		# 2. 旧模块逆序 Dispose
		for i in range(_active_modules.size() - 1, -1, -1):
			var old_mod := _active_modules[i]
			if old_mod != null:
				old_mod.dispose()
		_active_modules.clear()

		# 3. 赋值 CurrentStateId
		current_state_id = new_state_id
		var ctx := GameModeContext.new(current_state_id, GDCoreServices.get_locator())

		# 全局模块首次装配
		if not _globals_initialized and not _global_modules.is_empty():
			_globals_initialized = true
			for gmod in _global_modules:
				if gmod != null:
					gmod.construct(ctx)
			for gmod in _global_modules:
				if gmod != null:
					gmod.begin_play(ctx)

		# 4. 新模块按 category (Scene -> Player -> Misc) 排序后分两趟 Construct -> BeginPlay
		var raw_modules: Array = _bindings.get(new_state_id, [])
		var ordered: Array[GameModuleBase] = []
		for cat in [GDCoreTypes.ModuleCategory.SCENE, GDCoreTypes.ModuleCategory.PLAYER, GDCoreTypes.ModuleCategory.MISC]:
			for m in raw_modules:
				if m is GameModuleBase and (m as GameModuleBase).category == cat:
					ordered.append(m)

		for mod in ordered:
			mod.construct(ctx)
		for mod in ordered:
			mod.begin_play(ctx)

		_active_modules = ordered
		# 5. 重建 Tick 队列
		var all_tick: Array[GameModuleBase] = []
		all_tick.append_array(_global_modules)
		all_tick.append_array(_active_modules)
		tick_driver.rebuild(all_tick)

		# 6. 派发 GameStateChangedEvent
		GDCoreServices.get_event_bus().publish(EVENT_GAME_STATE_CHANGED, {
			"old_state_id": old_state_id,
			"new_state_id": new_state_id,
		})
		return true

	func shutdown() -> void:
		tick_driver.clear()
		for i in range(_active_modules.size() - 1, -1, -1):
			if _active_modules[i] != null:
				_active_modules[i].dispose()
		_active_modules.clear()
		for i in range(_global_modules.size() - 1, -1, -1):
			if _global_modules[i] != null:
				_global_modules[i].dispose()
		_globals_initialized = false
		current_state_id = -1
