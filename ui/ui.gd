class_name UI
extends CanvasLayer

@onready var HUD:Control = $Hud
@onready var tooltip:Panel = $Tooltip
@onready var minimap:FloatingPanel = $Minimap
@onready var settings_panel:FloatingPanel = $Settingspanel
@onready var vehicle_editor:Control = $VehicleEditor
@onready var building_editor:Control = $BuildingEditor
@onready var tankpanel:FloatingPanel = $Tankpanel

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		settings_panel.visible = !settings_panel.visible
