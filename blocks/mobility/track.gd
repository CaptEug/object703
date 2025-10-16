class_name Track
extends Block

# 抽象属性 - 需要在子类中定义
var friction: float
var max_force: float


# 运行时状态
var state_force: Array = ["idle", 0.0]
var force_direction := Vector2.ZERO

func _ready():
	super._ready()
	set_state_force("idle", 0.0)
	

func set_state_force(new_state: String, force_value: float):
	"""设置状态和力值"""
	state_force = [new_state, clamp(force_value, -max_force, max_force)]
	update_force_direction()

func update_force_direction():
	"""更新力的方向"""
	force_direction = Vector2.UP.rotated(global_rotation)

func apply_track_force():
	"""应用力的抽象方法"""
	if state_force[0] == 'move':
		apply_impulse(force_direction * state_force[1])

func _physics_process(_delta):
	if not functioning:
		return
	apply_track_force()

func _on_received_state_force_signal(state_force_signal):
	"""处理状态力信号"""
	if state_force_signal is Array and state_force_signal.size() >= 2:
		set_state_force(state_force_signal[0], state_force_signal[1])
	elif state_force_signal is Dictionary:
		set_state_force(state_force_signal.get("state", ""), state_force_signal.get("force", 0))

func broke():
	super.broke()
	var vehicle = get_parent_vehicle()
	if vehicle is Vehicle:
		if vehicle.tracks.has(self):
			vehicle.tracks.erase(self)
			vehicle.calculate_balanced_forces()

# Sprite Update
func set_sprite_region():
	var front_vec = Vector2.UP.rotated(global_rotation)
	var dis_front = global_position.project(front_vec)
	var new_y := int(clamp(dis_front, 0, 16 * size.y))
