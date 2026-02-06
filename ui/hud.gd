extends Control

@onready var UI:CanvasLayer = get_parent()
@onready var gamescene:GameScene = UI.get_parent()


func _ready():
	pass

func _process(_delta):
	$Panel/Clock.text = get_clock_string(gamescene.game_time)


func get_clock_string(time) -> String:
	var cycle_duration = 600.0
	var total_minutes = (time / cycle_duration) * 24.0 * 60.0
	var hour = int(total_minutes / 60.0) % 24
	var minute = int(total_minutes) % 60
	return "%02d:%02d" % [hour, minute]

# 创建新车辆
func create_new_vehicle():
	# 获取编辑器引用
	var editor = UI.find_child("Editorui")
	if editor:
		if editor.has_method("create_new_vehicle"):
			editor.create_new_vehicle()


func _on_build_button_pressed():
	create_new_vehicle()


func _on_tank_dex_button_pressed():
	var tankdex = UI.find_child("TankDex", true, false) as FloatingPanel
	if tankdex:
		tankdex.visible = true
	else:
		tankdex = load("res://ui/tankdex.tscn").instantiate()
		UI.add_child(tankdex)


func _on_settings_button_pressed() -> void:
	UI.settings_panel.visible = true
