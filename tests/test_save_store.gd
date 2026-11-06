extends SceneTree
## Unit coverage for core/save_store.gd: atomic write, .bak rotation and fallback.

const SaveStore = preload("res://core/save_store.gd")

var checks := 0
var failures: Array[String] = []
var path := "user://save_store_test/save.json"


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var target := ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
	var directory := ProjectSettings.globalize_path(path).get_base_dir()
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)


func run() -> void:
	_cleanup()
	var first := {"save_version": 1, "content_version": "1", "state": {"hp": 1}}
	var written: Dictionary = SaveStore.write(path, first)
	check(written.ok, "first write succeeds")
	check(FileAccess.file_exists(ProjectSettings.globalize_path(path)), "live save exists")
	check(not FileAccess.file_exists(ProjectSettings.globalize_path(path + ".bak")), "no backup before second write")

	var second := {"save_version": 1, "content_version": "1", "state": {"hp": 2}}
	written = SaveStore.write(path, second)
	check(written.ok, "second write succeeds")
	var live = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(path)))
	check(is_equal_approx(float(live.state.hp), 2.0), "live save holds newest state")
	var backup = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(path + ".bak")))
	check(is_equal_approx(float(backup.state.hp), 1.0), "backup holds previous state")

	var accept_all := func(value): return value is Dictionary and value.get("save_version") == 1
	var loaded: Dictionary = SaveStore.load_envelope(path, accept_all)
	check(loaded.ok and not loaded.from_backup, "load reads live save")
	check(int(loaded.value.state.hp) == 2, "load returns live state")

	# Corrupt the live file: the validator rejects it and the .bak wins.
	var live_path := ProjectSettings.globalize_path(path)
	var file := FileAccess.open(live_path, FileAccess.WRITE)
	file.store_string("{ broken")
	file.close()
	loaded = SaveStore.load_envelope(path, accept_all)
	check(loaded.ok and loaded.from_backup, "load falls back to backup")
	check(int(loaded.value.state.hp) == 1, "fallback returns previous state")

	# Reject everything: no usable envelope and a user-facing error.
	var reject_all := func(_value): return false
	loaded = SaveStore.load_envelope(path, reject_all)
	check(not loaded.ok and str(loaded.error).contains("存档损坏"), "invalid save reports an error")

	# A missing path is not an error for memory-only engines.
	var missing: Dictionary = SaveStore.load_envelope("", accept_all)
	check(not missing.ok and str(missing.error).is_empty(), "empty path is a quiet miss")

	_cleanup()
	print("SAVE_STORE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
