class_name HullEditingSystem
extends RefCounted

# === 引用 ===
var editor: Control
var selected_vehicle: Vehicle
var camera: Camera2D

# === 放置状态变量 ===
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null
var is_first_block := true
var is_new_vehicle := false

# === 移动功能变量 ===
var is_moving_block := false
var moving_block: Block = null
var moving_block_original_position: Vector2
var moving_block_original_rotation: float
var moving_block_original_grid_positions: Array
var moving_block_ghost: Node2D = null
var moving_snap_config: Dictionary = {}
var is_mouse_pressed := bool(false)
var drag_timer: float = 0.0
var is_dragging := bool(false)
var DRAG_DELAY: float = 0.2

# === 网格变换系统 ===
var grid_transform: Transform2D = Transform2D.IDENTITY
var inverse_grid_transform: Transform2D = Transform2D.IDENTITY
var reference_block: Block = null
var reference_grid_min: Vector2i = Vector2i.ZERO

const GRID_SIZE = 16

# === 获取引用辅助函数 ===
func get_viewport():
	return editor.get_viewport()

func get_tree():
	return editor.get_tree()

func setup(editor_ref: Control):
	editor = editor_ref
	selected_vehicle = editor_ref.selected_vehicle
	camera = editor_ref.camera

# === 网格变换系统核心 ===
func update_grid_transform():
	"""更新网格变换矩阵，基于车辆中第一个方块的位置和旋转"""
	if not selected_vehicle or selected_vehicle.grid.is_empty():
		# 没有方块时，使用车辆本身的变换
		grid_transform = selected_vehicle.global_transform
		inverse_grid_transform = grid_transform.affine_inverse()
		reference_block = null
		return
	
	# 获取第一个方块
	for pos in selected_vehicle.grid:
		reference_block = selected_vehicle.grid[pos]["block"]
		break
	
	if not reference_block:
		grid_transform = selected_vehicle.global_transform
		inverse_grid_transform = grid_transform.affine_inverse()
		return
	
	# 收集该方块的所有网格位置
	var block_grid_positions = []
	for pos in selected_vehicle.grid:
		if selected_vehicle.grid[pos]["block"] == reference_block:
			block_grid_positions.append(pos)
	
	if block_grid_positions.is_empty():
		grid_transform = selected_vehicle.global_transform
		inverse_grid_transform = grid_transform.affine_inverse()
		reference_block = null
		return
	
	# 找到方块的最小网格位置（左上角）
	var min_x = block_grid_positions[0].x
	var min_y = block_grid_positions[0].y
	for pos in block_grid_positions:
		min_x = min(min_x, pos.x)
		min_y = min(min_y, pos.y)
	
	reference_grid_min = Vector2i(min_x, min_y)
	
	# 计算方块的中心世界位置
	var block_center = reference_block.global_position
	var block_rotation = reference_block.global_rotation
	var block_size = reference_block.size
	
	# 计算方块左上角相对于中心的位置
	# 方块中心在 (size.x/2, size.y/2) * GRID_SIZE
	var half_block_width = (block_size.x * GRID_SIZE) / 2.0
	var half_block_height = (block_size.y * GRID_SIZE) / 2.0
	
	# 左上角相对于中心的位置（未旋转时）
	var top_left_offset = Vector2(-half_block_width, -half_block_height)
	
	# 应用方块的旋转
	top_left_offset = top_left_offset.rotated(block_rotation)
	
	# 计算左上角的世界位置
	var top_left_world = block_center + top_left_offset
	
	# 网格(min_x, min_y)对应的偏移量（未旋转时）
	var grid_offset = Vector2(min_x * GRID_SIZE, min_y * GRID_SIZE)
	
	# 应用网格系统的旋转（即参考方块的旋转）
	grid_offset = grid_offset.rotated(block_rotation)
	
	# 网格(0,0)对应的世界位置
	# 这是网格系统的原点，位于 top_left_world 减去 (min_x, min_y) 的偏移
	var grid_origin_world = top_left_world - grid_offset
	
	# 构建变换矩阵
	# Transform2D: x轴, y轴, 原点
	# x轴和y轴已经包含了旋转和缩放
	var x_axis = Vector2(GRID_SIZE, 0).rotated(block_rotation)
	var y_axis = Vector2(0, GRID_SIZE).rotated(block_rotation)
	
	grid_transform = Transform2D(x_axis, y_axis, grid_origin_world)
	inverse_grid_transform = grid_transform.affine_inverse()

