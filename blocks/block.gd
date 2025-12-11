class_name Block
extends RigidBody2D

## Basic Properties
var current_hp:float
var max_hp:float
var weight:float
var block_name:String
var type:String
var kinetic_absorb:float
var explosice_absorb:float
var size:Vector2i
var parent_vehicle: Vehicle = null  
var connected_blocks := []
var global_grid_pos
var mouse_inside:bool
var base_rotation_degree = 0
var cost:Dictionary = {}
var on_turret:TurretRing
var functioning:bool = true
var destroyed:bool
var sprite:Sprite2D
var broken_sprite:Sprite2D
var do_connect = true
var base_pos: Vector2i

var center_of_mass_offset: Vector2 = Vector2.ZERO

var shard_particle_path = "res://assets/particles/shard.tscn"

## Connection System
@export var connection_point_script: Script
@export var auto_detect_connection_points := true
@export var manual_connection_points: Array[Connector]
@export var is_movable_on_connection := true

var connection_points: Array[Connector] = []
var rigidbody_connectors: Array[TurretConnector] = []
var overlapping_points := []
var overlapping_rigidbody_connectors := []
var joint_connected_blocks := {}  # Tracks which blocks are connected through which joints

## Signals
signal connection_established(from: Connector, to: Connector, joint: Joint2D)
signal connection_broken(joint: Joint2D)
signal connections_processed(block: Block)

func _ready():
	# Initialize physics properties
	mass = weight/1000
	linear_damp = 5
	angular_damp = 1
	
	# init sprite
	sprite = find_child("Sprite2D") as Sprite2D
	broken_sprite = find_child("Broken") as Sprite2D
	
	# Set up input signals
	input_pickable = true
	connect("input_event", Callable(self, "_on_input_event"))
	connect("mouse_entered", Callable(self, "_on_mouse_entered"))
	connect("mouse_exited", Callable(self, "_on_mouse_exited"))
	
	# Collect connection points
	collect_connection_points()
	collect_rigidbody_connectors()
	
	enable_all_connectors(true)
	# Validation
	if connection_points.is_empty() and rigidbody_connectors.is_empty():
		push_warning("Block '%s' has no connection points" % block_name)

func _process(_delta):
	pass

func set_layer(i : int):
	self.collision_layer = i
	for joint in connection_points:
		if joint:
			joint.layer = i

func connect_aready():
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# 处理 Connector 连接
	if len(overlapping_points) > 0:
		for point_con in overlapping_points:
			var point1 = point_con[1]
			if point1 is Connector and is_movable_on_connection == true:
				point1.try_connect(point_con[0])
	
	# 处理 TurretConnector 连接
	if len(overlapping_rigidbody_connectors) > 0:
		for connector_con in overlapping_rigidbody_connectors:
			var connector1 = connector_con[1]
			if connector1 is TurretConnector and is_movable_on_connection == true:
				connector1.try_connect(connector_con[0])
	
	# 解冻逻辑
	for point_con in overlapping_points:
		if point_con[0].find_parent_block() is Block:
			if point_con[0].find_parent_block().freeze == true:
				point_con[0].find_parent_block().freeze = false
				
	for connector_con in overlapping_rigidbody_connectors:
		if connector_con[0].find_parent_block() is Block:
			if connector_con[0].find_parent_block().freeze == true:
				connector_con[0].find_parent_block().freeze = false
	
	is_movable_on_connection = false

## Physics and Drawing

func enable_all_connectors(enabled: bool):
	for point in connection_points:
		if is_instance_valid(point):
			point.is_connection_enabled = enabled
			point.qeck = enabled
	
	for connector in rigidbody_connectors:
		if is_instance_valid(connector):
			connector.is_connection_enabled = enabled
			connector.qeck = enabled

## Input Handling
func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton:
		if parent_vehicle:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				parent_vehicle.open_vehicle_panel()

func _on_mouse_entered():
	mouse_inside = true

func _on_mouse_exited():
	mouse_inside = false

func damage(amount:int):
	#print(str(name)+' receive damage:'+str(amount))
	current_hp -= amount
	# phase 1
	#if current_hp <= max_hp * 0.5:
		
	
	# phase 2
	if current_hp <= max_hp * 0.25:
		destroy()
	
	# phase 3
	if current_hp <= 0:
		queue_free()
		var shard_particle = load(shard_particle_path).instantiate()
		shard_particle.position = global_position
		get_tree().current_scene.add_child(shard_particle)

func destroy():
	if parent_vehicle:
		functioning = false
		parent_vehicle.update_vehicle()
		if broken_sprite:
			sprite.visible = false
			broken_sprite.visible = true
	# Disconnect all joints before destroying
	await disconnect_all()
	if parent_vehicle:
		parent_vehicle.remove_block(self, false)
	destroyed = true

## Block Management
func get_icon_texture():
	var texture_blocks := find_child("Sprite2D") as Sprite2D
	if texture_blocks != null:
		return texture_blocks.texture

