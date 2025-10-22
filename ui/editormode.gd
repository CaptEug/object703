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
var is_loading_mode := false  # 新增：标记是否处于加载模式
var original_tab_names := []  # 新增：存储原始标签页名称

# === 炮塔编辑模式变量 ===
var is_turret_editing_mode := false  # 是否处于炮塔编辑模式
var current_editing_turret: TurretRing = null  # 当前正在编辑的炮塔
var turret_cursor:Texture = preload("res://assets/icons/file.png")  # 炮塔模式光标
var turret_grid_previews := []  # 存储炮塔网格预览

# === 炮塔连接点吸附系统 ===
var available_turret_connectors: Array[RigidBodyConnector] = []  # 修改：使用RigidBodyConnector类型
var available_block_connectors: Array[RigidBodyConnector] = []   # 修改：使用RigidBodyConnector类型
var turret_snap_config: Dictionary = {}

# === 蓝图显示功能 ===
var blueprint_ghosts := []  # 存储虚影块的数组
var blueprint_data: Dictionary  # 当前蓝图数据
var is_showing_blueprint := false  # 是否正在显示蓝图
var ghost_data_map = {}  # ghost instance_id -> GhostData

# === 编辑器模式变量 ===
var is_editing := false
var selected_vehicle: Vehicle = null
var current_ghost_block: Node2D = null
var current_block_scene: PackedScene = null
var panel_instance: Control = null
var camera:Camera2D

# === 方块移动功能变量 ===
var is_moving_block := false  # 是否正在移动方块
var moving_block: Block = null  # 正在移动的方块
var moving_block_original_position: Vector2  # 方块的原始位置
var moving_block_original_rotation: float  # 方块的原始旋转
var moving_block_original_grid_positions: Array  # 方块的原始网格位置
var moving_block_ghost: Node2D = null  # 移动时的虚影
var moving_snap_config: Dictionary = {}  # 移动吸附配置
var is_mouse_pressed := false  # 鼠标按下状态
var drag_timer: float = 0.0  # 拖拽计时器
var is_dragging := false  # 是否正在拖拽
var DRAG_DELAY: float = 0.2  # 长按触发拖拽的延迟时间（秒）

# 连接点吸附系统
var current_ghost_connection_index := 0
var current_vehicle_connection_index = 0
var available_ghost_points: Array[ConnectionPoint] = []
var available_vehicle_points: Array[ConnectionPoint] = []
var current_snap_config: Dictionary = {}
var snap_config
var is_first_block := true  # 标记是否是第一个放置的块
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
	#load_button.pressed.connect(_on_load_button_pressed)
	repair_buttom.pressed.connect(_on_repair_button_pressed)
	create_tabs()
	
	save_dialog.hide()
	error_label.hide()
	
	var connect_result = vehicle_saved.connect(_on_vehicle_saved)
	if connect_result == OK:
		print("✅ vehicle_saved Signal connected successfully")
	else:
		print("❌ vehicle_saved 信号连接失败，错误代码:", connect_result)
		# 检查连接状态
		if vehicle_saved.is_connected(_on_vehicle_saved):
			print("⚠️  信号已经连接")
		else:
			print("⚠️  信号未连接")
	
	update_recycle_button()
	load_all_blocks()
	
	call_deferred("initialize_editor")

func _connect_block_buttons():
	# 找到所有方块选择按钮并连接信号
	var block_buttons = get_tree().get_nodes_in_group("block_buttons")
	for button in block_buttons:
		if button is BaseButton:
			button.pressed.connect(_on_block_button_pressed)

func _on_block_button_pressed():
	# 设置UI交互状态，防止意外建造
	is_ui_interaction = true
	# 0.2秒后自动重置状态（确保覆盖整个点击过程）
	await get_tree().create_timer(0.2).timeout
	is_ui_interaction = false

func _input(event):
	if get_viewport().gui_get_hovered_control():
		return
	
	# 全局TAB键检测
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
	
	# 在编辑模式下点击炮塔进入炮塔编辑模式
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_editing and not is_turret_editing_mode and not is_recycle_mode and not is_moving_block:
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			var clicked_turret = get_turret_at_position(global_mouse_pos)
			
			if clicked_turret:
				enter_turret_editing_mode(clicked_turret)
				return
	
	# 在炮塔编辑模式下点击空白处退出
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_turret_editing_mode:
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			
			print("🖱️ 炮塔编辑模式点击检测")
			print("   鼠标位置: ", global_mouse_pos)
			print("   当前吸附配置: ", turret_snap_config)
			
			# 检查是否点击在可放置位置
			var can_place = false
			if current_editing_turret and current_ghost_block:
				# 使用连接点吸附检查
				can_place = turret_snap_config and not turret_snap_config.is_empty()
			
			print("   是否可以放置: ", can_place)
			
			# 如果点击在不可放置位置，退出炮塔编辑模式
			if not can_place:
				print("❌ 点击在不可放置位置，退出炮塔编辑模式")
				exit_turret_editing_mode()
				return
			else:
				# 如果可以放置，执行放置操作
				print("✅ 点击在可放置位置，尝试放置块")
				try_place_turret_block()
				return
	
	# ESC键退出炮塔编辑模式
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_turret_editing_mode:
			exit_turret_editing_mode()
			return
	
	if not is_editing:
		return
	
	# 鼠标按下事件
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if is_turret_editing_mode:
				exit_turret_editing_mode()
			elif is_moving_block:
				cancel_block_move()
			else:
				cancel_placement()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 鼠标按下
				is_mouse_pressed = true
				drag_timer = 0.0
				is_dragging = false
				
				# 如果已经在移动模式，立即放置
				if is_recycle_mode:
					try_remove_block()
				elif is_turret_editing_mode:
					# 炮塔模式在点击检查中处理
					pass
				
				if is_moving_block:
					place_moving_block()
					return
					
				# 检查是否点击了现有方块（准备开始拖拽）
				if not is_recycle_mode and not current_ghost_block and not is_turret_editing_mode:
					var mouse_pos = get_viewport().get_mouse_position()
					var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
					var block = get_block_at_position(global_mouse_pos)
					if block:
						print("检测到方块，开始拖拽计时")
			else:
				# 鼠标释放
				is_mouse_pressed = false
				
				# 如果正在拖拽，放置方块
				if is_dragging and is_moving_block:
					place_moving_block()
				# 如果不是拖拽且不在移动模式，正常放置方块
				elif not is_dragging and not is_moving_block and not is_recycle_mode and not is_turret_editing_mode:
					try_place_block()
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				if is_turret_editing_mode:
					exit_turret_editing_mode()
				elif is_moving_block:
					cancel_block_move()
				else:
					cancel_placement()
			KEY_R:
				if is_moving_block and moving_block_ghost:
					rotate_moving_ghost()
				elif current_ghost_block and not is_turret_editing_mode:
					rotate_ghost_connection()
			KEY_F:
				print_connection_points_info()
			KEY_X:
				if is_recycle_mode:
					exit_recycle_mode()
				else:
					enter_recycle_mode()
			KEY_L:
				debug_block_layers()

func _process(delta):
	if is_editing and selected_vehicle:
		camera.sync_rotation_to_vehicle(selected_vehicle)
	
	# 更新炮塔模式状态显示
	update_turret_mode_status()
	
	if is_showing_blueprint and not blueprint_ghosts.is_empty():
		update_ghosts_transform()	
	
	if is_editing and is_recycle_mode and selected_vehicle:
		update_recycle_highlight()
		
	if not is_editing or not selected_vehicle:
		return
	
	# 处理长按拖拽
	if is_mouse_pressed and not is_dragging and not is_moving_block and not is_recycle_mode and not current_ghost_block and not is_turret_editing_mode:
		drag_timer += delta
		if drag_timer >= DRAG_DELAY:
			# 长按时间到达，开始拖拽
			start_drag_block()
	
	# 更新移动中的虚影位置
	if is_moving_block and moving_block_ghost:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_moving_ghost_position(global_mouse_pos)
	elif current_ghost_block and Engine.get_frames_drawn() % 2 == 0:
		var mouse_pos = get_viewport().get_mouse_position()
		var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
		update_ghost_block_position(global_mouse_pos)
	
	# 更新炮塔放置的视觉反馈
	if is_turret_editing_mode and current_ghost_block:
		update_turret_placement_feedback()