func world_to_grid_position(world_position: Vector2) -> Vector2i:
	"""将世界坐标转换为网格坐标（修复版）"""
	if not selected_vehicle:
		return Vector2i.ZERO
	
	# 使用车辆的位置作为参考点
	var vehicle_pos = selected_vehicle.global_position
	var relative_pos = world_position - vehicle_pos
	
	# 考虑车辆的旋转
	relative_pos = relative_pos.rotated(-selected_vehicle.global_rotation)
	
	# 转换为网格坐标（使用整数除法）
	var grid_x = int(floor(relative_pos.x / GRID_SIZE))
	var grid_y = int(floor(relative_pos.y / GRID_SIZE))
	
	return Vector2i(grid_x, grid_y)

func grid_to_world_position(grid_position: Vector2i) -> Vector2:
	"""将网格坐标转换为世界坐标"""
	if not selected_vehicle:
		return Vector2.ZERO
	
	# 更新网格变换
	update_grid_transform()
	
	# 使用变换将网格坐标转换到世界空间
	var grid_vec = Vector2(grid_position)
	return grid_transform * grid_vec

# === 输入处理 ===
func handle_left_click():
	if editor.is_ui_interaction:
		return
	
	if current_ghost_block and not editor.is_recycle_mode:
		try_place_block()
	
	if editor.is_recycle_mode:
		try_remove_block()
		return

func process(delta):
	# 拖动检测
	if is_mouse_pressed and not is_dragging:
		drag_timer += delta
		if drag_timer >= DRAG_DELAY:
			is_dragging = true
			_start_block_drag()
	
	# 更新虚影块位置
	if current_ghost_block and Engine.get_frames_drawn() % 2 == 0:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_ghost_block_position(global_mouse_pos)
	
	# 更新移动块位置
	if is_moving_block and moving_block_ghost:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_moving_block_position(global_mouse_pos)
	
	# 更新引用
	selected_vehicle = editor.selected_vehicle
	camera = editor.camera

func handle_mouse_press(pressed: bool):
	is_mouse_pressed = pressed
	if not pressed:
		if is_dragging:
			if is_moving_block:
				place_moving_block()
			is_dragging = false
		drag_timer = 0.0

# === 方块放置功能 ===
func start_block_placement(scene_path: String):
	if not editor.is_editing or not selected_vehicle:
		return
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	current_block_scene = load(scene_path)
	if not current_block_scene:
		push_error("Unable to load block scene: ", scene_path)
		return
	
	current_ghost_block = current_block_scene.instantiate()
	get_tree().current_scene.add_child(current_ghost_block)
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 100
	current_ghost_block.do_connect = false
	
	current_ghost_block.base_rotation_degree = 0
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)

func setup_ghost_block_collision(ghost: Node2D):
	# 禁用所有碰撞形状
	var collision_shapes = ghost.find_children("*", "CollisionShape2D", true)
	for shape in collision_shapes:
		shape.disabled = true
	
	var collision_polygons = ghost.find_children("*", "CollisionPolygon2D", true)
	for poly in collision_polygons:
		poly.disabled = true
	
	if ghost is RigidBody2D:
		ghost.freeze = true
		ghost.collision_layer = 0
		ghost.collision_mask = 0

