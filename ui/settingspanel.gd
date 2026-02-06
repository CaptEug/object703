extends FloatingPanel

@onready var status_label = $Status

func _ready() -> void:
	GameState.save_started.connect(_on_save_started)
	GameState.save_finished.connect(_on_save_finished)

func _on_save_started():
	status_label.text = "Saving..."
	status_label.visible = true

func _on_save_finished(success: bool):
	if success:
		status_label.text = "Game saved!"
	else:
		status_label.text = "Save failed"

func _on_save_button_pressed() -> void:
	GameState.save_game()

func _on_main_menu_button_pressed() -> void:
	GameState.to_mainmenu()

func _on_back_button_pressed() -> void:
	hide()
