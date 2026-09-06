extends Node

signal settings_changed

# Range Settings
var range_settings := RangeSettings.new()
const OPENFAIRWAY_LOG_LEVEL_INFO := 2
var practice_mode_primed : bool = false
var is_chipping_minigame : bool = false
var is_putting_minigame : bool = false


var _loaded_announcer_settings := {}

func _ready() -> void:
	PhysicsLogger.SetLevel(OPENFAIRWAY_LOG_LEVEL_INFO)
	load_settings()
	_setup_audio_players()
	
	# Wait for announcer engine if it enters tree later
	var announcer = get_node_or_null("/root/AnnouncerEngine")
	if announcer:
		_apply_announcer_settings(announcer)
	else:
		get_tree().root.child_entered_tree.connect(_on_root_child_entered_tree)
		
	# Connect save_settings to settings_changed signal
	range_settings.settings_changed.connect(save_settings)


func _on_root_child_entered_tree(node: Node) -> void:
	if node.name == "AnnouncerEngine":
		_apply_announcer_settings(node)
		get_tree().root.child_entered_tree.disconnect(_on_root_child_entered_tree)


func _apply_announcer_settings(announcer: Node) -> void:
	for key in _loaded_announcer_settings.keys():
		announcer.set(key, _loaded_announcer_settings[key])


func resett_defaults():
	range_settings.reset_defaults()
	var announcer = get_node_or_null("/root/AnnouncerEngine")
	if announcer:
		announcer.set("AnnouncerCoursePlay", true)
		announcer.set("HeckleCoursePlay", true)
		announcer.set("AnnouncerRange", false)
		announcer.set("HeckleRange", false)
		announcer.set("AnnouncerMiniGames", false)
		announcer.set("HeckleMiniGames", false)
		announcer.set("PraiseEnabled", true)
		announcer.set("ActiveVoice", "")
		announcer.set("Pitch", 1.0)
		announcer.set("Rate", 1.0)
	save_settings()
	emit_signal("settings_changed")


func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://global_settings.cfg")
	if err != OK:
		return
	
	# Load RangeSettings
	for key in range_settings.settings.keys():
		if config.has_section_key("range_settings", key):
			var val = config.get_value("range_settings", key)
			range_settings.settings[key].set_value(val)
			
	# Migration for camera settings if updating from older config files with small camera distance
	var migrated := false
	if range_settings.camera_distance.value < 14.0:
		range_settings.camera_distance.set_value(15.0)
		migrated = true
	if range_settings.camera_fov.value < 50.0:
		range_settings.camera_fov.set_value(55.0)
		migrated = true
	if range_settings.camera_height.value < 2.0:
		range_settings.camera_height.set_value(2.4)
		migrated = true
	if is_equal_approx(range_settings.ball_reset_timer.value, 3.0):
		range_settings.ball_reset_timer.set_value(1.5)
		migrated = true
	
	# Migration / validation for displayed_stats
	var stats_val = range_settings.displayed_stats.value
	if not (stats_val is Array) or stats_val.is_empty():
		range_settings.displayed_stats.set_value(StatDefinitions.DEFAULT_ENABLED_STAT_IDS.duplicate())
		migrated = true
	else:
		var valid_ids = StatDefinitions.get_all_stat_ids()
		var cleaned_stats: Array[String] = []
		for s in stats_val:
			var s_str = str(s)
			if valid_ids.has(s_str) and not cleaned_stats.has(s_str) and cleaned_stats.size() < StatDefinitions.MAX_DISPLAYED_STATS:
				cleaned_stats.append(s_str)
		if cleaned_stats.is_empty():
			cleaned_stats = StatDefinitions.DEFAULT_ENABLED_STAT_IDS.duplicate()
		if cleaned_stats != stats_val:
			range_settings.displayed_stats.set_value(cleaned_stats)
			migrated = true

	if migrated:
		save_settings()
	
	# Load AnnouncerSettings
	_loaded_announcer_settings.clear()
	var announcer_keys = [
		"AnnouncerCoursePlay",
		"HeckleCoursePlay",
		"AnnouncerRange",
		"HeckleRange",
		"AnnouncerMiniGames",
		"HeckleMiniGames",
		"PraiseEnabled",
		"ActiveVoice",
		"Pitch",
		"Rate"
	]
	for key in announcer_keys:
		var config_key = key.to_lower()
		if config.has_section_key("announcer", config_key):
			_loaded_announcer_settings[key] = config.get_value("announcer", config_key)

	# Migration / default fallbacks if upgrading from legacy announcer settings
	if not _loaded_announcer_settings.has("AnnouncerCoursePlay"):
		_loaded_announcer_settings["AnnouncerCoursePlay"] = true
	if not _loaded_announcer_settings.has("HeckleCoursePlay"):
		_loaded_announcer_settings["HeckleCoursePlay"] = true
	if not _loaded_announcer_settings.has("AnnouncerRange"):
		_loaded_announcer_settings["AnnouncerRange"] = false
	if not _loaded_announcer_settings.has("HeckleRange"):
		_loaded_announcer_settings["HeckleRange"] = false
	if not _loaded_announcer_settings.has("AnnouncerMiniGames"):
		_loaded_announcer_settings["AnnouncerMiniGames"] = false
	if not _loaded_announcer_settings.has("HeckleMiniGames"):
		_loaded_announcer_settings["HeckleMiniGames"] = false
	if not _loaded_announcer_settings.has("PraiseEnabled"):
		_loaded_announcer_settings["PraiseEnabled"] = true
			
	var announcer = get_node_or_null("/root/AnnouncerEngine")
	if announcer:
		_apply_announcer_settings(announcer)


