class_name Tankeditor
extends Block

### CONSTANTS ###
const GRID_SIZE := 16

### EXPORTS ###
@export var factory_size := Vector2i(10, 10)
@export var vehicle_scene: PackedScene = preload("res://vehicles/vehicle.tscn")

### NODE REFERENCES ###
@onready var factory_zone = $FactoryZone
@onready var zone_shape: CollisionShape2D = $FactoryZone/CollisionShape2D
@onready var texture: Sprite2D = $Sprite2D

### BUILD SYSTEM VARIABLES ###
var current_block_scene: PackedScene
var ghost_block: Block
var placed_blocks := {}
var can_build := true
var is_editing_vehicle := false
var is_build_mode := false
var ui_instance: Control
var current_vehicle: Vehicle = null
var original_parent = null
var to_local_offset: Vector2

### INVENTORY SYSTEM ###
var inventory = {
	"rusty_track": 10,
	"kwak45": 10,
	"maybach_hl_250": 10,
	"d_52s":10,
	"zis_57_2":10,
	"fuel_tank":10,
	"cupola":10,
	"ammo_rack":10,
	"tankbuilder":10
}

#-----------------------------------------------------------------------------#
#                           INITIALIZATION FUNCTIONS                          #
#-----------------------------------------------------------------------------#

func _ready():
	super._ready()
	original_parent = parent_vehicle
	init_ui()
	setup_test_inventory()
	setup_factory_zone()
	factory_zone.body_entered.connect(_on_body_entered_factory)
	factory_zone.body_exited.connect(_on_body_exited_factory)

func setup_factory_zone():
	"""Initialize the factory zone collision shape and position"""
	var rect = RectangleShape2D.new()
	rect.size = factory_size * GRID_SIZE
	zone_shape.shape = rect
	factory_zone.position = Vector2.ZERO + Vector2(factory_size * GRID_SIZE)/2
	texture.position = factory_zone.position
	factory_zone.collision_layer = 0
	factory_zone.collision_mask = 1

func init_ui():
	"""Initialize the builder UI"""
	if parent_vehicle != null:
		ui_instance = $"../../CanvasLayer/Tankbuilderui"
	elif get_parent().has_node("CanvasLayer"):
		ui_instance = $"../CanvasLayer/Tankbuilderui"
	else:
		ui_instance = $"../Tankbuilderui"
	if ui_instance != null:
		ui_instance.hide()
		ui_instance.setup_inventory(inventory)
		ui_instance.block_selected.connect(_on_block_selected)
		ui_instance.build_vehicle_requested.connect(_on_build_vehicle_requested)
		ui_instance.vehicle_saved.connect(_on_vehicle_saved)

func setup_test_inventory():
	"""Setup initial inventory for testing"""
	if ui_instance != null:
		ui_instance.update_inventory_display(inventory)

#-----------------------------------------------------------------------------#
#                             PROCESS FUNCTIONS                               #
#-----------------------------------------------------------------------------#

func _process(delta):
	"""Main process loop for handling ghost block and grid updates"""
	if ghost_block and is_build_mode:
		update_ghost_position()
		update_build_indicator()

func _input(event):
	"""Handle input events for build mode and actions"""
	handle_build_mode_toggle(event)
	if not is_build_mode:
		return
	handle_build_actions(event)

#-----------------------------------------------------------------------------#
#                          FACTORY ZONE FUNCTIONS                             #
#-----------------------------------------------------------------------------#

func _on_body_entered_factory(body: Node):
	"""Handle when a body enters the factory zone"""
	if body is Block and body.parent_vehicle:
		var vehicle = body.parent_vehicle
		if not vehicle in get_current_vehicles():
			if not is_build_mode:
				toggle_build_mode()
			current_vehicle = vehicle
			is_editing_vehicle = true
			load_vehicle_for_editing(vehicle)

func _on_body_exited_factory(body: Node):
	"""Handle when a body exits the factory zone"""
	if body is Block and body.parent_vehicle:
		var vehicle = body.parent_vehicle
		print("车辆离开工厂区域: ", vehicle.vehicle_name)

func get_current_vehicles() -> Array:
	"""Get all vehicles currently in the factory zone"""
	var vehicles = []
	for body in factory_zone.get_overlapping_bodies():
		if body is Block and body.parent_vehicle != null:
			var vehicle = body.parent_vehicle
			if vehicle is Vehicle and not vehicle in vehicles:
				vehicles.append(vehicle)
	return vehicles

