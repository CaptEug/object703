extends Control

@onready var new_vehicle_build = $Panel/BuildButton
@onready var camera = get_tree().current_scene.find_child("Camera2D") as Camera2D

var time:String = "00:00"

func _ready():
	# 连接新建车辆按钮的信号
	new_vehicle_build.pressed.connect(_on_new_vehicle_build_pressed)

func _process(delta):
	$Panel/Clock.text = time

# 新建车辆按钮按下时的处理
func _on_new_vehicle_build_pressed():
	create_new_vehicle()

# 创建新车辆
func create_new_vehicle():
	# 获取编辑器引用
	var editor = get_tree().current_scene.find_child("Editorui")
	if editor:
		if editor.has_method("create_new_vehicle"):
			editor.create_new_vehicle()
