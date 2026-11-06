extends SceneTree

var failures: int = 0
var checks: int = 0

class Probe extends GDGameFramework.GameModuleBase:
	var trace: Array = []
	var tag: String = ""
	var construct_action: Callable
	var begin_action: Callable
	var tick_action: Callable
	var dispose_action: Callable
	var event_count: int = 0

	func on_construct(_ctx: GDGameFramework.GameModeContext) -> void:
		trace.append("C:" + tag)
		listen("probe", _on_event)
		provide_service("probe:" + tag, self)
		if construct_action.is_valid():
			construct_action.call(self)
	func on_begin_play(_ctx: GDGameFramework.GameModeContext) -> void:
		trace.append("B:" + tag)
		if begin_action.is_valid():
			begin_action.call(self)
	func on_dispose() -> void:
		trace.append("D:" + tag)
		if dispose_action.is_valid():
			dispose_action.call(self)
	func on_update(_dt: float) -> void:
		trace.append("T:" + tag)
		if tick_action.is_valid():
			tick_action.call(self)
	func _on_event(_event: Variant) -> void:
		event_count += 1

class OwnedSystem extends GDGameFramework.BaseSystem:
	var hits: int = 0
	func on_construct(_ctx: GDGameFramework.SystemContext) -> void:
		listen("system_probe", _on_event)
		provide_service("owned_system", self)
	func _on_event(_value: Variant) -> void:
		hits += 1


class TickSystem extends GDGameFramework.BaseSystem:
	var trace: Array = []
	var tag := "owned"
	var action: Callable
	func on_update(_dt: float) -> void:
		trace.append("S:update:" + tag)
		if action.is_valid():
			action.call(self)
	func on_late_update(_dt: float) -> void:
		trace.append("S:late:" + tag)
	func on_fixed_update(_dt: float) -> void:
		trace.append("S:fixed:" + tag)

func factory(trace: Array, tag: String, category: int, id: int, options: Dictionary = {}) -> Callable:
	return func() -> GDGameFramework.GameModuleBase:
		var mod := Probe.new()
		mod.trace = trace
		mod.tag = tag
		mod.display_name = tag
		mod.category = category
		mod.module_id = id
		mod.debug_restartable = true
		mod.tick_enabled = options.get("tick_enabled", true)
		mod.construct_action = options.get("construct", Callable())
		mod.begin_action = options.get("begin", Callable())
		mod.tick_action = options.get("tick", Callable())
		mod.dispose_action = options.get("dispose", Callable())
		return mod

func _initialize() -> void:
	GDCoreServices.reset_for_tests()
	_test_order_and_identity()
	_test_tick_queue()
	_test_reentry()
	_test_fault_and_restart()
	_test_owned_cleanup()
	_test_system_ticks()
	_test_queued_operation()
	_test_configuration_queue()
	_test_shutdown_at_reentry_limit()
	_test_manual_api()
	GDCoreServices.shutdown_for_tests()
	print("GAME MODE FRAMEWORK: %s checks, %s failures" % [checks, failures])
	quit(1 if failures else 0)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _test_order_and_identity() -> void:
	var trace: Array = []
	var sm := GDGameFramework.GameStateMachine.new()
	sm.state_keys = {1: &"login", 2: &"game"}
	sm.register_global_factories([factory(trace, "gm", 2, 1), factory(trace, "gs", 0, 2)])
	sm.register_state_factories(1, [factory(trace, "misc", 2, 3), factory(trace, "scene", 0, 4), factory(trace, "player", 1, 5)])
	sm.register_state_factories(2, [])
	check(sm.switch_state(1), "first switch accepted")
	check(trace == ["C:gs", "C:gm", "B:gs", "B:gm", "C:scene", "C:player", "C:misc", "B:scene", "B:player", "B:misc"], "global/state each initialize by category in two phases")
	var first := sm._find_module(4).instance_serial
	var global_serial := sm._find_module(1).instance_serial
	trace.clear()
	sm.switch_state(2)
	check(trace == ["D:misc", "D:player", "D:scene"], "state disposal reverses actual initialization order")
	sm.switch_state(1)
	check(sm._find_module(4).instance_serial != first, "factory binding creates fresh instances on reentry")
	check(sm._find_module(1).instance_serial == global_serial, "globals survive state changes")
	var edges: Array = sm.capture_snapshot().transitions
	check(edges.size() == 2 and edges[0].last_sequence < edges[1].last_sequence, "transition sequence distinguishes multiple transitions in the same frame")
	trace.clear()
	sm.tick_driver.tick_update(0.1)
	check(trace == ["T:gs", "T:gm", "T:scene", "T:player", "T:misc"], "legacy driver forwards global then state ticks")
	trace.clear()
	sm.shutdown()
	check(trace == ["D:misc", "D:player", "D:scene", "D:gm", "D:gs"], "shutdown disposes states then globals in reverse order")

