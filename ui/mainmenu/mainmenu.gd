extends Control

@onready var mainbuttons := $VBoxContainer
@onready var worldpanel := $Worldpanel

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if mainmenue_is_blank():
		mainbuttons.show()
	

func mainmenue_is_blank() -> bool:
	for child in get_children():
		if child.visible:
			return false
	return true

func _on_start_game_pressed() -> void:
	worldpanel.visible = true
	mainbuttons.hide()
