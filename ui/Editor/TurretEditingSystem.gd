class_name TurretEditingSystem
extends RefCounted

# 引用
var editor: Control
var selected_vehicle: Vehicle
var camera: Camera2D

# 炮塔编辑状态变量
var is_turret_editing_mode := false
var current_editing_turret: TurretRing = null
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null

# 炮塔吸附系统变量
var available_turret_connectors: Array[TurretConnector] = []
var available_block_connectors: Array[TurretConnector] = []
var turret_snap_config: Dictionary = {}

const GRID_SIZE = 16
const MAX_SNAP_DISTANCE = 100.0  # 最大吸附距离
const TURRET_SNAP_RADIUS_MULTIPLIER = 4.0  # 炮塔吸附半径倍数

func get_viewport():
	return editor.get_viewport()

func get_tree():
	return editor.get_tree()

func setup(editor_ref: Control):
	editor = editor_ref
	selected_vehicle = editor_ref.selected_vehicle
	camera = editor_ref.camera

func handle_left_click():
	if editor.is_ui_interaction:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	if current_ghost_block:
		var can_place = turret_snap_config and not turret_snap_config.is_empty()
		
		if can_place and not editor.is_recycle_mode:
			try_place_turret_block()
		elif editor.is_recycle_mode:
			try_remove_turret_block()
	else:
		if editor.is_recycle_mode:
			try_remove_turret_block()
		
		var clicked_turret = get_turret_at_position(global_mouse_pos)
		if clicked_turret and clicked_turret != current_editing_turret:
			exit_turret_editing_mode()
			enter_turret_editing_mode(clicked_turret)

func process(delta):
	if is_turret_editing_mode and current_ghost_block:
		update_turret_placement_feedback()
	
	selected_vehicle = editor.selected_vehicle
	camera = editor.camera

# === 炮塔编辑模式功能 ===
func enter_turret_editing_mode(turret: TurretRing):
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	is_turret_editing_mode = true
	current_editing_turret = turret
	
	# 启用炮塔连接点
	for body in turret.turret_basket.get_children():
		if body is StaticBody2D:
			for point in body.get_children():
				if point is TurretConnector and point.connected_to == null:
					point.is_connection_enabled = true
	
	turret.lock_turret_rotation()
	
	# 设置块的颜色状态
	await update_all_block_colors_in_turret_mode(turret)
	
	if current_ghost_block:
		current_ghost_block.visible = false
	
	if editor.is_recycle_mode:
		Input.set_custom_mouse_cursor(editor.saw_cursor)
	
	editor.clear_tab_container_selection()

func exit_turret_editing_mode():
	if not is_turret_editing_mode:
		return
	
	is_turret_editing_mode = false
	
	if current_editing_turret:
		current_editing_turret.unlock_turret_rotation()
	
	Input.set_custom_mouse_cursor(null)
	
	# 恢复所有块的颜色
	if selected_vehicle:
		for block in selected_vehicle.blocks:
			if is_instance_valid(block):
				block.modulate = Color.WHITE
	
	if editor.is_recycle_mode:
		Input.set_custom_mouse_cursor(editor.saw_cursor)
	
	turret_snap_config = {}
	available_turret_connectors.clear()
	available_block_connectors.clear()
	
	if current_ghost_block:
		current_ghost_block.visible = true
	
	current_editing_turret = null

# === 颜色处理函数 ===
func handle_block_colors_in_turret_mode(block: Block):
	if not is_turret_editing_mode or not current_editing_turret:
		return
	
	if block == current_editing_turret:
		block.modulate = Color.WHITE
		# 炮塔篮筐中的子块也设为白色
		for child in block.turret_basket.get_children():
			if child is Block:
				child.modulate = Color.WHITE
	elif current_editing_turret.turret_blocks.has(block):
		block.modulate = Color.WHITE
	else:
		block.modulate = editor.BLOCK_DIM_COLOR
		# 如果是其他炮塔，将其子块也设为暗淡颜色
		if block is TurretRing:
			for child in block.turret_basket.get_children():
				if child is Block:
					child.modulate = editor.BLOCK_DIM_COLOR

func update_all_block_colors_in_turret_mode(turret:TurretRing):
	if not is_turret_editing_mode or not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			handle_block_colors_in_turret_mode(block)
	
	await get_tree().process_frame
	turret.lock_turret_rotation()
	
# === 方块放置功能 ===
func start_block_placement(scene_path: String):
	if not is_turret_editing_mode or not selected_vehicle:
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
	current_ghost_block.z_index = 1000
	current_ghost_block.do_connect = false
	
	# 在炮塔编辑模式下设置碰撞层
	if current_ghost_block is CollisionObject2D:
		current_ghost_block.set_layer(2)
		current_ghost_block.collision_mask = 2
	
	current_ghost_block.base_rotation_degree = 0
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	turret_snap_config = {}

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

