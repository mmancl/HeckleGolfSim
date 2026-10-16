extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: OSM Multi-Course Support & Sub-Course Holes")
	print("=======================================================")

	# 1. Test OsmMapLoader.ExtractSubCourseName
	var loader_script = load("res://Courses/OsmMapLoader.cs")
	assert(loader_script != null, "OsmMapLoader.cs must load")
	
	var loader = loader_script.new()
	assert(loader != null, "OsmMapLoader instance must be created")
	
	# Test ExtractSubCourseName with different tags via reflection / C# invocation
	assert(loader.ExtractSubCourseName({"golf:course:name": "Red"}) == "Red", "ExtractSubCourseName should read golf:course:name")
	assert(loader.ExtractSubCourseName({"course:name": "White"}) == "White", "ExtractSubCourseName should read course:name")
	assert(loader.ExtractSubCourseName({"golf:course": "Blue"}) == "Blue", "ExtractSubCourseName should read golf:course")
	assert(loader.ExtractSubCourseName({"course": "Gold"}) == "Gold", "ExtractSubCourseName should read course")
	assert(loader.ExtractSubCourseName({}) == "", "ExtractSubCourseName should return empty string if no course tag")
	print("  PASS: ExtractSubCourseName tag parsing verified.")

	# 2. Test generation of each route and every distinct OSM-defined relation.
	var elements: Array = []
	var course_ids := {}
	var next_way_id := 1000
	for sub_course in ["Blue", "Red", "White"]:
		course_ids[sub_course] = []
		for hole_num in range(1, 10):
			course_ids[sub_course].append(next_way_id)
			elements.append({
				"type": "way",
				"id": next_way_id,
				"nodes": [next_way_id * 10, next_way_id * 10 + 1],
				"tags": {
					"golf": "hole",
					"golf:course:name": sub_course,
					"ref": str(hole_num)
				}
			})
			next_way_id += 1
	var pair_relations = [
		{"id": 2000, "name": "Blue/White Course", "first": "Blue", "second": "White"},
		{"id": 2001, "name": "White/Blue Course", "first": "White", "second": "Blue"},
		{"id": 2002, "name": "Blue/Red Course", "first": "Blue", "second": "Red"},
		{"id": 2003, "name": "Red/Blue Course", "first": "Red", "second": "Blue"},
		{"id": 2004, "name": "Red/White Course", "first": "Red", "second": "White"},
		{"id": 2005, "name": "White/Red Course", "first": "White", "second": "Red"}
	]
	for relation in pair_relations:
		var members: Array = []
		for sub_course in [relation["first"], relation["second"]]:
			for way_id in course_ids[sub_course]:
				members.append({"type": "way", "ref": way_id, "role": ""})
		if relation["name"] == "Red/Blue Course":
			# OSM may have stray member ways; the explicit relation name identifies the intended pair.
			members.append({"type": "way", "ref": course_ids["White"][0], "role": ""})
		elements.append({
			"type": "relation",
			"id": relation["id"],
			"tags": {
				"golf": "course",
				"golf:course": "18_hole",
				"name": relation["name"]
			},
			"members": members
		})

	var variant_plan = loader.GetCourseVariantPlan(JSON.stringify({"elements": elements}), "Mid Vallee")
	assert(variant_plan.size() == 9, "Three nine-hole routes and six defined relations must produce nine variants")
	var single_count := 0
	var pair_count := 0
	var planned_singles := {}
	var planned_pairs := {}
	for variant in variant_plan:
		if variant["variant_type"] == "9-hole":
			single_count += 1
			assert(variant["hole_count"] == 9, "Each route variant must contain 9 holes")
			planned_singles[variant["sub_courses"][0]] = true
		elif variant["variant_type"] == "18-hole":
			pair_count += 1
			assert(variant["hole_count"] == 18, "Each paired variant must contain 18 holes")
			var pair_key = variant["sub_courses"][0] + "|" + variant["sub_courses"][1]
			planned_pairs[pair_key] = variant["osm_relation_id"]
	assert(single_count == 3 and pair_count == 6, "Each distinct OSM relation must produce its own 18-hole course")
	assert(planned_singles.has("Blue") and planned_singles.has("Red") and planned_singles.has("White"), "Each named nine-hole route must be included")
	assert(planned_pairs.has("Blue|White") and planned_pairs.has("White|Blue"), "Both Blue/White relation orientations must be included")
	assert(planned_pairs.has("Blue|Red") and planned_pairs.has("Red|Blue"), "Both Blue/Red relation orientations must be included")
	assert(planned_pairs.has("Red|White") and planned_pairs.has("White|Red"), "Both Red/White relation orientations must be included")
	assert(planned_pairs["Blue|White"] == "2000" and planned_pairs["White|Blue"] == "2001", "Inverse pairings must retain distinct relation IDs")
	assert(planned_pairs["Red|Blue"] == "2003", "Relation names must select their ordered route pair despite stray members")
	assert(planned_pairs["Blue|Red"] == "2002" and planned_pairs["Red|White"] == "2004" and planned_pairs["White|Red"] == "2005", "Every ordered relation must map to its own variant")
	print("  PASS: Every distinct OSM relation, including inverse pair order, produces a separate variant.")

	# 3. Test OsmDownloadDialog hole filtering with multi-course (27-hole) courses
	var dialog_scene = load("res://Courses/OsmDownloadDialog/osm_download_dialog.tscn")
	assert(dialog_scene != null, "osm_download_dialog.tscn must load")
	var dialog = dialog_scene.instantiate()
	root.add_child(dialog)

	var sample_courses = [
		{"name": "Regulation 9", "hole_count": 9},
		{"name": "Regulation 18", "hole_count": 18},
		{"name": "Mid Vallee 27", "hole_count": 27},
		{"name": "Resort 36", "hole_count": 36}
	]

	# Test with 18-hole enabled, 9-hole disabled
	dialog.btn_9_hole.button_pressed = false
	dialog.btn_18_hole.button_pressed = true
	dialog.btn_all_holes.button_pressed = false
	var filtered_18 = dialog._filter_by_hole_settings(sample_courses)
	var names_18 = filtered_18.map(func(c): return c["name"])
	assert(names_18.has("Regulation 18"), "18-hole course must be included")
	assert(names_18.has("Mid Vallee 27"), "27-hole multi-course must be included in 18-hole filter")
	assert(names_18.has("Resort 36"), "36-hole multi-course must be included in 18-hole filter")
	assert(!names_18.has("Regulation 9"), "9-hole course must be excluded when only 18-hole is enabled")
	print("  PASS: 18-hole filter includes multi-course facilities (27 & 36 holes).")

	dialog._display_courses_in_list([{"name": "Mid Vallee 27", "hole_count": 27.0}], true)
	assert(dialog.results_list.get_item_text(0).contains("27 Holes"), "Integer hole counts must display without a decimal suffix")
	assert(!dialog.results_list.get_item_text(0).contains("27.0 Holes"), "Hole-count display must not show decimal formatting")
	print("  PASS: Decimal-valued hole counts display as whole numbers.")

	# Test with 9-hole enabled, 18-hole disabled
	dialog.btn_9_hole.button_pressed = true
	dialog.btn_18_hole.button_pressed = false
	dialog.btn_all_holes.button_pressed = false
	var filtered_9 = dialog._filter_by_hole_settings(sample_courses)
	var names_9 = filtered_9.map(func(c): return c["name"])
	assert(names_9.has("Regulation 9"), "9-hole course must be included")
	assert(names_9.has("Mid Vallee 27"), "27-hole multi-course (divisible by 9) must be included in 9-hole filter")
	assert(names_9.has("Resort 36"), "36-hole multi-course (divisible by 9) must be included in 9-hole filter")
	assert(!names_9.has("Regulation 18"), "18-hole course must be excluded when only 9-hole is enabled")
	print("  PASS: 9-hole filter includes multi-course facilities (27 & 36 holes).")

	# Test with both 9 and 18 enabled
	dialog.btn_9_hole.button_pressed = true
	dialog.btn_18_hole.button_pressed = true
	dialog.btn_all_holes.button_pressed = false
	var filtered_both = dialog._filter_by_hole_settings(sample_courses)
	assert(filtered_both.size() == 4, "Both 9 and 18 enabled must include all sample courses")
	print("  PASS: Both 9 and 18 enabled includes all multi-course and regulation courses.")

	loader.free()
	dialog.queue_free()

	print("\nALL OSM MULTI-COURSE TESTS PASSED! 🎉\n")
	quit(0)
	return false
