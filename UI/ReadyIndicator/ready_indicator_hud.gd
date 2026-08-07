extends CanvasLayer

# ReadyIndicatorHUD
# Positioned overlay showing Launch Monitor ball readiness status ONLY during active gameplay.

enum ScreenLayout {
	HIDDEN,                 # Main menu, course selection, setup, history, analytics
	TOP_CENTER_UNDER_AIM,   # Driving Range, Full Course Play (positioned directly under Aim distance pill)
	TOP_LEFT                # Chipping & Putting practice (positioned top-left to clear minigame scoreboard)
}

var _container: MarginContainer
var _panel: PanelContainer
var _hbox: HBoxContainer
var _dot_panel: Panel
var _status_label: Label
var _sub_label: Label
var _glow_style: StyleBoxFlat
var _tween: Tween = null
var _pulse_tween: Tween = null

var _is_ready := false
var _status_text := "Disconnected"
var _visible_mode := true
var _current_layout := ScreenLayout.HIDDEN
var _check_timer := 0.0
var _cached_ball: GolfBall = null
var _ball_moving_prev := false


func _ready() -> void:
	layer = 90
	process_mode = PROCESS_MODE_ALWAYS
	_setup_ui()
	
	if has_node("/root/SceneManager"):
		var scn_mgr = get_node("/root/SceneManager")
		if scn_mgr.has_signal("scene_changed"):
			scn_mgr.scene_changed.connect(_on_scene_changed)
			
	_refresh_layout_and_display(true)


func _process(delta: float) -> void:
	# Check ball state every frame for immediate show/hide response
	var ball = _get_golf_ball()
	var ball_moving = false
	if ball != null and is_instance_valid(ball):
		ball_moving = ball.state != 0 # REST is 0

	if ball_moving != _ball_moving_prev:
		_ball_moving_prev = ball_moving
		_update_display(true)

	_check_timer += delta
	if _check_timer >= 0.1:
		_check_timer = 0.0
		var layout := _detect_current_gameplay_screen()
		if layout != _current_layout:
			_apply_layout(layout)
			_update_display(true)


func _on_scene_changed() -> void:
	_cached_ball = null
	_ball_moving_prev = false
	call_deferred("_refresh_layout_and_display", true)


func _setup_ui() -> void:
	_container = MarginContainer.new()
	_container.name = "ReadyHUDContainer"
	_container.anchors_preset = Control.PRESET_CENTER_TOP
	_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_container.grow_vertical = Control.GROW_DIRECTION_END
	_container.add_theme_constant_override("margin_top", 78)
	add_child(_container)

	_panel = PanelContainer.new()
	_panel.name = "StatusBadge"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_panel)

	_glow_style = StyleBoxFlat.new()
	_glow_style.corner_radius_top_left = 18
	_glow_style.corner_radius_top_right = 18
	_glow_style.corner_radius_bottom_left = 18
	_glow_style.corner_radius_bottom_right = 18
	_glow_style.bg_color = Color(0.06, 0.12, 0.09, 0.88)
	_glow_style.border_width_left = 2
	_glow_style.border_width_top = 2
	_glow_style.border_width_right = 2
	_glow_style.border_width_bottom = 2
	_glow_style.border_color = Color(0.18, 0.8, 0.44, 0.8)
	_glow_style.content_margin_left = 16
	_glow_style.content_margin_right = 18
	_glow_style.content_margin_top = 8
	_glow_style.content_margin_bottom = 8
	_glow_style.shadow_color = Color(0, 0, 0, 0.35)
	_glow_style.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", _glow_style)

	_hbox = HBoxContainer.new()
	_hbox.add_theme_constant_override("separation", 10)
	_panel.add_child(_hbox)

	# LED Dot Container
	var dot_center = CenterContainer.new()
	dot_center.custom_minimum_size = Vector2(16, 16)
	_hbox.add_child(dot_center)

	_dot_panel = Panel.new()
	_dot_panel.custom_minimum_size = Vector2(12, 12)
	var dot_style = StyleBoxFlat.new()
	dot_style.corner_radius_top_left = 6
	dot_style.corner_radius_top_right = 6
	dot_style.corner_radius_bottom_left = 6
	dot_style.corner_radius_bottom_right = 6
	dot_style.bg_color = Color(0.18, 0.8, 0.44)
	_dot_panel.add_theme_stylebox_override("panel", dot_style)
	dot_center.add_child(_dot_panel)

	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", -2)
	_hbox.add_child(text_vbox)

	_status_label = Label.new()
	_status_label.text = "BALL READY"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1))
	text_vbox.add_child(_status_label)

	_sub_label = Label.new()
	_sub_label.text = "READY TO HIT"
	_sub_label.add_theme_font_size_override("font_size", 10)
	_sub_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.75))
	text_vbox.add_child(_sub_label)


func set_ready_status(is_ready: bool, status: String, enabled: bool = true) -> void:
	_visible_mode = enabled
	_is_ready = is_ready
	_status_text = status
	_refresh_layout_and_display(false)


