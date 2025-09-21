class_name ConnectionPoint
extends Marker2D

# 严格对齐参数
@export var is_connection_enabled := true
@export var connection_range := 5.0  # 非常小的连接范围
@export var snap_angle_threshold := 30.0  # 角度对齐阈值(度)
@export var connection_type := "default"

var connected_to: ConnectionPoint = null
var joint: Joint2D = null
var detection_area: Area2D
var overlapping_points: Array[ConnectionPoint] = []
var qeck = true

func _ready():
	setup_detection_area()
	queue_redraw()

func _process(_delta):
	if find_parent_block() != null:
		if find_parent_block().do_connect == false:
			qeck = false
		else:
			qeck = true
	# 即使 is_connection_enabled 为 false，也继续处理已存在的连接
	for other_point in overlapping_points:
		# 只处理已经连接的节点，不尝试新连接
		if connected_to == other_point:
			# 可以在这里添加维持连接的逻辑
			pass

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
			var con = [other_point, self]
			if find_parent_block().is_movable_on_connection == true:
				find_parent_block().overlapping_points.append(con)
			overlapping_points.append(other_point)

func _on_area_exited(area: Area2D):
	var other_point = area.get_parent()
	if other_point is ConnectionPoint:
		overlapping_points.erase(other_point)

func try_connect(other_point: ConnectionPoint) -> bool:
	#if not (is_connection_enabled and other_point.is_connection_enabled):
		#return false
	
	if not can_connect_with(other_point):
		return false
	
	var parent_block = find_parent_block()
	var other_block = other_point.find_parent_block()
	if not other_block.is_movable_on_connection:
		# 检查两个块的移动性
		var parent_can_move = parent_block.is_movable_on_connection
		var other_can_move = other_block.is_movable_on_connection
		var offset = other_point.global_position - global_position
		var rotate = other_point.global_rotation - PI
		if parent_can_move and not other_can_move and qeck == true:
			parent_block.global_position += offset
			parent_block.global_rotation = rotate - rotation
			parent_block.create_joint_with(self, other_point, true) 
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

func set_connection_enabled(enabled: bool, keep_existing: bool = true, protect_internal: bool = true):
	"""设置连接点启用状态
	enabled: 是否启用
	keep_existing: 是否保留现有连接
	protect_internal: 是否保护内部连接不断开
	"""
	if is_connection_enabled == enabled:
		return
	
	is_connection_enabled = enabled
	queue_redraw()

func is_internal_connection() -> bool:
	"""检查当前连接是否是内部连接（同一个车辆）"""
	if not connected_to:
		return false
	
	var parent_block = find_parent_block()
	var other_block = connected_to.find_parent_block()
	
	if not parent_block or not other_block:
		return false
	
	# 获取父车辆
	var parent_vehicle = get_parent_vehicle(parent_block)
	var other_vehicle = get_parent_vehicle(other_block)
	
	return parent_vehicle == other_vehicle and parent_vehicle != null

func get_parent_vehicle(block: Node) -> Node:
	"""获取块所在的车辆"""
	if not block:
		return null
	
	# 向上查找直到找到Vehicle节点
	var current = block
	while current:
		if current is Vehicle:
			return current
		current = current.get_parent()
	return null

func is_joint_active() -> bool:
	return joint != null and is_instance_valid(joint)

func highlight():
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.YELLOW, 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.3)

func unhighlight():
	modulate = Color.WHITE

# 新增：获取连接状态信息
func get_connection_info() -> String:
	var info = "ConnectionPoint: " + name + "\n"
	info += "Enabled: " + str(is_connection_enabled) + "\n"
	info += "Connected: " + str(connected_to != null) + "\n"
	info += "Type: " + connection_type + "\n"
	
	if connected_to:
		info += "Connected to: " + connected_to.name + "\n"
		info += "Internal: " + str(is_internal_connection()) + "\n"
	
	return info

# 新增：安全地检查连接状态
func is_safely_connected() -> bool:
	if not connected_to:
		return false
	
	# 检查连接是否仍然有效
	if not is_instance_valid(connected_to):
		connected_to = null
		joint = null
		return false
	
	return true

# 新增：强制断开连接（即使内部连接）
func force_disconnect():
	"""强制断开连接，忽略内部连接保护"""
	disconnect_joint()
