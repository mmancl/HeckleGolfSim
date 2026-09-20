class_name InAppVideoPlayer
extends VBoxContainer

# InAppVideoPlayer
# Provides video tutorial playback for golf swing flaw recommendations.
# On Windows Desktop: Embeds a borderless Chromium/Edge player directly into Godot's HWND window.
# On Mobile / Non-Windows: Loads the high-resolution YouTube thumbnail with play overlay,
# providing direct one-tap opening in the YouTube App / mobile browser and clipboard link copying.

var video_url: String = ""
var video_title: String = ""
var drill_name: String = ""
var target_metric: String = ""
var is_mobile_view: bool = false

var _player_pid: int = -1
var _video_frame: PanelContainer = null
var _thumbnail_rect: TextureRect = null
var _status_lbl: Label = null
var _stop_btn: Button = null
var _play_btn: Button = null
var _browser_btn: Button = null
var _copy_btn: Button = null
var _http_thumb: HTTPRequest = null

static var active_players: Array = []

static func stop_all_players() -> void:
	print("[InAppVideoPlayer] Stopping all active in-app video players (count: %d)..." % active_players.size())
	for p in active_players.duplicate():
		if is_instance_valid(p) and p.has_method("_stop_in_app_player"):
			p._stop_in_app_player()
	active_players.clear()

var _is_playing: bool = false
var _check_timer: Timer = null

var _udp: PacketPeerUDP = null
var _target_udp_port: int = 0
var _browser_pid: int = -1
var _last_sent_pos: Vector2 = Vector2(-9999, -9999)
var _last_sent_size: Vector2 = Vector2(-9999, -9999)
var _last_sent_vis: bool = true
var _heartbeat_timer: float = 0.0


static func extract_youtube_id(target: String) -> String:
	var s = target.strip_edges()
	if s.contains("youtube.com") or s.contains("youtu.be"):
		if s.contains("embed/"):
			var parts = s.split("embed/")[1].split("?")[0].split("&")[0]
			return parts
		elif s.contains("v="):
			var parts = s.split("v=")[1].split("&")[0].split("#")[0]
			return parts
		elif s.contains("youtu.be/"):
			var parts = s.split("youtu.be/")[1].split("?")[0].split("&")[0]
			return parts
	return s


static func is_desktop_windows() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("mobile")


func setup(url: String, title: String = "", drill: String = "", metric: String = "", is_mob: bool = false) -> void:
	video_url = url
	video_title = title
	drill_name = drill
	target_metric = metric
	is_mobile_view = is_mob or OS.has_feature("mobile") or (OS.get_name() in ["Android", "iOS"])


func _ready() -> void:
	if not active_players.has(self):
		active_players.append(self)
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_process(true)

	_build_ui()
	_fetch_youtube_thumbnail()

	# Auto-start in-app playback after UI layout completes if on desktop Windows
	call_deferred("_start_in_app_player")


func _exit_tree() -> void:
	_stop_in_app_player()
	active_players.erase(self)
	if _http_thumb != null and is_instance_valid(_http_thumb):
		_http_thumb.queue_free()
		_http_thumb = null


