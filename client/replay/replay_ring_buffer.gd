## Bounded replay ring buffer for client-side recording.
##
## Stores per-tick records with a minimal schema:
##   {"t": int, "inputs": Array}
##
## Determinism notes:
## - The ring buffer is deterministic given deterministic call order.
## - If `inputs` is shaped as `[[ship_id, payload], ...]`, the buffer will sort
##   by ship_id ascending to stabilize ordering.

class_name ReplayRingBuffer
extends RefCounted

var _capacity_ticks: int
var _tick_rate: int

# Fixed-size ring storage.
var _ticks: Array[int] = []
var _inputs: Array = [] # Array[Array]

# _write_idx always points to the next slot to be overwritten.
var _write_idx: int = 0
var _count: int = 0


func _init(capacity_ticks: int, tick_rate: int) -> void:
	_capacity_ticks = maxi(1, int(capacity_ticks))
	_tick_rate = maxi(1, int(tick_rate))

	_ticks.resize(_capacity_ticks)
	_inputs.resize(_capacity_ticks)
	for i in range(_capacity_ticks):
		_ticks[i] = 0
		_inputs[i] = []

	_write_idx = 0
	_count = 0


func push_tick(t: int, inputs: Array) -> void:
	# Store at the current write index and advance.
	_ticks[_write_idx] = int(t)
	_inputs[_write_idx] = _normalize_inputs(inputs)

	_write_idx = (_write_idx + 1) % _capacity_ticks
	if _count < _capacity_ticks:
		_count += 1


func clear() -> void:
	_write_idx = 0
	_count = 0
	for i in range(_capacity_ticks):
		_ticks[i] = 0
		_inputs[i] = []


func snapshot() -> Array:
	# Oldest -> newest in insertion order.
	var out: Array = []
	out.resize(_count)
	var start_idx: int = _oldest_index()
	for i in range(_count):
		var idx: int = (start_idx + i) % _capacity_ticks
		out[i] = {
			"t": int(_ticks[idx]),
			"inputs": _deep_copy_variant(_inputs[idx]),
		}
	return out


func seconds_covered() -> float:
	if _count <= 0:
		return 0.0
	var oldest_t: int = int(_ticks[_oldest_index()])
	var newest_t: int = int(_ticks[_newest_index()])
	# Inclusive tick span (works even if ticks are not perfectly contiguous).
	var span_ticks: int = maxi(1, newest_t - oldest_t + 1)
	return float(span_ticks) / float(_tick_rate)


func _oldest_index() -> int:
	# If buffer isn't full, oldest is 0. If full, oldest is the next write slot.
	if _count < _capacity_ticks:
		return 0
	return _write_idx


func _newest_index() -> int:
	if _count <= 0:
		return 0
	var idx: int = _write_idx - 1
	if idx < 0:
		idx += _capacity_ticks
	return idx


func _normalize_inputs(inputs: Array) -> Array:
	# Defensive deep copy so callers can't mutate stored records.
	#
	# Preferred deterministic encoding: Array of pairs [ship_id, payload].
	# If inputs matches this shape, sort by ship_id.
	var copied_any: Variant = _deep_copy_variant(inputs)
	if typeof(copied_any) != TYPE_ARRAY:
		return []
	var copied: Array = copied_any
	if copied.is_empty():
		return copied

	var all_pairs: bool = true
	for v in copied:
		if typeof(v) != TYPE_ARRAY:
			all_pairs = false
			break
		var pair: Array = v
		if pair.size() < 1:
			all_pairs = false
			break
		if not _is_intlike(pair[0]):
			all_pairs = false
			break

	if all_pairs:
		# Sort by ship_id ascending.
		copied.sort_custom(func(a: Variant, b: Variant) -> bool:
			var aa: Array = a
			var bb: Array = b
			return int(aa[0]) < int(bb[0])
		)

	return copied


static func _is_intlike(v: Variant) -> bool:
	var t := typeof(v)
	if t == TYPE_INT:
		return true
	if t == TYPE_FLOAT:
		var f: float = float(v)
		var i: int = int(f)
		return absf(f - float(i)) < 0.00001
	return false


static func _deep_copy_variant(v: Variant) -> Variant:
	# Godot's Array/Dictionary duplicate(true) handles deep copies of nested
	# arrays/dicts. Other values are returned as-is.
	var t := typeof(v)
	if t == TYPE_ARRAY:
		return (v as Array).duplicate(true)
	if t == TYPE_DICTIONARY:
		return (v as Dictionary).duplicate(true)
	return v
