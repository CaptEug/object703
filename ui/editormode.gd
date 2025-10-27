extends Control

@onready var tab_container = $TabContainer
@onready var description_label = $Panel/RichTextLabel
@onready var build_vehicle_button = $Panel/SaveButton
@onready var save_dialog = $SaveDialog
@onready var name_input = $Panel/NameInput
@onready var error_label = $SaveDialog/ErrorLabel
@onready var recycle_button = $Panel/DismantleButton
@onready var load_button = $Panel/LoadButton
@onready var repair_buttom = $Panel/RepairButton

var saw_cursor:Texture = preload("res://assets/icons/saw_cursor.png")

signal block_selected(scene_path: String)
signal vehicle_saved(vehicle_name: String)
signal recycle_mode_toggled(is_recycle_mode: bool)

const GRID_SIZE = 16
const BLOCK_PATHS = {
	"Firepower": "res://blocks/firepower/",
	"Mobility": "res://blocks/mobility/",
	"Command": "res://blocks/command/",
	"Building": "res://blocks/building/",
	"Structual": "res://blocks/structual/",
	"Auxiliary": "res://blocks/auxiliary/"
}

const BLUEPRINT = {
	"BLUEPRINT":"res://vehicles/blueprint/"
}

var item_lists = {}
var is_recycle_mode := false
var is_loading_mode := false
var original_tab_names := []

# === 炮塔编辑模式变量 ===
var is_turret_editing_mode := false
var current_editing_turret: TurretRing = null
var turret_cursor:Texture = preload("res://assets/icons/file.png")
var turret_grid_previews := []

# === 炮塔放置模式变量 ===
var is_turret_placement_mode := false
var current_placement_turret: TurretRing = null

# === 炮塔连接点吸附系统 ===
var available_turret_connectors: Array[RigidBodyConnector] = []
var available_block_connectors: Array[RigidBodyConnector] = []
var turret_snap_config: Dictionary = {}

# === 蓝图显示功能 ===
var blueprint_ghosts := []
var blueprint_data: Dictionary
var is_showing_blueprint := false
var ghost_data_map = {}

# === 编辑器模式变量 ===
var is_editing := false
var selected_vehicle: Vehicle = null
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null
var panel_instance: Control = null
var camera:Camera2D

# === 方块移动功能变量 ===
var is_moving_block := false
var moving_block: Block = null
var moving_block_original_position: Vector2
var moving_block_original_rotation: float
var moving_block_original_grid_positions: Array
var moving_block_ghost: Node2D = null
var moving_snap_config: Dictionary = {}
var is_mouse_pressed := false
var drag_timer: float = 0.0
var is_dragging := false
var DRAG_DELAY: float = 0.2

# 连接点吸附系统
var current_ghost_connection_index := 0
var current_vehicle_connection_index = 0
var available_ghost_points: Array[ConnectionPoint] = []
var available_vehicle_points: Array[ConnectionPoint] = []
var current_snap_config: Dictionary = {}
var snap_config
var is_first_block := true
var is_new_vehicle := false

# 存储原始连接状态
var original_connections: Dictionary = {}
var is_ui_interaction: bool = false

# 虚影数据类
class GhostData:
	var grid_positions: Array
	var rotation_deg: float

func _ready():
	_connect_block_buttons()
	camera = get_tree().current_scene.find_child("Camera2D") as Camera2D
	build_vehicle_button.pressed.connect(_on_build_vehicle_pressed)
	save_dialog.get_ok_button().pressed.connect(_on_save_confirmed)
	save_dialog.close_requested.connect(_on_save_canceled)
	name_input.text_changed.connect(_on_name_input_changed)
	recycle_button.pressed.connect(_on_recycle_button_pressed)
	repair_buttom.pressed.connect(_on_repair_button_pressed)
	create_tabs()
	
	save_dialog.hide()
	error_label.hide()
	
	var connect_result = vehicle_saved.connect(_on_vehicle_saved)
	if connect_result == OK:
		print("✅ vehicle_saved Signal connected successfully")
	else:
		print("❌ vehicle_saved 信号连接失败，错误代码:", connect_result)
	
	update_recycle_button()
	load_all_blocks()
	
	call_deferred("initialize_editor")

func _connect_block_buttons():
	var block_buttons = get_tree().get_nodes_in_group("block_buttons")
	for button in block_buttons:
		if button is BaseButton:
			button.pressed.connect(_on_block_button_pressed)

func _on_block_button_pressed():
	is_ui_interaction = true
	await get_tree().create_timer(0.2).timeout
	is_ui_interaction = false

func _input(event):
	if get_viewport().gui_get_hovered_control():
		return
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
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
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		if is_editing:
			if is_turret_placement_mode:
				exit_turret_placement_mode()
			else:
				enter_turret_placement_mode()
		return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_editing and not is_turret_placement_mode and not is_turret_editing_mode and not is_recycle_mode and not is_moving_block:
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			var clicked_turret = get_turret_at_position(global_mouse_pos)
			
			if clicked_turret:
				enter_turret_editing_mode(clicked_turret)
				return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_turret_editing_mode:
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			
			var can_place = false
			if current_editing_turret and current_ghost_block:
				can_place = turret_snap_config and not turret_snap_config.is_empty()
			
			if not can_place:
				exit_turret_editing_mode()
				return
			else:
				try_place_turret_block()
				return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_turret_placement_mode:
			try_place_turret_block_combined()
			return
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_turret_editing_mode:
			exit_turret_editing_mode()
			return
		if is_turret_placement_mode:
			exit_turret_placement_mode()
			return
	
	if not is_editing:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if is_turret_editing_mode:
				exit_turret_editing_mode()
			elif is_turret_placement_mode:
				exit_turret_placement_mode()
			elif is_moving_block:
				cancel_block_move()
			else:
				cancel_placement()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_mouse_pressed = true
				drag_timer = 0.0
				is_dragging = false
				
				if is_recycle_mode:
					try_remove_block()
				
				if is_moving_block:
					place_moving_block()
					return
					
				if not is_recycle_mode and not current_ghost_block and not is_turret_editing_mode and not is_turret_placement_mode:
					var mouse_pos = get_viewport().get_mouse_position()
					var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
					var block = get_block_at_position(global_mouse_pos)
					if block:
						print("检测到方块，开始拖拽计时")
			else:
				is_mouse_pressed = false
				
				if is_dragging and is_moving_block:
					place_moving_block()
				elif not is_dragging and not is_moving_block and not is_recycle_mode and not is_turret_editing_mode and not is_turret_placement_mode:
					try_place_block()
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				if is_turret_editing_mode:
					exit_turret_editing_mode()
				elif is_turret_placement_mode:
					exit_turret_placement_mode()
				elif is_moving_block:
					cancel_block_move()
				else:
					cancel_placement()
			KEY_R:
				if is_moving_block and moving_block_ghost:
					rotate_moving_ghost()
				elif current_ghost_block and not is_turret_editing_mode and not is_turret_placement_mode:
					rotate_ghost_connection()
			KEY_X:
				if is_recycle_mode:
					exit_recycle_mode()
				else:
					enter_recycle_mode()

func _process(delta):
	if is_editing and selected_vehicle:
		camera.sync_rotation_to_vehicle(selected_vehicle)
	
	update_turret_mode_status()
	
	if is_showing_blueprint and not blueprint_ghosts.is_empty():
		update_ghosts_transform()	
	
	if is_editing and is_recycle_mode and selected_vehicle:
		update_recycle_highlight()
		
	if not is_editing or not selected_vehicle:
		return
	
	if is_mouse_pressed and not is_dragging and not is_moving_block and not is_recycle_mode and not current_ghost_block and not is_turret_editing_mode and not is_turret_placement_mode:
		drag_timer += delta
		if drag_timer >= DRAG_DELAY:
			start_drag_block()
	
	if is_moving_block and moving_block_ghost:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_moving_ghost_position(global_mouse_pos)
	elif current_ghost_block and Engine.get_frames_drawn() % 2 == 0:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		if is_turret_placement_mode:
			update_turret_placement_mode_ghost_combined()
		elif is_turret_editing_mode:
			update_turret_placement_feedback()
		else:
			update_ghost_block_position(global_mouse_pos)
	
	if is_turret_editing_mode and current_ghost_block:
		update_turret_placement_feedback()

# === 炮塔放置模式功能 ===
func _on_turret_placement_button_pressed():
	if is_turret_placement_mode:
		exit_turret_placement_mode()
	else:
		enter_turret_placement_mode()

func enter_turret_placement_mode():
	if is_turret_placement_mode:
		return
	
	if is_recycle_mode:
		exit_recycle_mode()
	
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	if is_moving_block:
		cancel_block_move()
	
	is_turret_placement_mode = true
	
	if current_ghost_block:
		current_ghost_block.visible = false
	
	clear_tab_container_selection()
	
	# 尝试找到可用的炮塔
	current_placement_turret = find_available_turret_for_placement()
	if current_placement_turret:
		highlight_current_placement_turret(true)
		print("进入炮塔放置模式 - 目标炮塔: ", current_placement_turret.name)
	else:
		print("进入炮塔放置模式 - 无可用炮塔，使用普通连接点")
	
	# 高亮所有可用的连接点
	highlight_available_connection_points(true)

func exit_turret_placement_mode():
	if not is_turret_placement_mode:
		return
	
	is_turret_placement_mode = false
	Input.set_custom_mouse_cursor(null)
	
	# 取消高亮
	highlight_current_placement_turret(false)
	highlight_available_connection_points(false)
	
	if current_ghost_block:
		current_ghost_block.visible = true
	
	current_placement_turret = null
	
	print("退出炮塔放置模式")

