extends RefCounted
## Deterministic random streams, extracted verbatim from core/game_engine.gd.
## Engine counterparts: STREAMS, _seed_streams(), _sync_rng(), _restore_rng(),
## _random_int() and _shuffle(). No engine, scene or save-file dependency.

const STREAMS = ["map", "battle", "loot", "event"]
const STREAM_SALT = 104729

var _seed: int = 0
var _rng: Dictionary = {}
var _snapshot: Dictionary = {}


func seed_with(seed_value: int) -> void:
	_seed = seed_value
	_rng.clear()
	_snapshot.clear()
	for i in range(STREAMS.size()):
		var generator = RandomNumberGenerator.new()
		generator.seed = seed_value + (i + 1) * STREAM_SALT
		_rng[STREAMS[i]] = generator
	_sync()


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func restore(seed_value: int, snapshot: Dictionary) -> void:
	_seed = seed_value
	_rng.clear()
	_snapshot.clear()
	for key in STREAMS:
		var generator = RandomNumberGenerator.new()
		var entry = snapshot.get(key, {})
		if not entry is Dictionary:
			entry = {}
		generator.seed = int(entry.get("seed", str(seed_value + (STREAMS.find(key) + 1) * STREAM_SALT)))
		if entry.has("state"):
			generator.state = int(entry.state)
		_rng[key] = generator
		_snapshot[key] = {"seed": str(generator.seed), "state": str(generator.state)}


func randi_range(stream: String, low: int, high: int) -> int:
	if not _rng.has(stream):
		restore(_seed, _snapshot.duplicate(true))
	var value: int = _rng[stream].randi_range(low, high)
	_snapshot[stream] = {"seed": str(_rng[stream].seed), "state": str(_rng[stream].state)}
	return value


func shuffle(items: Array, stream: String) -> void:
	for i in range(items.size() - 1, 0, -1):
		var other = self.randi_range(stream, 0, i)
		var temporary = items[i]
		items[i] = items[other]
		items[other] = temporary


func clear() -> void:
	_seed = 0
	_rng.clear()
	_snapshot.clear()


func has_stream(stream: String) -> bool:
	return _rng.has(stream)


func _sync() -> void:
	_snapshot.clear()
	for key in _rng:
		_snapshot[key] = {"seed": str(_rng[key].seed), "state": str(_rng[key].state)}
