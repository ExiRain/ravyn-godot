class_name ActionLog
extends RefCounted

# What she DID, sent to the PC so it can be counted afterwards.
#
# Nobody can watch the avatar for a whole stream, so every action — a blink,
# a look, an ear perk, an expression, the start and end of a line — is one
# small record. main.gd sends them down the WebSocket it already has open to
# the PC, which files them in logs/godot/ next to its own log and the
# notebook's (ravyn-lynx-p/services/godot_log.py). Read them back with
# ravyn-lynx-p/tools/godot_stats.py.
#
# Any script calls ActionLog.add("blink") or ActionLog.add("look", {...}).
# Records wait here until the socket is open, so nothing is lost while the
# PC restarts; past MAX_PENDING the oldest go, and the next batch says how
# many. Actions only, never per-frame values: a log line per frame would be
# 60 a second of nothing.

const MAX_PENDING     := 2000
const MAX_PER_MESSAGE := 100

static var _pending: Array = []
static var _dropped := 0


static func add(kind: String, data: Dictionary = {}) -> void:
	if _pending.size() >= MAX_PENDING:
		_pending.pop_front()
		_dropped += 1
	var record := {"t": Time.get_unix_time_from_system(), "kind": kind}
	record.merge(data)
	_pending.append(record)


# Called by main.gd every frame while the socket is open.
static func flush(socket: WebSocketPeer) -> void:
	if _pending.is_empty():
		return
	if _dropped > 0:
		_pending.push_front({"t": Time.get_unix_time_from_system(),
							 "kind": "log_dropped", "count": _dropped})
		_dropped = 0
	var count: int = min(_pending.size(), MAX_PER_MESSAGE)
	var batch := _pending.slice(0, count)
	if socket.send_text("LOG:" + JSON.stringify(batch)) == OK:
		_pending = _pending.slice(count)