func _refresh_layout_and_display(instant: bool = false) -> void:
	var layout := _detect_current_gameplay_screen()
	_apply_layout(layout)
	_update_display(instant)


func _get_active_scene() -> Node:
	if has_node("/root/SceneManager"):
		var scn_mgr = get_node("/root/SceneManager")
		var scn = scn_mgr.get("current_scene") as Node
		if scn != null and is_instance_valid(scn):
			return scn
	var tree := get_tree()
	if tree != null:
		return tree.current_scene
	return null


func _detect_current_gameplay_screen() -> ScreenLayout:
	var scene := _get_active_scene()
	if scene == null:
		return ScreenLayout.HIDDEN

	# Check if current screen is a non-gameplay menu/selection screen
	if _is_menu_screen(scene):
		return ScreenLayout.HIDDEN

	var scene_name := str(scene.name).to_lower()
	var script: Script = scene.get_script()
	var script_path := str(script.resource_path).to_lower() if script != null else ""
	var file_path := str(scene.scene_file_path).to_lower() if "scene_file_path" in scene else ""

	var full_id := (scene_name + " " + script_path + " " + file_path).to_lower()

	# Chipping Minigame or Putting Practice -> TOP_LEFT (Avoids 780px-800px top-center scoreboard panel)
	if full_id.contains("chipping") or scene_name.contains("chipping") or full_id.contains("putting") or scene_name.contains("putting"):
		return ScreenLayout.TOP_LEFT

	# Driving Range, Course Play, CourseManager, and all loaded course scenes -> TOP_CENTER_UNDER_AIM
	return ScreenLayout.TOP_CENTER_UNDER_AIM


func _is_menu_screen(scene: Node) -> bool:
	if scene == null:
		return true

	var scene_name := str(scene.name).to_lower()
	var script: Script = scene.get_script()
	var script_path := str(script.resource_path).to_lower() if script != null else ""
	var file_path := str(scene.scene_file_path).to_lower() if "scene_file_path" in scene else ""

	var full_id := (scene_name + " " + script_path + " " + file_path).to_lower()

	# Explicit list of menu / selection / setup / analytics / creator screens
	if full_id.contains("main_menu") or full_id.contains("mainmenu") \
		or full_id.contains("course_selector") or full_id.contains("courseselector") \
		or full_id.contains("course_play_setup") or full_id.contains("courseplaysetup") \
		or full_id.contains("minigames_menu") or full_id.contains("minigamesmenu") \
		or full_id.contains("players_menu") or full_id.contains("playersmenu") \
		or full_id.contains("analytics") or full_id.contains("history") \
		or full_id.contains("custom_course_creator") or full_id.contains("osm_download") \
		or full_id.contains("course_preview"):
		return true

	return false


func _is_device_connected() -> bool:
	var st := ""
	var ready := _is_ready

	if has_node("/root/LaunchMonitorManager"):
		var lm = get_node("/root/LaunchMonitorManager")
		if lm != null and is_instance_valid(lm):
			ready = ready or lm.is_ready
			st = str(lm.status).to_lower()

	if st == "":
		st = _status_text.to_lower()

	if ready:
		return true

	if (st.contains("connected") and not st.contains("disconnected")) or st == "ready" or st.contains("detecting"):
		return true

	return false


func _is_in_aerial_or_map_view(scene: Node) -> bool:
	if scene == null:
		return false

	if "is_sky_view_active" in scene and bool(scene.get("is_sky_view_active")):
		return true

	if "is_aerial_view" in scene and bool(scene.get("is_aerial_view")):
		return true

	if "course_instance" in scene:
		var ci = scene.get("course_instance")
		if ci != null and is_instance_valid(ci):
			if "is_aerial_view" in ci and bool(ci.get("is_aerial_view")):
				return true

	return false


