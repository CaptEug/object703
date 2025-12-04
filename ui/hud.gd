extends Control

@onready var camera = get_tree().current_scene.find_child("Camera2D") as Camera2D
@onready var UI = get_tree().current_scene.find_child("CanvasLayer") as CanvasLayer

var time:String = "00:00"

func _ready():
	pass

func _process(_delta):
	$Panel/Clock.text = time


# 创建新车辆
func create_new_vehicle():
	# 获取编辑器引用
	var editor = get_tree().current_scene.find_child("Editorui")
	if editor:
		if editor.has_method("create_new_vehicle"):
			editor.create_new_vehicle()


func _on_build_button_pressed():
	create_new_vehicle()


func _on_tank_dex_button_pressed():
	var tankdex = UI.find_child("TankDex") as FloatingPanel
	if tankdex:
		tankdex.visible = true
