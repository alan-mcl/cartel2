class_name LeaderboardStore
extends RefCounted

const FILE_NAME := "leaderboard.json"
const STORE_VERSION := 1

static var store_dir: String = "user://"

enum SortColumn {
	PROFIT,
	REVENUE,
	EXPENSES,
	TONNES,
	MISSIONS,
	KILLS,
	REPUTATION,
	CAREER_TIME,
	NET_WORTH,
}


static func file_path() -> String:
	return store_dir.path_join(FILE_NAME)


static func read_all() -> Array:
	var path := file_path()
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var entries: Variant = parsed.get("entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return []
	return entries.duplicate(true)


static func write_all(entries: Array) -> bool:
	var dir := store_dir
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(file_path(), FileAccess.WRITE)
	if file == null:
		push_error("Failed to write leaderboard: %s" % file_path())
		return false
	var payload := {
		"version": STORE_VERSION,
		"entries": entries,
	}
	file.store_string(JSON.stringify(payload, "\t"))
	return true


static func upsert_from_session(
	session: GameSession,
	saved_at: String,
	catalog: Catalog = null,
	mark_ended: bool = false
) -> bool:
	if session == null or session.player.sandbox:
		return false
	session.career.ensure_career_id()
	var board_mode := CareerTimeMode.normalise(session.career.time_mode)
	if board_mode != CareerTimeMode.UNLIMITED and session.career.time_limit_pending:
		return false
	var entries := read_all()
	var career_id := session.career.career_id
	var index := _find_entry_index(entries, career_id, board_mode)
	if index >= 0 and bool(entries[index].get("sealed", false)):
		return false
	var entry := _build_entry_from_session(session, saved_at, board_mode, catalog, mark_ended)
	if index >= 0:
		entries[index] = entry
	else:
		entries.append(entry)
	return write_all(entries)


static func seal_timed_run(session: GameSession, saved_at: String, catalog: Catalog = null) -> bool:
	if session == null or session.player.sandbox:
		return false
	session.career.ensure_career_id()
	var board_mode := CareerTimeMode.normalise(session.career.time_mode)
	if not CareerTimeMode.is_timed(board_mode):
		return false
	var entries := read_all()
	var career_id := session.career.career_id
	var index := _find_entry_index(entries, career_id, board_mode)
	if index >= 0 and bool(entries[index].get("sealed", false)):
		return false
	var entry := _build_entry_from_session(session, saved_at, board_mode, catalog, false)
	entry["sealed"] = true
	if index >= 0:
		entries[index] = entry
	else:
		entries.append(entry)
	return write_all(entries)


static func _build_entry_from_session(
	session: GameSession,
	saved_at: String,
	board_mode: String,
	catalog: Catalog,
	mark_ended: bool
) -> Dictionary:
	var entry := {
		"career_id": session.career.career_id,
		"callsign": session.callsign,
		"time_mode": CareerTimeMode.normalise(board_mode),
		"profit": session.career.nett_profit(),
		"revenue": session.career.total_revenue(),
		"expenses": session.career.total_expenses(),
		"tonnes_traded": session.career.tonnes_traded(),
		"missions_completed": session.career.missions_completed(),
		"kills": session.career.kills,
		"reputation": session.player.reputation,
		"ships_owned": session.fleet.owned_ships.size(),
		"career_time": session.career.elapsed_gst_seconds(session.gst_seconds),
		"career_time_gst": true,
		"saved_at": saved_at,
	}
	if mark_ended:
		entry["ended"] = true
	if catalog != null:
		entry["net_worth"] = CareerWorth.nett_worth(session, catalog)
	return entry


static func _entry_time_mode(entry: Dictionary) -> String:
	if not entry.has("time_mode"):
		return CareerTimeMode.UNLIMITED
	return CareerTimeMode.normalise(str(entry.get("time_mode", "")))


static func _find_entry_index(entries: Array, career_id: String, time_mode: String) -> int:
	var mode := CareerTimeMode.normalise(time_mode)
	for i in entries.size():
		var existing: Dictionary = entries[i]
		if typeof(existing) != TYPE_DICTIONARY:
			continue
		if str(existing.get("career_id", "")) != career_id:
			continue
		if _entry_time_mode(existing) == mode:
			return i
	return -1


static func is_career_ended(career_id: String) -> bool:
	if career_id.is_empty():
		return false
	for entry in read_all():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("career_id", "")) != career_id:
			continue
		return bool(entry.get("ended", false))
	return false


static func sorted_entries(
	column: SortColumn,
	descending: bool,
	time_mode: String = CareerTimeMode.UNLIMITED
) -> Array:
	var filter_mode := CareerTimeMode.normalise(time_mode)
	var entries: Array = []
	for entry_variant in read_all():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if _entry_time_mode(entry) == filter_mode:
			entries.append(entry.duplicate(true))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if column == SortColumn.NET_WORTH:
			var a_measured := a.has("net_worth")
			var b_measured := b.has("net_worth")
			if a_measured != b_measured:
				return a_measured
		if column == SortColumn.CAREER_TIME:
			var a_gst := bool(a.get("career_time_gst", false))
			var b_gst := bool(b.get("career_time_gst", false))
			if a_gst != b_gst:
				return a_gst
		var av: Variant = _sort_value(a, column)
		var bv: Variant = _sort_value(b, column)
		if av != bv:
			if typeof(av) == TYPE_FLOAT or typeof(bv) == TYPE_FLOAT:
				return (av > bv) if descending else (av < bv)
			return (av > bv) if descending else (av < bv)
		var at := str(a.get("saved_at", ""))
		var bt := str(b.get("saved_at", ""))
		if at != bt:
			return at < bt
		return str(a.get("callsign", "")) < str(b.get("callsign", ""))
	)
	return entries


static func _sort_value(entry: Dictionary, column: SortColumn) -> Variant:
	match column:
		SortColumn.PROFIT:
			return int(entry.get("profit", 0))
		SortColumn.REVENUE:
			return int(entry.get("revenue", 0))
		SortColumn.EXPENSES:
			return int(entry.get("expenses", 0))
		SortColumn.TONNES:
			return float(entry.get("tonnes_traded", 0.0))
		SortColumn.MISSIONS:
			return int(entry.get("missions_completed", 0))
		SortColumn.KILLS:
			return int(entry.get("kills", 0))
		SortColumn.REPUTATION:
			return int(entry.get("reputation", 0))
		SortColumn.CAREER_TIME:
			return float(entry.get("career_time", 0.0))
		SortColumn.NET_WORTH:
			return int(entry.get("net_worth", 0))
	return 0
