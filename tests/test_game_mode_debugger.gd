extends SceneTree

var passed := 0
var failed := 0

class RecordingLink extends GDGameModeLink:
	var sent: Array[Dictionary] = []
	func send(kind: String, payload: Dictionary) -> void:
		sent.append({"kind": kind, "payload": payload.duplicate(true)})


class ProtocolHost extends Node:
	var process_token := "protocol-host"
	var generation := 1
	var config_path := "res://protocol.tres"
	var config_digest := "initial"
	var events: Array[Dictionary] = []
	var executed: Array[String] = []

	func record_event(_kind: String, _data: Dictionary) -> void:
		pass

	func capture_snapshot() -> Dictionary:
		return {"generation": generation}

	func execute_debug_command(kind: String, _args: Dictionary) -> Dictionary:
		executed.append(kind)
		if kind == "change_generation":
			generation += 1
			config_digest = "changed"
		return {"ok": true, "code": "ok", "applied": kind == "change_generation"}


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(message)


func _run() -> void:
	var first := GDGameModeSession.new()
	first.session_id = 1
	var transport := RecordingLink.new()
	first.bind_transport(transport)
	check(first.status_text() == "未连接" and not first.can_command(), "new sessions are disconnected")
	first.start()
	check(transport.sent.size() == 1 and transport.sent[0].kind == "hello", "started session initiates handshake")
	check(not first.can_command(), "commands are disabled before welcome")
	first.poll_timeout(first._last_hello_usec + GDGameModeSession.HELLO_INTERVAL_USEC)
	check(transport.sent.size() == 2 and transport.sent.back().kind == "hello", "handshake is retried when runtime capture starts later")
	var welcome := {"protocol": 1, "process_token": "process-one", "generation": 1, "project_path": first.local_project_path, "editor_runtime": true, "config_path": "res://sample.tres", "config_digest": "abc"}
	transport.received.emit("welcome", welcome)
	first.poll_timeout(first._last_hello_usec + GDGameModeSession.HELLO_INTERVAL_USEC)
	check(transport.sent.size() == 2, "successful handshake stops hello retries")
	check(first.can_command() and first.can_apply(), "local editor runtime accepts commands and apply")
	transport.received.emit("snapshot", {"current_state_key": "login", "modules": [{"id": 1}]})
	var incoming: Array = []
	for seq in range(1, 552):
		incoming.append({"seq": seq, "kind": "module_construct", "generation": 1})
	transport.received.emit("events", {"events": incoming})
	check(first.events.size() == 500 and first.events[0].seq == 52, "timeline retains most recent 500 events")
	transport.received.emit("events", {"events": incoming})
	check(first.events.size() == 500 and first.events.back().seq == 551, "timeline deduplicates full replay by sequence")

	var second := GDGameModeSession.new()
	second.session_id = 2
	second.bind_transport(RecordingLink.new())
	second.start()
	var other_welcome := welcome.duplicate(true)
	other_welcome.process_token = "process-two"
	second.receive("welcome", other_welcome)
	second.receive("snapshot", {"current_state_key": "game"})
	check(first.snapshot.current_state_key == "login" and second.snapshot.current_state_key == "game" and second.events.is_empty(), "parallel sessions keep snapshots and timeline separate")

	first.set_paused(true)
	check(first.status_text() == "断点暂停" and first.send_command("restart_state").is_empty(), "breakpoints disable mutation commands")
	first.set_paused(false)
	var request := first.send_command("restart_state")
	check(not request.is_empty() and not first.can_command(), "one in-flight command locks controls")
	var sent: Dictionary = transport.sent.back().payload
	check(sent.process_token == "process-one" and sent.generation == 1 and sent.kind == "restart_state", "commands carry process and generation identity")
	first.receive("command_result", {"request_id": "unrelated", "ok": true})
	check(not first.pending_request.is_empty(), "unrelated receipt does not unlock controls")
	first.poll_timeout(int(first.pending_request.sent_usec) + GDGameModeSession.COMMAND_TIMEOUT_USEC)
	check(first.timed_out and not first.can_command() and transport.sent.size() == 3 and first.status_text().contains("无回执"), "timeout displays no receipt without resending or unlocking")
	first.receive("command_result", {"request_id": request, "ok": true, "code": "ok"})
	check(first.can_command() and not first.timed_out and first.last_result.ok, "late matching receipt unlocks controls")

	first.welcome.editor_runtime = false
	check(first.can_command() and not first.can_apply() and first.send_command("apply_config").is_empty(), "exported games support control but reject editor apply")
	first.welcome.editor_runtime = true
	first.welcome.project_path = "D:/a-different-project"
	check(not first.can_apply(), "other projects cannot receive config apply")
	first.welcome.protocol = 99
	check(first.status_text() == "协议不兼容" and not first.can_command(), "incompatible protocol is read-only")
	first.receive("snapshot", {"current_state_key": "still-readable"})
	check(first.snapshot.current_state_key == "still-readable", "incompatible sessions retain monitor data")
	first.stop()
	check(first.status_text() == "已断开" and first.snapshot.current_state_key == "still-readable" and first.events.size() == 500, "disconnect retains final snapshot and events")
	first.start()
	first.receive("welcome", welcome)
	check(first.events.size() == 500 and first.can_command(), "reconnecting same process preserves deduplicated history")
	first.receive("welcome", other_welcome)
	check(first.events.is_empty() and first.snapshot.is_empty(), "new process token clears previous process data")
	var timed_request := first.send_command("restart_state")
	check(not timed_request.is_empty(), "new process accepts a command")
	first.poll_timeout(int(first.pending_request.sent_usec) + GDGameModeSession.COMMAND_TIMEOUT_USEC)
	first.receive("welcome", welcome)
	check(not first.timed_out and first.pending_request.is_empty() and first.status_text() == "已连接", "replacement runtime clears a previous runtime's timeout status")
	_test_malformed_monitor_payloads(first)
	_test_command_identity_order()
	first.bind_transport(null)
	second.bind_transport(null)
	print("GameMode debugger: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _test_malformed_monitor_payloads(session: GDGameModeSession) -> void:
	session.receive("snapshot", {"current_state_key": "before", "states": [], "modules": []})
	session.receive("events", {"events": [{"seq": 1, "kind": "before"}]})
	var original_welcome := session.welcome.duplicate(true)
	for invalid: Dictionary in [
		{"protocol": [], "process_token": "bad", "generation": 1},
		{"protocol": 1, "process_token": [], "generation": 1},
		{"protocol": 1, "process_token": "bad", "generation": {}},
	]:
		session.receive("welcome", invalid)
	check(session.welcome == original_welcome, "malformed welcome does not replace a valid runtime identity")
	session.receive("snapshot", {"snapshot": 12})
	session.receive("snapshot", {"states": "invalid collection"})
	session.receive("snapshot", {"modules": [42]})
	check(session.snapshot.get("current_state_key") == "before", "malformed snapshot envelopes and collections preserve the last valid snapshot")
	session.receive("events", {"events": 12})
	session.receive("events", {"events": [null, {"seq": []}, {"seq": "2"}]})
	check(session.events.size() == 1 and session.events[0].seq == 1, "malformed event arrays and sequences are ignored")
	session.receive("snapshot", {"snapshot": {"current_state_key": "after"}, "events": [{"seq": 2, "kind": "after"}]})
	check(session.snapshot.current_state_key == "after" and session.events.back().seq == 2, "valid monitor data still arrives after malformed payloads")


func _test_command_identity_order() -> void:
	var host := ProtocolHost.new()
	var pair := GDGameModeLoopbackLink.create_pair()
	var protocol := GDGameModeProtocol.new(host, pair[0])
	var session := GDGameModeSession.new()
	session.bind_transport(pair[1])
	session.start()
	var results: Array[Dictionary] = []
	var on_completed := func(result: Dictionary) -> void:
		results.append(result)
		if results.size() == 1:
			session.send_command("follow_up")
	session.command_completed.connect(on_completed)
	session.send_command("change_generation")
	protocol.process_commands()
	protocol.process_commands()
	check(host.executed == ["change_generation", "follow_up"] and results.size() == 2 and results[1].ok, "completion callbacks see the new generation before sending the next command")
	session.command_completed.disconnect(on_completed)
	var malformed := {"request_id": "malformed", "process_token": host.process_token, "generation": [], "kind": "follow_up", "args": {}}
	pair[1].send("command", malformed)
	protocol.process_commands()
	check(pair[0].sent.back().payload.code == "invalid_request" and host.executed.size() == 2, "malformed command identity is rejected without executing business code")
	pair[1].send("hello", {"protocol": []})
	malformed.generation = host.generation
	pair[1].send("command", malformed)
	protocol.process_commands()
	check(pair[0].sent.back().payload.code == "protocol_mismatch" and host.executed.size() == 2, "malformed handshake versions cannot enable commands")
	protocol._editor_runtime = false
	pair[1].send("hello", {"protocol": 1})
	check(not session.can_apply(), "a non-editor runtime advertises config apply as unavailable")
	pair[1].send("command", {"request_id": "exported-apply", "process_token": host.process_token,
		"generation": host.generation, "kind": "apply_config", "args": {"path": "res://config.tres"}})
	protocol.process_commands()
	check(pair[0].sent.back().payload.code == "editor_runtime_required" and host.executed.size() == 2, "runtime transport rejects config apply even when the editor-side guard is bypassed")
	protocol.close()
	session.bind_transport(null)
	host.free()