func get_parent_vehicle():
	parent_vehicle = get_parent() as Vehicle
	if parent_vehicle:
		if self in parent_vehicle.blocks:
			return parent_vehicle
	return null

## Neighbor and Connectivity System
func get_all_connected_blocks() -> Array:
	connected_blocks.clear()
	get_connected_blocks(self)
	return connected_blocks

func get_connected_blocks(block: Block):
	if not is_instance_valid(block):
		return
	
	var jcb = block.joint_connected_blocks
	for blk in jcb.values():
		if is_instance_valid(blk) and not connected_blocks.has(blk) and blk != self:
			connected_blocks.append(blk)
			get_connected_blocks(blk)

func check_connectivity():
	if self is Command:
		return
	if not get_all_connected_blocks().any(func(item): return item is Command):
		if get_parent_vehicle():
			parent_vehicle.remove_block(self, false, true)

## Enhanced Connection Point System
func collect_connection_points():
	connection_points.clear()
	
	# Priority 1: Manually specified connection points
	if not manual_connection_points.is_empty():
		connection_points = manual_connection_points.duplicate()
		return
	
	# Priority 2: Auto-detection
	if auto_detect_connection_points:
		# Method 1: By script type
		if connection_point_script:
			var nodes = find_children("*", "", true, false)
			for node in nodes:
				if node.get_script() == connection_point_script:
					connection_points.append(node as Connector)
		
		# Method 2: Find all Connector nodes
		if connection_points.is_empty():
			var nodes = find_children("*", "Connector", true, false)
			for node in nodes:
				connection_points.append(node as Connector)

# 收集 TurretConnector 的方法
func collect_rigidbody_connectors():
	rigidbody_connectors.clear()
	var nodes = find_children("*", "TurretConnector", true, false)
	for node in nodes:
		rigidbody_connectors.append(node as TurretConnector)

func can_connect(source: Connector, target: Connector) -> bool:
	var source_block = source.find_parent_block()
	var target_block = target.find_parent_block()
	
	return (
		source_block != null and
		target_block != null and
		source_block != target_block and
		source.can_connect_with(target)
	)

func create_joint_with(source: Connector, target: Connector, _rigid_alignment: bool = false) -> Joint2D:
	if do_connect == true:
		var target_block = target.find_parent_block()
		if not target_block:
			return null
		# 使用焊接关节保证严格对齐
		var joint = PinJoint2D.new()
		#joint.initial_offset = 0
		#joint.length = 0.1
		joint.node_a = get_path()
		joint.node_b = target_block.get_path()
		joint.position = source.position
		joint.disable_collision = false
		joint.bias = 0.3
		joint.softness = 0.05
		joint.angular_limit_enabled = true
		joint.angular_limit_lower = -10
		joint.angular_limit_upper = 10
		add_child(joint)
		joint_connected_blocks[joint] = target_block
		if not target_block.joint_connected_blocks.has(joint):
			target_block.joint_connected_blocks[joint] = self
		
		source.joint = joint
		source.connected_to = target
		target.joint = joint
		target.connected_to = source
		
		connection_established.emit(source, target, joint)
		
		return joint
	return null

func disconnect_joint(joint: Joint2D):
	var should_disconnect = true
	for point in connection_points:
		if point.joint == joint and point.is_connection_enabled:
			should_disconnect = false
			break
	
	if not should_disconnect:
		return
	
	if not joint_connected_blocks.has(joint):
		return
	
	var other_block = joint_connected_blocks[joint]
	
	# Clean up the other block's reference
	if is_instance_valid(other_block) and other_block.joint_connected_blocks.has(joint):
		other_block.joint_connected_blocks.erase(joint)
	
	# Clean up our reference
	joint_connected_blocks.erase(joint)
	
	# Find and clean up the connection points
	for point in connection_points:
		if point.joint == joint:
			point.disconnect_joint()
	
	# Queue the joint for deletion
	if is_instance_valid(joint):
		joint.queue_free()
	
	# Emit break signal
	connection_broken.emit(joint)

func disconnect_all():
	# Create a copy of keys to avoid modification during iteration
	var joints = joint_connected_blocks.keys()
	for joint in joints:
		if is_instance_valid(joint) and not joint.is_queued_for_deletion():
			disconnect_joint(joint)
	
	# 断开 TurretConnector 连接
	for connector in rigidbody_connectors:
		if connector.connected_to:
			connector.disconnect_connection()
	
	# Clear any remaining connections
	joint_connected_blocks.clear()

## Query Methods
func get_available_connection_points() -> Array[Connector]:
	return connection_points.filter(
		func(point): return not point.connected_to
	) if connection_points else []

func get_available_rigidbody_connectors() -> Array[TurretConnector]:
	return rigidbody_connectors.filter(
		func(connector): return not connector.connected_to
	) if rigidbody_connectors else []

func get_all_connectors() -> Array:
	var all_connectors = []
	all_connectors.append_array(connection_points)
	all_connectors.append_array(rigidbody_connectors)
	return all_connectors

