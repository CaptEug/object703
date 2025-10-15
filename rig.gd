class_name RigidBodyConnector
extends Marker2D

# 连接参数
@export var is_connection_enabled := true
@export var connection_range := 10.0
@export var connection_type := "rigidbody"
@export var location := Vector2i()

var connected_to: RigidBodyConnector = null
var joint: Joint2D = null
var detection_area: Area2D
var overlapping_connectors: Array[RigidBodyConnector] = []

func _ready():
	setup_detection_area()
	queue_redraw()

func setup_detection_area():
	detection_area = Area2D.new()
	
	# 设置碰撞层和掩码为3，避免与其他层冲突
	detection_area.collision_layer = 3
	detection_area.collision_mask = 3
	
	var collider = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = connection_range
	collider.shape = shape
	detection_area.add_child(collider)
	add_child(detection_area)
	
	# 连接信号
	detection_area.connect("area_entered", Callable(self, "_on_area_entered"))
	detection_area.connect("area_exited", Callable(self, "_on_area_exited"))

func _on_area_entered(area: Area2D):
	var other_connector = area.get_parent()
	if other_connector is RigidBodyConnector and other_connector != self:
		if not overlapping_connectors.has(other_connector):
			overlapping_connectors.append(other_connector)
			try_connect(other_connector)

func _on_area_exited(area: Area2D):
	var other_connector = area.get_parent()
	if other_connector is RigidBodyConnector:
		if other_connector in overlapping_connectors:
			overlapping_connectors.erase(other_connector)

func try_connect(other_connector: RigidBodyConnector) -> bool:
	if not is_connection_enabled or connected_to != null:
		return false
	
	if not other_connector.is_connection_enabled or other_connector.connected_to != null:
		return false
	
	if not can_connect_with(other_connector):
		return false
	
	# 确定哪个是block，哪个是rigidbody
	var block_connector = self if get_parent() is Block else other_connector
	var rigidbody_connector = self if get_parent() is RigidBody2D else other_connector
	
	var block = block_connector.find_parent_block()
	var rigidbody = rigidbody_connector.get_parent_rigidbody()
	
	if not block or not rigidbody:
		return false
	
	# 创建连接
	connected_to = other_connector
	other_connector.connected_to = self
	
	# 使用block的连接方法
	joint = block.attach_to_rigidbody(rigidbody, block_connector)
	
	if joint:
		# 在另一个连接器中也记录joint
		other_connector.joint = joint
		print("点对点连接成功: ", block.name, " <-> ", rigidbody.name)
		return true
	else:
		connected_to = null
		other_connector.connected_to = null
		return false

func can_connect_with(other_connector: RigidBodyConnector) -> bool:
	if connected_to != null or other_connector.connected_to != null:
		return false
	
	# 检查连接类型是否匹配
	if connection_type != other_connector.connection_type:
		return false
	
	# 检查距离
	var distance = global_position.distance_to(other_connector.global_position)
	if distance > connection_range:
		return false
	
	# 检查是否一个是Block，一个是RigidBody
	var has_block = get_parent() is Block or other_connector.get_parent() is Block
	var has_rigidbody = get_parent() is RigidBody2D or other_connector.get_parent() is RigidBody2D
	
	return has_block and has_rigidbody

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

func disconnect_connection():
	if connected_to:
		connected_to.connected_to = null
		connected_to.joint = null
	
	if joint and is_instance_valid(joint):
		var parent_block = find_parent_block()
		if parent_block:
			parent_block.disconnect_from_rigidbody(joint)
	
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

# 重命名这个方法避免冲突
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

func get_connection_info() -> String:
	var info = "RigidBodyConnector: " + name + "\n"
	info += "Enabled: " + str(is_connection_enabled) + "\n"
	info += "Connected: " + str(connected_to != null) + "\n"
	info += "Type: " + connection_type + "\n"
	
	if connected_to:
		var parent_type = "Block" if get_parent() is Block else "RigidBody"
		var other_type = "Block" if connected_to.get_parent() is Block else "RigidBody"
		info += "Connection: " + parent_type + " <-> " + other_type + "\n"
	
	return info