func find_available_turret_for_placement() -> TurretRing:
	var available_turrets = get_turret_blocks()
	if available_turrets.is_empty():
		return null
	
	# 返回第一个有可用连接点的炮塔
	for turret in available_turrets:
		if is_instance_valid(turret):
			var connectors = turret.find_children("*", "RigidBodyConnector", true)
			for connector in connectors:
				if connector is RigidBodyConnector and connector.is_connection_enabled and connector.connected_to == null:
					return turret
	
	return null

func highlight_current_placement_turret(highlight: bool):
	if not current_placement_turret or not is_instance_valid(current_placement_turret):
		return
	
	if highlight:
		current_placement_turret.modulate = Color(0.8, 1, 0.8, 1.0)
	else:
		current_placement_turret.modulate = Color.WHITE

func highlight_available_connection_points(highlight: bool):
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			# 如果是炮塔，高亮RigidBodyConnector
			if block is TurretRing:
				var connectors = block.find_children("*", "RigidBodyConnector", true)
				for connector in connectors:
					if connector is RigidBodyConnector and connector.is_connection_enabled and connector.connected_to == null:
						if highlight:
							connector.modulate = Color(1, 0.8, 0.3, 1.0)
						else:
							connector.modulate = Color.WHITE
			# 如果是普通方块，高亮ConnectionPoint
			else:
				for point in block.connection_points:
					if is_instance_valid(point) and point.is_connection_enabled and point.connected_to == null:
						if highlight:
							point.modulate = Color(0.8, 0.8, 1.0, 1.0)
						else:
							point.modulate = Color.WHITE

func update_turret_placement_mode_ghost_combined():
	if not is_turret_placement_mode or not current_ghost_block:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	# 首先尝试炮塔连接
	var turret_snap_found = false
	
	if current_placement_turret:
		var available_turret_connectors = get_current_turret_available_connectors()
		available_block_connectors = get_ghost_block_available_rigidbody_connectors()
		
		if not available_turret_connectors.is_empty() and not available_block_connectors.is_empty():
			var snap_config = get_turret_placement_snap_config(global_mouse_pos, available_turret_connectors)
			
			if snap_config and not snap_config.is_empty():
				var ghost_position = calculate_turret_ghost_position_with_location(snap_config.turret_connector, snap_config.block_connector)
				var ghost_rotation = calculate_proper_turret_rotation(snap_config.turret_connector, snap_config.block_connector)
				
				current_ghost_block.global_position = ghost_position
				current_ghost_block.global_rotation = ghost_rotation + camera.target_rot
				current_ghost_block.base_rotation_degree = rad_to_deg(ghost_rotation)
				current_ghost_block.modulate = Color(0.5, 1, 0.5, 0.7)
				turret_snap_config = snap_config
				turret_snap_found = true
	
	# 如果没有找到炮塔连接，尝试普通连接点
	if not turret_snap_found:
		# 使用普通连接点吸附系统
		available_vehicle_points = selected_vehicle.get_available_points_near_position(global_mouse_pos, 50.0)
		available_ghost_points = get_ghost_block_available_connection_points()
		
		if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
			current_ghost_block.global_position = global_mouse_pos
			current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
			current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.7)
			current_snap_config = {}
			turret_snap_config = {}
		else:
			var snap_config = get_current_snap_config()
			
			if snap_config:
				current_ghost_block.global_position = snap_config.ghost_position
				current_ghost_block.global_rotation = snap_config.ghost_rotation
				current_ghost_block.modulate = Color(0.5, 1, 0.5, 0.7)
				current_snap_config = snap_config
				turret_snap_config = {}
			else:
				current_ghost_block.global_position = global_mouse_pos
				current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
				current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.7)
				current_snap_config = {}
				turret_snap_config = {}

func get_current_turret_available_connectors() -> Array[RigidBodyConnector]:
	var connectors: Array[RigidBodyConnector] = []
	
	if not current_placement_turret or not is_instance_valid(current_placement_turret):
		return connectors
	
	var block_connectors = current_placement_turret.find_children("*", "RigidBodyConnector", true)
	for connector in block_connectors:
		if connector is RigidBodyConnector and connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	return connectors

func get_turret_placement_snap_config(mouse_position: Vector2, available_turret_connectors: Array[RigidBodyConnector]) -> Dictionary:
	if available_turret_connectors.is_empty() or available_block_connectors.is_empty():
		return {}
	
	var best_config = {}
	var min_distance = INF
	
	for turret_connector in available_turret_connectors:
		for block_connector in available_block_connectors:
			if not can_connectors_connect(turret_connector, block_connector):
				continue
			
			var distance = mouse_position.distance_to(turret_connector.global_position)
			
			if distance < turret_connector.snap_distance_threshold:
				var ghost_position = calculate_turret_ghost_position_with_location(turret_connector, block_connector)
				var ghost_rotation = calculate_proper_turret_rotation(turret_connector, block_connector)
				
				if distance < min_distance:
					min_distance = distance
					best_config = {
						"turret_connector": turret_connector,
						"block_connector": block_connector,
						"ghost_position": ghost_position,
						"ghost_rotation": ghost_rotation,
						"turret_block": current_placement_turret
					}
	
	return best_config

func try_place_turret_block_combined():
	if not is_turret_placement_mode:
		return
	
	if not current_block_scene:
		return
	
	# 优先尝试炮塔连接
	if turret_snap_config and not turret_snap_config.is_empty():
		place_turret_block_via_turret_connection()
	# 其次尝试普通连接点
	elif current_snap_config and not current_snap_config.is_empty():
		place_turret_block_via_regular_connection()
	else:
		print("❌ 没有有效的吸附配置")

func place_turret_block_via_turret_connection():
	print("=== 炮塔连接点放置调试 ===")
	
	var new_block: Block = current_block_scene.instantiate()
	
	if new_block is CollisionObject2D:
		new_block.collision_layer = 2
		new_block.collision_mask = 2
	
	# 使用与虚影完全相同的位置和旋转计算方法
	var final_position = calculate_turret_ghost_position_with_location(
		turret_snap_config.turret_connector, 
		turret_snap_config.block_connector
	)
	var final_rotation = calculate_proper_turret_rotation(
		turret_snap_config.turret_connector,
		turret_snap_config.block_connector
	)
	new_block.global_position = final_position
	new_block.global_rotation = final_rotation
	new_block.base_rotation_degree = rad_to_deg(final_rotation)
	
	# 计算网格位置
	var grid_positions = calculate_turret_block_grid_positions_from_placement(new_block)
	
	# 检查位置是否可用
	var position_available = true
	for pos in grid_positions:
		if not turret_snap_config.turret_block.is_position_available(pos):
			position_available = false
			print("❌ 位置被占用: ", pos)
			break
	
	if not position_available:
		new_block.queue_free()
		print("❌ 位置不可用，放置失败")
		return
	
	# 添加到炮塔
	turret_snap_config.turret_block.add_block_to_turret(new_block, grid_positions)
	
	# 建立连接
	if turret_snap_config.turret_connector and turret_snap_config.block_connector:
		establish_turret_rigidbody_connection(turret_snap_config.turret_connector, new_block, turret_snap_config.block_connector)
	
	await new_block.connect_aready()
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	print("✅ 炮塔块通过炮塔连接点放置成功")

func place_turret_block_via_regular_connection():
	print("=== 普通连接点放置炮塔块调试 ===")
	
	if not current_snap_config:
		return
	
	var connections_to_disconnect = find_connections_to_disconnect_for_placement()
	disconnect_connections(connections_to_disconnect)
	
	var grid_positions = current_snap_config.positions
	var new_block: Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_snap_config.ghost_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	selected_vehicle.control = control
	
	# 建立普通连接
	if current_snap_config.vehicle_point and current_snap_config.ghost_point:
		establish_connection(current_snap_config.vehicle_point, new_block, current_snap_config.ghost_point)
	
	await new_block.connect_aready()
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	print("✅ 炮塔块通过普通连接点放置成功")

# === 炮塔编辑模式功能 ===
func enter_turret_editing_mode(turret: TurretRing):
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	is_turret_editing_mode = true
	current_editing_turret = turret
	
	reset_turret_rotation(turret)
	disable_turret_rotation(turret)
	
	dim_non_turret_blocks(true)
	
	if current_ghost_block:
		current_ghost_block.visible = false
	
	if is_moving_block:
		cancel_block_move()
	
	if is_recycle_mode:
		exit_recycle_mode()
	
	if is_turret_placement_mode:
		exit_turret_placement_mode()
	
	clear_tab_container_selection()
	
	highlight_current_editing_turret(turret)
	
	show_turret_grid_preview()

func exit_turret_editing_mode():
	if not is_turret_editing_mode:
		return
	
	is_turret_editing_mode = false
	
	if current_editing_turret:
		enable_turret_rotation(current_editing_turret)
	
	Input.set_custom_mouse_cursor(null)
	
	dim_non_turret_blocks(false)
	
	if current_editing_turret:
		highlight_current_editing_turret(current_editing_turret, false)
	
	hide_turret_grid_preview()
	
	turret_snap_config = {}
	available_turret_connectors.clear()
	available_block_connectors.clear()
	
	if current_ghost_block:
		current_ghost_block.visible = true
	
	current_editing_turret = null

func reset_turret_rotation(turret: TurretRing):
	if turret and is_instance_valid(turret):
		turret.reset_turret_rotation()

func disable_turret_rotation(turret: TurretRing):
	if turret and is_instance_valid(turret):
		turret.lock_turret_rotation()

func enable_turret_rotation(turret: TurretRing):
	if turret and is_instance_valid(turret):
		turret.unlock_turret_rotation()