# === 炮塔编辑模式功能 ===
func enter_turret_editing_mode(turret: TurretRing):
	"""进入指定炮塔的编辑模式"""
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	print("进入炮塔编辑模式: ", turret.block_name)
	is_turret_editing_mode = true
	current_editing_turret = turret
	
	# 调试信息
	debug_turret_connectors()
	
	# 炮塔回正并禁用旋转
	reset_turret_rotation(turret)
	disable_turret_rotation(turret)
	
	# 非炮塔块变灰
	dim_non_turret_blocks(true)
	
	# 取消当前块放置
	if current_ghost_block:
		current_ghost_block.visible = false
	
	# 如果正在移动方块，取消移动
	if is_moving_block:
		cancel_block_move()
	
	# 退出删除模式
	if is_recycle_mode:
		exit_recycle_mode()
	
	# 清除 TabContainer 的选择
	clear_tab_container_selection()
	
	# 高亮显示当前编辑的炮塔
	highlight_current_editing_turret(turret)
	
	# 显示炮塔网格预览
	show_turret_grid_preview()
	
	print("炮塔编辑模式：可以在炮塔 ", turret.block_name, " 上放置块")

func debug_turret_connection_points(turret: TurretRing):
	"""调试炮塔连接点信息"""
	print("=== 炮塔连接点调试 ===")
	print("炮塔: ", turret.block_name)
	if turret.turret:
		print("炮塔全局旋转: ", rad_to_deg(turret.turret.global_rotation))
	else:
		print("警告: 炮塔没有turret子节点")
	
	var points = []
	if turret is TurretRing:
		points = turret.get_available_connection_points()
	
	print("连接点数量: ", points.size())
	for i in range(points.size()):
		var point = points[i]
		var global_pos = get_connection_point_global_position(point, turret)
		print("连接点 ", i, ": ", point.name, " 位置=", point.position, " 全局位置=", global_pos, " 旋转=", rad_to_deg(point.global_rotation))
	print("==================")

func debug_ghost_connection_points():
	"""调试幽灵块连接点信息"""
	if not current_ghost_block:
		return
		
	print("=== 幽灵块连接点调试 ===")
	print("幽灵块: ", current_ghost_block.block_name)
	
	var points = get_ghost_block_available_connection_points()
	for i in range(points.size()):
		var point = points[i]
		var global_pos = current_ghost_block.to_global(point.position)
		print("连接点 ", i, ": ", point.name, " 位置=", point.position, " 全局位置=", global_pos, " 旋转=", rad_to_deg(point.global_rotation))
	print("==================")

func exit_turret_editing_mode():
	"""退出炮塔编辑模式"""
	if not is_turret_editing_mode:
		return
	
	print("退出炮塔编辑模式")
	is_turret_editing_mode = false
	
	# 恢复炮塔旋转
	if current_editing_turret:
		enable_turret_rotation(current_editing_turret)
	
	# 恢复默认光标
	Input.set_custom_mouse_cursor(null)
	
	# 恢复非炮塔块颜色
	dim_non_turret_blocks(false)
	
	# 取消炮塔高亮
	if current_editing_turret:
		highlight_current_editing_turret(current_editing_turret, false)
	
	# 隐藏炮塔网格预览
	hide_turret_grid_preview()
	
	# 重置吸附配置
	turret_snap_config = {}
	available_turret_connectors.clear()  # 修改：清除正确的数组
	available_block_connectors.clear()   # 修改：清除正确的数组
	
	# 如果有幽灵块，恢复显示
	if current_ghost_block:
		current_ghost_block.visible = true
	
	current_editing_turret = null
	
	print("返回正常编辑模式")

func reset_turret_rotation(turret: TurretRing):
	"""炮塔回正"""
	if turret and is_instance_valid(turret):
		turret.reset_turret_rotation()
		print("炮塔回正: ", turret.block_name)

func disable_turret_rotation(turret: TurretRing):
	"""禁用炮塔旋转"""
	if turret and is_instance_valid(turret):
		turret.lock_turret_rotation()
		print("禁用炮塔旋转: ", turret.block_name)

func enable_turret_rotation(turret: TurretRing):
	"""启用炮塔旋转"""
	if turret and is_instance_valid(turret):
		turret.unlock_turret_rotation()
		print("启用炮塔旋转: ", turret.block_name)

func dim_non_turret_blocks(dim: bool):
	"""非炮塔块变灰或恢复"""
	if not selected_vehicle:
		return
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			# 如果是炮塔块，保持原样
			if block is TurretRing:
				continue
			
			# 非炮塔块变灰或恢复
			if dim:
				block.modulate = Color(0.5, 0.5, 0.5, 0.6)  # 变灰半透明
			else:
				block.modulate = Color.WHITE  # 恢复原色

func highlight_current_editing_turret(turret: TurretRing, highlight: bool = true):
	"""高亮或取消高亮当前编辑的炮塔"""
	if not turret or not is_instance_valid(turret):
		return
	
	if highlight:
		turret.modulate = Color(1, 0.8, 0.3, 1.0)  # 橙色高亮
	else:
		turret.modulate = Color.WHITE  # 恢复原色

# === 炮塔连接点吸附系统 ===
func update_turret_placement_feedback():
	"""更新炮塔放置的视觉反馈 - 使用RigidBodyConnector吸附"""
	if not is_turret_editing_mode or not current_ghost_block or not current_editing_turret:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	# 获取可用的连接器（修改：使用RigidBodyConnector）
	available_turret_connectors = get_turret_available_rigidbody_connectors()
	available_block_connectors = get_ghost_block_available_rigidbody_connectors()
	
	# 调试信息
	print("可用炮塔连接器: ", available_turret_connectors.size())
	print("可用幽灵块连接器: ", available_block_connectors.size())
	
	if available_turret_connectors.is_empty() or available_block_connectors.is_empty():
		# 没有可用连接点，自由移动
		current_ghost_block.global_position = global_mouse_pos
		current_ghost_block.rotation = 0
		current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.7)  # 红色表示无法连接
		turret_snap_config = {}
		return
	
	# 获取当前连接配置
	var snap_config = get_current_turret_snap_config(global_mouse_pos)
	
	if snap_config and not snap_config.is_empty():
		# 应用吸附位置
		current_ghost_block.global_position = snap_config.ghost_position
		current_ghost_block.global_rotation = snap_config.ghost_rotation
		current_ghost_block.modulate = Color(0.5, 1, 0.5, 0.7)  # 绿色表示可以连接
		turret_snap_config = snap_config
		
		# 调试信息
		print("吸附成功: 位置=", snap_config.ghost_position, " 旋转=", rad_to_deg(snap_config.ghost_rotation))
	else:
		# 自由移动
		current_ghost_block.global_position = global_mouse_pos
		current_ghost_block.rotation = 0
		current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.7)
		turret_snap_config = {}
		print("无吸附配置")

func get_turret_available_rigidbody_connectors() -> Array[RigidBodyConnector]:
	"""获取炮塔上可用的RigidBodyConnector"""
	var connectors: Array[RigidBodyConnector] = []
	
	if not current_editing_turret or not is_instance_valid(current_editing_turret):
		return connectors
	
	# 获取炮塔上的所有RigidBodyConnector
	var all_connectors = current_editing_turret.find_children("*", "RigidBodyConnector", true)
	for connector in all_connectors:
		if connector is RigidBodyConnector and connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	return connectors

func get_ghost_block_available_rigidbody_connectors() -> Array[RigidBodyConnector]:
	"""获取幽灵块上可用的RigidBodyConnector"""
	var connectors: Array[RigidBodyConnector] = []
	
	if not current_ghost_block:
		return connectors
	
	# 获取幽灵块上的所有RigidBodyConnector
	var all_connectors = current_ghost_block.find_children("*", "RigidBodyConnector", true)
	for connector in all_connectors:
		if connector is RigidBodyConnector and connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	return connectors

func get_current_turret_snap_config(mouse_position: Vector2) -> Dictionary:
	"""为炮塔获取吸附配置 - 使用RigidBodyConnector吸附"""
	if available_turret_connectors.is_empty() or available_block_connectors.is_empty():
		return {}
	
	var best_config = {}
	var min_distance = INF
	
	for turret_connector in available_turret_connectors:
		for block_connector in available_block_connectors:
			# 检查连接器是否可以连接
			if not can_connectors_connect(turret_connector, block_connector):
				continue
			
			# 计算距离
			var distance = mouse_position.distance_to(turret_connector.global_position)
			
			# 如果距离在吸附范围内，创建吸附配置
			if distance < turret_connector.snap_distance_threshold:
				# 计算幽灵块的位置：炮塔连接器位置 - 块连接器局部位置
				var block_connector_local = block_connector.position
				var ghost_position = turret_connector.global_position - block_connector_local.rotated(current_ghost_block.global_rotation)
				
				if distance < min_distance:
					min_distance = distance
					best_config = {
						"turret_connector": turret_connector,
						"block_connector": block_connector,
						"ghost_position": ghost_position,
						"ghost_rotation": current_ghost_block.global_rotation,  # 保持当前旋转
						"turret_block": current_editing_turret
					}
	
	return best_config

