## Deterministic scripted input sequences for smoke tests.
##
## Keep this file dependency-free and deterministic.

extends RefCounted

const DriftInput = preload("res://shared/drift_input.gd")


static func inputs_for_tick(t: int) -> Dictionary:
	# Returns Dictionary[int, DriftInput]
	# Two-ship script: movement + turning + periodic firing.
	# NOTE: Must be deterministic and not use RNG/time.
	var tt: int = int(t)

	# Ship 1: accelerate in bursts, weave left/right, fire on a short cadence.
	var s1_thrust: int = 1 if (tt % 40) < 24 else 0
	var s1_turn: int = -1 if (tt % 50) < 25 else 1
	var s1_fire: bool = (tt % 6) == 0

	# Ship 2: alternate thrust, opposite weave, fire on a different cadence.
	var s2_thrust: int = 1 if (tt % 30) < 18 else 0
	var s2_turn: int = 1 if (tt % 44) < 22 else -1
	var s2_fire: bool = (tt % 7) == 2

	var di1 := DriftInput.new(s1_thrust, s1_turn, s1_fire, false, false, false)
	var di2 := DriftInput.new(s2_thrust, s2_turn, s2_fire, false, false, false)
	return {1: di1, 2: di2}
