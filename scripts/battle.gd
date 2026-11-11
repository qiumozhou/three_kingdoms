extends Node2D

signal battle_finished(victory: bool, friendly_survivors: int, enemy_survivors: int)
signal battle_timed_out
signal assault_ordered(friendly: bool)

enum Order { ADVANCE, HOLD, RETREAT }

const UNIT_ART := preload("res://assets/battle_units.png")
const PORTRAIT_ART := preload("res://assets/battle_portraits.png")
const FIELD_ART := preload("res://assets/battle_field.png")
const UNITY_RULES := preload("res://scripts/unity_battle_rules.gd")
# The attack column is wider to accommodate extended weapons.
const FRAME_EDGES := [0, 320, 660, 985, 1448]
const FRAME_ANCHORS := [150, 480, 810, 1170]
const ROW_EDGES := [0, 353, 735, 1086]
const ROW_BASELINES := [333, 703, 1040]
const SOLDIER_SPEED := 52.0
const PERSONAL_SPACE := 17.0
const FIELD_MIN := Vector2(24.0, 142.0)
const FIELD_MAX := Vector2(936.0, 514.0)
const ATTACK_RANGE := 22.0
const ATTACK_DAMAGE := 10.0
const ATTACK_INTERVAL := 0.55
const ATTACK_POSE_TIME := 0.32
const HIT_POSE_TIME := 0.16
const SOLDIERS_PER_SIDE := 50
const BLUE := Color("4da6ff")
const RED := Color("ef5b5b")
const GENERAL_HEALTH := 90.0
const SKILL_RADIUS := 115.0
const SKILL_DAMAGE := 30.0
const SKILL_COOLDOWN := 6.0
const SLASH_DURATION := 0.65
const PROJECTILE_CLIPS := ["Arrow", "Hammer", "Dart"]
const PROJECTILE_SPEED := 250.0
const PROJECTILE_RANGE := 500.0
const PROJECTILE_LANE := 4.0

var blue_units: Array[Dictionary] = []
var red_units: Array[Dictionary] = []
var blue_order := Order.ADVANCE
var blue_general_order := Order.HOLD
var red_order := Order.HOLD
var red_general_order := Order.HOLD
var enemy_phase := 0
var enemy_command_time := 0.0
var battle_over := false
var battle_seconds := 0.0
var blue_general: Dictionary
var red_general: Dictionary
var skill_cooldown := 0.0
var slash_time := 0.0
var slash_center := Vector2.ZERO
var slash_facing := 1.0
var campaign_battle := false
var friendly_name := "关羽"
var enemy_name := "敌军主将"
var friendly_soldiers := SOLDIERS_PER_SIDE
var enemy_soldiers := SOLDIERS_PER_SIDE
var friendly_health := GENERAL_HEALTH
var enemy_health := GENERAL_HEALTH
var friendly_knights := 0
var enemy_knights := 0
var friendly_portrait: Texture2D
var enemy_portrait: Texture2D
var battlefield_wall: Texture2D
var friendly_front := false
var presentation_paused := false
var presentation_focus := Vector2(480, 320)
var unity_commands: Control
var unity_command_buttons: Array[Button] = []
var commands_open := false
var battle_speed := 1
var assault_side := 0
var battle_mouse_origin := Vector2.ZERO
var battle_dragging := false
var source_font := preload("res://assets/unity_reference/Font.fnt")
var battlefield_sky: Texture2D
var battlefield_ground: Texture2D
var friendly_officer: Dictionary
var enemy_officer: Dictionary
var unity_rules: RefCounted
var spell_effect_time := 0.0
var spell_effect_position := Vector2.ZERO
var spell_effect_id := -1
var spell_effect_points: Array[Vector2] = []
var pending_spell: Dictionary
var composite_spells: Array = []
var composite_states: Array[Dictionary] = []
var composite_caster: Dictionary
var composite_target: Dictionary
var composite_elapsed := 0.0
var projectiles: Array[Dictionary] = []
var spell_picker: MenuButton

@onready var clock_label: Label = %BattleClock
@onready var order_label: Label = %OrderLabel
@onready var result_label: Label = %ResultLabel
@onready var skill_button: Button = %SkillButton


func _ready() -> void:
	$FriendlyName.text = friendly_name
	$EnemyName.text = enemy_name
	if not friendly_officer.is_empty() and not enemy_officer.is_empty():
		unity_rules = UNITY_RULES.new()
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		blue_order = Order.HOLD
		enemy_command_time = float(randi_range(8, 14))
		_add_unity_orders()
		for control in [$FriendlyName, $EnemyName, clock_label, order_label, $CommandPanel]:
			control.hide()
		$FriendlyName.position.x = 560.0
		$EnemyName.position.x = 166.0
	_spawn_army(blue_units, Vector2(218.0, 185.0), 1.0, friendly_soldiers, friendly_knights)
	_spawn_army(red_units, Vector2(742.0, 185.0), -1.0, enemy_soldiers, enemy_knights)
	blue_general = _spawn_general(blue_units, Vector2(174.0, 320.0), 1.0, friendly_health)
	red_general = _spawn_general(red_units, Vector2(786.0, 320.0), -1.0, enemy_health)
	if unity_rules != null:
		_configure_general(blue_general, friendly_officer)
		_configure_general(red_general, enemy_officer)
		if friendly_front:
			blue_general.position.x = 414.0
		_add_spell_selection()
	_update_ui()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if presentation_paused or commands_open:
		queue_redraw()
		return
	for step in battle_speed:
		_step_battle(delta)
		if battle_over or presentation_paused:
			break


func _step_battle(delta: float) -> void:
	spell_effect_time = maxf(0.0, spell_effect_time - delta)
	if slash_time > 0.0:
		slash_time = maxf(slash_time - delta, 0.0)
		queue_redraw()
	if battle_over:
		return
	battle_seconds += delta
	if unity_rules != null:
		_update_enemy_command(delta)
		if presentation_paused:
			queue_redraw()
			return
		_charge_spell(blue_general, delta)
		_charge_spell(red_general, delta)
		if red_general_order != Order.RETREAT and _choose_enemy_spell():
			_try_unity_spell(red_general, blue_general)
		_update_spell(delta)
		_update_composite_spell(delta)
	skill_cooldown = maxf(skill_cooldown - delta, 0.0)
	_update_army(blue_units, red_units, blue_order, 1.0, delta)
	_update_army(red_units, blue_units, red_order if unity_rules != null else Order.ADVANCE, -1.0, delta)
	_update_projectiles(delta)
	_remove_dead(blue_units)
	_remove_dead(red_units)
	_separate_units()
	_check_result()
	if unity_rules != null and not battle_over and battle_seconds >= 99.0:
		battle_over = true
		battle_timed_out.emit()
	_update_ui()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if presentation_paused:
		return
	if commands_open:
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton
				and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
			_close_unity_commands()
			get_viewport().set_input_as_handled()
		return
	if unity_rules != null and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			battle_mouse_origin = event.position
			battle_dragging = false
		elif not battle_dragging and Rect2(60, 0, 840, 540).has_point(event.position):
			_show_unity_commands()
	if unity_rules != null and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if event.position.distance_to(battle_mouse_origin) <= 7.5 and not battle_dragging:
			return
		battle_dragging = true
		presentation_focus -= event.relative / 3.0
		presentation_focus = presentation_focus.clamp(Vector2(-20, 230), Vector2(980, 410))
		queue_redraw()
	if event.is_action_pressed("army_advance"):
		_set_blue_order(Order.ADVANCE)
	elif event.is_action_pressed("army_hold"):
		_set_blue_order(Order.HOLD)
	elif event.is_action_pressed("army_retreat"):
		_set_blue_order(Order.RETREAT)
	elif event.is_action_pressed("general_skill"):
		_cast_skill()
	elif battle_over and not campaign_battle and event.is_action_pressed("restart_battle"):
		get_tree().reload_current_scene()