func can_points_connect_for_turret(point_a: ConnectionPoint, point_b: ConnectionPoint) -> bool:
	"""检查炮塔连接点是否可以连接"""
	# 检查连接点类型是否匹配
	if point_a.connection_type != point_b.connection_type:
		return false
	
	# 检查连接点是否启用
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	
	# 检查连接点方向是否相对
	var angle_diff = abs(fmod(point_a.global_rotation - point_b.global_rotation + PI, PI * 2) - PI)
	return angle_diff < 0.1  # 允许小的误差

func calculate_turret_aligned_rotation(turret_point: ConnectionPoint, block_point: ConnectionPoint) -> float:
	"""计算炮塔对齐的旋转角度"""
	# 计算使两个连接点方向相反的旋转
	var target_rotation = turret_point.global_rotation
	
	# 对齐到最近的90度倍数，并确保在-180到180范围内
	var degrees = rad_to_deg(target_rotation)
	var aligned_degrees = round(degrees / 90) * 90
	aligned_degrees = wrapf(aligned_degrees, -180, 180)
	
	print("旋转计算: 基础=", degrees, " 对齐=", aligned_degrees)
	return deg_to_rad(aligned_degrees)

func try_place_turret_block():
	"""在炮塔编辑模式下放置块 - 使用RigidBodyConnector吸附"""
	if not is_turret_editing_mode or not current_editing_turret:
		print("❌ 错误：不在炮塔编辑模式或没有当前编辑的炮塔")
		return
	
	# 检查是否有选中的块
	if not current_block_scene:
		print("❌ 炮塔编辑模式：请先选择一个块")
		return
	
	# 如果没有吸附配置，使用自由放置
	if not turret_snap_config or turret_snap_config.is_empty():
		print("❌ 炮塔编辑模式：无法吸附，请靠近连接点")
		# 调试信息
		debug_ghost_connectors()
		if current_editing_turret:
			debug_turret_connectors()
		return
	
	print("✅ 开始放置块，吸附配置:", turret_snap_config)
	
	# 创建新块并添加到炮塔
	var new_block: Block = current_block_scene.instantiate()
	
	# 设置碰撞层为2（炮塔层）
	if new_block is CollisionObject2D:
		new_block.collision_layer = 2
		new_block.collision_mask = 2
	
	# 设置块的位置和旋转（使用吸附位置）
	new_block.global_position = turret_snap_config.ghost_position
	new_block.global_rotation = turret_snap_config.ghost_rotation
	new_block.base_rotation_degree = rad_to_deg(turret_snap_config.ghost_rotation)
	
	print("📐 设置块位置: ", new_block.global_position, " 旋转: ", new_block.base_rotation_degree)
	
	# 计算网格位置（基于16x16网格）
	var grid_positions = calculate_turret_block_grid_positions_from_placement(new_block)
	print("📊 计算出的网格位置: ", grid_positions)
	
	# 检查位置是否可用
	var position_available = true
	for pos in grid_positions:
		if not current_editing_turret.is_position_available(pos):
			print("❌ 炮塔编辑模式：位置 ", pos, " 已被占用")
			position_available = false
			break
	
	if not position_available:
		new_block.queue_free()
		return
	
	print("✅ 所有网格位置可用")
	
	# 添加到炮塔
	current_editing_turret.add_block_to_turret(new_block, grid_positions)
	
	print("🎉 炮塔编辑模式放置块成功: ", new_block.block_name, " 在炮塔 ", current_editing_turret.block_name)
	
	# 建立物理连接
	if turret_snap_config.turret_connector and turret_snap_config.block_connector:
		print("🔗 尝试建立物理连接...")
		establish_turret_rigidbody_connection(turret_snap_config.turret_connector, new_block, turret_snap_config.block_connector)
	else:
		print("⚠️ 没有找到连接器，跳过物理连接")
	
	# 继续放置同一类型的块
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
func establish_turret_rigidbody_connection(turret_connector: RigidBodyConnector, new_block: Block, block_connector: RigidBodyConnector):
	"""建立炮塔的RigidBody连接"""
	# 在新块中查找对应的连接器
	var new_block_connectors = new_block.find_children("*", "RigidBodyConnector")
	var target_connector = null
	
	for connector in new_block_connectors:
		if connector is RigidBodyConnector and connector.name == block_connector.name:
			target_connector = connector
			break
	
	if target_connector is RigidBodyConnector:
		# 启用连接器并尝试连接
		target_connector.is_connection_enabled = true
		turret_connector.try_connect(target_connector)
		print("炮塔物理连接建立: ", turret_connector.name, " -> ", target_connector.name)
	else:
		print("警告: 无法建立炮塔物理连接")

func can_connectors_connect(connector_a: RigidBodyConnector, connector_b: RigidBodyConnector) -> bool:
	"""检查两个RigidBodyConnector是否可以连接"""
	# 检查连接器是否有效
	if not connector_a or not connector_b:
		return false
	
	# 检查连接类型是否匹配
	if connector_a.connection_type != connector_b.connection_type:
		print("连接类型不匹配: ", connector_a.connection_type, " vs ", connector_b.connection_type)
		return false
	
	# 检查连接器是否启用
	if not connector_a.is_connection_enabled or not connector_b.is_connection_enabled:
		print("连接器未启用")
		return false
	
	# 检查是否已经连接
	if connector_a.connected_to != null or connector_b.connected_to != null:
		print("连接器已连接")
		return false
	
	# 检查是否一个是Block，一个是RigidBody
	var a_is_block = connector_a.is_attached_to_block()
	var b_is_block = connector_b.is_attached_to_block()
	
	print("连接器类型检查: A是Block=", a_is_block, " B是Block=", b_is_block)
	
	if a_is_block and b_is_block:
		print("两个都是Block，不连接")
		return false
	
	if not a_is_block and not b_is_block:
		print("两个都是RigidBody，不连接")
		return false
	
	print("✅ 连接器可以连接")
	return true

func calculate_turret_block_grid_positions_from_placement(block: Block) -> Array:
	"""从放置位置计算块的网格位置 - 基于16x16网格"""
	var positions = []
	
	# 将世界坐标转换为炮塔局部坐标
	var turret_local_pos = current_editing_turret.turret.to_local(block.global_position)
	
	# 计算基础网格位置（基于16x16网格）
	var base_pos = Vector2i(
		floor(turret_local_pos.x / GRID_SIZE),
		floor(turret_local_pos.y / GRID_SIZE)
	)
	
	# 根据块的大小和旋转计算所有网格位置
	for x in range(block.size.x):
		for y in range(block.size.y):
			var grid_pos: Vector2i
			
			# 计算相对于基础位置的偏移
			var offset_x = x
			var offset_y = y
			
			# 根据旋转调整偏移
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
					grid_pos = base_pos + Vector2i(offset_x, offset_y)  # 默认情况
			
			positions.append(grid_pos)
	
	return positions

func establish_turret_connection(turret_point: ConnectionPoint, new_block: Block, ghost_point: ConnectionPoint):
	"""建立炮塔连接"""
	# 在新块中查找对应的连接点
	var new_block_points = new_block.find_children("*", "ConnectionPoint")
	var target_point = null
	
	for point in new_block_points:
		if point is ConnectionPoint and point.name == ghost_point.name:
			target_point = point
			break
	
	if target_point is ConnectionPoint:
		target_point.is_connection_enabled = true
		turret_point.try_connect(target_point)
		print("炮塔连接建立: ", turret_point.name, " -> ", target_point.name)
	else:
		print("警告: 无法建立炮塔连接")

# === 炮塔检测功能 ===
func has_turret_blocks() -> bool:
	"""检测车辆中是否有炮塔块"""
	if not selected_vehicle:
		return false
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			# 检查是否是TurretRing类或其子类
			if block is TurretRing:
				return true
			# 或者通过类名检测
			if block.get_script() and "TurretRing" in block.get_script().resource_path:
				return true
	
	return false

func get_turret_blocks() -> Array:
	"""获取车辆中所有的炮塔块"""
	var turrets = []
	if not selected_vehicle:
		return turrets
	
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			if block is TurretRing:
				turrets.append(block)
			# 或者通过类名检测
			elif block.get_script() and "TurretRing" in block.get_script().resource_path:
				turrets.append(block)
	
	return turrets

func get_turret_at_position(position: Vector2) -> TurretRing:
	"""获取指定位置的炮塔块"""
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1  # 块所在的碰撞层
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is TurretRing and block.get_parent() == selected_vehicle:
			return block
	return null

func show_turret_mode_error(message: String):
	"""显示炮塔模式错误信息"""
	print("炮塔模式错误: ", message)
	
	# 在界面上显示错误信息
	error_label.text = message
	error_label.show()
	await get_tree().create_timer(3.0).timeout
	error_label.hide()

