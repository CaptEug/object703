extends Panel


var save_dir:String = "res://saves/"


func _ready():
	$WorldName/LineEdit.text = "new world"
	$WorldSeed/LineEdit.text = str(randi())


func _on_generate_button_pressed():
	GameState.world_gen($WorldName/LineEdit.text, $WorldSeed/LineEdit.text)


func world_exists(world_name:String) -> bool:
	var path = save_dir + world_name
	return DirAccess.dir_exists_absolute(path)


func _on_line_edit_text_changed(new_text):
	if new_text == "":
		$Warning.text = ""
		$GenerateButton.disabled = true
	elif world_exists(new_text):
		$Warning.text = "World exists!"
		$GenerateButton.disabled = true
	else:
		$Warning.text = ""
		$GenerateButton.disabled = false
		