func dim_non_turret_blocks(dim: bool):
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			if block is TurretRing:
				continue
			
			if dim:
				block.modulate = Color(0.5, 0.5, 0.5, 0.6)
			else:
				block.modulate = Color.WHITE

func highlight_current_editing_turret(turret: TurretRing, highlight: bool = true):
	if not turret or not is_instance_valid(turret):
		return
	
	if highlight:
		turret.modulate = Color(1, 0.8, 0.3, 1.0)
	else:
		turret.modulate = Color.WHITE

# === 炮塔连接点吸附系统 ===
func update_turret_placement_feedback():
	if not is_turret_editing_mode or not current_ghost_block or not current_editing_turret:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	available_turret_connectors = get_turret_available_rigidbody_connectors()
	available_block_connectors = get_ghost_block_available_rigidbody_connectors()
	
	if available_turret_connectors.is_empty() or available_block_connectors.is_empty():
		current_ghost_block.global_position = global_mouse_pos
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.7)
		turret_snap_config = {}
		return
	
	var snap_config = get_current_turret_snap_config(global_mouse_pos)
	
	if snap_config and not snap_config.is_empty():
		# 使用与放置时相同的计算方法
		var ghost_position = calculate_turret_ghost_position_with_location(snap_config.turret_connector, snap_config.block_connector)
		var ghost_rotation = snap_config.ghost_rotation
		
		current_ghost_block.global_position = ghost_position
		current_ghost_block.global_rotation = ghost_rotation + camera.target_rot
		current_ghost_block.base_rotation_degree = rad_to_deg(ghost_rotation)  # 更新基础旋转角度
		current_ghost_block.modulate = Color(0.5, 1, 0.5, 0.7)
		turret_snap_config = snap_config
	else:
		current_ghost_block.global_position = global_mouse_pos
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.base_rotation_degree = 0
		current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.7)
		turret_snap_config = {}


func calculate_turret_ghost_position(turret_connector: RigidBodyConnector, block_connector: RigidBodyConnector) -> Vector2:
	"""计算炮塔虚影位置，确保与放置时一致"""
	# 获取炮塔连接器的全局位置
	var turret_connector_global = turret_connector.global_position
	
	# 获取块连接器在幽灵块局部坐标系中的位置
	var block_connector_local = block_connector.position
	
	# 计算幽灵块的位置：炮塔连接器位置 - 块连接器局部位置（考虑旋转）
	var ghost_rotation = current_ghost_block.global_rotation
	var rotated_block_connector = block_connector_local.rotated(ghost_rotation)
	
	return turret_connector_global - rotated_block_connector

func get_turret_available_rigidbody_connectors() -> Array[RigidBodyConnector]:
	var connectors: Array[RigidBodyConnector] = []
	
	if not current_editing_turret or not is_instance_valid(current_editing_turret):
		return connectors
	
	var all_connectors = current_editing_turret.find_children("*", "RigidBodyConnector", true)
	for connector in all_connectors:
		if connector is RigidBodyConnector and connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	return connectors

func get_ghost_block_available_rigidbody_connectors() -> Array[RigidBodyConnector]:
	var connectors: Array[RigidBodyConnector] = []
	
	if not current_ghost_block:
		return connectors
	
	var all_connectors = current_ghost_block.find_children("*", "RigidBodyConnector", true)
	for connector in all_connectors:
		if connector is RigidBodyConnector and connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	return connectors

func get_current_turret_snap_config(mouse_position: Vector2) -> Dictionary:
	if available_turret_connectors.is_empty() or available_block_connectors.is_empty():
		return {}
	
	var best_config = {}
	var min_distance = INF
	
	for turret_connector in available_turret_connectors:
		for block_connector in available_block_connectors:
			if not can_connectors_connect(turret_connector, block_connector):
				continue
			
			var distance = mouse_position.distance_to(turret_connector.global_position)
			
			if distance < turret_connector.snap_distance_threshold:
				# 使用location计算虚影位置和旋转
				var ghost_position = calculate_turret_ghost_position_with_location(turret_connector, block_connector)
				var ghost_rotation = calculate_proper_turret_rotation(turret_connector, block_connector)
				
				if distance < min_distance:
					min_distance = distance
					best_config = {
						"turret_connector": turret_connector,
						"block_connector": block_connector,
						"ghost_position": ghost_position,
						"ghost_rotation": ghost_rotation,
						"turret_block": current_editing_turret
					}
	
	return best_config

func calculate_proper_turret_rotation(turret_connector: RigidBodyConnector, block_connector: RigidBodyConnector) -> float:
	"""计算正确的炮塔块旋转角度"""
	# 获取连接点的旋转
	var turret_connector_rotation = turret_connector.get_parent().global_rotation
	var block_connector_rotation = block_connector.get_parent().global_rotation
	
	# 计算目标旋转：炮塔连接器旋转 - 块连接器旋转 + 180度（使方向相对）
	var target_rotation = turret_connector_rotation - block_connector_rotation
	
	# 对齐到最近的90度倍数，并确保在-180到180范围内
	var degrees = rad_to_deg(target_rotation)
	var aligned_degrees = round(degrees / 90) * 90
	aligned_degrees = wrapf(aligned_degrees, -180, 180)
	return deg_to_rad(aligned_degrees)

func calculate_turret_ghost_position_with_location(turret_connector: RigidBodyConnector, block_connector: RigidBodyConnector) -> Vector2:
	"""使用location计算虚影位置"""
	# 获取炮塔连接器的全局位置
	var turret_connector_global = turret_connector.global_position
	
	# 获取块连接器的location（网格位置）
	var block_connector_location = block_connector.location
	
	# 将location转换为实际偏移（乘以网格大小）
	var block_connector_offset = Vector2(block_connector_location.x * GRID_SIZE, block_connector_location.y * GRID_SIZE)
	
	# 计算正确的旋转角度
	var ghost_rotation = calculate_proper_turret_rotation(turret_connector, block_connector)
	
	# 计算幽灵块的位置：炮塔连接器位置 - 块连接器偏移（考虑旋转）
	var rotated_block_connector = block_connector_offset.rotated(ghost_rotation)
	
	var result = turret_connector_global - rotated_block_connector
	
	return result

func calculate_turret_aligned_rotation(turret_connector: RigidBodyConnector, block_connector: RigidBodyConnector) -> float:
	"""计算炮塔对齐的旋转角度"""
	# 获取连接点的旋转
	var turret_connector_rotation = turret_connector.global_rotation
	var block_connector_rotation = block_connector.rotation
	
	# 计算目标旋转（使连接点方向相对）
	var target_rotation = turret_connector_rotation - block_connector_rotation + PI
	
	# 对齐到最近的90度倍数
	var degrees = rad_to_deg(target_rotation)
	var aligned_degrees = round(degrees / 90) * 90
	aligned_degrees = wrapf(aligned_degrees, -180, 180)
	
	return deg_to_rad(aligned_degrees)

func can_connectors_connect(connector_a: RigidBodyConnector, connector_b: RigidBodyConnector) -> bool:
	if not connector_a or not connector_b:
		return false
	
	if connector_a.connection_type != connector_b.connection_type:
		return false
	
	if not connector_a.is_connection_enabled or not connector_b.is_connection_enabled:
		return false
	
	if connector_a.connected_to != null or connector_b.connected_to != null:
		return false
	
	var a_is_block = connector_a.is_attached_to_block()
	var b_is_block = connector_b.is_attached_to_block()
	
	if a_is_block and b_is_block:
		return false
	
	if not a_is_block and not b_is_block:
		return false
	
	return true

func calculate_turret_block_grid_positions_from_placement(block: Block) -> Array:
	var positions = []
	
	if not turret_snap_config or turret_snap_config.is_empty():
		return positions
	
	# 使用连接点的location来计算网格位置
	var turret_connector = turret_snap_config.turret_connector
	var block_connector = turret_snap_config.block_connector
	
	print("  炮塔网格位置计算:")
	print("    炮塔连接器location: ", turret_connector.location)
	print("    块连接器location: ", block_connector.location)
	print("    块旋转角度: ", block.base_rotation_degree)
	print("    块大小: ", block.size)
	
	# 计算基础网格位置（基于炮塔连接器的location）
	var base_pos = Vector2i(turret_connector.location.x, turret_connector.location.y)
	
	print("    基础网格位置: ", base_pos)
	
	# 根据块的大小和旋转计算所有网格位置
	for x in range(block.size.x):
		for y in range(block.size.y):
			var grid_pos: Vector2i
			
			# 根据旋转调整偏移（考虑块连接器的location）
			var offset_x = x - block_connector.location.x
			var offset_y = y - block_connector.location.y
			
			match int(block.base_rotation_degree):
				0:
					grid_pos = base_pos + Vector2i(offset_x, offset_y)
				90:
					grid_pos = base_pos + Vector2i(-offset_y, offset_x)
				-90:
					grid_pos = base_pos + Vector2i(offset_y, -offset_x)
				180, -180:
					grid_pos = base_pos + Vector2i(-offset_x, -offset_y)
				_:
					grid_pos = base_pos + Vector2i(offset_x, offset_y)
			
			positions.append(grid_pos)
	
	print("    所有网格位置: ", positions)
	return positions