func update_ghost_block_position(mouse_position: Vector2):
	# 更新网格变换
	update_grid_transform()
	
	if is_first_block and is_new_vehicle:
		# 第一个块自由放置
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = editor.GHOST_FREE_COLOR
		return
	
	# 关键修改：计算方块中心相对于左上角的偏移
	var block_size = current_ghost_block.size
	var center_offset = Vector2(
		block_size.x * GRID_SIZE / 2.0,
		block_size.y * GRID_SIZE / 2.0
	)
	
	# 设置旋转：方块自身旋转 + 网格参考旋转
	var base_rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	var final_rotation = base_rotation
	if reference_block:
		final_rotation = base_rotation + reference_block.global_rotation
		current_ghost_block.global_rotation = final_rotation
	else:
		current_ghost_block.global_rotation = base_rotation
	
	# 应用旋转到偏移量
	center_offset = center_offset.rotated(final_rotation)
	
	# 计算鼠标位置对应的左上角位置
	var top_left_position = mouse_position - center_offset
	
	# 计算网格位置（基于左上角）
	var grid_pos = world_to_grid_position(top_left_position)
	
	# 计算方块占用的所有网格位置
	var block_positions = calculate_block_grid_positions_for_placement(grid_pos, current_ghost_block)
	
	# 检查是否可以放置
	var can_place = are_grid_positions_available(block_positions)
	
	if can_place:
		# 可以放置，计算世界位置（左上角）
		var world_pos = grid_to_world_position(grid_pos)
		
		# 设置虚影方块位置（左上角 + 中心偏移 = 中心点）
		current_ghost_block.global_position = world_pos + center_offset
		
		# 检查是否有连接吸附 - 关键修改：这是判断是否可以拼装的依据
		var snap_config = check_grid_connection_snap(grid_pos, block_positions, current_ghost_block)
		
		if snap_config and not snap_config.is_empty():
			# 可以连接到其他方块 - 显示绿色
			current_ghost_block.modulate = editor.GHOST_SNAP_COLOR
	else:
		# 不能放置，跟随鼠标但不吸附（中心点跟随鼠标）
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = Color(1.0, 0.5, 0.5, 0.5)

func rotate_ghost_connection():
	if not current_ghost_block:
		return
	
	current_ghost_block.base_rotation_degree += 90
	current_ghost_block.base_rotation_degree = fmod(current_ghost_block.base_rotation_degree + 90, 360) - 90
	
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	# 旋转后重新计算位置
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)

func try_place_block():
	if not current_ghost_block or not selected_vehicle:
		return
	
	# 第一个块放置逻辑
	if is_first_block and is_new_vehicle:
		place_first_block()
		return
	
	# 更新网格变换
	update_grid_transform()
	
	# 计算当前虚影块位置对应的网格位置（虚影块当前是中心点位置）
	var block_size = current_ghost_block.size
	var center_offset = Vector2(
		block_size.x * GRID_SIZE / 2.0,
		block_size.y * GRID_SIZE / 2.0
	)
	
	var base_rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	var final_rotation = base_rotation
	if reference_block:
		final_rotation = base_rotation + reference_block.global_rotation
	
	# 应用旋转到偏移量
	center_offset = center_offset.rotated(final_rotation)
	
	# 计算左上角位置
	var top_left_position = current_ghost_block.global_position - center_offset
	
	# 计算网格位置（基于左上角）
	var grid_pos = world_to_grid_position(top_left_position)
	var block_positions = calculate_block_grid_positions_for_placement(grid_pos, current_ghost_block)
	
	# 检查位置是否可用
	if not are_grid_positions_available(block_positions):
		return  # 位置不可用，不能放置
	
	# 创建新块
	var new_block: Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	
	# 设置位置（左上角 + 中心偏移 = 中心点）
	var world_pos = grid_to_world_position(grid_pos)
	new_block.global_position = world_pos + center_offset
	
	# 设置旋转
	if reference_block:
		new_block.global_rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + reference_block.global_rotation
	else:
		new_block.global_rotation = current_ghost_block.global_rotation
	
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	# 添加到车辆
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, block_positions)
	selected_vehicle.control = control
	
	# 如果有连接配置，建立连接
	var snap_config = check_grid_connection_snap(grid_pos, block_positions, current_ghost_block)
	if snap_config and not snap_config.is_empty():
		establish_grid_connection(new_block, snap_config)
	
	# 重新开始放置
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	# 放置后更新网格变换
	update_grid_transform()
	
	editor.update_blueprint_ghosts()

