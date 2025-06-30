extends Control

@onready var tree = $Tree
@onready var description_label = $Panel/RichTextLabel
@onready var build_vehicle_button = $Button
signal build_vehicle_requested 

const BLOCK_PATHS = {
	"Weapon": "res://blocks/firepower/",
	"Power": "res://blocks/mobility/",
	#"Armor": "res://blocks/armor/"
}

func _ready():
	setup_block_tree()
	build_vehicle_button.pressed.connect(_on_build_vehicle_pressed)

func setup_block_tree():
	var root = tree.create_item()
	root.set_text(0, "Blocks")
	
	# 创建分类节点
	var category_nodes = {}
	for category in BLOCK_PATHS:
		category_nodes[category] = tree.create_item(root)
		category_nodes[category].set_text(0, category)
	
	# 扫描文件夹
	for category in BLOCK_PATHS:
		var dir = DirAccess.open(BLOCK_PATHS[category])
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".tscn"):
					var scene_path = BLOCK_PATHS[category] + file_name
					var scene = load(scene_path)
					if scene:
						var block = scene.instantiate()
						if block is Block:  # 确保是Block类型
							var item = tree.create_item(category_nodes[category])
							item.set_text(0, block.name)
							if block.get_icon_texture():
								item.set_icon(0, block.get_icon_texture())
							item.set_meta("scene_path", scene_path)
						block.queue_free()
				file_name = dir.get_next()

func _on_tree_item_selected():
	var selected = tree.get_selected()
	if selected and selected.has_meta("scene_path"):
		var scene_path = selected.get_meta("scene_path")
		var scene = load(scene_path)
		if scene:
			var block = scene.instantiate()
			if block is Block:
				update_description(block.get_block_info())
				emit_signal("block_selected", scene_path)
			block.queue_free()

func update_description(info: Dictionary):
	description_label.clear()
	description_label.append_text("[b]%s[/b]\n\n" % info.name)
	description_label.append_text("TYPE: %s\n" % info.type)
	description_label.append_text("HITPOINT: %d\n" % info.hitpoint)
	description_label.append_text("WEIGHT: %.1fkg\n" % info.weight)
	description_label.append_text("SIZE: %s\n" % str(info.size))
	


func _on_build_vehicle_pressed():
	emit_signal("build_vehicle_requested")