func find_vehicles_in_factory() -> Array:
	"""Find all vehicles in the factory zone"""
	return get_current_vehicles()

#-----------------------------------------------------------------------------#
#                          BUILD MODE FUNCTIONS                               #
#-----------------------------------------------------------------------------#

func toggle_build_mode():
	"""Toggle build mode on/off"""
	is_build_mode = !is_build_mode
	if is_build_mode:
		var vehicles = find_vehicles_in_factory()
		print(vehicles)
		if vehicles.size() > 0:
			current_vehicle = vehicles[0]
			is_editing_vehicle = true
			load_vehicle_for_editing(current_vehicle)
		else:
			original_parent = parent_vehicle
			is_editing_vehicle = false
			current_vehicle = null
		enter_build_mode()
	else:
		exit_build_mode()

func enter_build_mode():
	"""Enter build mode setup"""
	print("进入建造模式")
	ui_instance.build_vehicle_button.visible = true
	create_ghost_block()
	if is_editing_vehicle:
		ui_instance.set_edit_mode(true, current_vehicle.vehicle_name)
	else:
		ui_instance.set_edit_mode(false)

func exit_build_mode():
	"""Exit build mode cleanup"""
	print("退出建造模式")
	var vehicle_to_update = current_vehicle
	if ghost_block:
		ghost_block.queue_free()
		ghost_block = null
	ui_instance.build_vehicle_button.visible = false
	is_editing_vehicle = false
	if current_vehicle:
		current_vehicle.update_vehicle_size()
	current_vehicle = null

func handle_build_mode_toggle(event):
	"""Handle build mode toggle input (TAB key)"""
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed:
		toggle_build_mode()
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed:
		toggle_codex_ui()