func place_first_block():
	var new_block: Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_ghost_block.global_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	# 第一个方块的网格位置从 (0, 0) 开始
	var grid_positions = calculate_block_grid_positions_for_placement(Vector2i.ZERO, new_block)
	
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	selected_vehicle.control = control
	
	is_first_block = false
	is_new_vehicle = false
	
	# 放置第一个方块后，更新网格参考
	update_grid_transform()
	
	start_block_placement_with_rotation(current_block_scene.resource_path)

func start_block_placement_with_rotation(scene_path: String):
	if not editor.is_editing or not selected_vehicle:
		return
	
	var base_rotation_degree = current_ghost_block.base_rotation_degree
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	current_block_scene = load(scene_path)
	if not current_block_scene:
		push_error("无法加载块场景: ", scene_path)
		return
	
	current_ghost_block = current_block_scene.instantiate()
	get_tree().current_scene.add_child(current_ghost_block)
	current_ghost_block.modulate = Color(1, 1, 1, 0.5)
	current_ghost_block.z_index = 100
	current_ghost_block.do_connect = false
	
	current_ghost_block.base_rotation_degree = base_rotation_degree
	current_ghost_block.rotation = deg_to_rad(base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)

# === 删除模式功能 ===
func try_remove_block():
	if not selected_vehicle:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = global_mouse_pos
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:
			var connections_to_disconnect = find_connections_for_block(block)
			disconnect_connections(connections_to_disconnect)
			
			var control = selected_vehicle.control
			selected_vehicle.remove_block(block, true)
			selected_vehicle.control = control
			
			enable_connection_points_for_blocks(get_affected_blocks_for_removal(block))
			call_deferred("check_vehicle_stability")
			
			editor.update_blueprint_ghosts()
			
			var block_count_after = selected_vehicle.blocks.size()
			if block_count_after == 0:
				is_first_block = true
				is_new_vehicle = true
			break

func find_connections_for_block(block: Block) -> Array:
	var connections = []
	for point in block.connection_points:
		if point.connected_to:
			connections.append({
				"from": point,
				"to": point.connected_to
			})
	return connections

func disconnect_connections(connections: Array):
	for connection in connections:
		if is_instance_valid(connection.from):
			connection.from.disconnect_joint()
		if is_instance_valid(connection.to):
			connection.to.disconnect_joint()

func get_affected_blocks_for_removal(removed_block: Block) -> Array:
	var affected_blocks = []
	for point in removed_block.connection_points:
		if point.connected_to:
			var connected_block = point.connected_to.find_parent_block()
			if connected_block:
				affected_blocks.append(connected_block)
	return affected_blocks

func cancel_placement():
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	current_block_scene = null
	editor.clear_tab_container_selection()
	editor.update_vehicle_info_display()

# === 方块移动功能 ===
func _start_block_drag():
	if not selected_vehicle:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	var block = get_block_at_position(global_mouse_pos)
	
	if block and block.get_parent() == selected_vehicle:
		start_moving_block(block)

func start_moving_block(block: Block):
	if is_moving_block:
		return
	
	moving_block = block
	moving_block_original_position = block.global_position
	moving_block_original_rotation = block.global_rotation
	moving_block_original_grid_positions = get_block_grid_positions(block)
	
	# 创建移动虚影
	moving_block_ghost = block.duplicate()
	get_tree().current_scene.add_child(moving_block_ghost)
	moving_block_ghost.modulate = Color(1, 1, 1, 0.5)
	moving_block_ghost.z_index = 100
	setup_ghost_block_collision(moving_block_ghost)
	
	# 从车辆中移除原块（临时）
	var connections_to_disconnect = find_connections_for_block(block)
	disconnect_connections(connections_to_disconnect)
	
	var control = selected_vehicle.control
	selected_vehicle.remove_block(block, false)
	selected_vehicle.control = control
	
	is_moving_block = true

