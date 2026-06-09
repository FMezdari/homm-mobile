extends Node

# Singleton pour partager des données entre scènes

var should_load_save: bool = false
var hero_name: String = "Samurai"
var difficulty: int = 0

enum Difficulty { EASY, MEDIUM, HARD }

var difficulty_labels: Dictionary = {
	Difficulty.EASY: "Facile",
	Difficulty.MEDIUM: "Moyen",
	Difficulty.HARD: "Difficile",
}

# -------------------------------------------------
# CONSTANTES — Types d'unités
# -------------------------------------------------
const UNIT_TYPES: Dictionary = {
	"ashigaru":     {"name":"Ashigaru",     "speed":4, "attack":4,  "defense":3, "dmg_min":1, "dmg_max":3, "hp":8,  "cost_gold":30,  "cost_wood":0,  "cost_ore":0,  "tier":1, "faction":"human", "is_ranged":false, "sprite":"ashigaru", "hex_size":1},
	"samurai":      {"name":"Samouraï",     "speed":6, "attack":8,  "defense":6, "dmg_min":3, "dmg_max":6, "hp":15, "cost_gold":100, "cost_wood":10, "cost_ore":0,  "tier":2, "faction":"human", "is_ranged":false, "sprite":"samurai", "hex_size":1},
	"archer":       {"name":"Archer",       "speed":5, "attack":6,  "defense":2, "dmg_min":2, "dmg_max":5, "hp":10, "cost_gold":60,  "cost_wood":20, "cost_ore":0,  "tier":1, "faction":"human", "is_ranged":true,  "sprite":"archer", "hex_size":1},
	"yari":         {"name":"Yari (Piquier)","speed":4, "attack":5,  "defense":5, "dmg_min":2, "dmg_max":4, "hp":12, "cost_gold":45,  "cost_wood":5,  "cost_ore":5,  "tier":1, "faction":"human", "is_ranged":false, "sprite":"yari", "hex_size":1},
	"cavalier":     {"name":"Cavalier",     "speed":8, "attack":9,  "defense":5, "dmg_min":4, "dmg_max":8, "hp":18, "cost_gold":150, "cost_wood":0,  "cost_ore":15, "tier":2, "faction":"human", "is_ranged":false, "sprite":"cavalier", "hex_size":2},
	"ninja":        {"name":"Ninja",        "speed":9, "attack":10, "defense":3, "dmg_min":5, "dmg_max":10,"hp":13, "cost_gold":200, "cost_wood":30, "cost_ore":10, "tier":2, "faction":"human", "is_ranged":false, "sprite":"ninja", "hex_size":1},
	"monk":         {"name":"Moine",        "speed":5, "attack":4,  "defense":4, "dmg_min":2, "dmg_max":5, "hp":14, "cost_gold":80,  "cost_wood":0,  "cost_ore":0,  "tier":2, "faction":"human", "is_ranged":false, "sprite":"monk", "hex_size":1, "heals":true},
	"onmyoji":      {"name":"Onmyōji",      "speed":7, "attack":7,  "defense":2, "dmg_min":3, "dmg_max":7, "hp":10, "cost_gold":120, "cost_wood":15, "cost_ore":20, "tier":2, "faction":"human", "is_ranged":true,  "sprite":"onmyoji", "hex_size":1, "magic":true},
	"oni":          {"name":"Oni",          "speed":3, "attack":12, "defense":10,"dmg_min":6, "dmg_max":12,"hp":30, "cost_gold":300, "cost_wood":40, "cost_ore":50, "tier":3, "faction":"human", "is_ranged":false, "sprite":"oni", "hex_size":2},
	"daimyo":       {"name":"Daimyo",       "speed":7, "attack":14, "defense":8, "dmg_min":7, "dmg_max":14,"hp":25, "cost_gold":500, "cost_wood":60, "cost_ore":40, "tier":3, "faction":"human", "is_ranged":false, "sprite":"daimyo", "hex_size":1},
	"sohei":        {"name":"Sōhei",        "speed":6, "attack":9,  "defense":7, "dmg_min":4, "dmg_max":9, "hp":22, "cost_gold":180, "cost_wood":20, "cost_ore":20, "tier":2, "faction":"human", "is_ranged":false, "sprite":"sohei", "hex_size":1},
	"goblin":       {"name":"Gobelin",      "speed":5, "attack":3,  "defense":2, "dmg_min":1, "dmg_max":3, "hp":6,  "cost_gold":20,  "cost_wood":0,  "cost_ore":0,  "tier":1, "faction":"monster","is_ranged":false, "sprite":"goblin", "hex_size":1},
	"skeleton":     {"name":"Squelette",    "speed":4, "attack":4,  "defense":4, "dmg_min":1, "dmg_max":4, "hp":8,  "cost_gold":25,  "cost_wood":0,  "cost_ore":0,  "tier":1, "faction":"monster","is_ranged":false, "sprite":"skeleton", "hex_size":1},
	"oni_brute":    {"name":"Oni Brute",    "speed":3, "attack":14, "defense":12,"dmg_min":7, "dmg_max":14,"hp":35, "cost_gold":400, "cost_wood":0,  "cost_ore":0,  "tier":3, "faction":"monster","is_ranged":false, "sprite":"oni", "hex_size":2},
	"bandit":       {"name":"Bandit",       "speed":6, "attack":5,  "defense":3, "dmg_min":2, "dmg_max":4, "hp":9,  "cost_gold":35,  "cost_wood":0,  "cost_ore":0,  "tier":1, "faction":"monster","is_ranged":false, "sprite":"bandit", "hex_size":1},
	"oni_mage":     {"name":"Oni Mage",     "speed":5, "attack":8,  "defense":3, "dmg_min":4, "dmg_max":9, "hp":14, "cost_gold":200, "cost_wood":0,  "cost_ore":0,  "tier":2, "faction":"monster","is_ranged":true,  "sprite":"oni_mage", "hex_size":1, "magic":true},
}