func _test_tick_queue() -> void:
	var trace: Array = []
	var sm := GDGameFramework.GameStateMachine.new()
	var result := {"accepted": false, "alive": false, "old": false, "pending": false}
	var tick := func(mod: Probe) -> void:
		result.accepted = sm.switch_state(2)
		result.alive = not mod.is_disposed
		result.old = sm.current_state_id == 1
		result.pending = sm.pending_state_id == 2
		trace.append("return:" + mod.tag)
	sm.register_global_factories([factory(trace, "global", 2, 1)])
	sm.register_state_factories(1, [factory(trace, "first", 0, 2, {"tick": tick}), factory(trace, "skip", 1, 3)])
	sm.register_state_factories(2, [])
	sm.switch_state(1)
	trace.clear()
	sm.tick_update(0.1)
	check(result.accepted and result.alive and result.old and result.pending, "tick switch queues without disposing the caller")
	check(trace == ["T:global", "T:first", "return:first", "D:skip", "D:first"], "remaining state ticks skipped before queued disposal")
	check(sm.current_state_id == 2 and sm.pending_state_id == -1, "tick queue drains after iteration")
	sm.shutdown()
	# A request from a global must still let all other globals tick.
	sm = GDGameFramework.GameStateMachine.new()
	sm.register_global_factories([factory(trace, "g1", 0, 1, {"tick": func(_m: Probe) -> void: sm.switch_state(2)}), factory(trace, "g2", 1, 2)])
	sm.register_state_factories(1, [factory(trace, "state", 0, 3)])
	sm.register_state_factories(2, [])
	sm.switch_state(1)
	trace.clear()
	sm.tick_update(0.1)
	check(trace == ["T:g1", "T:g2", "D:state"], "global tick requests do not skip remaining globals")
	sm.shutdown()

func _test_reentry() -> void:
	var trace: Array = []
	var sm := GDGameFramework.GameStateMachine.new()
	var result: Array = []
	var action := func(_mod: Probe) -> void:
		result.append(sm.switch_state(2))
		result.append(sm.switch_state(2))
		result.append(sm.switch_state(1))
		result.append(sm.pending_state_id)
	sm.register_state_factories(1, [factory(trace, "one", 0, 1, {"construct": action})])
	sm.register_state_factories(2, [])
	var events: Array = []
	sm.lifecycle_hook = func(kind: StringName, _detail: Dictionary) -> void: events.append(kind)
	sm.switch_state(1)
	check(result.slice(0, 4) == [true, false, true, 1], "same-target rejection compares queue tail rather than current state")
	check(events.count(&"state_enter_end") == 8 and events.count(&"reentry_overflow") == 1, "ninth reentrant transition is discarded")
	check(sm.pending_state_id == -1 and sm.current_state_id == 2, "overflow remains in last completed state")
	sm.shutdown()
	# Shutdown issued inside lifecycle is also deferred.
	sm = GDGameFramework.GameStateMachine.new()
	var alive := {"value": false}
	sm.register_state_factories(1, [factory(trace, "stop", 0, 1, {"construct": func(mod: Probe) -> void:
		sm.shutdown()
		alive.value = not mod.is_disposed
	})])
	sm.switch_state(1)
	check(alive.value and sm.current_state_id == -1, "lifecycle shutdown never disposes inside the caller callback")

