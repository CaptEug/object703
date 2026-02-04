extends FloatingPanel

var mapfolder_path := "res://tilemaps/savedmaps/"

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
	var dir := DirAccess.open(mapfolder_path)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(mapfolder_path)
		return worlds
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".llh"):
				worlds.append(file_name)
		file_name = dir.get_next()
	
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
	
