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
const SCAN_INTERVAL: float = 0.5

## Set of OptionButton instance IDs we've already hooked signals onto.
var _hooked_option_buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Hook any OptionButtons already in the tree.
	_scan_and_hook_option_buttons()


func _process(delta: float) -> void:
	# Periodically scan for new OptionButtons added dynamically.
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL:
		_scan_timer = 0.0
		_scan_and_hook_option_buttons()

	# Safety: clear stale popup state if the OptionButton was freed.
	if _option_popup_open:
		if _active_option_button == null or not is_instance_valid(_active_option_button):
			_option_popup_open = false
			_active_option_button = null


# ── PUBLIC API ─────────────────────────────────────────────────────────

## Whether an OptionButton dropdown is currently open.
func is_dropdown_open() -> bool:
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
	if root != null and is_instance_valid(root) and root.has_method("_on_focus_lock_popped"):
		root._on_focus_lock_popped()
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
	if not event.is_pressed():
		return

	var is_directional := _is_directional(event)
	var is_cancel := event.is_action_pressed("ui_cancel")

	# ── 1.  OptionButton popup guard ──────────────────────────────
	if _option_popup_open:
		if is_directional:
			# Suppress all directional input globally while a dropdown
			# is open.  The popup itself (whether embedded or native OS
			# window) handles up/down internally; we just prevent the
			# event from also moving focus on controls behind the popup.
			get_viewport().set_input_as_handled()
			return
		if is_cancel:
			# Close the popup cleanly and restore focus.
			_close_active_popup()
			get_viewport().set_input_as_handled()
			return
		# Let accept and other events through for the popup.
		return

	var vp := get_viewport()

	# ── 2.  Range / Slider / SpinBox guard ────────────────────────
	if vp != null and is_directional:
		var focused := vp.gui_get_focus_owner()
		if focused != null:
			var effective_ctrl := focused
			# SpinBox wraps a LineEdit; check parent.
			if focused is LineEdit and focused.get_parent() is SpinBox:
				effective_ctrl = focused.get_parent()

			if effective_ctrl is Range:
				if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
					# The Range already adjusts its value via built-in
					# GUI handling; consume the event so it doesn't ALSO
					# move focus laterally.
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
					KeybindingManager.focus_first_control(lock_root)
					get_viewport().set_input_as_handled()
					return


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
		return

	if popup.visible:
		# Popup just opened.
		_option_popup_open = true
		_active_option_button = opt
	else:
		# Popup just closed — restore focus to the OptionButton.
		_option_popup_open = false
		_active_option_button = null
		if opt != null and is_instance_valid(opt) and opt.is_visible_in_tree():
			opt.call_deferred("grab_focus")


func _on_option_button_exiting(opt: OptionButton) -> void:
	var iid := opt.get_instance_id()
	_hooked_option_buttons.erase(iid)
	if _active_option_button == opt:
		_option_popup_open = false
		_active_option_button = null


func _close_active_popup() -> void:
	if _active_option_button != null and is_instance_valid(_active_option_button):
		var popup := _active_option_button.get_popup()
		if popup != null and is_instance_valid(popup) and popup.visible:
			popup.hide()
		# _on_popup_visibility_changed will handle the rest.


# ── HELPERS ────────────────────────────────────────────────────────────

func _prune_invalid_locks() -> void:
	var i := _lock_stack.size() - 1
	while i >= 0:
		var root = _lock_stack[i].get("root")
		if root == null or not is_instance_valid(root):
			_lock_stack.remove_at(i)
		elif root is Control and not (root as Control).is_visible_in_tree():
			_lock_stack.remove_at(i)
		elif root is CanvasLayer and "visible" in root and not root.visible:
			_lock_stack.remove_at(i)
		i -= 1


func _is_directional(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
		or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")
