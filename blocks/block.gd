class_name Block
extends RigidBody2D

## Basic Properties
var current_hp: float
var weight: float
var block_name: String
var type: String
var size: Vector2i
var parent_vehicle: Vehicle = null  
var _cached_icon: Texture2D
var neighbors := {}
var connected_blocks := []
var global_grid_pos := []
var mouse_inside: bool
var outline_tex: Texture
var rotation_to_parent = 0.0

## Connection System
@export var connection_point_script: Script
@export var auto_detect_connection_points := true
@export var manual_connection_points: Array[ConnectionPoint]
@export var is_movable_on_connection := true

var connection_points: Array[ConnectionPoint] = []
var joint_connected_blocks := {}  # Tracks which blocks are connected through which joints

## Signals
signal frame_post_drawn
signal connection_established(from: ConnectionPoint, to: ConnectionPoint, joint: Joint2D)
signal connection_broken(joint: Joint2D)

func _ready():
	# Initialize physics properties
	RenderingServer.frame_post_draw.connect(_emit_relay_signal)
	mass = weight
	
	# Initialize parent vehicle reference
	parent_vehicle = get_parent_vehicle()
	
	# Set up input signals
	input_pickable = true
	connect("input_event", Callable(self, "_on_input_event"))
	connect("mouse_entered", Callable(self, "_on_mouse_entered"))
	connect("mouse_exited", Callable(self, "_on_mouse_exited"))
	
	# Collect connection points
	collect_connection_points()
	
	# Validation
	if connection_points.is_empty():
		push_warning("Block '%s' has no connection points" % block_name)

func _process(delta):
	# 处理现有连接的维持
	for joint in joint_connected_blocks:
		if is_instance_valid(joint):
			var other_block = joint_connected_blocks[joint]
			if is_instance_valid(other_block):

				pass

## Physics and Drawing
func _emit_relay_signal():
	frame_post_drawn.emit()

## Input Handling
func _on_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var control_ui := get_tree().current_scene.find_child("CanvasLayer") as CanvasLayer
			if control_ui:
				var tank_panel := control_ui.find_child("Tankpanel") as Panel
				tank_panel.selected_vehicle = get_parent_vehicle()

func _on_mouse_entered():
	mouse_inside = true


func _on_mouse_exited():
	mouse_inside = false


func damage(amount:int):
	print(str(name)+' receive damage:'+str(amount))
	current_hp -= amount
	if current_hp <= 0:
		destroy()

func destroy():
	# Disconnect all joints before destroying
	disconnect_all()
	queue_free()
	if parent_vehicle:
		parent_vehicle.remove_block(self)

## Block Management
func get_icon_texture():
	var texture_blocks := find_child("Sprite2D") as Sprite2D
	return texture_blocks.texture

func get_parent_vehicle():
	parent_vehicle = get_parent() as Vehicle
	if parent_vehicle:
		if self in parent_vehicle.blocks:
			return parent_vehicle
	return null

## Neighbor and Connectivity System
func get_neighbors():
	neighbors.clear()
	if get_parent_vehicle():
		var grid = get_parent_vehicle().grid
		var grid_pos = parent_vehicle.find_pos(grid, self)
		for x in size.x:
			for y in size.y:
				var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
				for dir in directions:
					var neighbor_pos = grid_pos + Vector2i(x, y) + dir
					if grid.has(neighbor_pos) and grid[neighbor_pos] != self:
						if is_instance_valid(grid[neighbor_pos]):
							var neighbor = grid[neighbor_pos]
							var neighbor_real_pos = parent_vehicle.find_pos(grid, neighbor)
							neighbors[neighbor_real_pos - grid_pos] = neighbor
	return neighbors

func get_all_connected_blocks() -> Array:
	get_neighbors()
	connected_blocks.clear()
	get_connected_blocks(self)
	return connected_blocks

func get_connected_blocks(block: Block):
	var nbrs = block.neighbors
	for neighbor in nbrs.values():
		if not connected_blocks.has(neighbor) and neighbor != self:
			connected_blocks.append(neighbor)
			get_connected_blocks(neighbor)

func check_connectivity():
	if self is Command:
		return
	if not get_all_connected_blocks().any(func(item): return item is Command):
		if get_parent_vehicle():
			parent_vehicle.remove_block(self)

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
					connection_points.append(node as ConnectionPoint)
		
		# Method 2: Find all ConnectionPoint nodes
		if connection_points.is_empty():
			var nodes = find_children("*", "ConnectionPoint", true, false)
			for node in nodes:
				connection_points.append(node as ConnectionPoint)

func request_connection(source: ConnectionPoint, target: ConnectionPoint):
	if not can_connect(source, target):
		return
	
	# Create the joint through the parent block
	var joint = create_joint_with(source, target)
	if joint:
		connection_established.emit(source, target, joint)

func can_connect(source: ConnectionPoint, target: ConnectionPoint) -> bool:
	var source_block = source.find_parent_block()
	var target_block = target.find_parent_block()
	
	return (
		source_block != null and
		target_block != null and
		source_block != target_block and
		source.can_connect_with(target)
	)


func create_joint_with(source: ConnectionPoint, target: ConnectionPoint, rigid_alignment: bool = false) -> Joint2D:
	if not source.is_connection_enabled or not target.is_connection_enabled:
		return null
	
	var target_block = target.find_parent_block()
	if not target_block:
		return null
	
	# 检查移动性
	if not self.is_movable_on_connection and not target_block.is_movable_on_connection:
		return null
	
	# 使用焊接关节保证严格对齐
	var joint = PinJoint2D.new()
	joint.node_a = get_path()
	joint.node_b = target_block.get_path()
	joint.position = source.position
	joint.disable_collision = false
	
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
		disconnect_joint(joint)
	
	# Clear any remaining connections
	joint_connected_blocks.clear()

## Query Methods
func get_available_connection_points() -> Array[ConnectionPoint]:
	return connection_points.filter(
		func(point): return not point.connected_to
	) if connection_points else []

func get_connected_points() -> Array[ConnectionPoint]:
	return connection_points.filter(
		func(point): return point.connected_to
	) if connection_points else []

func get_connection_point_by_name(name: String) -> ConnectionPoint:
	if connection_points:
		for point in connection_points:
			if point.name == name:
				return point
	return null

func get_joint_connected_blocks() -> Array[Block]:
	return joint_connected_blocks.values()

func get_block_connected_by_joint(joint: Joint2D) -> Block:
	return joint_connected_blocks.get(joint)

## Helper Methods
func find_parent_block() -> Block:
	return self

func _on_connection_established(from: ConnectionPoint, to: ConnectionPoint, joint: Joint2D):
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
	
	queue_redraw()
