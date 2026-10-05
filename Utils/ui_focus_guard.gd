extends Node
## UIFocusGuard — Centralized input-context / focus-lock system.
##
## Prevents directional navigation (arrow keys, analog stick, D-pad) from
## "bleeding" to other UI elements when the user is interacting with a
## nested control such as an OptionButton popup, a Slider, a SpinBox, or a
## modal overlay.
##
## HOW IT WORKS
## ────────────
## 1. This script sits at the TOP of the input chain (_input, not
##    _unhandled_input) so it can intercept events before Godot's built-in
##    GUI focus system propagates them.
##
## 2. It monitors for open OptionButton popups using a signal-based
##    approach that works even with `embed_subwindows = false` (native OS
##    popup windows).  When a popup opens, directional input is suppressed
##    until the popup closes.
##
## 3. When a Range (HSlider, VSlider, SpinBox internal slider) has focus,
##    left/right input is consumed (the Range already handles it internally
##    via Godot's built-in GUI) so it doesn't also jump focus to a
##    neighbouring control.
##
## 4. Provides a manual push/pop focus_lock API so that any scene can call
##    UIFocusGuard.push_lock(node) / UIFocusGuard.pop_lock() to restrict
##    all navigation to descendants of `node` while the lock is active.
##
## SETUP
## ─────
## Register as autoload in project.godot AFTER KeybindingManager and
## GlobalSettings.

const LOG_PREFIX := "[UIFocusGuard]"

## Currently open OptionButton popup state.
var _option_popup_open: bool = false
var _active_option_button: OptionButton = null

## Stack of focus-lock contexts. Each entry:
##   { "root": Node, "prev_focus": Control }
var _lock_stack: Array[Dictionary] = []

## Timer to periodically discover new OptionButtons in the tree.
var _scan_timer: float = 0.0

## Controller repeat timing for dropdown popups to prevent skipping items.
const DROPDOWN_INITIAL_REPEAT_DELAY := 0.42
const DROPDOWN_REPEAT_INTERVAL := 0.20
var _last_dropdown_nav_time: float = 0.0
var _dropdown_press_start_time: float = 0.0
var _dropdown_stick_neutral: bool = true
var _last_tracked_dropdown_idx: int = -1
const SCAN_INTERVAL: float = 0.5

const SLIDER_REPEAT_INTERVAL := 0.08
var _last_slider_nav_time: float = 0.0

## Set of OptionButton instance IDs we've already hooked signals onto.
var _hooked_option_buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Hook any OptionButtons already in the tree.
	_scan_and_hook_option_buttons()
	var vp := get_viewport()
	if vp != null and not vp.gui_focus_changed.is_connected(_on_gui_focus_changed):
		vp.gui_focus_changed.connect(_on_gui_focus_changed)


func _process(delta: float) -> void:
	# Periodically scan for new OptionButtons added dynamically.
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL:
		_scan_timer = 0.0
		_scan_and_hook_option_buttons()

	_validate_option_popup_state()


# ── PUBLIC API ─────────────────────────────────────────────────────────

## Whether an OptionButton dropdown is currently open.
func is_dropdown_open() -> bool:
	_validate_option_popup_state()
	return _option_popup_open


## Push a focus lock — all directional navigation will be confined to
## descendants of `root_node` until pop_lock() is called or the user
## presses ui_cancel.
func push_lock(root_node: Node) -> bool:
	if root_node == null or not is_instance_valid(root_node):
		return false
	var vp := get_viewport()
	var prev_focus: Control = null
	if vp != null:
		prev_focus = vp.gui_get_focus_owner()
	_lock_stack.push_back({
		"root": root_node,
		"prev_focus": prev_focus
	})
	return true


## Pop the most recent focus lock and restore focus.
func pop_lock(restore_focus: bool = true) -> void:
	if _lock_stack.is_empty():
		return
	var entry: Dictionary = _lock_stack.pop_back()
	var root: Node = entry.get("root") as Node
	if root != null and is_instance_valid(root):
		if root.has_method("_on_focus_lock_popped"):
			root._on_focus_lock_popped()
		elif root.has_meta("on_focus_lock_popped"):
			var cb = root.get_meta("on_focus_lock_popped")
			if cb is Callable and cb.is_valid():
				cb.call()
	if restore_focus:
		var prev: Control = entry.get("prev_focus") as Control
		if prev != null and is_instance_valid(prev) and prev.is_visible_in_tree():
			prev.call_deferred("grab_focus")


