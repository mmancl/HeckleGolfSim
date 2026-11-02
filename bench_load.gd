@tool
extends SceneTree

func _init():
    print("=== PROFILING COURSE LOAD & DETAIL ENHANCER ===")
    var tscn_path = "user://courses/Westridge_Golf_Course/course.tscn"
    var t0 = Time.get_ticks_msec()
    var packed = ResourceLoader.load(tscn_path) as PackedScene
    var t1 = Time.get_ticks_msec()
    print("ResourceLoader.load took: ", (t1 - t0) / 1000.0, " s")
    
    var t2 = Time.get_ticks_msec()
    var inst = packed.instantiate()
    var t3 = Time.get_ticks_msec()
    print("packed.instantiate took: ", (t3 - t2) / 1000.0, " s")
    
    var enhancer = load("res://HighFidelity/Terrain/course_detail_enhancer.gd")
    var t4 = Time.get_ticks_msec()
    print("Running enhance_course_scene...")
    enhancer.enhance_course_scene(inst, false)
    var t5 = Time.get_ticks_msec()
    print("enhance_course_scene took: ", (t5 - t4) / 1000.0, " s")
    
    inst.free()
    quit()