func try_place_turret_block():
	if not is_turret_editing_mode or not current_editing_turret:
		print("❌ 不在炮塔编辑模式")
		return
	
	if not current_block_scene:
		print("❌ 没有当前块场景")
		return
	
	if not turret_snap_config or turret_snap_config.is_empty():
		print("❌ 没有吸附配置")
		return
	
	print("=== 炮塔放置调试 ===")
	
	var new_block: Block = current_block_scene.instantiate()
	
	if new_block is CollisionObject2D:
		new_block.collision_layer = 2
		new_block.collision_mask = 2
	
	# 使用与虚影完全相同的位置和旋转计算方法
	var final_position = calculate_turret_ghost_position_with_location(
		turret_snap_config.turret_connector, 
		turret_snap_config.block_connector
	)
	var final_rotation = calculate_proper_turret_rotation(
		turret_snap_config.turret_connector,
		turret_snap_config.block_connector
	)
	new_block.global_position = final_position
	new_block.global_rotation = final_rotation
	new_block.base_rotation_degree = rad_to_deg(final_rotation)
	
	# 计算网格位置（使用与虚影相同的逻辑）
	var grid_positions = calculate_turret_block_grid_positions_from_placement(new_block)
	
	var position_available = true
	for pos in grid_positions:
		if not current_editing_turret.is_position_available(pos):
			position_available = false
			print("❌ 位置被占用: ", pos)
			break
	
	if not position_available:
		new_block.queue_free()
		print("❌ 位置不可用，放置失败")
		return
	
	current_editing_turret.add_block_to_turret(new_block, grid_positions)
	
	if turret_snap_config.turret_connector and turret_snap_config.block_connector:
		establish_turret_rigidbody_connection(turret_snap_config.turret_connector, new_block, turret_snap_config.block_connector)
	
	await new_block.connect_aready()
	start_block_placement_with_rotation(current_block_scene.resource_path)

	
func establish_turret_rigidbody_connection(turret_connector: RigidBodyConnector, new_block: Block, block_connector: RigidBodyConnector):
	var new_block_connectors = new_block.find_children("*", "RigidBodyConnector")
	var target_connector = null
	
	for connector in new_block_connectors:
		if connector is RigidBodyConnector and connector.name == block_connector.name:
			target_connector = connector
			break
	
	if target_connector is RigidBodyConnector:
		target_connector.is_connection_enabled = true
		turret_connector.try_connect(target_connector)

# === 炮塔检测功能 ===
func has_turret_blocks() -> bool:
	if not selected_vehicle:
		return false
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			if block is TurretRing:
				return true
			if block.get_script() and "TurretRing" in block.get_script().resource_path:
				return true
	
	return false

func get_turret_blocks() -> Array:
	var turrets = []
	if not selected_vehicle:
		return turrets
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			if block is TurretRing:
				turrets.append(block)
			elif block.get_script() and "TurretRing" in block.get_script().resource_path:
				turrets.append(block)
	
	return turrets

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

func update_turret_mode_status():
	if is_editing and selected_vehicle:
		var has_turrets = has_turret_blocks()
		var turret_count = get_turret_blocks().size()
		
		# 显示炮塔放置模式状态
		if is_turret_placement_mode:
			var mode_info = "炮塔放置模式激活"
			if current_placement_turret:
				mode_info += " - 连接到炮塔: " + current_placement_turret.name
			else:
				mode_info += " - 使用普通连接点"
			print(mode_info)

# === 炮塔网格预览功能 ===
func show_turret_grid_preview():
	hide_turret_grid_preview()
	
	if current_editing_turret and is_instance_valid(current_editing_turret):
		create_turret_grid_preview(current_editing_turret)

func hide_turret_grid_preview():
	for preview in turret_grid_previews:
		if is_instance_valid(preview):
			preview.queue_free()
	turret_grid_previews.clear()

func create_turret_grid_preview(turret: TurretRing):
	var grid_lines = Line2D.new()
	grid_lines.width = 1.0
	grid_lines.default_color = Color(0, 1, 0, 0.3)
	
	var bounds = turret.get_turret_grid_bounds()
	var min_x = bounds.min_x
	var min_y = bounds.min_y
	var max_x = bounds.max_x
	var max_y = bounds.max_y
	
	var points = []
	
	for x in range(min_x, max_x + 1):
		var line_x = x * GRID_SIZE
		points.append(Vector2(line_x, min_y * GRID_SIZE))
		points.append(Vector2(line_x, max_y * GRID_SIZE))
		points.append(Vector2(line_x, min_y * GRID_SIZE))
	
	for y in range(min_y, max_y + 1):
		var line_y = y * GRID_SIZE
		points.append(Vector2(min_x * GRID_SIZE, line_y))
		points.append(Vector2(max_x * GRID_SIZE, line_y))
		points.append(Vector2(min_x * GRID_SIZE, line_y))
	
	grid_lines.points = points
	turret.turret.add_child(grid_lines)
	turret_grid_previews.append(grid_lines)
	
	var connection_points = turret.get_available_connection_points()
	for point in connection_points:
		var point_marker = ColorRect.new()
		point_marker.size = Vector2(6, 6)
		point_marker.position = point.position - Vector2(3, 3)
		point_marker.color = Color(1, 1, 0, 0.8)
		turret.turret.add_child(point_marker)
		turret_grid_previews.append(point_marker)
	
	for grid_pos in turret.turret_grid:
		var occupied_marker = ColorRect.new()
		occupied_marker.size = Vector2(GRID_SIZE - 4, GRID_SIZE - 4)
		occupied_marker.position = Vector2(grid_pos.x * GRID_SIZE + 2, grid_pos.y * GRID_SIZE + 2)
		occupied_marker.color = Color(1, 0, 0, 0.3)
		turret.turret.add_child(occupied_marker)
		turret_grid_previews.append(occupied_marker)

# === UI 相关函数 ===
func create_tabs():
	for child in tab_container.get_children():
		child.queue_free()
	
	create_tab_with_itemlist("All")
	
	for category in BLOCK_PATHS:
		create_tab_with_itemlist(category)
	
	for tab_name in item_lists:
		item_lists[tab_name].item_selected.connect(_on_item_selected.bind(tab_name))
	
	original_tab_names = []
	for i in range(tab_container.get_tab_count()):
		original_tab_names.append(tab_container.get_tab_title(i))

func create_tab_with_itemlist(tab_name: String):
	var item_list = ItemList.new()
	item_list.name = tab_name
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.max_columns = 0
	item_list.icon_mode = ItemList.ICON_MODE_TOP
	item_list.fixed_column_width = 100
	item_list.fixed_icon_size = Vector2(64, 64)
	item_list.allow_reselect = false
	item_list.allow_search = false
	
	tab_container.add_child(item_list)
	item_lists[tab_name] = item_list

func load_all_blocks():
	var all_blocks = []
	var categorized_blocks = {}
	
	for category in BLOCK_PATHS:
		categorized_blocks[category] = []
		var dir = DirAccess.open(BLOCK_PATHS[category])
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".tscn"):
					var scene_path = BLOCK_PATHS[category] + file_name
					var scene = load(scene_path)
					var block = scene.instantiate()
					if block is Block:
						all_blocks.append({
							"name": block.block_name,
							"icon": block.get_icon_texture(),
							"path": scene_path
						})
						categorized_blocks[category].append({
							"name": block.block_name,
							"icon": block.get_icon_texture(),
							"path": scene_path
						})
						block.queue_free()
				file_name = dir.get_next()
	
	populate_item_list(item_lists["All"], all_blocks)
	for category in categorized_blocks:
		if item_lists.has(category):
			populate_item_list(item_lists[category], categorized_blocks[category])

func populate_item_list(item_list: ItemList, items: Array):
	item_list.clear()
	for item in items:
		var idx = item_list.add_item(item.name)
		item_list.set_item_icon(idx, item.icon)
		item_list.set_item_metadata(idx, item.path)

func _on_item_selected(index: int, tab_name: String):
	if is_loading_mode:
		var item_list = item_lists[tab_name]
		var vehicle_name = item_list.get_item_text(index)
		load_selected_vehicle(vehicle_name)
	else:
		var item_list = item_lists[tab_name]
		var scene_path = item_list.get_item_metadata(index)
		if scene_path:
			if is_recycle_mode:
				exit_recycle_mode()
			if is_turret_editing_mode or is_turret_placement_mode:
				start_block_placement(scene_path)
			else:
				emit_signal("block_selected", scene_path)
				update_description(scene_path)
				if is_editing:
					start_block_placement(scene_path)
					update_blueprint_ghosts()

func update_description(scene_path: String):
	var scene = load(scene_path)
	var block = scene.instantiate()
	if block:
		description_label.clear()
		description_label.append_text("[b]%s[/b]\n\n" % block.block_name)
		description_label.append_text("TYPE: %s\n" % block.type)
		description_label.append_text("SIZE: %s\n" % str(block.size))
		if block.has_method("get_description"):
			description_label.append_text("DESCRIPTION: %s\n" % block.get_description())
		block.queue_free()

func _on_build_vehicle_pressed():
	try_save_vehicle()

func switch_to_loading_mode():
	is_loading_mode = true
	load_button.add_theme_color_override("font_color", Color.CYAN)
	
	for tab_name in item_lists:
		item_lists[tab_name].clear()
	
	load_blueprint_vehicles()

func switch_to_normal_mode():
	is_loading_mode = false
	load_button.remove_theme_color_override("font_color")
	
	load_all_blocks()
	
	for i in range(tab_container.get_tab_count()):
		if i < original_tab_names.size():
			tab_container.set_tab_title(i, original_tab_names[i])
	
	clear_blueprint_ghosts()

func load_blueprint_vehicles():
	var blueprint_dir = DirAccess.open(BLUEPRINT["BLUEPRINT"])
	if not blueprint_dir:
		print("错误: 无法打开蓝图目录 ", BLUEPRINT["BLUEPRINT"])
		return
	
	blueprint_dir.list_dir_begin()
	var file_name = blueprint_dir.get_next()
	var vehicle_names = []
	
	while file_name != "":
		if file_name.ends_with(".json"):
			var vehicle_name = file_name.get_basename()
			vehicle_names.append(vehicle_name)
		file_name = blueprint_dir.get_next()
	
	blueprint_dir.list_dir_end()
	
	vehicle_names.sort()
	
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.clear()
		
		var tab_index = tab_container.get_tab_count() - 1
		for i in range(tab_container.get_tab_count()):
			if tab_container.get_tab_control(i) == item_list:
				tab_index = i
				break
		
		if tab_name == "All":
			tab_container.set_tab_title(tab_index, "Vehicles")
		else:
			tab_container.set_tab_title(tab_index, "")
		
		for vehicle_name in vehicle_names:
			var _idx = item_list.add_item(vehicle_name)