func update_moving_block_position(mouse_position: Vector2):
	if not is_moving_block or not moving_block_ghost:
		return
	
	# 更新网格变换
	update_grid_transform()
	
	# 计算方块中心偏移
	var block_size = moving_block_ghost.size
	var center_offset = Vector2(
		block_size.x * GRID_SIZE / 2.0,
		block_size.y * GRID_SIZE / 2.0
	)
	center_offset = center_offset.rotated(moving_block_original_rotation)
	
	# 计算鼠标位置对应的左上角位置
	var top_left_position = mouse_position - center_offset
	
	# 计算网格位置（基于左上角）
	var grid_pos = world_to_grid_position(top_left_position)
	
	# 计算方块占用的所有网格位置
	var new_grid_positions = calculate_block_grid_positions_for_moving(grid_pos)
	
	# 检查新位置是否可用（排除原始位置）
	var can_place = are_grid_positions_available_for_moving(new_grid_positions)
	
	# 检查网格连接吸附
	var snap_config = check_connection_snap_for_moving_block(grid_pos, new_grid_positions)
	
	if can_place and snap_config and not snap_config.is_empty():
		# 可以放置且有吸附点
		var world_pos = grid_to_world_position(grid_pos)
		
		# 设置移动虚影位置（左上角 + 中心偏移 = 中心点）
		moving_block_ghost.global_position = world_pos + center_offset
		moving_block_ghost.global_rotation = moving_block_original_rotation
		moving_block_ghost.modulate = editor.GHOST_SNAP_COLOR
		
		# 更新吸附配置
		moving_snap_config = {
			"ghost_position": world_pos + center_offset,  # 存储的是中心位置
			"ghost_rotation": moving_block_original_rotation,
			"positions": new_grid_positions,
			"grid_valid": true,
			"connection_config": snap_config
		}
	else:
		# 不能放置或没有吸附点，中心点跟随鼠标
		moving_block_ghost.global_position = mouse_position
		moving_block_ghost.rotation = moving_block_original_rotation
		moving_block_ghost.modulate = editor.GHOST_FREE_COLOR
		moving_snap_config = {}

func place_moving_block():
	if not is_moving_block or not moving_block:
		return
	
	# 如果有有效的网格吸附配置，放置到网格位置
	if moving_snap_config and moving_snap_config.get("grid_valid", false):
		var grid_positions = moving_snap_config.positions
		
		# 设置新位置和旋转
		moving_block.global_position = moving_snap_config.ghost_position
		moving_block.global_rotation = moving_snap_config.ghost_rotation
		
		# 重新添加到车辆
		var control = selected_vehicle.control
		selected_vehicle._add_block(moving_block, moving_block.position, grid_positions)
		selected_vehicle.control = control
		
		# 如果有连接配置，建立连接
		if moving_snap_config.get("connection_config"):
			var conn_config = moving_snap_config.connection_config
			establish_grid_connection(moving_block, conn_config)
		
		editor.update_blueprint_ghosts()
	else:
		# 没有有效的吸附，恢复原始位置
		cancel_moving_block()
	
	# 清理移动状态
	cleanup_moving_block()

func cancel_moving_block():
	if not is_moving_block or not moving_block:
		return
	
	# 恢复原位置
	moving_block.global_position = moving_block_original_position
	moving_block.global_rotation = moving_block_original_rotation
	
	# 重新添加到车辆
	var control = selected_vehicle.control
	selected_vehicle._add_block(moving_block, moving_block.position, moving_block_original_grid_positions)
	selected_vehicle.control = control
	
	# 恢复连接
	enable_connection_points_for_blocks([moving_block])
	
	# 清理移动状态
	cleanup_moving_block()

func cleanup_moving_block():
	if moving_block_ghost:
		moving_block_ghost.queue_free()
		moving_block_ghost = null
	
	moving_block = null
	is_moving_block = false
	is_dragging = false
	moving_snap_config = {}

