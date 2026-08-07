class_name SettingCollector
extends RefCounted

signal settings_changed

var settings : Dictionary[String,Setting] = {}

func _init(sets : Dictionary[String, Setting] = {}):
	init(sets)
	
func init(sets : Dictionary[String, Setting] = {}):
	settings = sets
	for name in settings.keys():
		var setting = settings[name]
		if not setting.setting_changed.is_connected(_on_setting_changed):
			setting.setting_changed.connect(_on_setting_changed)

var _block_events := false

func _on_setting_changed(_val):
	if not _block_events:
		emit_signal("settings_changed")

func reset_defaults():
	_block_events = true
	for name in settings.keys():
		settings[name].reset_default()
	_block_events = false
	emit_signal("settings_changed")
		
func set_value(setting_name : String, setting_value : Variant):
	settings[setting_name].set_value(setting_value)
	
func set_default(setting_name : String, setting_default : Variant):
	settings[setting_name].set_default(setting_default)