func _test_fault_and_restart() -> void:
	var trace: Array = []
	var sm := GDGameFramework.GameStateMachine.new()
	var faults := {"count": 0}
	var fault_once := func(mod: Probe) -> void:
		if faults.count == 0:
			faults.count += 1
			mod.report_fault(&"construct", "intentional fixture fault")
	sm.register_global_factories([factory(trace, "fault", 0, 1, {"construct": fault_once}), factory(trace, "steady", 2, 2)])
	sm.register_state_factories(1, [factory(trace, "off", 0, 3, {"tick_enabled": false})])
	sm.register_state_factories(2, [])
	sm.switch_state(1)
	var faulted := sm._find_module(1)
	check(faulted.is_faulted and not faulted.is_begun_play and not trace.has("B:fault"), "construct fault skips BeginPlay")
	trace.clear()
	sm.tick_update(0.1)
	check(trace == ["T:steady"], "faulted and tick-disabled modules are not ticked")
	sm.switch_state(2)
	check(sm._find_module(1) == faulted and not sm.global_tick_driver.is_ticking(faulted), "global faults survive a state switch")
	var steady_serial := sm._find_module(2).instance_serial
	check(sm.restart_module(1) == OK, "faulted configured module can restart")
	check(faulted.is_disposed and sm._find_module(1).instance_serial != faulted.instance_serial and not sm._find_module(1).is_faulted, "restart disposes partial initialization and clears fault only on new instance")
	check(sm._find_module(2).instance_serial == steady_serial, "module restart preserves other module instances")
	trace.clear()
	sm.tick_update(0.1)
	check(trace == ["T:fault", "T:steady"], "replacement restores original tick position")
	trace.clear()
	sm.shutdown()
	check(trace == ["D:fault", "D:steady"], "restarted module disposed by new actual initialization order")

func _test_owned_cleanup() -> void:
	var trace: Array = []
	var sm := GDGameFramework.GameStateMachine.new()
	sm.register_state_factories(1, [factory(trace, "owned", 0, 1)])
	sm.switch_state(1)
	var old := sm._find_module(1) as Probe
	for _i in range(4):
		sm.restart_state()
	var current := sm._find_module(1) as Probe
	GDCoreServices.get_event_bus().publish("probe")
	check(old.event_count == 0 and current.event_count == 1, "repeated restart leaves exactly one live owned subscription")
	var replacement := RefCounted.new()
	GDCoreServices.get_locator().register_service("probe:owned", replacement)
	sm.shutdown()
	check(GDCoreServices.get_locator().resolve("probe:owned") == replacement, "disposing old service owner does not unregister a newer provider")
	GDCoreServices.get_locator().unregister_service("probe:owned")
	var owner := Probe.new()
	var system := OwnedSystem.new()
	owner.systems.add(system)
	owner.construct(GDGameFramework.GameModeContext.new())
	owner.begin_play(GDGameFramework.GameModeContext.new())
	owner.dispose()
	GDCoreServices.get_event_bus().publish("system_probe")
	check(system.hits == 0 and not GDCoreServices.get_locator().has_service("owned_system"), "systems automatically clean up their subscriptions and services")

