extends Control

@onready var tree = $Tree

# Called when the node enters the scene tree for the first time.
func _ready():

	prepare_data()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func prepare_data():
	var root = tree.create_item()
	root.set_text(0, "Blocks")
	
	# block type
	var weapon = tree.create_item(root)
	weapon.set_text(0, "Weapon")
	var power = tree.create_item(root)
	power.set_text(0, "Power")
	
	for scene in get_scenes_from_folder("res://blocks/weapon/"):
		var block = scene.instantiate()
		var item = tree.create_item(weapon)
		item.set_text(0, block.BLOCK_NAME)
	
	for scene in get_scenes_from_folder("res://blocks/power/"):
		var block = scene.instantiate()
		var item = tree.create_item(power)
		item.set_text(0, block.BLOCK_NAME)
		item.set_icon(0, preload("res://assets/engine_icon.png"))
		
func get_scenes_from_folder(folder_path: String) -> Array:
	var scenes = []
	var dir = DirAccess.open(folder_path)
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tscn"):
				var path = folder_path + "/" + file
				scenes.append(load(path))
	return scenes