func load_selected_vehicle(vehicle_name: String):
	switch_to_normal_mode()
	
	var blueprint_path = BLUEPRINT["BLUEPRINT"] + vehicle_name + ".json"
	var file = FileAccess.open(blueprint_path, FileAccess.READ)
	
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		
		if parse_result == OK:
			var blueprint_data_ghost = json.data
			show_blueprint_ghosts(blueprint_data_ghost)
			
		else:
			print("错误: 无法解析JSON文件 ", blueprint_path)
	else:
		print("错误: 无法打开文件 ", blueprint_path)

func show_blueprint_ghosts(blueprint: Dictionary):
	if not selected_vehicle:
		print("错误: 没有选中的车辆")
		return
	
	if blueprint.size() == 0:
		return
	
	clear_blueprint_ghosts()
	
	blueprint_data = blueprint
	is_showing_blueprint = true
	
	var current_block_positions = {}
	
	for block in selected_vehicle.total_blocks:
		if is_instance_valid(block):
			var block_grid_positions = get_block_grid_positions(block)
			for grid_pos in block_grid_positions:
				current_block_positions[grid_pos] = block
	
	var created_ghosts = 0
	var total_blueprint_blocks = 0
	
	for block_id in blueprint["blocks"]:
		total_blueprint_blocks += 1
		var block_data = blueprint["blocks"][block_id]
		var scene_path = block_data["path"]
		var base_pos = Vector2i(block_data["base_pos"][0], block_data["base_pos"][1])
		var rotation_deg = block_data["rotation"][0]
		
		var ghost_grid_positions = calculate_ghost_grid_positions(base_pos, rotation_deg, scene_path)
		
		var is_missing = false
		for grid_pos in ghost_grid_positions:
			if not current_block_positions.has(grid_pos):
				is_missing = true
				break
		
		if is_missing:
			create_ghost_block_with_data(scene_path, rotation_deg, ghost_grid_positions)
			created_ghosts += 1

func calculate_ghost_grid_positions(base_pos: Vector2i, rotation_deg: float, scene_path: String) -> Array:
	var scene = load(scene_path)
	if not scene:
		print("错误: 无法加载场景 ", scene_path)
		return []
	
	var temp_block = scene.instantiate()
	var block_size = Vector2i(1, 1)
	if temp_block is Block:
		block_size = temp_block.size
	else:
		temp_block.queue_free()
		return []
	
	temp_block.queue_free()
	
	var grid_positions = []
	
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			
			match int(rotation_deg):
				0:
					grid_pos = base_pos + Vector2i(x, y)
				90:
					grid_pos = base_pos + Vector2i(-y, x)
				-90:
					grid_pos = base_pos + Vector2i(y, -x)
				180, -180:
					grid_pos = base_pos + Vector2i(-x, -y)
				_:
					grid_pos = base_pos + Vector2i(x, y)
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func get_block_grid_positions(block: Block) -> Array:
	var grid_positions = []
	
	for grid_pos in selected_vehicle.grid:
		if selected_vehicle.grid[grid_pos] == block:
			grid_positions.append(grid_pos)
	
	return grid_positions

func get_rectangle_corners_arry(grid_data):
	if grid_data.is_empty():
		return []
	
	var x_coords = []
	var y_coords = []
	
	for coord in grid_data:
		x_coords.append(coord[0])
		y_coords.append(coord[1])
	
	x_coords.sort()
	y_coords.sort()
	
	var min_x = x_coords[0]
	var max_x = x_coords[x_coords.size() - 1]
	var min_y = y_coords[0]
	var max_y = y_coords[y_coords.size() - 1]
	
	var vc_1 = Vector2(min_x * GRID_SIZE , min_y * GRID_SIZE)
	var vc_2 = Vector2(max_x * GRID_SIZE + GRID_SIZE, max_y * GRID_SIZE + GRID_SIZE)
	
	var pos = (vc_1 + vc_2)/2
	
	return pos

func create_ghost_block_with_data(scene_path: String, rotation_deg: float, grid_positions: Array):
	var scene = load(scene_path)
	if not scene:
		print("错误: 无法加载块场景: ", scene_path)
		return
	
	var ghost = scene.instantiate()
	get_tree().current_scene.add_child(ghost)
	
	ghost.modulate = Color(0.3, 0.6, 1.0, 0.5)
	ghost.z_index = 45
	ghost.visible = true
	
	var ghost_world_position = calculate_ghost_world_position_precise(grid_positions)
	ghost.global_position = ghost_world_position[0]
	ghost.global_rotation = ghost_world_position[1] + deg_to_rad(rotation_deg)
	
	if ghost.has_method("set_base_rotation_degree"):
		ghost.base_rotation_degree = rotation_deg
	
	setup_blueprint_ghost_collision(ghost)
	
	var data = GhostData.new()
	data.grid_positions = grid_positions
	data.rotation_deg = rotation_deg
	ghost_data_map[ghost.get_instance_id()] = data
	
	blueprint_ghosts.append(ghost)

func calculate_ghost_world_position_precise(grid_positions: Array):
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	var local_position = get_rectangle_corners_arry(grid_positions)
	
	if not selected_vehicle.grid.is_empty():
		var first_grid_pos = selected_vehicle.grid.keys()[0]
		var first_block = selected_vehicle.grid[first_grid_pos]
		var first_gird = []
		for key in selected_vehicle.grid.keys():
			if selected_vehicle.grid[key] == first_block:
				if not first_gird.has(key):
					first_gird.append(key)
		if first_block is Block:
			var first_rotation = deg_to_rad(rad_to_deg(first_block.global_rotation) - first_block.base_rotation_degree)
			
			var first_position = get_rectangle_corners_arry(first_gird)
			
			if first_block:
				
				var local_offset = local_position - first_position
				
				var rotated_offset = local_offset.rotated(first_rotation)
				
				return [first_block.global_position + rotated_offset, first_rotation]
		
	return calculate_ghost_world_position_simple(grid_positions)

func calculate_ghost_world_position_simple(grid_positions: Array) -> Vector2:
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	var sum_x = 0
	var sum_y = 0
	for pos in grid_positions:
		sum_x += pos.x
		sum_y += pos.y
	
	var center_grid = Vector2(sum_x / float(grid_positions.size()), sum_y / float(grid_positions.size()))
	
	var grid_size = 16
	var local_center = Vector2(center_grid.x * grid_size, center_grid.y * grid_size)
	
	return selected_vehicle.to_global(local_center)

func setup_blueprint_ghost_collision(ghost: Node2D):
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
	
	if ghost is Block:
		ghost.do_connect = false
	
	var connection_points = ghost.find_children("*", "ConnectionPoint", true)
	for point in connection_points:
		if point.has_method("set_connection_enabled"):
			point.set_connection_enabled(false)
			
func get_ghost_data(ghost: Node2D) -> GhostData:
	return ghost_data_map.get(ghost.get_instance_id())

func update_ghosts_transform():
	if not is_showing_blueprint or blueprint_ghosts.is_empty():
		return
	
	for ghost in blueprint_ghosts:
		if is_instance_valid(ghost):
			var ghost_data = get_ghost_data(ghost)
			if ghost_data:
				var new_position = calculate_ghost_world_position_precise(ghost_data.grid_positions)
				ghost.global_position = new_position[0]
				ghost.global_rotation = new_position[1] + deg_to_rad(ghost_data.rotation_deg)

func clear_blueprint_ghosts():
	for ghost in blueprint_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	blueprint_ghosts.clear()
	ghost_data_map.clear()
	is_showing_blueprint = false

func update_blueprint_ghosts():
	if is_showing_blueprint and selected_vehicle and blueprint_data:
		show_blueprint_ghosts(blueprint_data)

func toggle_blueprint_display():
	if is_editing and selected_vehicle:
		if is_showing_blueprint:
			clear_blueprint_ghosts()
		else:
			if selected_vehicle.blueprint is Dictionary:
				show_blueprint_ghosts(selected_vehicle.blueprint)
			elif selected_vehicle.blueprint is String:
				var blueprint_path = BLUEPRINT["BLUEPRINT"] + selected_vehicle.blueprint + ".json"
				var file = FileAccess.open(blueprint_path, FileAccess.READ)
				if file:
					var json_string = file.get_as_text()
					file.close()
					var json = JSON.new()
					if json.parse(json_string) == OK:
						show_blueprint_ghosts(json.data)
					else:
						print("错误: 无法解析蓝图文件")
				else:
					print("错误: 无法打开蓝图文件")

func try_save_vehicle():
	var vehicle_name = name_input.text.strip_edges()
	
	if vehicle_name.is_empty():
		show_error_dialog("Name cannot be empty!")
		return
	
	if vehicle_name.contains("/") or vehicle_name.contains("\\"):
		show_error_dialog("The name cannot contain special characters!")
		return
	
	save_vehicle(vehicle_name)

func show_error_dialog(error_message: String):
	error_label.text = error_message
	error_label.show()
	save_dialog.title = "Save Error"
	save_dialog.popup_centered()

func _on_save_confirmed():
	save_dialog.hide()

func _on_save_canceled():
	save_dialog.hide()

func _on_name_input_changed(_new_text: String):
	error_label.hide()

