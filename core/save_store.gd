extends RefCounted
## Atomic save envelope persistence shared by the rules engine and tests.
## A write never replaces the live save directly: it writes a temporary file,
## keeps the previous save as .bak, then renames the temporary file into place.
## Validation and state migration stay in the domain layer; this module only
## owns filesystem semantics and JSON parsing.

const JSON_INDENT := "\t"


static func write(path: String, envelope: Dictionary) -> Dictionary:
	if path.is_empty():
		return {"ok": true, "error": ""}
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(directory)
		if directory_error != OK:
			return {"ok": false, "error": "无法建立存档目录：%s" % error_string(directory_error)}
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入临时存档：%s" % error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(envelope, JSON_INDENT))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "error": "存档写入失败：%s" % error_string(write_error)}
	if FileAccess.file_exists(absolute):
		var previous := FileAccess.get_file_as_bytes(absolute)
		var backup := FileAccess.open(absolute + ".bak", FileAccess.WRITE)
		if backup == null:
			return {"ok": false, "error": "无法保留上一份存档。"}
		backup.store_buffer(previous)
		backup.flush()
		backup.close()
	var rename_error := DirAccess.rename_absolute(temporary, absolute)
	if rename_error != OK:
		return {"ok": false, "error": "无法提交存档：%s" % error_string(rename_error)}
	return {"ok": true, "error": ""}


## Loads the live save, then the .bak fallback. The validator receives the
## parsed envelope and returns true when its schema is usable.
static func load_envelope(path: String, validator: Callable) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "error": "", "path": "", "value": {}, "from_backup": false}
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if validator.is_valid() and not bool(validator.call(parsed)):
			continue
		return {"ok": true, "error": "", "path": candidate, "value": parsed, "from_backup": candidate.ends_with(".bak")}
	return {"ok": false, "error": "存档损坏或版本不兼容，原文件已保留；未自动覆盖。", "path": "", "value": {}, "from_backup": false}