func update_turret_mode_status():
	"""更新炮塔模式状态显示"""
	if is_editing and selected_vehicle:
		var has_turrets = has_turret_blocks()
		var turret_count = get_turret_blocks().size()
		
		# 可以在控制台显示炮塔信息（可选）
		if Engine.get_frames_drawn() % 60 == 0:  # 每60帧显示一次，避免太频繁
			if has_turrets and not is_turret_editing_mode:
				print("检测到", turret_count, "个炮塔块，点击炮塔进入炮塔编辑模式")
			elif is_turret_editing_mode:
				print("炮塔编辑模式激活中，当前编辑: ", current_editing_turret.block_name if current_editing_turret else "无")

func debug_turret_blocks():
	"""调试炮塔块信息"""
	if not selected_vehicle:
		print("没有选中车辆")
		return
	
	var turrets = get_turret_blocks()
	print("=== 炮塔块检测 ===")
	print("炮塔块数量: ", turrets.size())
	for i in range(turrets.size()):
		var turret = turrets[i]
		if is_instance_valid(turret):
			print("炮塔 ", i, ": ", turret.block_name, " 类型: ", turret.get_class())
		else:
			print("炮塔 ", i, ": 无效")
	print("=================")

# === 炮塔网格预览功能 ===
func show_turret_grid_preview():
	"""显示当前编辑炮塔的网格预览"""
	hide_turret_grid_preview()
	
	if current_editing_turret and is_instance_valid(current_editing_turret):
		create_turret_grid_preview(current_editing_turret)

func hide_turret_grid_preview():
	"""隐藏所有炮塔网格预览"""
	for preview in turret_grid_previews:
		if is_instance_valid(preview):
			preview.queue_free()
	turret_grid_previews.clear()

func create_turret_grid_preview(turret: TurretRing):
	"""为炮塔创建网格预览 - 显示连接点"""
	# 创建网格线
	var grid_lines = Line2D.new()
	grid_lines.width = 1.0
	grid_lines.default_color = Color(0, 1, 0, 0.3)
	
	# 计算炮塔的边界
	var bounds = turret.get_turret_grid_bounds()
	var min_x = bounds.min_x
	var min_y = bounds.min_y
	var max_x = bounds.max_x
	var max_y = bounds.max_y
	
	# 添加网格线
	var points = []
	
	# 垂直线
	for x in range(min_x, max_x + 1):
		var line_x = x * GRID_SIZE
		points.append(Vector2(line_x, min_y * GRID_SIZE))
		points.append(Vector2(line_x, max_y * GRID_SIZE))
		points.append(Vector2(line_x, min_y * GRID_SIZE))
	
	# 水平线
	for y in range(min_y, max_y + 1):
		var line_y = y * GRID_SIZE
		points.append(Vector2(min_x * GRID_SIZE, line_y))
		points.append(Vector2(max_x * GRID_SIZE, line_y))
		points.append(Vector2(min_x * GRID_SIZE, line_y))
	
	grid_lines.points = points
	turret.turret.add_child(grid_lines)
	turret_grid_previews.append(grid_lines)
	
	# 显示连接点位置
	var connection_points = turret.get_available_connection_points()
	for point in connection_points:
		var point_marker = ColorRect.new()
		point_marker.size = Vector2(6, 6)
		point_marker.position = point.position - Vector2(3, 3)  # 居中显示
		point_marker.color = Color(1, 1, 0, 0.8)  # 黄色表示连接点
		turret.turret.add_child(point_marker)
		turret_grid_previews.append(point_marker)
	
	# 显示已占用位置的标记
	for grid_pos in turret.turret_grid:
		var occupied_marker = ColorRect.new()
		occupied_marker.size = Vector2(GRID_SIZE - 4, GRID_SIZE - 4)
		occupied_marker.position = Vector2(grid_pos.x * GRID_SIZE + 2, grid_pos.y * GRID_SIZE + 2)
		occupied_marker.color = Color(1, 0, 0, 0.3)  # 半透明红色表示已占用
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
	
	# 存储原始标签页名称
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
		# 在加载模式下，处理车辆选择
		var item_list = item_lists[tab_name]
		var vehicle_name = item_list.get_item_text(index)
		load_selected_vehicle(vehicle_name)
	else:
		# 正常模式下的方块选择
		var item_list = item_lists[tab_name]
		var scene_path = item_list.get_item_metadata(index)
		if scene_path:
			if is_recycle_mode:
				exit_recycle_mode()
			if is_turret_editing_mode:
				# 在炮塔编辑模式下选择方块，直接开始放置
				start_block_placement(scene_path)
			else:
				emit_signal("block_selected", scene_path)
				update_description(scene_path)
				if is_editing:
					start_block_placement(scene_path)
					# 放置新块后更新蓝图显示
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
	print("=== 保存按钮被点击 ===")
	print("当前选中的车辆: ", selected_vehicle)
	print("编辑模式状态: ", is_editing)
	
	# 直接尝试保存，不显示确认弹窗
	try_save_vehicle()

func _on_load_button_pressed():
	if is_loading_mode:
		# 如果已经在加载模式，切换回正常模式
		switch_to_normal_mode()
	else:
		# 切换到加载模式
		switch_to_loading_mode()

func switch_to_loading_mode():
	is_loading_mode = true
	load_button.add_theme_color_override("font_color", Color.CYAN)
	
	# 清空所有标签页
	for tab_name in item_lists:
		item_lists[tab_name].clear()
	
	# 加载蓝图文件夹中的车辆
	load_blueprint_vehicles()

func switch_to_normal_mode():
	is_loading_mode = false
	load_button.remove_theme_color_override("font_color")
	
	# 恢复原始方块列表
	load_all_blocks()
	
	# 恢复原始标签页标题
	for i in range(tab_container.get_tab_count()):
		if i < original_tab_names.size():
			tab_container.set_tab_title(i, original_tab_names[i])
	
	# 清除蓝图显示
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
	
	# 按字母顺序排序
	vehicle_names.sort()
	
	# 在所有标签页中显示车辆名称
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.clear()
		
		# 设置标签页标题
		var tab_index = tab_container.get_tab_count() - 1
		for i in range(tab_container.get_tab_count()):
			if tab_container.get_tab_control(i) == item_list:
				tab_index = i
				break
		
		if tab_name == "All":
			tab_container.set_tab_title(tab_index, "Vehicles")
		else:
			tab_container.set_tab_title(tab_index, "")
		
		# 添加车辆到列表
		for vehicle_name in vehicle_names:
			var _idx = item_list.add_item(vehicle_name)

func load_selected_vehicle(vehicle_name: String):
	print("显示蓝图虚影: ", vehicle_name)
	
	# 首先切换回正常模式
	switch_to_normal_mode()
	
	# 然后显示选定蓝图的虚影
	var blueprint_path = BLUEPRINT["BLUEPRINT"] + vehicle_name + ".json"
	var file = FileAccess.open(blueprint_path, FileAccess.READ)
	
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		
		if parse_result == OK:
			var blueprint_data_ghost = json.data
			print("成功加载蓝图: ", blueprint_data_ghost["name"])
			
			# 显示蓝图虚影
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
	
	# 清除之前的虚影
	clear_blueprint_ghosts()
	
	# 存储蓝图数据
	blueprint_data = blueprint
	is_showing_blueprint = true
	
	# 获取当前车辆已有的块位置（用于检测哪些块缺失）
	var current_block_positions = {}
	
	for block in selected_vehicle.total_blocks:
		if is_instance_valid(block):
			# 获取块在车辆网格中的位置
			var block_grid_positions = get_block_grid_positions(block)
			for grid_pos in block_grid_positions:
				current_block_positions[grid_pos] = block
	
	print("当前车辆块数量: ", selected_vehicle.blocks.size())
	print("当前占用网格位置: ", current_block_positions.size())
	
	# 分析蓝图并创建缺失块的虚影
	var created_ghosts = 0
	var total_blueprint_blocks = 0
	
	for block_id in blueprint["blocks"]:
		total_blueprint_blocks += 1
		var block_data = blueprint["blocks"][block_id]
		var scene_path = block_data["path"]
		var base_pos = Vector2i(block_data["base_pos"][0], block_data["base_pos"][1])
		var rotation_deg = block_data["rotation"][0]
		
		# 计算这个块在蓝图中的网格位置
		var ghost_grid_positions = calculate_ghost_grid_positions(base_pos, rotation_deg, scene_path)
		
		# 检查这个块是否在当前车辆中缺失
		var is_missing = false
		for grid_pos in ghost_grid_positions:
			if not current_block_positions.has(grid_pos):
				is_missing = true
				break
		
		if is_missing:
			# 创建缺失块的虚影
			create_ghost_block_with_data(scene_path, rotation_deg, ghost_grid_positions)
			created_ghosts += 1
	
	print("蓝图总块数: ", total_blueprint_blocks, ", 缺失块数量: ", created_ghosts)
	print("显示蓝图虚影完成")

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
		print("警告: 场景 ", scene_path, " 不是Block类型")
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
					grid_pos = base_pos + Vector2i(x, y)  # 默认情况
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func get_block_grid_positions(block: Block) -> Array:
	var grid_positions = []
	
	# 在车辆网格中查找这个块的所有位置
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
	
	# 设置虚影外观
	ghost.modulate = Color(0.3, 0.6, 1.0, 0.5)
	ghost.z_index = 45
	ghost.visible = true
	
	# 使用精确的位置计算方法
	var ghost_world_position = calculate_ghost_world_position_precise(grid_positions)
	ghost.global_position = ghost_world_position[0]
	ghost.global_rotation = ghost_world_position[1] + deg_to_rad(rotation_deg)
	
	if ghost.has_method("set_base_rotation_degree"):
		ghost.base_rotation_degree = rotation_deg
	
	# 禁用碰撞
	setup_blueprint_ghost_collision(ghost)
	
	# 存储虚影数据
	var data = GhostData.new()
	data.grid_positions = grid_positions
	data.rotation_deg = rotation_deg
	ghost_data_map[ghost.get_instance_id()] = data
	
	blueprint_ghosts.append(ghost)
	
	print("创建虚影: ", ghost.block_name if ghost is Block else "未知", " 在网格位置 ", grid_positions)