func rotate_ghost_connection():
	if not current_ghost_block:
		return
	
	current_ghost_block.base_rotation_degree = fmod(current_ghost_block.base_rotation_degree + 90, 360)
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	# 旋转后重新计算吸附
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_turret_editing_snap_system(global_mouse_pos)

func cancel_placement():
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	current_block_scene = null
	turret_snap_config = {}
	editor.clear_tab_container_selection()
	editor.update_vehicle_info_display()

# === 炮塔编辑模式吸附系统 ===
func update_turret_placement_feedback():
	if not is_turret_editing_mode or not current_ghost_block or not current_editing_turret:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	update_turret_editing_snap_system(global_mouse_pos)

func update_turret_editing_snap_system(mouse_position: Vector2):
	if not is_turret_editing_mode or not current_ghost_block or not current_editing_turret:
		set_ghost_free_position(mouse_position)
		return
	
	# 检查鼠标是否离炮塔太远
	if is_mouse_too_far_from_turret(mouse_position):
		turret_snap_config = {}
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = editor.GHOST_FREE_COLOR
		return
	
	# 重置吸附配置
	turret_snap_config = {}
	
	# 先尝试炮塔内吸附（与炮塔篮筐的连接点吸附）
	var turret_snap = try_turret_internal_snap(mouse_position)
	if turret_snap and not turret_snap.is_empty():
		# 炮塔内吸附成功
		turret_snap_config = turret_snap
		current_ghost_block.global_position = turret_snap_config.ghost_position
		if turret_snap_config.has("ghost_rotation"):
			current_ghost_block.global_rotation = turret_snap_config.ghost_rotation
		current_ghost_block.modulate = editor.GHOST_SNAP_COLOR
		return
	
	# 再尝试炮塔外吸附（与炮塔上已有方块的连接点吸附）
	var external_snap = try_turret_external_snap(mouse_position)
	if external_snap and not external_snap.is_empty():
		# 炮塔外吸附成功
		turret_snap_config = external_snap
		current_ghost_block.global_position = turret_snap_config.ghost_position
		if turret_snap_config.has("ghost_rotation"):
			current_ghost_block.global_rotation = turret_snap_config.ghost_rotation
		current_ghost_block.modulate = editor.GHOST_SNAP_COLOR
		return
	
	# 都不能吸附，显示为不能放置
	turret_snap_config = {}
	current_ghost_block.global_position = mouse_position
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
	current_ghost_block.modulate = editor.GHOST_FREE_COLOR

func try_turret_internal_snap(mouse_position: Vector2) -> Dictionary:
	# 尝试炮塔内吸附（与炮塔篮筐的连接点吸附）
	var available_turret_points = get_turret_platform_connectors()
	var available_ghost_points = get_ghost_block_rigidbody_connectors()
	
	if available_turret_points.is_empty() or available_ghost_points.is_empty():
		return {}
	
	# 使用新的吸附逻辑
	var best_snap = find_valid_rigidbody_snap(mouse_position, available_turret_points, available_ghost_points)
	
	if best_snap and not best_snap.is_empty():
		return best_snap
	
	return {}

func try_turret_external_snap(mouse_position: Vector2) -> Dictionary:
	# 尝试炮塔外吸附（与炮塔上已有方块的连接点吸附）
	var available_block_points = get_turret_block_connection_points()
	var available_ghost_points = get_ghost_block_connection_points()
	
	print("=== 外部吸附调试 ===")
	print("可用块连接点数量: ", available_block_points.size())
	print("可用虚影连接点数量: ", available_ghost_points.size())
	
	if available_block_points.is_empty():
		print("外部吸附失败: 没有可用的块连接点")
		return {}
	
	if available_ghost_points.is_empty():
		print("外部吸附失败: 没有可用的虚影连接点")
		return {}
	
	# 打印一些连接点信息用于调试
	for i in range(min(3, available_block_points.size())):
		var point = available_block_points[i]
		var block = point.find_parent_block()
		print("块连接点 ", i, ": ", point.name, " 在块 ", block.name if block else "未知", " 位置: ", point.global_position)
	
	for i in range(min(3, available_ghost_points.size())):
		var point = available_ghost_points[i]
		print("虚影连接点 ", i, ": ", point.name, " 位置: ", point.global_position)
	
	# 使用新的吸附逻辑
	var best_snap = find_valid_regular_snap(mouse_position, available_block_points, available_ghost_points)
	
	if best_snap and not best_snap.is_empty():
		print("炮塔外吸附成功，网格位置: ", best_snap.get("grid_positions", []))
		return best_snap
	
	print("外部吸附失败: 未找到有效吸附")
	return {}

