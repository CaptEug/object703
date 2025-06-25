extends Node2D

# 配置
const GRID_SIZE := 16
@export var factory_size := Vector2i(10, 8)  # 工厂可建造范围 (宽10格，高8格)
@export var block_scenes: Array[PackedScene] = [
	preload("res://blocks/armor.tscn"),
	preload("res://blocks/bridge.tscn"),
	preload("res://blocks/maybach_hl_250.tscn"),
	preload("res://blocks/rusty_track.tscn"),
	preload("res://blocks/weapons/kwak45.tscn")
]

@export var vehicle_scene: PackedScene = preload("res://vehicles/vehicle.tscn")

# 建造系统
var current_block_index := 0
var ghost_block: Node2D
var placed_blocks := {}  # {Vector2i 网格坐标: 方块实例}
var can_build := true
var is_creating_vehicle := false

func _ready():
	create_ghost_block()
	queue_redraw()

func _process(delta):
	if ghost_block and not is_creating_vehicle:
		update_ghost_position()
		update_build_indicator()
	if is_creating_vehicle:
		complete_vehicle_creation()
		
func _input(event):
	if is_creating_vehicle: return
	
	# 鼠标滚轮切换方块
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			change_block(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			change_block(-1)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			remove_block_at_mouse()
	
	# 按键生成车辆
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		begin_vehicle_creation()

func _draw():
	# 绘制建造范围边界
	draw_rect(Rect2(Vector2.ZERO, factory_size * GRID_SIZE), Color(1, 0, 0, 0.2), true)
	draw_rect(Rect2(Vector2.ZERO, factory_size * GRID_SIZE), Color.RED, false, 2.0)

# 方块尺寸获取
func get_block_size(block: Node) -> Vector2i:
	return block.SIZE if "SIZE" in block else Vector2i(1, 1)

# 建造范围检测
func is_position_in_factory(world_pos: Vector2) -> bool:
  # 将全局坐标转换为相对于工厂节点的局部坐标
	var local_pos = world_pos
	
	# 获取当前幽灵方块的尺寸（单位：网格数）
	var block_size = get_block_size(ghost_block)
	
	# 计算方块左下角的网格坐标（向下取整）
	var base_grid_pos = Vector2i(
		floor(local_pos.x / GRID_SIZE),
		floor(local_pos.y / GRID_SIZE)
	)
	
	# 检查方块占用的每个网格是否都在工厂范围内
	for x in range(block_size.x):
		for y in range(block_size.y):
			var check_pos = base_grid_pos + Vector2i(x, y)
			
			# 判断是否超出边界（四个方向）
			if (check_pos.x < 0 or 
				check_pos.y < 0 or 
				check_pos.x >= factory_size.x or 
				check_pos.y >= factory_size.y):
				return false
	return true

# 建造状态指示器
func update_build_indicator():
	can_build = is_position_in_factory(ghost_block.position)
	ghost_block.modulate = Color(1, 1, 1, 0.5) if can_build else Color(1, 0.5, 0.5, 0.3)

# 方块切换
func change_block(direction: int):
	current_block_index = wrapi(current_block_index + direction, 0, block_scenes.size())
	create_ghost_block()
	print("当前方块: ", get_current_block_name())

func get_current_block_name() -> String:
	return block_scenes[current_block_index].resource_path.get_file().trim_suffix(".tscn")

# 幽灵方块管理
func create_ghost_block():
	if ghost_block:
		ghost_block.queue_free()
	
	ghost_block = block_scenes[current_block_index].instantiate()
	ghost_block.modulate = Color(1, 1, 1, 0.5)
	
	# 禁用所有物理行为
	for child in ghost_block.get_children():
		if child is CollisionObject2D:
			child.set_deferred("disabled", true)
		if child is RigidBody2D:
			child.freeze = true
	
	add_child(ghost_block)

func update_ghost_position():
	var mouse_pos = get_global_mouse_position()
	var local_mouse_pos = to_local(mouse_pos)
	var block_size = get_block_size(ghost_block)
	
	# 计算左下角网格坐标
	var grid_pos = Vector2i(
		floor(local_mouse_pos.x / GRID_SIZE),
		floor(local_mouse_pos.y / GRID_SIZE)
	)
	
	# 中心点对齐
	ghost_block.position = grid_pos * GRID_SIZE + (block_size * GRID_SIZE) / 2

# 方块放置/删除
func place_block():
	if not ghost_block or not can_build: return
	
	var block_size = get_block_size(ghost_block)
	var grid_pos = Vector2i(
		floor((ghost_block.position.x - (block_size.x * GRID_SIZE)/2) / GRID_SIZE),
		floor((ghost_block.position.y - (block_size.y * GRID_SIZE)/2) / GRID_SIZE
	))
	
	# 检查所有网格是否可用
	for x in block_size.x:
		for y in block_size.y:
			var check_pos = grid_pos + Vector2i(x, y)
			if placed_blocks.has(check_pos):
				print("位置被占用: ", check_pos)
				return
	
	# 创建新方块（确保静止）
	var new_block = block_scenes[current_block_index].instantiate()
	new_block.position = ghost_block.position
	
	# 禁用物理（如果是RigidBody2D）
	if new_block is RigidBody2D:
		new_block.freeze = true
		new_block.sleeping = true
	
	add_child(new_block)
	
	# 记录占用网格
	for x in block_size.x:
		for y in block_size.y:
			placed_blocks[grid_pos + Vector2i(x, y)] = new_block
	#print("已放置方块: ", get_current_block_name(), " 在位置: ", grid_pos,placed_blocks,new_block.position)

func remove_block_at_mouse():
	var mouse_pos = get_global_mouse_position()
	var grid_pos = Vector2i(mouse_pos / GRID_SIZE)
	
	if placed_blocks.has(grid_pos):
		var block = placed_blocks[grid_pos]
		var block_size = get_block_size(block)
		
		# 移除所有关联位置
		for x in block_size.x:
			for y in block_size.y:
				var pos = grid_pos + Vector2i(x, y)
				if placed_blocks.get(pos) == block:
					placed_blocks.erase(pos)
		
		block.queue_free()
		print("已移除方块: ", grid_pos)

# 车辆生成系统
func begin_vehicle_creation():
	if placed_blocks.is_empty():
		print("没有放置方块")
		return
	
	is_creating_vehicle = true
	print("开始生成车辆...")

func complete_vehicle_creation():
	var vehicle = vehicle_scene.instantiate()
	get_parent().add_child(vehicle)
	
	# 转移所有方块到车辆节点
	var processed_blocks = []
	for grid_pos in placed_blocks:
		var block = placed_blocks[grid_pos]
		if block in processed_blocks: continue
		if block is RigidBody2D:
			block.sleeping = false
			block.freeze = false
		vehicle._add_block(block)
	vehicle.Get_ready_again()
	
	# 初始化车辆物理
	if vehicle.has_method("initialize_physics"):
		vehicle.initialize_physics(processed_blocks)
	
	placed_blocks.clear() 
	is_creating_vehicle = false
	print("车辆生成完成")

func snap_block_to_grid(block:Block) -> Vector2i:
	var world_pos = block.global_position - block.size/2 * GRID_SIZE
	var snapped_pos = Vector2(
		floor(world_pos.x / GRID_SIZE),
		floor(world_pos.y / GRID_SIZE)
	)
	block.global_position = snapped_pos * GRID_SIZE + block.size/2 * GRID_SIZE
	return snapped_pos