func calculate_ghost_world_position_precise(grid_positions: Array):
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	var local_position = get_rectangle_corners_arry(grid_positions)
	
	# 方法1：使用车辆的第一个网格位置作为参考
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
				
				# 将局部偏移旋转到车辆的方向
				var rotated_offset = local_offset.rotated(first_rotation)
				
				# 返回世界坐标
				return [first_block.global_position + rotated_offset, first_rotation]
		
	# 方法2：使用车辆中心点
	return calculate_ghost_world_position_simple(grid_positions)

func calculate_ghost_world_position_simple(grid_positions: Array) -> Vector2:
	# 简单方法：基于车辆中心点计算
	if grid_positions.is_empty():
		return Vector2.ZERO
	
	# 计算网格中心
	var sum_x = 0
	var sum_y = 0
	for pos in grid_positions:
		sum_x += pos.x
		sum_y += pos.y
	
	var center_grid = Vector2(sum_x / float(grid_positions.size()), sum_y / float(grid_positions.size()))
	
	# 转换为世界坐标
	var grid_size = 16
	var local_center = Vector2(center_grid.x * grid_size, center_grid.y * grid_size)
	
	# 考虑车辆的全局变换
	return selected_vehicle.to_global(local_center)

func setup_blueprint_ghost_collision(ghost: Node2D):
	# 禁用所有碰撞形状
	var collision_shapes = ghost.find_children("*", "CollisionShape2D", true)
	for shape in collision_shapes:
		shape.disabled = true
	
	var collision_polygons = ghost.find_children("*", "CollisionPolygon2D", true)
	for poly in collision_polygons:
		poly.disabled = true
	
	# 如果是RigidBody2D，冻结它
	if ghost is RigidBody2D:
		ghost.freeze = true
		ghost.collision_layer = 0
		ghost.collision_mask = 0
	
	if ghost is Block:
		ghost.do_connect = false
	# 禁用所有连接点
	var connection_points = ghost.find_children("*", "ConnectionPoint", true)
	for point in connection_points:
		if point.has_method("set_connection_enabled"):
			point.set_connection_enabled(false)
			
func get_ghost_data(ghost: Node2D) -> GhostData:
	return ghost_data_map.get(ghost.get_instance_id())

func update_ghosts_transform():
	if not is_showing_blueprint or blueprint_ghosts.is_empty():
		return
	
	# 重新计算所有虚影的位置和旋转
	for ghost in blueprint_ghosts:
		if is_instance_valid(ghost):
			# 获取虚影对应的网格位置
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
		# 重新显示蓝图虚影（会清除旧的并创建新的）
		show_blueprint_ghosts(blueprint_data)

func toggle_blueprint_display():
	if is_editing and selected_vehicle:
		if is_showing_blueprint:
			clear_blueprint_ghosts()
			print("隐藏蓝图虚影")
		else:
			# 尝试从车辆获取蓝图数据
			if selected_vehicle.blueprint is Dictionary:
				show_blueprint_ghosts(selected_vehicle.blueprint)
				print("显示蓝图虚影")
			elif selected_vehicle.blueprint is String:
				# 从文件加载蓝图
				var blueprint_path = BLUEPRINT["BLUEPRINT"] + selected_vehicle.blueprint + ".json"
				var file = FileAccess.open(blueprint_path, FileAccess.READ)
				if file:
					var json_string = file.get_as_text()
					file.close()
					var json = JSON.new()
					if json.parse(json_string) == OK:
						show_blueprint_ghosts(json.data)
						print("显示蓝图虚影")
					else:
						print("错误: 无法解析蓝图文件")
				else:
					print("错误: 无法打开蓝图文件")

func try_save_vehicle():
	var vehicle_name = name_input.text.strip_edges()
	
	# 验证名称
	if vehicle_name.is_empty():
		show_error_dialog("Name cannot be empty!")
		return
	
	if vehicle_name.contains("/") or vehicle_name.contains("\\"):
		show_error_dialog("The name cannot contain special characters!")
		return
	
	# 直接保存
	save_vehicle(vehicle_name)

func show_error_dialog(error_message: String):
	error_label.text = error_message
	error_label.show()
	save_dialog.title = "Save Error"
	save_dialog.popup_centered()

func _on_save_confirmed():
	# 确认按钮现在只用于错误确认，关闭弹窗即可
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
	
	# 取消当前块放置
	if current_ghost_block:
		current_ghost_block.visible = false
	
	# 如果正在移动方块，取消移动
	if is_moving_block:
		cancel_block_move()
	
	# 退出炮塔编辑模式
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
	# 清除 TabContainer 的选择
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
	print("方块列表已重新加载")

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
			print("Find the vehicle: ", selected_vehicle.vehicle_name)
			return

func enter_editor_mode(vehicle: Vehicle):
	if is_editing:
		exit_editor_mode()
	selected_vehicle = vehicle

	is_editing = true
	
	# 如果不是通过新建车辆进入的编辑模式，则不是新车辆
	if not is_new_vehicle:
		is_first_block = false  # 编辑现有车辆时所有块都要吸附
	
	camera.focus_on_vehicle(selected_vehicle)
	camera.sync_rotation_to_vehicle(selected_vehicle)
	
	print("=== Enter edit mode ===")
	if is_first_block:
		print("新车辆 - 第一个块可以自由放置")
	else:
		print("编辑现有车辆 - 所有块都需要吸附连接")
	
	enable_all_connection_points_for_editing(true)
	
	vehicle.control = Callable()
	
	for block:Block in vehicle.blocks:
		block.collision_layer = 1
	
	show()
	
	# 重置连接点索引
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	
	toggle_blueprint_display()
	
	print("=== Edit mode ready ===")

func exit_editor_mode():
	if not is_editing:
		return
	
	# 如果正在炮塔编辑模式，先退出
	if is_turret_editing_mode:
		exit_turret_editing_mode()
	
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
		block.modulate = Color.WHITE  # 重置颜色
	
	is_new_vehicle = false
	is_first_block = true
	
	# 退出删除模式
	if is_recycle_mode:
		exit_recycle_mode()
	
	clear_tab_container_selection()
	print("=== Exit edit mode ===")
 	
	restore_original_connections()
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
	
	if current_ghost_block:
		current_ghost_block.queue_free()
		current_ghost_block = null
	
	# 清除蓝图显示
	clear_blueprint_ghosts()
	
	camera.target_rot = 0.0
	
	hide()
	is_editing = false
	panel_instance = null
	selected_vehicle = null
	print("=== 编辑模式已退出 ===")

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
	
	print("Start placing blocks: ", scene_path.get_file())
	
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
	
	# 如果是炮塔编辑模式，设置幽灵块的碰撞层为2
	if is_turret_editing_mode and current_ghost_block is CollisionObject2D:
		current_ghost_block.collision_layer = 2
		current_ghost_block.collision_mask = 2
	
	# 重置基础旋转角度
	current_ghost_block.base_rotation_degree = 0
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	# 重置连接点索引
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	current_snap_config = {}

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
	# 只有新车辆的第一个块可以自由放置
	if is_first_block and is_new_vehicle:
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = Color(0.8, 0.8, 1.0, 0.5)  # 蓝色表示自由放置
		current_snap_config = {}
		return
	
	# 其他情况都需要吸附：编辑现有车辆，或新车辆的非第一个块
	available_vehicle_points = selected_vehicle.get_available_points_near_position(mouse_position, 20.0)
	available_ghost_points = get_ghost_block_available_connection_points()
	
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		# 没有可用连接点，自由移动
		current_ghost_block.global_position = mouse_position
		current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree) + camera.target_rot
		current_ghost_block.modulate = Color(1, 0.3, 0.3, 0.5)  # 红色表示无法连接
		current_snap_config = {}
		return
	
	# 获取当前连接配置
	snap_config = get_current_snap_config()
	
	if snap_config:
		# 应用吸附位置和自动对齐的旋转
		current_ghost_block.global_position = snap_config.ghost_position
		current_ghost_block.global_rotation = snap_config.ghost_rotation
		current_ghost_block.modulate = Color(0.5, 1, 0.5, 0.5)  # 绿色表示可以连接
		current_snap_config = snap_config
	else:
		# 自由移动
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
	# 寻找最佳匹配的连接点（基于基础旋转来寻找合适的对齐）
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
			# 基于基础旋转计算最佳对齐角度
			var target_rotation = calculate_aligned_rotation_from_base(vehicle_block)
			# 检查连接点是否可以连接
			if not can_points_connect_with_rotation(vehicle_point, ghost_point, target_rotation):
				continue
				
			var positions = calculate_rotated_grid_positions(vehicle_point, ghost_point)
			if positions is bool:
				continue
			# 计算幽灵块的位置
			var ghost_local_offset = ghost_point.position.rotated(target_rotation)
			var ghost_position = vehicle_point_global - ghost_local_offset
			# 计算鼠标位置与连接点的距离
			var mouse_pos = get_viewport().get_mouse_position()
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
			var distance = global_mouse_pos.distance_to(ghost_position)
			# 选择距离鼠标最近的点
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