# === 新的吸附检测函数 ===
func find_valid_rigidbody_snap(mouse_position: Vector2, turret_points: Array[TurretConnector], ghost_points: Array[TurretConnector]) -> Dictionary:
	var best_config = {}
	var min_mouse_distance = INF
	var SNAP_DISTANCE = 32.0  # 吸附距离阈值
	
	for turret_point in turret_points:
		var turret_global_pos = turret_point.global_position
		
		for ghost_point in ghost_points:
			if not can_rigidbody_connectors_connect(turret_point, ghost_point):
				continue
			
			var ghost_global_pos = ghost_point.global_position
			var connector_distance = turret_global_pos.distance_to(ghost_global_pos)
			
			if connector_distance > SNAP_DISTANCE:
				continue
			
			# 计算吸附配置
			var snap_config = calculate_rigidbody_snap_config(turret_point, ghost_point)
			if snap_config.is_empty():
				continue
			
			# 检查网格位置是否可用
			var grid_positions = snap_config.get("grid_positions", [])
			if not are_turret_grid_positions_available(grid_positions, current_editing_turret):
				print("内部吸附 - 网格位置被占用: ", grid_positions)
				continue
			
			var snap_position = snap_config.get("ghost_position", Vector2.ZERO)
			var mouse_distance = mouse_position.distance_to(snap_position)
			if mouse_distance < min_mouse_distance:
				min_mouse_distance = mouse_distance
				best_config = snap_config
	
	return best_config

func find_valid_regular_snap(mouse_position: Vector2, block_points: Array[Connector], ghost_points: Array[Connector]) -> Dictionary:
	var best_config = {}
	var min_mouse_distance = INF
	var SNAP_DISTANCE = 32.0  # 吸附距离阈值
	
	print("开始查找有效外部吸附，块连接点数量: ", block_points.size(), " 虚影连接点数量: ", ghost_points.size())
	
	var connection_tested = 0
	var connection_valid = 0
	
	for block_point in block_points:
		var block = block_point.find_parent_block()
		if not block or block == current_editing_turret:
			continue
		
		var block_point_global = get_turret_connection_point_global_position(block_point, block)
		
		for ghost_point in ghost_points:
			connection_tested += 1
			
			# 检查连接点类型是否匹配
			if block_point.connection_type != ghost_point.connection_type:
				continue
			
			# 检查连接点方向
			if not can_points_connect_with_rotation_for_turret(block_point, ghost_point, 0):
				continue
			
			connection_valid += 1
			
			var ghost_global_pos = ghost_point.global_position
			var connector_distance = block_point_global.distance_to(ghost_global_pos)
			
			print("连接点测试 - 块: ", block.name, " 距离: ", connector_distance)
			
			if connector_distance > SNAP_DISTANCE:
				continue
			
			# 计算完整的吸附配置
			var target_rotation = calculate_aligned_rotation_for_turret_block(block)
			var positions = calculate_rotated_grid_positions_for_turret(block_point, ghost_point)
			
			if positions is bool or positions.is_empty():
				print("网格位置计算失败")
				continue
			
			# 检查网格位置是否可用
			if not are_turret_grid_positions_available(positions, current_editing_turret):
				print("外部吸附 - 网格位置被占用: ", positions)
				continue
			
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = block_point_global - ghost_local_offset
			
			# 计算鼠标到吸附位置的距离
			var mouse_distance = mouse_position.distance_to(ghost_position)
			
			if mouse_distance < min_mouse_distance:
				min_mouse_distance = mouse_distance
				
				best_config = {
					"vehicle_point": block_point,
					"ghost_point": ghost_point,
					"ghost_position": ghost_position,
					"ghost_rotation": target_rotation,
					"vehicle_block": block,
					"grid_positions": positions
				}
	
	print("外部吸附测试统计 - 总共测试: ", connection_tested, " 有效连接: ", connection_valid)
	
	if best_config.is_empty():
		print("未找到有效外部吸附配置")
	else:
		print("找到有效外部吸附配置，鼠标距离: ", min_mouse_distance)
	
	return best_config

# === 删除模式功能 ===
func try_remove_turret_block():
	if not is_turret_editing_mode or not current_editing_turret:
		return
		
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	var block_to_remove = get_turret_block_at_position(global_mouse_pos)
	
	if block_to_remove and block_to_remove != current_editing_turret:
		current_editing_turret.remove_block_from_turret(block_to_remove)
		# 更新块颜色
		update_all_block_colors_in_turret_mode(current_editing_turret)

