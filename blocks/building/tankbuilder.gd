class_name Tankeditor
extends Block

### CONSTANTS ###
const GRID_SIZE := 16

### EXPORTS ###
@export var factory_size := Vector2i(100000, 100000)
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
var is_recycle_mode := false
var ui_instance: Control
var current_vehicle: Vehicle = null
var original_parent = null
var to_local_offset: Vector2
var ghost_rotation := 0

### CONNECTION SNAP SYSTEM ###
var hovered_connection_point: ConnectionPoint = null
var is_snapped_to_connection := false
var snap_offset := Vector2.ZERO
var ghost_connection_point: ConnectionPoint = null

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
	"tankbuilder":10,
	"pike_armor":10,
	"armor":10,
	"small_cargo":10,
	"turret3x3":10
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
	
	# Connect UI signals
	if ui_instance:
		ui_instance.recycle_mode_toggled.connect(_on_recycle_mode_toggled)

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
		ui_instance.vehicle_saved.connect(_on_vehicle_saved)

func setup_test_inventory():
	"""Setup initial inventory for testing"""
	if ui_instance != null:
		ui_instance.update_inventory_display(inventory)

#-----------------------------------------------------------------------------#
#                             PROCESS FUNCTIONS                               #
#-----------------------------------------------------------------------------#

func _process(_delta):
	"""Main process loop for handling ghost block and connection points"""
	if ghost_block and is_build_mode and not is_recycle_mode:
		check_nearby_connection_points()
		update_ghost_position()
		update_build_indicator()

func _input(event):
	"""Handle input events for build mode and actions"""
	handle_build_mode_toggle(event)
	if not is_build_mode:
		return
	handle_build_actions(event)
	handle_rotation_input(event)
	
	# 添加取消选择功能
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		if ghost_block:
			ghost_block.queue_free()
			ghost_block = null
			current_block_scene = null
			print("取消选择方块")

#-----------------------------------------------------------------------------#
#                          CONNECTION POINT SYSTEM                            #
#-----------------------------------------------------------------------------#

func check_nearby_connection_points():
	"""检查附近的连接点并尝试吸附"""
	if not ghost_block or is_recycle_mode:
		return
	
	hovered_connection_point = null
	is_snapped_to_connection = false
	ghost_connection_point = null
	
	# 获取幽灵方块的所有连接点
	var ghost_points = ghost_block.connection_points
	if ghost_points.is_empty():
		return
	
	# 找到所有可用的连接点
	var available_points = []
	for vehicle in get_current_vehicles():
		for block in vehicle.blocks:
			for point in block.connection_points:
				if point.is_connection_enabled and not point.connected_to:
					available_points.append(point)
	
	if available_points.is_empty():
		return
	
	# 找到最佳匹配的连接点对
	var best_match = find_best_connection_match(ghost_points, available_points)
	if best_match:
		hovered_connection_point = best_match.target_point
		ghost_connection_point = best_match.ghost_point
		is_snapped_to_connection = true
		
		# 计算旋转对齐
		var parent_block = hovered_connection_point.find_parent_block()
		if parent_block:
			var target_rotation = parent_block.global_rotation
			ghost_block.global_rotation = target_rotation
			ghost_rotation = round(target_rotation / (PI/2)) * (PI/2)

func find_best_connection_match(ghost_points: Array, available_points: Array):
	"""找到最佳的连接点匹配"""
	var best_match = null
	var min_distance = INF
	
	for ghost_point in ghost_points:
		for target_point in available_points:
			# 检查连接类型是否匹配
			if ghost_point.connection_type != target_point.connection_type:
				continue
			
			# 计算距离
			var ghost_global_pos = ghost_point.global_position
			var target_global_pos = target_point.global_position
			var distance = ghost_global_pos.distance_to(target_global_pos)
			
			# 检查是否在连接范围内
			if distance <= target_point.connection_range:
				if distance < min_distance:
					min_distance = distance
					best_match = {
						"ghost_point": ghost_point,
						"target_point": target_point,
						"distance": distance
					}
	if best_match != null:
		print(best_match)
		return best_match

