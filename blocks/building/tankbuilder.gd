class_name Tankeditor
extends Block



# 配置
const GRID_SIZE := 16
@export var factory_size := Vector2i(10, 10)
@onready var factory_zone = $FactoryZone
@onready var zone_shape: CollisionShape2D = $FactoryZone/CollisionShape2D
@onready var texture: Sprite2D = $Sprite2D

@export var vehicle_scene: PackedScene = preload("res://vehicles/vehicle.tscn")
@export var builder_ui: PackedScene = preload("res://ui/tankbuilderUI.tscn")

# 建造系统
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

# 背包系统
var inventory = {
	"rusty_track": 10,
	"kwak45": 10,
	"maybach_hl_250": 10,
	"d_52s":10,
	"zis_57_2":10,
	"fuel_tank":10,
	"cupola":10,
	"ammo_rack":10,
	#"tankbuilder":10
}

func _ready():
	super._ready()
	original_parent = parent_vehicle
	init_ui()
	setup_test_inventory()
	setup_factory_zone()
	factory_zone.body_entered.connect(_on_body_entered_factory)
	factory_zone.body_exited.connect(_on_body_exited_factory)

func setup_factory_zone():
	var rect = RectangleShape2D.new()
	rect.size = factory_size * GRID_SIZE
	zone_shape.shape = rect
	factory_zone.position = Vector2.ZERO + Vector2(factory_size * GRID_SIZE)/2
	texture.position = factory_zone.position
	factory_zone.collision_layer = 0
	factory_zone.collision_mask = 1

func init_ui():
	ui_instance = $"../Tankbuilderui"
	if ui_instance != null:
		ui_instance.hide()
		ui_instance.setup_inventory(inventory)
		ui_instance.block_selected.connect(_on_block_selected)
		ui_instance.build_vehicle_requested.connect(_on_build_vehicle_requested)
		ui_instance.vehicle_saved.connect(_on_vehicle_saved)

	

func setup_test_inventory():
	ui_instance.update_inventory_display(inventory)

func _process(delta):
	if ghost_block and is_build_mode:
		update_ghost_position()
		update_build_indicator()
			
	#if current_vehicle and is_editing_vehicle:
		#block_to_grid(current_vehicle)


func _input(event):
	handle_build_mode_toggle(event)
	if not is_build_mode:
		return
	handle_build_actions(event)

func _on_body_entered_factory(body: Node):
	if body is Block and body.parent_vehicle:
		var vehicle = body.parent_vehicle
		if not vehicle in get_current_vehicles():
			if not is_build_mode:
				toggle_build_mode()
			current_vehicle = vehicle
			is_editing_vehicle = true
			load_vehicle_for_editing(vehicle)
	
func _on_body_exited_factory(body: Node):
	if body is Block and body.parent_vehicle:
		var vehicle = body.parent_vehicle
		print("车辆离开工厂区域: ", vehicle.vehicle_name)

func get_current_vehicles() -> Array:
	var vehicles = []
	for body in factory_zone.get_overlapping_bodies():
		if body is Block and body.parent_vehicle != null:
			var vehicle = body.parent_vehicle
			if vehicle is Vehicle and not vehicle in vehicles:
				vehicles.append(vehicle)
	return vehicles

func find_vehicles_in_factory() -> Array:
	return get_current_vehicles()

func handle_build_mode_toggle(event):
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed:
		toggle_build_mode()
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed:
		toggle_codex_ui()