func _draw() -> void:
	if battlefield_sky != null and battlefield_ground != null:
		if unity_rules != null:
			draw_rect(Rect2(0, 0, 960, 720), Color8(49, 77, 121))
		draw_texture_rect(battlefield_sky, Rect2(0, 0, 960, 145), false)
		if unity_rules != null:
			_draw_unity_ground()
		else:
			draw_texture_rect(battlefield_ground, Rect2(0, 145, 960, 405), true)
		if battlefield_wall != null:
			var parallax := -0.405 * (presentation_focus.x - 480.0) if unity_rules != null else 0.0
			draw_texture_rect(battlefield_wall, Rect2(-270 + parallax, 0, 1500, 144), false)
	else:
		draw_texture_rect(FIELD_ART, Rect2(0, 0, 960, 550), false)
	var units := blue_units + red_units
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.position.y < b.position.y)
	for unit in units:
		_draw_unit(unit)
	for shot in projectiles:
		if shot["delay"] <= 0.0:
			_draw_atlas_frame("Projectiles", false, PROJECTILE_CLIPS[shot["arms"] - 3],
				0.0, shot["position"] - Vector2(10.0 * shot["direction"], 25.0), -shot["direction"])
	if slash_time > 0.0:
		_draw_dragon_slash()
	if spell_effect_time > 0.0:
		if (spell_effect_id == 15 or spell_effect_id in UNITY_RULES.LIGHTNING_SPELLS) and spell_effect_time > 0.65:
			_draw_atlas_frame("Lightning", false, "Idle", 1.0 - spell_effect_time,
				spell_effect_position, 1.0)
		elif spell_effect_id in UNITY_RULES.HEAL_SPELLS:
			draw_arc(spell_effect_position - Vector2(0, 20), 27, 0.0, TAU, 32,
				Color(0.38, 1.0, 0.60, spell_effect_time), 3.0, true)
		elif spell_effect_id in UNITY_RULES.MINE_SPELLS or spell_effect_id in UNITY_RULES.RISING_STONE_SPELLS:
			var atlas := "Mine" if spell_effect_id in UNITY_RULES.MINE_SPELLS else "RisingStone"
			for point in spell_effect_points:
				_draw_atlas_frame(atlas, false, "Idle", 1.0 - spell_effect_time, point, 1.0)
		elif spell_effect_id == 14:
			for point in spell_effect_points:
				_draw_atlas_frame("DragonFire", false, "Idle", 1.0 - spell_effect_time, point, 1.0)
	if not pending_spell.is_empty():
		_draw_pending_spell(pending_spell)
	for effect in composite_states:
		_draw_pending_spell(effect)
	_draw_battle_hud(units)


func _draw_pending_spell(effect: Dictionary) -> void:
	var position: Vector2 = effect["position"]
	if effect["id"] in UNITY_RULES.MOON_SPELLS:
		_draw_atlas_frame("Moon", false, "Idle", battle_seconds, position, -effect["direction"])
	elif effect["id"] in UNITY_RULES.AIMED_SPELLS:
		var aimed: int = effect["id"]
		var atlas: String = {5: "MoonBow", 24: "SunBow", 23: "GhostSpear"}.get(aimed, "Projectiles")
		_draw_atlas_frame(atlas, false, "Dart" if aimed == 6 else "Idle", battle_seconds,
			position - Vector2(0, 25), -effect["direction"])
	elif effect["id"] == 40:
		_draw_unity_general(effect["caster"], position)
	elif effect["id"] in UNITY_RULES.RAM_SPELLS and effect["remaining"] <= 0.0:
		var count := 2 if effect["id"] == 21 else 4
		for lane in range(count):
			_draw_atlas_frame("Ram", false, "Idle", effect["elapsed"],
				_ram_position(effect, lane, effect["elapsed"]), -effect["direction"])
	elif effect["id"] in UNITY_RULES.SWORD_SPELLS and effect["remaining"] < 0.5:
		var height: float = effect["remaining"] * 220.0
		_draw_atlas_frame("Sword", false, "Idle", battle_seconds, position - Vector2(0, height), 1.0)


func _spawn_army(army: Array[Dictionary], origin: Vector2, facing: float, soldier_count: int,
		knight_count: int = 0) -> void:
	var total := soldier_count + knight_count
	var officer := friendly_officer if facing > 0.0 else enemy_officer
	var formation: Array[Vector3i] = []
	var arms := 0
	var atlas := ""
	if unity_rules != null:
		formation = unity_rules.formation_slots(officer["formation_current"],
			soldier_count, knight_count, facing > 0.0)
		arms = UNITY_RULES.arms_index(officer["arms_current"])
		atlas = "%s%02d" % ["Green" if facing > 0.0 else "Red", arms + 1]
		unity_rules.atlas_texture(atlas)
	var row_spacing := minf(54.0, 310.0 / maxf(1.0, ceilf(total / 10.0) - 1.0))
	for index in range(total):
		var row := index / 10
		var column := index % 10
		var knight := index >= soldier_count
		var front := true
		var position := origin + Vector2(-facing * column * 20.0, row * row_spacing + randf_range(-8.0, 8.0))
		if not formation.is_empty():
			var slot := formation[index]
			var center := Vector2(174.0 if facing > 0.0 else 786.0, 320.0)
			position = (center + Vector2(slot.x * 0.50, -slot.y * 0.50)).clamp(FIELD_MIN, FIELD_MAX)
			knight = (slot.z & 1) != 0
			front = (slot.z & 2) != 0
		army.append(_soldier(position, facing, arms, atlas, knight, front, index))


func _soldier(position: Vector2, facing: float, arms: int, atlas: String, knight: bool,
		front: bool, index: int) -> Dictionary:
	return {
			"position": position,
			"knight": knight,
			"front": front,
			"health": float(2 if knight else 1) if unity_rules != null else 30.0,
			"arms": arms,
			"atlas": atlas,
			"parry": 0.0,
			"cooldown": randf_range(0.0, ATTACK_INTERVAL),
			"side": facing,
			"facing": facing,
			"stride": fmod(float(index) * 0.17, 1.0),
			"gait": 0.0,
			"attack_time": 0.0,
			"hit_time": 0.0,
			"hit_direction": 0.0,
			"approach_bias": randf_range(-0.85, 0.85),
			"speed_factor": randf_range(0.88, 1.12),
	}


func _spawn_general(army: Array[Dictionary], position: Vector2, facing: float,
		health: float = GENERAL_HEALTH) -> Dictionary:
	var general := {
		"position": position, "health": health, "max_health": health, "cooldown": 0.0, "general": true,
		"side": facing, "facing": facing, "stride": 0.0, "gait": 0.0,
		"attack_time": 0.0, "hit_time": 0.0, "hit_direction": 0.0,
		"approach_bias": 0.0, "speed_factor": 1.0,
	}
	army.append(general)
	return general


func _configure_general(unit: Dictionary, officer: Dictionary) -> void:
	unit["parts"] = unity_rules.general_parts(officer, "Green" if unit.side > 0.0 else "Red")
	unit["strength"] = officer["Strength"]
	unit["max_health"] = float(officer["HealthMax"])
	unit["mana"] = officer["ManaCur"]
	unit["charge"] = 60.0
	var learned: Array[int] = []
	for slot in ["Magic0", "Magic1", "Magic2", "Magic3"]:
		if officer[slot] >= 0:
			learned.append(officer[slot])
	unit["spells"] = learned
	unit["spell"] = learned[0] if not learned.is_empty() else -1


func _charge_spell(unit: Dictionary, delta: float) -> void:
	var rate: float = float(unit["strength"]) / 30.0 + 3.0
	if (unit.side > 0.0 and blue_general_order == Order.RETREAT
			or unit.side < 0.0 and red_general_order == Order.RETREAT):
		rate = -rate
	unit["charge"] = clampf(unit["charge"] + rate * delta, 1.0, 132.0)


func _can_cast(unit: Dictionary, spell_id := -1) -> bool:
	if spell_id < 0:
		spell_id = unit["spell"]
	if (not pending_spell.is_empty() or not composite_spells.is_empty() or not composite_states.is_empty()
			or unit.health <= 0.0 or unit["charge"] < 132.0
			or not UNITY_RULES.supports_spell(spell_id)):
		return false
	if (unit.side > 0.0 and blue_general_order == Order.RETREAT
			or unit.side < 0.0 and red_general_order == Order.RETREAT):
		return false
	return unit["mana"] >= unity_rules.spells[spell_id]["mp"]