#-----------------------------------------------------------------------------#
#                          GHOST BLOCK FUNCTIONS                              #
#-----------------------------------------------------------------------------#

func create_ghost_block():
	"""Create a ghost block preview"""
	if not current_block_scene or is_recycle_mode:
		return
		
	if ghost_block is Block:
		ghost_block.queue_free()
	
	ghost_block = current_block_scene.instantiate()
	ghost_rotation = 0
	ghost_block.collision_layer = 0
	ghost_block.collision_mask = 0
	configure_ghost_block()
	add_child(ghost_block)

func configure_ghost_block():
	"""Configure ghost block appearance and properties"""
	ghost_block.modulate = Color(1, 1, 1, 0.5)
	# 禁用所有碰撞形状
	for child in ghost_block.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", true)
		if child is RigidBody2D:
			child.freeze = true

func update_ghost_position():
	"""Update ghost block position based on mouse and connection points"""
	if not ghost_block:
		return
	
	var mouse_pos = get_global_mouse_position()
	
	if is_snapped_to_connection and hovered_connection_point and ghost_connection_point:
		# 吸附到连接点模式
		var target_global_pos = hovered_connection_point.global_position
		var ghost_local_pos = ghost_connection_point.position
		var ghost_global_offset = ghost_block.to_global(ghost_local_pos) - ghost_block.global_position
		
		# 计算精确位置
		ghost_block.global_position = target_global_pos - ghost_global_offset
	else:
		# 自由放置模式
		ghost_block.global_position = mouse_pos

func update_build_indicator():
	"""Update build indicator based on connection state"""
	if not ghost_block:
		return
	
	var in_factory = is_position_in_factory(ghost_block)
	
	# 检查是否可以建造（有连接点或在编辑模式中）
	can_build = (is_snapped_to_connection or is_editing_vehicle) and in_factory
	
	# 设置颜色反馈
	if is_snapped_to_connection:
		ghost_block.modulate = Color(0.5, 1, 0.5, 0.7)  # 绿色表示可以连接
	elif can_build:
		ghost_block.modulate = Color(1, 1, 1, 0.5)      # 半透明表示可以建造
	else:
		ghost_block.modulate = Color(1, 0.5, 0.5, 0.3)  # 红色表示不能建造

#-----------------------------------------------------------------------------#
#                          BLOCK PLACEMENT FUNCTIONS                          #
#-----------------------------------------------------------------------------#

func place_block():
	"""Place the current ghost block with connection point system"""
	if not ghost_block or not can_build or is_recycle_mode:
		return
	
	# 检查是否悬空建造（没有连接到任何东西）
	if not is_editing_vehicle and not is_snapped_to_connection:
		print("不能悬空建造 - 必须连接到现有方块")
		return
	
	var block_name = ghost_block.scene_file_path.get_file().get_basename()
	if not inventory.has(block_name) or inventory[block_name] <= 0:
		print("没有足够的", block_name)
		return
	
	# 资源消耗
	inventory[block_name] -= 1
	ui_instance.update_inventory_display(inventory)
	
	if inventory[block_name] <= 0:
		inventory.erase(block_name)
		if ghost_block and ghost_block.name == block_name:
			ghost_block.queue_free()
			ghost_block = null
			return
	
	# 创建新方块
	var new_block: Block = current_block_scene.instantiate()
	new_block.global_position = ghost_block.global_position
	new_block.global_rotation = ghost_block.global_rotation
	new_block.rotation_to_parent = ghost_block.rotation_to_parent
	
	# 如果没有当前车辆，创建新车辆
	if not current_vehicle and not is_editing_vehicle:
		current_vehicle = vehicle_scene.instantiate()
		get_parent().add_child(current_vehicle)
		current_vehicle.global_position = factory_zone.position
		is_editing_vehicle = true
		print("创建新车辆")
	
	if current_vehicle:
		# 添加到车辆
		var local_pos = current_vehicle.to_local(new_block.global_position)
		new_block.position = local_pos
		
		# 计算网格位置（用于车辆网格系统）
		var grid_positions = calculate_grid_positions(new_block)
		current_vehicle._add_block(new_block, local_pos, grid_positions)
		
		# 如果吸附到连接点，创建物理连接
		if is_snapped_to_connection and hovered_connection_point:
			create_connection(new_block)
		
		# 更新放置记录
		for pos in grid_positions:
			placed_blocks[pos] = new_block
	
	# 重新创建幽灵方块
	create_ghost_block()