# === 网格吸附系统 ===
func check_connection_snap_for_moving_block(base_grid_pos: Vector2i, block_positions: Array) -> Dictionary:
	"""检查移动块是否可以与车辆块连接"""
	if not moving_block_ghost or not selected_vehicle:
		return {}
	
	# 获取虚影块的连接信息
	var ghost_connections = calculate_ghost_connections(moving_block_ghost, base_grid_pos)
	
	# 查找可能的连接
	var best_connection = {}
	
	for ghost_info in ghost_connections:
		var ghost_dir = ghost_info["direction"]
		var ghost_grid_pos = ghost_info["grid_position"]
		
		# 计算目标网格位置（根据连接方向）
		var target_grid_pos = ghost_grid_pos + get_direction_vector(ghost_dir)
		
		# 检查目标位置是否有车辆块
		if selected_vehicle.grid.has(target_grid_pos):
			var vehicle_block_data = selected_vehicle.grid[target_grid_pos]
			var vehicle_block = vehicle_block_data["block"]
			
			# 获取车辆块在该位置的连接方向
			var vehicle_connections = vehicle_block_data["connections"]
			
			# 检查相反方向是否有连接
			var opposite_dir = (ghost_dir + 2) % 4
			
			if vehicle_connections.size() > opposite_dir:
				if vehicle_connections[opposite_dir]:
					# 找到连接点！计算详细配置
					var connection_config = {
						"vehicle_block": vehicle_block,
						"vehicle_grid_pos": target_grid_pos,
						"vehicle_direction": opposite_dir,
						"ghost_grid_pos": ghost_grid_pos,
						"ghost_direction": ghost_dir,
						"connection_type": "grid_snap"
					}
					
					# 如果这是第一个连接，就使用它
					if best_connection.is_empty():
						best_connection = connection_config
	
	return best_connection

func check_grid_connection_snap(base_grid_pos: Vector2i, block_positions: Array, ghost_block: Node2D) -> Dictionary:
	"""检查虚影块是否可以与车辆块连接（用于放置新块）"""
	if not ghost_block or not selected_vehicle:
		return {}
	
	# 获取虚影块的连接信息
	var ghost_connections = calculate_ghost_connections(ghost_block, base_grid_pos)
	
	# 获取虚影块的连接点
	var ghost_connectors = []
	if ghost_block.has_method("get_available_connection_points"):
		ghost_connectors = ghost_block.get_available_connection_points()
	
	if ghost_connections.is_empty():
		return {}
	
	# 查找可能的连接
	var best_connection = {}
	
	for ghost_info in ghost_connections:
		var ghost_dir = ghost_info["direction"]
		var ghost_grid_pos = ghost_info["grid_position"]
		
		# 计算目标网格位置（根据连接方向）
		var target_grid_pos = ghost_grid_pos + get_direction_vector(ghost_dir)
		
		# 检查目标位置是否有车辆块
		if selected_vehicle.grid.has(target_grid_pos):
			var vehicle_block_data = selected_vehicle.grid[target_grid_pos]
			var vehicle_block = vehicle_block_data["block"]
			
			# 获取车辆块在该位置的连接方向
			var vehicle_connections = vehicle_block_data["connections"]
			
			# 检查相反方向是否有连接
			var opposite_dir = (ghost_dir + 2) % 4
			
			if vehicle_connections.size() > opposite_dir:
				if vehicle_connections[opposite_dir]:
					# 找到连接点！计算详细配置
					var connection_config = {
						"vehicle_block": vehicle_block,
						"vehicle_grid_pos": target_grid_pos,
						"vehicle_direction": opposite_dir,
						"ghost_grid_pos": ghost_grid_pos,
						"ghost_direction": ghost_dir,
						"connection_type": "grid_snap"
					}
					
					# 如果这是第一个连接，就使用它
					if best_connection.is_empty():
						best_connection = connection_config
	
	return best_connection