# -------------------------------------------------
# CONSTANTES — Bâtiments de ville
# -------------------------------------------------
const CITY_BUILDINGS: Dictionary = {
	# name, cost_gold, cost_wood, cost_ore, unlocks_unit, description, required_building
	"caserne":       {"name":"Caserne",       "cost_gold":100, "cost_wood":30, "cost_ore":20,  "unlocks_unit":"ashigaru",  "desc":"Entraîne des Ashigaru", "required":""},
	"dojo":          {"name":"Dojo",          "cost_gold":200, "cost_wood":50, "cost_ore":30,  "unlocks_unit":"samurai",   "desc":"Entraîne des Samouraïs", "required":"caserne"},
	"tour_de_guet":  {"name":"Tour de Guet",  "cost_gold":150, "cost_wood":40, "cost_ore":20,  "unlocks_unit":"archer",    "desc":"Entraîne des Archers", "required":"caserne"},
	"ecurie":        {"name":"Écurie",        "cost_gold":300, "cost_wood":80, "cost_ore":50,  "unlocks_unit":"cavalier",  "desc":"Entraîne des Cavaliers", "required":"dojo"},
	"dojo_ninja":    {"name":"Dojo Ninja",    "cost_gold":350, "cost_wood":70, "cost_ore":60,  "unlocks_unit":"ninja",     "desc":"Entraîne des Ninjas", "required":"tour_de_guet"},
	"temple":        {"name":"Temple",        "cost_gold":200, "cost_wood":60, "cost_ore":40,  "unlocks_unit":"monk",      "desc":"Entraîne des Moines", "required":"dojo"},
	"sanctuaire":    {"name":"Sanctuaire",    "cost_gold":400, "cost_wood":90, "cost_ore":80,  "unlocks_unit":"onmyoji",   "desc":"Entraîne des Onmyōji", "required":"temple"},
	"forteresse":    {"name":"Forteresse",    "cost_gold":500, "cost_wood":100,"cost_ore":120, "unlocks_unit":"oni",       "desc":"Invoque des Oni", "required":"ecurie"},
	"palais":        {"name":"Palais",        "cost_gold":800, "cost_wood":150,"cost_ore":100, "unlocks_unit":"daimyo",    "desc":"Au service du Daimyo", "required":"forteresse"},
	"arsenal":       {"name":"Arsenal",       "cost_gold":250, "cost_wood":50, "cost_ore":80,  "unlocks_unit":"sohei",     "desc":"Entraîne des Sōhei", "required":"dojo"},
	"entrepot":      {"name":"Entrepôt",      "cost_gold":100, "cost_wood":40, "cost_ore":20,  "unlocks_unit":"",          "desc":"+10 Or/jour", "required":""},
	"marché":        {"name":"Marché",        "cost_gold":200, "cost_wood":30, "cost_ore":30,  "unlocks_unit":"",          "desc":"+5 Bois et Minerai/jour", "required":""},
}

