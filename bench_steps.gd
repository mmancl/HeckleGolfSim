@tool
extends SceneTree

func _init():
    print("=== PROFILING INDIVIDUAL ENHANCE STEPS ===")
    var tscn_path = "user://courses/Westridge_Golf_Course/course.tscn"
    var packed = ResourceLoader.load(tscn_path) as PackedScene
    var inst = packed.instantiate()
    var enhancer = load("res://HighFidelity/Terrain/course_detail_enhancer.gd")
    
    var t0 = Time.get_ticks_msec()
    var height_map = enhancer._build_terrain_height_lookup(inst)
    var t1 = Time.get_ticks_msec()
    print("1. _build_terrain_height_lookup: ", (t1 - t0) / 1000.0, " s")
    
    var t2 = Time.get_ticks_msec()
    enhancer._build_recessed_3d_bunkers(inst, height_map, false)
    var t3 = Time.get_ticks_msec()
    print("2. _build_recessed_3d_bunkers: ", (t3 - t2) / 1000.0, " s")
    
    var t4 = Time.get_ticks_msec()
    enhancer._build_shoreline_reeds(inst, height_map, false)
    var t5 = Time.get_ticks_msec()
    print("3. _build_shoreline_reeds: ", (t5 - t4) / 1000.0, " s")
    
    var t6 = Time.get_ticks_msec()
    enhancer._build_horizon_skirt(inst, height_map, false)
    var t7 = Time.get_ticks_msec()
    print("4. _build_horizon_skirt: ", (t7 - t6) / 1000.0, " s")
    
    var t8 = Time.get_ticks_msec()
    enhancer._build_cart_paths(inst, height_map, false)
    var t9 = Time.get_ticks_msec()
    print("5. _build_cart_paths: ", (t9 - t8) / 1000.0, " s")
    
    var t10 = Time.get_ticks_msec()
    enhancer._build_thick_rough_bushes(inst, height_map, false)
    var t11 = Time.get_ticks_msec()
    print("6. _build_thick_rough_bushes: ", (t11 - t10) / 1000.0, " s")
    
    var t12 = Time.get_ticks_msec()
    enhancer.ensure_deep_rough_map(inst)
    var t13 = Time.get_ticks_msec()
    print("7. ensure_deep_rough_map: ", (t13 - t12) / 1000.0, " s")
    
    inst.free()
    quit()