func _process(delta: float) -> void:
	if not _is_playing or _player_pid <= 0 or _video_frame == null:
		return

	# Discover Python's UDP port & Browser PID if not yet connected
	if _target_udp_port <= 0:
		var temp_dir = OS.get_environment("TEMP")
		var port_file = temp_dir + "/heckle_yt_port_%d.txt" % _player_pid
		var latest_file = temp_dir + "/heckle_yt_ipc_latest.txt"
		var target_file = port_file if FileAccess.file_exists(port_file) else (latest_file if FileAccess.file_exists(latest_file) else "")

		if target_file != "":
			var f = FileAccess.open(target_file, FileAccess.READ)
			if f != null:
				var lines = f.get_as_text().split("\n")
				for line in lines:
					var trimmed = line.strip_edges()
					if trimmed.begins_with("PORT:"):
						_target_udp_port = trimmed.substr(5).to_int()
					elif trimmed.begins_with("PYTHON_PID:"):
						var parsed_py_pid = trimmed.substr(11).to_int()
						if parsed_py_pid > 0:
							_player_pid = parsed_py_pid
					elif trimmed.begins_with("BROWSER_PID:"):
						_browser_pid = trimmed.substr(12).to_int()

				if _target_udp_port > 0:
					_udp = PacketPeerUDP.new()
					_udp.set_dest_address("127.0.0.1", _target_udp_port)
					print("[InAppVideoPlayer] Connected to player UDP port: %d (PyPID: %d, BrowserPID: %d)" % [_target_udp_port, _player_pid, _browser_pid])

	if _udp == null or _target_udp_port <= 0:
		return

	var cur_win: Window = get_window()
	var win_id: int = cur_win.get_window_id() if cur_win != null else DisplayServer.MAIN_WINDOW_ID
	var win_size: Vector2i = DisplayServer.window_get_size(win_id)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var scale_x: float = float(win_size.x) / max(vp_size.x, 1.0)
	var scale_y: float = float(win_size.y) / max(vp_size.y, 1.0)

	var g_pos: Vector2 = _video_frame.get_global_position()
	var f_size: Vector2 = _video_frame.size
	var is_vis: bool = is_visible_in_tree() and _video_frame.is_visible_in_tree()

	_heartbeat_timer += delta
	var pos_changed = (g_pos != _last_sent_pos or f_size != _last_sent_size or is_vis != _last_sent_vis)
	
	# Send on movement/resize or as periodic heartbeat every 0.1s so Python watchdog stays alive
	if pos_changed or _heartbeat_timer >= 0.1:
		_heartbeat_timer = 0.0
		_last_sent_pos = g_pos
		_last_sent_size = f_size
		_last_sent_vis = is_vis

		var cx: int = int(g_pos.x * scale_x)
		var cy: int = int(g_pos.y * scale_y)
		var cw: int = int(max(f_size.x * scale_x, 320.0))
		var ch: int = int(max(f_size.y * scale_y, 180.0))

		var pkt = "POS %d %d %d %d %d\n" % [cx, cy, cw, ch, 1 if is_vis else 0]
		_udp.put_packet(pkt.to_utf8_buffer())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_UNPARENTED:
		if not is_visible_in_tree() or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_UNPARENTED:
			_stop_in_app_player()


func _fetch_youtube_thumbnail() -> void:
	if video_url == "":
		return
	var yt_id = extract_youtube_id(video_url)
	if yt_id == "":
		return

	if _http_thumb != null and is_instance_valid(_http_thumb):
		_http_thumb.queue_free()

	_http_thumb = HTTPRequest.new()
	_http_thumb.name = "YouTubeThumbHTTPRequest"
	add_child(_http_thumb)
	_http_thumb.request_completed.connect(_on_thumbnail_request_completed)
	var thumb_url = "https://img.youtube.com/vi/%s/hqdefault.jpg" % yt_id
	var err = _http_thumb.request(thumb_url)
	if err != OK:
		print("[InAppVideoPlayer] Failed to initiate thumbnail request for ID: ", yt_id)


func _on_thumbnail_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and body.size() > 0:
		var img = Image.new()
		var err = img.load_jpg_from_buffer(body)
		if err == OK:
			var tex = ImageTexture.create_from_image(img)
			if _thumbnail_rect != null and is_instance_valid(_thumbnail_rect):
				_thumbnail_rect.texture = tex
				_thumbnail_rect.visible = true
	if _http_thumb != null and is_instance_valid(_http_thumb):
		_http_thumb.queue_free()
		_http_thumb = null