## Returns `true` when any focus lock is active.
func is_locked() -> bool:
	_prune_invalid_locks()
	return not _lock_stack.is_empty()


## Returns the root of the current (topmost) lock, or null.
func current_lock_root() -> Node:
	_prune_invalid_locks()
	if _lock_stack.is_empty():
		return null
	return _lock_stack.back()["root"]


# ── CORE INPUT INTERCEPTION ────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# Always validate dropdown popup state so stale open flags never swallow input
	_validate_option_popup_state()

	# Release stick neutral tracking when analog stick returns near center (< 0.25)
	if event is InputEventJoypadMotion and abs(event.axis_value) < 0.25:
		_dropdown_stick_neutral = true
		_dropdown_press_start_time = 0.0

	var is_motion: bool = (event is InputEventJoypadMotion and abs((event as InputEventJoypadMotion).axis_value) >= 0.5)
	if not event.is_pressed() and not is_motion:
		return

	var is_directional: bool = _is_directional(event)
	var is_cancel: bool = event.is_action_pressed("ui_cancel")

	# ── 1.  OptionButton popup guard & controller navigation ──────
	if _option_popup_open:
		var popup: PopupMenu = _active_option_button.get_popup() if (_active_option_button != null and is_instance_valid(_active_option_button)) else null

		if is_cancel or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed):
			# Close the popup cleanly and restore focus.
			_close_active_popup()
			get_viewport().set_input_as_handled()
			if popup is Viewport:
				popup.set_input_as_handled()
			return

		if popup != null and is_instance_valid(popup) and popup.visible and popup.item_count > 0:
			var is_stick_down: bool = (event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y and event.axis_value >= 0.5)
			var is_stick_up: bool = (event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y and event.axis_value <= -0.5)
			var is_btn_down: bool = event.is_action_pressed("ui_down") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_DPAD_DOWN and event.pressed)
			var is_btn_up: bool = event.is_action_pressed("ui_up") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_DPAD_UP and event.pressed)

			var is_headless: bool = (DisplayServer.get_name() == "headless")

			# Handle analog stick or D-pad navigation
			if is_stick_down or is_stick_up or is_btn_down or is_btn_up:
				var now := Time.get_ticks_msec() / 1000.0
				var repeat_limit := DROPDOWN_REPEAT_INTERVAL
				if _dropdown_stick_neutral:
					repeat_limit = DROPDOWN_INITIAL_REPEAT_DELAY
					_dropdown_stick_neutral = false
				if (now - _last_dropdown_nav_time) < repeat_limit:
					get_viewport().set_input_as_handled()
					if popup is Viewport:
						popup.set_input_as_handled()
					return
				_last_dropdown_nav_time = now

				var dir := 1 if (is_stick_down or is_btn_down) else -1
				var cur := popup.get_focused_item()
				if cur < 0:
					cur = _last_tracked_dropdown_idx
				if cur < 0 and _active_option_button != null:
					cur = _active_option_button.selected
				var next_idx := _get_next_selectable_popup_item(popup, cur, dir)
				_last_tracked_dropdown_idx = next_idx
				popup.set_focused_item(next_idx)
				get_viewport().set_input_as_handled()
				if popup is Viewport:
					popup.set_input_as_handled()
				return
			elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or \
				(event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X and abs(event.axis_value) >= 0.5):
				get_viewport().set_input_as_handled()
				if popup is Viewport:
					popup.set_input_as_handled()
				return
			elif event.is_action_pressed("ui_accept") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A and event.pressed):
				var focused_idx := popup.get_focused_item()
				if focused_idx < 0:
					focused_idx = _last_tracked_dropdown_idx
				if focused_idx < 0 and _active_option_button != null:
					focused_idx = _active_option_button.selected
				if focused_idx >= 0 and focused_idx < popup.item_count:
					if not popup.is_item_disabled(focused_idx) and not popup.is_item_separator(focused_idx):
						if popup.has_method("activate_item"):
							popup.activate_item(focused_idx)
						if _active_option_button != null and is_instance_valid(_active_option_button):
							_active_option_button.select(focused_idx)
							_active_option_button.item_selected.emit(focused_idx)
						popup.hide()
						_option_popup_open = false
						_active_option_button = null
						_last_tracked_dropdown_idx = -1
						get_viewport().set_input_as_handled()
						if popup is Viewport:
							popup.set_input_as_handled()
						return

		if is_directional:
			get_viewport().set_input_as_handled()
			if popup is Viewport:
				popup.set_input_as_handled()
			return
		return

	var vp := get_viewport()

	# ── 2.  3D Gameplay Aim vs HUD Focus Release ──────────────────
	# In 3D gameplay (Course Play / Driving Range), D-pad is for aiming the ball.
	# If a HUD button has focus from previous controller/analog stick navigation,
	# pressing any aim input (D-pad or arrow key) or cancel releases HUD focus so
	# Godot GUI doesn't swallow D-pad for UI focus navigation, and ball aiming works immediately.
	if vp != null and _is_in_3d_gameplay() and not _option_popup_open and _lock_stack.is_empty():
		var focused := vp.gui_get_focus_owner()
		if focused != null and is_instance_valid(focused) and focused.is_visible_in_tree():
			var in_modal := _is_control_in_modal(focused)
			var in_editor := focused is LineEdit or focused is TextEdit or focused is Range or (focused.get_parent() != null and is_instance_valid(focused.get_parent()) and focused.get_parent() is SpinBox)
			if not in_modal and not in_editor:
				if _is_aim_input(event):
					vp.gui_release_focus()
					# Do not mark handled: let the event fall through to _unhandled_input so aim executes immediately!
				elif is_cancel or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed):
					vp.gui_release_focus()
					get_viewport().set_input_as_handled()
					return

	# ── 3.  Range / Slider / SpinBox guard ────────────────────────
	if vp != null and is_directional:
		var focused := vp.gui_get_focus_owner()
		if focused != null and is_instance_valid(focused):
			var effective_ctrl := focused
			# SpinBox wraps a LineEdit; check parent.
			if focused is LineEdit and focused.get_parent() != null and is_instance_valid(focused.get_parent()) and focused.get_parent() is SpinBox:
				effective_ctrl = focused.get_parent()

			if effective_ctrl is Range:
				var rng := effective_ctrl as Range
				var step_val := rng.step
				if is_zero_approx(step_val):
					step_val = (rng.max_value - rng.min_value) / 20.0
					if is_zero_approx(step_val):
						step_val = 1.0

				var now := Time.get_ticks_msec() / 1000.0
				var is_vslider: bool = (effective_ctrl is VSlider)
				var is_up: bool = event.is_action_pressed("ui_up") or (event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y and event.axis_value <= -0.5)
				var is_down: bool = event.is_action_pressed("ui_down") or (event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y and event.axis_value >= 0.5)
				var is_left: bool = event.is_action_pressed("ui_left") or (event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X and event.axis_value <= -0.5)
				var is_right: bool = event.is_action_pressed("ui_right") or (event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X and event.axis_value >= 0.5)

				if is_vslider:
					if is_up or is_down:
						if event is InputEventJoypadMotion and (now - _last_slider_nav_time) < SLIDER_REPEAT_INTERVAL:
							get_viewport().set_input_as_handled()
							return
						_last_slider_nav_time = now
						var delta_val = step_val if is_up else -step_val
						rng.value = clampf(rng.value + delta_val, rng.min_value, rng.max_value)
						rng.value_changed.emit(rng.value)
						get_viewport().set_input_as_handled()
						return
				else:
					if is_left or is_right:
						if event is InputEventJoypadMotion and (now - _last_slider_nav_time) < SLIDER_REPEAT_INTERVAL:
							get_viewport().set_input_as_handled()
							return
						_last_slider_nav_time = now
						var delta_val = step_val if is_right else -step_val
						rng.value = clampf(rng.value + delta_val, rng.min_value, rng.max_value)
						rng.value_changed.emit(rng.value)
						get_viewport().set_input_as_handled()
						return

	# ── 3.  Manual focus-lock guard ───────────────────────────────
	_prune_invalid_locks()
	if not _lock_stack.is_empty():
		var lock_root: Node = _lock_stack.back()["root"]

		if is_cancel:
			pop_lock(true)
			get_viewport().set_input_as_handled()
			return

		if is_directional or event.is_action_pressed("ui_accept"):
			if vp != null:
				var cur_focus := vp.gui_get_focus_owner()
				if cur_focus == null or not lock_root.is_ancestor_of(cur_focus):
					var focused_ok := _focus_first_control(lock_root)
					if focused_ok:
						get_viewport().set_input_as_handled()
						return
					else:
						# Lock root has no interactive controls; pop stale lock
						pop_lock(false)