func _on_recycle_button_pressed():
	if is_recycle_mode:
		exit_recycle_mode()
	else:
		enter_recycle_mode()

func enter_recycle_mode():
	is_recycle_mode = true
	Input.set_custom_mouse_cursor(preload("res://assets/icons/saw_cursor.png"))
	
	if current_ghost_block:
		current_ghost_block.visible = false
	
	if is_moving_block:
		cancel_block_move()
	
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	if is_turret_placement_mode:
		exit_turret_placement_mode()
	
	clear_tab_container_selection()
	
	update_recycle_button()
	emit_signal("recycle_mode_toggled", is_recycle_mode)

func update_recycle_button():
	if is_recycle_mode:
		recycle_button.add_theme_color_override("font_color", Color.RED)
	else:
		recycle_button.remove_theme_color_override("font_color")

func reload_blocks():
	for item_list in item_lists.values():
		item_list.clear()
	load_all_blocks()

# === 编辑器模式功能 ===
func initialize_editor():
	pass

func find_and_select_vehicle():
	var testground = get_tree().current_scene
	if testground:
		var canvas_layer = testground.find_child("CanvasLayer", false, false)
		if canvas_layer:
			var panels = canvas_layer.get_children()
			for item in range(panels.size() - 1, -1, -1):
				if panels[item] is FloatingPanel and panels[item].selected_vehicle != null and panels[item].visible == true:
					panel_instance = panels[item]
					break
	if testground and panel_instance:
		if panel_instance.selected_vehicle:
			selected_vehicle = panel_instance.selected_vehicle
			name_input.text = selected_vehicle.vehicle_name
			return

func enter_editor_mode(vehicle: Vehicle):
	if is_editing:
		exit_editor_mode()
	selected_vehicle = vehicle

	is_editing = true
	
	if not is_new_vehicle:
		is_first_block = false
	
	camera.focus_on_vehicle(selected_vehicle)
	camera.sync_rotation_to_vehicle(selected_vehicle)
	
	enable_all_connection_points_for_editing(true)
	
	vehicle.control = Callable()
	
	for block:Block in vehicle.blocks:
		block.collision_layer = 1
	
	show()
	
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	
	toggle_blueprint_display()

func exit_editor_mode():
	if not is_editing:
		return
	
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	if is_turret_placement_mode:
		exit_turret_placement_mode()
	
	if selected_vehicle.check_and_regroup_disconnected_blocks() or selected_vehicle.commands.size() == 0:
		error_label.show()
		if selected_vehicle.check_and_regroup_disconnected_blocks():
			if selected_vehicle.commands.size() == 0:
				error_label.text = "Unconnected Block & No Command"
			else:
				error_label.text = "Unconnected Block"
		else:
			error_label.text = "No Command"
		save_dialog.show()
		save_dialog.title = "Error"
		save_dialog.popup_centered()
		return
	
	for block:Block in selected_vehicle.blocks:
		block.collision_layer = 1
		block.modulate = Color.WHITE
	
	is_new_vehicle = false
	is_first_block = true
	
	if is_recycle_mode:
		exit_recycle_mode()
	
	clear_tab_container_selection()
 	
	restore_original_connections()
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	clear_blueprint_ghosts()
	
	camera.target_rot = 0.0
	
	hide()
	is_editing = false
	panel_instance = null
	selected_vehicle = null

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
	

func start_block_placement(scene_path: String):
	if not is_editing or not selected_vehicle:
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
	
	# 在炮塔放置模式下设置碰撞层
	if is_turret_placement_mode or is_turret_editing_mode:
		if current_ghost_block is CollisionObject2D:
			current_ghost_block.collision_layer = 2
			current_ghost_block.collision_mask = 2
	
	current_ghost_block.base_rotation_degree = 0
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	current_snap_config = {}
	turret_snap_config = {}

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

# === 连接点吸附系统 ===
func update_ghost_block_position(mouse_position: Vector2):
	if is_first_block and is_new_vehicle:
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = Color(0.8, 0.8, 1.0, 0.5)
		current_snap_config = {}
		return
	
	available_vehicle_points = selected_vehicle.get_available_points_near_position(mouse_position, 20.0)
	available_ghost_points = get_ghost_block_available_connection_points()
	
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.5)
		current_snap_config = {}
		return
	
	snap_config = get_current_snap_config()
	
	if snap_config:
		current_ghost_block.global_position = snap_config.ghost_position
		current_ghost_block.global_rotation = snap_config.ghost_rotation
		current_ghost_block.modulate = Color(0.5, 1, 0.5, 0.5)
		current_snap_config = snap_config
	else:
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.5)
		current_snap_config = {}

func get_ghost_block_available_connection_points() -> Array[ConnectionPoint]:
	var points: Array[ConnectionPoint] = []
	if current_ghost_block:
		var connection_points = current_ghost_block.get_available_connection_points()
		for point in connection_points:
			if point is ConnectionPoint:
				point.qeck = false
				points.append(point)
	return points

func get_current_snap_config() -> Dictionary:
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		return {}
	var best_config = find_best_snap_config()
	return best_config

func find_best_snap_config() -> Dictionary:
	var best_config = {}
	var min_distance = INF
	var best_ghost_pos = null
	var best_vehicle_pos = null
	for vehicle_point in available_vehicle_points:
		var vehicle_block = vehicle_point.find_parent_block()
		if not vehicle_block:
			continue
		var vehicle_point_global = get_connection_point_global_position(vehicle_point, vehicle_block)
		for ghost_point in available_ghost_points:
			var target_rotation = calculate_aligned_rotation_from_base(vehicle_block)
			if not can_points_connect_with_rotation(vehicle_point, ghost_point, target_rotation):
				continue
				
			var positions = calculate_rotated_grid_positions(vehicle_point, ghost_point)
			if positions is bool:
				continue
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = vehicle_point_global - ghost_local_offset
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			var distance = global_mouse_pos.distance_to(ghost_position)
			if distance < min_distance:
				best_vehicle_pos = vehicle_point
				best_ghost_pos = ghost_point
				min_distance = distance
				best_config = {
					"vehicle_point": vehicle_point,
					"ghost_point": ghost_point,
					"ghost_position": ghost_position,
					"ghost_rotation": target_rotation,
					"vehicle_block": vehicle_block,
					"positions":positions
				}
	
	return best_config

func calculate_aligned_rotation_from_base(vehicle_block: Block) -> float:
	var dir = vehicle_block.base_rotation_degree
	return deg_to_rad(current_ghost_block.base_rotation_degree) + deg_to_rad(-dir) + vehicle_block.global_rotation

func can_points_connect_with_rotation(point_a: ConnectionPoint, point_b: ConnectionPoint, ghost_rotation: float) -> bool:
	if point_a.connection_type != point_b.connection_type:
		return false
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	var ghost_point_direction = point_b.rotation + ghost_rotation
	var angle_diff = are_rotations_opposite_best(ghost_point_direction, point_a.global_rotation)
	return angle_diff

func are_rotations_opposite_best(rot1: float, rot2: float) -> bool:
	var dir1 = Vector2(cos(rot1), sin(rot1))
	var dir2 = Vector2(cos(rot2), sin(rot2))
	
	var dot_product = dir1.dot(dir2)
	return dot_product < -0.9

func get_connection_point_global_position(point: ConnectionPoint, block: Block) -> Vector2:
	if block is TurretRing and block.turret:
		return block.turret.to_global(point.position)
	else:
		return block.global_position + point.position.rotated(block.global_rotation)

func rotate_ghost_connection():
	if not current_ghost_block:
		return
	
	current_ghost_block.base_rotation_degree += 90
	current_ghost_block.base_rotation_degree = fmod(current_ghost_block.base_rotation_degree + 90, 360) - 90
	
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)

func try_place_block():
	if not current_ghost_block or not selected_vehicle:
		return
	
	if is_first_block and is_new_vehicle:
		place_first_block()
		return
	
	if not current_snap_config:
		return
	
	var connections_to_disconnect = find_connections_to_disconnect_for_placement()
	disconnect_connections(connections_to_disconnect)
	
	var grid_positions = snap_config.positions
	var new_block:Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_snap_config.ghost_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	selected_vehicle.control = control
	
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	update_blueprint_ghosts()

func place_first_block():
	var new_block:Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_ghost_block.global_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	var grid_positions = calculate_free_grid_positions(new_block)
	
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	selected_vehicle.control = control
	
	is_first_block = false
	
	start_block_placement_with_rotation(current_block_scene.resource_path)

