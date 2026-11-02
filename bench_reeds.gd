@tool
extends SceneTree

func _init():
    print("=== PROFILING _build_shoreline_reeds INTERNALS ===")
    var tscn_path = "user://courses/Westridge_Golf_Course/course.tscn"
    var packed = ResourceLoader.load(tscn_path) as PackedScene
    var inst = packed.instantiate()
    var enhancer = load("res://HighFidelity/Terrain/course_detail_enhancer.gd")
    var height_map = enhancer._build_terrain_height_lookup(inst)
    
    # Sub-step A: Finding water bodies
    var t0 = Time.get_ticks_msec()
    var water_children = []
    for child in inst.find_children("*", "CollisionObject3D", true, false):
        var cname = child.name.to_lower()
        if bool(child.get_meta("is_water", false)) or cname.begins_with("water") or cname.contains("water"):
            water_children.append(child)
    var t1 = Time.get_ticks_msec()
    print("A. Find water bodies (count=", water_children.size(), "): ", (t1 - t0) / 1000.0, " s")
    
    # Sub-step B: _extract_boundary_polygon_from_faces for each water body
    var t2 = Time.get_ticks_msec()
    for child in water_children:
        for sub in child.get_children():
            if sub is CollisionShape3D and sub.shape is ConcavePolygonShape3D:
                var faces = sub.shape.get_faces()
                var b = enhancer._extract_boundary_polygon_from_faces(faces, Transform3D.IDENTITY)
                print("   water child ", child.name, " faces=", faces.size(), " boundary=", b.size())
    var t3 = Time.get_ticks_msec()
    print("B. Extract boundary polygons: ", (t3 - t2) / 1000.0, " s")
    
    inst.free()
    quit()