func _is_node_visible_in_tree(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node is CanvasItem:
		return (node as CanvasItem).is_visible_in_tree()
	elif node is CanvasLayer:
		return (node as CanvasLayer).visible
	elif node is Window:
		return (node as Window).is_visible_in_tree()

	return false


func _is_menu_overlay_open(scene: Node) -> bool:
	if scene == null:
		return false

	if "hud_scorecard" in scene:
		var sc = scene.get("hud_scorecard")
		if sc != null and is_instance_valid(sc) and _is_node_visible_in_tree(sc):
			return true
	if "hud_manage_players" in scene:
		var mp = scene.get("hud_manage_players")
		if mp != null and is_instance_valid(mp) and _is_node_visible_in_tree(mp):
			return true
	if "hud_overview" in scene:
		var ov = scene.get("hud_overview")
		if ov != null and is_instance_valid(ov) and _is_node_visible_in_tree(ov):
			return true
	if "mulligan_confirm_dialog" in scene:
		var mc = scene.get("mulligan_confirm_dialog")
		if mc != null and is_instance_valid(mc) and _is_node_visible_in_tree(mc):
			return true

	return _find_visible_overlay_node(scene)


func _find_visible_overlay_node(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node is Popup or node is AcceptDialog or node is ConfirmationDialog:
		if _is_node_visible_in_tree(node):
			return true

	if (node is Control or node is CanvasLayer) and _is_node_visible_in_tree(node):
		var n_lower := str(node.name).to_lower()
		if n_lower.contains("rangesettings") or n_lower.contains("minigamesettings") \
			or n_lower == "settingslayer" or n_lower.contains("sessionpopup") \
			or n_lower.contains("swingreplay") or n_lower.contains("pausemenu") \
			or n_lower.contains("settingsmodal") or n_lower.contains("optionsmenu"):
			return true

	for child in node.get_children():
		if child == self or (child is CanvasLayer and child.name.contains("ReadyHUD")):
			continue
		if _find_visible_overlay_node(child):
			return true

	return false


func _apply_layout(layout: ScreenLayout) -> void:
	_current_layout = layout

	if layout == ScreenLayout.TOP_LEFT:
		_container.anchors_preset = Control.PRESET_TOP_LEFT
		_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_container.grow_horizontal = Control.GROW_DIRECTION_END
		_container.grow_vertical = Control.GROW_DIRECTION_END
		_container.add_theme_constant_override("margin_top", 18)
		_container.add_theme_constant_override("margin_left", 20)
	elif layout == ScreenLayout.TOP_CENTER_UNDER_AIM:
		_container.anchors_preset = Control.PRESET_CENTER_TOP
		_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_container.grow_vertical = Control.GROW_DIRECTION_END
		_container.add_theme_constant_override("margin_top", 78) # Right beneath "Aim: 464 Yards | Tee Box" pill!
		_container.add_theme_constant_override("margin_left", 0)


func _update_display(instant: bool = false) -> void:
	var scene := _get_active_scene()

	# 1. Hide on non-gameplay screens or if disabled by setting
	if _current_layout == ScreenLayout.HIDDEN or not _visible_mode:
		visible = false
		return

	# 2. Hide when no launch monitor device is connected
	if not _is_device_connected():
		visible = false
		return

	# 3. Hide when the ball is moving
	if _ball_moving_prev:
		visible = false
		return

	# 4. Hide when in map/aerial view or sky view (not in hitting spot)
	if _is_in_aerial_or_map_view(scene):
		visible = false
		return

	# 5. Hide when any menu overlay, settings panel, popup, or scorecard is open
	if _is_menu_overlay_open(scene):
		visible = false
		return

	# Display status indicator when connected and in hitting spot
	visible = true
	_panel.modulate.a = 1.0
	var dot_style = _dot_panel.get_theme_stylebox("panel") as StyleBoxFlat

	if _is_ready:
		_status_label.text = "BALL READY"
		_sub_label.text = "READY TO HIT"
		_status_label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.95))
		_sub_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
		
		_glow_style.bg_color = Color(0.05, 0.16, 0.09, 0.92)
		_glow_style.border_color = Color(0.2, 0.9, 0.45, 0.9)
		_glow_style.shadow_color = Color(0.1, 0.8, 0.3, 0.35)
		if dot_style:
			dot_style.bg_color = Color(0.2, 0.95, 0.45)
		
		_trigger_pulse_animation()
		if not instant:
			_trigger_pop_animation()
	else:
		_stop_pulse_animation()
		_status_label.text = "PLACE BALL IN ZONE"
		_sub_label.text = "WAITING FOR BALL"
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
		_sub_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
		
		_glow_style.bg_color = Color(0.12, 0.1, 0.05, 0.85)
		_glow_style.border_color = Color(0.9, 0.65, 0.2, 0.7)
		_glow_style.shadow_color = Color(0, 0, 0, 0.3)
		if dot_style:
			dot_style.bg_color = Color(0.95, 0.65, 0.15)


func _trigger_pop_animation() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_panel.pivot_offset = _panel.size / 2.0
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_panel.scale = Vector2(1.15, 1.15)
	_tween.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.35)


func _trigger_pulse_animation() -> void:
	if _pulse_tween != null and _pulse_tween.is_running():
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_dot_panel, "modulate:a", 0.3, 0.6)
	_pulse_tween.tween_property(_dot_panel, "modulate:a", 1.0, 0.6)


func _stop_pulse_animation() -> void:
	if _pulse_tween != null and _pulse_tween.is_running():
		_pulse_tween.kill()
	_dot_panel.modulate.a = 1.0


func _fade_out() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(func(): visible = false)


func _find_golf_ball(node: Node) -> Node:
	if node == null:
		return null
	if node is GolfBall:
		return node
	# Also check if the node has a "ball" property that is a GolfBall
	if "ball" in node:
		var b = node.get("ball")
		if b is GolfBall:
			return b
	for child in node.get_children():
		var b = _find_golf_ball(child)
		if b != null:
			return b
	return null


func _get_golf_ball() -> GolfBall:
	if _cached_ball != null and is_instance_valid(_cached_ball):
		return _cached_ball
		
	var scene = _get_active_scene()
	if scene != null:
		_cached_ball = _find_golf_ball(scene) as GolfBall
		return _cached_ball
	return null