func calculate_free_grid_positions(block: Block) -> Array:
	var grid_positions = []
	var world_pos = block.global_position
	var grid_x = int(round(world_pos.x / GRID_SIZE))
	var grid_y = int(round(world_pos.y / GRID_SIZE))
	
	var block_size = block.size
	for x in range(block_size.x):
		for y in range(block_size.y):
			var grid_pos: Vector2i
			match int(block.base_rotation_degree):
				0:
					grid_pos = Vector2i(grid_x + x, grid_y + y)
				90:
					grid_pos = Vector2i(grid_x - y, grid_y + x)
				-90:
					grid_pos = Vector2i(grid_x + y, grid_y - x)
				180, -180:
					grid_pos = Vector2i(grid_x - x, grid_y - y)
				_:
					grid_pos = Vector2i(grid_x + x, grid_y + y)
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func start_block_placement_with_rotation(scene_path: String):
	if not is_editing or not selected_vehicle:
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
	
	# 在炮塔放置模式下设置碰撞层
	if is_turret_placement_mode or is_turret_editing_mode:
		if current_ghost_block is CollisionObject2D:
			current_ghost_block.collision_layer = 2
			current_ghost_block.collision_mask = 2
	
	current_ghost_block.base_rotation_degree = base_rotation_degree
	current_ghost_block.rotation = deg_to_rad(base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	current_snap_config = {}

func establish_connection(vehicle_point: ConnectionPoint, new_block: Block, ghost_point: ConnectionPoint):
	var new_block_points = new_block.find_children("*", "ConnectionPoint")
	var target_point = null
	
	for point in new_block_points:
		if point is ConnectionPoint and point.name == ghost_point.name:
			target_point = point
			break
	
	if target_point is ConnectionPoint:
		target_point.is_connection_enabled = true
		vehicle_point.try_connect(target_point)

func calculate_rotated_grid_positions(vehiclepoint, ghostpoint):
	var grid_positions = []
	var grid_block = {}
	
	if not selected_vehicle:
		return grid_positions
	
	var block_size = current_ghost_block.size

	var location_v = vehiclepoint.location
	
	var rotation_b = vehiclepoint.find_parent_block().base_rotation_degree
	var grid_b = {}
	var grid_b_pos = {}
	
	for key in selected_vehicle.grid:
		if selected_vehicle.grid[key] == vehiclepoint.find_parent_block():
			grid_b[key] = selected_vehicle.grid[key]
	
	grid_b_pos = get_rectangle_corners(grid_b)
	var grid_connect_g
	if grid_b_pos.is_empty():
		return false
	var connect_pos_v
	if rotation_b == 0:
		connect_pos_v = Vector2i(grid_b_pos["1"].x + location_v.x, grid_b_pos["1"].y + location_v.y)
	elif rotation_b == -90:
		connect_pos_v = Vector2i(grid_b_pos["4"].x + location_v.y, grid_b_pos["4"].y - location_v.x)
	elif rotation_b == -180 or rotation_b == 180:
		connect_pos_v = Vector2i(grid_b_pos["3"].x - location_v.x, grid_b_pos["3"].y - location_v.y)
	elif rotation_b == 90:
		connect_pos_v = Vector2i(grid_b_pos["2"].x - location_v.y, grid_b_pos["2"].y + location_v.x)
	grid_connect_g = get_connection_offset(connect_pos_v, vehiclepoint.rotation, vehiclepoint.find_parent_block().base_rotation_degree)
	
	if grid_connect_g != null and block_size != null and ghostpoint.location != null:
		grid_block = to_grid(grid_connect_g, block_size, ghostpoint.location)
	
	for pos in grid_block:
		if selected_vehicle.grid.has(pos):
			return false
		grid_positions.append(pos)
	
	
	return grid_positions

func get_connection_offset(connect_pos_v: Vector2i, _rotation: float, direction: int) -> Vector2i:
	var rounded_rotation_or = round(rad_to_deg(_rotation))
	var rounded_rotation = direction + rounded_rotation_or
	rounded_rotation = wrapf(rounded_rotation, -180, 180)
	
	if rounded_rotation == 0:
		return Vector2i(connect_pos_v.x + 1, connect_pos_v.y)
	elif rounded_rotation == -90:
		return Vector2i(connect_pos_v.x, connect_pos_v.y - 1)
	elif rounded_rotation == -180 or rounded_rotation == 180:
		return Vector2i(connect_pos_v.x - 1, connect_pos_v.y)
	elif rounded_rotation == 90:
		return Vector2i(connect_pos_v.x, connect_pos_v.y + 1)
	
	return connect_pos_v

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
	
	var min_x = x_coords[0]
	var max_x = x_coords[x_coords.size() - 1]
	var min_y = y_coords[0]
	var max_y = y_coords[y_coords.size() - 1]
	
	var corners = {
		"1": Vector2i(min_x, min_y),
		"2": Vector2i(max_x, min_y),
		"3": Vector2i(max_x, max_y),
		"4": Vector2i(min_x, max_y)
	}
	
	return corners

func to_grid(grid_connect_g: Vector2i, block_size: Vector2i, connect_pos_g: Vector2i) -> Dictionary:
	var grid_block = {}
	for i in block_size.x:
		for j in block_size.y:
			if current_ghost_block.base_rotation_degree == 0:
				var left_up = Vector2i(grid_connect_g.x - connect_pos_g.x, grid_connect_g.y - connect_pos_g.y)
				grid_block[Vector2i(left_up.x + i, left_up.y + j)] = current_ghost_block
			elif current_ghost_block.base_rotation_degree == -90:
				var left_up = Vector2i(grid_connect_g.x - connect_pos_g.y, grid_connect_g.y + connect_pos_g.x)
				grid_block[Vector2i(left_up.x + j, left_up.y - i)] = current_ghost_block
			elif current_ghost_block.base_rotation_degree == -180 or current_ghost_block.base_rotation_degree == 180:
				var left_up = Vector2i(grid_connect_g.x + connect_pos_g.x, grid_connect_g.y + connect_pos_g.y)
				grid_block[Vector2i(left_up.x - i, left_up.y - j)] = current_ghost_block
			elif current_ghost_block.base_rotation_degree == 90:
				var left_up = Vector2i(grid_connect_g.x + connect_pos_g.y, grid_connect_g.y - connect_pos_g.x)
				grid_block[Vector2i(left_up.x - j, left_up.y + i)] = current_ghost_block
	return grid_block
	

func find_connections_to_disconnect_for_placement() -> Array:
	var connections_to_disconnect = []
	if current_snap_config.vehicle_point and current_snap_config.vehicle_point.connected_to:
		connections_to_disconnect.append({
			"from": current_snap_config.vehicle_point,
			"to": current_snap_config.vehicle_point.connected_to
		})
	return connections_to_disconnect

func disconnect_connections(connections: Array):
	for connection in connections:
		if is_instance_valid(connection.from):
			connection.from.disconnect_joint()
		if is_instance_valid(connection.to):
			connection.to.disconnect_joint()

func get_affected_blocks() -> Array:
	var affected_blocks = []
	if current_snap_config.vehicle_point:
		var parent_block = current_snap_config.vehicle_point.find_parent_block()
		if parent_block:
			affected_blocks.append(parent_block)
	return affected_blocks

func enable_connection_points_for_blocks(blocks: Array):
	for block in blocks:
		if is_instance_valid(block):
			for point in block.connection_points:
				if is_instance_valid(point):
					point.set_connection_enabled(true)

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
			var block_name = block.block_name
			var connections_to_disconnect = find_connections_for_block(block)
			disconnect_connections(connections_to_disconnect)
			var control = selected_vehicle.control
			selected_vehicle.remove_block(block, true)
			selected_vehicle.control = control
			enable_connection_points_for_blocks(get_affected_blocks_for_removal(block))
			call_deferred("check_vehicle_stability")
			
			update_blueprint_ghosts()
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
	current_snap_config = {}
	clear_tab_container_selection()

func get_block_size(block: Block) -> Vector2i:
	if block.has_method("get_size"):
		return block.size
	return Vector2i(1, 1)

func check_connections_from_block(block: Block, checked_blocks: Dictionary):
	if checked_blocks.get(block, false):
		return
	
	checked_blocks[block] = true
	
	for point in block.connection_points:
		if point.connected_to:
			var connected_block = point.connected_to.find_parent_block()
			if connected_block and not checked_blocks.get(connected_block, false):
				check_connections_from_block(connected_block, checked_blocks)

func _on_vehicle_saved(vehicle_name: String):
	save_vehicle(vehicle_name)

func save_vehicle(vehicle_name: String):
	if not selected_vehicle:
		print("Error: No vehicle selected")
		return
	
	var blueprint_data_save = create_blueprint_data(vehicle_name)
	var blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	
	if save_blueprint(blueprint_data_save, blueprint_path):
		selected_vehicle.vehicle_name = vehicle_name
		selected_vehicle.blueprint = blueprint_data_save
	else:
		show_error_dialog("Failed to save the vehicle")

func create_blueprint_data(vehicle_name: String) -> Dictionary:
	var blueprint_data_save = {
		"name": vehicle_name,
		"blocks": {},
		"vehicle_size": [0, 0],
		"rotation": [0]
	}
	
	var block_counter = 1
	var processed_blocks = {}
	
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	for grid_pos in selected_vehicle.grid:
		min_x = min(min_x, grid_pos.x)
		min_y = min(min_y, grid_pos.y)
		max_x = max(max_x, grid_pos.x)
		max_y = max(max_y, grid_pos.y)
	
	for grid_pos in selected_vehicle.grid:
		var block = selected_vehicle.grid[grid_pos]
		if not processed_blocks.has(block):
			var relative_pos = Vector2i(grid_pos.x - min_x, grid_pos.y - min_y)
			var rotation_str = block.base_rotation_degree
			
			blueprint_data_save["blocks"][str(block_counter)] = {
				"name": block.block_name,
				"path": block.scene_file_path,
				"base_pos": [relative_pos.x, relative_pos.y],
				"rotation": [rotation_str],
			}
			block_counter += 1
			processed_blocks[block] = true
	
	blueprint_data_save["vehicle_size"] = [max_x - min_x + 1, max_y - min_y + 1]
	return blueprint_data_save

func save_blueprint(blueprint_data_save: Dictionary, save_path: String) -> bool:
	var dir = DirAccess.open("res://vehicles/blueprint/")
	if not dir:
		DirAccess.make_dir_absolute("res://vehicles/blueprint/")
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(blueprint_data_save, "\t"))
		file.close()
		return true
	else:
		push_error("Failed to save file:", FileAccess.get_open_error())
		return false

func update_recycle_highlight():
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	reset_all_blocks_color()
	
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = global_mouse_pos
	query.collision_mask = 1
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:
			block.modulate = Color.RED
			break

func reset_all_blocks_color():
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			block.modulate = Color.WHITE