func save_settings() -> void:
	var config = ConfigFile.new()
	
	# Save RangeSettings
	for key in range_settings.settings.keys():
		config.set_value("range_settings", key, range_settings.settings[key].value)
	
	# Save AnnouncerSettings
	var announcer = get_node_or_null("/root/AnnouncerEngine")
	if announcer:
		_loaded_announcer_settings["AnnouncerCoursePlay"] = announcer.get("AnnouncerCoursePlay")
		_loaded_announcer_settings["HeckleCoursePlay"] = announcer.get("HeckleCoursePlay")
		_loaded_announcer_settings["AnnouncerRange"] = announcer.get("AnnouncerRange")
		_loaded_announcer_settings["HeckleRange"] = announcer.get("HeckleRange")
		_loaded_announcer_settings["AnnouncerMiniGames"] = announcer.get("AnnouncerMiniGames")
		_loaded_announcer_settings["HeckleMiniGames"] = announcer.get("HeckleMiniGames")
		_loaded_announcer_settings["PraiseEnabled"] = announcer.get("PraiseEnabled")
		_loaded_announcer_settings["ActiveVoice"] = announcer.get("ActiveVoice")
		_loaded_announcer_settings["Pitch"] = announcer.get("Pitch")
		_loaded_announcer_settings["Rate"] = announcer.get("Rate")
		
	for key in _loaded_announcer_settings.keys():
		config.set_value("announcer", key.to_lower(), _loaded_announcer_settings[key])
			
	var err = config.save("user://global_settings.cfg")
	if err != OK:
		push_error("Failed to save settings: %d" % err)


var _clap_player: AudioStreamPlayer = null

func play_golf_clap() -> void:
	if not range_settings.golf_clap_enabled.value:
		return
	if _clap_player == null:
		_clap_player = AudioStreamPlayer.new()
		add_child(_clap_player)
		var stream = load("res://assets/audio/golf_clap.mp3")
		_clap_player.stream = stream
	_clap_player.play()


var _ambient_player: AudioStreamPlayer = null
var _menu_music_player: AudioStreamPlayer = null
var _minigames_music_player: AudioStreamPlayer = null
var _audio_check_timer: float = 0.0

func _process(delta: float) -> void:
	_audio_check_timer += delta
	if _audio_check_timer >= 0.25:
		_audio_check_timer = 0.0
		update_audio_state()


var _minigame_tracks: Array[AudioStream] = []
var _minigame_track_index: int = 0

func _setup_audio_players() -> void:
	if _ambient_player == null:
		_ambient_player = AudioStreamPlayer.new()
		_ambient_player.name = "AmbientNaturePlayer"
		add_child(_ambient_player)
		
		var path = "res://assets/audio/ambient_nature.ogg"
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream:
				if "loop" in stream:
					stream.loop = true
				_ambient_player.stream = stream
				_ambient_player.volume_db = -25.0
				_ambient_player.finished.connect(func():
					if _should_play_ambient():
						_ambient_player.play()
				)
				
	if _menu_music_player == null:
		_menu_music_player = AudioStreamPlayer.new()
		_menu_music_player.name = "MenuMusicPlayer"
		add_child(_menu_music_player)
		
		var path = "res://assets/audio/menu_soundtrack.wav"
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream:
				if "loop" in stream:
					stream.loop = true
				_menu_music_player.stream = stream
				_menu_music_player.volume_db = -34.0
				_menu_music_player.finished.connect(func():
					if _should_play_menu_music():
						_menu_music_player.play()
				)

	if _minigames_music_player == null:
		_minigames_music_player = AudioStreamPlayer.new()
		_minigames_music_player.name = "MinigamesMusicPlayer"
		add_child(_minigames_music_player)
		
		var track_paths = [
			"res://assets/audio/minigames_music.mp3",
			"res://assets/audio/boogie_pecan_pie.mp3"
		]
		_minigame_tracks.clear()
		for t_path in track_paths:
			if ResourceLoader.exists(t_path):
				var stream = load(t_path)
				if stream:
					if "loop" in stream:
						stream.loop = false
					_minigame_tracks.append(stream)
		
		if not _minigame_tracks.is_empty():
			_minigame_track_index = 0
			_minigames_music_player.stream = _minigame_tracks[0]
			_minigames_music_player.volume_db = -22.0
			_minigames_music_player.finished.connect(_on_minigames_music_finished)
				
	range_settings.ambient_sound_enabled.setting_changed.connect(func(_val): update_audio_state())
	range_settings.menu_music_enabled.setting_changed.connect(func(_val): update_audio_state())
	range_settings.minigame_music_enabled.setting_changed.connect(func(_val): update_audio_state())
	
	if has_node("/root/SceneManager"):
		var scn_mgr = get_node("/root/SceneManager")
		if scn_mgr.has_signal("scene_changed"):
			scn_mgr.scene_changed.connect(func(): update_audio_state())
			
	get_tree().root.child_entered_tree.connect(func(_node): call_deferred("update_audio_state"))
	call_deferred("update_audio_state")


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


