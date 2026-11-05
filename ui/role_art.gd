extends RefCounted

## Independent portraits take precedence; the supplied lineup is a temporary atlas.
const REGIONS := {
	"warden": Rect2(0, 0, 390, 793),
	"ranger": Rect2(390, 0, 412, 793),
	"sister": Rect2(802, 0, 390, 793),
	"arcanist": Rect2(1192, 0, 400, 793),
	"medium": Rect2(1592, 0, 391, 793),
}
## Delivered 1024×1536 portraits used at runtime. Concept sheets live under
## roles/concepts/ for review only (docs/character-concepts-20261104.md); map a
## concept here only when it is the canonical design — never to shadow a
## delivered portrait with an earlier sketch.
const ORIGINAL_PORTRAITS := {
	"bellscribe": "res://assets/art/roles/bellscribe.png",
	"ashlamper": "res://assets/art/roles/concepts/ashlamper-concept-2026-11-04.png",
}
static var _original_textures: Dictionary = {}

static func texture_for(role_id: String) -> Texture2D:
	if ORIGINAL_PORTRAITS.has(role_id):
		return _original_texture(role_id)
	if not REGIONS.has(role_id):
		return null
	var path := "res://assets/art/roles/%s.png" % role_id
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var lineup_path := "res://assets/art/roles/reference-lineup.png"
	if not ResourceLoader.exists(lineup_path):
		return null
	var result := AtlasTexture.new()
	result.atlas = load(lineup_path) as Texture2D
	result.region = REGIONS[role_id]
	return result


static func _original_texture(role_id: String) -> Texture2D:
	if _original_textures.has(role_id):
		return _original_textures[role_id]
	var path: String = ORIGINAL_PORTRAITS[role_id]
	var texture: Texture2D
	if path.get_extension().to_lower() == "svg" and FileAccess.file_exists(path):
		# Starting from a source checkout may precede the editor's first import.
		var image := Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(path)) == OK:
			texture = ImageTexture.create_from_image(image)
	elif ResourceLoader.exists(path, "Texture2D"):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		# Raster source files can be loaded directly before their first editor import.
		var raster := Image.new()
		if raster.load(ProjectSettings.globalize_path(path)) == OK:
			texture = ImageTexture.create_from_image(raster)
	if texture != null:
		_original_textures[role_id] = texture
	return texture