func _build_ui() -> void:
	var on_desktop_win = is_desktop_windows()

	# ── 1. Video Info Header Panel ─────────────────────────────────────────────
	var header_panel = PanelContainer.new()
	var h_style = StyleBoxFlat.new()
	h_style.bg_color = Color(0.12, 0.07, 0.07, 0.95)
	h_style.corner_radius_top_left = 8
	h_style.corner_radius_top_right = 8
	h_style.corner_radius_bottom_left = 8
	h_style.corner_radius_bottom_right = 8
	h_style.border_width_left = 4
	h_style.border_color = Color(0.95, 0.30, 0.30, 0.95)
	h_style.content_margin_left = 14
	h_style.content_margin_top = 12
	h_style.content_margin_right = 14
	h_style.content_margin_bottom = 12
	header_panel.add_theme_stylebox_override("panel", h_style)

	var h_vbox = VBoxContainer.new()
	h_vbox.add_theme_constant_override("separation", 6)

	var title_lbl = Label.new()
	title_lbl.text = "🎬 " + (video_title if video_title != "" else "HackMotion Video Drill Tutorial")
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", 18 if is_mobile_view else 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.70, 0.70))
	h_vbox.add_child(title_lbl)

	if drill_name != "":
		var drill_lbl = Label.new()
		drill_lbl.text = "🎯 Recommended Drill: " + drill_name
		drill_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		drill_lbl.add_theme_font_size_override("font_size", 14)
		drill_lbl.add_theme_color_override("font_color", Color(0.90, 0.90, 1.0))
		h_vbox.add_child(drill_lbl)

	if target_metric != "":
		var metric_lbl = Label.new()
		metric_lbl.text = "📊 Target Metric: " + target_metric
		metric_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		metric_lbl.add_theme_font_size_override("font_size", 13)
		metric_lbl.add_theme_color_override("font_color", Color(0.60, 0.95, 0.75))
		h_vbox.add_child(metric_lbl)

	header_panel.add_child(h_vbox)
	add_child(header_panel)

	# ── 2. Embedded Video / Thumbnail Preview Viewport Container ─────────────────
	_video_frame = PanelContainer.new()
	_video_frame.name = "VideoPlaceholderFrame"
	_video_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_video_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_video_frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_video_frame.gui_input.connect(_on_thumbnail_gui_input)

	var min_h = 220.0 if is_mobile_view else 340.0
	_video_frame.custom_minimum_size = Vector2(0, min_h)

	var frame_style = StyleBoxFlat.new()
	frame_style.bg_color = Color(0.04, 0.04, 0.06, 1.0)
	frame_style.border_width_left = 2
	frame_style.border_width_top = 2
	frame_style.border_width_right = 2
	frame_style.border_width_bottom = 2
	frame_style.border_color = Color(0.40, 0.15, 0.15, 0.8)
	frame_style.corner_radius_top_left = 8
	frame_style.corner_radius_top_right = 8
	frame_style.corner_radius_bottom_left = 8
	frame_style.corner_radius_bottom_right = 8
	_video_frame.add_theme_stylebox_override("panel", frame_style)

	# Thumbnail background image (TextureRect)
	_thumbnail_rect = TextureRect.new()
	_thumbnail_rect.name = "YouTubeThumbnail"
	_thumbnail_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_thumbnail_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumbnail_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumbnail_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumbnail_rect.visible = false
	_video_frame.add_child(_thumbnail_rect)

	# Dark scrim overlay so play badge & text stand out cleanly
	var scrim = ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.0, 0.0, 0.0, 0.42)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_frame.add_child(scrim)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var msg_vbox = VBoxContainer.new()
	msg_vbox.add_theme_constant_override("separation", 10)
	msg_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	msg_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Large YouTube Play Badge Icon
	var play_icon_panel = PanelContainer.new()
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = Color(0.90, 0.15, 0.15, 0.95)
	icon_style.corner_radius_top_left = 18
	icon_style.corner_radius_top_right = 18
	icon_style.corner_radius_bottom_left = 18
	icon_style.corner_radius_bottom_right = 18
	icon_style.content_margin_left = 22
	icon_style.content_margin_right = 22
	icon_style.content_margin_top = 10
	icon_style.content_margin_bottom = 10
	play_icon_panel.add_theme_stylebox_override("panel", icon_style)
	play_icon_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var play_icon_lbl = Label.new()
	play_icon_lbl.text = "▶  WATCH VIDEO"
	play_icon_lbl.add_theme_font_size_override("font_size", 16 if is_mobile_view else 18)
	play_icon_lbl.add_theme_color_override("font_color", Color.WHITE)
	play_icon_panel.add_child(play_icon_lbl)
	msg_vbox.add_child(play_icon_panel)

	_status_lbl = Label.new()
	_status_lbl.text = "🎬 Tap preview or button below to watch on YouTube." if not on_desktop_win else "▶ Loading In-App Video Player..."
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 15 if is_mobile_view else 16)
	_status_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_vbox.add_child(_status_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "Opens video drill tutorial directly in YouTube." if not on_desktop_win else "Video embeds seamlessly in Heckle Golf Sim."
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.82))
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_vbox.add_child(sub_lbl)

	center.add_child(msg_vbox)
	_video_frame.add_child(center)
	add_child(_video_frame)

	# ── 3. Player Control Toolbar ─────────────────────────────────────────────
	var bar_panel = PanelContainer.new()
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.08, 0.08, 0.10, 0.9)
	bar_style.corner_radius_top_left = 6
	bar_style.corner_radius_top_right = 6
	bar_style.corner_radius_bottom_left = 6
	bar_style.corner_radius_bottom_right = 6
	bar_style.content_margin_left = 12
	bar_style.content_margin_top = 8
	bar_style.content_margin_right = 12
	bar_style.content_margin_bottom = 8
	bar_panel.add_theme_stylebox_override("panel", bar_style)

	var bar_hflow = HFlowContainer.new()
	bar_hflow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_hflow.add_theme_constant_override("h_separation", 10)
	bar_hflow.add_theme_constant_override("v_separation", 8)

	if not on_desktop_win or is_mobile_view:
		# Mobile-optimized primary touch buttons
		var mob_watch_btn = Button.new()
		mob_watch_btn.text = "▶ Open in YouTube App"
		mob_watch_btn.custom_minimum_size = Vector2(210, 52)
		mob_watch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_btn_style(mob_watch_btn, Color(0.85, 0.16, 0.16))
		mob_watch_btn.pressed.connect(_on_open_browser_pressed)
		bar_hflow.add_child(mob_watch_btn)

		_copy_btn = Button.new()
		_copy_btn.text = "📋 Copy Video Link"
		_copy_btn.custom_minimum_size = Vector2(170, 52)
		_copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_btn_style(_copy_btn, Color(0.20, 0.28, 0.38))
		_copy_btn.pressed.connect(_on_copy_link_pressed.bind(_copy_btn))
		bar_hflow.add_child(_copy_btn)
	else:
		# Desktop Windows control buttons
		_browser_btn = Button.new()
		_browser_btn.text = "↗ Open in External Browser"
		_browser_btn.custom_minimum_size = Vector2(190, 42)
		_apply_btn_style(_browser_btn, Color(0.25, 0.32, 0.42))
		_browser_btn.pressed.connect(_on_open_browser_pressed)
		bar_hflow.add_child(_browser_btn)

		_copy_btn = Button.new()
		_copy_btn.text = "📋 Copy Link"
		_copy_btn.custom_minimum_size = Vector2(130, 42)
		_apply_btn_style(_copy_btn, Color(0.20, 0.28, 0.38))
		_copy_btn.pressed.connect(_on_copy_link_pressed.bind(_copy_btn))
		bar_hflow.add_child(_copy_btn)

		_play_btn = Button.new()
		_play_btn.text = "🔄 Reload Player"
		_play_btn.custom_minimum_size = Vector2(140, 42)
		_apply_btn_style(_play_btn, Color(0.20, 0.45, 0.35))
		_play_btn.pressed.connect(_on_reload_pressed)
		bar_hflow.add_child(_play_btn)

		_stop_btn = Button.new()
		_stop_btn.text = "⏹ Stop Video"
		_stop_btn.custom_minimum_size = Vector2(120, 42)
		_apply_btn_style(_stop_btn, Color(0.55, 0.20, 0.20))
		_stop_btn.pressed.connect(_on_stop_pressed)
		bar_hflow.add_child(_stop_btn)

	bar_panel.add_child(bar_hflow)
	add_child(bar_panel)


