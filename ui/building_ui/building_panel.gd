class_name BuildingPanel
extends Panel

var building: Building
var world_blocks: WorldBlockLayer
var selected_cell := WorldBlockLayer.INVALID_CELL

@onready var building_name_input: LineEdit = $BuildingName
@onready var building_info_label: RichTextLabel = $BuildingInfo


func _ready() -> void:
	hide()


func open_for_building(
	new_building: Building,
	new_world_blocks: WorldBlockLayer,
	cell: Vector2i
) -> void:
	_disconnect_world_layer()
	building = new_building
	world_blocks = new_world_blocks
	selected_cell = cell
	if world_blocks != null:
		world_blocks.buildings_rebuilt.connect(_on_buildings_rebuilt)
	refresh_information()
	show()
	move_to_front()


func close_panel() -> void:
	hide()
	_disconnect_world_layer()
	building = null
	world_blocks = null
	selected_cell = WorldBlockLayer.INVALID_CELL


func is_building_selected(candidate: Building) -> bool:
	return visible and building != null and building == candidate


func refresh_information() -> void:
	if building == null:
		building_name_input.text = "No building selected"
		building_info_label.text = (
			"Weight: --\n"
			+ "Blocks: --\n"
			+ "Occupied cells: --\n"
			+ "Functional blocks: --\n"
			+ "Owner: --"
		)
		return
	building_name_input.text = building.building_name
	building_info_label.text = (
		"Weight: %.1f t\n" % building.get_total_mass()
		+ "Blocks: %d\n" % building.block_anchors.size()
		+ "Occupied cells: %d\n" % building.occupied_cells.size()
		+ "Functional blocks: %d\n" % (
			building.functional_blocks.size()
		)
		+ "Owner: %s" % String(building.owner_id)
	)


func _on_buildings_rebuilt(_rebuilt: Array[Building]) -> void:
	if world_blocks == null:
		close_panel()
		return
	var current := world_blocks.get_building_at(selected_cell)
	if current == null:
		close_panel()
		return
	building = current
	refresh_information()


func _disconnect_world_layer() -> void:
	if (
		world_blocks != null
		and world_blocks.buildings_rebuilt.is_connected(
			_on_buildings_rebuilt
		)
	):
		world_blocks.buildings_rebuilt.disconnect(_on_buildings_rebuilt)


func _on_close_button_pressed() -> void:
	close_panel()
