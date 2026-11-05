extends Control
## Load no gameplay resources until the signed local update has been checked.

const UPDATE_DIR := "user://updates"
const MANIFEST_NAME := "update.json"
const PUBLIC_KEY := "res://data/update_public.pem"
const PRODUCT := "com.zebao.greyoath"
const BASE_PACK := "../Resources/灰誓.pck"
const MAX_ENVELOPE_BYTES := 16 * 1024
const MAX_PACK_BYTES := 512 * 1024 * 1024
const MAX_REVISION := 9007199254740991


func _ready() -> void:
	_start_game.call_deferred()


func _start_game() -> void:
	var base_version := str(ProjectSettings.get_setting("application/config/version"))
	var result := _mount_local_update(base_version)
	result.base_version = base_version
	result.revision = int(result.get("revision", 0))
	result.directory = UPDATE_DIR
	get_tree().set_meta("grey_oath_local_update", result)
	print("GREY_OATH_LOCAL_UPDATE ", JSON.stringify(result))
	if get_tree().change_scene_to_file("res://main.tscn") != OK:
		var error := Label.new()
		error.text = "游戏场景加载失败。若安装了本地更新，请移走 updates/update.json 后重新打开。"
		error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		error.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(error)
		error.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		push_error("Grey Oath could not load res://main.tscn")


func _mount_local_update(base_version: String) -> Dictionary:
	if "--no-local-update" in OS.get_cmdline_user_args() or "--no-local-update" in OS.get_cmdline_args():
		return {"status": "bypassed"}
	if OS.has_feature("editor") or OS.get_name() != "macOS":
		return {"status": "editor" if OS.has_feature("editor") else "base"}

	var user_dir := DirAccess.open("user://")
	if user_dir != null and user_dir.is_link("updates"):
		return _reject("更新目录不能使用符号链接。")
	var updates := DirAccess.open(UPDATE_DIR)
	if updates == null:
		return {"status": "base"}
	if updates.is_link(MANIFEST_NAME):
		return _reject("更新清单不能使用符号链接。")
	if not updates.file_exists(MANIFEST_NAME):
		return {"status": "base"}
	var envelope_file := FileAccess.open(UPDATE_DIR.path_join(MANIFEST_NAME), FileAccess.READ)
	if envelope_file == null:
		return _reject("无法读取更新清单。")
	var length := envelope_file.get_length()
	if length < 1 or length > MAX_ENVELOPE_BYTES:
		return _reject("更新清单大小无效。")
	var envelope := _json_object(envelope_file.get_buffer(length))
	var encoded_payload: Variant = envelope.get("payload")
	var encoded_signature: Variant = envelope.get("signature")
	if not encoded_payload is String or not encoded_signature is String:
		return _reject("更新清单格式无效。")
	var payload := Marshalls.base64_to_raw(encoded_payload)
	var signature := Marshalls.base64_to_raw(encoded_signature)
	if payload.is_empty() or signature.is_empty() or not _verify_signature(payload, signature):
		return _reject("更新签名无效。")

	var manifest := _json_object(payload)
	if not _valid_integer(manifest.get("schema"), 1) or str(manifest.get("product", "")) != PRODUCT:
		return _reject("更新产品或清单格式不匹配。")
	if str(manifest.get("base_version", "")) != base_version:
		return _reject("更新需要不同的基础版本。")
	var revision: Variant = manifest.get("revision")
	var size: Variant = manifest.get("size")
	var sha: Variant = manifest.get("sha256")
	var base_sha: Variant = manifest.get("base_sha256")
	if not _valid_integer(revision, MAX_REVISION) or not _valid_integer(size, MAX_PACK_BYTES):
		return _reject("更新编号或更新包大小无效。")
	if not _valid_sha256(sha) or not _valid_sha256(base_sha):
		return _reject("更新指纹格式无效。")
	var filename := "%s.pck" % sha
	if str(manifest.get("pack", "")) != filename or updates.is_link(filename):
		return _reject("更新包文件名无效。")
	var base_path := OS.get_executable_path().get_base_dir().path_join(BASE_PACK).simplify_path()
	if FileAccess.get_sha256(base_path) != base_sha:
		return _reject("更新与当前应用的基础包不匹配。")
	var path := ProjectSettings.globalize_path(UPDATE_DIR.path_join(filename))
	var pack := FileAccess.open(path, FileAccess.READ)
	if pack == null or pack.get_length() != int(size):
		return _reject("更新包缺失或大小不符。")
	pack.close()
	if FileAccess.get_sha256(path) != sha:
		return _reject("更新包指纹不符。")
	if not ProjectSettings.load_resource_pack(path, true):
		return _reject("无法挂载更新包。")
	return {"status": "applied", "revision": int(revision)}


func _verify_signature(payload: PackedByteArray, signature: PackedByteArray) -> bool:
	if not FileAccess.file_exists(PUBLIC_KEY):
		return false
	var key := CryptoKey.new()
	if key.load_from_string(FileAccess.get_file_as_string(PUBLIC_KEY), true) != OK:
		return false
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	return Crypto.new().verify(HashingContext.HASH_SHA256, context.finish(), signature, key)


func _json_object(bytes: PackedByteArray) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data


func _valid_integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and value >= 1 and value <= maximum and int(value) == value


func _valid_sha256(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _reject(reason: String) -> Dictionary:
	return {"status": "rejected", "detail": reason}
