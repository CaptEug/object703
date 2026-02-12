class_name Manufactory
extends Block

var connected_cargos: Array[Cargo]
var recipes: Array
		# a single recipe is
		#{
		#"inputs": {"item_id": amount},
		#"outputs": {"item_id": amount},
		#"production_time": int
		#},
var input_inv: Array[Dictionary] = []
var output_inv: Array[Dictionary] = []
var timer:Timer
var on:bool = true
var working:bool = false
var current_recipe:Dictionary
var panel:FloatingPanel
var manufactory_panel_path := "res://ui/manufactory/manufactory_panel.tscn"

func _ready():
	super._ready()
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)


func _process(delta):
	super._process(delta)
	find_all_connected_cargo()
	if on:
		var recipe = find_recipe()
		if recipe:
			produce(recipe)
		unload_products()


# UI realated 
func _on_input_event(_viewport, event, _shape_idx):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				open_manufactory_panel()

func open_manufactory_panel():
	if panel:
		panel.visible = true
		panel.move_to_front()
	else:
		var UI = GameState.current_gamescene.gameUI
		panel = load(manufactory_panel_path).instantiate()
		panel.manufactory = self
		UI.add_child(panel)
		while panel.any_overlap():
			panel.position += Vector2(32, 32)

# manufactory code
func find_recipe():
	for recipe in recipes:
		if recipe_can_run(recipe):
			return recipe

func recipe_can_run(recipe:Dictionary) -> bool:
	for item_id in recipe["inputs"]:
		if not has_material(item_id, recipe["inputs"][item_id]):
			return false
	return true

func has_material(item_id:String, amount:int):
	var total_amount_in_cargo:int
	for cargo in connected_cargos:
		total_amount_in_cargo += cargo.check_amount(item_id)
	return total_amount_in_cargo >= amount

func load_material(recipe:Dictionary):
	for item_id in recipe["inputs"]:
		var amount_needed = recipe["inputs"][item_id]
		for cargo in connected_cargos:
			if cargo.check_amount(item_id) >= amount_needed:
				cargo.take_item(item_id, amount_needed)
				amount_needed = 0
			else:
				cargo.take_item(item_id, cargo.check_amount(item_id))
				amount_needed -= cargo.check_amount(item_id)
			if amount_needed == 0:
				break
		
		var found:= false
		for item in input_inv:
			if item["id"] == item_id:
				item["count"] += recipe["inputs"][item_id]
				found = true
		if not found:
			var item = {"id":item_id, "count":recipe["inputs"][item_id]}
			input_inv.append(item)


func produce(recipe:Dictionary):
	if working:
		return
	load_material(recipe)
	print(input_inv)
	if not inputs_ready(recipe):
		timer.stop()
		working = false
		return
	working = true
	current_recipe = recipe
	timer.wait_time = recipe["production_time"]
	timer.start()

func inputs_ready(recipe:Dictionary) -> bool:
	if recipe == null or recipe.is_empty():
		return false  # recipe is invalid or empty → not ready
	for item_id in recipe["inputs"]:
		var found:= false
		for item in input_inv:
			if item["id"] == item_id and item["count"] >= recipe["inputs"][item_id]:
				found = true
				break
		if not found:
			return false
	return true

func _on_timer_timeout():
	consume_inputs(current_recipe)
	produce_outputs(current_recipe)
	working = false
	current_recipe = {}
	
	print(output_inv)


func consume_inputs(recipe:Dictionary):
	for item_id in recipe["inputs"]:
		var needed = recipe["inputs"][item_id]
		for item in input_inv:
			if item["id"] == item_id:
				var take = min(item["count"], needed)
				item["count"] -= take
				needed -= take
				if item["count"] == 0:
					input_inv.erase(item)
				if needed == 0:
					break

func produce_outputs(recipe:Dictionary):
	for item_id in recipe["outputs"]:
		var found := false
		var amount = recipe["outputs"][item_id]
		for item in output_inv:
			if item["id"] == item_id:
				item["count"] += amount
				found = true
				break
		if not found:
			output_inv.append({
		"id": item_id,
		"count": amount
	})

func unload_products():
	for item in output_inv:
		for cargo in connected_cargos:
			if cargo.can_accept_item(item["id"]):
				cargo.add_item(item["id"], item["count"])
				item["count"] -= item["count"]
				if item["count"] == 0:
					output_inv.erase(item)

func find_all_connected_cargo():
	connected_cargos.clear()
	for block in get_all_connected_blocks():
		if block is Cargo:
			connected_cargos.append(block)
	return connected_cargos
