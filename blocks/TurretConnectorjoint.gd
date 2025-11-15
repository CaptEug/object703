class_name TurretConnectorJoint
extends PinJoint2D

@export var connection_strength: float = 1.0
@export var lock_rotation: bool = true
@export var maintain_position: bool = true
@export var rotation_stiffness: float = 1.0 
@export var rotation_damping: float = 2.0  

var block: Block
var target_body: RigidBody2D
var initial_global_position: Vector2
var connector: TurretConnector

func _ready():
	setup_joint()

func setup_joint():
	softness = 0.01
	bias = 0.5
	disable_collision = true

func setup(block_node: Block, target: RigidBody2D, connector_ref: TurretConnector):
	block = block_node
	target_body = target
	connector = connector_ref
	
	if maintain_position:
		initial_global_position = block.global_position
	
	node_a = block.get_path()
	node_b = target.get_path()
	
	var local_connect_pos = block.to_local(connector.global_position)
	position = local_connect_pos
	
	if lock_rotation:
		block.rotation = target.rotation + deg_to_rad(block.base_rotation_degree)

func _physics_process(delta):
	if not is_instance_valid(block) or not is_instance_valid(target_body):
		break_connection()
		return
	
	if lock_rotation and is_instance_valid(target_body):
		apply_rotation_constraint(delta)

func apply_rotation_constraint(delta: float):
	var body_rid = block.get_rid()
	var body_state = PhysicsServer2D.body_get_direct_state(body_rid)
	var inverse_inertia = body_state.inverse_inertia
	var actual_inertia = 1.0 / inverse_inertia if inverse_inertia > 0 else 0.0
	
	if actual_inertia <= 0:
		return
	
	var target_rotation = target_body.global_rotation + deg_to_rad(block.base_rotation_degree)
	var rotation_diff = wrapf(target_rotation - block.global_rotation, -PI, PI)
	
	if abs(rotation_diff) < 0.001:
		return
	
	var target_angular_velocity = target_body.angular_velocity
	var angular_velocity_diff = target_angular_velocity - block.angular_velocity
	
	var restoration_torque = rotation_diff * rotation_stiffness * 1000.0 * actual_inertia
	var damping_torque = angular_velocity_diff * rotation_damping * actual_inertia * 10
	var total_torque = restoration_torque + damping_torque
	
	block.apply_torque(total_torque)

func break_connection():
	if block and block.joint_connected_blocks.has(self):
		block.joint_connected_blocks.erase(self)
	
	if connector and is_instance_valid(connector):
		connector.disconnect_connection()
	
	queue_free()

static func connect_to_rigidbody(block: Block, rigidbody: RigidBody2D, connector_ref: TurretConnector, node_a_path: NodePath, lock_rot: bool = true, maintain_pos: bool = true) -> TurretConnectorJoint:
	var joint = TurretConnectorJoint.new()
	joint.lock_rotation = lock_rot
	joint.maintain_position = maintain_pos
	joint.setup(block, rigidbody, connector_ref)
	block.add_child(joint)
	
	var turretring = rigidbody.get_node(node_a_path)
	if turretring is TurretRing:
		if not block.joint_connected_blocks.has(turretring):
			block.joint_connected_blocks[joint] = turretring
		if not turretring.joint_connected_blocks.has(block):
			turretring.joint_connected_blocks[joint] = block
	
	return joint
