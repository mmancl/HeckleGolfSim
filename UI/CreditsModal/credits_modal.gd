extends Control

signal closed

@onready var modal_panel: PanelContainer = $CenterContainer/ModalPanel
@onready var scroll_container: ScrollContainer = $CenterContainer/ModalPanel/MarginContainer/VBoxContainer/ScrollContainer
@onready var close_header_button: Button = %CloseHeaderButton
@onready var close_footer_button: Button = %CloseFooterButton
@onready var repo_button: Button = %RepoButton
@onready var discord_button: Button = %DiscordModalButton
@onready var base_repo_button: Button = %BaseRepoButton
@onready var donation_feedback_label: Label = %DonationFeedbackLabel
@onready var donation_feedback_panel: PanelContainer = %DonationFeedbackPanel

# Donation Tier Buttons
@onready var donate_1_btn: Button = %Donate1Button
@onready var donate_5_btn: Button = %Donate5Button
@onready var donate_10_btn: Button = %Donate10Button
@onready var donate_50_btn: Button = %Donate50Button
@onready var donate_100_btn: Button = %Donate100Button

var _feedback_tween: Tween = null


func _ready() -> void:
	# Apply Theme Design System
	if modal_panel != null:
		ThemeManager.apply_modal_style(modal_panel, 14)

	# Responsive modal sizing
	var viewport_size = get_viewport().get_visible_rect().size
	var target_width = clamp(viewport_size.x * 0.92, 320.0, 920.0)
	var target_height = clamp(viewport_size.y * 0.92, 280.0, 760.0)
	modal_panel.custom_minimum_size = Vector2(target_width, target_height)

	# Apply touch-friendly scrollbar styling and kinetic swipe scrolling
	if scroll_container != null:
		ThemeManager.apply_scroll_container_style(scroll_container, 28)

	# Style primary and navigation buttons
	ThemeManager.apply_nav_button_style(close_header_button, 6)
	ThemeManager.apply_secondary_button_style(close_footer_button, 8)
	ThemeManager.apply_primary_button_style(repo_button, 8)
	if discord_button != null:
		ThemeManager.apply_primary_button_style(discord_button, 8)
	ThemeManager.apply_secondary_button_style(base_repo_button, 8)

	# Style donation buttons
	_style_donation_button(donate_1_btn)
	_style_donation_button(donate_5_btn)
	_style_donation_button(donate_10_btn)
	_style_donation_button(donate_50_btn)
	_style_donation_button(donate_100_btn)

	# Connect Close signals
	close_header_button.pressed.connect(_on_close_pressed)
	close_footer_button.pressed.connect(_on_close_pressed)

	# Connect Repo and Community links
	repo_button.pressed.connect(_on_repo_pressed)
	if discord_button != null:
		discord_button.pressed.connect(_on_discord_pressed)
	base_repo_button.pressed.connect(_on_base_repo_pressed)

	# Connect Donation buttons
	donate_1_btn.pressed.connect(func(): _on_donate_pressed(1, "Coffee", "Coffee secured! ☕ Energy boosted for late-night golf sim coding!"))
	donate_5_btn.pressed.connect(func(): _on_donate_pressed(5, "Tees", "Tees restocked! 🪵 Peg it high and let it fly!"))
	donate_10_btn.pressed.connect(func(): _on_donate_pressed(10, "Balls", "Fresh dozen balls in the bag! ⚪ Ready to attack the pins (or feed the water hazards)!"))
	donate_50_btn.pressed.connect(func(): _on_donate_pressed(50, "Round of Golf", "18 holes of pure golfing bliss unlocked! 🏌️ Thanks for sponsoring a round!"))
	donate_100_btn.pressed.connect(func(): _on_donate_pressed(100, "New Club", "New club added to the bag! 🏆 Pure golf sim dedication unlocked!"))

	# Connect all RichTextLabels with bbcode links
	_connect_rich_text_links(self)

	# Hide initial donation feedback
	if donation_feedback_panel != null:
		donation_feedback_panel.visible = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# If user clicks outside modal panel on darkened backdrop, close modal
		var mouse_pos = get_global_mouse_position()
		if not modal_panel.get_global_rect().has_point(mouse_pos):
			_on_close_pressed()


func _on_close_pressed() -> void:
	closed.emit()
	queue_free()


func _on_repo_pressed() -> void:
	OS.shell_open("https://github.com/mmancl/HeckleGolfSim")


func _on_discord_pressed() -> void:
	OS.shell_open("https://discord.gg/gjaNhkQwJ")


func _on_base_repo_pressed() -> void:
	OS.shell_open("https://github.com/jhauck2/OpenShotGolf")


func _on_donate_pressed(amount: int, title: String, funny_message: String) -> void:
	if donation_feedback_panel == null or donation_feedback_label == null:
		return

	donation_feedback_label.text = "💚 [$" + str(amount) + " - " + title + "]: " + funny_message + "\n(In-app purchases will be enabled in Google Play Store soon!)"
	donation_feedback_panel.visible = true
	donation_feedback_panel.modulate.a = 0.0

	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()

	_feedback_tween = create_tween()
	_feedback_tween.tween_property(donation_feedback_panel, "modulate:a", 1.0, 0.25)


func _on_meta_clicked(meta) -> void:
	var url = str(meta)
	if url.begins_with("http://") or url.begins_with("https://"):
		OS.shell_open(url)


func _connect_rich_text_links(node: Node) -> void:
	if node is RichTextLabel:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
		node.selection_enabled = false
		if not node.meta_clicked.is_connected(_on_meta_clicked):
			node.meta_clicked.connect(_on_meta_clicked)
	for child in node.get_children():
		_connect_rich_text_links(child)


func _style_donation_button(btn: Button) -> void:
	if btn == null:
		return
	ThemeManager.apply_secondary_button_style(btn, 8)