# -------------------------------------------------
# Unit stack: a group of identical units
# -------------------------------------------------
class UnitStack:
	var unit_id: String           # key in UNIT_TYPES
	var count: int                # number of units in stack
	var current_hp: int           # total HP of the stack
	var max_hp_per_unit: int      # HP per single unit
	
	func _init(p_unit_id: String, p_count: int):
		unit_id = p_unit_id
		count = p_count
		var base = GameData.UNIT_TYPES.get(unit_id, {})
		max_hp_per_unit = base.get("hp", 10)
		current_hp = max_hp_per_unit * count
	
	func get_base() -> Dictionary:
		return GameData.UNIT_TYPES.get(unit_id, {})
	
	func get_name() -> String:
		return get_base().get("name", unit_id)
	
	func get_attack() -> int:
		return get_base().get("attack", 1)
	
	func get_defense() -> int:
		return get_base().get("defense", 1)
	
	func get_speed() -> int:
		return get_base().get("speed", 5)
	
	func get_damage_min() -> int:
		return get_base().get("dmg_min", 1)
	
	func get_damage_max() -> int:
		return get_base().get("dmg_max", 1)
	
	func get_alive_count() -> int:
		return max(0, ceili(float(current_hp) / max_hp_per_unit))
	
	func get_current_hp_display() -> int:
		return max(0, current_hp)
	
	func get_max_hp_display() -> int:
		return max_hp_per_unit * count
	
	func is_alive() -> bool:
		return current_hp > 0 and count > 0
	
	func take_damage(damage: int) -> int:
		current_hp = max(0, current_hp - damage)
		var previous_count = count
		count = max(0, ceili(float(current_hp) / max_hp_per_unit))
		return previous_count - count  # units killed
	
	func heal(amount: int) -> int:
		var max_total = max_hp_per_unit * count
		var before = current_hp
		current_hp = mini(max_total, current_hp + amount)
		return current_hp - before
	
	func serialize() -> Dictionary:
		return {"unit_id": unit_id, "count": count, "current_hp": current_hp}
	
	static func deserialize(data: Dictionary) -> UnitStack:
		var stack = UnitStack.new(data.get("unit_id", ""), data.get("count", 0))
		stack.current_hp = data.get("current_hp", stack.current_hp)
		return stack

# -------------------------------------------------
# Army: owned by a hero
# -------------------------------------------------
class Army:
	var stacks: Array[UnitStack] = []
	
	func _init(initial_stacks: Array[Dictionary] = []):
		for s in initial_stacks:
			add_stack(s.get("unit_id", ""), s.get("count", 1))
	
	func add_stack(unit_id: String, count: int) -> void:
		if stacks.size() >= 7:
			return
		if unit_id.is_empty() or count <= 0:
			return
		for stack in stacks:
			if stack.unit_id == unit_id:
				stack.count += count
				stack.current_hp += stack.max_hp_per_unit * count
				return
		stacks.append(UnitStack.new(unit_id, count))
	
	func remove_stack(index: int) -> void:
		if index >= 0 and index < stacks.size():
			stacks.remove_at(index)
	
	func get_total_count() -> int:
		var total = 0
		for s in stacks:
			total += s.count
		return total
	
	func is_alive() -> bool:
		for s in stacks:
			if s.is_alive():
				return true
		return false
	
	func get_alive_stacks() -> Array[UnitStack]:
		var alive: Array[UnitStack] = []
		for s in stacks:
			if s.is_alive():
				alive.append(s)
		return alive
	
	func serialize() -> Array:
		var result: Array = []
		for s in stacks:
			result.append(s.serialize())
		return result
	
	static func deserialize(data: Array) -> Army:
		var army = Army.new()
		for d in data:
			army.stacks.append(UnitStack.deserialize(d))
		return army

# -------------------------------------------------
# STRUCTURES DE JEU EXISTANTES (améliorées)
# -------------------------------------------------
class Creature:
	var name: String
	var amount: int

class Hero:
	var id: int
	var name: String
	var sprite: Texture2D
	var position: Vector2i       # coordonnées tile (x, y)
	var owner: int               # id du joueur
	var creatures: Array = []
	var army: Army = Army.new()  # NOUVEAU

class City:
	var id: int
	var name: String
	var position: Vector2i
	var owner: int
	var resource_type: String
	var resource_per_day: int
	var creatures: Array = []
	var buildings: Array[String] = []  # NOUVEAU: buildings built in this city
	var weekly_growth: Dictionary = {} # NOUVEAU: unit_id -> weekly growth

