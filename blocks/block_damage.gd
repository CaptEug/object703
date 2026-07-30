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