# ── OPTION BUTTON SIGNAL HOOKING ───────────────────────────────────────

## Scan the full scene tree for OptionButtons and hook popup signals.
func _scan_and_hook_option_buttons() -> void:
	var root := get_tree().root
	if root == null:
		return
	_hook_option_buttons_recursive(root)


func _hook_option_buttons_recursive(node: Node) -> void:
	if node is OptionButton:
		var opt := node as OptionButton
		var iid := opt.get_instance_id()
		if not _hooked_option_buttons.has(iid):
			_hook_option_button(opt)
			_hooked_option_buttons[iid] = true

	for child in node.get_children():
		_hook_option_buttons_recursive(child)


func _hook_option_button(opt: OptionButton) -> void:
	# The OptionButton's internal PopupMenu has visibility_changed and
	# id_pressed signals we can use to track open/close state.
	var popup := opt.get_popup()
	if popup == null:
		return

	# Use a lambda that captures the OptionButton reference.
	# visibility_changed fires when the popup shows AND hides.
	if not popup.visibility_changed.is_connected(_on_popup_visibility_changed):
		popup.visibility_changed.connect(_on_popup_visibility_changed.bind(opt, popup))

	# Also handle the OptionButton being freed.
	if not opt.tree_exiting.is_connected(_on_option_button_exiting):
		opt.tree_exiting.connect(_on_option_button_exiting.bind(opt))


