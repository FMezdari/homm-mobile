extends Node

# ArmyManager — Gère les opérations sur les armées (ajout, retrait, transfert)

signal army_changed(hero_index: int)

func add_unit_to_hero(hero_index: int, unit_id: String, count: int) -> bool:
	var heroes = GameData.heroes
	if hero_index < 0 or hero_index >= heroes.size():
		return false
	var hero = heroes[hero_index]
	if not GameData.UNIT_TYPES.has(unit_id):
		return false
	hero.army.add_stack(unit_id, count)
	army_changed.emit(hero_index)
	return true

func remove_unit_from_hero(hero_index: int, stack_index: int) -> bool:
	var heroes = GameData.heroes
	if hero_index < 0 or hero_index >= heroes.size():
		return false
	var hero = heroes[hero_index]
	if stack_index < 0 or stack_index >= hero.army.stacks.size():
		return false
	hero.army.remove_stack(stack_index)
	army_changed.emit(hero_index)
	return true

func get_hero_army(hero_index: int) -> GameData.Army:
	if hero_index >= 0 and hero_index < GameData.heroes.size():
		return GameData.heroes[hero_index].army
	return null

func get_army_summary(hero_index: int) -> String:
	var army = get_hero_army(hero_index)
	if not army or army.stacks.is_empty():
		return "Armée vide"
	var parts: Array[String] = []
	for s in army.stacks:
		parts.append("%s x%d" % [s.get_name(), s.get_alive_count()])
	return ", ".join(parts)

func get_army_total_power(hero_index: int) -> int:
	var army = get_hero_army(hero_index)
	if not army:
		return 0
	var power = 0
	for s in army.stacks:
		if s.is_alive():
			power += s.count * (s.get_attack() + s.get_defense() + s.get_damage_max())
	return power

func give_starting_army(hero_index: int) -> void:
	var heroes = GameData.heroes
	if hero_index < 0 or hero_index >= heroes.size():
		return
	var hero = heroes[hero_index]
	hero.army = GameData.Army.new()
	hero.army.add_stack("ashigaru", 15)
	hero.army.add_stack("samurai", 5)
	hero.army.add_stack("archer", 8)
	army_changed.emit(hero_index)

func generate_enemy_army(difficulty: int, wave: int = 1) -> GameData.Army:
	var army = GameData.Army.new()
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var enemy_units: Array[String] = ["goblin", "skeleton", "bandit"]
	if difficulty >= 1 or wave > 2:
		enemy_units.append_array(["oni_brute", "oni_mage"])
	var count = rng.randi_range(2, 4)
	var used: Array[String] = []
	for i in range(count):
		var unit_id = enemy_units[rng.randi() % enemy_units.size()]
		if used.has(unit_id) and rng.randf() < 0.4 and enemy_units.size() > 1:
			while true:
				var alt = enemy_units[rng.randi() % enemy_units.size()]
				if alt != unit_id:
					unit_id = alt
					break
		used.append(unit_id)
		var stack_count = rng.randi_range(4 + wave * 2, 8 + wave * 4) + difficulty * 3
		army.add_stack(unit_id, stack_count)
	return army
