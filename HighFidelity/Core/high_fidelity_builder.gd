extends Node3D
class_name HighFidelityBuilder

## HighFidelityBuilder
## Master coordinator for High-fidelity desktop graphics.
## Dynamically instantiates and configures Forward+ lighting, SDFGI, SSIL,
## instanced 3D grass, and performance telemetry on desktop systems.

const HighFidelityLightingScript = preload("res://HighFidelity/Lighting/high_fidelity_lighting.gd")
const HighFidelityOverlayScript = preload("res://HighFidelity/Core/high_fidelity_overlay.gd")

var overlay_node: CanvasLayer = null

static func is_supported() -> bool:
	return not MobilePerformance.is_mobile()


static func apply_high_fidelity(scene_root: Node) -> Node3D:
	if scene_root == null or not is_supported():
		return null
	
	var existing = scene_root.get_node_or_null("HighFidelityBuilder")
	if existing != null:
		if existing.has_method("refresh"):
			existing.refresh(scene_root)
		return existing
	
	var script = load("res://HighFidelity/Core/high_fidelity_builder.gd") as GDScript
	var builder = script.new() as Node3D
	builder.name = "HighFidelityBuilder"
	scene_root.add_child(builder)
	builder.call("setup", scene_root)
	return builder


static func remove_high_fidelity(scene_root: Node) -> void:
	if scene_root == null:
		return
	
	var existing = scene_root.get_node_or_null("HighFidelityBuilder")
	if existing != null:
		if existing.has_method("teardown"):
			existing.call("teardown", scene_root)
		scene_root.remove_child(existing)
		existing.queue_free()
	else:
		HighFidelityLightingScript.remove(scene_root)


func setup(scene_root: Node) -> void:
	# 1. Apply Forward+ Desktop Lighting, SDFGI, SSIL, PCSS Shadows & AgX Tonemapper
	HighFidelityLightingScript.apply(scene_root)

	# 2. Add Diagnostic Telemetry HUD (toggleable with F3)
	if overlay_node == null:
		overlay_node = HighFidelityOverlayScript.new()
		add_child(overlay_node)


func refresh(scene_root: Node) -> void:
	HighFidelityLightingScript.apply(scene_root)


func teardown(scene_root: Node) -> void:
	HighFidelityLightingScript.remove(scene_root)
	if overlay_node != null:
		overlay_node.queue_free()
		overlay_node = null
