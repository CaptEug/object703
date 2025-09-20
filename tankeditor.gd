class_name EditorMode
extends Node2D

signal editor_mode_changed(is_editing: bool)

var is_editing := false
var selected_vehicle: Vehicle = null
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null
var hovered_connection_point: ConnectionPoint = null
var is_recycle_mode := false
var ui_instance: Control = null
var panel_instance: Control = null

# 存储原始连接状态
var original_connection_states: Dictionary = {}
var original_connections: Dictionary = {}

# 吸附系统变量
var best_snap_score := 0.0
var best_snap_position := Vector2.ZERO
var best_snap_rotation := 0.0
var current_rotation := 0

# 移除库存限制，改为无限使用
var inventory: Dictionary = {}

func _ready():
	print("EditorMode 初始化 - Testground 场景")
	call_deferred("initialize_editor")

func _input(event):
	# 全局TAB键检测
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if is_editing:
			exit_editor_mode()
		else:
			if selected_vehicle == null:
				find_and_select_vehicle()
			if selected_vehicle:
				enter_editor_mode(selected_vehicle)
			else:
				print("错误: 未找到可编辑的车辆")
		return
	
	if not is_editing:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				cancel_placement()
			KEY_R:
				rotate_ghost_block()
			KEY_F:
				print_connection_points_info()
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_recycle_mode:
				try_remove_block()
			else:
				try_place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()

func _process(delta):
	if not is_editing or not current_ghost_block or not selected_vehicle:
		return
	
	# 减少计算频率（每2帧计算一次）
	if Engine.get_frames_drawn() % 2 == 0:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		
		find_best_snap_position(global_mouse_pos)
		
		if best_snap_score > 0:
			current_ghost_block.global_position = best_snap_position
			current_ghost_block.rotation = best_snap_rotation
			current_ghost_block.modulate = Color(0.5, 1, 0.5, 0.5)
		else:
			current_ghost_block.global_position = global_mouse_pos
			current_ghost_block.rotation = current_rotation * PI / 2
			current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.5)

func initialize_editor():
	print("正在初始化编辑器...")
	
	var testground = get_parent()
	if testground:
		var canvas_layer = testground.find_child("CanvasLayer", false, false)
		if canvas_layer:
			ui_instance = canvas_layer.find_child("Tankbuilderui", false, false)
			panel_instance = canvas_layer.find_child("Tankpanel", false, false)
			if ui_instance:
				print("成功找到UI: ", ui_instance.name)
		
		find_and_select_vehicle()
	
	if ui_instance:
		ui_instance.hide()
		connect_ui_signals()
	
	print("编辑器初始化完成")

func find_and_select_vehicle():
	var testground = get_parent()
	if testground:
		if panel_instance.selected_vehicle:
			selected_vehicle = panel_instance.selected_vehicle
			ui_instance.name_input.placeholder_text = selected_vehicle.vehicle_name
			print("找到车辆: ", selected_vehicle.vehicle_name, ui_instance.name_input)
			return

func find_vehicles_in_children(node: Node, result: Array):
	for child in node.get_children():
		if child is Vehicle:
			result.append(child)
		find_vehicles_in_children(child, result)

func connect_ui_signals():
	if ui_instance:
		if ui_instance.has_signal("block_selected") and not ui_instance.block_selected.is_connected(_on_block_selected):
			ui_instance.block_selected.connect(_on_block_selected)
		if ui_instance.has_signal("vehicle_saved") and not ui_instance.vehicle_saved.is_connected(_on_vehicle_saved):
			ui_instance.vehicle_saved.connect(_on_vehicle_saved)
		if ui_instance.has_signal("recycle_mode_toggled") and not ui_instance.recycle_mode_toggled.is_connected(_on_recycle_mode_toggled):
			ui_instance.recycle_mode_toggled.connect(_on_recycle_mode_toggled)

func enter_editor_mode(vehicle: Vehicle):
	if is_editing:
		exit_editor_mode()
	
	selected_vehicle = vehicle
	is_editing = true
	
	print("=== 进入编辑模式 ===")
	
	if ui_instance == null:
		initialize_editor()
		if ui_instance == null:
			print("严重错误: UI初始化失败")
			is_editing = false
			return
	
	save_original_connections()
	disconnect_all_blocks()
	enable_all_connection_points_for_editing()
	
	vehicle.control = Callable()
	
	ui_instance.show()
	# 移除库存设置，因为现在是无限使用
	# ui_instance.setup_inventory(inventory)
	
	editor_mode_changed.emit(true)
	print("=== 编辑模式就绪 ===")

