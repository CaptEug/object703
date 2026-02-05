extends FloatingPanel

var save_dir:String = "res://saves/"

@onready var world_list: ItemList = $MarginContainer/Panel/VBoxContainer/WorldList

var world_files: Array[String] = []

func _ready():
	refresh_world_list()
	world_list.add_item("dont_load_this")

func refresh_world_list():
	world_list.clear()
	world_files = scan_worlds()
	for path in world_files:
		var world_name:= path.get_file().get_basename()
		world_list.add_item(world_name)

func scan_worlds() -> Array[String]:
	var worlds: Array[String] = []
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return worlds
	
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			# skip "." and ".."
			if name != "." and name != "..":
				# validate save by header.json
				if FileAccess.file_exists(save_dir + name + "/header.json"):
					worlds.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	return worlds




func _on_back_button_pressed() -> void:
	visible = false


func _on_world_list_item_selected(index: int) -> void:
	$LoadButton.disabled = false


func _on_load_button_pressed() -> void:
	var selected := world_list.get_selected_items()
	if selected.is_empty():
		return
	var idx := selected[0]
	var file := world_files[idx]
	GameState.load_game(file)
	
