extends RefCounted
## Optional card illustrations.
##
## Card definitions may carry an `art` path (res://assets/art/cards/<card id>.webp).
## Missing files, empty fields and texture-less paths deliberately resolve to null
## so ui/card_visual.gd keeps drawing its procedural crest instead of a blank box.

const ART_DIRECTORY := "res://assets/art/cards/"

static var _cache: Dictionary = {}


static func texture_for(card: Dictionary) -> Texture2D:
	var path := art_path(card)
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		texture = load(path) as Texture2D
	_cache[path] = texture
	return texture


static func art_path(card: Dictionary) -> String:
	var path := str(card.get("art", "")).strip_edges()
	if path.is_empty():
		return ""
	if not path.begins_with("res://"):
		path = ART_DIRECTORY + path
	return path


static func has_art(card: Dictionary) -> bool:
	return texture_for(card) != null


static func clear_cache() -> void:
	_cache.clear()


static func cached_count() -> int:
	return _cache.size()