func get_turret_block_at_position(position: Vector2) -> Block:
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 2
	
	var result = space_state.intersect_point(query)
	
	for collision in result:
		var block = collision.collider
		
		if (block is Block and 
			block != current_editing_turret and 
			is_block_on_turret(block)):
			return block
			
	return null

func is_block_on_turret(block: Block) -> bool:
	if not current_editing_turret:
		return false
	
	var attached_blocks = current_editing_turret.get_attached_blocks()
	return block in attached_blocks

# === 炮塔放置功能 ===
func try_place_turret_block():
	if not is_turret_editing_mode or not current_editing_turret:
		print("错误：不在炮塔编辑模式")
		return
	
	if not current_block_scene:
		print("错误：没有当前块场景")
		return
	
	if not turret_snap_config or turret_snap_config.is_empty():
		print("错误：没有吸附配置")
		return
	
	if not turret_snap_config.has("ghost_position"):
		print("错误：吸附配置缺少ghost_position")
		return
	
	# 使用加强验证
	if not validate_snap_config_before_placement():
		print("错误：放置前验证失败")
		return
	
	var grid_positions = turret_snap_config.get("grid_positions", [])
	
	if not grid_positions or grid_positions.is_empty():
		print("错误：没有网格位置")
		return
	
	# 创建新块
	var new_block: Block = current_block_scene.instantiate()
	
	if new_block is CollisionObject2D:
		new_block.set_layer(2)
		new_block.collision_mask = 2
	
	new_block.global_position = turret_snap_config.ghost_position
	new_block.global_rotation = turret_snap_config.ghost_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	# 添加到炮塔
	if turret_snap_config.has("grid_positions"):
		var success = current_editing_turret.add_block_to_turret(new_block, turret_snap_config.grid_positions)
		if not success:
			print("错误：添加到炮塔失败")
			new_block.queue_free()
			return
	else:
		new_block.queue_free()
		print("错误：吸附配置缺少grid_positions")
		return
	
	# 异步操作
	if new_block.has_method("connect_aready"):
		await new_block.connect_aready()
	else:
		await get_tree().process_frame
	
	if selected_vehicle:
		selected_vehicle.update_vehicle()
	
	# 更新块颜色
	update_all_block_colors_in_turret_mode(current_editing_turret)
	
	# 重新开始放置
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	print("块放置成功")