func _test_system_ticks() -> void:
	var trace: Array = []
	var sm := GDGameFramework.GameStateMachine.new()
	var owner := Probe.new()
	owner.tag = "owner"
	owner.trace = trace
	var system := TickSystem.new()
	system.trace = trace
	owner.systems.add(system)
	sm.register_state_binding(1, [owner])
	sm.register_state_binding(2, [])
	sm.switch_state(1)
	trace.clear()
	sm.tick_update(0.1)
	sm.tick_late_update(0.1)
	sm.tick_fixed_update(0.1)
	check(trace == ["T:owner", "S:update:owned", "S:late:owned", "S:fixed:owned"], "owned systems receive update, late update and fixed update through their module")
	var second := TickSystem.new()
	second.tag = "second"
	second.trace = trace
	owner.systems.add(second)
	var alive := {"value": false}
	system.action = func(sys: TickSystem) -> void:
		sm.switch_state(2)
		alive.value = not sys.is_disposed and not owner.is_disposed
	trace.clear()
	sm.tick_update(0.1)
	check(alive.value and trace == ["T:owner", "S:update:owned", "D:owner"] and sm.current_state_id == 2, "system-triggered switch skips remaining state systems and waits for callback return")
	sm.shutdown()
	sm = GDGameFramework.GameStateMachine.new()
	owner = Probe.new()
	owner.trace = trace
	owner.tag = "fault_owner"
	system = TickSystem.new()
	system.trace = trace
	system.action = func(sys: TickSystem) -> void: sys._context.owner_module.report_fault(&"tick", "system fault")
	second = TickSystem.new()
	second.trace = trace
	second.tag = "skipped"
	owner.systems.add(system)
	owner.systems.add(second)
	sm.register_state_binding(1, [owner])
	sm.switch_state(1)
	trace.clear()
	sm.tick_update(0.1)
	sm.tick_update(0.1)
	check(trace == ["T:fault_owner", "S:update:owned"] and owner.is_faulted, "system fault stops the remaining systems and future module ticks")
	sm.shutdown()


func _test_manual_api() -> void:
	var sm := GDGameFramework.GameStateMachine.new()
	var mod := Probe.new()
	mod.tag = "manual"
	sm.register_state_binding(1, [mod])
	sm.register_state_binding(2, [])
	check(not sm.switch_state(-1) and not sm.switch_state(999), "invalid and unregistered states rejected")
	sm.switch_state(1)
	var serial := mod.instance_serial
	check(sm.capture_snapshot().modules[0].id == "manual:1:0", "manual snapshot exposes stable read-only identity")
	check(not sm.restart_state() and sm.restart_module(-1) != OK, "manual instances cannot be restarted")
	sm.switch_state(2)
	sm.switch_state(1)
	check(mod.instance_serial == serial and mod.is_begun_play and not mod.is_disposed, "manual bindings reuse same instance on reentry")
	sm.shutdown()

func _test_queued_operation() -> void:
	var trace: Array = []
	var sm := GDGameFramework.GameStateMachine.new()
	var observed := {"reason": "", "old": "", "new": "", "disposed_in_operation": false}
	var callback := func(event: Dictionary) -> void:
		observed.reason = String(event.reason)
		observed.old = String(event.old_state_key)
		observed.new = String(event.new_state_key)
	GDCoreServices.get_event_bus().subscribe(GDGameFramework.GameStateMachine.EVENT_GAME_STATE_CHANGED, callback)
	sm.state_keys = {1: &"login"}
	sm.register_state_factories(1, [factory(trace, "queued", 0, 1)])
	sm.switch_state(1)
	sm.restart_state()
	check(observed.reason == "restart" and observed.old == "login" and observed.new == "login", "restart events preserve state keys and report restart reason")
	GDCoreServices.get_event_bus().unsubscribe(GDGameFramework.GameStateMachine.EVENT_GAME_STATE_CHANGED, callback)
	var active := sm._find_module(1) as Probe
	active.tick_action = func(mod: Probe) -> void:
		sm.enqueue_operation(func() -> void:
			sm.shutdown()
			observed.disposed_in_operation = mod.is_disposed
			trace.append("operation")
		)
		trace.append("callback_return")
	trace.clear()
	sm.tick_update(0.1)
	check(trace == ["T:queued", "callback_return", "D:queued", "operation"], "apply-style operation waits for callback return before shutdown")
	check(observed.disposed_in_operation and sm.current_state_id == -1, "queued operation can synchronously shut down old machine")

