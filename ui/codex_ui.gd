extends Control

@onready var tree = $Tree
@onready var description_textbox = $Panel/RichTextLabel
var selected_block:Block


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
		item.set_icon(0, load(block.icon_path))
		item.set_metadata(0, block)
	
	for scene in get_scenes_from_folder("res://blocks/power/"):
		var block = scene.instantiate()
		var item = tree.create_item(power)
		item.set_text(0, block.BLOCK_NAME)
		item.set_icon(0, load(block.icon_path))
		item.set_metadata(0, block)

func get_scenes_from_folder(folder_path: String) -> Array:
	var scenes = []
	var dir = DirAccess.open(folder_path)
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tscn"):
				var path = folder_path + "/" + file
				scenes.append(load(path))
	return scenes

func _on_tree_item_selected():
	var selected = tree.get_selected().get_metadata(0)
	if selected is Block:
		if selected_block:
			$Panel/Marker2D.remove_child(selected_block)
		selected_block = selected
		$Panel/Marker2D.add_child(selected_block)
		
		description_textbox.clear()
		description_textbox.append_text(selected_block.BLOCK_NAME+"\n\n")
		description_textbox.append_text("HITPOINT: "+str(selected_block.HITPOINT)+"\n")
		description_textbox.append_text("WEIGHT: "+str(selected_block.WEIGHT)+"kg\n")
		
		if selected_block is Weapon:
			description_textbox.append_text("Fire rate: "+str(60/selected_block.RELOAD)+"rpm\n")
		
		if selected_block is Powerpack:
			description_textbox.append_text("POWER: "+str(selected_block.POWER)+"hp\n")
