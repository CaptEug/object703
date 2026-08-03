extends Panel

@onready var world_list: ItemList = $VBoxContainer/WorldList
var world_files: Array[String] = []


func _ready():
	refresh_world_list()


func _process(delta):
	pass


func refresh_world_list():
	world_list.clear()
	$LoadButton.disabled = true
	world_files = scan_worlds()
	for world_folder: String in world_files:
		world_list.add_item(world_folder)


func scan_worlds() -> Array[String]:
	var worlds: Array[String] = []
	var dir := DirAccess.open(GameState.saving_dir)
	if dir == null:
		return worlds
	
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if name != "." and name != "..":
				var validation := GameState.inspect_world(name)
				if validation["ok"]:
					worlds.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	worlds.sort()
	return worlds


func _on_load_button_pressed() -> void:
	var selected := world_list.get_selected_items()
	if selected.is_empty():
		return
	var idx := selected[0]
	var file := world_files[idx]
	var validation := GameState.inspect_world(file)
	if not validation["ok"]:
		refresh_world_list()
		return
	GameState.load_game(file)


func _on_world_list_item_selected(index: int) -> void:
	$LoadButton.disabled = false
