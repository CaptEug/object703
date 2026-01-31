class_name Track
extends Block

# 抽象属性 - 需要在子类中定义
var friction: float
var max_force: float

# 承重系统属性
var max_load: float = 5.0  
var current_load: float = 0.0  
var overload_damage: float = 0.0  
var overload_timer: float = 0.0  
var overloaded: bool = false 
var load_damage_rate: float = 2.0  
var is_moving: bool = false  # 新增：是否在运动中

@onready var track_sprite:= find_child("Sprite2D")
@onready var mask:= find_child("Mask")
var mask_up_path:String
var mask_down_path:String
var mask_single_path:String
var sprite_origin:Vector2
var track_scroll:float = 0.0
var whole_track:Array[Track] = []

# 运行时状态
var state_force:Array = ["idle", 0.0]
var force_direction:= Vector2.ZERO
var prev_position:Vector2


func _ready():
	super._ready()
	set_state_force("idle", 0.0)
	sprite_origin = track_sprite.texture.region.position
	prev_position = global_position
	

func set_state_force(new_state: String, force_value: float):
	"""设置状态和力值"""
	state_force = [new_state, clamp(force_value, -max_force, max_force)]
	
	# 更新运动状态
	is_moving = (new_state == 'move' and abs(force_value) > 0.1)
	
	update_force_direction()

func update_force_direction():
	"""更新力的方向"""
	force_direction = Vector2.UP.rotated(global_rotation)

func apply_track_force():
	"""应用力的抽象方法"""
	if state_force[0] == 'move' and not overloaded:
		apply_impulse(force_direction * state_force[1])

func _physics_process(delta):
	if not functioning:
		return
		
	# 只有在运动中才更新承重伤害系统
	if is_moving:
		update_overload_damage(delta)
	
	apply_track_force()
	update_track_sprite(delta)
	prev_position = global_position

func _on_received_state_force_signal(state_force_signal):
	"""处理状态力信号"""
	if state_force_signal is Array and state_force_signal.size() >= 2:
		set_state_force(state_force_signal[0], state_force_signal[1])
	elif state_force_signal is Dictionary:
		set_state_force(state_force_signal.get("state", ""), state_force_signal.get("force", 0))

func destroy():
	super.destroy()
	var vehicle = get_parent_vehicle()
	if vehicle is Vehicle:
		if vehicle.tracks.has(self):
			vehicle.tracks.erase(self)
			vehicle.calculate_balanced_forces()

func update_overload_damage(delta: float):
	"""更新承重伤害 - 只在运动中造成伤害"""
	if not functioning or not is_moving:
		return
		
	# 计算超载量
	var overload_amount = max(0.0, current_load - max_load)
	
	if overload_amount > 0:
		# 更新伤害计时器
		overload_timer += delta
		
		# 每5秒造成一次伤害
		if overload_timer >= 5.0:
			var damage = min(overload_amount * load_damage_rate, max_hp * 0.02)
			damage(int(damage))
			overload_timer = 0.0
			overload_damage += damage
		if overload_amount > 5.0:
			overloaded = true
	else:
		# 无超载时重置计时器
		overload_timer = 0.0

func set_current_load(load_amount: float):
	"""设置当前承重"""
	current_load = load_amount
	if current_load > max_load + 5.0:
		overloaded = true
	elif current_load <= max_load:
		overloaded = false

func get_load_status() -> Dictionary:
	"""获取承重状态"""
	return {
		"current_load": current_load,
		"max_load": max_load,
		"overload_amount": max(0.0, current_load - max_load),
		"overloaded": overloaded,
		"functioning": functioning and not overloaded,
		"is_moving": is_moving,
		"overload_timer": overload_timer
	}

func update_track_sprite(delta):
	#identify track edges
	if track_up_clear() and track_down_clear():
		mask.texture = load(mask_single_path)
	elif track_up_clear():
		mask.texture = load(mask_up_path)
	elif track_down_clear():
		mask.texture = load(mask_down_path)
	else:
		mask.texture = null
	
	var front_vec = Vector2.UP.rotated(global_rotation)
	var movement_vec = global_position - prev_position
	var forward_movement = movement_vec.dot(front_vec)
	
	# Accumulate scroll based on forward/backward movement
	track_scroll += forward_movement
	var total_scroll = 0.0
	for track in get_whole_track():
		total_scroll += track.track_scroll
	var synced_track_scroll = total_scroll / get_whole_track().size()
	
	# Wrap around texture region vertically
	var wrapped_y = wrapf(synced_track_scroll, 0, 16 * size.y)
	
	# Update the region's position
	track_sprite.texture.region.position = sprite_origin + Vector2(0, wrapped_y)

func get_whole_track():
	whole_track = [self]
	get_nearby_tracks(self)
	return whole_track

func get_nearby_tracks(track):
	for point in track.connection_points:
		if is_equal_approx(point.rotation, PI/2) or is_equal_approx(point.rotation, -PI/2):
			if point.connected_to:
				var blk = point.connected_to.parent_block as Block
				if blk is Track:
					if not whole_track.has(blk):
						whole_track.append(blk)
						get_nearby_tracks(blk)

func track_up_clear():
	for point in connection_points:
		if is_equal_approx(point.rotation, -PI/2):
			if not point.connected_to:
				return true
			else:
				return not point.connected_to.parent_block is Track
	return false

func track_down_clear():
	for point in connection_points:
		if is_equal_approx(point.rotation, PI/2):
			if not point.connected_to:
				return true
			else:
				return not point.connected_to.parent_block is Track
	return false
