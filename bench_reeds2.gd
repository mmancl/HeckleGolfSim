@tool
extends SceneTree

func _init():
    var tscn_path = "user://courses/Westridge_Golf_Course/course.tscn"
    var packed = ResourceLoader.load(tscn_path) as PackedScene
    var inst = packed.instantiate()
    var enhancer = load("res://HighFidelity/Terrain/course_detail_enhancer.gd")
    var height_map = enhancer._build_terrain_height_lookup(inst)
    
    # Check cart paths extraction
    var t0 = Time.get_ticks_msec()
    var path_segments = []
    for child in inst.get_children():
        var cname = child.name.to_lower()
        if child is MeshInstance3D and (cname.begins_with("cartpath_") or cname == "cartpaths" or cname.begins_with("cartbridge_")):
            var mi = child as MeshInstance3D
            if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() > 0:
                var arrays = (mi.mesh as ArrayMesh).surface_get_arrays(0)
                if arrays.size() > Mesh.ARRAY_VERTEX:
                    var verts = arrays[Mesh.ARRAY_VERTEX]
                    for i in range(0, verts.size() - 3, 2):
                        var p0 = Vector2((verts[i].x + verts[i + 1].x) * 0.5, (verts[i].z + verts[i + 1].z) * 0.5)
                        var p1 = Vector2((verts[i + 2].x + verts[i + 3].x) * 0.5, (verts[i + 2].z + verts[i + 3].z) * 0.5)
                        var hw = maxf(1.95, verts[i].distance_to(verts[i + 1]) * 0.5 + 0.65)
                        var min_x = minf(p0.x, p1.x) - hw
                        var max_x = maxf(p0.x, p1.x) + hw
                        var min_y = minf(p0.y, p1.y) - hw
                        var max_y = maxf(p0.y, p1.y) + hw
                        path_segments.append({
                            "a": p0, "b": p1, "radius": hw,
                            "aabb": Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
                        })
    var t1 = Time.get_ticks_msec()
    print("Cart paths count=", path_segments.size(), " time=", (t1 - t0) / 1000.0, " s")
    
    # Check is_pt_on_path calls:
    var is_pt_on_path = func(pt: Vector2) -> bool:
        for seg in path_segments:
            var aabb: Rect2 = seg["aabb"]
            if pt.x >= aabb.position.x and pt.x <= aabb.end.x and pt.y >= aabb.position.y and pt.y <= aabb.end.y:
                var a: Vector2 = seg["a"]
                var b: Vector2 = seg["b"]
                var closest := Geometry2D.get_closest_point_to_segment(pt, a, b)
                var r: float = seg["radius"]
                if pt.distance_squared_to(closest) <= r * r:
                    return true
        return false

    var t2 = Time.get_ticks_msec()
    var count = 0
    for k in range(50000):
        if is_pt_on_path.call(Vector2(k * 0.1, k * 0.1)):
            count += 1
    var t3 = Time.get_ticks_msec()
    print("50k is_pt_on_path calls: ", (t3 - t2) / 1000.0, " s")
    
    # Check mm.set_instance_transform loop
    var mm = MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_custom_data = true
    mm.instance_count = 50000
    var t4 = Time.get_ticks_msec()
    var xf = Transform3D.IDENTITY
    var col = Color.WHITE
    for i in range(50000):
        mm.set_instance_transform(i, xf)
        mm.set_instance_custom_data(i, col)
    var t5 = Time.get_ticks_msec()
    print("50k set_instance_transform: ", (t5 - t4) / 1000.0, " s")
    
    inst.free()
    quit()