func _test_configuration_queue() -> void:
	var trace: Array = []
	var sm := GDGameFramework.GameStateMachine.new()
	sm.state_keys = {1: &"login", 2: &"game"}
	var apply := func(tag: String) -> void:
		check(sm.reset_configuration(), "configuration reset is accepted at operation safe point")
		sm.state_keys = {20: &"login", 10: &"game"}
		sm.register_state_factories(20, [factory(trace, tag, 0, 1)])
		sm.register_state_factories(10, [])
		sm.enter_configuration_state(20)
	var tick := func(_mod: Probe) -> void:
		sm.enqueue_operation(apply.bind("applied_a"))
		sm.enqueue_operation(apply.bind("applied_b"))
		sm.switch_state(2)
	sm.register_state_factories(1, [factory(trace, "original", 0, 1, {"tick": tick})])
	sm.register_state_factories(2, [])
	sm.switch_state(1)
	trace.clear()
	sm.tick_update(0.1)
	check(trace == ["T:original", "D:original", "C:applied_a", "B:applied_a", "D:applied_a", "C:applied_b", "B:applied_b", "D:applied_b"], "consecutive applies both complete before subsequent state request")
	check(sm.current_state_id == 10, "pending state key remaps to new internal ID after apply")
	sm.shutdown()
	# A lifecycle reached from an apply operation is not itself a safe point.
	sm = GDGameFramework.GameStateMachine.new()
	sm.register_state_factories(1, [])
	sm.switch_state(1)
	var nested := {"alive": false, "safe": true}
	sm.enqueue_operation(func() -> void:
		sm.reset_configuration()
		sm.register_state_factories(1, [factory(trace, "nested", 0, 1, {"construct": func(mod: Probe) -> void:
			nested.safe = sm.is_operation_safe_point()
			sm.shutdown()
			nested.alive = not mod.is_disposed
		})])
		sm.enter_configuration_state(1)
	)
	check(nested.alive and not nested.safe and sm.current_state_id == -1, "shutdown in apply-triggered Construct still waits for callback return")
	# Applying again during every Construct must share the original drain budget.
	sm = GDGameFramework.GameStateMachine.new()
	var loop := {"count": 0, "overflow": 0, "apply": Callable()}
	loop.apply = func() -> void:
		loop.count += 1
		sm.reset_configuration()
		sm.register_state_factories(1, [factory(trace, "loop", 0, 1, {"construct": func(_mod: Probe) -> void:
			sm.enqueue_operation(loop.apply)
		})])
		sm.enter_configuration_state(1)
	sm.lifecycle_hook = func(kind: StringName, _detail: Dictionary) -> void:
		if kind == &"reentry_overflow":
			loop.overflow += 1
	sm.enqueue_operation(loop.apply)
	check(loop.count == 8 and loop.overflow == 1, "configuration replacement cannot reset the eight-operation reentry limit")
	sm.shutdown()
	loop.apply = Callable()

func _test_shutdown_at_reentry_limit() -> void:
	var trace: Array = []
	var sm := GDGameFramework.GameStateMachine.new()
	var loop := {"count": 0, "alive": false, "overflow": 0}
	var construct := func(mod: Probe) -> void:
		loop.count += 1
		sm.switch_state(2 if sm.current_state_id == 1 else 1)
		if loop.count == 8:
			sm.shutdown()
			loop.alive = not mod.is_disposed
	sm.register_state_factories(1, [factory(trace, "one", 0, 1, {"construct": construct})])
	sm.register_state_factories(2, [factory(trace, "two", 0, 2, {"construct": construct})])
	sm.lifecycle_hook = func(kind: StringName, _detail: Dictionary) -> void:
		if kind == &"reentry_overflow":
			loop.overflow += 1
	sm.switch_state(1)
	check(loop.count == 8 and loop.overflow == 1, "ninth transition is still rejected when shutdown is pending")
	check(loop.alive and sm.current_state_id == -1 and sm._active_modules.is_empty(), "terminal shutdown survives overflow and disposes after callback return")
	check(trace.count("D:one") + trace.count("D:two") == 8, "overflow shutdown disposes every initialized instance exactly once")