func _on_thumbnail_gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_on_open_browser_pressed()


func _on_copy_link_pressed(btn: Button) -> void:
	if video_url == "":
		return
	DisplayServer.clipboard_set(video_url)
	if btn != null and is_instance_valid(btn):
		var orig_text = btn.text
		btn.text = "✓ Link Copied!"
		var timer = get_tree().create_timer(2.0)
		timer.timeout.connect(func():
			if is_instance_valid(btn):
				btn.text = orig_text
		)


func _start_in_app_player() -> void:
	if video_url == "":
		if _status_lbl != null:
			_status_lbl.text = "No video tutorial available for this shot type."
		return

	if not is_desktop_windows():
		# On mobile / non-Windows platforms, interactive thumbnail card handles playback via YouTube app
		if _status_lbl != null:
			_status_lbl.text = "🎬 Tap preview or button below to watch on YouTube."
		return

	_stop_in_app_player()

	await get_tree().process_frame
	await get_tree().process_frame

	if _video_frame == null or not is_inside_tree():
		return

	# Calculate native screen / client area coordinates
	var cur_win: Window = get_window()
	var win_id: int = cur_win.get_window_id() if cur_win != null else DisplayServer.MAIN_WINDOW_ID
	var godot_hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, win_id)
	var win_size: Vector2i = DisplayServer.window_get_size(win_id)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size

	var scale_x: float = float(win_size.x) / max(vp_size.x, 1.0)
	var scale_y: float = float(win_size.y) / max(vp_size.y, 1.0)

	var g_pos: Vector2 = _video_frame.get_global_position()
	var f_size: Vector2 = _video_frame.size
	if f_size.x < 100.0 or f_size.y < 100.0:
		f_size = _video_frame.custom_minimum_size

	var client_x: int = int(g_pos.x * scale_x)
	var client_y: int = int(g_pos.y * scale_y)
	var client_w: int = int(max(f_size.x * scale_x, 480.0))
	var client_h: int = int(max(f_size.y * scale_y, 270.0))

	var script_path = ProjectSettings.globalize_path("res://UI/GolferCamera/in_app_player.py")
	if not FileAccess.file_exists(script_path):
		print("[InAppVideoPlayer] Embedded player script not found at: ", script_path)
		if _status_lbl != null:
			_status_lbl.text = "🎬 Tap preview or button below to watch on YouTube."
		return

	var args: PackedStringArray = [
		script_path,
		str(godot_hwnd),
		str(client_x),
		str(client_y),
		str(client_w),
		str(client_h),
		video_url
	]

	print("[InAppVideoPlayer] Starting embedded in-app player for HWND %d at (%d,%d %dx%d)..." % [
		godot_hwnd, client_x, client_y, client_w, client_h
	])

	_player_pid = OS.create_process("python", args)
	if _player_pid <= 0:
		_player_pid = OS.create_process("py", args)

	if _player_pid > 0:
		_is_playing = true
		if _status_lbl != null:
			_status_lbl.text = "🎬 Playing in-app. Video active."
		print("[InAppVideoPlayer] Embedded player launched (PID: %d)" % _player_pid)

		# Monitor liveness after startup
		var check_timer = get_tree().create_timer(2.0)
		check_timer.timeout.connect(func():
			if _player_pid > 0 and not OS.is_process_running(_player_pid):
				_is_playing = false
				_player_pid = -1
				if _status_lbl != null and is_inside_tree():
					_status_lbl.text = "🎬 Tap preview or button below to watch on YouTube."
		)
	else:
		print("[InAppVideoPlayer] In-app player helper could not be launched. Falling back to thumbnail player.")
		if _status_lbl != null:
			_status_lbl.text = "🎬 Tap preview or button below to watch on YouTube."


