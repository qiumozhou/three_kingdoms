extends RefCounted

const VERSION := 1
const SLOT_COUNT := 8


static func write(path: String, state: Dictionary) -> Error:
	var config := ConfigFile.new()
	config.set_value("campaign", "version", VERSION)
	config.set_value("campaign", "state", state)
	var temporary := path + ".tmp"
	var error := config.save(temporary)
	if error != OK:
		return error
	return DirAccess.rename_absolute(temporary, path)


static func read(path: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK or config.get_value("campaign", "version", -1) != VERSION:
		return {}
	var state: Variant = config.get_value("campaign", "state", {})
	if not state is Dictionary:
		return {}
	if not state.get("index") is int or not state.get("king") is int or not state.get("year") is int:
		return {}
	var index: int = state["index"]
	var king: int = state["king"]
	if index < 0 or index >= UnityScenario.KING_COUNTS.size() or king < 0 or king >= UnityScenario.KING_COUNTS[index]:
		return {}
	for key in ["kings", "cities", "generals"]:
		if not state.get(key) is Array or not state[key].all(func(row: Variant) -> bool: return row is Dictionary):
			return {}
	if (state["kings"].size() != UnityScenario.KING_COUNTS[index] + 1
			or state["cities"].size() != 48 or state["generals"].size() != 255):
		return {}
	return state
