extends Control

@onready var item_list = $ItemList
@onready var description_label = $Panel/RichTextLabel
@onready var build_vehicle_button = $BuildButton

signal build_vehicle_requested
signal block_selected(scene_path: String)

const BLOCK_PATHS = {
	"Weapon": "res://blocks/firepower/",
	"Power": "res://blocks/mobility/"
}

var inventory = {}

func _ready():
	build_vehicle_button.pressed.connect(_on_build_vehicle_pressed)
	item_list.item_selected.connect(_on_item_selected)

func setup_inventory(initial_inventory: Dictionary):
	inventory = initial_inventory.duplicate()
	update_inventory_display(inventory)

func update_inventory_display(current_inventory: Dictionary):
	item_list.clear()
	item_list.max_columns = 0
	item_list.icon_mode = ItemList.ICON_MODE_TOP
	item_list.fixed_column_width = 100
	item_list.fixed_icon_size = Vector2(64, 64)
	
	for category in BLOCK_PATHS:
		# 添加分类标题
		var category_idx = item_list.add_item(category)
		item_list.set_item_selectable(category_idx, false)
		
		# 扫描文件夹
		var dir = DirAccess.open(BLOCK_PATHS[category])
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".tscn"):
					var block_basename = file_name.get_basename()
					if current_inventory.has(block_basename) and current_inventory[block_basename] > 0:
						var scene_path = BLOCK_PATHS[category] + file_name
						var scene = load(scene_path)
						var block = scene.instantiate()
						if block:
							var idx = item_list.add_item("%s (%d)" % [block.block_name, current_inventory[block_basename]])
							item_list.set_item_icon(idx, block.get_icon_texture())
							item_list.set_item_metadata(idx, scene_path)
							block.queue_free()
				file_name = dir.get_next()

func _on_item_selected(index: int):
	var scene_path = item_list.get_item_metadata(index)
	if scene_path:
		emit_signal("block_selected", scene_path)
		update_description(scene_path)

func update_description(scene_path: String):
	var scene = load(scene_path)
	var block = scene.instantiate()
	if block:
		description_label.clear()
		description_label.append_text("[b]%s[/b]\n\n" % block.name)
		description_label.append_text("TYPE: %s\n" % block._get_block_type())
		description_label.append_text("SIZE: %s\n" % str(block.size))
		block.queue_free()

func _on_build_vehicle_pressed():
	emit_signal("build_vehicle_requested")
