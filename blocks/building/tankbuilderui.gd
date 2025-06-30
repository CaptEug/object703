extends Control

signal build_vehicle_requested  # 建造车辆信号
signal block_selected(block_data)

const BLOCK_PATHS = {
	"Firepower": "res://blocks/firepower/",
	"Mobility": "res://blocks/mobility/",
}

@onready var tree = $Tree
@onready var description_textbox = $Panel/RichTextLabel
@onready var inventory_label = $Panel/InventoryLabel  # 新增：背包显示标签

var selected_item:TreeItem
var selected_block:Block
var inventory = {}  # 新增：背包字典，格式为{"block_name": count}

# Called when the node enters the scene tree for the first time.
func _ready():
	prepare_data()
	update_inventory_display()  # 新增：初始化背包显示

# 新增：更新背包显示
func update_inventory_display():
	var text = "Inventory:\n"
	for block_name in inventory:
		text += "%s: %d\n" % [block_name, inventory[block_name]]
	inventory_label.text = text

# 新增：添加物品到背包
func add_to_inventory(block_name: String, amount: int = 1):
	if block_name in inventory:
		inventory[block_name] += amount
	else:
		inventory[block_name] = amount
	update_inventory_display()

# 新增：从背包移除物品
func remove_from_inventory(block_name: String, amount: int = 1) -> bool:
	if block_name in inventory and inventory[block_name] >= amount:
		inventory[block_name] -= amount
		if inventory[block_name] <= 0:
			inventory.erase(block_name)
		update_inventory_display()
		return true
	return false

# 新增：检查背包中是否有足够物品
func has_in_inventory(block_name: String, amount: int = 1) -> bool:
	return block_name in inventory and inventory[block_name] >= amount

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
				block.init()
				# 新增：只在背包中有该方块时才显示
				if has_in_inventory(block.block_name):
					var item = tree.create_item(category_nodes[category])
					item.set_text(0, "%s (%d)" % [block.block_name, inventory[block.block_name]])
					item.set_icon(0, load(block.icons["normal"]))
					item.set_metadata(0, block)
				block.queue_free()

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
			description_textbox.append_text("POWER: "+str(selected_block.POWER)+"hp\n")