func calculate_grid_positions(block: Block) -> Array:
	"""计算方块占据的网格位置"""
	var positions = []
	var block_global_pos = block.global_position
	var block_local_pos = to_local(block_global_pos)
	
	var base_x = int(block_local_pos.x / GRID_SIZE)
	var base_y = int(block_local_pos.y / GRID_SIZE)
	
	for x in range(block.size.x):
		for y in range(block.size.y):
			positions.append(Vector2i(base_x + x, base_y + y))
	
	return positions

func create_connection(new_block: Block):
	"""创建方块之间的连接"""
	if not hovered_connection_point or not ghost_connection_point:
		return
	
	# 找到新方块上的对应连接点
	var new_block_point = null
	for point in new_block.connection_points:
		if point.name == ghost_connection_point.name:
			new_block_point = point
			break
	
	if new_block_point:
		# 尝试建立连接
		hovered_connection_point.try_connect(new_block_point)

func rotate_ghost_block(angle: float):
	"""Rotate the ghost block by specified angle"""
	if not ghost_block or is_recycle_mode:
		return
	
	ghost_rotation += angle
	ghost_block.rotation = ghost_rotation * PI * 0.5 
	ghost_block.rotation_to_parent = ghost_rotation * PI * 0.5
	
	# 重新检查连接点
	check_nearby_connection_points()
	update_ghost_position()

#-----------------------------------------------------------------------------#
#                          INPUT HANDLING FUNCTIONS                           #
#-----------------------------------------------------------------------------#

func handle_build_mode_toggle(event):
	"""Handle build mode toggle input (TAB key)"""
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed:
		toggle_build_mode()

