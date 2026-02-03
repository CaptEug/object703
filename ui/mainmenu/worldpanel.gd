extends FloatingPanel

var mapfolder_path := "res://tilemaps/savedmaps/"

@onready var world_list: ItemList = $MarginContainer/Panel/VBoxContainer/WorldList

var world_files: Array[String] = []

func _ready():
	refresh_world_list()
	world_list.add_item("world_namebruh")


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
