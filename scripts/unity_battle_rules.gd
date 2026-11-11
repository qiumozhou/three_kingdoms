extends RefCounted

# Rows are attacking arms indices, columns are defending arms indices.
const BLOCK := [
	[50, 70, 70, 20, 20, 20, 50, 50, 70, 50, 50],
	[30, 50, 50, 70, 70, 70, 30, 50, 50, 50, 30],
	[30, 50, 50, 70, 70, 70, 50, 30, 50, 50, 30],
	[80, 30, 30, 50, 50, 50, 30, 80, 30, 80, 30],
	[80, 30, 30, 50, 50, 50, 30, 80, 30, 80, 30],
	[80, 30, 30, 50, 50, 50, 30, 80, 30, 80, 30],
	[50, 70, 30, 70, 50, 50, 50, 50, 30, 70, 30],
	[50, 65, 65, 25, 25, 25, 50, 50, 65, 50, 50],
	[25, 50, 50, 65, 65, 65, 50, 25, 50, 50, 25],
	[50, 65, 65, 25, 25, 25, 50, 50, 65, 50, 50],
	[60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60],
]

const SOLDIERS := "res://assets/unity_reference/soldiers/"
const HEAL_SPELLS := [0, 37]
const SWORD_SPELLS := [19, 33, 42]
const MOON_SPELLS := [28, 35, 48]
const AIMED_SPELLS := [5, 6, 23, 24]
const VOLLEY_SPELLS := [27, 32, 44, 1, 7, 16]
const LIGHTNING_SPELLS := [4, 10]
const FIRE_SPELLS := [22, 34]
const MINE_SPELLS := [2, 8, 17]
const CATAPULT_SPELLS := [26, 38, 41]
const RISING_STONE_SPELLS := [20, 30, 43]
const FIRE_DRAGON_SPELLS := [3, 9, 13]
const TORNADO_SPELLS := [25, 36, 45]
const RAM_SPELLS := [21, 31]
const COMPOSITE_SPELLS := {
	18: [[0.3, 14], [1.8, 31], [2.8, 15]],
	49: [[0.0, 7], [0.0, 38], [1.8, 40]],
}
const AMBUSH_REINFORCEMENTS := {11: 4, 12: 16, 29: 8, 46: 30}
const FORMATION_MASKS := [1, 2, 8, 16, 32, 64]
const MAX_FORMATION_UNITS := 100
const FORMATION_ROWS := 5151
const FORMATION_RECORD_BYTES := 5

var formations := FileAccess.get_file_as_bytes("res://assets/unity_reference/formation_slots.gz"
	).decompress_dynamic(22_000_000, FileAccess.COMPRESSION_GZIP)
var animations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
	SOLDIERS + "animation.json"))
var generals: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
	SOLDIERS + "generals.json"))
var spells: Dictionary = {}
var textures: Dictionary = {}


func _init() -> void:
	var xml := XMLParser.new()
	if xml.open("res://assets/unity_reference/MagicConfig.xml") != OK:
		return
	while xml.read() == OK:
		if xml.get_node_type() == XMLParser.NODE_ELEMENT and xml.get_node_name() == "MAGIC":
			var id := xml.get_named_attribute_value("SEQUENCE").to_int()
			spells[id] = {
				"name": xml.get_named_attribute_value("NAME"),
				"mp": xml.get_named_attribute_value("MP").to_int(),
				"attack": xml.get_named_attribute_value("ATTACK").to_int(),
			}


static func supports_spell(id: int) -> bool:
	return (id == 15 or id == 39 or id in HEAL_SPELLS or id in SWORD_SPELLS or id in MOON_SPELLS
		or id in AIMED_SPELLS or id in VOLLEY_SPELLS or id in LIGHTNING_SPELLS
		or id in FIRE_SPELLS or id in MINE_SPELLS or id in CATAPULT_SPELLS or id in RISING_STONE_SPELLS
		or id in FIRE_DRAGON_SPELLS or id in TORNADO_SPELLS or id in RAM_SPELLS
		or id in [14, 40, 47] or COMPOSITE_SPELLS.has(id)
		or AMBUSH_REINFORCEMENTS.has(id))


static func arms_index(mask: int) -> int:
	var index := 0
	while mask > 1:
		mask >>= 1
		index += 1
	return clampi(index, 0, 10)


static func ranged(arms: int) -> bool:
	return arms >= 3 and arms <= 5


static func block_chance(attacker: int, defender: int) -> int:
	if attacker == -1:
		return 0
	if attacker == 1000:
		return 50
	return BLOCK[attacker][defender]


static func general_hit_chance(attacker_strength: int, defender_strength: int, duel: bool) -> int:
	if duel:
		return 61 + clampi(attacker_strength - defender_strength, -20, 20)
	@warning_ignore("integer_division")
	return 71 - defender_strength / 5


func formation_slots(mask: int, foot: int, mounted: int, left: bool) -> Array[Vector3i]:
	var slots: Array[Vector3i] = []
	var shape := FORMATION_MASKS.find(1 if mask == 4 else mask)
	if shape == -1 or foot < 0 or mounted < 0 or foot + mounted > MAX_FORMATION_UNITS:
		return slots
	var shape_count := FORMATION_MASKS.size()
	@warning_ignore("integer_division")
	var counts_row := foot * (MAX_FORMATION_UNITS + 1) - foot * (foot - 1) / 2 + mounted
	var row := (shape + (0 if left else shape_count)) * FORMATION_ROWS + counts_row
	var header_size := (2 * shape_count * FORMATION_ROWS + 1) * 4
	var begin := header_size + formations.decode_u32(row * 4)
	var end := header_size + formations.decode_u32((row + 1) * 4)
	for offset in range(begin, end, FORMATION_RECORD_BYTES):
		slots.append(Vector3i(formations.decode_s16(offset), formations.decode_s16(offset + 2),
			formations[offset + 4]))
	return slots


func atlas_texture(key: String) -> Texture2D:
	if not textures.has(key):
		textures[key] = load(SOLDIERS + key + ".png")
	return textures[key]


func soldier_frame(key: String, knight: bool, clip: String, time: float) -> Array:
	var atlas: Dictionary = animations[key]
	var track: Array = atlas["knight" if knight else "foot"][clip]
	return _frame_at(atlas["frames"], track, clip, time)


func general_parts(officer: Dictionary, side: String) -> Array[String]:
	var indices: Array = generals["officers"][officer["Index"]]
	var mapping: Dictionary = generals["mapping"]
	var horse: int = maxi(0, officer["Equipment"] - 26)
	var parts: Array[String] = [
		mapping["Horse" + side].get(str(horse), mapping["Horse" + side]["0"]),
		mapping["Body" + side][str(int(indices[1]))],
		mapping["Head" + side][str(int(indices[0]))],
	]
	for part in parts:
		for entry: Array in generals["parts"][part].values():
			atlas_texture(entry[0])
	return parts


func general_frame(part: String, clip: String, time: float) -> Array:
	var clips: Dictionary = generals["parts"][part]
	var entry: Array = clips.get(clip, clips["Idle"])
	var atlas: String = entry[0]
	return [atlas, _frame_at(animations[atlas]["frames"], entry[1], clip, time)]


func _frame_at(frames: Array, track: Array, clip: String, time: float) -> Array:
	var duration := 0.0
	for frame: Array in track:
		duration += float(frame[1])
	var cursor := fposmod(time, duration) if clip == "Idle" or clip == "Run" else time
	for frame: Array in track:
		if cursor < float(frame[1]):
			return frames[int(frame[0])]
		cursor -= float(frame[1])
	return frames[int(track.back()[0])]