func exit_recycle_mode():
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
		update_recycle_button()
		
		if selected_vehicle:
			reset_all_blocks_color()
		
		emit_signal("recycle_mode_toggled", false)

func create_new_vehicle():
	if is_editing:
		exit_editor_mode()
		if is_editing:
			return
	
	var new_vehicle = Vehicle.new()
	new_vehicle.vehicle_name = "NewVehicle_" + str(Time.get_unix_time_from_system())
	new_vehicle.blueprint = {}
	
	if camera:
		new_vehicle.global_position = camera.global_position
	else:
		new_vehicle.global_position = Vector2(500, 300)
	
	var current_scene = get_tree().current_scene
	current_scene.add_child(new_vehicle)
	
	enter_editor_mode_with_new_vehicle(new_vehicle)

func enter_editor_mode_with_new_vehicle(vehicle: Vehicle):
	selected_vehicle = vehicle
	
	is_new_vehicle = true
	is_first_block = true
	
	name_input.text = ""
	
	enter_editor_mode(vehicle)

func clear_tab_container_selection():
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.deselect_all()
		item_list.release_focus()

func _on_repair_button_pressed():
	if not is_editing or not selected_vehicle or not is_showing_blueprint:
		return
	
	repair_blueprint_missing_blocks()

func repair_blueprint_missing_blocks():
	for pos in selected_vehicle.grid.keys():
		var block = selected_vehicle.grid[pos]
		if block is Block:
			if block.current_hp < block.max_hp:
				block.current_hp = block.max_hp
	if not blueprint_data or blueprint_ghosts.is_empty():
		return
	
	var repaired_count = 0
	var failed_count = 0
	
	var occupied_grid_positions = {}
	for grid_pos in selected_vehicle.grid:
		occupied_grid_positions[grid_pos] = true
	
	for ghost in blueprint_ghosts:
		if not is_instance_valid(ghost):
			continue
		
		var ghost_data = get_ghost_data(ghost)
		if not ghost_data:
			continue
		
		var can_place = true
		for grid_pos in ghost_data.grid_positions:
			if occupied_grid_positions.has(grid_pos):
				can_place = false
				break
		
		if can_place:
			if try_place_ghost_block(ghost, ghost_data):
				repaired_count += 1
				for grid_pos in ghost_data.grid_positions:
					occupied_grid_positions[grid_pos] = true
			else:
				failed_count += 1
	
	if repaired_count > 0:
		update_blueprint_ghosts()

func try_place_ghost_block(ghost: Node2D, ghost_data: GhostData) -> bool:
	var scene_path = ghost.scene_file_path
	if not scene_path or scene_path.is_empty():
		return false
	
	var scene = load(scene_path)
	if not scene:
		return false
	
	var new_block: Block = scene.instantiate()
	selected_vehicle.add_child(new_block)
	
	new_block.global_position = ghost.global_position
	new_block.global_rotation = ghost.global_rotation
	new_block.base_rotation_degree = ghost_data.rotation_deg
	
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, ghost_data.grid_positions)
	selected_vehicle.control = control
	
	return true

# === 长按拖拽功能 ===

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

func start_drag_block():
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	var block = get_block_at_position(global_mouse_pos)
	
	if block:
		is_dragging = true
		start_block_move(block)

func update_moving_ghost_position(mouse_position: Vector2):
	if not moving_block_ghost:
		return
	
	available_vehicle_points = selected_vehicle.get_available_points_near_position(mouse_position, 50.0)
	available_ghost_points = get_moving_ghost_available_connection_points()
	
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		moving_block_ghost.global_position = mouse_position
		moving_block_ghost.rotation = deg_to_rad(moving_block_ghost.base_rotation_degree) + camera.target_rot
		moving_block_ghost.modulate = Color(1, 1, 0.3, 0.7)
		moving_snap_config = {}
		return
	
	var snap_config = get_current_snap_config_for_moving()
	
	if snap_config:
		moving_block_ghost.global_position = snap_config.ghost_position
		moving_block_ghost.global_rotation = snap_config.ghost_rotation
		moving_block_ghost.modulate = Color(0.5, 1, 0.5, 0.7)
		moving_snap_config = snap_config
	else:
		moving_block_ghost.global_position = mouse_position
		moving_block_ghost.rotation = deg_to_rad(moving_block_ghost.base_rotation_degree) + camera.target_rot
		moving_block_ghost.modulate = Color(1, 1, 0.3, 0.7)
		moving_snap_config = {}

func get_current_snap_config_for_moving() -> Dictionary:
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		return {}
	
	var original_ghost = current_ghost_block
	current_ghost_block = moving_block_ghost
	
	var best_config = find_best_snap_config()
	
	current_ghost_block = original_ghost
	
	return best_config

func get_moving_ghost_available_connection_points() -> Array[ConnectionPoint]:
	var points: Array[ConnectionPoint] = []
	if moving_block_ghost:
		var connection_points = moving_block_ghost.get_available_connection_points()
		for point in connection_points:
			if point is ConnectionPoint:
				point.qeck = false
				points.append(point)
	return points

func start_block_move(block: Block):
	if is_moving_block:
		cancel_block_move()
	
	moving_block = block
	moving_block_original_position = block.global_position
	moving_block_original_rotation = block.global_rotation
	moving_block_original_grid_positions = get_block_grid_positions(block)
	
	create_moving_ghost(block)
	
	var control = selected_vehicle.control
	selected_vehicle.remove_block(block, false)
	selected_vehicle.control = control
	
	is_moving_block = true
	
	moving_snap_config = {}
	
	block.visible = false
	
	if current_ghost_block:
		current_ghost_block.visible = false

func create_moving_ghost(block: Block):
	var scene_path = block.scene_file_path
	if not scene_path or scene_path.is_empty():
		return
	
	var scene = load(scene_path)
	if not scene:
		return
	
	moving_block_ghost = scene.instantiate()
	get_tree().current_scene.add_child(moving_block_ghost)
	
	moving_block_ghost.modulate = Color(1, 1, 0.5, 0.7)
	moving_block_ghost.z_index = 100
	moving_block_ghost.global_position = moving_block_original_position
	moving_block_ghost.global_rotation = moving_block_original_rotation
	moving_block_ghost.base_rotation_degree = moving_block.base_rotation_degree
	
	setup_moving_ghost_collision(moving_block_ghost)

func setup_moving_ghost_collision(ghost: Node2D):
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
	
	ghost.do_connect = false

func place_moving_block():
	if not is_moving_block or not moving_block or not moving_block_ghost:
		return
	
	if moving_snap_config and not moving_snap_config.is_empty():
		var connections_to_disconnect = find_connections_to_disconnect_for_moving()
		disconnect_connections(connections_to_disconnect)
		
		var grid_positions = moving_snap_config.positions
		
		if not are_grid_positions_available(grid_positions):
			cancel_block_move()
			return
		
		moving_block.global_position = moving_snap_config.ghost_position
		moving_block.global_rotation = moving_snap_config.ghost_rotation
		
		var world_rotation_deg = rad_to_deg(moving_snap_config.ghost_rotation)
		var camera_rotation_deg = rad_to_deg(camera.target_rot)
		moving_block.base_rotation_degree = wrapf(world_rotation_deg - camera_rotation_deg, -180, 180)
		
		var control = selected_vehicle.control
		selected_vehicle._add_block(moving_block, moving_block.position, grid_positions)
		selected_vehicle.control = control
		
	else:
		cancel_block_move()
		return
	
	finish_block_move()
	
	update_blueprint_ghosts()

func are_grid_positions_available(grid_positions: Array) -> bool:
	for pos in grid_positions:
		if selected_vehicle.grid.has(pos):
			return false
	return true

func find_connections_to_disconnect_for_moving() -> Array:
	var connections_to_disconnect = []
	
	if moving_snap_config and moving_snap_config.has("vehicle_point"):
		var vehicle_point = moving_snap_config.vehicle_point
		if vehicle_point and vehicle_point.connected_to:
			connections_to_disconnect.append({
				"from": vehicle_point,
				"to": vehicle_point.connected_to
			})
	
	return connections_to_disconnect

func cancel_block_move():
	if not is_moving_block or not moving_block:
		return
	
	moving_block.global_position = moving_block_original_position
	moving_block.global_rotation = moving_block_original_rotation
	moving_block.base_rotation_degree = rad_to_deg(moving_block_original_rotation - camera.target_rot)
	
	var control = selected_vehicle.control
	selected_vehicle._add_block(moving_block, moving_block.position, moving_block_original_grid_positions)
	selected_vehicle.control = control
	
	finish_block_move()

func finish_block_move():
	if moving_block:
		moving_block.visible = true
		moving_block = null
	
	if moving_block_ghost:
		moving_block_ghost.queue_free()
		moving_block_ghost = null
	
	is_moving_block = false
	is_dragging = false
	moving_snap_config = {}
	
	if current_ghost_block:
		current_ghost_block.visible = true

func rotate_moving_ghost():
	"""旋转移动中的虚影"""
	if not moving_block_ghost:
		return
	
	# 旋转基础旋转90度
	moving_block_ghost.base_rotation_degree += 90
	moving_block_ghost.base_rotation_degree = fmod(moving_block_ghost.base_rotation_degree + 90, 360) - 90
	
	# 更新虚影显示
	moving_block_ghost.rotation = deg_to_rad(moving_block_ghost.base_rotation_degree)
	
	# 如果有吸附配置，重新计算位置
	if moving_snap_config and not moving_snap_config.is_empty():
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_moving_ghost_position(global_mouse_pos)
	else:
		# 自由移动时只更新旋转
		moving_block_ghost.rotation = deg_to_rad(moving_block_ghost.base_rotation_degree) + camera.target_rot