func normalize_rotation_simple(angle: float) -> float:
	var normalized = wrapf(angle, 0, PI/2)
	return normalized

func can_points_connect_with_rotation(point_a: ConnectionPoint, point_b: ConnectionPoint, ghost_rotation: float) -> bool:
	# 检查连接点类型是否匹配
	if point_a.connection_type != point_b.connection_type:
		return false
	# 检查连接点是否启用
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	# 计算幽灵块连接点在指定旋转下的全局方向
	var ghost_point_direction = point_b.rotation + ghost_rotation
	var angle_diff = are_rotations_opposite_best(ghost_point_direction, point_a.global_rotation)
	return angle_diff   # 允许稍大的误差，因为是基于基础旋转的对齐

func are_rotations_opposite_best(rot1: float, rot2: float) -> bool:
	"""
	最可靠的相对角度检测
	"""
	# 使用向量点积的方法来检测方向相对性
	var dir1 = Vector2(cos(rot1), sin(rot1))
	var dir2 = Vector2(cos(rot2), sin(rot2))
	
	# 如果两个方向相反，点积应该接近-1
	var dot_product = dir1.dot(dir2)
	return dot_product < -0.9  # 对应约±25度的误差范围

func get_connection_point_global_position(point: ConnectionPoint, block: Block) -> Vector2:
	# 对于炮塔上的连接点，需要特殊处理
	if block is TurretRing and block.turret:
		# 炮塔连接点的全局位置需要从炮塔的turret子节点计算
		return block.turret.to_global(point.position)
	else:
		return block.global_position + point.position.rotated(block.global_rotation)

func rotate_ghost_connection():
	if not current_ghost_block:
		return
	
	# 旋转基础旋转90度
	current_ghost_block.base_rotation_degree += 90
	current_ghost_block.base_rotation_degree = fmod(current_ghost_block.base_rotation_degree + 90, 360) - 90
	
	# 更新幽灵方块显示（使用基础旋转）
	current_ghost_block.rotation = deg_to_rad(current_ghost_block.base_rotation_degree)
	
	# 更新位置
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)
	
func switch_vehicle_connection():
	if available_vehicle_points.is_empty():
		return
	
	# 切换到下一个车辆连接点
	current_vehicle_connection_index = (current_vehicle_connection_index + 1) % available_vehicle_points.size()
	print("切换到车辆连接点: ", current_vehicle_connection_index)
	
	# 更新位置
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_ghost_block_position(global_mouse_pos)

func can_points_connect(point_a: ConnectionPoint, point_b: ConnectionPoint) -> bool:
	# 检查连接点类型是否匹配
	if point_a.connection_type != point_b.connection_type:
		return false
	
	# 检查连接点是否启用
	if not point_a.is_connection_enabled or not point_b.is_connection_enabled:
		return false
	
	# 检查连接点方向是否相对（相差约180度）
	var angle_diff = abs(fmod(point_a.global_rotation - point_b.global_rotation + PI, PI * 2) - PI)
	return angle_diff < 0.1  # 允许小的误差

func calculate_aligned_rotation(vehicle_block: Block, vehicle_point: ConnectionPoint, ghost_point: ConnectionPoint) -> float:
	# 计算基础旋转角度（使连接点方向相对）
	var base_rotation = vehicle_block.global_rotation + vehicle_point.rotation - ghost_point.rotation + PI
	
	# 对齐到最近的90度倍数（0, 90, 180, 270度）
	var degrees = rad_to_deg(base_rotation)
	var aligned_degrees = round(degrees / 90) * 90
	return deg_to_rad(aligned_degrees)

func try_place_block():
	if not current_ghost_block or not selected_vehicle:
		return
	
	# 只有新车辆的第一个块可以自由放置
	if is_first_block and is_new_vehicle:
		place_first_block()
		return
	
	# 其他情况都需要吸附连接
	if not current_snap_config:
		return
	
	# 断开可能冲突的连接
	var connections_to_disconnect = find_connections_to_disconnect_for_placement()
	disconnect_connections(connections_to_disconnect)
	
	var grid_positions = snap_config.positions
	# 创建新块
	var new_block:Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_snap_config.ghost_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	var control = selected_vehicle.control
	# 计算网格位置并更新
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	
	selected_vehicle.control = control
	
	# 继续放置同一类型的块（保持当前基础旋转）
	start_block_placement_with_rotation(current_block_scene.resource_path)
	
	# 放置块后更新蓝图显示
	update_blueprint_ghosts()

func place_first_block():
	# 创建新块
	var new_block:Block = current_block_scene.instantiate()
	selected_vehicle.add_child(new_block)
	new_block.global_position = current_ghost_block.global_position
	new_block.global_rotation = current_ghost_block.global_rotation
	new_block.base_rotation_degree = current_ghost_block.base_rotation_degree
	
	# 计算网格位置（基于世界坐标）
	var grid_positions = calculate_free_grid_positions(new_block)
	
	var control = selected_vehicle.control
	# 计算网格位置并更新
	selected_vehicle._add_block(new_block, new_block.position, grid_positions)
	selected_vehicle.control = control
	
	# 第一个块放置完成后，关闭自由放置模式
	is_first_block = false
	
	print("第一个块放置完成: ", new_block.block_name)
	print("现在开始所有块都需要吸附连接")
	
	# 继续放置同一类型的块
	start_block_placement_with_rotation(current_block_scene.resource_path)

func calculate_free_grid_positions(block: Block) -> Array:
	var grid_positions = []
	var world_pos = block.global_position
	var grid_x = int(round(world_pos.x / GRID_SIZE))
	var grid_y = int(round(world_pos.y / GRID_SIZE))
	
	# 根据块的大小和旋转计算所有网格位置
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
					grid_pos = Vector2i(grid_x + x, grid_y + y)  # 默认情况
			
			grid_positions.append(grid_pos)
	
	return grid_positions

func start_block_placement_with_rotation(scene_path: String):
	if not is_editing or not selected_vehicle:
		return
	
	print("Start placing blocks: ", current_ghost_block.block_name, " Basic rotation: ", current_ghost_block.base_rotation_degree, " degree")
	
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
	
	# 如果是炮塔编辑模式，设置幽灵块的碰撞层为2
	if is_turret_editing_mode and current_ghost_block is CollisionObject2D:
		current_ghost_block.collision_layer = 2
		current_ghost_block.collision_mask = 2
	
	# 保持之前的基础旋转
	current_ghost_block.base_rotation_degree = base_rotation_degree
	current_ghost_block.rotation = deg_to_rad(base_rotation_degree)
	
	setup_ghost_block_collision(current_ghost_block)
	
	# 重置连接点索引
	current_ghost_connection_index = 0
	current_vehicle_connection_index = 0
	current_snap_config = {}

func establish_connection(vehicle_point: ConnectionPoint, new_block: Block, ghost_point: ConnectionPoint):
	# 在新块中查找对应的连接点
	var new_block_points = new_block.find_children("*", "ConnectionPoint")
	var target_point = null
	
	for point in new_block_points:
		if point is ConnectionPoint and point.name == ghost_point.name:
			target_point = point
			break
	
	if target_point is ConnectionPoint:
		target_point.is_connection_enabled = true
		vehicle_point.try_connect(target_point)
		print("连接建立: ", vehicle_point.name, " -> ", target_point.name)
	else:
		print("警告: 无法建立连接")

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
	# 提取重复的连接点计算逻辑
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