func calculate_ghost_connections(ghost_block: Node2D, base_grid_pos: Vector2i) -> Array:
	"""计算虚影块每个小格的连接方向"""
	var connections = []
	
	if not ghost_block:
		return connections
	
	# 获取虚影块的连接点
	var ghost_connectors = []
	if ghost_block.has_method("get_available_connection_points"):
		ghost_connectors = ghost_block.get_available_connection_points()
	
	# 获取块的大小和旋转
	var block_size = ghost_block.size
	var rotation_deg = ghost_block.base_rotation_degree
	
	# 计算左上角网格位置
	var top_left_grid_pos = base_grid_pos
	
	# 遍历虚影块占用的每个小格
	for x in range(block_size.x):
		for y in range(block_size.y):
			# 计算局部网格位置
			var local_grid_pos = Vector2i(x, y)
			
			# 转换为世界网格位置（考虑旋转）
			var world_grid_pos = calculate_rotated_grid_position(local_grid_pos, top_left_grid_pos, rotation_deg)
			
			# 查找该位置的所有连接点
			for connector in ghost_connectors:
				if not is_instance_valid(connector):
					continue
					
				if connector.location == local_grid_pos:
					# 计算连接点的方向（考虑块旋转）
					var connector_direction = calculate_connector_direction(connector, rotation_deg)
					
					# 直接访问属性，假设所有 Connector 都有 connection_type
					var connection_type = "default"
					if connector.has_method("get_connection_type"):
						connection_type = connector.get_connection_type()
					elif "connection_type" in connector:
						connection_type = connector.connection_type
					
					connections.append({
						"connector": connector,
						"local_position": local_grid_pos,
						"grid_position": world_grid_pos,
						"direction": connector_direction,
						"connection_type": connection_type
					})
	
	return connections

func calculate_connector_direction(connector: Connector, block_rotation_deg: int) -> int:
	"""计算连接点的方向（0-右, 1-下, 2-左, 3-上）"""
	# 获取连接点相对旋转（相对于块）
	var connector_rotation_deg = rad_to_deg(connector.rotation)
	
	# 计算总旋转（块旋转 + 连接点旋转）
	var total_rotation_deg = block_rotation_deg + connector_rotation_deg
	
	# 归一化到0-360度
	total_rotation_deg = fmod(total_rotation_deg + 360, 360)
	
	# 转换为方向（基于连接点的朝向）
	# 假设连接点的默认朝向右(0度)
	if total_rotation_deg >= 315 or total_rotation_deg < 45:
		return 0  # 右
	elif total_rotation_deg >= 45 and total_rotation_deg < 135:
		return 1  # 下
	elif total_rotation_deg >= 135 and total_rotation_deg < 225:
		return 2  # 左
	else:  # 225-315
		return 3  # 上

func calculate_rotated_grid_position(local_pos: Vector2i, base_pos: Vector2i, rotation_deg: int) -> Vector2i:
	"""计算旋转后的网格位置"""
	# 将旋转度转换为标准值（0, 90, 180, 270）
	var normalized_rotation = int(fmod(rotation_deg + 360, 360))
	
	match normalized_rotation:
		0:
			return base_pos + local_pos
		90:
			return base_pos + Vector2i(-local_pos.y, local_pos.x)
		180:
			return base_pos + Vector2i(-local_pos.x, -local_pos.y)
		270:
			return base_pos + Vector2i(local_pos.y, -local_pos.x)
		_:
			return base_pos + local_pos

func get_direction_vector(direction: int) -> Vector2i:
	"""将方向转换为向量"""
	match direction:
		0: return Vector2i(1, 0)   # 右
		1: return Vector2i(0, 1)   # 下
		2: return Vector2i(-1, 0)  # 左
		3: return Vector2i(0, -1)  # 上
		_: return Vector2i.ZERO

func get_direction_name(direction: int) -> String:
	match direction:
		0: return "右"
		1: return "下"
		2: return "左"
		3: return "上"
		_: return "未知"