func _choose_enemy_spell() -> bool:
	if red_general["charge"] < 132.0 or not pending_spell.is_empty():
		return false
	var learned: Array[int] = red_general["spells"]
	for slot in range(learned.size() - 1, -1, -1):
		var id := learned[slot]
		if UNITY_RULES.supports_spell(id) and red_general["mana"] >= unity_rules.spells[id]["mp"]:
			red_general["spell"] = id
			return true
	return false


func _try_unity_spell(caster: Dictionary, target: Dictionary) -> void:
	if not _can_cast(caster) or target.health <= 0.0:
		return
	var id: int = caster["spell"]
	var spell: Dictionary = unity_rules.spells[caster["spell"]]
	caster["mana"] -= spell["mp"]
	caster["charge"] = 0.0
	if UNITY_RULES.COMPOSITE_SPELLS.has(id):
		composite_spells = UNITY_RULES.COMPOSITE_SPELLS[id].duplicate()
		composite_caster = caster
		composite_target = target
		composite_elapsed = 0.0
	else:
		_start_spell_effect(caster, target, id)


func _update_composite_spell(delta: float) -> void:
	if composite_spells.is_empty() and composite_states.is_empty():
		return
	composite_elapsed += delta
	for index in range(composite_states.size() - 1, -1, -1):
		pending_spell = composite_states[index]
		_update_spell(delta)
		if pending_spell.is_empty():
			composite_states.remove_at(index)
		pending_spell = {}
	if composite_caster.health <= 0.0 or composite_target.health <= 0.0:
		composite_spells.clear()
		composite_states.clear()
		return
	while not composite_spells.is_empty() and composite_elapsed >= composite_spells[0][0]:
		var event: Array = composite_spells.pop_front()
		_start_spell_effect(composite_caster, composite_target, event[1])
		if not pending_spell.is_empty():
			composite_states.append(pending_spell)
			pending_spell = {}


