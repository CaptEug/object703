extends Control

@onready var item_list = $TabContainer/ItemList
@onready var description_label = $Panel/RichTextLabel
@onready var build_vehicle_button = $BuildButton
@onready var tab_container = $TabContainer

signal build_vehicle_requested
signal block_selected(scene_path: String)

const BLOCK_PATHS = {
	"Weapon": "res://blocks/firepower/",
	"Power": "res://blocks/mobility/"
}

var inventory = {}
var current_category = "All"  # Current selected category
var category_buttons = {}     # Stores our category buttons

func _ready():
	build_vehicle_button.pressed.connect(_on_build_vehicle_pressed)
	item_list.item_selected.connect(_on_item_selected)
	
	# Initialize tabs
	_init_tabs()

func _init_tabs():
	# Create "All" button first
	var all_button = Button.new()
	all_button.text = "All"
	all_button.toggle_mode = true
	all_button.button_pressed = true
	all_button.pressed.connect(_on_category_button_pressed.bind("All"))
	tab_container.add_child(all_button)
	category_buttons["All"] = all_button
	
	# Create buttons for each category
	for category in BLOCK_PATHS:
		var button = Button.new()
		button.text = category
		button.toggle_mode = true
		button.pressed.connect(_on_category_button_pressed.bind(category))
		tab_container.add_child(button)
		category_buttons[category] = button

func _on_category_button_pressed(category: String):
	# Deselect all other buttons
	for cat in category_buttons:
		category_buttons[cat].button_pressed = (cat == category)
	
	current_category = category
	update_inventory_display(inventory)

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
		# Skip if not showing all and this isn't the current category
		if current_category != "All" and current_category != category:
			continue
			
		# Scan directory
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
