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


static func upsert_from_session(session: GameSession, saved_at: String) -> bool:
	if session == null or session.player.sandbox:
		return false
	session.career.ensure_career_id()
	var entries := read_all()
	var career_id := session.career.career_id
	var entry := {
		"career_id": career_id,
		"callsign": session.callsign,
		"profit": session.career.nett_profit(),
		"revenue": session.career.total_revenue(),
		"expenses": session.career.total_expenses(),
		"tonnes_traded": session.career.tonnes_traded(),
		"missions_completed": session.career.missions_completed(),
		"kills": session.career.kills,
		"saved_at": saved_at,
	}
	var replaced := false
	for i in entries.size():
		var existing: Dictionary = entries[i]
		if str(existing.get("career_id", "")) == career_id:
			entries[i] = entry
			replaced = true
			break
	if not replaced:
		entries.append(entry)
	return write_all(entries)


static func sorted_entries(column: SortColumn, descending: bool) -> Array:
	var entries := read_all()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
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
	return 0
