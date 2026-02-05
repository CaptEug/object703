class_name VehicleManager
extends Node2D

func get_vehicle_save_data() -> Dictionary:
	var save_data := {}
	
	for child in get_children():
		if child is Vehicle:
			var vehicle: Vehicle = child
			save_data[vehicle.vehicle_name] = get_single_vehicle_data(vehicle)
	
	return save_data

func get_single_vehicle_data(vehicle: Vehicle) -> Dictionary:
	if not is_instance_valid(vehicle) or vehicle.destroyed:
		return {}
	
	var blueprint_data := {
		"name": vehicle.vehicle_name,
		"vehicle_size": [vehicle.vehicle_size.x, vehicle.vehicle_size.y],
		"rotation": [get_vehicle_rotation(vehicle)],
		"center_of_mass": get_center_of_mass_array(vehicle),
		"blocks": {}
	}
	
	var block_counter = 1
	for block in vehicle.blocks:
		if not is_instance_valid(block):
			continue
		
		var block_data = get_block_data_for_save(block, vehicle)
		if block_data:
			blueprint_data["blocks"][str(block_counter)] = block_data
			block_counter += 1
	
	return blueprint_data

func get_vehicle_rotation(vehicle: Vehicle) -> float:
	if vehicle.grid.is_empty():
		return 0.0
	
	var first_grid_pos = vehicle.grid.keys()[0]
	var first_block_data = vehicle.grid[first_grid_pos]
	var first_block = first_block_data["block"]
	
	if not is_instance_valid(first_block):
		return 0.0
	
	var block_global_rotation_deg = rad_to_deg(first_block.global_rotation)
	var relative_rotation = block_global_rotation_deg - first_block.base_rotation_degree
	return fmod(relative_rotation + 360, 360)

func get_center_of_mass_array(vehicle: Vehicle) -> Array:
	var com = vehicle.calculate_center_of_mass()
	return [com.x, com.y]

func get_block_data_for_save(block: Block, vehicle: Vehicle) -> Dictionary:
	var grid_positions = vehicle.get_block_grid(block)
	if grid_positions.is_empty():
		return {}
	
	var min_x = grid_positions[0].x
	var min_y = grid_positions[0].y
	for pos in grid_positions:
		min_x = min(min_x, pos.x)
		min_y = min(min_y, pos.y)
	
	var block_data = {
		"base_pos": [min_x, min_y],
		"name": block.block_name,
		"path": get_block_scene_path(block),
		"rotation": [block.base_rotation_degree],
		"current_hp": block.current_hp,
		"max_hp": block.max_hp
	}
	
	if block is TurretRing:
		var turret_grid = get_turret_grid_data(block)
		if turret_grid:
			block_data["turret_grid"] = turret_grid
	
	return block_data

func get_block_scene_path(block: Block) -> String:
	var block_name = block.block_name
	var type = "structual"
	
	if "track" in block_name.to_lower():
		type = "mobility"
	elif "cannon" in block_name.to_lower() or "gun" in block_name.to_lower():
		type = "firepower"
	elif "command" in block_name.to_lower():
		type = "command"
	elif "armor" in block_name.to_lower():
		type = "structual"
	elif "pump" in block_name.to_lower() or "smelter" in block_name.to_lower():
		type = "industrial"
	else:
		type = "auxiliary"
	
	return "res://blocks/%s/%s.tscn" % [type, block_name]

func get_turret_grid_data(turret_ring: TurretRing) -> Dictionary:
	if not is_instance_valid(turret_ring.turret_basket):
		return {"grid_size": [0, 0], "blocks": {}}
	
	var turret_grid = {"grid_size": [0, 0], "blocks": {}}
	var turret_blocks = []
	
	for child in turret_ring.turret_basket.get_children():
		if child is Block:
			turret_blocks.append(child)
	
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	var block_counter = 1
	
	for block in turret_blocks:
		if not is_instance_valid(block):
			continue
		
		var local_pos = block.position - turret_ring.position
		var grid_x = int(round(local_pos.x / Vehicle.GRID_SIZE))
		var grid_y = int(round(local_pos.y / Vehicle.GRID_SIZE))
		
		min_x = min(min_x, grid_x)
		min_y = min(min_y, grid_y)
		max_x = max(max_x, grid_x)
		max_y = max(max_y, grid_y)
		
		turret_grid["blocks"][str(block_counter)] = {
			"base_pos": [grid_x, grid_y],
			"name": block.block_name,
			"path": get_block_scene_path(block),
			"rotation": [block.base_rotation_degree],
			"current_hp": block.current_hp,
			"max_hp": block.max_hp
		}
		
		block_counter += 1
	
	if min_x != INF and max_x != -INF:
		var width = int(max_x - min_x + 1)
		var height = int(max_y - min_y + 1)
		turret_grid["grid_size"] = [width, height]
		
		if min_x != 0 or min_y != 0:
			for block_id in turret_grid["blocks"]:
				var block_data = turret_grid["blocks"][block_id]
				var pos = block_data["base_pos"]
				block_data["base_pos"] = [pos[0] - min_x, pos[1] - min_y]
	
	return turret_grid
