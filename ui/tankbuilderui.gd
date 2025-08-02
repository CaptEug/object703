extends Control

@onready var tab_container = $TabContainer
@onready var description_label = $Panel/RichTextLabel
@onready var build_vehicle_button = $Panel/SaveButton
@onready var save_dialog = $SaveDialog
@onready var name_input = $Panel/NameInput
@onready var error_label = $SaveDialog/ErrorLabel

signal build_vehicle_requested
signal block_selected(scene_path: String)
signal vehicle_saved(vehicle_name: String)


const BLOCK_PATHS = {
	"Firepower": "res://blocks/firepower/",
	"Mobility": "res://blocks/mobility/",
	"Command": "res://blocks/command/",
	"Building": "res://blocks/building/",
	"Structual":"res://blocks/structual/"
}

var inventory = {}
var item_lists = {}  # Stores references to all ItemList nodes by tab name

func _ready():
	build_vehicle_button.pressed.connect(_on_build_vehicle_pressed)
	save_dialog.get_ok_button().pressed.connect(_on_save_confirmed)
	save_dialog.close_requested.connect(_on_save_canceled)
	name_input.text_changed.connect(_on_name_input_changed)
	create_tabs()
	
	# Hide save dialog initially
	save_dialog.hide()
	error_label.hide()
	
func create_tabs():
	# Clear existing tabs (except maybe the first one)
	for child in tab_container.get_children():
		child.queue_free()
	
	# Create "All" tab first
	create_tab_with_itemlist("All")
	
	# Create tabs for each category
	for category in BLOCK_PATHS:
		create_tab_with_itemlist(category)
	
	# Connect signals for all item lists
	for tab_name in item_lists:
		item_lists[tab_name].item_selected.connect(_on_item_selected.bind(tab_name))

func create_tab_with_itemlist(tab_name: String):
	var item_list = ItemList.new()
	item_list.name = tab_name
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Configure item list appearance
	item_list.max_columns = 0
	item_list.icon_mode = ItemList.ICON_MODE_TOP
	item_list.fixed_column_width = 100
	item_list.fixed_icon_size = Vector2(64, 64)
	
	tab_container.add_child(item_list)
	item_lists[tab_name] = item_list

func setup_inventory(initial_inventory: Dictionary):
	inventory = initial_inventory.duplicate()
	update_inventory_display(inventory)

func update_inventory_display(current_inventory: Dictionary):
	# Clear all item lists first
	for item_list in item_lists.values():
		item_list.clear()
	
	var all_blocks = []
	var categorized_blocks = {}
	
	# First collect all blocks and organize them by category
	for category in BLOCK_PATHS:
		categorized_blocks[category] = []
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
							# Add to "All" tab
							all_blocks.append({
								"name": block.block_name,
								"count": current_inventory[block_basename],
								"icon": block.get_icon_texture(),
								"path": scene_path
							})
							
							# Add to category tab
							categorized_blocks[category].append({
								"name": block.block_name,
								"count": current_inventory[block_basename],
								"icon": block.get_icon_texture(),
								"path": scene_path
							})
							block.queue_free()
				file_name = dir.get_next()
	
	# Populate "All" tab
	populate_item_list(item_lists["All"], all_blocks)
	
	# Populate category tabs
	for category in categorized_blocks:
		if item_lists.has(category):
			populate_item_list(item_lists[category], categorized_blocks[category])

func populate_item_list(item_list: ItemList, items: Array):
	for item in items:
		var idx = item_list.add_item("%s (%d)" % [item.name, item.count])
		item_list.set_item_icon(idx, item.icon)
		item_list.set_item_metadata(idx, item.path)

func _on_item_selected(index: int, tab_name: String):
	var item_list = item_lists[tab_name]
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
		description_label.append_text("TYPE: %s\n" % block.type)
		description_label.append_text("SIZE: %s\n" % str(block.size))
		block.queue_free()

func _on_build_vehicle_pressed():
	show_save_dialog()

func show_save_dialog():
	error_label.text = ""
	error_label.hide()
	save_dialog.popup_centered()

func _on_save_confirmed():
	var vehicle_name = name_input.text.strip_edges()
	
	if vehicle_name.is_empty():
		error_label.text = "Name cannot be empty!"
		error_label.show()
		return
	
	if vehicle_name.contains("/") or vehicle_name.contains("\\"):
		error_label.text = "The name cannot contain special characters!"
		error_label.show()
		return
	
	emit_signal("vehicle_saved", vehicle_name)
	save_dialog.hide()

func _on_save_canceled():
	save_dialog.hide()

func _on_name_input_changed(new_text: String):
	error_label.hide()
