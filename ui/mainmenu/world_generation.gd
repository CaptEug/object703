extends Panel


var save_dir:String = "res://saves/"


func _ready():
	$WorldName/LineEdit.text = "new world"
	$WorldSeed/LineEdit.text = str(randi())
	check_world_name($WorldName/LineEdit.text)


func _on_generate_button_pressed():
	GameState.world_gen($WorldName/LineEdit.text, $WorldSeed/LineEdit.text)


func check_world_name(world_name:String):
	if world_name == "":
		$Warning.text = ""
		$GenerateButton.disabled = true
	elif DirAccess.dir_exists_absolute(save_dir + world_name):
		$Warning.text = "World exists!"
		$GenerateButton.disabled = true
	else:
		$Warning.text = ""
		$GenerateButton.disabled = false


func _on_line_edit_text_changed(new_text):
	check_world_name(new_text)
		