func handle_build_actions(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			remove_block_at_mouse()

func toggle_build_mode():
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

func load_vehicle_for_editing(vehicle: Vehicle):
	# 1. 暂停物理处理并重置车辆旋转
	vehicle.set_physics_process(false)
	vehicle.rotation = 0
	
	# 2. 断开所有物理连接
	for block:Block in vehicle.blocks:
		for child in block.get_children():
			if child is Joint2D:
				child.queue_free()
	
	# 3. 计算车辆原始质心（世界坐标）
	block_to_grid(vehicle)
	
	for block in vehicle.blocks:
		if is_instance_valid(block):
			vehicle.connect_to_adjacent_blocks(block)
	ui_instance.update_inventory_display(inventory)
	ui_instance.set_edit_mode(true, vehicle.vehicle_name)
	create_ghost_block()
	# 10. 恢复物理处理
	vehicle.set_physics_process(true)


func block_to_grid(vehicle:Vehicle):
	var original_com := to_local(vehicle.calculate_center_of_mass()) 
	print(vehicle.calculate_center_of_mass())
	
	# 4. 逐块处理旋转（保持原始位置，仅校正旋转）
	for block:Block in vehicle.blocks:
		# 保存原始全局位置
		var original_global_pos = to_local(block.global_position) 
		#print(original_global_pos)
		# 计算方块相对质心的向量
		var offset_from_com = original_global_pos - original_com
		
		# 重置方块旋转（清除之前任何旋转）
		var original_rotation = block.global_rotation
		block.global_rotation = global_rotation
		
		# 计算旋转后的新位置（保持相对质心距离）
		var rotated_offset = offset_from_com.rotated(-original_rotation + block.global_rotation)
		block.position = vehicle.to_local(to_global(original_com + rotated_offset)) 
	
	# 6. 移动整个车辆使质心对齐工厂中心
	vehicle.grid.clear()
	placed_blocks.clear()
	# 7. [新增] 网格对齐处理
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
	#


	
func update_editor_state(vehicle: Vehicle):
	placed_blocks.clear()
	for grid_pos in vehicle.grid:
		placed_blocks[grid_pos] = vehicle.grid[grid_pos]
	
	ui_instance.update_inventory_display(inventory)
	ui_instance.set_edit_mode(true, vehicle.vehicle_name)




func enter_build_mode():
	print("进入建造模式")
	ui_instance.build_vehicle_button.visible = true
	create_ghost_block()
	if is_editing_vehicle:
		ui_instance.set_edit_mode(true, current_vehicle.vehicle_name)
	else:
		ui_instance.set_edit_mode(false)

func exit_build_mode():
	print("退出建造模式")
	if ghost_block:
		ghost_block.queue_free()
		ghost_block = null
	ui_instance.build_vehicle_button.visible = false
	is_editing_vehicle = false
	current_vehicle = null
	placed_blocks.clear()

func toggle_codex_ui():
	ui_instance.visible = !ui_instance.visible

func create_ghost_block():
	if not current_block_scene:
		return
		
	if ghost_block is Block:
		ghost_block.collision_layer = 0
		ghost_block.queue_free()
	
	ghost_block = current_block_scene.instantiate()
	configure_ghost_block()
	add_child(ghost_block)

func configure_ghost_block():
	ghost_block.modulate = Color(1, 1, 1, 0.5)
	for child in ghost_block.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
		if child is RigidBody2D:
			child.freeze = true

func update_ghost_position():
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
	if not ghost_block or not can_build:
		return
	
	var block_name = ghost_block.scene_file_path.get_file().get_basename()
	if not inventory.has(block_name) or inventory[block_name] <= 0:
		print("没有足够的", block_name)
		return
		
	var grid_positions = ghost_block.global_grid_pos
	
	# 检查位置是否被占用
	for pos in grid_positions:
		print(grid_positions, ghost_block)
		if placed_blocks.has(pos):
			print("位置被占用: ", pos)
			return
	
	# 如果没有当前车辆且不在编辑模式，创建新车辆
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
		# 计算相对于车辆的局部位置
		var local_pos = current_vehicle.to_local(to_global(ghost_block.position))
		new_block.position = local_pos
		new_block.global_rotation = rotation
		
		current_vehicle._add_block(new_block)
		
		# 更新网格记录
		for pos in grid_positions:
			current_vehicle.grid[pos] = new_block
			placed_blocks[pos] = new_block
		# 自动连接相邻方块
		current_vehicle.connect_to_adjacent_blocks(new_block)
	
	create_ghost_block()

func remove_block_at_mouse():
	var mouse_pos = to_local(get_global_mouse_position())
	var grid_pos = Vector2i(
		floor(mouse_pos.x / GRID_SIZE),
		floor(mouse_pos.y / GRID_SIZE)
	)
	if placed_blocks.has(grid_pos):
		var block:Block = placed_blocks[grid_pos]
		var block_name = block.scene_file_path.get_file().get_basename()
		
		# 返还资源
		if inventory.has(block_name):
			inventory[block_name] += 1
		else:
			inventory[block_name] = 1
		
		
		ui_instance.update_inventory_display(inventory)
		if is_editing_vehicle and current_vehicle:
			# 如果是编辑模式，从车辆中移除方块
			current_vehicle.remove_block(block)
			print(block,"已处理")
			# 从车辆网格中移除
			for pos in current_vehicle.grid:
				if current_vehicle.grid[pos] == block:
					current_vehicle.grid.erase(pos)
					current_vehicle.target_grid.erase(pos)
		else:
			# 否则直接从场景中移除
			block.queue_free()
		
		# 从放置记录中移除
		remove_block_from_grid(block, grid_pos)

func begin_vehicle_creation():
	if placed_blocks.is_empty():
		print("无法创建空车辆")
		return
	
	# 如果已经有当前车辆，直接使用它
	if not current_vehicle:
		current_vehicle = vehicle_scene.instantiate()
		get_parent().add_child(current_vehicle)
		current_vehicle.global_position = factory_zone.position
	
	# 转移所有方块到车辆节点
	var processed_blocks = []
	for grid_pos in placed_blocks:
		var block = placed_blocks[grid_pos]
		if block in processed_blocks: 
			continue
			
		if block is RigidBody2D:
			block.collision_layer = 1  # 恢复正常碰撞层
		remove_child(block)
		#current_vehicle.add_child(block)
		processed_blocks.append(block)
	
	# 初始化车辆网格
	current_vehicle.grid = placed_blocks.duplicate()
	current_vehicle.target_grid = placed_blocks.duplicate()
	
	# 连接所有相邻方块
	for block in current_vehicle.blocks:
		current_vehicle.connect_to_adjacent_blocks(block)
	
	current_vehicle.Get_ready_again()
	
	if is_instance_valid(ui_instance):
		ui_instance.hide()
	placed_blocks.clear()
	print("车辆生成完成")
	

# 信号处理
func _on_block_selected(scene_path: String):
	current_block_scene = load(scene_path)
	create_ghost_block()


func _on_build_vehicle_requested():
	if not is_build_mode: 
		return
		
	if is_editing_vehicle and current_vehicle:
		_on_vehicle_saved(current_vehicle.vehicle_name)
	else:
		begin_vehicle_creation()

func update_build_indicator():
	can_build = is_position_in_factory(ghost_block)
	ghost_block.modulate = Color(1, 1, 1, 0.5) if can_build else Color(1, 0.5, 0.5, 0.3)
	
	# 更新按钮状态
	ui_instance.build_vehicle_button.disabled = placed_blocks.is_empty()
	ui_instance.build_vehicle_button.visible = is_build_mode

func is_position_in_factory(block:Block) -> bool:
   # 计算方块的左上角世界坐标
	var block_top_left = block.position - Vector2(block.size)/2 * GRID_SIZE
	
	# 计算方块的右下角世界坐标
	var block_bottom_right = Vector2((block_top_left.x + block.size.x * GRID_SIZE), (block_top_left.y + block.size.y * GRID_SIZE))
	
	# 工厂区域的边界
	var factory_top_left = factory_zone.position - Vector2(factory_size)/2 * GRID_SIZE
	var factory_bottom_right = Vector2((factory_top_left.x + factory_size.x * GRID_SIZE), (factory_top_left.y + factory_size.y * GRID_SIZE))
	
	# 检查是否完全在工厂范围内
	return (block_top_left.x >= factory_top_left.x and
			block_top_left.y >= factory_top_left.y and
			block_bottom_right.x <= factory_bottom_right.x and
			block_bottom_right.y <= factory_bottom_right.y)

func is_position_occupied(positions: Array) -> bool:  # 添加缺失的函数
	for pos in positions:
		if placed_blocks.has(pos):
			return true
	return false

func remove_block_from_grid(block: Node, grid_pos: Vector2i):  # 添加缺失的函数
	var positions_to_remove = []
	for pos in placed_blocks:
		if placed_blocks[pos] == block:
			positions_to_remove.append(pos)
	
	for pos in positions_to_remove:
		placed_blocks.erase(pos)
	
	block.queue_free()

func _on_vehicle_saved(vehicle_name: String):
	if placed_blocks.is_empty() or not current_vehicle:
		push_error("没有可保存的方块或车辆无效")
		return
	current_vehicle.vehicle_name = vehicle_name
	current_vehicle.calculate_center_of_mass()
	current_vehicle.calculate_balanced_forces()
	current_vehicle.calculate_rotation_forces()
	# 生成蓝图数据
	var blueprint_data = create_blueprint_data(vehicle_name)
	
	# 确定保存路径
	var blueprint_path = ""
	if current_vehicle.blueprint != null:
		# 编辑模式：使用原有路径或生成默认路径
		if current_vehicle.blueprint is String:
			blueprint_path = current_vehicle.blueprint
		elif current_vehicle.blueprint is Dictionary:
			blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	else:
		# 新建模式：使用新路径
		blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	
	# 保存蓝图
	if save_blueprint(blueprint_data, blueprint_path):
		# 更新车辆引用
		current_vehicle.blueprint = blueprint_data
		
		# 如果是新建模式，恢复碰撞层
		if not is_editing_vehicle:
			for block:Block in current_vehicle.blocks:
				block.collision_layer = 1
		
		clear_builder()
		toggle_codex_ui()
		toggle_build_mode()
	else:
		push_error("蓝图保存失败")
		
	


func create_blueprint_data(vehicle_name: String) -> Dictionary:
	var blueprint_data = {
		"name": vehicle_name,
		"blocks": {}
	}
	
	var block_counter = 1
	var processed_blocks = {}
	
	# 首先收集所有方块的基准位置
	var base_positions = {}
	var min_x:int
	var min_y:int
	for grid_pos in placed_blocks:
		min_x = grid_pos.x
		min_y = grid_pos.y
		break
	
	for grid_pos in placed_blocks:
		if min_x > grid_pos.x:
			min_x = grid_pos.x
		if min_y > grid_pos.y:
			min_y = grid_pos.y
		
	for grid_pos in placed_blocks:
		var block = placed_blocks[grid_pos]
		if not processed_blocks.has(block):
			base_positions[block] = grid_pos
			processed_blocks[block] = true
	
	# 重新处理并分配顺序ID
	processed_blocks.clear()
	for grid_pos in placed_blocks:
		var block = placed_blocks[grid_pos]
		if not processed_blocks.has(block):
			var base_pos = grid_pos
			var rotation_str = get_rotation_direction(block.rotation)
			
			blueprint_data["blocks"][str(block_counter)] = {
				"name": block.name,
				"path": block.scene_file_path,
				"base_pos": [base_pos.x - min_x, base_pos.y - min_y],
				"size": [block.size.x, block.size.y],
				"rotation": rotation_str
			}
			block_counter += 1
			processed_blocks[block] = true
	
	return blueprint_data

func get_rotation_direction(angle: float) -> String:
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
	# 确保目录存在
	var dir = DirAccess.open("res://vehicles/blueprint/")
	if not dir:
		DirAccess.make_dir_absolute("res://vehicles/blueprint/")
	
	# 保存文件
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(blueprint_data, "\t"))
		file.close()
		print("车辆蓝图已保存到:", save_path)
		return true
	else:
		push_error("文件保存失败:", FileAccess.get_open_error())
		return false

func clear_builder():
	placed_blocks.clear()
	for block in get_children():
		if block is RigidBody2D and block != ghost_block:
			block.queue_free()

func spawn_vehicle_from_blueprint(blueprint: Dictionary):
	var vehicle = vehicle_scene.instantiate()
	vehicle.blueprint = blueprint  # 传递字典而非文件路径
	get_parent().add_child(vehicle)
	clear_builder()
