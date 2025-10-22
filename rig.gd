class_name RigidBodyConnector
extends Marker2D

# 连接参数
@export var is_connection_enabled := true
@export var connection_range := 5.0
@export var connection_type := "rigidbody"
@export var location := Vector2i()

var connected_to: RigidBodyConnector = null
var joint: Joint2D = null
var detection_area: Area2D
var overlapping_connectors: Array[RigidBodyConnector] = []

# 新增：吸附相关属性
var is_snapping := false
var snap_target: RigidBodyConnector = null
var snap_distance_threshold := 10.0  # 吸附距离阈值

func _ready():
	setup_detection_area()
	queue_redraw()

func setup_detection_area():
	detection_area = Area2D.new()
	
	# 设置碰撞层和掩码
	detection_area.collision_layer = 0  # 自己不参与碰撞
	detection_area.collision_mask = 8   # 检测第4层（我们专门为连接器设置的层）
	
	var collider = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = connection_range
	collider.shape = shape
	detection_area.add_child(collider)
	
	# 设置检测区域也在第4层，这样其他连接器能检测到它
	detection_area.collision_layer = 8  # 自己在第4层
	
	add_child(detection_area)
	
	# 连接信号
	detection_area.connect("area_entered", Callable(self, "_on_area_entered"))
	detection_area.connect("area_exited", Callable(self, "_on_area_exited"))

func _on_area_entered(area: Area2D):
	var other_connector = area.get_parent()
	if other_connector is RigidBodyConnector:
		if other_connector != self:
			if not overlapping_connectors.has(other_connector):
				overlapping_connectors.append(other_connector)

func _on_area_exited(area: Area2D):
	var other_connector = area.get_parent()
	if other_connector is RigidBodyConnector:
		if other_connector in overlapping_connectors:
			overlapping_connectors.erase(other_connector)
			if snap_target == other_connector:
				snap_target = null
				is_snapping = false

# 新增：检查是否可以吸附到目标连接器
func can_snap_to(other_connector: RigidBodyConnector) -> bool:
	if not is_connection_enabled or not other_connector.is_connection_enabled:
		return false
	
	if connected_to != null or other_connector.connected_to != null:
		return false
	
	if connection_type != other_connector.connection_type:
		return false
	
	# 检查是否一个是Block，一个是RigidBody
	var self_is_block = is_attached_to_block()
	var other_is_block = other_connector.is_attached_to_block()
	
	if self_is_block and other_is_block:
		return false
	
	if not self_is_block and not other_is_block:
		return false
	
	return true

# 新增：获取最近的可用连接器用于吸附
func get_nearest_snap_target() -> RigidBodyConnector:
	var nearest_target: RigidBodyConnector = null
	var min_distance = snap_distance_threshold
	
	for other_connector in overlapping_connectors:
		if can_snap_to(other_connector):
			var distance = global_position.distance_to(other_connector.global_position)
			if distance < min_distance:
				min_distance = distance
				nearest_target = other_connector
	
	return nearest_target

# 新增：计算吸附位置和旋转
func calculate_snap_transform(other_connector: RigidBodyConnector) -> Dictionary:
	var result = {
		"position": Vector2.ZERO,
		"rotation": 0.0
	}
	
	# 如果是Block连接器吸附到RigidBody连接器
	if is_attached_to_block() and other_connector.is_attached_to_rigidbody():
		# Block移动到RigidBody连接器的位置
		result["position"] = other_connector.global_position
		# 保持Block当前的旋转，或者可以根据需要调整
		result["rotation"] = get_parent().global_rotation
		
	# 如果是RigidBody连接器吸附到Block连接器
	elif is_attached_to_rigidbody() and other_connector.is_attached_to_block():
		# RigidBody移动到Block连接器的位置
		result["position"] = other_connector.global_position
		result["rotation"] = get_parent().global_rotation
	
	return result

func is_attached_to_block() -> bool:
	var block = get_parent()
	if block is Block:
		block = block
	else:
		block = null
	var result = block != null
	return result

func is_attached_to_rigidbody() -> bool:
	var rigidbody = get_parent_rigidbody()
	var result = rigidbody != null
	return result

func get_connector_type() -> String:
	if is_attached_to_block():
		return "Block"
	elif is_attached_to_rigidbody():
		return "RigidBody"
	else:
		return "Unknown"