# 提取的重复逻辑函数
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
			print("Remove block: ", block_name)
			
			# 移除块后更新蓝图显示
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
	print("放置已取消")

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

func _on_vehicle_saved(vehicle_name: String):
	save_vehicle(vehicle_name)

func save_vehicle(vehicle_name: String):
	if not selected_vehicle:
		print("Error: No vehicle selected")
		return
	
	print("Saving vehicle: ", vehicle_name)
	
	var blueprint_data_save = create_blueprint_data(vehicle_name)
	var blueprint_path = "res://vehicles/blueprint/%s.json" % vehicle_name
	
	if save_blueprint(blueprint_data_save, blueprint_path):
		selected_vehicle.vehicle_name = vehicle_name
		selected_vehicle.blueprint = blueprint_data_save
		print("Vehicle saved successfully: ", blueprint_path)
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

func save_blueprint(blueprint_data_save: Dictionary, save_path: String) -> bool:
	var dir = DirAccess.open("res://vehicles/blueprint/")
	if not dir:
		DirAccess.make_dir_absolute("res://vehicles/blueprint/")
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(blueprint_data_save, "\t"))
		file.close()
		print("Vehicle blueprint has been saved to:", save_path)
		return true
	else:
		push_error("Failed to save file:", FileAccess.get_open_error())
		return false

func update_recycle_highlight():
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	
	# 重置所有块的颜色
	reset_all_blocks_color()
	
	# 检测鼠标下的块并高亮为红色
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = global_mouse_pos
	query.collision_mask = 1  # 只检测块所在的碰撞层
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == selected_vehicle:
			# 将要删除的块变成红色
			block.modulate = Color.RED
			break

# 重置所有块的颜色
func reset_all_blocks_color():
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			block.modulate = Color.WHITE

# 退出删除模式
func exit_recycle_mode():
	if is_recycle_mode:
		is_recycle_mode = false
		Input.set_custom_mouse_cursor(null)
		update_recycle_button()
		
		# 重置所有块的颜色
		if selected_vehicle:
			reset_all_blocks_color()
		
		emit_signal("recycle_mode_toggled", false)

# 创建新车辆
func create_new_vehicle():
	print("开始创建新车辆...")
	if is_editing:
		exit_editor_mode()
		if is_editing:
			return
	# 创建新的 Vehicle 实例
	var new_vehicle = Vehicle.new()
	new_vehicle.vehicle_name = "NewVehicle_" + str(Time.get_unix_time_from_system())
	new_vehicle.blueprint = {}  # 暂无蓝图
	
	# 设置车辆位置为摄像机中心
	if camera:
		new_vehicle.global_position = camera.global_position
		print("新车辆位置: ", new_vehicle.global_position)
	else:
		print("警告: 未找到摄像机，使用默认位置")
		new_vehicle.global_position = Vector2(500, 300)
	
	# 添加到当前场景
	var current_scene = get_tree().current_scene
	current_scene.add_child(new_vehicle)
	
	# 进入编辑模式，标记为新车辆
	enter_editor_mode_with_new_vehicle(new_vehicle)
	
	print("新车辆创建完成: ", new_vehicle.vehicle_name)

func enter_editor_mode_with_new_vehicle(vehicle: Vehicle):
	# 设置选中的车辆
	selected_vehicle = vehicle
	
	# 标记为新车辆
	is_new_vehicle = true
	is_first_block = true  # 新车辆的第一个块可以自由放置
	
	# 清空名称输入框
	name_input.text = ""
	
	# 进入编辑模式
	enter_editor_mode(vehicle)
	
	print("已进入新车辆的编辑模式 - 第一个块可以自由放置")

func clear_tab_container_selection():
	for tab_name in item_lists:
		var item_list = item_lists[tab_name]
		item_list.deselect_all()
		item_list.release_focus()

func _on_repair_button_pressed():
	if not is_editing or not selected_vehicle or not is_showing_blueprint:
		print("修复条件不满足：需要处于编辑模式、选中车辆且显示蓝图")
		return
	
	print("开始修复蓝图缺失部分...")
	repair_blueprint_missing_blocks()

func repair_blueprint_missing_blocks():
	for pos in selected_vehicle.grid.keys():
		var block = selected_vehicle.grid[pos]
		if block is Block:
			if block.current_hp < block.max_hp:
				block.current_hp = block.max_hp
	if not blueprint_data or blueprint_ghosts.is_empty():
		print("没有需要修复的蓝图虚影")
		return
	
	var repaired_count = 0
	var failed_count = 0
	
	# 获取当前车辆已占用的网格位置
	var occupied_grid_positions = {}
	for grid_pos in selected_vehicle.grid:
		occupied_grid_positions[grid_pos] = true
	
	# 遍历所有蓝图虚影
	for ghost in blueprint_ghosts:
		if not is_instance_valid(ghost):
			continue
		
		var ghost_data = get_ghost_data(ghost)
		if not ghost_data:
			continue
		
		# 检查这个虚影的位置是否被占用
		var can_place = true
		for grid_pos in ghost_data.grid_positions:
			if occupied_grid_positions.has(grid_pos):
				can_place = false
				print("无法修复：网格位置 ", grid_pos, " 已被占用")
				break
		
		if can_place:
			# 尝试放置这个块
			if try_place_ghost_block(ghost, ghost_data):
				repaired_count += 1
				# 更新已占用位置
				for grid_pos in ghost_data.grid_positions:
					occupied_grid_positions[grid_pos] = true
			else:
				failed_count += 1
	
	print("修复完成：成功修复 ", repaired_count, " 个块，失败 ", failed_count, " 个块")
	
	# 修复后更新蓝图显示（会重新计算缺失的块）
	if repaired_count > 0:
		update_blueprint_ghosts()

func try_place_ghost_block(ghost: Node2D, ghost_data: GhostData) -> bool:
	# 加载块场景
	var scene_path = ghost.scene_file_path
	if not scene_path or scene_path.is_empty():
		print("错误：无法获取虚影的场景路径")
		return false
	
	var scene = load(scene_path)
	if not scene:
		print("错误：无法加载场景 ", scene_path)
		return false
	
	# 创建新块
	var new_block: Block = scene.instantiate()
	selected_vehicle.add_child(new_block)
	
	# 设置块的位置和旋转
	new_block.global_position = ghost.global_position
	new_block.global_rotation = ghost.global_rotation
	new_block.base_rotation_degree = ghost_data.rotation_deg
	
	# 添加到车辆网格
	var control = selected_vehicle.control
	selected_vehicle._add_block(new_block, new_block.position, ghost_data.grid_positions)
	selected_vehicle.control = control
	
	print("成功修复块: ", new_block.block_name, " 在位置 ", ghost_data.grid_positions)
	return true

# === 长按拖拽功能 ===

func get_block_at_position(position: Vector2) -> Block:
	"""获取指定位置的方块"""
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
	"""开始拖拽方块"""
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	var block = get_block_at_position(global_mouse_pos)
	
	if block:
		print("开始拖拽方块: ", block.block_name)
		is_dragging = true
		start_block_move(block)

func update_moving_ghost_position(mouse_position: Vector2):
	"""更新移动虚影的位置"""
	if not moving_block_ghost:
		return
	
	# 使用和普通幽灵块相同的吸附系统
	available_vehicle_points = selected_vehicle.get_available_points_near_position(mouse_position, 50.0)
	available_ghost_points = get_moving_ghost_available_connection_points()
	
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		# 没有可用连接点，自由移动
		moving_block_ghost.global_position = mouse_position
		moving_block_ghost.rotation = deg_to_rad(moving_block_ghost.base_rotation_degree) + camera.target_rot
		moving_block_ghost.modulate = Color(1, 1, 0.3, 0.7)  # 黄色表示自由移动
		moving_snap_config = {}
		return
	
	# 获取吸附配置
	var snap_config = get_current_snap_config_for_moving()
	
	if snap_config:
		# 应用吸附位置和自动对齐的旋转
		moving_block_ghost.global_position = snap_config.ghost_position
		moving_block_ghost.global_rotation = snap_config.ghost_rotation
		moving_block_ghost.modulate = Color(0.5, 1, 0.5, 0.7)  # 绿色表示可以连接
		moving_snap_config = snap_config
	else:
		# 自由移动
		moving_block_ghost.global_position = mouse_position
		moving_block_ghost.rotation = deg_to_rad(moving_block_ghost.base_rotation_degree) + camera.target_rot
		moving_block_ghost.modulate = Color(1, 1, 0.3, 0.7)
		moving_snap_config = {}

