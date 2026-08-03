class_name PowerPack
extends Block

@export var max_power : float = 100.0
# Each dictionary is one alternative recipe.
# Values are consumption rates:
# - liquid: mass per second
# - mineral/material: units per second (consumed from internal buffer)
@export var fuel_choices: Array[Dictionary] = [{"petroleum": 1.0}]

var is_running: bool = false
var power_output : float = 0.0
var power_target : float = 0.0
var efficiency : float = power_output / max_power
var current_fuel : Dictionary = {}
var solid_fuel_buffer: Dictionary = {}    # item_name -> buffered solid amount


func has_information_panel() -> bool:
	return true


func get_save_state() -> Dictionary:
	var saved_buffer := {}
	for item_name: String in solid_fuel_buffer:
		var amount := maxf(float(solid_fuel_buffer[item_name]), 0.0)
		if amount > 0.0:
			saved_buffer[item_name] = amount
	return {"solid_fuel_buffer": saved_buffer}


func apply_save_state(state: Dictionary) -> void:
	solid_fuel_buffer.clear()
	var saved_buffer: Variant = state.get("solid_fuel_buffer")
	if not saved_buffer is Dictionary:
		return
	for item_value: Variant in saved_buffer:
		var item_name := str(item_value)
		var item_data := ItemDB.get_item_by_name(item_name)
		var amount := maxf(float(saved_buffer[item_value]), 0.0)
		if (
			amount > 0.0
			and not item_data.is_empty()
			and item_data.get("type", -1) != ItemDB.ItemType.LIQUID
			and ItemDB.has_subclass(
				item_name,
				ItemDB.ItemSubclass.FUEL
			)
		):
			solid_fuel_buffer[item_name] = amount


func _physics_process(delta: float) -> void:
	if get_assembly() == null:
		return
	
	# 1. set this frame's intended output first
	power_output = minf(power_target, max_power)
	
	# 2. update efficiency from THIS frame output
	efficiency = power_output / max_power
	
	# 3. consume fuel based on THIS frame output
	is_running = request_fuel(delta)
	
	# 4. if fuel failed, kill output
	if not is_running:
		power_output = 0.0
		current_fuel.clear()
	
	#print("engine on: " + str(is_running))
	#print("engIne target: " + str(power_target))
	#print("engIne output: " + str(power_output))


# Fuel Calculation

func request_fuel(delta: float) -> bool:
	var current_assembly := get_assembly()
	if current_assembly == null:
		return false
	for recipe in fuel_choices:
		var split := preprocess_recipe(recipe, delta)
		var liquid_requests: Dictionary = split["liquid_requests"]
		var solid_needs: Dictionary = split["solid_needs"]
		var solid_requests: Dictionary = split["solid_requests"]
		
		var liquids_ok := true
		var solids_ok := true
		
		if not liquid_requests.is_empty():
			liquids_ok = current_assembly.can_supply_liquids(
				self,
				liquid_requests
			)
		if not solid_requests.is_empty():
			solids_ok = _can_supply_items(
				current_assembly,
				solid_requests
			)
		
		if not liquids_ok or not solids_ok:
			continue
		
		var liquids_taken := true
		var solids_taken := true
		
		if not liquid_requests.is_empty():
			liquids_taken = current_assembly.supply_liquids(
				self,
				liquid_requests
			)
		if not solid_requests.is_empty():
			solids_taken = _supply_items(
				current_assembly,
				solid_requests
			)
		
		if not liquids_taken or not solids_taken:
			continue
		
		# add requested solids into internal buffer
		for item in solid_requests.keys():
			solid_fuel_buffer[item] = solid_fuel_buffer.get(item, 0.0) + int(solid_requests[item])
		
		# consume this frame's solid need from buffer
		for item in solid_needs.keys():
			var need: float = solid_needs[item]
			var have: float = solid_fuel_buffer.get(item, 0.0)
			solid_fuel_buffer[item] = have - need
		
		current_fuel = recipe.duplicate()
		return true
	
	return false


func _can_supply_items(
	current_assembly: BlockAssembly,
	requirements: Dictionary
) -> bool:
	for item_name: String in requirements:
		if not current_assembly.can_supply_item(
			self,
			item_name,
			int(requirements[item_name])
		):
			return false
	return true


func _supply_items(
	current_assembly: BlockAssembly,
	requirements: Dictionary
) -> bool:
	for item_name: String in requirements:
		if not current_assembly.supply_item(
			self,
			item_name,
			int(requirements[item_name])
		):
			return false
	return true


func preprocess_recipe(recipe: Dictionary, delta: float) -> Dictionary:
	var liquid_requests := {}
	var solid_needs := {}
	var solid_requests := {}
	
	for item in recipe.keys():
		var item_data = ItemDB.get_item_by_name(item)
		if item_data.is_empty():
			continue
		
		var rate := float(recipe[item])
		if item_data["type"] == ItemDB.ItemType.LIQUID:
			liquid_requests[item] = rate * delta * efficiency
		elif ItemDB.has_subclass(item, ItemDB.ItemSubclass.FUEL):
			var need: float = rate * delta * efficiency
			solid_needs[item] = need
			var buffered: float = solid_fuel_buffer.get(item, 0.0)
			if buffered < need:
				var shortage := need - buffered
				var units_to_request := int(ceil(shortage))
				if units_to_request > 0:
					solid_requests[item] = units_to_request
	
	return {
		"liquid_requests": liquid_requests,
		"solid_needs": solid_needs,
		"solid_requests": solid_requests
	}