func _on_popup_visibility_changed(opt: OptionButton, popup: PopupMenu) -> void:
	if popup == null or not is_instance_valid(popup):
		_option_popup_open = false
		_active_option_button = null
		_last_tracked_dropdown_idx = -1
		return

	if popup.visible:
		# Popup just opened.
		_option_popup_open = true
		_active_option_button = opt
		_dropdown_stick_neutral = true
		_dropdown_press_start_time = 0.0
		_last_dropdown_nav_time = 0.0
		if opt != null and is_instance_valid(opt) and popup.item_count > 0:
			var init_idx = opt.selected if (opt.selected >= 0 and opt.selected < popup.item_count) else 0
			_last_tracked_dropdown_idx = init_idx
			popup.set_focused_item(init_idx)
	else:
		# Popup just closed — restore focus to the OptionButton.
		_option_popup_open = false
		_active_option_button = null
		_last_tracked_dropdown_idx = -1
		if opt != null and is_instance_valid(opt) and opt.is_inside_tree() and opt.is_visible_in_tree():
			opt.call_deferred("grab_focus")


func _on_option_button_exiting(opt: OptionButton) -> void:
	var iid := opt.get_instance_id()
	_hooked_option_buttons.erase(iid)
	if _active_option_button == opt:
		_option_popup_open = false
		_active_option_button = null


func _close_active_popup() -> void:
	_option_popup_open = false
	var opt := _active_option_button
	_active_option_button = null
	_last_tracked_dropdown_idx = -1
	if opt != null and is_instance_valid(opt):
		var popup := opt.get_popup()
		if popup != null and is_instance_valid(popup) and popup.visible:
			popup.hide()
		if is_instance_valid(opt) and opt.is_inside_tree() and opt.is_visible_in_tree():
			opt.call_deferred("grab_focus")


func _validate_option_popup_state() -> void:
	if not _option_popup_open:
		return
	if _active_option_button == null or not is_instance_valid(_active_option_button):
		_option_popup_open = false
		_active_option_button = null
		_last_tracked_dropdown_idx = -1
		return
	var popup: PopupMenu = _active_option_button.get_popup()
	if popup == null or not is_instance_valid(popup) or not popup.visible:
		_option_popup_open = false
		_active_option_button = null
		_last_tracked_dropdown_idx = -1


# ── HELPERS ────────────────────────────────────────────────────────────

func _prune_invalid_locks() -> void:
	var i := _lock_stack.size() - 1
	while i >= 0:
		var root = _lock_stack[i].get("root")
		if root == null or not is_instance_valid(root):
			_lock_stack.remove_at(i)
		elif root is Node and not (root as Node).is_inside_tree():
			_lock_stack.remove_at(i)
		elif root is Control and not (root as Control).is_visible_in_tree():
			_lock_stack.remove_at(i)
		elif root is Window and not (root as Window).visible:
			_lock_stack.remove_at(i)
		elif root is CanvasLayer and "visible" in root and not root.visible:
			_lock_stack.remove_at(i)
		i -= 1


