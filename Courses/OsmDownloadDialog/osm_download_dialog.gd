extends Control

signal course_downloaded(course_name: String)

@onready var search_input: LineEdit = %SearchInput
@onready var search_button: Button = %SearchButton
@onready var results_list: ItemList = %ResultsList
@onready var status_label: Label = %StatusLabel
@onready var cancel_button: Button = %CancelButton
@onready var download_button: Button = %DownloadButton

var _loader: Node = null
var _results: Array = []


func _ready() -> void:
	search_button.pressed.connect(_on_search_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	download_button.pressed.connect(_on_download_pressed)
	results_list.item_selected.connect(_on_item_selected)
	search_input.text_submitted.connect(func(_text): _on_search_pressed())
	
	results_list.clear()
	download_button.disabled = true
	
	var loader_script = load("res://Courses/OsmMapLoader.cs")
	if loader_script != null:
		_loader = loader_script.new()
		add_child(_loader)
	else:
		status_label.text = "Error: Failed to load OsmMapLoader.cs script."
		search_button.disabled = true
		search_input.editable = false


func _on_search_pressed() -> void:
	var query = search_input.text.strip_edges()
	if query.is_empty():
		status_label.text = "Please enter a search query."
		return
		
	status_label.text = "Searching OpenStreetMap for '" + query + "'..."
	_set_ui_disabled(true)
	results_list.clear()
	_results.clear()
	download_button.disabled = true
	
	# Call C# search and await signal
	_loader.SearchGolfCourses(query)
	var results_array = await _loader.SearchCompleted
	
	_set_ui_disabled(false)
	
	if results_array == null or results_array.is_empty():
		status_label.text = "No golf courses found matching '" + query + "'."
		return
		
	_results = results_array
	for item in _results:
		var name_text = item.get("name", "Unnamed Course")
		var loc_text = item.get("location", "")
		var display_text = name_text
		if not loc_text.is_empty():
			display_text += " (" + loc_text + ")"
		results_list.add_item(display_text)
		
	status_label.text = "Found " + str(_results.size()) + " course(s). Select one to download."


func _on_item_selected(_index: int) -> void:
	download_button.disabled = false


func _on_download_pressed() -> void:
	var selected_items = results_list.get_selected_items()
	if selected_items.is_empty():
		return
		
	var idx = selected_items[0]
	if idx < 0 or idx >= _results.size():
		return
		
	var course = _results[idx]
	var course_name = course.get("name", "Unnamed Course")
	var lat = course.get("lat", 0.0)
	var lon = course.get("lon", 0.0)
	
	status_label.text = "Downloading and generating 3D map for '" + course_name + "'..."
	_set_ui_disabled(true)
	download_button.disabled = true
	cancel_button.disabled = true
	
	# Call C# download and generate and await signal
	_loader.DownloadAndGenerateCourse(lat, lon, course_name)
	var success = await _loader.CourseGenerated
	
	if success:
		var msg = ""
		if _loader.has_method("GetGenerationMessage"):
			msg = _loader.GetGenerationMessage()
		if msg != "":
			status_label.text = msg
		else:
			status_label.text = "Successfully generated course: " + course_name + "!"
		course_downloaded.emit(course_name)
		# Wait 1.5 seconds before auto-closing
		await get_tree().create_timer(1.5).timeout
		queue_free()
	else:
		status_label.text = "Error: Failed to download or generate course data."
		_set_ui_disabled(false)
		download_button.disabled = false
		cancel_button.disabled = false


func _on_cancel_pressed() -> void:
	queue_free()


func _set_ui_disabled(disabled: bool) -> void:
	search_input.editable = not disabled
	search_button.disabled = disabled
	results_list.auto_height = false # Keep styling
	# Disable individual items in list during loading if needed, or mouse filtering
	results_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_PASS