func exit_editor_mode():
	if not is_editing:
		return
	
	print("=== 退出编辑模式 ===")
	
	restore_original_connections()
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	if ui_instance:
		ui_instance.hide()
	
	is_editing = false
	selected_vehicle = null
	editor_mode_changed.emit(false)
	print("=== 编辑模式已退出 ===")

func save_original_connections():
	original_connections.clear()
	
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point) and point.connected_to:
					var connection_key = get_connection_key(point, point.connected_to)
					original_connections[connection_key] = {
						"from_point": point,
						"to_point": point.connected_to,
						"from_block": block,
						"to_block": point.connected_to.find_parent_block()
					}

func get_connection_key(point_a: ConnectionPoint, point_b: ConnectionPoint) -> String:
	var block_a = point_a.find_parent_block()
	var block_b = point_b.find_parent_block()
	
	if not block_a or not block_b:
		return ""
	
	var paths = [str(block_a.get_path()) + ":" + point_a.name, str(block_b.get_path()) + ":" + point_b.name]
	paths.sort()
	return paths[0] + "<->" + paths[1]

func disconnect_all_blocks():
	if not selected_vehicle:
		return
	
	print("断开所有连接...")
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point) and point.connected_to:
					point.disconnect_joint()
			
			for joint in block.get_children():
				if joint is Joint2D and is_instance_valid(joint):
					joint.queue_free()

func enable_all_connection_points_for_editing():
	if not selected_vehicle:
		return
	
	print("启用所有连接点用于编辑...")
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(true)

func restore_original_connections():
	if not selected_vehicle:
		return
	
	print("恢复原始连接...")
	
	enable_all_connection_points_for_editing()
	await get_tree().process_frame
	
	var restored_count = 0
	for connection_key in original_connections:
		var connection = original_connections[connection_key]
		
		if (is_instance_valid(connection.from_point) and 
			is_instance_valid(connection.to_point) and
			is_instance_valid(connection.from_block) and
			is_instance_valid(connection.to_block)):
			
			if (connection.from_point.is_connection_enabled and 
				connection.to_point.is_connection_enabled and
				not connection.from_point.connected_to and
				not connection.to_point.connected_to):
				
				if connection.from_point.can_connect_with(connection.to_point):
					connection.from_point.request_connection(connection.from_point, connection.to_point)
					restored_count += 1
	
	print("成功恢复 ", restored_count, " 个连接")

func start_block_placement(scene_path: String):
	if not is_editing or not selected_vehicle:
		return
	
	print("开始放置块: ", scene_path.get_file())
	
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
	
	setup_ghost_block_collision(current_ghost_block)
	
	current_rotation = 0
	hovered_connection_point = null

func setup_ghost_block_collision(ghost: Node2D):
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

func rotate_ghost_block():
	if current_ghost_block:
		current_rotation = (current_rotation + 1) % 4
		current_ghost_block.rotation = current_rotation * PI / 2
		print("旋转块: ", rad_to_deg(current_ghost_block.rotation))
		
		# 旋转后重新检查连接点
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		find_best_snap_position(global_mouse_pos)

func find_best_snap_position(mouse_position: Vector2):
	best_snap_score = -1.0
	best_snap_position = mouse_position
	best_snap_rotation = 0.0
	hovered_connection_point = null
	
	if not selected_vehicle or not current_ghost_block:
		return
	
	# 首先检查连接点吸附（积木式拼接）
	var connection_snap = find_connection_point_snap(mouse_position)
	if connection_snap.score > 0:
		best_snap_score = connection_snap.score
		best_snap_position = connection_snap.position
		best_snap_rotation = connection_snap.rotation
		hovered_connection_point = connection_snap.connection_point
	else:
		# 如果没有连接点，检查普通位置吸附
		if is_near_vehicle(mouse_position) and not would_overlap_anywhere():
			best_snap_score = 1.0
			best_snap_position = mouse_position
			best_snap_rotation = current_rotation * PI / 2