func handle_build_actions(event):
	"""Handle build actions (left/right mouse clicks)"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_recycle_mode:
				remove_block_at_mouse()
			else:
				place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not is_recycle_mode:
			rotate_ghost_block(1)  # Right click rotates clockwise

func handle_rotation_input(event):
	"""Handle rotation input for ghost block"""
	if not ghost_block or is_recycle_mode:
		return
	
	# 使用键盘快捷键旋转
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q:
				rotate_ghost_block(-1)  # 逆时针
			KEY_E:
				rotate_ghost_block(1)   # 顺时针
			KEY_R:
				ghost_rotation = 0
				ghost_block.rotation = 0
				ghost_block.rotation_to_parent = 0
				check_nearby_connection_points()
				update_ghost_position()

#-----------------------------------------------------------------------------#
#                          RECYCLE MODE FUNCTIONS                             #
#-----------------------------------------------------------------------------#

func _on_recycle_mode_toggled(is_active: bool):
	"""Handle recycle mode toggle from UI"""
	is_recycle_mode = is_active
	if is_recycle_mode:
		print("进入回收模式")
		if ghost_block:
			ghost_block.queue_free()
			ghost_block = null
	else:
		print("退出回收模式")
		create_ghost_block()

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
	toggle_codex_ui()
	ui_instance.build_vehicle_button.visible = true
	if not is_recycle_mode:
		create_ghost_block()

func exit_build_mode():
	"""Exit build mode cleanup"""
	print("退出建造模式")
	is_recycle_mode = false
	if ghost_block:
		ghost_block.queue_free()
		ghost_block = null
	ui_instance.build_vehicle_button.visible = false
	is_editing_vehicle = false
	if current_vehicle:
		current_vehicle.update_vehicle_size()
	current_vehicle = null

func toggle_codex_ui():
	"""Toggle the builder UI visibility"""
	ui_instance.visible = !ui_instance.visible

#-----------------------------------------------------------------------------#
#                          VEHICLE EDITING FUNCTIONS                          #
#-----------------------------------------------------------------------------#

func load_vehicle_for_editing(vehicle: Vehicle):
	"""Load a vehicle for editing in the factory"""
	# 1. Pause physics and reset vehicle rotation
	vehicle.rotation = 0
	
	# 3. Align blocks to grid
	block_to_grid(vehicle)
	
	# 4. Reconnect adjacent blocks
	for block:Block in vehicle.blocks:
		if is_instance_valid(block):
			block.set_connection_enabled(true)
			block.is_movable_on_connection = true
	ui_instance.update_inventory_display(inventory)
	if not is_recycle_mode:
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
		var original_rotation = block.global_rotation - block.rotation_to_parent
		block.global_rotation = global_rotation + block.rotation_to_parent
		# Calculate new position after rotation
		var rotated_offset = offset_from_com.rotated(-original_rotation + global_rotation)
		block.position = vehicle.to_local(to_global(original_com + rotated_offset)) 

	# Move whole vehicle to align center with factory
	vehicle.grid.clear()
	placed_blocks.clear()
	
	# Grid alignment processing
	for block:Block in vehicle.blocks:
		var local_pos = to_local(block.global_position) - Vector2(GRID_SIZE, GRID_SIZE)/2*Vector2(block.size)
		var grid_x = roundi(local_pos.x / GRID_SIZE)
		var grid_y = roundi(local_pos.y / GRID_SIZE)
		var grid_pos = Vector2i(grid_x, grid_y)
		for x in block.size.x:
			for y in block.size.y:
				var cell_pos = grid_pos + Vector2i(x, y)
				placed_blocks[cell_pos] = block
				vehicle.grid = placed_blocks
		block.position = current_vehicle.to_local(to_global(Vector2(grid_pos * GRID_SIZE) + Vector2(GRID_SIZE, GRID_SIZE)/2*Vector2(block.size)))

#-----------------------------------------------------------------------------#
#                          BLOCK REMOVAL FUNCTIONS                            #
#-----------------------------------------------------------------------------#

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
		remove_block_from_grid(block)

func remove_block_from_grid(block: Node):
	"""Remove block from grid tracking"""
	var positions_to_remove = []
	for pos in placed_blocks:
		if placed_blocks[pos] == block:
			positions_to_remove.append(pos)
	
	for pos in positions_to_remove:
		placed_blocks.erase(pos)
	
	block.queue_free()

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
	for block:Block in current_vehicle.blocks:
		block.set_connection_enabled(false)
	
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
				"name": block.block_name,
				"path": block.scene_file_path,
				"base_pos": [base_pos.x - min_x, base_pos.y - min_y],
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

func is_position_in_factory(block: Block) -> bool:
	"""Check if block is within factory bounds"""
	var block_global_pos = block.global_position
	var factory_global_pos = factory_zone.global_position
	var factory_half_size = Vector2(factory_size) * GRID_SIZE / 2
	
	var in_x = abs(block_global_pos.x - factory_global_pos.x) <= factory_half_size.x
	var in_y = abs(block_global_pos.y - factory_global_pos.y) <= factory_half_size.y
	
	return in_x and in_y

func is_position_occupied(positions: Array) -> bool:
	"""Check if positions are occupied"""
	for pos in positions:
		if placed_blocks.has(pos):
			return true
	return false

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
	if not is_recycle_mode:
		create_ghost_block()
		
		# 显示提示信息
		var scene = load(scene_path)
		var block = scene.instantiate()
		print("已选择: " + block.block_name)
		block.queue_free()

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