func establish_grid_connection(block: Block, connection_config: Dictionary):
	"""基于网格连接配置建立连接"""
	# 获取车辆块和目标连接点
	var vehicle_block = connection_config.vehicle_block
	var vehicle_direction = connection_config.vehicle_direction
	
	# 在车辆块上找到对应方向的连接点
	var vehicle_connector = find_connector_by_direction(vehicle_block, vehicle_direction)
	
	if not vehicle_connector:
		return
	
	# 在移动块上找到对应方向的连接点
	var block_direction = connection_config.ghost_direction
	var block_connector = find_connector_by_direction(block, block_direction)
	
	if not block_connector:
		return
	
	# 尝试连接
	if vehicle_connector.is_connection_enabled and block_connector.is_connection_enabled:
		vehicle_connector.try_connect(block_connector)

func find_connector_by_direction(block: Block, direction: int) -> Connector:
	"""在块上查找指定方向的连接点"""
	if not block:
		return null
	
	for connector in block.connection_points:
		if connector is Connector:
			# 计算连接点的方向
			var connector_dir = calculate_connector_direction(connector, block.base_rotation_degree)
			
			if connector_dir == direction and not connector.connected_to:
				return connector
	return null

# === 网格计算辅助函数 ===
func calculate_block_grid_positions_for_moving(base_grid_pos: Vector2i) -> Array:
	"""计算移动块占用的网格位置"""
	if not moving_block:
		return []
	
	return calculate_block_grid_positions_for_placement(base_grid_pos, moving_block)

func calculate_block_grid_positions_for_placement(base_grid_pos: Vector2i, block: Node2D) -> Array:
	"""计算块占用的网格位置"""
	var grid_positions = []
	var block_size = block.size
	var rotation_deg = int(block.base_rotation_degree)
	
	# 获取方块左上角的网格位置
	var top_left_grid_pos = base_grid_pos
	
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			
			# 根据方块的旋转计算网格位置
			match rotation_deg:
				0:
					grid_pos = top_left_grid_pos + Vector2i(x, y)
				90:
					grid_pos = top_left_grid_pos + Vector2i(-y, x)
				-90, 270:
					grid_pos = top_left_grid_pos + Vector2i(y, -x)
				180, -180:
					grid_pos = top_left_grid_pos + Vector2i(-x, -y)
				_:
					grid_pos = top_left_grid_pos + Vector2i(x, y)
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func are_grid_positions_available_for_moving(new_positions: Array) -> bool:
	"""检查移动块的新位置是否可用"""
	if not selected_vehicle:
		return false
	
	for pos in new_positions:
		# 检查是否在其他方块占用
		if selected_vehicle.grid.has(pos):
			var existing_block = selected_vehicle.grid[pos]
			# 允许与原始位置重叠
			var is_original_position = false
			for original_pos in moving_block_original_grid_positions:
				if pos == original_pos:
					is_original_position = true
					break
			
			if not is_original_position:
				return false
	
	return true

func are_grid_positions_available(positions: Array) -> bool:
	"""检查位置是否可用（通用）"""
	if not selected_vehicle:
		return false
	
	for pos in positions:
		if selected_vehicle.grid.has(pos):
			return false
	
	return true

# === 辅助函数 ===
func get_block_at_position(position: Vector2) -> Block:
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:
			return block
	return null

func get_block_grid_positions(block: Block) -> Array:
	var grid_positions = []
	
	for grid_pos in selected_vehicle.grid:
		if selected_vehicle.grid[grid_pos]["block"] == block:
			grid_positions.append(grid_pos)
	
	return grid_positions

func enable_connection_points_for_blocks(blocks: Array):
	for block in blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(true)

func enable_all_connection_points_for_editing(open: bool):
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(open)

func restore_original_connections():
	if not selected_vehicle:
		return
	
	enable_all_connection_points_for_editing(false)
	await get_tree().process_frame

func check_vehicle_stability():
	if selected_vehicle:
		selected_vehicle.check_and_regroup_disconnected_blocks()
