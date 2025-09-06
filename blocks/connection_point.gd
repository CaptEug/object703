class_name ConnectionPoint
extends Marker2D

# 严格对齐参数
@export var is_connection_enabled := false
@export var connection_range := 3.0  # 非常小的连接范围
@export var snap_angle_threshold := 30.0  # 角度对齐阈值(度)
@export var connection_type := "default"

var connected_to: ConnectionPoint = null
var joint: Joint2D = null
var detection_area: Area2D
var overlapping_points: Array[ConnectionPoint] = []

func _ready():
	setup_detection_area()
	queue_redraw()

func _process(_delta):
	# 即使 is_connection_enabled 为 false，也继续处理已存在的连接
	for other_point in overlapping_points:
		# 只处理已经连接的节点，不尝试新连接
		if connected_to == other_point:
			# 可以在这里添加维持连接的逻辑
			pass
		
		# 只有当启用时才尝试新连接
		if (is_connection_enabled and 
			other_point != self and 
			other_point.is_connection_enabled and 
			not connected_to and 
			not other_point.connected_to):
			try_connect(other_point)

func _draw():
	var color = Color.GREEN if connected_to else Color.RED
	draw_circle(Vector2.ZERO, 3, color)

func setup_detection_area():
	detection_area = Area2D.new()
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
	var other_point = area.get_parent()
	if other_point is ConnectionPoint:
		if not overlapping_points.has(other_point):
			overlapping_points.append(other_point)

func _on_area_exited(area: Area2D):
	var other_point = area.get_parent()
	if other_point is ConnectionPoint:
		overlapping_points.erase(other_point)
		# 如果断开的是当前连接的点
		if connected_to == other_point:
			disconnect_joint()

func try_connect(other_point: ConnectionPoint) -> bool:
	if not (is_connection_enabled and other_point.is_connection_enabled):
		return false
	
	if not can_connect_with(other_point):
		return false
	
	var parent_block = find_parent_block()
	var other_block = other_point.find_parent_block()
	
	if not parent_block or not other_block:
		return false
	
	# 检查两个块的移动性
	var parent_can_move = parent_block.is_movable_on_connection
	var other_can_move = other_block.is_movable_on_connection
	
	# 如果两个都不能移动，则不连接
	if not parent_can_move and not other_can_move:
		return false
	
	# 修改部分：强制对齐旋转到最近的90度增量 (0, 90, 180, 270)
	var angle_diff = other_block.global_rotation - parent_block.global_rotation
	var angle_deg = rad_to_deg(angle_diff)
	
	# 计算最近的90度增量
	var snapped_angle_deg = round(angle_deg / 90) * 90
	var snapped_angle = deg_to_rad(snapped_angle_deg)
	
	# 应用旋转对齐
	other_block.global_rotation = parent_block.global_rotation + snapped_angle
	
	# 计算精确位置对齐
	var offset = other_point.global_position - global_position
	
	# 根据移动性决定如何移动
	if parent_can_move and other_can_move:
		# 两个都可以移动，各自移动一半
		parent_block.global_position += offset * 0.5
		other_block.global_position -= offset * 0.5
	elif parent_can_move and not other_can_move:
		# 只有父块可以移动
		parent_block.global_position += offset
	elif not parent_can_move and other_can_move:
		# 只有其他块可以移动
		other_block.global_position -= offset
	
	# 创建固定连接
	parent_block.create_joint_with(self, other_point, true)  # 最后一个参数表示严格对齐
	return true

func can_connect_with(other_point: ConnectionPoint) -> bool:
	if connected_to or other_point.connected_to:
		return false
	
	# 检查角度是否接近90度增量对齐
	var parent_block = find_parent_block()
	var other_block = other_point.find_parent_block()
	if not parent_block or not other_block:
		return false
	
	var angle_diff = rad_to_deg(abs(other_block.global_rotation - parent_block.global_rotation))
	angle_diff = fmod(angle_diff, 90)  # 取模90度
	var angle_ok = min(angle_diff, 90 - angle_diff) < snap_angle_threshold
	
	return (
		connection_type == other_point.connection_type and
		global_position.distance_to(other_point.global_position) <= connection_range and
		angle_ok
	)

func find_parent_block() -> Node:
	var parent = get_parent()
	while parent:
		if parent is Block:
			return parent
		parent = parent.get_parent()
	return null

func disconnect_joint():
	# 先保存对面的连接点引用
	var other_point = connected_to
	
	if joint and is_instance_valid(joint):
		var parent_block = find_parent_block()
		if parent_block:
			parent_block.disconnect_joint(joint)
	
	# 清空本地连接状态
	connected_to = null
	joint = null
	
	# 如果对面的连接点仍然有效，也清空它的连接状态
	if other_point and is_instance_valid(other_point):
		other_point.connected_to = null
		other_point.joint = null
		other_point.queue_redraw()
	
	queue_redraw()

func set_connection_enabled(enabled: bool, keep_existing: bool = true):
	if is_connection_enabled == enabled:
		return
	
	is_connection_enabled = enabled
	
	# 只有当不保留现有连接且禁用时才断开
	if not keep_existing and not enabled and connected_to:
		disconnect_joint()
	
	queue_redraw()


func is_joint_active() -> bool:
	return joint != null and is_instance_valid(joint)
