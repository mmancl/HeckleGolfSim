extends CanvasLayer

@onready var popup_control: Control = $PopupControl
@onready var panel: PanelContainer = $PopupControl/PanelContainer
@onready var badge_rect: TextureRect = $PopupControl/PanelContainer/MarginContainer/HBoxContainer/BadgeRect
@onready var header_lbl: Label = $PopupControl/PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/HeaderLabel
@onready var title_lbl: Label = $PopupControl/PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/TitleLabel
@onready var desc_lbl: Label = $PopupControl/PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/DescLabel

var _queue: Array = []
var _is_showing: bool = false

func is_showing_achievement() -> bool:
	return _is_showing or not _queue.is_empty() or (popup_control != null and is_instance_valid(popup_control) and popup_control.modulate.a > 0.05 and popup_control.offset_top > OFFSCREEN_TOP + 10.0)

# Layout constants for high-contrast, enlarged popup window
const OFFSCREEN_TOP: float = -170.0
const OFFSCREEN_BOTTOM: float = -26.0
const ONSCREEN_TOP: float = 28.0
const ONSCREEN_BOTTOM: float = 172.0

func _ready() -> void:
	# Layer 128 guarantees the achievement popup renders above ALL in-game UI, dialogs, and menus
	layer = 128
	
	popup_control.anchor_left = 0.5
	popup_control.anchor_right = 0.5
	popup_control.anchor_top = 0.0
	popup_control.anchor_bottom = 0.0
	popup_control.offset_left = -280.0
	popup_control.offset_right = 280.0
	popup_control.offset_top = OFFSCREEN_TOP
	popup_control.offset_bottom = OFFSCREEN_BOTTOM
	popup_control.modulate.a = 0.0
	
	popup_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if has_node("/root/AchievementManager"):
		get_node("/root/AchievementManager").connect("achievement_unlocked", _on_achievement_unlocked)

func _on_achievement_unlocked(player_name: String, ach: Dictionary) -> void:
	_queue.append({
		"player_name": player_name,
		"ach": ach
	})
	if not _is_showing:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_is_showing = false
		return
		
	_is_showing = true
	var item = _queue.pop_front()
	var player_name: String = item["player_name"]
	var ach: Dictionary = item["ach"]
	
	header_lbl.text = "🏆 ACHIEVEMENT UNLOCKED (%s)" % player_name.to_upper()
	title_lbl.text = ach.get("title", "Achievement")
	desc_lbl.text = ach.get("description", "")
	
	var badge_path = ach.get("badge_path", "")
	if ResourceLoader.exists(badge_path):
		badge_rect.texture = load(badge_path)
	else:
		badge_rect.texture = null
		
	# Reset position offscreen
	popup_control.offset_top = OFFSCREEN_TOP
	popup_control.offset_bottom = OFFSCREEN_BOTTOM
	popup_control.modulate.a = 0.0
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(popup_control, "offset_top", ONSCREEN_TOP, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup_control, "offset_bottom", ONSCREEN_BOTTOM, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup_control, "modulate:a", 1.0, 0.3)
	
	await tween.finished
	
	# Play subtle notification sound if audio available
	if has_node("/root/GlobalSettings"):
		var gs = get_node("/root/GlobalSettings")
		if gs.has_method("play_golf_clap"):
			gs.play_golf_clap()
			
	# Hold for 3.5s
	await get_tree().create_timer(3.5).timeout
	
	# Slide out
	var hide_tween = create_tween().set_parallel(true)
	hide_tween.tween_property(popup_control, "offset_top", OFFSCREEN_TOP, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	hide_tween.tween_property(popup_control, "offset_bottom", OFFSCREEN_BOTTOM, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	hide_tween.tween_property(popup_control, "modulate:a", 0.0, 0.4)
	
	await hide_tween.finished
	_show_next()
