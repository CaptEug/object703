class_name WindowBase

extends Control

signal request_close

@export var modal := false
@export var close_on_bg_click := false

func open(data) -> void:
	visible = true
	on_open(data)

func close() -> void:
	on_close()
	visible = false
	emit_signal("request_close")

func on_open(data):
	pass

func on_close():
	pass