func get_available_connectors() -> Array:
	var available = []
	
	# Connectors
	for point in connection_points:
		if not point.connected_to and point.is_connection_enabled:
			available.append(point)
	
	# TurretConnectors  
	for connector in rigidbody_connectors:
		if not connector.connected_to and connector.is_connection_enabled:
			available.append(connector)
	
	return available

func get_connected_points() -> Array[Connector]:
	return connection_points.filter(
		func(point): return point.connected_to
	) if connection_points else []

func get_connected_rigidbody_connectors() -> Array[TurretConnector]:
	return rigidbody_connectors.filter(
		func(connector): return connector.connected_to
	) if rigidbody_connectors else []

func get_connection_point_by_name(pointname: String) -> Connector:
	if connection_points:
		for point in connection_points:
			if point.name == pointname:
				return point
	return null

func get_rigidbody_connector_by_name(connectorname: String) -> TurretConnector:
	if rigidbody_connectors:
		for connector in rigidbody_connectors:
			if connector.name == connectorname:
				return connector
	return null

func get_joint_connected_blocks() -> Array[Block]:
	return joint_connected_blocks.values()

func get_block_connected_by_joint(joint: Joint2D) -> Block:
	return joint_connected_blocks.get(joint)

## Helper Methods
func find_parent_block() -> Block:
	return self

func _on_connection_established(_from: Connector, to: Connector, _joint: Joint2D):
	var other_block = to.find_parent_block()
	if other_block and not connected_blocks.has(other_block):
		connected_blocks.append(other_block)

func _on_connection_broken(joint: Joint2D):
	var other_block = joint_connected_blocks.get(joint)
	if other_block and connected_blocks.has(other_block):
		connected_blocks.erase(other_block)

func set_connection_enabled(enabled: bool, keep_existing_joints: bool = true):
	for point in connection_points:
		# 保存当前连接状态
		var was_connected = point.is_joint_active()
		
		# 设置启用状态
		point.set_connection_enabled(enabled, keep_existing_joints)
		
		# 恢复连接状态（如果需要）
		if was_connected and keep_existing_joints and not enabled:
			# 获取连接的另一个点
			var other_point = point.connected_to
			if other_point and is_instance_valid(other_point):
				# 重新建立连接（但不物理断开）
				point.connected_to = other_point
				other_point.connected_to = point
	
	# 设置 TurretConnector 的启用状态
	for connector in rigidbody_connectors:
		connector.set_connection_enabled(enabled)
	
	queue_redraw()

func get_connection_point_by_index(index: int) -> Connector:
	var available_points = get_available_connection_points()
	if index >= 0 and index < available_points.size():
		return available_points[index]
	return null

func attach_to_staticbody(rigidbody: StaticBody2D, connector: TurretConnector = null, maintain_rotation: bool = true) -> TurretConnectorJoint:
	var connect_pos = connector.position if connector else Vector2.ZERO
	return TurretConnectorJoint.connect_to_staticbody(self, rigidbody, connect_pos, rigidbody.joint.node_a)

# 断开所有与RigidBody的连接
func detach_from_rigidbodies():
	var joints_to_remove = []
	for joint in joint_connected_blocks:
		if joint is TurretConnectorJoint:
			joints_to_remove.append(joint)
	
	for joint in joints_to_remove:
		if joint is TurretConnectorJoint:
			joint.break_connection()

# 检查是否连接到某个RigidBody
func is_attached_to_rigidbody(rigidbody: RigidBody2D = null) -> bool:
	if rigidbody:
		return joint_connected_blocks.values().has(rigidbody)
	else:
		for connected in joint_connected_blocks.values():
			if connected is RigidBody2D:
				return true
	return false

# 获取所有连接的RigidBody
func get_attached_rigidbodies() -> Array[RigidBody2D]:
	var rigidbodies: Array[RigidBody2D] = []
	for connected in joint_connected_blocks.values():
		if connected is RigidBody2D:
			rigidbodies.append(connected)
	return rigidbodies

# 获取所有TurretConnector
func get_rigidbody_connectors() -> Array[TurretConnector]:
	return rigidbody_connectors.duplicate()

# 统一的断开所有连接的方法
func disconnect_all_connections():
	# 断开 Connector 连接
	var joints = joint_connected_blocks.keys()
	for joint in joints:
		if is_instance_valid(joint) and not joint.is_queued_for_deletion():
			disconnect_joint(joint)
	
	# 断开 TurretConnector 连接
	for connector in rigidbody_connectors:
		if connector.connected_to:
			connector.disconnect_connection()
	
	joint_connected_blocks.clear()

# 获取块的实际重心位置（考虑偏移和旋转）
func get_actual_center_of_mass(geometric_center: Vector2) -> Vector2:
	if not functioning:
		return geometric_center
	
	# 计算考虑旋转后的偏移
	var rotation_rad = deg_to_rad(base_rotation_degree)
	var rotated_offset = center_of_mass_offset.rotated(rotation_rad)
	
	return geometric_center + rotated_offset
