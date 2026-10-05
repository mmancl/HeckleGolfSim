class_name MJPEGStreamReader
extends Node

## High-performance, non-blocking MJPEG multipart stream reader for IP cameras,
## DroidCam, and IP Webcam apps over local Wi-Fi.
## Bypasses sequential HTTP snapshot requests to deliver continuous 30-60 FPS.

signal frame_received(image: Image, timestamp_usec: int)
signal connection_status_changed(is_connected: bool, message: String)

var _http_client: HTTPClient = null
var _stream_url: String = ""
var _is_active: bool = false
var _buffer: PackedByteArray = PackedByteArray()
var _reconnect_timer: float = 0.0

const MAX_BUFFER_SIZE: int = 4 * 1024 * 1024  # 4 MB max buffer
const RECONNECT_DELAY: float = 2.0
const JPEG_SOI: int = 0xD8  # 0xFF 0xD8
const JPEG_EOI: int = 0xD9  # 0xFF 0xD9


func _ready() -> void:
	set_process(false)


func start_stream(url_str: String) -> void:
	stop_stream()
	_stream_url = url_str.strip_edges()
	if _stream_url.is_empty():
		connection_status_changed.emit(false, "Empty stream URL")
		return
	
	_is_active = true
	_buffer.clear()
	_reconnect_timer = 0.0
	set_process(true)
	_initiate_connection()


func stop_stream() -> void:
	_is_active = false
	set_process(false)
	if _http_client != null:
		_http_client.close()
		_http_client = null
	_buffer.clear()
	connection_status_changed.emit(false, "Disconnected")


func is_active() -> bool:
	return _is_active


func _initiate_connection() -> void:
	if not _is_active:
		return
	
	if _http_client != null:
		_http_client.close()
		_http_client = null
	
	_buffer.clear()
	_http_client = HTTPClient.new()
	
	var parsed = _parse_url(_stream_url)
	if parsed.host.is_empty():
		connection_status_changed.emit(false, "Invalid host in URL: %s" % _stream_url)
		return
	
	connection_status_changed.emit(false, "Connecting to %s:%d..." % [parsed.host, parsed.port])
	var err = _http_client.connect_to_host(parsed.host, parsed.port)
	if err != OK:
		connection_status_changed.emit(false, "Connection error: %d" % err)
		_reconnect_timer = RECONNECT_DELAY


func _process(delta: float) -> void:
	if not _is_active:
		return
	
	if _reconnect_timer > 0.0:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_initiate_connection()
		return
	
	if _http_client == null:
		_reconnect_timer = RECONNECT_DELAY
		return
	
	_http_client.poll()
	var status = _http_client.get_status()
	
	match status:
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE:
			connection_status_changed.emit(false, "Connection dropped (Status %d)" % status)
			_reconnect_timer = RECONNECT_DELAY
		
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
			pass
		
		HTTPClient.STATUS_CONNECTED:
			# Send request for stream
			var parsed = _parse_url(_stream_url)
			var headers = PackedStringArray([
				"User-Agent: HeckleGolfSim/1.0",
				"Accept: multipart/x-mixed-replace, image/jpeg, */*",
				"Connection: keep-alive"
			])
			var err = _http_client.request(HTTPClient.METHOD_GET, parsed.path, headers)
			if err != OK:
				connection_status_changed.emit(false, "Request failed: %d" % err)
				_reconnect_timer = RECONNECT_DELAY
		
		HTTPClient.STATUS_REQUESTING:
			pass
		
		HTTPClient.STATUS_BODY:
			connection_status_changed.emit(true, "Streaming")
			var chunk = _http_client.read_response_body_chunk()
			if chunk.size() > 0:
				_buffer.append_array(chunk)
				_extract_and_dispatch_frames()
				
				# Prevent runaway memory if stream is corrupt
				if _buffer.size() > MAX_BUFFER_SIZE:
					_buffer.clear()
		
		_:
			pass


func _extract_and_dispatch_frames() -> void:
	var buf_len = _buffer.size()
	if buf_len < 4:
		return
	
	var search_idx: int = 0
	while search_idx < buf_len - 1:
		# Search for JPEG Start of Image (0xFF, 0xD8)
		var soi_idx: int = -1
		for i in range(search_idx, buf_len - 1):
			if _buffer[i] == 0xFF and _buffer[i + 1] == JPEG_SOI:
				soi_idx = i
				break
		
		if soi_idx == -1:
			# No SOI found; discard searched prefix
			if buf_len > 1024:
				_buffer = _buffer.slice(buf_len - 1)
			break
		
		# Search for JPEG End of Image (0xFF, 0xD9) after SOI
		var eoi_idx: int = -1
		for j in range(soi_idx + 2, buf_len - 1):
			if _buffer[j] == 0xFF and _buffer[j + 1] == JPEG_EOI:
				eoi_idx = j + 2  # Include the 0xD9 byte
				break
		
		if eoi_idx == -1:
			# Incomplete frame; keep from soi_idx onwards and wait for next chunk
			if soi_idx > 0:
				_buffer = _buffer.slice(soi_idx)
			break
		
		# Complete JPEG found
		var jpeg_bytes = _buffer.slice(soi_idx, eoi_idx)
		var capture_time_usec = Time.get_ticks_usec()
		
		var img = Image.new()
		var err = img.load_jpg_from_buffer(jpeg_bytes)
		if err == OK and not img.is_empty():
			frame_received.emit(img, capture_time_usec)
		
		# Advance buffer past this frame
		_buffer = _buffer.slice(eoi_idx)
		buf_len = _buffer.size()
		search_idx = 0


func _parse_url(raw_url: String) -> Dictionary:
	var clean = raw_url.strip_edges()
	for prefix in ["https://", "http://"]:
		if clean.begins_with(prefix):
			clean = clean.substr(prefix.length())
			break
	
	var host_part = clean
	var path_part = "/video"
	var slash_pos = clean.find("/")
	if slash_pos != -1:
		host_part = clean.substr(0, slash_pos)
		path_part = clean.substr(slash_pos)
	
	var port = 8080
	var colon_pos = host_part.find(":")
	if colon_pos != -1:
		var port_str = host_part.substr(colon_pos + 1)
		host_part = host_part.substr(0, colon_pos)
		if port_str.is_valid_int():
			port = port_str.to_int()
	
	# Common default paths
	if path_part.is_empty() or path_part == "/":
		path_part = "/mjpegfeed" if port == 4747 else "/video"
	elif path_part.ends_with("/shot.jpg") or path_part.ends_with("/frame.jpg"):
		# Translate snapshot URL to video stream URL
		path_part = path_part.get_base_dir() + ("/mjpegfeed" if port == 4747 else "/video")
	
	return {
		"host": host_part,
		"port": port,
		"path": path_part
	}
