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

func _process(delta):
	if not is_connection_enabled:
		return
	
	# 持续检测区域内的连接点
	for other_point in overlapping_points:
		if (other_point != self and 
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
	if not is_connection_enabled or not other_point.is_connection_enabled:
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
	
	# 强制对齐旋转(0度或180度)
	var angle_diff = other_block.global_rotation - parent_block.global_rotation
	var snapped_angle = round(angle_diff / PI) * PI  # 对齐到0或PI弧度
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
	
	# 检查角度是否接近对齐
	var parent_block = find_parent_block()
	var other_block = other_point.find_parent_block()
	if not parent_block or not other_block:
		return false
	
	var angle_diff = rad_to_deg(abs(other_block.global_rotation - parent_block.global_rotation))
	angle_diff = fmod(angle_diff, 180)
	var angle_ok = min(angle_diff, 180 - angle_diff) < snap_angle_threshold
	
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
	if joint and is_instance_valid(joint):
		var parent_block = find_parent_block()
		if parent_block:
			parent_block.disconnect_joint(joint)
	
	if connected_to and is_instance_valid(connected_to):
		connected_to.connected_to = null
		connected_to.joint = null
		connected_to.queue_redraw()
	
	connected_to = null
	joint = null
	queue_redraw()