func _stop_in_app_player() -> void:
	if _udp != null and _target_udp_port > 0:
		_udp.put_packet("QUIT\n".to_utf8_buffer())
		_udp.close()
		_udp = null
	_target_udp_port = 0
	_last_sent_pos = Vector2(-9999, -9999)

	var temp_dir = OS.get_environment("TEMP")
	if temp_dir != null and temp_dir != "":
		var port_file = temp_dir + "/heckle_yt_port_%d.txt" % _player_pid
		var latest_file = temp_dir + "/heckle_yt_ipc_latest.txt"
		if FileAccess.file_exists(port_file):
			DirAccess.remove_absolute(port_file)
		if FileAccess.file_exists(latest_file):
			DirAccess.remove_absolute(latest_file)

	if OS.get_name() == "Windows":
		if _browser_pid > 0:
			print("[InAppVideoPlayer] Terminating browser process tree (PID: %d)..." % _browser_pid)
			OS.execute("taskkill.exe", ["/F", "/T", "/PID", str(_browser_pid)])
		if _player_pid > 0:
			print("[InAppVideoPlayer] Terminating player helper process tree (PID: %d)..." % _player_pid)
			OS.execute("taskkill.exe", ["/F", "/T", "/PID", str(_player_pid)])
	else:
		if _player_pid > 0:
			OS.kill(_player_pid)

	_browser_pid = -1
	_player_pid = -1
	_is_playing = false
	if _status_lbl != null and is_inside_tree():
		_status_lbl.text = "⏹ Video stopped."


func _on_reload_pressed() -> void:
	_start_in_app_player()


func _on_stop_pressed() -> void:
	_stop_in_app_player()


func _on_open_browser_pressed() -> void:
	if video_url != "":
		print("[InAppVideoPlayer] Opening YouTube video URL: ", video_url)
		OS.shell_open(video_url)


func _apply_btn_style(btn: Button, bg_col: Color) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_col
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 8

	var hover_style = style.duplicate()
	hover_style.bg_color = bg_col.lightened(0.15)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = bg_col.darkened(0.15)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", style)
	btn.add_theme_font_size_override("font_size", 14 if not is_mobile_view else 15)
	btn.add_theme_color_override("font_color", Color.WHITE)