func is_minigames_menu_screen() -> bool:
	var scene := _get_active_scene()
	if scene == null:
		return false

	var scene_name := str(scene.name).to_lower()
	var script: Script = scene.get_script()
	var script_path := str(script.resource_path).to_lower() if script != null else ""
	var file_path := str(scene.scene_file_path).to_lower() if "scene_file_path" in scene else ""

	var full_id := (scene_name + " " + script_path + " " + file_path).to_lower()
	return full_id.contains("minigames_menu") or full_id.contains("minigamesmenu")


func is_minigames_gameplay_screen() -> bool:
	var scene := _get_active_scene()
	if scene == null:
		return false

	var scene_name := str(scene.name).to_lower()
	var script: Script = scene.get_script()
	var script_path := str(script.resource_path).to_lower() if script != null else ""
	var file_path := str(scene.scene_file_path).to_lower() if "scene_file_path" in scene else ""

	var full_id := (scene_name + " " + script_path + " " + file_path).to_lower()
	return full_id.contains("putting_practice") or full_id.contains("puttingpractice") \
		or full_id.contains("chipping") or full_id.contains("/minigames/")


func is_minigames_scene() -> bool:
	return is_minigames_menu_screen() or is_minigames_gameplay_screen()


func is_menu_screen() -> bool:
	var scene := _get_active_scene()
	if scene == null:
		return true

	var scene_name := str(scene.name).to_lower()
	var script: Script = scene.get_script()
	var script_path := str(script.resource_path).to_lower() if script != null else ""
	var file_path := str(scene.scene_file_path).to_lower() if "scene_file_path" in scene else ""

	var full_id := (scene_name + " " + script_path + " " + file_path).to_lower()

	# Menu / setup / selection / analytics screens (excluding minigames_menu which uses minigame soundtrack)
	if full_id.contains("main_menu") or full_id.contains("mainmenu") \
		or full_id.contains("course_selector") or full_id.contains("courseselector") \
		or full_id.contains("course_play_setup") or full_id.contains("courseplaysetup") \
		or full_id.contains("players_menu") or full_id.contains("playersmenu") \
		or full_id.contains("analytics") or full_id.contains("history") \
		or full_id.contains("custom_course_creator") or full_id.contains("osm_download") \
		or full_id.contains("course_preview"):
		return true

	return false


func _should_play_menu_music() -> bool:
	if not range_settings.menu_music_enabled.value:
		return false
	return is_menu_screen() and not is_minigames_scene()


func _should_play_ambient() -> bool:
	if not range_settings.ambient_sound_enabled.value:
		return false
	return not is_menu_screen() and not is_minigames_scene()


func _should_play_minigame_music() -> bool:
	if not range_settings.minigame_music_enabled.value:
		return false
	return is_minigames_scene()


func _on_minigames_music_finished() -> void:
	if _minigame_tracks.is_empty():
		return
	_minigame_track_index = (_minigame_track_index + 1) % _minigame_tracks.size()
	_minigames_music_player.stream = _minigame_tracks[_minigame_track_index]
	if _should_play_minigame_music():
		_minigames_music_player.play()


func update_audio_state() -> void:
	# Menu Soundtrack logic
	if _menu_music_player != null and _menu_music_player.stream != null:
		if _should_play_menu_music():
			if not _menu_music_player.playing:
				_menu_music_player.play()
		else:
			if _menu_music_player.playing:
				_menu_music_player.stop()

	# Minigames Music Soundtrack logic
	if _minigames_music_player != null and _minigames_music_player.stream != null:
		if _should_play_minigame_music():
			if not _minigames_music_player.playing:
				_minigames_music_player.play()
		else:
			if _minigames_music_player.playing:
				_minigames_music_player.stop()

	# Ambient Nature Sounds logic (disabled in minigames and menus)
	if _ambient_player != null and _ambient_player.stream != null:
		if _should_play_ambient():
			if not _ambient_player.playing:
				_ambient_player.play()
		else:
			if _ambient_player.playing:
				_ambient_player.stop()



