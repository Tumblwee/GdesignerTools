@tool
class_name GDCoreServices
extends RefCounted

## 跨模块事件总线、服务定位器与撤销重做包装（对应 IEventBus / EventBus / ServiceLocator / ServiceRegistry）

class EventBus extends RefCounted:
	var _subscribers: Dictionary = {} # event_name (String) -> Array[Callable]

	func subscribe(event_name: String, callback: Callable) -> void:
		if event_name.is_empty() or not callback.is_valid():
			return
		if not _subscribers.has(event_name):
			_subscribers[event_name] = []
		var list: Array = _subscribers[event_name]
		if not list.has(callback):
			list.append(callback)

	func unsubscribe(event_name: String, callback: Callable) -> void:
		if not _subscribers.has(event_name):
			return
		var list: Array = _subscribers[event_name]
		list.erase(callback)

	func publish(event_name: String, payload: Variant = null) -> void:
		if not _subscribers.has(event_name):
			return
		var snapshot: Array = _subscribers[event_name].duplicate()
		for cb in snapshot:
			if cb is Callable and cb.is_valid():
				cb.call(payload)

	func clear() -> void:
		_subscribers.clear()


class ServiceLocator extends RefCounted:
	var _services: Dictionary = {} # service_key (String) -> Object

	func register_service(service_key: String, instance: Object) -> void:
		if service_key.is_empty() or instance == null:
			return
		_services[service_key] = instance

	func unregister_service(service_key: String) -> bool:
		return _services.erase(service_key)

	func resolve(service_key: String) -> Object:
		return _services.get(service_key, null)

	func try_resolve(service_key: String) -> Dictionary:
		if _services.has(service_key) and _services[service_key] != null:
			return {"ok": true, "service": _services[service_key]}
		return {"ok": false, "service": null}

	func has_service(service_key: String) -> bool:
		return _services.has(service_key) and _services[service_key] != null

	func clear() -> void:
		_services.clear()


## 全局 ServiceRegistry 单例访问点
static var _locator: ServiceLocator = null
static var _event_bus: EventBus = null
static var _undo_redo: UndoRedo = null

static func ensure_exists() -> void:
	if _locator == null:
		_locator = ServiceLocator.new()
	if _event_bus == null:
		_event_bus = EventBus.new()
	if not _locator.has_service("IEventBus"):
		_locator.register_service("IEventBus", _event_bus)

static func get_locator() -> ServiceLocator:
	ensure_exists()
	return _locator

static func get_event_bus() -> EventBus:
	ensure_exists()
	return _event_bus

static func get_undo_redo() -> UndoRedo:
	if _undo_redo == null:
		_undo_redo = UndoRedo.new()
	return _undo_redo

static func reset_for_tests() -> void:
	if _event_bus != null:
		_event_bus.clear()
	if _locator != null:
		_locator.clear()
	if _undo_redo != null:
		_undo_redo.clear_history()
	ensure_exists()

static func shutdown_for_tests() -> void:
	if _event_bus != null:
		_event_bus.clear()
		_event_bus = null
	if _locator != null:
		_locator.clear()
		_locator = null
	if _undo_redo != null:
		_undo_redo.free()
		_undo_redo = null
