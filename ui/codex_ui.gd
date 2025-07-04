extends Control

const BLOCK_PATHS = {
	"Firepower": "res://blocks/firepower/",
	"Mobility": "res://blocks/mobility/",
}

@onready var tree = $Tree
@onready var description_textbox = $Panel/RichTextLabel
var selected_item:TreeItem
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
	
	# block category
	var category_nodes = {}
	for category in BLOCK_PATHS:
		category_nodes[category] = tree.create_item(root)
		category_nodes[category].set_text(0, category)
	
	for category in BLOCK_PATHS:
		for scene in get_scenes_from_folder(BLOCK_PATHS[category]):
			var block = scene.instantiate()
			if block is Block:
				#block.init()
				var item = tree.create_item(category_nodes[category])
				item.set_text(0, block.block_name)
				item.set_icon(0, load(block.icons["normal"]))
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
	var selected = tree.get_selected()
	if selected_item:
		selected_item.set_icon(0, load(selected_block.icons["normal"]))
	if selected.get_metadata(0) is Block:
		if selected_block:
			$Panel/Marker2D.remove_child(selected_block)
		selected_block = selected.get_metadata(0)
		$Panel/Marker2D.add_child(selected_block)
		selected_item = tree.get_selected()
		selected_item.set_icon(0, load(selected_block.icons["selected"]))
		
		description_textbox.clear()
		description_textbox.append_text(selected_block.BLOCK_NAME+"\n\n")
		description_textbox.append_text("HITPOINT: "+str(selected_block.HITPOINT)+"\n")
		description_textbox.append_text("WEIGHT: "+str(selected_block.WEIGHT)+"kg\n")
		
		if selected_block is Weapon:
			description_textbox.append_text("Fire rate: "+str(60/selected_block.RELOAD)+"rpm\n")
		
		if selected_block is Powerpack:
			description_textbox.append_text("POWER: "+str(selected_block.MAX_POWER)+"hp\n")