func get_parent_collision_layer() -> int:
	var parent = get_parent()
	if parent is CollisionObject2D:
		var layer = (parent as CollisionObject2D).collision_layer
		return layer
	return 0

func find_parent_block() -> Block:
	var parent = get_parent()
	while parent:
		if parent is Block:
			return parent as Block
		parent = parent.get_parent()
	return null

func get_parent_rigidbody() -> RigidBody2D:
	var parent = get_parent()
	if parent is RigidBody2D:
		return parent as RigidBody2D
	return null

func try_connect(other_connector: RigidBodyConnector) -> bool:
	# 新增：检查是否已经连接
	if connected_to != null:
		return false
	
	if other_connector.connected_to != null:
		return false
	
	if not is_connection_enabled:
		return false
	
	if not other_connector.is_connection_enabled:
		return false
	
	if not can_connect_with(other_connector):
		return false
	
	# 确定哪个是block，哪个是rigidbody
	var block_connector = self if is_attached_to_block() else other_connector
	var rigidbody_connector = self if is_attached_to_rigidbody() else other_connector
	
	# 确保一个是block，一个是rigidbody
	if block_connector == rigidbody_connector:
		return false
	
	var block = block_connector.find_parent_block()
	var rigidbody = rigidbody_connector.get_parent_rigidbody()
	
	if not block:
		return false
	
	if not rigidbody:
		return false
	
	# 创建连接
	connected_to = other_connector
	other_connector.connected_to = self
	
	# 使用block的连接方法
	joint = BlockPinJoint2D.connect_to_rigidbody(block, rigidbody, block_connector)
	
	if joint:
		# 在另一个连接器中也记录joint
		other_connector.joint = joint
		
		# 连接成功后，从重叠列表中移除已连接的连接器
		if other_connector in overlapping_connectors:
			overlapping_connectors.erase(other_connector)
		
		queue_redraw()
		other_connector.queue_redraw()
		return true
	else:
		connected_to = null
		other_connector.connected_to = null
		return false

func can_connect_with(other_connector: RigidBodyConnector) -> bool:
	# 新增：优先检查连接状态
	if connected_to != null:
		return false
	
	if other_connector.connected_to != null:
		return false
	
	# 检查连接类型是否匹配
	if connection_type != other_connector.connection_type:
		return false
	
	# 检查距离
	var distance = global_position.distance_to(other_connector.global_position)
	if distance > connection_range:
		return false
	
	# 检查是否一个是Block，一个是RigidBody
	var self_is_block = is_attached_to_block()
	var other_is_block = other_connector.is_attached_to_block()
	
	if self_is_block and other_is_block:
		return false
	
	if not self_is_block and not other_is_block:
		return false
	
	return true

func disconnect_connection():
	if connected_to:
		connected_to.connected_to = null
		connected_to.joint = null
		connected_to.queue_redraw()
	
	if joint and is_instance_valid(joint):
		if joint is BlockPinJoint2D:
			(joint as BlockPinJoint2D).break_connection()
		else:
			joint.queue_free()
	
	connected_to = null
	joint = null
	queue_redraw()

func set_connection_enabled(enabled: bool):
	if is_connection_enabled == enabled:
		return
	
	is_connection_enabled = enabled
	
	if not enabled and connected_to:
		disconnect_connection()
	
	queue_redraw()

func is_joint_connected() -> bool:
	return connected_to != null and joint != null and is_instance_valid(joint)

func get_connected_rigidbody() -> RigidBody2D:
	if not connected_to:
		return null
	return connected_to.get_parent_rigidbody()

func get_connected_block() -> Block:
	if not connected_to:
		return null
	return connected_to.find_parent_block()

func _draw():
	if Engine.is_editor_hint() or get_tree().debug_collisions_hint:
		var color: Color
		if is_joint_connected():
			color = Color.GREEN
		elif is_connection_enabled:
			color = Color.YELLOW
		else:
			color = Color.RED
		
		# 绘制连接范围圆圈
		draw_arc(Vector2.ZERO, connection_range, 0, TAU, 32, color, 1.0)
		
		# 绘制连接状态指示器
		if is_joint_connected():
			draw_circle(Vector2.ZERO, 3, Color.GREEN)
		else:
			draw_circle(Vector2.ZERO, 2, color)