func _start_spell_effect(caster: Dictionary, target: Dictionary, id: int) -> void:
	var spell: Dictionary = unity_rules.spells[id]
	var heals := id in UNITY_RULES.HEAL_SPELLS
	var troops := blue_units if target.side > 0.0 else red_units
	var position: Vector2 = caster.position
	var soldiers := troops.filter(func(unit: Dictionary) -> bool:
		return unit.health > 0.0 and not unit.has("general"))
	if heals:
		caster.health = minf(caster.health + spell["attack"], caster.max_health)
	elif id == 15:
		target.health -= spell["attack"]
	elif id == 39:
		for soldier in soldiers:
			soldier["magic_lock"] = 5.0
	elif UNITY_RULES.AMBUSH_REINFORCEMENTS.has(id):
		_reinforce(caster, UNITY_RULES.AMBUSH_REINFORCEMENTS[id])
	else:
		var strikes: Array[Vector2] = []
		var selected: Array[Dictionary] = []
		var hits_general := false
		var delay := 0.0
		var radius := 0.0
		var period := 0.0
		var regions: Array[Rect2] = []
		if id in UNITY_RULES.SWORD_SPELLS:
			delay = 2.5
			for _strike in range(UNITY_RULES.SWORD_SPELLS.find(id) + 1):
				var soldier: Dictionary = {} if soldiers.is_empty() else soldiers.pick_random()
				strikes.append(soldier.position if not soldier.is_empty() and not soldier in selected else target.position)
				selected.append(soldier)
			position = strikes[0]
		elif id in UNITY_RULES.LIGHTNING_SPELLS or id in UNITY_RULES.VOLLEY_SPELLS:
			var lightning := id in UNITY_RULES.LIGHTNING_SPELLS
			var level := UNITY_RULES.LIGHTNING_SPELLS.find(id) if lightning else UNITY_RULES.VOLLEY_SPELLS.find(id) % 3
			delay = 0.8 if lightning else 2.0
			for _strike in range((level + 1) * 10):
				var soldier: Dictionary = {} if soldiers.is_empty() else soldiers.pick_random()
				if not soldier.is_empty() and not soldier in selected:
					selected.append(soldier)
				elif not hits_general and randi_range(0, 99) < 20:
					hits_general = true
			if hits_general and not lightning:
				# MGArrowDownCtrl uses the fire arrow's damage for ordinary volleys and vice versa.
				spell = unity_rules.spells[1 if UNITY_RULES.VOLLEY_SPELLS.find(id) < 3 else 27]
		elif id in UNITY_RULES.FIRE_SPELLS or id in UNITY_RULES.MINE_SPELLS:
			var mine := id in UNITY_RULES.MINE_SPELLS
			var level := (UNITY_RULES.MINE_SPELLS.find(id) if mine else UNITY_RULES.FIRE_SPELLS.find(id)) + 1
			delay = 0.5
			radius = 50.0 * level
			strikes.append(position)
		elif id in UNITY_RULES.RISING_STONE_SPELLS:
			delay = 0.8
			radius = 30.0
			hits_general = true
			var count: int = [1, 3, 6][UNITY_RULES.RISING_STONE_SPELLS.find(id)]
			strikes.append(target.position)
			for _strike in range(1, count):
				strikes.append(target.position + Vector2(randf_range(-50, 50), randf_range(-50, 50)))
		elif id in UNITY_RULES.CATAPULT_SPELLS:
			delay = 1.75
			radius = 25.0
			var count: int = [3, 6, 12][UNITY_RULES.CATAPULT_SPELLS.find(id)]
			for _strike in range(count):
				var point: Vector2
				if not soldiers.is_empty():
					point = soldiers.pick_random().position
				elif not hits_general and randi_range(0, 99) < 40:
					hits_general = true
					point = target.position
				else:
					point = target.position + Vector2(randf_range(-75, 75), randf_range(-40, 40))
				strikes.append(point)
			hits_general = false
			# The original catapult controller reads the damage of skill 38 for every variant.
			spell = unity_rules.spells[38]
		elif id in UNITY_RULES.FIRE_DRAGON_SPELLS:
			delay = 0.8
			period = 0.2
			var level := UNITY_RULES.FIRE_DRAGON_SPELLS.find(id) + 1
			var center := _army_center(soldiers, target.position)
			var direction: float = caster.side
			for segment in range(10):
				regions.append(Rect2(center.x + (-50.0 + segment * 10.0) * direction,
					320.0 - level * 15.0, 10.0, level * 30.0))
		elif id == 14 or id in UNITY_RULES.TORNADO_SPELLS:
			var dragon := id == 14
			delay = 1.5 if dragon else 0.8
			period = 0.1 if dragon else 0.6
			radius = 20.0 if dragon else 25.0
			var count := 10 if dragon else UNITY_RULES.TORNADO_SPELLS.find(id) + 1
			var center := _army_center(soldiers, target.position)
			for _strike in range(count):
				var soldier: Dictionary = {} if soldiers.is_empty() else soldiers.pick_random()
				var point: Vector2
				if not soldier.is_empty() and (dragon or not soldier in selected):
					point = soldier.position
					selected.append(soldier)
				elif not hits_general and randi_range(0, 99) < (20 if dragon else 40):
					hits_general = true
					point = target.position
				else:
					point = center + Vector2(randf_range(-90, 90), randf_range(-50, 50))
				regions.append(Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
			selected.clear()
			hits_general = false
		elif id in UNITY_RULES.RAM_SPELLS:
			delay = 0.5
			position = _army_center(soldiers, target.position)
		elif id == 47:
			delay = 0.4
			if absf(caster.position.x - target.position.x) < 100.0:
				period = 0.3
				strikes.assign([Vector2(20, 0), Vector2(10, 0), Vector2(10, 0), Vector2(10, 0)])
		pending_spell = {"id": id, "attack": spell["attack"], "target": target, "troops": troops,
			"position": position, "direction": float(caster.side), "remaining": delay,
			"strikes": strikes, "selected": selected, "hits_general": hits_general, "radius": radius,
			"period": period, "regions": regions, "caster": caster, "elapsed": 0.0, "burned": false}
		return
	spell_effect_position = caster.position if heals else target.position
	spell_effect_id = id
	spell_effect_time = 1.0


func _update_spell(delta: float) -> void:
	if pending_spell.is_empty():
		return
	var target: Dictionary = pending_spell["target"]
	var position: Vector2 = pending_spell["position"]
	var id: int = pending_spell["id"]
	if id in UNITY_RULES.RAM_SPELLS:
		_update_ram_spell(delta)
		return
	if id not in UNITY_RULES.MOON_SPELLS and id not in UNITY_RULES.AIMED_SPELLS and id != 40:
		pending_spell["remaining"] -= delta
		if pending_spell["remaining"] > 0.0:
			return
		spell_effect_points.clear()
		var regions: Array[Rect2] = pending_spell["regions"]
		if not regions.is_empty():
			var region: Rect2 = regions.pop_front()
			_spell_hit(region)
			if region.has_point(target.position) and not pending_spell["burned"]:
				target.health -= pending_spell["attack"]
				pending_spell["burned"] = id == 14 or id in UNITY_RULES.FIRE_DRAGON_SPELLS
			spell_effect_points.append(region.get_center())
			spell_effect_id = id
			spell_effect_time = 1.0
			if not regions.is_empty():
				pending_spell["remaining"] += pending_spell["period"]
				return
		if id == 47:
			var hits: Array[Vector2] = pending_spell["strikes"]
			if not hits.is_empty():
				var hit: Vector2 = hits.pop_front()
				target.health -= hit.x
				if not hits.is_empty():
					pending_spell["remaining"] += pending_spell["period"]
					return
		var radius: float = pending_spell["radius"] if pending_spell["radius"] > 0.0 else 30.0
		var general_burned := false
		for strike: Vector2 in pending_spell["strikes"]:
			var region := Rect2(strike - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
			_spell_hit(region)
			spell_effect_points.append(strike)
			if id not in UNITY_RULES.RISING_STONE_SPELLS and region.has_point(target.position) and not general_burned:
				target.health -= pending_spell["attack"]
				general_burned = id in UNITY_RULES.CATAPULT_SPELLS
			if id in UNITY_RULES.MINE_SPELLS:
				for _effect in range(roundi(radius / 5.0)):
					spell_effect_points.append(strike + Vector2(randf_range(-radius, radius), randf_range(-radius, radius)))
		for soldier: Dictionary in pending_spell["selected"]:
			if id not in UNITY_RULES.SWORD_SPELLS:
				soldier.health = 0.0
		if pending_spell["hits_general"]:
			target.health -= pending_spell["attack"]
	else:
		var direction: float = pending_spell["direction"]
		var next := position + Vector2(direction * 250.0 * delta, 0)
		if id in UNITY_RULES.MOON_SPELLS or id == 23 or id == 40:
			var level := maxi(0, UNITY_RULES.MOON_SPELLS.find(id))
			for lane in range(-level, level + 1):
				var shift := absf(lane) * 15.0 * direction
				var height := 20.0 if id == 40 else 15.0
				var region := Rect2(Vector2(minf(position.x, next.x) - shift, position.y + lane * 30.0 - height / 2.0),
					Vector2(absf(next.x - position.x) + 10.0, height))
				_spell_hit(region)
		pending_spell["position"] = next
		if (next.x - target.position.x) * direction < 0.0:
			return
		target.health -= pending_spell["attack"]
		position = target.position
	spell_effect_position = position
	spell_effect_id = pending_spell["id"]
	spell_effect_time = 1.0
	pending_spell.clear()


func _army_center(soldiers: Array[Dictionary], fallback: Vector2) -> Vector2:
	if soldiers.is_empty():
		return fallback
	var center := Vector2.ZERO
	for soldier in soldiers:
		center += soldier.position
	return center / float(soldiers.size())


func _update_ram_spell(delta: float) -> void:
	pending_spell["remaining"] -= delta
	if pending_spell["remaining"] > 0.0:
		return
	var direction: float = pending_spell["direction"]
	var previous: float = pending_spell["elapsed"]
	var elapsed := minf(3.0, previous + delta)
	var count := 2 if pending_spell["id"] == 21 else 4
	for lane in range(count):
		var point := _ram_position(pending_spell, lane, previous)
		_spell_hit(Rect2(minf(point.x, point.x + (elapsed - previous) * 100.0 * direction) - 15.0,
			point.y - 15.0, 30.0 + (elapsed - previous) * 100.0, 30.0))
	pending_spell["elapsed"] = elapsed
	if elapsed >= 3.0:
		pending_spell.clear()


func _ram_position(effect: Dictionary, lane: int, elapsed: float) -> Vector2:
	var center: Vector2 = effect["position"]
	var height := 50.0 if lane < 2 else 80.0
	return center + Vector2((-150.0 + elapsed * 100.0) * effect["direction"],
		height * (-1.0 if lane % 2 == 0 else 1.0))


func _reinforce(caster: Dictionary, available: int) -> void:
	var friendly: bool = caster.side > 0.0
	var army := blue_units if friendly else red_units
	var officer := friendly_officer if friendly else enemy_officer
	var mounted := 0
	var foot := 0
	for soldier in army:
		if soldier.health > 0.0 and not soldier.has("general"):
			mounted += int(soldier["knight"])
			foot += int(not soldier["knight"])
	var horses := maxi(0, officer["KnightMax"] - mounted)
	var count := mini(available, horses + maxi(0, officer["SoldierMax"] - foot))
	var arms := UNITY_RULES.arms_index(officer["arms_current"])
	var atlas := "%s%02d" % ["Red" if friendly else "Green", arms + 1]
	for index in range(count):
		@warning_ignore("integer_division")
		var column := index / 10
		var x := FIELD_MIN.x + column * 18.0 if friendly else FIELD_MAX.x - column * 18.0
		var unit := _soldier(Vector2(x, 230.0 + index % 10 * 18.0),
			caster.side, arms, atlas, index < horses, false, index)
		unit["order"] = Order.ADVANCE
		army.append(unit)


func _spell_hit(region: Rect2) -> void:
	for unit: Dictionary in pending_spell["troops"]:
		if not unit.has("general") and region.has_point(unit.position):
			unit.health = 0.0


func _unity_hit(attacker: Dictionary, target: Dictionary) -> bool:
	var duel := attacker.has("general")
	var roll := randi_range(0, 99)
	if target.has("general"):
		var strength: int = attacker.get("strength", 0)
		if roll >= UNITY_RULES.general_hit_chance(strength, target["strength"], duel):
			return false
		@warning_ignore("integer_division")
		var base := strength / 12
		target.health -= maxi(0, randi_range(base - 3, base + 2)) if duel else 2
		return true
	var arms: int = 1000 if duel else attacker["arms"]
	if roll < UNITY_RULES.block_chance(arms, target["arms"]):
		target["parry"] = 0.2
		return false
	target.health -= 1.0
	return true


func _queue_projectile(unit: Dictionary) -> void:
	projectiles.append({"source": unit, "position": unit.position, "direction": unit.facing,
		"arms": unit["arms"], "travel": 0.0, "delay": 0.333334})


func _update_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var shot := projectiles[index]
		var elapsed := delta
		if shot["delay"] > 0.0:
			if shot["source"]["health"] <= 0.0:
				projectiles.remove_at(index)
				continue
			elapsed = maxf(0.0, delta - shot["delay"])
			shot["delay"] -= delta
			if shot["delay"] > 0.0:
				continue
			shot["position"] = shot["source"]["position"]
		var position: Vector2 = shot["position"]
		var direction: float = shot["direction"]
		var travel := minf(PROJECTILE_SPEED * elapsed, PROJECTILE_RANGE - shot["travel"])
		var edge := FIELD_MAX.x if direction > 0.0 else FIELD_MIN.x
		travel = minf(travel, absf(edge - position.x))
		var end := position.x + direction * travel
		var enemies := red_units if shot["source"]["side"] > 0.0 else blue_units
		var impact := INF
		for target in enemies:
			var distance: float = (target.position.x - position.x) * direction
			if target.health > 0.0 and _projectile_lane(target.position.y) == _projectile_lane(position.y):
				if distance >= 0.0 and distance <= travel:
					impact = minf(impact, distance)
		if impact < INF:
			for target in enemies:
				var distance: float = (target.position.x - position.x) * direction
				if (target.health > 0.0 and _projectile_lane(target.position.y) == _projectile_lane(position.y)
						and distance >= impact and distance < impact + 6.0 and _unity_hit(shot, target)):
					target.hit_time = HIT_POSE_TIME
					target.hit_direction = direction
			projectiles.remove_at(index)
		else:
			shot["position"] = Vector2(end, position.y)
			shot["travel"] += travel
			if shot["travel"] >= PROJECTILE_RANGE or is_equal_approx(end, edge):
				projectiles.remove_at(index)


func _projectile_lane(y: float) -> int:
	return floori((420.0 - y) / PROJECTILE_LANE)


func _cast_skill() -> void:
	if unity_rules != null:
		if not battle_over:
			_try_unity_spell(blue_general, red_general)
			_update_ui()
			queue_redraw()
		return
	if battle_over or blue_general.health <= 0.0 or skill_cooldown > 0.0:
		return
	skill_cooldown = SKILL_COOLDOWN
	slash_time = SLASH_DURATION
	slash_center = blue_general.position
	slash_facing = blue_general.facing
	blue_general.attack_time = ATTACK_POSE_TIME
	for enemy in red_units:
		if slash_center.distance_squared_to(enemy.position) <= SKILL_RADIUS * SKILL_RADIUS:
			enemy.health -= SKILL_DAMAGE
			enemy.hit_time = HIT_POSE_TIME
			enemy.hit_direction = signf(enemy.position.x - slash_center.x)
	_remove_dead(red_units)
	_check_result()
	_update_ui()
	queue_redraw()


func _draw_dragon_slash() -> void:
	var progress := 1.0 - slash_time / SLASH_DURATION
	var opacity := 1.0 - smoothstep(0.44, 1.0, progress)
	var sweep := smoothstep(0.0, 0.58, progress)
	draw_arc(slash_center, SKILL_RADIUS * lerpf(0.2, 1.0, sweep),
		0.0, TAU, 64, Color(0.34, 0.94, 0.75, opacity * 0.42), 2.0, true)

	var head_angle := lerpf(-1.8, 2.2, sweep)
	var radius := SKILL_RADIUS * lerpf(0.45, 0.90, sweep)
	var tail := PackedVector2Array()
	for index in range(25):
		var t := float(index) / 24.0
		var angle := head_angle - (1.0 - t) * 2.1
		var wave := sin(t * TAU * 2.0 - sweep * 6.0) * 7.0
		var point := Vector2.from_angle(angle) * (radius + wave)
		point.x *= slash_facing
		tail.append(slash_center + point)
	for index in range(1, tail.size()):
		var width := lerpf(1.0, 12.0, float(index) / 24.0)
		draw_line(tail[index - 1], tail[index], Color(0.15, 0.85, 0.61, opacity * 0.38), width + 7.0, true)
		draw_line(tail[index - 1], tail[index], Color(0.68, 1.0, 0.81, opacity), width, true)
	var head := tail[24]
	var forward := tail[23].direction_to(head)
	var side := forward.orthogonal()
	draw_colored_polygon(PackedVector2Array([
		head + forward * 14.0, head + forward * 3.0 + side * 7.0,
		head - forward * 9.0 + side * 12.0, head - forward * 4.0,
		head - forward * 9.0 - side * 12.0, head + forward * 3.0 - side * 7.0,
	]), Color(0.72, 1.0, 0.78, opacity))
	draw_circle(head + forward * 5.0 + side * 3.0, 2.0, Color(1.0, 0.81, 0.38, opacity))

	for index in range(20):
		var angle := float(index) * 2.4
		var travel := lerpf(30.0, SKILL_RADIUS + 18.0, sweep) * (0.65 + 0.35 * absf(sin(angle)))
		var direction := Vector2.from_angle(angle)
		var point := slash_center + direction * travel
		draw_line(point - direction * 7.0, point, Color(1.0, 0.82, 0.42, opacity * sweep), 2.0, true)


func _update_army(
		army: Array[Dictionary], enemies: Array[Dictionary], order: Order,
		facing: float, delta: float) -> void:
	for unit in army:
		if unit.health <= 0.0:
			continue
		if unit.get("magic_lock", 0.0) > 0.0:
			unit["magic_lock"] = maxf(0.0, unit["magic_lock"] - delta)
			continue
		unit.cooldown = maxf(unit.cooldown - delta, 0.0)
		unit.attack_time = maxf(unit.attack_time - delta, 0.0)
		unit.hit_time = maxf(unit.hit_time - delta, 0.0)
		unit["parry"] = maxf(unit.get("parry", 0.0) - delta, 0.0)
		unit["shot_check"] = maxf(unit.get("shot_check", 0.0) - delta, 0.0)
		var target := _nearest_living_enemy(unit.position, enemies)
		var direction := Vector2.ZERO
		var command := order
		if unity_rules != null:
			if unit.has("general"):
				command = blue_general_order if facing > 0.0 else red_general_order
			else:
				command = unit.get("order", order)
		if unit.has("move_to"):
			var destination: Vector2 = unit["move_to"]
			if unit.position.distance_to(destination) <= 8.0:
				unit.erase("move_to")
			else:
				direction = unit.position.direction_to(destination)
		elif command == Order.RETREAT:
			direction = Vector2(-facing, 0.0)
			unit.attack_time = 0.0
		elif not target.is_empty():
			var distance: float = unit.position.distance_to(target.position)
			var ranged := unity_rules != null and not unit.has("general") and UNITY_RULES.ranged(unit["arms"])
			var shoot := false
			if ranged and unit.cooldown <= 0.0 and unit["shot_check"] <= 0.0:
				for candidate in enemies:
					var ahead: float = (candidate.position.x - unit.position.x) * unit.facing
					if (candidate.health > 0.0 and _projectile_lane(candidate.position.y) == _projectile_lane(unit.position.y)
							and ahead >= 0.0 and ahead <= PROJECTILE_RANGE):
						shoot = ahead <= ATTACK_RANGE or randi_range(0, 99) > 90
						unit["shot_check"] = randf_range(0.5, 1.0)
						break
			if shoot:
				_queue_projectile(unit)
				unit.cooldown = 1.667
				unit.attack_time = 0.667
			elif not ranged and distance <= ATTACK_RANGE and unit.cooldown <= 0.0:
				var hit: bool
				if unity_rules == null:
					target.health -= ATTACK_DAMAGE * (2.0 if unit.has("general") else 1.0)
					hit = true
				else:
					hit = _unity_hit(unit, target)
				unit.cooldown = 1.167 if unity_rules != null and not unit.has("general") else ATTACK_INTERVAL
				unit.attack_time = 0.667 if unity_rules != null and not unit.has("general") else ATTACK_POSE_TIME
				unit.facing = 1.0 if target.position.x >= unit.position.x else -1.0
				if hit:
					target.hit_time = HIT_POSE_TIME
					target.hit_direction = unit.facing
			elif distance > ATTACK_RANGE and command == Order.ADVANCE and unit.attack_time <= 0.0:
				var approach: Vector2 = unit.position.direction_to(target.position)
				direction = approach.rotated(unit.approach_bias * smoothstep(ATTACK_RANGE, 100.0, distance))
		if not is_zero_approx(direction.x):
			unit.facing = signf(direction.x)
		var previous_position: Vector2 = unit.position
		unit.position = (previous_position + direction * SOLDIER_SPEED * float(unit.speed_factor) * delta).clamp(FIELD_MIN, FIELD_MAX)
		var traveled := previous_position.distance_to(unit.position)
		unit.stride = fmod(unit.stride + traveled / 15.0, 1.0)
		unit.gait = move_toward(unit.gait, 1.0 if traveled > 0.01 else 0.0, delta * 10.0)


func _separate_units() -> void:
	var units := blue_units + red_units
	# Repeat because moving one pair can squeeze a neighboring pair.
	for _pass_index in range(3):
		for i in range(units.size()):
			var first: Vector2 = units[i].position
			for j in range(i + 1, units.size()):
				var second: Vector2 = units[j].position
				var offset := second - first
				var distance_squared := offset.length_squared()
				if distance_squared >= PERSONAL_SPACE * PERSONAL_SPACE:
					continue
				var distance := sqrt(distance_squared)
				var axis := offset / distance if distance > 0.001 else Vector2.DOWN
				var correction := axis * (PERSONAL_SPACE - distance) * 0.5
				first = (first - correction).clamp(FIELD_MIN, FIELD_MAX)
				units[j].position = (second + correction).clamp(FIELD_MIN, FIELD_MAX)
			units[i].position = first


func _nearest_living_enemy(position: Vector2, enemies: Array[Dictionary]) -> Dictionary:
	var nearest: Dictionary = {}
	var best_distance := INF
	for enemy in enemies:
		if enemy.health <= 0.0:
			continue
		var distance := position.distance_squared_to(enemy.position)
		if distance < best_distance:
			best_distance = distance
			nearest = enemy
	return nearest


func _remove_dead(army: Array[Dictionary]) -> void:
	for index in range(army.size() - 1, -1, -1):
		if army[index].health <= 0.0:
			army.remove_at(index)


func _draw_unit(unit: Dictionary) -> void:
	var friendly: bool = unit.side > 0.0
	var general := unit.has("general")
	if unity_rules != null:
		if general:
			_draw_unity_general(unit)
		else:
			_draw_unity_soldier(unit)
		return
	var row := (0 if friendly else 1) if general else 2
	var frame := 0
	var offset := Vector2.ZERO
	var lean := 0.0
	var scale_factor := 0.19 if general else 0.14
	if unit.attack_time > 0.0:
		var progress := 1.0 - float(unit.attack_time) / ATTACK_POSE_TIME
		frame = 3 if progress < 0.63 else 0
		var thrust := 1.0 - smoothstep(0.08, 1.0, progress)
		offset.x = unit.facing * thrust * (12.0 if general else 8.0)
		lean = unit.facing * thrust * 0.08
	elif unit.gait > 0.2:
		var stride: float = unit.stride
		frame = 1 if stride < 0.5 else 2
		offset.y = -absf(sin(stride * TAU)) * unit.gait * (3.0 if general else 2.0)
		lean = sin(stride * TAU) * unit.gait * 0.035
	var recoil := float(unit.hit_time) / HIT_POSE_TIME
	offset.x += unit.hit_direction * recoil * recoil * 5.0
	var source := Rect2(
		FRAME_EDGES[frame], ROW_EDGES[row],
		FRAME_EDGES[frame + 1] - FRAME_EDGES[frame], ROW_EDGES[row + 1] - ROW_EDGES[row]
	)
	var anchor := Vector2(FRAME_ANCHORS[frame], ROW_BASELINES[row]) - source.position
	var side_color := BLUE if friendly else RED
	var ground: Vector2 = unit.position
	draw_set_transform(ground, 0.0, Vector2(1.0, 0.30))
	draw_circle(Vector2.ZERO, 14.0 if general else 8.0, Color(0.12, 0.09, 0.06, 0.38))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(ground - Vector2(5, 1), Vector2(10, 3)), side_color)
	draw_set_transform(ground + offset, lean, Vector2(unit.facing, 1.0))
	draw_texture_rect_region(UNIT_ART, Rect2(-anchor * scale_factor, source.size * scale_factor), source)
	draw_set_transform(Vector2.ZERO)


func _draw_unity_soldier(unit: Dictionary) -> void:
	var clip := "Idle"
	var time := battle_seconds
	if unit.attack_time > 0.0:
		clip = "Attack"
		time = 0.667 - unit.attack_time
	elif unit["parry"] > 0.0:
		clip = "Parry"
		time = 0.0
	elif unit.gait > 0.2:
		clip = "Run"
	_draw_atlas_frame(unit["atlas"], unit["knight"], clip, time, unit.position, -unit.facing)


func _draw_unity_general(unit: Dictionary, position: Vector2 = Vector2.INF) -> void:
	var clip := "Idle"
	var time := battle_seconds
	if unit.attack_time > 0.0:
		clip = "AttackFront2"
		time = (ATTACK_POSE_TIME - unit.attack_time) * 2.0
	elif unit.hit_time > 0.0:
		clip = "Hit"
		time = HIT_POSE_TIME - unit.hit_time
	elif unit.gait > 0.2:
		clip = "Run"
	var parts: Array[String] = unit["parts"]
	for index in parts.size():
		var part_clip := "Fight" if index == 0 and clip == "AttackFront2" else clip
		var part_time := time
		if assault_side != 0 and assault_side == int(unit.side):
			part_clip = "Idle" if index == 0 else "Assault"
			part_time = 0.0
		var pose: Array = unity_rules.general_frame(parts[index], part_clip, part_time)
		_draw_sprite_region(pose[0], pose[1], unit.position if position == Vector2.INF else position,
			-unit.facing)


func _draw_atlas_frame(atlas: String, knight: bool, clip: String, time: float,
		ground: Vector2, direction: float) -> void:
	var frame: Array = unity_rules.soldier_frame(atlas, knight, clip, time)
	_draw_sprite_region(atlas, frame, ground, direction)


func _draw_sprite_region(atlas: String, frame: Array, ground: Vector2, direction: float) -> void:
	var source := Rect2(frame[0], frame[1], frame[2], frame[3])
	var offset := Vector2(frame[4], frame[5])
	var scale_factor := 0.43
	if unity_rules != null:
		var projected := _project_unity_ground(ground)
		ground = Vector2(projected.x, projected.y)
		direction = -direction
		scale_factor = projected.z
	draw_set_transform(ground, 0.0, Vector2(direction, 1.0))
	draw_texture_rect_region(unity_rules.atlas_texture(atlas),
		Rect2(offset * scale_factor, source.size * scale_factor), source)
	draw_set_transform(Vector2.ZERO)


func _project_unity_ground(ground: Vector2) -> Vector3:
	# WarScene's perspective camera has a 38-degree FOV and a 290-degree X rotation.
	# Its sprite root is at (0, 270, 126), with sprites scaled to 0.5.
	var focal := 360.0 / tan(deg_to_rad(19.0))
	var height := 270.0 + 2.0 * (presentation_focus.y - ground.y)
	var depth := height * sin(deg_to_rad(70.0)) + 126.0 * cos(deg_to_rad(70.0))
	var vertical := height * cos(deg_to_rad(70.0)) - 126.0 * sin(deg_to_rad(70.0))
	var pixels_per_unit := focal / maxf(10.0, depth)
	return Vector3(480.0 + (960.0 - ground.x - presentation_focus.x) * 2.0 * pixels_per_unit,
		360.0 - vertical * pixels_per_unit, 0.5 * pixels_per_unit)


func _draw_unity_ground() -> void:
	# The 3000 × 1000 ground sprite spans world Y 50–1050 at the same depth as the units.
	var colors := PackedColorArray([Color.WHITE])
	for row in 64:
		var top := row / 64.0
		var bottom := (row + 1) / 64.0
		var y0 := -70.0 + top * 500.0
		var y1 := -70.0 + bottom * 500.0
		var left_top := _project_unity_ground(Vector2(1230, y0))
		if left_top.y > 720.0:
			break
		var right_top := _project_unity_ground(Vector2(-270, y0))
		var left_bottom := _project_unity_ground(Vector2(1230, y1))
		var right_bottom := _project_unity_ground(Vector2(-270, y1))
		var points := PackedVector2Array([Vector2(left_top.x, left_top.y), Vector2(right_top.x, right_top.y),
			Vector2(right_bottom.x, right_bottom.y), Vector2(left_bottom.x, left_bottom.y)])
		draw_polygon(points, colors, PackedVector2Array([Vector2(0, top * 4.0), Vector2(12, top * 4.0),
			Vector2(12, bottom * 4.0), Vector2(0, bottom * 4.0)]), battlefield_ground)


func _draw_battle_hud(units: Array[Dictionary]) -> void:
	if unity_rules != null:
		_draw_unity_hud(units)
		return
	var frame := PackedVector2Array([
		Vector2(0, 520), Vector2(224, 520), Vector2(264, 547),
		Vector2(696, 547), Vector2(736, 520), Vector2(960, 520),
		Vector2(960, 720), Vector2(0, 720),
	])
	draw_colored_polygon(frame, Color("131332"))
	draw_polyline(frame, Color("a47743"), 4)
	draw_line(Vector2(0, 718), Vector2(960, 718), Color("a47743"), 4)
	for x in range(273, 696, 12):
		draw_rect(Rect2(x, 551, 8, 6), Color("8e633a"), false)
	draw_rect(Rect2(420, 519, 120, 47), Color("632a23"))
	draw_rect(Rect2(426, 525, 108, 35), Color("e7c996"))
	draw_rect(Rect2(426, 525, 108, 35), Color("b3854c"), false, 2)
	_draw_officer_card(blue_general, 1 if unity_rules != null else 0, blue_units.size())
	_draw_officer_card(red_general, 0 if unity_rules != null else 1, red_units.size())

	var map := Rect2(368, 622, 224, 42)
	draw_rect(map.grow(2), Color("b28a54"))
	draw_rect(map, Color("0a0911"))
	for unit in units:
		var ground: Vector2 = unit.position
		if unity_rules != null:
			ground.x = 960.0 - ground.x
		var point := map.position + Vector2(4, 4) + (ground - FIELD_MIN) / (FIELD_MAX - FIELD_MIN) * (map.size - Vector2(8, 8))
		var color := BLUE if unit.side > 0.0 else RED
		if unit.has("general"):
			draw_rect(Rect2(point - Vector2(3, 3), Vector2(6, 6)), color.lightened(0.4), false)
		else:
			draw_rect(Rect2(point, Vector2(2, 2)), color)


func _draw_unity_hud(units: Array[Dictionary]) -> void:
	draw_texture_rect(preload("res://assets/unity_reference/313-1.png"), Rect2(0, 519, 960, 204), false)
	for side in 2:
		var general := red_general if side == 0 else blue_general
		var officer := enemy_officer if side == 0 else friendly_officer
		var texture := enemy_portrait if side == 0 else friendly_portrait
		if texture != null:
			draw_texture_rect(texture, Rect2(10.5 if side == 0 else 805.5, 525, 144, 144), false)
		_draw_hud_text(enemy_name if side == 0 else friendly_name, Vector2(78 if side == 0 else 882, 697.5), 30, true)
		_draw_hud_text("%02d" % officer["Level"], Vector2(192 if side == 0 else 787.5, 537), 15, true)
		var troops := red_units if side == 0 else blue_units
		var strength: String = str(officer["Strength"])
		var count := str(troops.size() - int(general.health > 0.0))
		_draw_hud_text(strength, Vector2(202.5 if side == 0 else 757.5, 693), 30, false, side == 1)
		_draw_hud_text(count, Vector2(310.5 if side == 0 else 649.5, 693), 30, false, side == 1)
		for resource in 2:
			var maximum: int = officer["HealthMax"] if resource == 0 else officer["ManaMax"]
			var current := ceili(maxf(0.0, general.health)) if resource == 0 else int(general["mana"])
			var width := minf(maximum, 150) * 1.5
			var x := 202.5 if side == 0 else 757.5 - width - 6.0
			var y := 603.0 + resource * 42.0
			draw_texture_rect(preload("res://assets/unity_reference/321-1.png"), Rect2(x, y - 7.5, width + 6, 15), false)
			var fill := width * clampf(float(current) / maxf(1.0, maximum), 0.0, 1.0)
			var bar := preload("res://assets/unity_reference/324-1.png") if side == 0 else preload("res://assets/unity_reference/325-1.png")
			if fill > 0.0:
				var source_width := bar.get_width() * fill / width
				draw_texture_rect_region(bar, Rect2(x + 3.0 + (width - fill if side == 1 else 0.0), y - 4.5, fill, 9),
					Rect2(bar.get_width() - source_width if side == 1 else 0.0, 0, source_width, bar.get_height()))
			_draw_hud_text("%d/%d" % [current, maximum],
				Vector2(202.5 if side == 0 else 757.5, y + 18), 15, false, side == 1)
		var charge: float = general["charge"]
		var sword := preload("res://assets/unity_reference/314-1.png") if side == 0 else preload("res://assets/unity_reference/315-1.png")
		var sword_x := 208.5 if side == 0 else 751.5 - charge * 1.5
		draw_texture_rect_region(sword, Rect2(sword_x, 558.75, charge * 1.5, 13.5),
			Rect2(0 if side == 0 else 132.0 - charge, 0, charge, 9))
	_draw_hud_text(str(maxi(0, 99 - int(battle_seconds))), Vector2(476.469, 629.735), 30, true)
	var map := Rect2(397.5, 669, 165, 36)
	for unit in units:
		var position: Vector2 = unit.position
		position.x = 960.0 - position.x
		var point := map.position + (position - FIELD_MIN) / (FIELD_MAX - FIELD_MIN) * map.size
		draw_rect(Rect2(point, Vector2(3, 3)), BLUE if unit.side > 0.0 else RED)


func _draw_hud_text(text: String, anchor: Vector2, size: int, centered := false, right := false) -> void:
	var width := source_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var offset := width / 2.0 if centered else (width if right else 0.0)
	draw_string(source_font, anchor + Vector2(-offset, size / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)


func _draw_officer_card(general: Dictionary, index: int, army_size: int) -> void:
	var friendly: bool = general == blue_general
	var left := index == 0
	var portrait := Rect2(10 if left else 810, 530, 140, 180)
	var texture := friendly_portrait if friendly else enemy_portrait
	if texture != null:
		draw_texture_rect(texture, portrait, false)
	else:
		var side := PORTRAIT_ART.get_height()
		var crop_width := side * portrait.size.x / portrait.size.y
		draw_texture_rect_region(PORTRAIT_ART, portrait,
			Rect2(index * side + (side - crop_width) * 0.5, 0, crop_width, side))
	draw_rect(portrait.grow(3), Color("682b29"), false, 5)
	draw_rect(portrait.grow(1), Color("c69a56"), false, 2)

	var bar := Rect2(166 if left else 560, 579, 234, 12)
	draw_rect(bar.grow(2), Color("43242c"))
	draw_rect(bar, Color("543744"))
	var width := bar.size.x * clampf(general.health / general.max_health, 0.0, 1.0)
	var fill := Rect2(bar.position.x if left else bar.end.x - width, bar.position.y, width, bar.size.y)
	draw_rect(fill, Color("bd5b67"))
	draw_rect(Rect2(fill.position, Vector2(width, 3)), Color("f3a6a3"))

	var font := ThemeDB.fallback_font
	var stats := "体力 %d/%d   兵力 %d" % [
		ceili(maxf(general.health, 0.0)), int(general.max_health),
		army_size - int(general.health > 0.0),
	]
	draw_string(font, Vector2(bar.position.x, 609), stats,
		HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT,
		bar.size.x, 15, Color("f3dba5"))


func _check_result() -> void:
	if unity_rules != null:
		if blue_general_order == Order.RETREAT and blue_general.position.x <= FIELD_MIN.x + 6.0:
			_finish_battle(false)
			return
		if red_general_order == Order.RETREAT and red_general.position.x >= FIELD_MAX.x - 6.0:
			_finish_battle(true)
			return
	if blue_units.is_empty() or (unity_rules != null and blue_general.health <= 0.0):
		_finish_battle(false)
	elif red_units.is_empty() or (unity_rules != null and red_general.health <= 0.0):
		_finish_battle(true)


func _finish_battle(victory: bool) -> void:
	battle_over = true
	if campaign_battle:
		battle_finished.emit(victory, blue_units.size() - int(blue_general.health > 0.0),
			red_units.size() - int(red_general.health > 0.0))
	else:
		result_label.text = "%s\n按 R 再来一局" % ("胜利" if victory else "战败")
		result_label.show()


func _set_blue_order(order: Order) -> void:
	if battle_over or (unity_rules != null and blue_general_order == Order.RETREAT):
		return
	blue_order = order
	if unity_rules != null:
		for unit in blue_units:
			unit.erase("order")
			unit.erase("move_to")
		if order == Order.RETREAT:
			blue_general_order = Order.RETREAT
	_update_ui()


func _update_enemy_command(delta: float) -> void:
	if enemy_phase >= 2:
		return
	enemy_command_time -= delta
	if enemy_command_time > 0.0:
		return
	if enemy_phase == 0:
		if (red_general.health < 20.0 and red_units.size() - 1 < 10
				and (blue_general.health > 50.0 or blue_units.size() - 1 > 10)
				and blue_general_order != Order.RETREAT):
			red_order = Order.RETREAT
			red_general_order = Order.RETREAT
			enemy_phase = 2
			return
		red_order = Order.ADVANCE
		enemy_command_time = float(randi_range(2, 9))
		enemy_phase = 1
		if red_units.size() > 1:
			assault_ordered.emit(false)
	else:
		red_general_order = Order.ADVANCE
		enemy_phase = 2


func _add_unity_orders() -> void:
	var speed := _battle_button(self, "加速", Rect2(442.5, 39, 75, 45))
	speed.pressed.connect(func() -> void:
		battle_speed = 1 if battle_speed == 2 else 2
		speed.text = "加速" if battle_speed == 1 else "正常")
	unity_commands = Control.new()
	unity_commands.visible = false
	add_child(unity_commands)
	for image_data in [
		[preload("res://assets/unity_reference/380-1.png"), Rect2(685.5, 1.5, 273, 87), Rect2(690.75, 7.5, 262.5, 75)],
		[preload("res://assets/unity_reference/274-1.png"), Rect2(685.5, 91.5, 273, 426), Rect2(690.75, 96, 262.5, 417)]]:
		var fill := ColorRect.new()
		fill.color = Color8(0, 8, 90, 128)
		fill.position = image_data[2].position
		fill.size = image_data[2].size
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unity_commands.add_child(fill)
		var art := TextureRect.new()
		art.texture = image_data[0]
		art.position = image_data[1].position
		art.size = image_data[1].size
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unity_commands.add_child(art)
	var names := ["前军前进", "前军后退", "左右分散", "中央集中", "全军待机",
		"全军突击", "武 将 技", "武将出击", "全军撤退"]
	for index in names.size():
		var button := _battle_button(unity_commands, names[index], Rect2(685.5, 99 + index * 45, 273, 42), true)
		button.pressed.connect(_on_unity_command.bind(index))
		unity_command_buttons.append(button)
	_battle_button(unity_commands, "返回", Rect2(861, 636, 75, 45)).pressed.connect(_close_unity_commands)


func _battle_button(parent: Node, caption: String, area: Rect2, flat := false) -> Button:
	var button := Button.new()
	button.text = caption
	button.flat = flat
	button.position = area.position
	button.size = area.size
	button.add_theme_font_override("font", source_font)
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_color_override("font_hover_color", Color.GREEN)
	if not flat:
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color8(0, 8, 90, 128)
		frame.border_color = Color8(140, 124, 67)
		frame.set_border_width_all(2)
		button.add_theme_stylebox_override("normal", frame)
		button.add_theme_stylebox_override("hover", frame)
		button.add_theme_stylebox_override("pressed", frame)
	parent.add_child(button)
	return button


func _show_unity_commands() -> void:
	if battle_over or presentation_paused:
		return
	commands_open = true
	unity_commands.show()
	for index in unity_command_buttons.size():
		unity_command_buttons[index].disabled = blue_general_order == Order.RETREAT or (index < 6 and blue_units.size() <= 1)
	unity_command_buttons[6].disabled = not _can_cast(blue_general)
	if spell_picker != null:
		var available := false
		var popup := spell_picker.get_popup()
		for item in popup.item_count:
			var allowed := _can_cast(blue_general, popup.get_item_id(item))
			popup.set_item_disabled(item, not allowed)
			available = available or allowed
		spell_picker.disabled = not available


func _close_unity_commands() -> void:
	commands_open = false
	unity_commands.hide()


func _on_unity_command(index: int) -> void:
	if index < 4:
		_apply_unity_order(index)
	elif index == 4:
		_set_blue_order(Order.HOLD)
	elif index == 5:
		_set_blue_order(Order.ADVANCE)
	elif index == 6:
		_cast_skill()
	elif index == 7:
		_apply_unity_order(4)
	else:
		_set_blue_order(Order.RETREAT)
	_close_unity_commands()
	if index == 5:
		assault_ordered.emit(true)


func _add_spell_selection() -> void:
	var learned: Array[int] = blue_general["spells"]
	if learned.size() < 2:
		return
	spell_picker = MenuButton.new()
	spell_picker.text = "武 将 技"
	spell_picker.flat = true
	spell_picker.position = unity_command_buttons[6].position
	spell_picker.size = unity_command_buttons[6].size
	spell_picker.add_theme_font_override("font", source_font)
	spell_picker.add_theme_font_size_override("font_size", 30)
	unity_commands.add_child(spell_picker)
	unity_command_buttons[6].hide()
	var popup := spell_picker.get_popup()
	for id in learned:
		var label: String = unity_rules.spells[id]["name"]
		popup.add_item(label, id)
		popup.set_item_disabled(popup.item_count - 1, not UNITY_RULES.supports_spell(id))
	popup.id_pressed.connect(_select_spell)


func _select_spell(id: int) -> void:
	blue_general["spell"] = id
	_cast_skill()
	_close_unity_commands()
	_update_ui()


func _apply_unity_order(command: int) -> void:
	if battle_over or blue_general_order == Order.RETREAT:
		return
	if command == 4:
		blue_general_order = Order.ADVANCE
		return
	var rank := 0
	for unit in blue_units:
		if not unit.get("front", false):
			continue
		unit.erase("move_to")
		if command < 2:
			unit["order"] = Order.ADVANCE if command == 0 else Order.RETREAT
		else:
			@warning_ignore("integer_division")
			var column := rank / 2
			var y := 320.0
			if command == 2:
				y += 74.5 if rank % 2 == 0 else -74.5
			unit["move_to"] = Vector2(180.0 + column * 6.0, y)
			unit["order"] = Order.HOLD
		rank += 1


func _update_ui() -> void:
	clock_label.text = "%d 秒" % (maxi(0, 99 - int(battle_seconds)) if unity_rules != null else int(battle_seconds))
	var skill_status := "就绪"
	if blue_general.health <= 0.0:
		skill_status = "%s已倒下" % friendly_name
	elif skill_cooldown > 0.0:
		skill_status = "%d 秒" % ceili(skill_cooldown)
	order_label.text = "军令 · %s" % _order_name(blue_order)
	skill_button.text = "4  %s · %s" % ["青龙斩" if friendly_name == "关羽" else "武将技", skill_status]
	if unity_rules != null:
		var spell: Dictionary = unity_rules.spells.get(blue_general["spell"], {})
		skill_button.text = "4  %s · 技力 %d · 蓄力 %d%%" % [
			spell.get("name", "武将技"), blue_general["mana"], int(blue_general["charge"] / 1.32)]
		if not UNITY_RULES.supports_spell(blue_general["spell"]):
			skill_button.text = "%s · 待移植" % spell.get("name", "武将技")
		skill_button.disabled = battle_over or not _can_cast(blue_general)
		return
	skill_button.disabled = battle_over or blue_general.health <= 0.0 or skill_cooldown > 0.0


func _order_name(order: Order) -> String:
	match order:
		Order.ADVANCE:
			return "全军前进"
		Order.HOLD:
			return "原地待命"
		Order.RETREAT:
			return "全军后退"
	return "未知"


func _on_advance_pressed() -> void:
	_set_blue_order(Order.ADVANCE)


func _on_hold_pressed() -> void:
	_set_blue_order(Order.HOLD)


func _on_retreat_pressed() -> void:
	_set_blue_order(Order.RETREAT)
