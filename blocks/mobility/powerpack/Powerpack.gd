class_name PowerPack
extends Block

@export var max_power : float = 100.0
@export var shaft_port : Vector2i = Vector2i.ZERO

# Each dictionary is one alternative recipe.
# Values are consumption rates:
# - liquid: Litre per second
# - solid: units per second (consumed from internal buffer)
@export var fuel_choices: Array[Dictionary] = [{"petroleum": 1.0}]

var is_running: bool = false
var power_output : float = 0.0
var power_target : float = 0.0
var efficiency : float = power_output / max_power
var current_fuel : Dictionary = {}
var solid_fuel_buffer: Dictionary = {}    # item_name -> buffered solid amount


func _physics_process(delta: float) -> void:
	if vehicle == null:
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
	for recipe in fuel_choices:
		var split := preprocess_recipe(recipe, delta)
		var liquid_requests: Dictionary = split["liquid_requests"]
		var solid_needs: Dictionary = split["solid_needs"]
		var solid_requests: Dictionary = split["solid_requests"]
		
		var liquids_ok := true
		var solids_ok := true
		
		if not liquid_requests.is_empty():
			liquids_ok = vehicle.fluid_system.can_supply_liquids(self, liquid_requests)
		if not solid_requests.is_empty():
			solids_ok = vehicle.supply_system.can_supply_items(self, solid_requests)
		
		if not liquids_ok or not solids_ok:
			print("INSUFFICIENT FUEL")
			continue
		
		var liquids_taken := true
		var solids_taken := true
		
		if not liquid_requests.is_empty():
			liquids_taken = vehicle.fluid_system.supply_liquids(self, liquid_requests)
		if not solid_requests.is_empty():
			solids_taken = vehicle.supply_system.supply_items(self, solid_requests)
		
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


func preprocess_recipe(recipe: Dictionary, delta: float) -> Dictionary:
	var liquid_requests := {}
	var solid_needs := {}
	var solid_requests := {}
	
	for item in recipe.keys():
		var item_data = ItemDB.get_item(item)
		if item_data.is_empty():
			continue
		
		var rate := float(recipe[item])
		if item_data["type"] == "liquid":
			liquid_requests[item] = rate * delta * efficiency
		elif item_data["type"] == "solid":
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
