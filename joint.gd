extends Node2D

@export var body_a: RigidBody2D
@export var body_b: RigidBody2D

var initial_offset: Vector2
var initial_rotation_offset: float

func _ready():
	if body_a and body_b:
		# 记录初始相对位置和旋转
		initial_offset = body_a.global_position.direction_to(body_b.global_position)
		initial_rotation_offset = body_b.global_rotation - body_a.global_rotation
		
		# 冻结第二个物体的物理
		body_b.freeze = true

func _physics_process(delta):
	if body_a and body_b:
		# 强制第二个物体跟随第一个物体
		body_b.global_position = body_a.global_position + initial_offset.rotated(body_a.global_rotation)
		body_b.global_rotation = body_a.global_rotation + initial_rotation_offset