func handle_build_actions(event):
	"""Handle build actions (left/right mouse clicks)"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			remove_block_at_mouse()

func toggle_codex_ui():
	"""Toggle the builder UI visibility"""
	ui_instance.visible = !ui_instance.visible

#-----------------------------------------------------------------------------#
#                          BLOCK PLACEMENT FUNCTIONS                          #
#-----------------------------------------------------------------------------#

func create_ghost_block():
	"""Create a ghost block preview"""
	if not current_block_scene:
		return
		
	if ghost_block is Block:
		ghost_block.collision_layer = 0
		ghost_block.queue_free()
	
	ghost_block = current_block_scene.instantiate()
	configure_ghost_block()
	add_child(ghost_block)

func configure_ghost_block():
	"""Configure ghost block appearance and properties"""
	ghost_block.modulate = Color(1, 1, 1, 0.5)
	for child in ghost_block.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
		if child is RigidBody2D:
			child.freeze = true

func update_ghost_position():
	"""Update ghost block position based on mouse"""
	var mouse_pos = to_local(get_global_mouse_position())
	var snapped_pos = Vector2i(
		floor(mouse_pos.x / GRID_SIZE),
		floor(mouse_pos.y / GRID_SIZE)
	)
	ghost_block.position = Vector2(snapped_pos * GRID_SIZE) + Vector2(ghost_block.size)/2 * GRID_SIZE
	ghost_block.global_grid_pos.clear()
	for x in ghost_block.size.x:
		for y in ghost_block.size.y:
			ghost_block.global_grid_pos.append(snapped_pos + Vector2i(x, y))

func place_block():
	"""Place the current ghost block"""
	if not ghost_block or not can_build:
		return
	
	var block_name = ghost_block.scene_file_path.get_file().get_basename()
	if not inventory.has(block_name) or inventory[block_name] <= 0:
		print("没有足够的", block_name)
		return
		
	var grid_positions = ghost_block.global_grid_pos
	
	# Check if position is occupied
	for pos in grid_positions:
		print(grid_positions, ghost_block)
		if placed_blocks.has(pos):
			print("位置被占用: ", pos)
			return
	
	# If no current vehicle and not in edit mode, create new vehicle
	if not current_vehicle and not is_editing_vehicle:
		current_vehicle = vehicle_scene.instantiate()
		get_parent().add_child(current_vehicle)
		current_vehicle.global_position = factory_zone.position
		is_editing_vehicle = true
		print("创建新车辆")
	
	inventory[block_name] -= 1
	ui_instance.update_inventory_display(inventory)
	
	if inventory[block_name] <= 0:
		inventory.erase(block_name)
		if ghost_block and ghost_block.name == block_name:
			ghost_block.queue_free()
			ghost_block = null
	
	var new_block:Block = current_block_scene.instantiate()
	new_block.position = ghost_block.position
	
	if current_vehicle:
		# Calculate local position relative to vehicle
		var local_pos = current_vehicle.to_local(to_global(ghost_block.position))
		new_block.position = local_pos
		new_block.global_rotation = rotation
		current_vehicle._add_block(new_block, local_pos, grid_positions)	
		# Update grid records
		for pos in grid_positions:
			placed_blocks[pos] = new_block
				
	create_ghost_block()

func remove_block_at_mouse():
	"""Remove block at mouse position"""
	var mouse_pos = to_local(get_global_mouse_position())
	var grid_pos = Vector2i(
		floor(mouse_pos.x / GRID_SIZE),
		floor(mouse_pos.y / GRID_SIZE)
	)
	if placed_blocks.has(grid_pos):
		var block:Block = placed_blocks[grid_pos]
		var block_name = block.scene_file_path.get_file().get_basename()
		
		# Return resources
		if inventory.has(block_name):
			inventory[block_name] += 1
		else:
			inventory[block_name] = 1
		
		ui_instance.update_inventory_display(inventory)
		if is_editing_vehicle and current_vehicle:
			# If in edit mode, remove from vehicle
			current_vehicle.remove_block(block)
			print(block,"已处理")
			# Remove from vehicle grid
			for pos in current_vehicle.grid:
				if current_vehicle.grid[pos] == block:
					current_vehicle.grid.erase(pos)
		else:
			# Otherwise remove from scene directly
			block.queue_free()
		
		# Remove from placement records
		remove_block_from_grid(block, grid_pos)

#-----------------------------------------------------------------------------#
#                          VEHICLE EDITING FUNCTIONS                          #
#-----------------------------------------------------------------------------#

func load_vehicle_for_editing(vehicle: Vehicle):
	"""Load a vehicle for editing in the factory"""
	# 1. Pause physics and reset vehicle rotation
	vehicle.rotation = 0
	
	# 2. Disconnect all physics joints
	for block:Block in vehicle.blocks:
		for child in block.get_children():
			if child is Joint2D:
				child.queue_free()
	
	# 3. Align blocks to grid
	block_to_grid(vehicle)
	
	# 4. Reconnect adjacent blocks
	for block in vehicle.blocks:
		if is_instance_valid(block):
			vehicle.connect_to_adjacent_blocks(block)
	ui_instance.update_inventory_display(inventory)
	ui_instance.set_edit_mode(true, vehicle.vehicle_name)
	create_ghost_block()
	

func block_to_grid(vehicle:Vehicle):
	"""Align vehicle blocks to the factory grid"""
	var original_com := to_local(vehicle.center_of_mass) 
	
	# Process each block's rotation
	for block:Block in vehicle.blocks:
		# Save original global position
		var original_global_pos = to_local(block.global_position) 
		#print(original_global_pos)
		# Calculate vector from center of mass
		var offset_from_com = original_global_pos - original_com
		
		# Reset block rotation
		var original_rotation = block.global_rotation
		block.global_rotation = global_rotation
		
		# Calculate new position after rotation
		var rotated_offset = offset_from_com.rotated(-original_rotation + block.global_rotation)
		block.position = vehicle.to_local(to_global(original_com + rotated_offset)) 
	
	# Move whole vehicle to align center with factory
	vehicle.grid.clear()
	placed_blocks.clear()
	
	# Grid alignment processing
	for block:Block in vehicle.blocks:
		var local_pos = to_local(block.global_position) - Vector2(GRID_SIZE/2, GRID_SIZE/2)*Vector2(block.size)
		var grid_x = roundi(local_pos.x / GRID_SIZE)
		var grid_y = roundi(local_pos.y / GRID_SIZE)
		var grid_pos = Vector2i(grid_x, grid_y)
		for x in block.size.x:
			for y in block.size.y:
				var cell_pos = grid_pos + Vector2i(x, y)
				placed_blocks[cell_pos] = block
				vehicle.grid = placed_blocks
		block.position = current_vehicle.to_local(to_global(Vector2(grid_pos * GRID_SIZE) + Vector2(GRID_SIZE/2, GRID_SIZE/2)*Vector2(block.size)))


#-----------------------------------------------------------------------------#
#                          VEHICLE CREATION FUNCTIONS                         #
#-----------------------------------------------------------------------------#

func begin_vehicle_creation():
	"""Begin creating a new vehicle from placed blocks"""
	if placed_blocks.is_empty():
		print("无法创建空车辆")
		return
	
	# Use existing vehicle if available
	if not current_vehicle:
		current_vehicle = vehicle_scene.instantiate()
		get_parent().add_child(current_vehicle)
		current_vehicle.global_position = factory_zone.position
	
	# Transfer all blocks to vehicle node
	var processed_blocks = []
	for grid_pos in placed_blocks:
		var block = placed_blocks[grid_pos]
		if block in processed_blocks: 
			continue
			
		if block is RigidBody2D:
			block.collision_layer = 1  # Restore normal collision layer
		remove_child(block)
		processed_blocks.append(block)
	
	# Initialize vehicle grid
	current_vehicle.grid = placed_blocks.duplicate()
	
	# Connect all adjacent blocks
	for block in current_vehicle.blocks:
		current_vehicle.connect_to_adjacent_blocks(block)
	
	current_vehicle.Get_ready_again()
	
	if is_instance_valid(ui_instance):
		ui_instance.hide()
	placed_blocks.clear()
	print("车辆生成完成")

#-----------------------------------------------------------------------------#
#                          BLUEPRINT FUNCTIONS                                #
#-----------------------------------------------------------------------------#

func _on_vehicle_saved(vehicle_name: String):
	"""Save vehicle as blueprint"""
	if placed_blocks.is_empty() or not current_vehicle:
		push_error("没有可保存的方块或车辆无效")
		return
	current_vehicle.vehicle_name = vehicle_name
	current_vehicle.calculate_center_of_mass()
	current_vehicle.calculate_balanced_forces()
	current_vehicle.calculate_rotation_forces()
	
	# Generate blueprint data
	var blueprint_data = create_blueprint_data(vehicle_name)
	
	# Determine save path
	var blueprint_path = ""
	if current_vehicle.blueprint != null:
		# Edit mode: Use existing path or generate default
		if current_vehicle.blueprint is String:
			blueprint_path = current_vehicle.blueprint
		elif current_vehicle.blueprint is Dictionary:
			blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	else:
		# New mode: Use new path
		blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	
	# Save blueprint
	if save_blueprint(blueprint_data, blueprint_path):
		# Update vehicle reference
		current_vehicle.blueprint = blueprint_data
		
		# If new mode, restore collision layers
		if not is_editing_vehicle:
			for block:Block in current_vehicle.blocks:
				block.collision_layer = 1
		
		clear_builder()
		toggle_codex_ui()
		toggle_build_mode()
	else:
		push_error("蓝图保存失败")

func create_blueprint_data(vehicle_name: String) -> Dictionary:
	"""Create blueprint data from current vehicle"""
	var blueprint_data = {
		"name": vehicle_name,
		"blocks": {}
	}
	
	var block_counter = 1
	var processed_blocks = {}
	
	# First collect all block base positions
	var base_positions = {}
	var min_x:int
	var min_y:int
	var max_x:int
	var max_y:int
	for grid_pos in placed_blocks:
		min_x = grid_pos.x
		min_y = grid_pos.y
		max_x = grid_pos.x
		max_y = grid_pos.y
		break
	
	# Find bounds of vehicle
	for grid_pos in placed_blocks:
		if min_x > grid_pos.x:
			min_x = grid_pos.x
		if min_y > grid_pos.y:
			min_y = grid_pos.y
		if max_x < grid_pos.x:
			max_x = grid_pos.x
		if max_y < grid_pos.y:
			max_y = grid_pos.y
		
	# Process each block
	for grid_pos in placed_blocks:
		var block = placed_blocks[grid_pos]
		if not processed_blocks.has(block):
			base_positions[block] = grid_pos
			processed_blocks[block] = true
	
	# Process blocks and assign IDs
	processed_blocks.clear()
	for grid_pos in placed_blocks:
		var block:Block = placed_blocks[grid_pos]
		if not processed_blocks.has(block):
			var base_pos = grid_pos
			var rotation_str = get_rotation_direction(block.global_rotation - global_rotation)
			
			blueprint_data["blocks"][str(block_counter)] = {
				"name": block.name,
				"path": block.scene_file_path,
				"base_pos": [base_pos.x - min_x, base_pos.y - min_y],
				"size": [block.size.x, block.size.y],
				"rotation": rotation_str,
			}
			block_counter += 1
			processed_blocks[block] = true
	
	blueprint_data["vehicle_size"] = [max_x - min_x + 1, max_y - min_y + 1]
	return blueprint_data

func get_rotation_direction(angle: float) -> String:
	"""Convert rotation angle to direction string"""
	var normalized = fmod(angle, TAU)
	if abs(normalized) <= PI/4 or abs(normalized) >= 7*PI/4:
		return "up"
	elif normalized >= PI/4 and normalized <= 3*PI/4:
		return "right"
	elif normalized >= 3*PI/4 and normalized <= 5*PI/4:
		return "down"
	else:
		return "left"

func save_blueprint(blueprint_data: Dictionary, save_path: String) -> bool:
	"""Save blueprint data to file"""
	# Ensure directory exists
	var dir = DirAccess.open("res://vehicles/blueprint/")
	if not dir:
		DirAccess.make_dir_absolute("res://vehicles/blueprint/")
	
	# Save file
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(blueprint_data, "\t"))
		file.close()
		print("车辆蓝图已保存到:", save_path)
		return true
	else:
		push_error("文件保存失败:", FileAccess.get_open_error())
		return false

#-----------------------------------------------------------------------------#
#                          UTILITY FUNCTIONS                                  #
#-----------------------------------------------------------------------------#

func update_build_indicator():
	"""Update build indicator based on ghost block position"""
	can_build = is_position_in_factory(ghost_block)
	ghost_block.modulate = Color(1, 1, 1, 0.5) if can_build else Color(1, 0.5, 0.5, 0.3)
	
	# Update button state
	ui_instance.build_vehicle_button.disabled = placed_blocks.is_empty()
	ui_instance.build_vehicle_button.visible = is_build_mode

func is_position_in_factory(block:Block) -> bool:
	"""Check if block is within factory bounds"""
	# Calculate block's top-left world coordinates
	var block_top_left = block.position - Vector2(block.size)/2 * GRID_SIZE
	
	# Calculate block's bottom-right world coordinates
	var block_bottom_right = Vector2((block_top_left.x + block.size.x * GRID_SIZE), (block_top_left.y + block.size.y * GRID_SIZE))
	
	# Factory area bounds
	var factory_top_left = factory_zone.position - Vector2(factory_size)/2 * GRID_SIZE
	var factory_bottom_right = Vector2((factory_top_left.x + factory_size.x * GRID_SIZE), (factory_top_left.y + factory_size.y * GRID_SIZE))
	
	# Check if completely within factory bounds
	return (block_top_left.x >= factory_top_left.x and
			block_top_left.y >= factory_top_left.y and
			block_bottom_right.x <= factory_bottom_right.x and
			block_bottom_right.y <= factory_bottom_right.y)

func is_position_occupied(positions: Array) -> bool:
	"""Check if positions are occupied"""
	for pos in positions:
		if placed_blocks.has(pos):
			return true
	return false

func remove_block_from_grid(block: Node, grid_pos: Vector2i):
	"""Remove block from grid tracking"""
	var positions_to_remove = []
	for pos in placed_blocks:
		if placed_blocks[pos] == block:
			positions_to_remove.append(pos)
	
	for pos in positions_to_remove:
		placed_blocks.erase(pos)
	
	block.queue_free()

func clear_builder():
	"""Clear all placed blocks"""
	for block in get_children():
		if block is RigidBody2D and block != ghost_block:
			block.queue_free()

#-----------------------------------------------------------------------------#
#                          SIGNAL HANDLERS                                    #
#-----------------------------------------------------------------------------#

func _on_block_selected(scene_path: String):
	"""Handle when a block is selected from UI"""
	current_block_scene = load(scene_path)
	create_ghost_block()

func _on_build_vehicle_requested():
	"""Handle build vehicle request from UI"""
	if not is_build_mode: 
		return
		
	if is_editing_vehicle and current_vehicle:
		_on_vehicle_saved(current_vehicle.vehicle_name)
	else:
		begin_vehicle_creation()

func spawn_vehicle_from_blueprint(blueprint: Dictionary):
	"""Spawn vehicle from blueprint data"""
	var vehicle = vehicle_scene.instantiate()
	vehicle.blueprint = blueprint  # Pass dictionary instead of file path
	get_parent().add_child(vehicle)
	clear_builder()
