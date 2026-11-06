extends SceneTree
const Rules = preload("res://core/game_engine.gd")
var checks := 0
var failures: Array[String] = []
var path := "user://experience-test-%d.json" % OS.get_process_id()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = Rules.new(path)
	for role in game.data.roles:
		check(game.is_role_unlocked(str(role.id)), "all roles available on a fresh profile: " + str(role.id))
		var fresh = Rules.new("")
		check(fresh.new_run(str(role.id), 729).ok, "every role starts without wins: " + str(role.id))
	check(game.achievement_entries().size() == 13, "twelve existing achievements plus sacred collection")
	check(game.profile.seen_cards.is_empty() and game.profile.achievements.is_empty(), "fresh profile is empty")
	check(not game.new_run("missing").ok and int(game.profile.stats.runs_started) == 0, "rejected start changes no counters")
	var started: Dictionary = game.new_run("warden", 729)
	check(started.ok and started.achievements.has("first_oath"), "new run unlocks first oath")
	check(game.profile.seen_cards.size() == 4, "duplicate starter cards collected once")
	var count: int = game.profile.seen_cards.size()
	game._seen(str(game.state.deck[0].id))
	check(game.profile.seen_cards.size() == count, "repeated acquisition is idempotent")
	game.enter_node(1)
	check(not game.play_card(-1).ok and int(game.profile.stats.cards_played) == 0, "rejected card does not count")
	game.state.energy = 100
	check(game.play_card(0).ok and int(game.profile.stats.cards_played) == 1, "successful play counted once")
	# Explicit elite fixture tests settlement, not natural combat balance.
	game.state.encounter_kind = "elite"
	game._win_battle()
	game._commit("fixture")
	check(game.profile.achievements.has("first_elite"), "elite victory milestone")
	var wins: int = game.profile.total_wins
	game._win_battle()
	check(game.profile.total_wins == wins and int(game.profile.stats.elite_wins) == 1, "duplicate victory does not increment")
	count = game.profile.seen_cards.size()
	game.choose_reward(-1)
	check(game.profile.seen_cards.size() == count, "skipped reward not collected")
	game.state.room = "rest"
	game.rest(0)
	check(game.profile.achievements.has("artisan"), "upgrade milestone")
	check(game.update_setting("music_volume", 0.25).ok, "valid volume accepted")
	check(game.update_setting("combat_speed", 2.0).ok, "valid animation speed accepted")
	check(not game.update_setting("music_volume", -1).ok, "invalid volume rejected")
	check(not game.update_setting("music_volume", NAN).ok, "non-finite volume rejected")
	check(not game.update_setting("combat_speed", 99).ok, "invalid speed rejected")
	check(not game.update_setting("unknown", true).ok, "unknown setting rejected")
	var snapshot: Dictionary = game.profile.duplicate(true)
	var loaded = Rules.new(path)
	for key in snapshot:
		if loaded.profile.get(key) != snapshot[key]:
			print("RELOAD_DIFF ", key, " before=", snapshot[key], " after=", loaded.profile.get(key))
	check(loaded.profile == snapshot, "collection, achievements, counters and settings survive reload")
	var duplicate: Dictionary = loaded._commit("read again")
	check(duplicate.achievements.is_empty(), "reload does not emit duplicate unlocks")
	loaded.abandon_run()
	check(loaded.profile.seen_cards == snapshot.seen_cards and loaded.profile.achievements == snapshot.achievements, "abandon preserves permanent progress")
	# Simulate a legacy save with only the original settings and profile shape.
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.erase("stats")
	legacy.erase("achievements")
	legacy.settings = {"music": false, "sound": true}
	legacy.seen_cards.append(legacy.seen_cards[0])
	legacy.seen_cards.append("missing_card")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"save_version": 1, "content_version": game.data.version, "profile": legacy, "state": game.state}))
	file.close()
	var migrated = Rules.new(path)
	check(migrated.last_error.is_empty(), "legacy save accepted")
	check(not migrated.profile.settings.music and migrated.profile.settings.has("combat_speed"), "nested defaults merged without discarding legacy mute")
	check(migrated.profile.seen_cards.size() == snapshot.seen_cards.size(), "collection migration deduplicates and removes unknown ids")
	check(int(migrated.profile.stats.cards_played) == 0, "legacy unknown counters not fabricated")
	check(migrated.profile.achievements.has("first_victory"), "existing win evidence unlocks legacy milestone")
	var collector = Rules.new("")
	var card_ids: Array = collector.data.cards.map(func(card): return card.id)
	collector.profile.seen_cards = card_ids.slice(0, card_ids.size() - 1)
	check(not collector._commit("almost complete").achievements.has("collector_all"), "expanded collection requires every card")
	var collection: Dictionary = collector.achievement_entries().filter(func(entry): return entry.id == "collector_all")[0]
	check(collection.goal == card_ids.size() and collection.progress == card_ids.size() - 1, "collection goal follows catalog")
	collector.profile.seen_cards.append(card_ids.back())
	check(collector._commit("complete").achievements.has("collector_all"), "complete expanded collection unlocks achievement")
	collector.profile.seen_cards.resize(250)
	check(collector.achievement_entries().filter(func(entry): return entry.id == "collector_all")[0].unlocked, "previously earned collection achievement remains unlocked")
	var before_rng: Dictionary = game.state.rng_states.duplicate(true)
	game.achievement_entries()
	check(game.state.rng_states == before_rng, "reading progression never consumes gameplay RNG")
	var failed_save = Rules.new("/dev/null/grey-oath-experience.json")
	var result: Dictionary = failed_save.new_run("warden", 729)
	check(result.ok and result.has("save_error") and result.achievements.has("first_oath"), "save failure reports committed progress and error")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var report := {"checks": checks, "failures": failures, "scope": "progression, acquisition, persistence, old save migration, idempotency and failed saves; explicit fixtures"}
	var output := FileAccess.open("res://docs/evidence/experience-20261104/progression.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("PROGRESSION_RESULT=", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
