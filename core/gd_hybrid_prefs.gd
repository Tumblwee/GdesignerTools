@tool
class_name GDHybridPrefs
extends RefCounted

## 编辑器 / 本地持久化配置存储（对应 TimiMiniGame.Core.HybridPrefs + FileStorePrefs）

const STORE_FILE_PATH := "user://gdesigner_hybrid_prefs.json"

static var _memory_store: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(STORE_FILE_PATH):
		var f := FileAccess.open(STORE_FILE_PATH, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				_memory_store = parsed

static func _flush_to_disk() -> void:
	var f := FileAccess.open(STORE_FILE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_memory_store, "\t"))
		f.close()

static func get_string(key: String, default_val: String = "") -> String:
	_ensure_loaded()
	return str(_memory_store.get(key, default_val))

static func set_string(key: String, val: String) -> void:
	_ensure_loaded()
	_memory_store[key] = val
	_flush_to_disk()

static func get_int(key: String, default_val: int = 0) -> int:
	_ensure_loaded()
	return int(_memory_store.get(key, default_val))

static func set_int(key: String, val: int) -> void:
	_ensure_loaded()
	_memory_store[key] = val
	_flush_to_disk()

static func get_float(key: String, default_val: float = 0.0) -> float:
	_ensure_loaded()
	return float(_memory_store.get(key, default_val))

static func set_float(key: String, val: float) -> void:
	_ensure_loaded()
	_memory_store[key] = val
	_flush_to_disk()

static func get_bool(key: String, default_val: bool = false) -> bool:
	_ensure_loaded()
	return bool(_memory_store.get(key, default_val))

static func set_bool(key: String, val: bool) -> void:
	_ensure_loaded()
	_memory_store[key] = val
	_flush_to_disk()

static func has_key(key: String) -> bool:
	_ensure_loaded()
	return _memory_store.has(key)

static func delete_key(key: String) -> void:
	_ensure_loaded()
	if _memory_store.erase(key):
		_flush_to_disk()