class Building:
	var id: int
	var type: String
	var position: Vector2i
	var owner: int
	var resource_type: String = ""
	var resource_per_day: int = 0

# Collections
var heroes: Array[Hero] = []
var cities: Array[City] = []
var buildings: Array[Building] = []

# Boss tracking
var bosses_defeated: int = 0
var unlocked_heroes: Array = []  # list of additional hero names/ids available in combat

# LLM / Player history tracking
var enemies_killed: int = 0
var enemies_spared: int = 0
var quests_completed: int = 0
var recent_actions: Array[String] = []

var creatures_on_tile: Dictionary = {}   # clé = Vector2i, valeur = Creature


# Couleurs des joueurs
var player_colors: Array[Color] = [
	Color.RED,
	Color.BLUE,
	Color.GREEN,
	Color.YELLOW
]

# Sélection courante
enum SelectionMode { NONE, HERO, CITY, BUILDING, TILE }
var current_mode: SelectionMode = SelectionMode.NONE

# Signals
signal selection_changed(mode, id, tile)
signal turn_ended(counter, max)
signal move_requested(hero, dest)
signal hero_switch_requested(index)

# Turn counter (displayed in DBI/DBT)
var turn_counter: int = 0
var max_turns: int = 30

# Current selection details
var current_id: int = -1
var current_tile: Vector2i = Vector2i.ZERO

func set_selection(mode: SelectionMode, id: int = -1, tile: Vector2i = Vector2i.ZERO) -> void:
	current_mode = mode
	current_id = id
	current_tile = tile
	emit_signal("selection_changed", mode, id, tile)

func end_turn() -> void:
	turn_counter += 1
	emit_signal("turn_ended", turn_counter, max_turns)
	set_selection(SelectionMode.NONE)

func save_game() -> void:
	var file = FileAccess.open("user://game_data_state.json", FileAccess.WRITE)
	if file == null:
		push_error("Impossible d'ouvrir le fichier de sauvegarde en écriture.")
		return
	var data = {
		"player_name": hero_name,
		"turn_counter": turn_counter,
		"difficulty": difficulty,
		"heroes": [],
		"cities": [],
		"buildings": [],
		"creatures_on_tile": [],
		"enemies_killed": enemies_killed,
		"enemies_spared": enemies_spared,
		"recent_actions": recent_actions.duplicate()
	}
	for h in heroes:
		data["heroes"].append({
			"id": h.id,
			"name": h.name,
			"owner": h.owner,
			"position": [h.position.x, h.position.y],
			"army": h.army.serialize()
		})
	for c in cities:
		data["cities"].append({
			"id": c.id,
			"name": c.name,
			"owner": c.owner,
			"position": [c.position.x, c.position.y],
			"resource_type": c.resource_type,
			"resource_per_day": c.resource_per_day,
			"buildings": c.buildings.duplicate(),
			"weekly_growth": c.weekly_growth.duplicate()
		})
	for b in buildings:
		data["buildings"].append({
			"id": b.id,
			"type": b.type,
			"owner": b.owner,
			"position": [b.position.x, b.position.y],
			"resource_type": b.resource_type,
			"resource_per_day": b.resource_per_day
		})
	for tile_pos in creatures_on_tile:
		var creature = creatures_on_tile[tile_pos]
		data["creatures_on_tile"].append({
			"position": [tile_pos.x, tile_pos.y],
			"name": creature.name,
			"amount": creature.amount
		})
	var json = JSON.stringify(data)
	file.store_string(json)
	file.close()


