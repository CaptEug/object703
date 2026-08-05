class_name BlockDamage
extends RefCounted

const DESTROYED_EPSILON := 0.001


static func miss() -> Dictionary:
	return {
		"hit": false,
		"destroyed": false,
		"hp_before": 0.0,
		"hp_after": 0.0,
		"damage_applied": 0.0,
		"damage_consumed": 0.0,
	}


static func apply_to_host(
	host: Object,
	cell: Vector2i,
	amount: float,
	damage_type: StringName
) -> Dictionary:
	if (
		not is_instance_valid(host)
		or not host.has_method("get_block_damage_state")
		or not host.has_method("commit_block_damage")
	):
		return miss()
	var state_value: Variant = host.call(
		"get_block_damage_state",
		cell
	)
	if not state_value is Dictionary:
		return miss()
	var state := state_value as Dictionary
	if state.is_empty():
		return miss()
	var result := calculate(
		int(state.get("block_id", BlockDB.INVALID_BLOCK_ID)),
		float(state.get("hp", 0.0)),
		amount,
		damage_type
	)
	if result["hit"]:
		host.call("commit_block_damage", state, result)
	return result


static func calculate(
	block_id: int,
	current_hp: float,
	amount: float,
	damage_type: StringName
) -> Dictionary:
	if not BlockDB.has_block(block_id) or amount <= 0.0:
		return miss()

	var hp_before := maxf(current_hp, 0.0)
	var multiplier := BlockDB.get_damage_multiplier(
		block_id,
		damage_type
	)
	var result := {
		"hit": true,
		"destroyed": false,
		"hp_before": hp_before,
		"hp_after": hp_before,
		"damage_applied": 0.0,
		"damage_consumed": 0.0,
	}

	# A zero multiplier is impenetrable to this damage type. The hit consumes
	# the remaining attack without reducing HP.
	if multiplier <= 0.0:
		result["damage_consumed"] = amount
		return result

	var damage_applied := minf(amount * multiplier, hp_before)
	var damage_consumed := minf(amount, hp_before / multiplier)
	var hp_after := maxf(hp_before - damage_applied, 0.0)
	result["hp_after"] = hp_after
	result["damage_applied"] = damage_applied
	result["damage_consumed"] = damage_consumed
	result["destroyed"] = hp_after <= DESTROYED_EPSILON
	return result
