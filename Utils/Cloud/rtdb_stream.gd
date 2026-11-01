class_name RtdbStream
extends RefCounted

## Pure-GDScript Server-Sent Events (SSE) stream client for Firebase Realtime Database.
## Parses chunked event: put / patch streams across Windows, macOS, Linux, Android, and iOS.

signal data_received(event_name: String, event_data: Dictionary)
signal put(path: String, data: Variant)
signal patch(path: String, data: Variant)
signal connected()
signal closed()
signal error_occurred(error: String)

var stream_url: String = ""
var is_active: bool = false

var _buffer: String = ""
var _current_event: String = ""
var _current_data_str: String = ""
var _thread: Thread = null
var _stop_requested: bool = false


func start(url: String, auth_token: String = "") -> void:
	close()
	stream_url = url
	if not auth_token.is_empty():
		stream_url += ("&" if stream_url.contains("?") else "?") + "auth=" + auth_token

	_stop_requested = false
	is_active = true
	_thread = Thread.new()
	_thread.start(_run_stream_thread)


func close() -> void:
	if not is_active and _thread == null:
		return
	_stop_requested = true
	is_active = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null
	closed.emit()


func is_connected_to_stream() -> bool:
	return is_active


# ── SSE CHUNK PARSER ─────────────────────────────────────────────────────

func feed_data(chunk: String) -> void:
	feed_chunk(chunk)


func feed_chunk(chunk: String) -> void:
	_buffer += chunk

	while true:
		var newline_idx := _buffer.find("\n")
		if newline_idx == -1:
			break

		var line := _buffer.substr(0, newline_idx)
		_buffer = _buffer.substr(newline_idx + 1)

		if line.ends_with("\r"):
			line = line.left(-1)

		line = line.strip_edges(false, true) # strip trailing spaces

		if line.is_empty():
			_dispatch_current_message()
		elif line.begins_with("event:"):
			_current_event = line.substr(6).strip_edges()
		elif line.begins_with("data:"):
			var data_segment := line.substr(5).strip_edges()
			if _current_data_str.is_empty():
				_current_data_str = data_segment
			else:
				_current_data_str += "\n" + data_segment
		elif line.begins_with(":"):
			# SSE comment or keep-alive heartbeat ping
			pass


func _dispatch_current_message() -> void:
	if _current_event.is_empty() and _current_data_str.is_empty():
		return

	var event := _current_event
	var raw_data := _current_data_str

	_current_event = ""
	_current_data_str = ""

	if event == "keep-alive":
		return

	if event == "cancel" or event == "auth_revoked":
		error_occurred.emit(event)
		close()
		return

	var parsed: Variant = null
	if not raw_data.is_empty() and raw_data != "null":
		parsed = JSON.parse_string(raw_data)

	var event_dict: Dictionary = {}
	if parsed is Dictionary:
		event_dict = parsed
	else:
		event_dict = {"path": "/", "data": parsed}

	data_received.emit(event, event_dict)

	var path: String = str(event_dict.get("path", "/"))
	var data: Variant = event_dict.get("data", null)

	if event == "put":
		put.emit(path, data)
	elif event == "patch":
		patch.emit(path, data)


# ── BACKGROUND STREAM THREAD ─────────────────────────────────────────────

func _run_stream_thread() -> void:
	var client := HTTPClient.new()
	var tls_opts := TLSOptions.client()

	# Parse URL host and port
	var url_without_proto := stream_url
	var is_ssl := false
	if url_without_proto.begins_with("https://"):
		is_ssl = true
		url_without_proto = url_without_proto.substr(8)
	elif url_without_proto.begins_with("http://"):
		is_ssl = false
		url_without_proto = url_without_proto.substr(7)

	var slash_pos := url_without_proto.find("/")
	var host := url_without_proto
	var path := "/"
	if slash_pos != -1:
		host = url_without_proto.substr(0, slash_pos)
		path = url_without_proto.substr(slash_pos)

	var port := 443 if is_ssl else 80
	if host.contains(":"):
		var parts := host.split(":")
		host = parts[0]
		port = int(parts[1])

	var err := client.connect_to_host(host, port, tls_opts if is_ssl else null)
	if err != OK:
		error_occurred.emit("Connection failed: %d" % err)
		return

	while not _stop_requested and (client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING):
		client.poll()
		OS.delay_msec(20)

	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		error_occurred.emit("Failed to connect to host: %s" % host)
		return

	var headers := PackedStringArray([
		"Accept: text/event-stream",
		"User-Agent: HeckleGolfSim-Godot/1.0"
	])
	err = client.request(HTTPClient.METHOD_GET, path, headers)
	if err != OK:
		error_occurred.emit("Stream request failed: %d" % err)
		return

	while not _stop_requested and client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		OS.delay_msec(20)

	if client.get_status() != HTTPClient.STATUS_BODY and client.get_status() != HTTPClient.STATUS_CONNECTED:
		error_occurred.emit("Stream request invalid status: %d" % client.get_status())
		return

	connected.emit()

	while not _stop_requested and client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.size() > 0:
			var txt := chunk.get_string_from_utf8()
			if not txt.is_empty():
				feed_chunk(txt)
		OS.delay_msec(20)

	client.close()
