class_name BlockPinJoint2D
extends PinJoint2D

@export var connection_strength: float = 1.0
@export var lock_rotation: bool = true
@export var maintain_position: bool = true

var block: Block
var target_body: RigidBody2D
var initial_global_position: Vector2

func _ready():
	setup_joint()

func setup_joint():
	softness = 0.1
	bias = 0.8
	disable_collision = true

func setup(block_node: Block, target: RigidBody2D, connect_pos: Vector2 = Vector2.ZERO):
	block = block_node
	target_body = target
	
	if maintain_position:
		initial_global_position = block.global_position
	
	node_a = block.get_path()
	node_b = target.get_path()
	position = connect_pos
	
	if lock_rotation:
		block.rotation = target.rotation

func _physics_process(delta):
	if not is_instance_valid(block) or not is_instance_valid(target_body):
		queue_free()
		return
	
	if maintain_position:
		maintain_block_position()
	
	if lock_rotation:
		block.global_rotation = target_body.global_rotation

func maintain_block_position():
	var position_diff = initial_global_position - block.global_position
	if position_diff.length() > 1.0:
		var correction_force = position_diff * 100.0 * connection_strength
		block.apply_central_force(correction_force)

func break_connection():
	if block and block.joint_connected_blocks.has(self):
		block.joint_connected_blocks.erase(self)
	queue_free()

static func connect_to_rigidbody(block: Block, rigidbody: RigidBody2D, connect_pos: Vector2 = Vector2.ZERO, lock_rot: bool = true, maintain_pos: bool = true) -> BlockPinJoint2D:
	var joint = BlockPinJoint2D.new()
	joint.lock_rotation = lock_rot
	joint.maintain_position = maintain_pos
	joint.setup(block, rigidbody, connect_pos)
	block.add_child(joint)
	block.joint_connected_blocks[joint] = rigidbody
	return joint