func get_current_snap_config_for_moving() -> Dictionary:
	"""为移动虚影获取吸附配置 - 重用普通吸附逻辑"""
	if available_vehicle_points.is_empty() or available_ghost_points.is_empty():
		return {}
	
	# 临时替换 current_ghost_block 以便重用现有的吸附逻辑
	var original_ghost = current_ghost_block
	current_ghost_block = moving_block_ghost
	
	var best_config = find_best_snap_config()
	
	# 恢复原始幽灵块
	current_ghost_block = original_ghost
	
	return best_config

func get_moving_ghost_available_connection_points() -> Array[ConnectionPoint]:
	"""获取移动虚影的可用连接点"""
	var points: Array[ConnectionPoint] = []
	if moving_block_ghost:
		var connection_points = moving_block_ghost.get_available_connection_points()
		for point in connection_points:
			if point is ConnectionPoint:
				point.qeck = false
				points.append(point)
	return points

func start_block_move(block: Block):
	"""开始移动指定的方块"""
	if is_moving_block:
		cancel_block_move()
	
	print("开始移动方块: ", block.block_name)
	
	# 存储原始信息
	moving_block = block
	moving_block_original_position = block.global_position
	moving_block_original_rotation = block.global_rotation
	moving_block_original_grid_positions = get_block_grid_positions(block)
	
	# 创建移动虚影
	create_moving_ghost(block)
	
	# 从车辆中临时移除方块（不断开连接）
	var control = selected_vehicle.control
	selected_vehicle.remove_block(block, false)  # false表示不断开连接
	selected_vehicle.control = control
	
	# 设置移动状态
	is_moving_block = true
	
	# 重置吸附配置
	moving_snap_config = {}
	
	# 隐藏原始方块
	block.visible = false
	
	# 取消当前幽灵块放置
	if current_ghost_block:
		current_ghost_block.visible = false

func create_moving_ghost(block: Block):
	"""为移动的方块创建虚影"""
	var scene_path = block.scene_file_path
	if not scene_path or scene_path.is_empty():
		print("错误：无法获取方块场景路径")
		return
	
	var scene = load(scene_path)
	if not scene:
		print("错误：无法加载场景 ", scene_path)
		return
	
	moving_block_ghost = scene.instantiate()
	get_tree().current_scene.add_child(moving_block_ghost)
	
	# 设置虚影外观
	moving_block_ghost.modulate = Color(1, 1, 0.5, 0.7)  # 黄色半透明
	moving_block_ghost.z_index = 100
	moving_block_ghost.global_position = moving_block_original_position
	moving_block_ghost.global_rotation = moving_block_original_rotation
	moving_block_ghost.base_rotation_degree = moving_block.base_rotation_degree
	
	# 设置碰撞
	setup_moving_ghost_collision(moving_block_ghost)
	
	print("创建移动虚影: ", moving_block_ghost.block_name)

func setup_moving_ghost_collision(ghost: Node2D):
	"""设置移动虚影的碰撞"""
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
	"""放置移动的方块"""
	if not is_moving_block or not moving_block or not moving_block_ghost:
		return
	
	print("放置移动的方块: ", moving_block.block_name)
	
	# 如果有吸附配置，使用吸附位置
	if moving_snap_config and not moving_snap_config.is_empty():
		print("使用吸附配置放置")
		
		# 断开可能冲突的连接
		var connections_to_disconnect = find_connections_to_disconnect_for_moving()
		disconnect_connections(connections_to_disconnect)
		
		var grid_positions = moving_snap_config.positions
		
		# 检查网格位置是否可用
		if not are_grid_positions_available(grid_positions):
			print("网格位置被占用，放回原位置")
			cancel_block_move()
			return
		
		# 设置方块的新位置和旋转
		moving_block.global_position = moving_snap_config.ghost_position
		moving_block.global_rotation = moving_snap_config.ghost_rotation
		
		# 计算正确的基础旋转角度
		var world_rotation_deg = rad_to_deg(moving_snap_config.ghost_rotation)
		var camera_rotation_deg = rad_to_deg(camera.target_rot)
		moving_block.base_rotation_degree = wrapf(world_rotation_deg - camera_rotation_deg, -180, 180)
		
		# 重新添加到车辆
		var control = selected_vehicle.control
		selected_vehicle._add_block(moving_block, moving_block.position, grid_positions)
		selected_vehicle.control = control
		
		print("方块已成功移动到新位置")
	else:
		# 没有吸附，放回原位置
		print("没有吸附配置，放回原位置")
		cancel_block_move()
		return
	
	# 完成移动
	finish_block_move()
	
	# 放置块后更新蓝图显示
	update_blueprint_ghosts()

func are_grid_positions_available(grid_positions: Array) -> bool:
	"""检查网格位置是否可用"""
	for pos in grid_positions:
		if selected_vehicle.grid.has(pos):
			print("位置 ", pos, " 已被占用")
			return false
	return true

func find_connections_to_disconnect_for_moving() -> Array:
	"""为移动方块查找需要断开的连接"""
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
	"""取消方块移动，将方块放回原位置"""
	if not is_moving_block or not moving_block:
		return
	
	print("取消移动方块: ", moving_block.block_name)
	
	# 恢复方块的原始位置和旋转
	moving_block.global_position = moving_block_original_position
	moving_block.global_rotation = moving_block_original_rotation
	moving_block.base_rotation_degree = rad_to_deg(moving_block_original_rotation - camera.target_rot)
	
	# 重新添加到车辆的原始位置
	var control = selected_vehicle.control
	selected_vehicle._add_block(moving_block, moving_block.position, moving_block_original_grid_positions)
	selected_vehicle.control = control
	
	# 完成移动（恢复状态）
	finish_block_move()

func finish_block_move():
	"""完成方块移动，清理资源"""
	if moving_block:
		moving_block.visible = true
		moving_block = null
	
	if moving_block_ghost:
		moving_block_ghost.queue_free()
		moving_block_ghost = null
	
	is_moving_block = false
	is_dragging = false
	moving_snap_config = {}
	
	# 恢复幽灵块显示
	if current_ghost_block:
		current_ghost_block.visible = true
	
	print("方块移动完成")

func rotate_moving_ghost():
	"""旋转移动中的虚影"""
	if not moving_block_ghost:
		return
	
	# 旋转基础旋转90度
	moving_block_ghost.base_rotation_degree += 90
	moving_block_ghost.base_rotation_degree = fmod(moving_block_ghost.base_rotation_degree + 90, 360) - 90
	
	# 更新虚影显示
	moving_block_ghost.rotation = deg_to_rad(moving_block_ghost.base_rotation_degree) + camera.target_rot
	
	# 更新位置
	var mouse_pos = get_viewport().get_mouse_position()
	var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	update_moving_ghost_position(global_mouse_pos)

# === 调试功能 ===
func debug_block_layers():
	"""调试所有块的碰撞层"""
	if not selected_vehicle:
		return
	
	print("=== 块碰撞层调试 ===")
	for block in selected_vehicle.blocks:
		if is_instance_valid(block):
			print("块: ", block.block_name, " 层: ", block.collision_layer)
	
	# 调试炮塔上的块
	var turrets = get_turret_blocks()
	for turret in turrets:
		if is_instance_valid(turret):
			print("炮塔: ", turret.block_name)
			for turret_block in turret.turret_blocks:
				if is_instance_valid(turret_block):
					print("  炮塔块: ", turret_block.block_name, " 层: ", turret_block.collision_layer)
	print("==================")

func debug_turret_connectors():
	"""调试炮塔连接器信息"""
	if not current_editing_turret:
		return
	
	print("=== 炮塔连接器调试 ===")
	var connectors = get_turret_available_rigidbody_connectors()
	print("炮塔连接器数量: ", connectors.size())
	
	for i in range(connectors.size()):
		var connector = connectors[i]
		print("连接器 ", i, ": ", connector.name, 
			  " 位置: ", connector.global_position,
			  " 类型: ", connector.connection_type,
			  " 启用: ", connector.is_connection_enabled,
			  " 已连接: ", connector.connected_to != null)
	print("==================")

func debug_ghost_connectors():
	"""调试幽灵块连接器信息"""
	if not current_ghost_block:
		return
	
	print("=== 幽灵块连接器调试 ===")
	var connectors = get_ghost_block_available_rigidbody_connectors()
	print("幽灵块连接器数量: ", connectors.size())
	
	for i in range(connectors.size()):
		var connector = connectors[i]
		print("连接器 ", i, ": ", connector.name,
			  " 位置: ", connector.global_position,
			  " 类型: ", connector.connection_type,
			  " 启用: ", connector.is_connection_enabled,
			  " 已连接: ", connector.connected_to != null)
	print("==================")
