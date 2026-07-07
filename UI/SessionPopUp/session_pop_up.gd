extends CenterContainer

var bad_dir_text : String = "This directory does not exist."


signal dir_selected(dir: String, player_name: String)
signal cancelled


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	close()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func open():
	visible = true
	get_tree().paused = true
	$PanelContainer/MarginContainer/VBoxContainer/Label2.visible = false
	$PanelContainer/MarginContainer/VBoxContainer/Label2.text = ""
	
func set_session_data(user, dir):
	$PanelContainer/MarginContainer/VBoxContainer/PlayerName/PlayerNameInput.text = user
	$PanelContainer/MarginContainer/VBoxContainer/Directory/DirectoryInput.text = dir
	
func close():
	visible = false
	get_tree().paused = false

func _on_ok_button_pressed() -> void:
	var dir_text = $PanelContainer/MarginContainer/VBoxContainer/Directory/DirectoryInput.text
	var player_name = $PanelContainer/MarginContainer/VBoxContainer/PlayerName/PlayerNameInput.text
	if DirAccess.dir_exists_absolute(dir_text):
		emit_signal("dir_selected", dir_text, player_name)
		close()
	else:
		$PanelContainer/MarginContainer/VBoxContainer/Label2. visible = true
		$PanelContainer/MarginContainer/VBoxContainer/Label2.text = bad_dir_text

func _on_cancel_button_pressed() -> void:
	emit_signal("cancelled")
	close()