func start_block_placement_with_rotation(scene_path: String):
	if not is_turret_editing_mode or not selected_vehicle:
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
	current_ghost_block.z_index = 1000
	current_ghost_block.do_connect = false
	
	if current_ghost_block is CollisionObject2D:
		current_ghost_block.set_layer(2)
		current_ghost_block.collision_mask = 2
	
	current_ghost_block.base_rotation_degree = base_rotation_degree
	current_ghost_block.rotation = deg_to_rad(base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	turret_snap_config = {}

# === 放置前验证函数 ===
func validate_snap_config_before_placement() -> bool:
	# 1. 检查吸附配置是否完整
	if not turret_snap_config.has("ghost_position") or not turret_snap_config.has("grid_positions"):
		print("吸附配置不完整")
		return false
	
	# 2. 检查网格位置是否仍然可用
	var grid_positions = turret_snap_config.get("grid_positions", [])
	if not are_turret_grid_positions_available(grid_positions, current_editing_turret):
		print("网格位置已被占用")
		return false
	
	# 3. 检查连接点是否仍然可用
	if turret_snap_config.has("turret_point") and turret_snap_config.has("ghost_point"):
		var turret_point: TurretConnector = turret_snap_config.turret_point
		var ghost_point: TurretConnector = turret_snap_config.ghost_point
		
		if not is_instance_valid(turret_point) or not is_instance_valid(ghost_point):
			print("连接点无效")
			return false
		
		if not can_rigidbody_connectors_connect(turret_point, ghost_point):
			print("连接点无法连接")
			return false
	elif turret_snap_config.has("vehicle_point") and turret_snap_config.has("ghost_point"):
		var vehicle_point: Connector = turret_snap_config.vehicle_point
		var ghost_point: Connector = turret_snap_config.ghost_point
		
		if not is_instance_valid(vehicle_point) or not is_instance_valid(ghost_point):
			print("连接点无效")
			return false
		
		if not can_points_connect_with_rotation_for_turret(vehicle_point, ghost_point, 0):
			print("连接点无法连接")
			return false
	
	# 4. 检查块是否在炮塔范围内
	var ghost_position = turret_snap_config.ghost_position
	if is_position_too_far_from_turret(ghost_position):
		print("位置离炮塔太远")
		return false
	
	return true

func is_position_too_far_from_turret(position: Vector2) -> bool:
	if not current_editing_turret:
		return true
	
	var turret_center = current_editing_turret.global_position
	var distance = position.distance_to(turret_center)
	var turret_radius = calculate_effective_turret_radius()
	
	return distance > turret_radius

# === 炮塔检测功能 ===
func get_turret_at_position(position: Vector2) -> TurretRing:
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is TurretRing and block.get_parent() == selected_vehicle:
			return block
	return null

# === 吸附系统辅助函数 ===
func get_turret_connection_point_global_position(point: Connector, block: Block) -> Vector2:
	return block.global_position + point.position.rotated(block.global_rotation)

func calculate_aligned_rotation_for_turret_block(vehicle_block: Block) -> float:
	var world_rotation = vehicle_block.global_rotation
	var self_rotation = deg_to_rad(vehicle_block.base_rotation_degree)
	var base_rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	return world_rotation + base_rotation - self_rotation

func can_points_connect_with_rotation_for_turret(point_a: Connector, point_b: Connector, ghost_rotation: float) -> bool:
	if point_a.connection_type != point_b.connection_type:
		print("连接点类型不匹配: ", point_a.connection_type, " vs ", point_b.connection_type)
		return false
	
	# 使用角度差来判断，而不是点积
	var ghost_point_direction = wrapf(point_b.rotation + ghost_rotation, -PI, PI)
	var vehicle_point_direction = wrapf(point_a.global_rotation, -PI, PI)
	
	# 计算角度差
	var angle_diff = abs(wrapf(vehicle_point_direction - ghost_point_direction, -PI, PI))
	
	print("方向检测 - 点A方向: ", rad_to_deg(vehicle_point_direction), " 点B方向: ", rad_to_deg(ghost_point_direction), " 角度差: ", rad_to_deg(angle_diff))
	
	# 允许更大的角度容差，比如165-195度范围内都认为是可连接的
	return angle_diff > deg_to_rad(165) and angle_diff < deg_to_rad(195)

func calculate_rotated_grid_positions_for_turret(turret_point: Connector, ghost_point: Connector):
	if not current_editing_turret:
		print("网格计算失败: 没有当前编辑的炮塔")
		return []
	
	# 获取父块的网格位置
	var parent_block = turret_point.find_parent_block()
	if not parent_block:
		print("网格计算失败: 找不到父块")
		return []
	
	# 找到父块在炮塔网格中的位置
	var parent_grid_positions = current_editing_turret.get_turret_block_grid(parent_block)
	if parent_grid_positions.is_empty():
		print("网格计算失败: 父块没有网格位置")
		return []
	
	print("父块网格位置: ", parent_grid_positions)
	
	# 计算父块的边界
	var bounds = calculate_grid_bounds(parent_grid_positions)
	if not bounds:
		print("网格计算失败: 无法计算边界")
		return []
	
	# 计算连接点在父块中的局部位置
	var local_connector_pos = turret_point.location
	
	# 计算连接点在炮塔网格中的位置
	var connector_grid_pos = calculate_connector_grid_position(bounds, local_connector_pos, parent_block.base_rotation_degree)
	print("连接点网格位置: ", connector_grid_pos)
	
	# 计算新块的网格位置
	var new_block_positions = calculate_new_block_grid_positions(connector_grid_pos, ghost_point, current_ghost_block.size, current_ghost_block.base_rotation_degree)
	
	print("新块网格位置: ", new_block_positions)
	
	return new_block_positions

func calculate_grid_bounds(grid_positions: Array) -> Dictionary:
	if grid_positions.is_empty():
		return {}
	
	var min_x = grid_positions[0].x
	var min_y = grid_positions[0].y
	var max_x = grid_positions[0].x
	var max_y = grid_positions[0].y
	
	for pos in grid_positions:
		min_x = min(min_x, pos.x)
		min_y = min(min_y, pos.y)
		max_x = max(max_x, pos.x)
		max_y = max(max_y, pos.y)
	
	return {
		"min_x": min_x,
		"min_y": min_y,
		"max_x": max_x,
		"max_y": max_y,
		"width": max_x - min_x + 1,
		"height": max_y - min_y + 1
	}

func calculate_connector_grid_position(bounds: Dictionary, local_pos: Vector2i, rotation_degree: int) -> Vector2i:
	var base_pos = Vector2i(bounds.min_x, bounds.min_y)
	
	match rotation_degree:
		0:
			return base_pos + local_pos
		90:
			return base_pos + Vector2i(local_pos.y, bounds.height - 1 - local_pos.x)
		-90, 270:
			return base_pos + Vector2i(bounds.width - 1 - local_pos.y, local_pos.x)
		180, -180:
			return base_pos + Vector2i(bounds.width - 1 - local_pos.x, bounds.height - 1 - local_pos.y)
		_:
			return base_pos + local_pos

func calculate_new_block_grid_positions(connector_pos: Vector2i, ghost_point: Connector, block_size: Vector2i, rotation_degree: int) -> Array:
	var positions = []
	var local_connector_pos = ghost_point.location
	
	# 计算新块的基准位置
	var base_pos = calculate_base_position(connector_pos, local_connector_pos, rotation_degree)
	
	# 根据旋转计算所有网格位置
	for x in range(block_size.x):
		for y in range(block_size.y):
			var pos = calculate_rotated_position(base_pos, Vector2i(x, y), block_size, rotation_degree)
			positions.append(pos)
	
	return positions

func calculate_base_position(connector_pos: Vector2i, local_connector_pos: Vector2i, rotation_degree: int) -> Vector2i:
	match rotation_degree:
		0:
			return Vector2i(connector_pos.x - local_connector_pos.x, connector_pos.y - local_connector_pos.y)
		90:
			return Vector2i(connector_pos.x + local_connector_pos.y, connector_pos.y - local_connector_pos.x)
		-90, 270:
			return Vector2i(connector_pos.x - local_connector_pos.y, connector_pos.y + local_connector_pos.x)
		180, -180:
			return Vector2i(connector_pos.x + local_connector_pos.x, connector_pos.y + local_connector_pos.y)
		_:
			return Vector2i(connector_pos.x - local_connector_pos.x, connector_pos.y - local_connector_pos.y)

func calculate_rotated_position(base_pos: Vector2i, local_pos: Vector2i, block_size: Vector2i, rotation_degree: int) -> Vector2i:
	match rotation_degree:
		0:
			return Vector2i(base_pos.x + local_pos.x, base_pos.y + local_pos.y)
		90:
			return Vector2i(base_pos.x - local_pos.y, base_pos.y + local_pos.x)
		-90, 270:
			return Vector2i(base_pos.x + local_pos.y, base_pos.y - local_pos.x)
		180, -180:
			return Vector2i(base_pos.x - local_pos.x, base_pos.y - local_pos.y)
		_:
			return Vector2i(base_pos.x + local_pos.x, base_pos.y + local_pos.y)

func get_rectangle_corners(grid_data: Dictionary) -> Dictionary:
	if grid_data.is_empty():
		return {}
	
	var x_coords = []
	var y_coords = []
	
	for coord in grid_data.keys():
		x_coords.append(coord[0])
		y_coords.append(coord[1])
	
	x_coords.sort()
	y_coords.sort()
	
	return {
		"1": Vector2i(x_coords[0], y_coords[0]),
		"2": Vector2i(x_coords[x_coords.size() - 1], y_coords[0]),
		"3": Vector2i(x_coords[x_coords.size() - 1], y_coords[y_coords.size() - 1]),
		"4": Vector2i(x_coords[0], y_coords[y_coords.size() - 1])
	}

func get_connection_offset(connect_pos_v: Vector2i, _rotation: float, direction: int) -> Vector2i:
	var rounded_rotation_or = round(rad_to_deg(_rotation))
	var rounded_rotation = direction + rounded_rotation_or
	rounded_rotation = wrapf(rounded_rotation, -180, 180)
	
	match int(rounded_rotation):
		0:
			return Vector2i(connect_pos_v.x + 1, connect_pos_v.y)
		-90:
			return Vector2i(connect_pos_v.x, connect_pos_v.y - 1)
		-180, 180:
			return Vector2i(connect_pos_v.x - 1, connect_pos_v.y)
		90:
			return Vector2i(connect_pos_v.x, connect_pos_v.y + 1)
	
	return connect_pos_v

func to_grid_array(grid_connect_g: Vector2i, block_size: Vector2i, connect_pos_g: Vector2i) -> Array:
	var grid_positions = []
	
	for i in block_size.x:
		for j in block_size.y:
			var pos: Vector2i
			match int(current_ghost_block.base_rotation_degree):
				0:
					var left_up = Vector2i(grid_connect_g.x - connect_pos_g.x, grid_connect_g.y - connect_pos_g.y)
					pos = Vector2i(left_up.x + i, left_up.y + j)
				90:
					var left_up = Vector2i(grid_connect_g.x - connect_pos_g.y, grid_connect_g.y + connect_pos_g.x)
					pos = Vector2i(left_up.x + j, left_up.y - i)
				-90, 270:
					var left_up = Vector2i(grid_connect_g.x + connect_pos_g.y, grid_connect_g.y - connect_pos_g.x)
					pos = Vector2i(left_up.x - j, left_up.y + i)
				180, -180:
					var left_up = Vector2i(grid_connect_g.x + connect_pos_g.x, grid_connect_g.y + connect_pos_g.y)
					pos = Vector2i(left_up.x - i, left_up.y - j)
				_:
					var left_up = Vector2i(grid_connect_g.x - connect_pos_g.x, grid_connect_g.y - connect_pos_g.y)
					pos = Vector2i(left_up.x + i, left_up.y + j)
	
			grid_positions.append(pos)
	
	return grid_positions

# === 连接点获取函数 ===
func get_turret_platform_connectors() -> Array[TurretConnector]:
	var points: Array[TurretConnector] = []
	
	if not current_editing_turret:
		return points
	
	for body in current_editing_turret.turret_basket.get_children():
		if body is StaticBody2D:
			for connector in body.get_children():
				if (connector is TurretConnector and 
					connector.is_connection_enabled and 
					connector.connected_to == null):
					points.append(connector)
	
	return points

func get_turret_block_connection_points() -> Array[Connector]:
	var points: Array[Connector] = []
	
	if not current_editing_turret:
		print("错误: 没有当前编辑的炮塔")
		return points
	
	var attached_blocks = current_editing_turret.get_attached_blocks()
	print("炮塔上的块数量: ", attached_blocks.size())
	
	for block in attached_blocks:
		if is_instance_valid(block) and block != current_editing_turret:
			print("检查块: ", block.name, " 的连接点")
			for point in block.connection_points:
				if (point is Connector and 
					point.is_connection_enabled and 
					point.connected_to == null):
					# 添加连接点详细信息
					print("找到可用连接点: ", point.name, 
						  " 在块: ", block.name,
						  " 类型: ", point.connection_type,
						  " 本地旋转: ", rad_to_deg(point.rotation),
						  " 全局旋转: ", rad_to_deg(point.global_rotation),
						  " 位置: ", point.location)
					points.append(point)
	
	print("总共找到外部连接点: ", points.size())
	return points

func get_ghost_block_rigidbody_connectors() -> Array[TurretConnector]:
	var points: Array[TurretConnector] = []
	
	if not current_ghost_block:
		return points
	
	# 确保我们找到的是正确的连接点类型
	for connector in current_ghost_block.find_children("*", "TurretConnector", true):
		if (connector is TurretConnector and 
			connector.is_connection_enabled and 
			connector.connected_to == null):
			points.append(connector)
	
	return points

func get_ghost_block_connection_points() -> Array[Connector]:
	var points: Array[Connector] = []
	if current_ghost_block:
		var connection_points = current_ghost_block.get_available_connection_points()
		for point in connection_points:
			if point is Connector:
				# 添加虚影块连接点详细信息
				print("虚影块连接点: ", point.name,
					  " 类型: ", point.connection_type,
					  " 本地旋转: ", rad_to_deg(point.rotation),
					  " 全局旋转: ", rad_to_deg(point.global_rotation),
					  " 位置: ", point.location)
				points.append(point)
	return points

# === 刚性体吸附系统 ===
func calculate_rigidbody_snap_config(turret_point: TurretConnector, ghost_point: TurretConnector) -> Dictionary:
	if not turret_point or not ghost_point or not current_ghost_block or not current_editing_turret:
		return {}
	
	# 计算网格位置
	var grid_positions = calculate_rigidbody_grid_positions(turret_point, ghost_point)
	if not are_turret_grid_positions_available(grid_positions, current_editing_turret):
		return {}
	
	# 计算世界位置和旋转
	var world_position = calculate_turret_world_position(turret_point, ghost_point.position, deg_to_rad(ghost_point.get_parent().base_rotation_degree))
	var target_rotation = calculate_turret_block_rotation(turret_point, ghost_point)
	
	return {
		"turret_point": turret_point,
		"ghost_point": ghost_point,
		"ghost_position": world_position,
		"ghost_rotation": target_rotation,
		"grid_positions": grid_positions,
		"connection_type": "rigidbody"
	}

func calculate_rigidbody_grid_positions(turret_point: TurretConnector, ghost_point: TurretConnector) -> Array:
	var positions = []
	var turret_local_pos = turret_point.location
	var ghost_local_pos = ghost_point.location
	
	# 计算基准位置
	var base_pos = turret_local_pos
	
	# 根据虚影块的旋转计算所有网格位置
	for x in range(current_ghost_block.size.x):
		for y in range(current_ghost_block.size.y):
			var pos = calculate_rigidbody_position(base_pos, Vector2i(x, y), ghost_local_pos, current_ghost_block.base_rotation_degree)
			positions.append(pos)
	
	return positions

func calculate_rigidbody_position(base_pos: Vector2i, local_pos: Vector2i, connector_pos: Vector2i, rotation_degree: int) -> Vector2i:
	match rotation_degree:
		0:
			return Vector2i(base_pos.x - connector_pos.x + local_pos.x, base_pos.y - connector_pos.y + local_pos.y)
		90:
			return Vector2i(base_pos.x + connector_pos.y - local_pos.y, base_pos.y - connector_pos.x + local_pos.x)
		-90, 270:
			return Vector2i(base_pos.x - connector_pos.y + local_pos.y, base_pos.y + connector_pos.x - local_pos.x)
		180, -180:
			return Vector2i(base_pos.x + connector_pos.x - local_pos.x, base_pos.y + connector_pos.y - local_pos.y)
		_:
			return Vector2i(base_pos.x - connector_pos.x + local_pos.x, base_pos.y - connector_pos.y + local_pos.y)

func calculate_turret_world_position(turret_point: TurretConnector, ghost_local_pos: Vector2, rotation: float) -> Vector2:
	var use_pos = turret_point.position - ghost_local_pos.rotated(rotation)
	return turret_point.get_parent().to_global(use_pos)

func calculate_turret_block_rotation(turret_point: TurretConnector, ghost_point: TurretConnector) -> float:
	var turret_direction = turret_point.global_rotation
	var ghost_base_rotation = deg_to_rad(ghost_point.get_parent().base_rotation_degree)
	return turret_direction + ghost_base_rotation

func can_rigidbody_connectors_connect(connector_a: TurretConnector, connector_b: TurretConnector) -> bool:
	if not connector_a or not connector_b:
		return false
	
	if connector_a.connection_type != connector_b.connection_type:
		return false
	
	if not connector_a.is_connection_enabled or not connector_b.is_connection_enabled:
		return false
	
	if connector_a.connected_to != null or connector_b.connected_to != null:
		return false
	
	var a_is_turret = connector_a.get_parent() is Block
	var b_is_turret = connector_b.get_parent() is Block
	
	var can_connect = a_is_turret != b_is_turret
	
	return can_connect

func are_turret_grid_positions_available(grid_positions: Array, turret: TurretRing) -> bool:
	if not turret:
		return false
	
	for pos in grid_positions:
		if not is_grid_position_available(pos, turret):
			return false
	
	return true

func is_grid_position_available(grid_pos: Vector2i, turret: TurretRing) -> bool:
	if not turret:
		return false
	
	# 检查位置是否在炮塔网格中
	var existing_block = turret.get_turret_block_at_position(grid_pos)
	if existing_block:
		return false
	
	return true

# === 距离检测函数 ===
func is_mouse_too_far_from_turret(mouse_position: Vector2) -> bool:
	if not current_editing_turret:
		return true
	
	var turret_center = current_editing_turret.global_position
	var distance = mouse_position.distance_to(turret_center)
	var effective_radius = calculate_effective_turret_radius()
	
	print("鼠标距离检测 - 距离: ", distance, " 有效半径: ", effective_radius)
	
	# 在炮塔编辑模式下，我们使用更宽松的距离检测
	# 允许在炮塔外部较远的位置进行外部吸附
	return distance > effective_radius * 3.0  # 增加3倍容忍范围

func calculate_effective_turret_radius() -> float:
	if not current_editing_turret:
		return 0.0
	
	# 基础半径基于炮塔大小
	var base_radius = max(current_editing_turret.size.x, current_editing_turret.size.y) * GRID_SIZE * TURRET_SNAP_RADIUS_MULTIPLIER
	
	# 考虑已放置块的最大延伸
	var attached_blocks = current_editing_turret.get_attached_blocks()
	var max_extension = 0.0
	
	for block in attached_blocks:
		if is_instance_valid(block):
			var block_distance = block.global_position.distance_to(current_editing_turret.global_position)
			# 加上块本身的大小
			var block_radius = max(block.size.x, block.size.y) * GRID_SIZE * 0.5
			var total_distance = block_distance + block_radius
			max_extension = max(max_extension, total_distance)
	
	# 使用较大的半径，确保外部吸附有足够空间
	var effective_radius = max(base_radius, max_extension) + MAX_SNAP_DISTANCE
	
	print("计算有效半径 - 基础: ", base_radius, " 最大延伸: ", max_extension, " 最终: ", effective_radius)
	
	return effective_radius

# === 通用函数 ===
func set_ghost_free_position(mouse_position: Vector2):
	current_ghost_block.global_position = mouse_position
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
	current_ghost_block.modulate = editor.GHOST_FREE_COLOR
	turret_snap_config = {}