func load_game() -> void:
	if not FileAccess.file_exists("user://game_data_state.json"):
		push_warning("Aucune sauvegarde trouvée.")
		return
	var file = FileAccess.open("user://game_data_state.json", FileAccess.READ)
	if file == null:
		push_error("Impossible d'ouvrir le fichier de sauvegarde en lecture.")
		return
	var json_text = file.get_as_text()
	file.close()
	var json_parser = JSON.new()
	var result = json_parser.parse(json_text)
	if result.error != OK:
		push_error("Erreur de parsing JSON de sauvegarde : %s" % result.error_string)
		return
	var data = result.result
	hero_name = data.get("player_name", "Samurai")
	difficulty = data.get("difficulty", 0)
	enemies_killed = data.get("enemies_killed", 0)
	enemies_spared = data.get("enemies_spared", 0)
	var loaded_actions: Array = data.get("recent_actions", [])
	recent_actions.clear()
	for a in loaded_actions:
		recent_actions.append(str(a))
	heroes.clear()
	for h_data in data.get("heroes", []):
		var h = Hero.new()
		h.id = h_data.get("id", -1)
		h.name = h_data.get("name", "")
		h.owner = h_data.get("owner", 0)
		var pos = h_data.get("position", [0,0])
		h.position = Vector2i(pos[0], pos[1])
		var army_data: Array = h_data.get("army", [])
		if army_data.size() > 0:
			h.army = Army.deserialize(army_data)
		heroes.append(h)
	cities.clear()
	for c_data in data.get("cities", []):
		var c = City.new()
		c.id = c_data.get("id", -1)
		c.name = c_data.get("name", "")
		c.owner = c_data.get("owner", 0)
		var pos = c_data.get("position", [0,0])
		c.position = Vector2i(pos[0], pos[1])
		c.resource_type = c_data.get("resource_type", "")
		c.resource_per_day = c_data.get("resource_per_day", 0)
		c.buildings = c_data.get("buildings", []).duplicate()
		c.weekly_growth = c_data.get("weekly_growth", {}).duplicate()
		cities.append(c)
	buildings.clear()
	for b_data in data.get("buildings", []):
		var b = Building.new()
		b.id = b_data.get("id", -1)
		b.type = b_data.get("type", "")
		b.owner = b_data.get("owner", 0)
		var pos = b_data.get("position", [0,0])
		b.position = Vector2i(pos[0], pos[1])
		b.resource_type = b_data.get("resource_type", "")
		b.resource_per_day = b_data.get("resource_per_day", 0)
		buildings.append(b)
	creatures_on_tile.clear()
	for c_data in data.get("creatures_on_tile", []):
		var pos = c_data.get("position", [0, 0])
		var tile_pos = Vector2i(pos[0], pos[1])
		var creature = Creature.new()
		creature.name = c_data.get("name", "")
		creature.amount = c_data.get("amount", 0)
		creatures_on_tile[tile_pos] = creature

func track_action(action_text: String) -> void:
	recent_actions.append(action_text)
	if recent_actions.size() > 20:
		recent_actions.pop_front()


func get_player_history_dict(hero_level: int = 1, hero_hp: int = 50, hero_attack: int = 10, hero_defense: int = 5, gold: int = 0) -> Dictionary:
	return {
		"hero_name": hero_name,
		"enemies_killed": enemies_killed,
		"enemies_spared": enemies_spared,
		"bosses_defeated": bosses_defeated,
		"hero_level": hero_level,
		"hero_hp": hero_hp,
		"hero_attack": hero_attack,
		"hero_defense": hero_defense,
		"gold": gold,
		"quests_completed": quests_completed,
		"recent_actions": recent_actions.duplicate(),
	}


func get_units_for_city(city: City) -> Array[Dictionary]:
	"""Returns list of units available for recruitment in this city based on buildings built"""
	var available: Array[Dictionary] = []
	for b_id in city.buildings:
		var b_info = CITY_BUILDINGS.get(b_id, {})
		var unit_id = b_info.get("unlocks_unit", "")
		if not unit_id.is_empty() and not _unit_already_in_list(available, unit_id):
			var unit_info = UNIT_TYPES.get(unit_id, {}).duplicate()
			unit_info["unit_id"] = unit_id
			unit_info["weekly_growth"] = city.weekly_growth.get(unit_id, 0)
			available.append(unit_info)
	return available

func _unit_already_in_list(list: Array[Dictionary], unit_id: String) -> bool:
	for entry in list:
		if entry.get("unit_id", "") == unit_id:
			return true
	return false

func generate_weekly_growth(city: City) -> Dictionary:
	"""Generate weekly growth for all unlocked units in a city"""
	var growth: Dictionary = {}
	for b_id in city.buildings:
		var b_info = CITY_BUILDINGS.get(b_id, {})
		var unit_id = b_info.get("unlocks_unit", "")
		if not unit_id.is_empty():
			var base = UNIT_TYPES.get(unit_id, {})
			var tier = base.get("tier", 1)
			var base_growth = ([8, 5, 2] as Array)[mini(tier - 1, 2)]
			growth[unit_id] = base_growth + randi() % 3
	return growth

func _ready() -> void:
	if should_load_save:
		load_game()
	else:
		heroes.clear()
		cities.clear()
		buildings.clear()
		creatures_on_tile.clear()

func _exit_tree() -> void:
	save_game()