func find_connection_point_snap(mouse_position: Vector2) -> Dictionary:
	var result = { "score": -1.0, "position": mouse_position, "rotation": 0.0, "connection_point": null }
	
	# 获取幽灵块的连接点
	var ghost_points = get_ghost_block_connection_points()
	if ghost_points.is_empty():
		return result
	
	# 检查车辆所有连接点
	for block in selected_vehicle.blocks:
		if not is_instance_valid(block):
			continue
		
		for vehicle_point in block.connection_points:
			if not is_instance_valid(vehicle_point) or not vehicle_point.is_connection_enabled or vehicle_point.connected_to:
				continue
			
			var vehicle_point_pos = get_connection_point_world_position(block, vehicle_point)
			var distance = mouse_position.distance_to(vehicle_point_pos)
			
			if distance < 35.0:  # 连接点吸附范围
				# 检查每个幽灵块连接点
				for ghost_point in ghost_points:
					if can_points_connect(vehicle_point, ghost_point):
						var score = 100.0 / (distance + 1.0)
						if score > result.score:
							result.score = score
							result.position = calculate_snap_position(vehicle_point, ghost_point, block)
							result.rotation = calculate_snap_rotation(block, vehicle_point, ghost_point)
							result.connection_point = vehicle_point
	
	return result

func get_connection_point_world_position(block: Block, point: ConnectionPoint) -> Vector2:
	return block.global_position + point.position.rotated(block.global_rotation)

func can_points_connect(point_a: ConnectionPoint, point_b: ConnectionPoint) -> bool:
	return (point_a.connection_type == point_b.connection_type and 
			point_a.is_connection_enabled and point_b.is_connection_enabled)

func calculate_snap_position(vehicle_point: ConnectionPoint, ghost_point: ConnectionPoint, vehicle_block: Block) -> Vector2:
	var vehicle_point_pos = get_connection_point_world_position(vehicle_block, vehicle_point)
	var ghost_local_offset = ghost_point.position.rotated(current_ghost_block.rotation)
	return vehicle_point_pos - ghost_local_offset

func calculate_snap_rotation(vehicle_block: Block, vehicle_point: ConnectionPoint, ghost_point: ConnectionPoint) -> float:
	var base_rotation = vehicle_block.global_rotation
	var vehicle_point_rotation = vehicle_point.rotation
	var ghost_point_rotation = ghost_point.rotation
	return base_rotation + vehicle_point_rotation - ghost_point_rotation + PI

func get_ghost_block_connection_points() -> Array:
	var points = []
	if current_ghost_block:
		var connection_points = current_ghost_block.find_children("*", "ConnectionPoint")
		for point in connection_points:
			if point is ConnectionPoint and point.is_connection_enabled:
				points.append(point)
	return points

func try_place_block():
	if not current_ghost_block or not selected_vehicle:
		print("无法放置: 没有选择块或车辆")
		return
	
	# 移除库存检查，所有方块都可以无限使用
	var block_name = current_ghost_block.scene_file_path.get_file().get_basename()
	
	if best_snap_score <= 0:
		print("错误: 必须靠近车辆或连接点放置")
		return
	
	print("放置块: ", block_name)
	
	# 只断开必要的连接，而不是所有连接
	var connections_to_disconnect = find_connections_to_disconnect_for_placement()
	disconnect_connections(connections_to_disconnect)
	
	var new_block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = best_snap_position
	new_block.rotation = best_snap_rotation
	
	var grid_positions = calculate_grid_positions_from_world(new_block)
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	
	# 建立新连接
	if hovered_connection_point:
		establish_connection(hovered_connection_point, new_block)
	
	# 重新启用连接点（只针对新块和受影响块）
	enable_connection_points_for_blocks([new_block] + get_affected_blocks())
	
	# 移除库存更新逻辑，因为所有方块都是无限的
	
	# 延迟检查稳定性，避免性能问题
	call_deferred("check_vehicle_stability")
	start_block_placement(current_block_scene.resource_path)

func find_connections_to_disconnect_for_placement() -> Array:
	# 只返回需要断开的连接，而不是所有连接
	var connections_to_disconnect = []
	if hovered_connection_point and hovered_connection_point.connected_to:
		connections_to_disconnect.append({
			"from": hovered_connection_point,
			"to": hovered_connection_point.connected_to
		})
	return connections_to_disconnect

func disconnect_connections(connections: Array):
	"""断开特定的连接（重命名以避免重复）"""
	for connection in connections:
		if is_instance_valid(connection.from):
			connection.from.disconnect_joint()
		if is_instance_valid(connection.to):
			connection.to.disconnect_joint()