func _is_directional(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
		or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		return true
	if event is InputEventJoypadMotion and abs(event.axis_value) >= 0.5:
		return event.is_action("ui_up") or event.is_action("ui_down") \
			or event.is_action("ui_left") or event.is_action("ui_right")
	return false


func _get_next_selectable_popup_item(popup: PopupMenu, from_idx: int, dir: int) -> int:
	var count := popup.item_count
	if count <= 0:
		return -1
	var start := clampi(from_idx, 0, count - 1)
	var cur := start + dir
	while cur >= 0 and cur < count:
		if not popup.is_item_separator(cur) and not popup.is_item_disabled(cur):
			return cur
		cur += dir
	return start


func _is_control_in_modal(ctrl: Node) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	var cur: Node = ctrl
	var root: Node = get_tree().root if get_tree() != null else null
	while cur != null and is_instance_valid(cur) and cur != root:
		if cur is Popup or cur is AcceptDialog or cur is ConfirmationDialog or cur is Window:
			return true
		var c_name := str(cur.name).to_lower()
		if c_name.contains("modal") or c_name.contains("dialog") or c_name.contains("popup") \
			or c_name == "distancemenu" or c_name == "settingslayer" or c_name == "settingsmodallayer" \
			or c_name == "scorecardpanel" or c_name == "manageplayerspanel" \
			or c_name == "placeballbutton" or c_name == "prevholebutton" or c_name == "nextholebutton":
			return true
		if not cur.is_inside_tree():
			break
		cur = cur.get_parent()
	return false


func _on_gui_focus_changed(new_focus: Control) -> void:
	if new_focus == null or _option_popup_open:
		return
	_prune_invalid_locks()
	if not _lock_stack.is_empty():
		var lock_root: Node = _lock_stack.back()["root"]
		if lock_root != null and is_instance_valid(lock_root):
			if not lock_root.is_ancestor_of(new_focus) and new_focus != lock_root:
				call_deferred("_restore_lock_focus", lock_root)


func _restore_lock_focus(lock_root: Node) -> void:
	if lock_root != null and is_instance_valid(lock_root) and is_locked() and current_lock_root() == lock_root:
		var vp := get_viewport()
		if vp != null:
			var cur := vp.gui_get_focus_owner()
			if cur == null or (not lock_root.is_ancestor_of(cur) and cur != lock_root):
				_focus_first_control(lock_root)


static func _focus_first_control(root: Node) -> bool:
	if root == null:
		return false
	if root is Control:
		var c = root as Control
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE:
			if c is Button or c is OptionButton or c is LineEdit or c is Range or c is ItemList or c is CheckBox or c is CheckButton:
				c.grab_focus()
				return true
	for child in root.get_children():
		if child is Control and not (child as Control).is_visible_in_tree():
			continue
		if _focus_first_control(child):
			return true
	return false


func _is_in_3d_gameplay() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var cur_scene := tree.current_scene
	if cur_scene == null:
		return false
	var scene_name := str(cur_scene.name).to_lower()
	var path: String = ""
	if cur_scene.get_script() != null:
		path = str(cur_scene.get_script().resource_path).to_lower()

	# Menu screens, setup screens, creators, or dialogs are never 3D gameplay
	if scene_name.contains("setup") or path.contains("setup") or \
	   scene_name.contains("menu") or path.contains("menu") or \
	   scene_name.contains("dialog") or path.contains("dialog") or \
	   scene_name.contains("creator") or path.contains("creator"):
		return false

	if scene_name == "courseplay" or scene_name == "range" or scene_name == "coursemanager":
		return true
	if path.ends_with("course_play.gd") or path.ends_with("range.gd"):
		return true
	return false


func _is_aim_input(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return false
	if event is InputEventJoypadButton:
		var btn: int = event.button_index
		if (btn == JOY_BUTTON_DPAD_UP or btn == JOY_BUTTON_DPAD_DOWN or
			btn == JOY_BUTTON_DPAD_LEFT or btn == JOY_BUTTON_DPAD_RIGHT):
			return true
	if event is InputEventKey:
		var kc: Key = event.keycode
		if kc == KEY_NONE:
			kc = event.physical_keycode
		if kc == KEY_LEFT or kc == KEY_RIGHT or kc == KEY_UP or kc == KEY_DOWN:
			return true
	if event.is_action("aim_left") or event.is_action("aim_right") or \
	   event.is_action("aim_forward") or event.is_action("aim_backward"):
		return true
	return false
