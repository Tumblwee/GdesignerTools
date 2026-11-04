@tool
class_name GDGameLogger
extends RefCounted

## 统一日志门面（对应 TimiMiniGame.Core.GameLogger）
## 支持 LogVerbose / LogDebug / LogInfo / FlowLog / LogWarning / LogErrorP / LogErrorD / Assert

enum LogLevel {
	VERBOSE = 0,
	DEBUG = 1,
	INFO = 2,
	WARNING = 3,
	ERROR_P = 4,
	ERROR_D = 5,
}

static var enabled_verbose: bool = false
static var capture_history: bool = true
static var max_history: int = 500
static var _history: Array[Dictionary] = []

static func get_history() -> Array[Dictionary]:
	return _history

static func clear_history() -> void:
	_history.clear()

static func _record(level: int, tag: String, msg: String) -> void:
	if not capture_history:
		return
	if _history.size() >= max_history:
		_history.pop_front()
	_history.append({
		"level": level,
		"tag": tag,
		"message": msg,
		"time_ms": Time.get_ticks_msec(),
	})

static func log_verbose(msg: String) -> void:
	_record(LogLevel.VERBOSE, "VERBOSE", msg)
	if enabled_verbose:
		print("[VERBOSE] ", msg)

static func log_debug(msg: String) -> void:
	_record(LogLevel.DEBUG, "DEBUG", msg)
	if enabled_verbose:
		print("[DEBUG] ", msg)

static func log_info(msg: String) -> void:
	_record(LogLevel.INFO, "INFO", msg)
	print("[INFO] ", msg)

static func flow_log(msg: String) -> void:
	_record(LogLevel.INFO, "FLOW", msg)
	print("[FLOW] ", msg)

static func log_warning(msg: String) -> void:
	_record(LogLevel.WARNING, "WARN", msg)
	push_warning(msg)

static func log_error_p(msg: String) -> void:
	_record(LogLevel.ERROR_P, "ERR_P", msg)
	push_error("[ProgramError] " + msg)

static func log_error_d(msg: String) -> void:
	_record(LogLevel.ERROR_D, "ERR_D", msg)
	push_error("[DataError] " + msg)

static func log_custom_exception(err_msg: String, prefix: String = "") -> void:
	var full := prefix + err_msg
	_record(LogLevel.ERROR_P, "EXCEPTION", full)
	push_error(full)

static func assert_true(cond: bool, msg: String = "Assertion failed") -> bool:
	if not cond:
		log_error_p("ASSERT: " + msg)
	return cond
