class_name TurretConnectorJoint
extends PinJoint2D

@export var connection_strength: float = 1.0
@export var lock_rotation: bool = true
@export var maintain_position: bool = true
@export var rotation_stiffness: float = 1000
@export var rotation_damping: float = 200

var block: Block
var target_body: StaticBody2D
var initial_global_position: Vector2
var connector: TurretConnector
var initial_distance: float = 0.0
var old_v

func _ready():
	setup_joint()

func setup_joint():
	softness = 0.01
	bias = 1
	disable_collision = true

func setup(block_node: Block, target: StaticBody2D, connector_ref: TurretConnector):
	block = block_node
	target_body = target
	connector = connector_ref
	
	# 设置节点路径
	node_a = block.get_path()
	node_b = target.get_path()
	
	# 计算连接点在target本地坐标系中的位置
	var global_connect_pos = connector.global_position
	position = target.to_local(global_connect_pos)
	
	if lock_rotation:
		block.rotation = target.rotation + deg_to_rad(block.base_rotation_degree)

func _physics_process(delta):
	if not is_instance_valid(block) or not is_instance_valid(target_body):
		break_connection()
		return
	
	if lock_rotation and is_instance_valid(target_body):
		apply_rotation_constraint(delta)
	
	if not check_connection_strength():
		return

func apply_rotation_constraint(delta: float):
	if not is_instance_valid(block):
		return
	var body_rid = block.get_rid()
	if not body_rid.is_valid():
		return
	var body_state = PhysicsServer2D.body_get_direct_state(body_rid)
	if body_state == null:
		return
	var inverse_inertia = body_state.inverse_inertia
	var actual_inertia = 1.0 / inverse_inertia if inverse_inertia > 0 else 0.0
	
	if actual_inertia <= 0:
		return
	
	var target_rotation = target_body.global_rotation + deg_to_rad(block.base_rotation_degree)
	var rotation_diff = wrapf(target_rotation - block.global_rotation, -PI, PI)
	if abs(rotation_diff) < 0.001:
		return
	
	var target_angular_velocity = target_body.get_parent().angular_velocity
	var angular_velocity_diff = target_angular_velocity - block.angular_velocity
	
	var restoration_torque = rotation_diff * rotation_stiffness * actual_inertia
	var damping_torque = angular_velocity_diff * rotation_damping * actual_inertia 
	var total_torque = restoration_torque + damping_torque
	
	block.apply_torque(total_torque / 10)


func check_connection_strength() -> bool:
	if not maintain_position or initial_distance <= 0:
		return true
	
	var current_distance = block.global_position.distance_to(target_body.global_position)
	var stretch_ratio = current_distance / initial_distance
	
	if stretch_ratio > (1.0 + connection_strength * 0.5):
		print("连接断裂! 拉伸比例: ", stretch_ratio)
		break_connection()
		return false
	
	return true

func break_connection():
	if block and block.joint_connected_blocks.has(self):
		block.joint_connected_blocks.erase(self)
	
	if connector and is_instance_valid(connector):
		connector.disconnect_connection()
	
	queue_free()

# 保持原有参数不变的创建函数
static func connect_to_staticbody(block: Block, staticbody: StaticBody2D, connector_ref: TurretConnector, turret_ring: TurretRing, lock_rot: bool = true, maintain_pos: bool = true) -> TurretConnectorJoint:
	var joint = TurretConnectorJoint.new()
	joint.lock_rotation = lock_rot
	joint.maintain_position = maintain_pos
	## 先设置所有属性，再添加为子节点
	joint.node_a = block.get_path()
	joint.node_b = staticbody.get_path()
	joint.setup(block, staticbody, connector_ref)
	
	# 最后添加为子节点
	staticbody.add_child(joint)
	
	# 保持原有的连接关系管理
	if turret_ring is TurretRing:
		if not block.joint_connected_blocks.has(turret_ring):
			block.joint_connected_blocks[joint] = turret_ring
		if not turret_ring.joint_connected_blocks.has(block):
			turret_ring.joint_connected_blocks[joint] = block
	
	return joint
