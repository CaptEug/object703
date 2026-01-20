extends Node2D
class_name BuildingSystem

# 建筑系统管理
@export var tilemap: TileMap
@export var grid_size: int = 16

var buildings: Array[Building] = []
var current_editing_building: Building = null
var is_editing_mode: bool = false
var ghost_block: Node2D = null

# 颜色配置
@export var GHOST_FREE_COLOR = Color(1, 0.3, 0.3, 0.6)
@export var GHOST_SNAP_COLOR = Color(0.6, 1, 0.6, 0.6)

func _ready():
	pass

func create_new_building(building_name: String = "新建建筑") -> Building:
	"""创建新建筑"""
	var building = Building.new()
	building.building_name = building_name
	building.global_position = get_global_mouse_position()
	
	add_child(building)
	buildings.append(building)
	
	return building

func start_editing_building(building: Building):
	"""开始编辑建筑"""
	if is_editing_mode:
		stop_editing()
	
	current_editing_building = building
	is_editing_mode = true
	
	# 取消冻结，允许编辑
	building.freeze_all_blocks(false)

func stop_editing():
	"""停止编辑"""
	if not is_editing_mode:
		return
	
	if current_editing_building:
		# 重新冻结
		current_editing_building.freeze_all_blocks(true)
	
	current_editing_building = null
	is_editing_mode = false
	
	if ghost_block:
		ghost_block.queue_free()
		ghost_block = null

func add_block_to_building(scene_path: String):
	"""向当前编辑的建筑添加块"""
	if not is_editing_mode or not current_editing_building:
		return
	
	if ghost_block:
		ghost_block.queue_free()
	
	var scene = load(scene_path)
	if not scene:
		push_error("Unable to load block scene: ", scene_path)
		return
	
	ghost_block = scene.instantiate()
	add_child(ghost_block)
	ghost_block.modulate = Color(1, 1, 1, 0.5)
	ghost_block.z_index = 100
	
	# 设置幽灵块属性
	ghost_block.do_connect = false
	if ghost_block is RigidBody2D:
		ghost_block.freeze = true
		ghost_block.collision_layer = 0
		ghost_block.collision_mask = 0

func _process(delta):
	if is_editing_mode and ghost_block:
		update_ghost_position()

func update_ghost_position():
	"""更新幽灵块位置"""
	var mouse_pos = get_global_mouse_position()
	var grid_pos = world_to_grid(mouse_pos)
	var world_pos = grid_to_world(grid_pos)
	
	ghost_block.global_position = world_pos
	
	# 检查是否可以放置
	if can_place_block_at(grid_pos, ghost_block):
		ghost_block.modulate = GHOST_SNAP_COLOR
	else:
		ghost_block.modulate = GHOST_FREE_COLOR

func can_place_block_at(grid_pos: Vector2i, block: Node2D) -> bool:
	"""检查是否可以在指定网格位置放置块"""
	if not current_editing_building or not block.has_method("size"):
		return false
	
	var block_size = block.size
	var grid_positions = []
	
	# 计算块会占据的所有网格位置
	for x in range(block_size.x):
		for y in range(block_size.y):
			grid_positions.append(grid_pos + Vector2i(x, y))
	
	# 检查所有位置是否可用
	for pos in grid_positions:
		if not current_editing_building.is_position_available([pos]):
			return false
	
	# 检查是否在建筑网格内（可选）
	if tilemap:
		for pos in grid_positions:
			var tile_data = tilemap.get_cell_tile_data(0, pos)
			if not tile_data:
				return false
	
	return true

func place_current_block():
	"""放置当前幽灵块"""
	if not is_editing_mode or not ghost_block or not current_editing_building:
		return
	
	var mouse_pos = get_global_mouse_position()
	var grid_pos = world_to_grid(mouse_pos)
	
	if not can_place_block_at(grid_pos, ghost_block):
		return
	
	# 创建实际块
	var block_scene = load(ghost_block.scene_file_path)
	if not block_scene:
		return
	
	var block: Block = block_scene.instantiate()
	var world_pos = grid_to_world(grid_pos)
	
	# 计算块会占据的所有网格位置
	var grid_positions = []
	for x in range(block.size.x):
		for y in range(block.size.y):
			grid_positions.append(grid_pos + Vector2i(x, y))
	
	# 添加到建筑
	current_editing_building.add_block(block, world_pos, grid_positions)
	
	# 重新创建幽灵块以继续放置
	add_block_to_building(ghost_block.scene_file_path)

#func get_global_mouse_position() -> Vector2:
	#"""获取鼠标的全局位置"""
	#return get_viewport().get_mouse_position()

func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""世界坐标转网格坐标"""
	var x = int(floor(world_pos.x / grid_size))
	var y = int(floor(world_pos.y / grid_size))
	return Vector2i(x, y)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""网格坐标转世界坐标"""
	return Vector2(grid_pos.x * grid_size + grid_size * 0.5,
				  grid_pos.y * grid_size + grid_size * 0.5)

func get_building_at_position(position: Vector2) -> Building:
	"""获取指定位置的建筑"""
	for building in buildings:
		if building.get_block_at_position(position):
			return building
	return null

func demolish_building(building: Building):
	"""拆除建筑"""
	if building in buildings:
		building.demolish()
		buildings.erase(building)
