# GlobalTimeManager.gd
extends Node

# 默认时间缩放为1.0（正常速度）
var time_scale: float = 1.0:
	set(value):
		time_scale = value
		# 当time_scale改变时，立即更新Engine的物理和空闲时间缩放。
		# 这会影响所有基于delta的计算。
		Engine.time_scale = value

# 可以添加一个函数来实现平滑的慢动作过渡，而不是瞬间切换
func set_time_scale_smoothly(target_scale: float, duration: float = 0.5):
	var tween = create_tween()
	tween.tween_property(self, "time_scale", target_scale, duration)