func get_affected_blocks() -> Array:
	# 只返回受影响的块，而不是所有块
	var affected_blocks = []
	if hovered_connection_point:
		var parent_block = hovered_connection_point.find_parent_block()
		if parent_block:
			affected_blocks.append(parent_block)
	return affected_blocks

func enable_connection_points_for_blocks(blocks: Array):
	for block in blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(true)

func establish_connection(vehicle_point: ConnectionPoint, new_block: Block):
	var ghost_points = new_block.find_children("*", "ConnectionPoint")
	var best_ghost_point = null
	var best_score = -1.0
	
	for ghost_point in ghost_points:
		if ghost_point is ConnectionPoint and can_points_connect(vehicle_point, ghost_point):
			var ghost_point_pos = get_connection_point_world_position(new_block, ghost_point)
			var vehicle_point_pos = get_connection_point_world_position(vehicle_point.find_parent_block(), vehicle_point)
			var distance = ghost_point_pos.distance_to(vehicle_point_pos)
			var score = 100.0 / (distance + 1.0)
			
			if score > best_score:
				best_score = score
				best_ghost_point = ghost_point
	
	if best_ghost_point:
		vehicle_point.request_connection(vehicle_point, best_ghost_point)
		print("连接建立: ", vehicle_point.name, " -> ", best_ghost_point.name)

func try_remove_block():
	if not selected_vehicle:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	# 使用物理查询检测鼠标下的方块
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = global_mouse_pos
	query.collision_mask = 1  # 确保只检测正确的碰撞层
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:
			# 检查是否是命令块（不能移除）
			if block is Command:
				print("不能移除命令块")
				continue
			
			# 移除库存返还逻辑，因为所有方块都是无限的
			var block_name = block.block_name
			
			# 断开与被移除块相关的连接
			var connections_to_disconnect = find_connections_for_block(block)
			disconnect_connections(connections_to_disconnect)
			
			# 从车辆中移除方块
			print(selected_vehicle.blocks)
			print("             ")
			selected_vehicle.remove_block(block)
			print(selected_vehicle.blocks)
			
			# 重新启用受影响块的连接点
			enable_connection_points_for_blocks(get_affected_blocks_for_removal(block))
			
			# 移除UI库存更新逻辑
			
			# 检查车辆稳定性
			call_deferred("check_vehicle_stability")
			print("移除块: ", block_name)
			break

func find_connections_for_block(block: Block) -> Array:
	"""查找与指定块相关的所有连接"""
	var connections = []
	for point in block.connection_points:
		if point.connected_to:
			connections.append({
				"from": point,
				"to": point.connected_to
			})
	return connections

func get_affected_blocks_for_removal(removed_block: Block) -> Array:
	"""获取受移除操作影响的所有块"""
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
	hovered_connection_point = null
	print("放置已取消")

func is_near_vehicle(position: Vector2) -> bool:
	if not selected_vehicle:
		return false
	
	var vehicle_center = selected_vehicle.global_position
	var max_distance = 200.0
	return position.distance_to(vehicle_center) < max_distance

func would_overlap_anywhere() -> bool:
	if not current_ghost_block or not selected_vehicle:
		return true
	
	var expected_positions = calculate_grid_positions_from_world(current_ghost_block)
	for pos in expected_positions:
		if selected_vehicle.grid.has(pos):
			return true
	return false

func calculate_grid_positions_from_world(block: Block) -> Array:
	var grid_positions = []
	var world_pos = block.global_position
	
	if not selected_vehicle:
		return grid_positions
	
	var grid_center = Vector2i(
		floor((world_pos.x - selected_vehicle.global_position.x) / 16),
		floor((world_pos.y - selected_vehicle.global_position.y) / 16)
	)
	
	var block_size = get_block_size(block)
	for x in range(block_size.x):
		for y in range(block_size.y):
			var offset = Vector2i(x - block_size.x / 2, y - block_size.y / 2)
			var grid_pos = grid_center + offset
			grid_positions.append(grid_pos)
	
	return grid_positions

func get_block_size(block: Block) -> Vector2i:
	if block.has_method("get_size"):
		return block.size
	return Vector2i(1, 1)

func check_vehicle_stability():
	if not selected_vehicle:
		return
	
	# 使用标记法避免无限递归
	var checked_blocks = {}
	var command_blocks = []
	
	for block in selected_vehicle.blocks:
		if block is Command:
			command_blocks.append(block)
	
	if command_blocks.is_empty():
		print("警告: 车辆没有命令块！")
		return
	
	# 从命令块开始检查连接
	for command_block in command_blocks:
		check_connections_from_block(command_block, checked_blocks)
	
	# 报告未连接的块
	for block in selected_vehicle.blocks:
		if not checked_blocks.get(block, false) and not block is Command:
			print("警告: 块 ", block.block_name, " 未连接到命令块！")

func check_connections_from_block(block: Block, checked_blocks: Dictionary):
	if checked_blocks.get(block, false):
		return
	
	checked_blocks[block] = true
	
	for point in block.connection_points:
		if point.connected_to:
			var connected_block = point.connected_to.find_parent_block()
			if connected_block and not checked_blocks.get(connected_block, false):
				check_connections_from_block(connected_block, checked_blocks)

func print_connection_points_info():
	if not selected_vehicle:
		return
	
	print("=== 连接点信息 ===")
	for block in selected_vehicle.blocks:
		for point in block.connection_points:
			var info = point.name + " - 启用: " + str(point.is_connection_enabled)
			if point.connected_to:
				info += " - 已连接"
			print(info)
	print("=================")

func _on_block_selected(scene_path: String):
	print("UI选择块: ", scene_path.get_file())
	start_block_placement(scene_path)

func _on_vehicle_saved(vehicle_name: String):
	save_vehicle(vehicle_name)
	
	# 通知UI保存成功
	if ui_instance and ui_instance.has_method("on_vehicle_saved_successfully"):
		ui_instance.on_vehicle_saved_successfully()

func _on_recycle_mode_toggled(is_recycle: bool):
	is_recycle_mode = is_recycle
	print("回收模式: ", "启用" if is_recycle_mode else "禁用")
	
	if is_recycle_mode:
		Input.set_custom_mouse_cursor(load("res://assets/icons/saw_cursor.png"), Input.CURSOR_ARROW)
	else:
		Input.set_custom_mouse_cursor(null)

func save_vehicle(vehicle_name: String):
	if not selected_vehicle:
		print("错误: 没有选中的车辆")
		return
	
	print("正在保存车辆: ", vehicle_name)
	
	# 生成蓝图数据
	var blueprint_data = create_blueprint_data(vehicle_name)
	
	# 确定保存路径
	var blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	
	# 保存蓝图
	if save_blueprint(blueprint_data, blueprint_path):
		# 更新车辆引用
		selected_vehicle.vehicle_name = vehicle_name
		selected_vehicle.blueprint = blueprint_data
		
		print("车辆保存成功: ", blueprint_path)
	else:
		push_error("车辆保存失败")

func create_blueprint_data(vehicle_name: String) -> Dictionary:
	"""从当前车辆创建蓝图数据"""
	var blueprint_data = {
		"name": vehicle_name,
		"blocks": {},
		"vehicle_size": [0, 0]
	}
	
	var block_counter = 1
	var processed_blocks = {}
	
	# 计算车辆边界
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	# 首先计算所有网格位置的范围
	for grid_pos in selected_vehicle.grid:
		min_x = min(min_x, grid_pos.x)
		min_y = min(min_y, grid_pos.y)
		max_x = max(max_x, grid_pos.x)
		max_y = max(max_y, grid_pos.y)
	
	# 处理每个块
	for grid_pos in selected_vehicle.grid:
		var block = selected_vehicle.grid[grid_pos]
		if not processed_blocks.has(block):
			var relative_pos = Vector2i(grid_pos.x - min_x, grid_pos.y - min_y)
			var rotation_str = get_rotation_direction(block.global_rotation)
			
			blueprint_data["blocks"][str(block_counter)] = {
				"name": block.block_name,
				"path": block.scene_file_path,
				"base_pos": [relative_pos.x, relative_pos.y],
				"rotation": rotation_str,
			}
			block_counter += 1
			processed_blocks[block] = true
	
	blueprint_data["vehicle_size"] = [max_x - min_x + 1, max_y - min_y + 1]
	return blueprint_data

func get_rotation_direction(angle: float) -> String:
	"""将旋转角度转换为方向字符串"""
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
	"""将蓝图数据保存到文件"""
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
