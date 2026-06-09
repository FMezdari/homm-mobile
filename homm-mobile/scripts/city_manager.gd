extends CanvasLayer

# CityManager — Écran de ville : bâtiments et recrutement

signal city_closed()
signal building_constructed(city_id: int, building_id: String)
signal units_recruited(city_id: int, unit_id: String, count: int)

var _city_id: int = -1
var _panel: Panel
var _title_label: Label
var _buildings_container: VBoxContainer
var _recruit_container: VBoxContainer
var _resources_label: Label
var _gold: int = 0
var _wood: int = 0
var _ore: int = 0

const PANEL_STYLE := preload("res://scripts/japanese_ui_theme.gd")

func _ready() -> void:
	visible = false

func open_city(city_id: int, gold: int, wood: int, ore: int) -> void:
	_city_id = city_id
	_gold = gold
	_wood = wood
	_ore = ore
	_build_ui()
	visible = true

func _build_ui() -> void:
	if _panel:
		_panel.queue_free()
	
	var vp = get_viewport().get_visible_rect().size
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.07, 0.97)
	style.border_color = Color(0.50, 0.38, 0.20)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var city = _get_city()
	if not city:
		return

	_title_label = Label.new()
	_title_label.text = city.name
	_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.75, 0.18))
	_title_label.custom_minimum_size = Vector2(0, 60)
	_panel.add_child(_title_label)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.position = Vector2(-50, 10)
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.30, 0.30))
	close_btn.pressed.connect(_close)
	_panel.add_child(close_btn)

	_resources_label = Label.new()
	_resources_label.position = Vector2(20, 60)
	_resources_label.add_theme_font_size_override("font_size", 14)
	_resources_label.add_theme_color_override("font_color", Color(0.80, 0.78, 0.72))
	_panel.add_child(_resources_label)
	_update_resources_display()

	var tab_container = TabContainer.new()
	tab_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_container.offset_top = 100
	tab_container.offset_bottom = 20
	tab_container.offset_left = 10
	tab_container.offset_right = -10
	_panel.add_child(tab_container)

	_buildings_container = VBoxContainer.new()
	_buildings_container.name = "Bâtiments"
	tab_container.add_child(_buildings_container)
	_fill_buildings_tab(city)

	_recruit_container = VBoxContainer.new()
	_recruit_container.name = "Recrutement"
	tab_container.add_child(_recruit_container)
	_fill_recruit_tab(city)

func _fill_buildings_tab(city: GameData.City) -> void:
	for child in _buildings_container.get_children():
		child.queue_free()
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_buildings_container.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var built_count = 0
	var available_count = 0
	for b_id in GameData.CITY_BUILDINGS.keys():
		var b_info = GameData.CITY_BUILDINGS[b_id]
		var is_built = city.buildings.has(b_id)
		var can_build = _can_build(city, b_id)
		
		built_count += 1 if is_built else 0
		if not is_built:
			available_count += 1
		
		var card = Panel.new()
		card.custom_minimum_size = Vector2(0, 80)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_style = StyleBoxFlat.new()
		if is_built:
			card_style.bg_color = Color(0.08, 0.12, 0.08, 0.90)
			card_style.border_color = Color(0.20, 0.50, 0.20)
		elif can_build:
			card_style.bg_color = Color(0.10, 0.08, 0.06, 0.90)
			card_style.border_color = Color(0.50, 0.40, 0.25)
		else:
			card_style.bg_color = Color(0.08, 0.06, 0.06, 0.90)
			card_style.border_color = Color(0.30, 0.25, 0.18)
		card_style.border_width_left = 1
		card_style.border_width_right = 1
		card_style.border_width_top = 1
		card_style.border_width_bottom = 2
		card_style.corner_radius_top_left = 6
		card_style.corner_radius_top_right = 6
		card_style.corner_radius_bottom_left = 6
		card_style.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("panel", card_style)
		vbox.add_child(card)

		var name_label = Label.new()
		name_label.position = Vector2(10, 6)
		name_label.text = b_info["name"]
		name_label.add_theme_font_size_override("font_size", 16)
		if is_built:
			name_label.add_theme_color_override("font_color", Color(0.30, 0.75, 0.30))
		elif can_build:
			name_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
		else:
			name_label.add_theme_color_override("font_color", Color(0.50, 0.48, 0.42))
		card.add_child(name_label)

		var desc_label = Label.new()
		desc_label.position = Vector2(10, 28)
		desc_label.text = b_info["desc"]
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.add_theme_color_override("font_color", Color(0.70, 0.68, 0.62))
		card.add_child(desc_label)

		if is_built:
			var built_label = Label.new()
			built_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			built_label.position = Vector2(-80, 30)
			built_label.text = "✓ Construit"
			built_label.add_theme_font_size_override("font_size", 12)
			built_label.add_theme_color_override("font_color", Color(0.30, 0.75, 0.30))
			card.add_child(built_label)
		elif can_build:
			var cost_str = "💰" + str(b_info["cost_gold"])
			if b_info["cost_wood"] > 0:
				cost_str += " 🪵" + str(b_info["cost_wood"])
			if b_info["cost_ore"] > 0:
				cost_str += " ⛏" + str(b_info["cost_ore"])

			var cost_label = Label.new()
			cost_label.position = Vector2(10, 46)
			cost_label.text = cost_str
			cost_label.add_theme_font_size_override("font_size", 11)
			cost_label.add_theme_color_override("font_color", Color(0.92, 0.75, 0.18))
			card.add_child(cost_label)

			var build_btn = Button.new()
			build_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			build_btn.position = Vector2(-130, 24)
			build_btn.custom_minimum_size = Vector2(120, 36)
			build_btn.text = "Construire"
			build_btn.add_theme_font_size_override("font_size", 13)
			build_btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.85))
			var btn_style = StyleBoxFlat.new()
			btn_style.bg_color = Color(0.18, 0.45, 0.18)
			btn_style.border_color = Color(0.30, 0.65, 0.30)
			btn_style.border_width_left = 1
			btn_style.border_width_right = 1
			btn_style.border_width_top = 1
			btn_style.border_width_bottom = 2
			btn_style.corner_radius_top_left = 6
			btn_style.corner_radius_top_right = 6
			btn_style.corner_radius_bottom_left = 6
			btn_style.corner_radius_bottom_right = 6
			build_btn.add_theme_stylebox_override("normal", btn_style)
			build_btn.pressed.connect(_on_build_pressed.bind(b_id))
			card.add_child(build_btn)
		else:
			var req = b_info.get("required", "")
			if not req.is_empty():
				var req_label = Label.new()
				req_label.position = Vector2(10, 46)
				req_label.text = "Nécessite: " + GameData.CITY_BUILDINGS.get(req, {}).get("name", req)
				req_label.add_theme_font_size_override("font_size", 10)
				req_label.add_theme_color_override("font_color", Color(0.60, 0.40, 0.40))
				card.add_child(req_label)

func _fill_recruit_tab(city: GameData.City) -> void:
	for child in _recruit_container.get_children():
		child.queue_free()
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recruit_container.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var available_units = GameData.get_units_for_city(city)
	if available_units.is_empty():
		var no_units = Label.new()
		no_units.text = "Construisez des bâtiments pour débloquer des unités."
		no_units.add_theme_font_size_override("font_size", 14)
		no_units.add_theme_color_override("font_color", Color(0.60, 0.58, 0.52))
		no_units.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_units.custom_minimum_size = Vector2(0, 100)
		vbox.add_child(no_units)
		return

	for unit_info in available_units:
		var unit_id = unit_info.get("unit_id", "")
		var card = Panel.new()
		card.custom_minimum_size = Vector2(0, 90)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.08, 0.06, 0.10, 0.90)
		card_style.border_color = Color(0.45, 0.38, 0.22)
		card_style.border_width_left = 1
		card_style.border_width_right = 1
		card_style.border_width_top = 1
		card_style.border_width_bottom = 2
		card_style.corner_radius_top_left = 6
		card_style.corner_radius_top_right = 6
		card_style.corner_radius_bottom_left = 6
		card_style.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("panel", card_style)
		vbox.add_child(card)

		var name_label = Label.new()
		name_label.position = Vector2(10, 4)
		name_label.text = unit_info.get("name", unit_id)
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
		card.add_child(name_label)

		var stats_text = "ATK:%d DEF:%d DMG:%d-%d SPD:%d" % [
			unit_info.get("attack", 0), unit_info.get("defense", 0),
			unit_info.get("dmg_min", 0), unit_info.get("dmg_max", 0),
			unit_info.get("speed", 5)
		]
		if unit_info.get("is_ranged", false):
			stats_text += " [DISTANCE]"
		if unit_info.get("magic", false):
			stats_text += " [MAGIE]"
		var stats_label = Label.new()
		stats_label.position = Vector2(10, 24)
		stats_label.text = stats_text
		stats_label.add_theme_font_size_override("font_size", 10)
		stats_label.add_theme_color_override("font_color", Color(0.70, 0.68, 0.62))
		card.add_child(stats_label)

		var growth = unit_info.get("weekly_growth", 0)
		var cost = "💰" + str(unit_info.get("cost_gold", 0))
		if unit_info.get("cost_wood", 0) > 0:
			cost += " 🪵" + str(unit_info.get("cost_wood", 0))
		if unit_info.get("cost_ore", 0) > 0:
			cost += " ⛏" + str(unit_info.get("cost_ore", 0))
		var growth_text = "Croissance: +%d/semaine" % growth if growth > 0 else ""
		var info_label = Label.new()
		info_label.position = Vector2(10, 44)
		info_label.text = cost + "   " + growth_text
		info_label.add_theme_font_size_override("font_size", 11)
		info_label.add_theme_color_override("font_color", Color(0.92, 0.75, 0.18))
		card.add_child(info_label)

		var recruit_btn = Button.new()
		recruit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		recruit_btn.position = Vector2(-220, 20)
		recruit_btn.custom_minimum_size = Vector2(100, 36)
		recruit_btn.text = "Recruter x1"
		recruit_btn.add_theme_font_size_override("font_size", 12)
		recruit_btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.85))
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.16, 0.35, 0.16)
		btn_style.border_color = Color(0.25, 0.55, 0.25)
		btn_style.border_width_left = 1
		btn_style.border_width_right = 1
		btn_style.border_width_top = 1
		btn_style.border_width_bottom = 2
		btn_style.corner_radius_top_left = 6
		btn_style.corner_radius_top_right = 6
		btn_style.corner_radius_bottom_left = 6
		btn_style.corner_radius_bottom_right = 6
		recruit_btn.add_theme_stylebox_override("normal", btn_style)
		recruit_btn.pressed.connect(_on_recruit_pressed.bind(unit_id, 1))
		card.add_child(recruit_btn)

		var recruit_btn_x10 = Button.new()
		recruit_btn_x10.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		recruit_btn_x10.position = Vector2(-110, 20)
		recruit_btn_x10.custom_minimum_size = Vector2(100, 36)
		recruit_btn_x10.text = "Recruter x10"
		recruit_btn_x10.add_theme_font_size_override("font_size", 12)
		recruit_btn_x10.add_theme_color_override("font_color", Color(0.95, 0.90, 0.85))
		recruit_btn_x10.add_theme_stylebox_override("normal", btn_style)
		recruit_btn_x10.pressed.connect(_on_recruit_pressed.bind(unit_id, 10))
		card.add_child(recruit_btn_x10)

func _can_build(city: GameData.City, building_id: String) -> bool:
	if city.buildings.has(building_id):
		return false
	var b_info = GameData.CITY_BUILDINGS.get(building_id, {})
	var req = b_info.get("required", "")
	if not req.is_empty() and not city.buildings.has(req):
		return false
	if _gold < b_info.get("cost_gold", 0):
		return false
	if _wood < b_info.get("cost_wood", 0):
		return false
	if _ore < b_info.get("cost_ore", 0):
		return false
	return true

func _on_build_pressed(building_id: String) -> void:
	var city = _get_city()
	if not city:
		return
	if not _can_build(city, building_id):
		return
	var b_info = GameData.CITY_BUILDINGS.get(building_id, {})
	_gold -= b_info.get("cost_gold", 0)
	_wood -= b_info.get("cost_wood", 0)
	_ore -= b_info.get("cost_ore", 0)
	city.buildings.append(building_id)
	var unit_id = b_info.get("unlocks_unit", "")
	if not unit_id.is_empty():
		var base = GameData.UNIT_TYPES.get(unit_id, {})
		var tier = base.get("tier", 1)
		var base_growth = ([8, 5, 2] as Array)[mini(tier - 1, 2)]
		city.weekly_growth[unit_id] = base_growth + randi() % 3
	_update_resources_display()
	_fill_buildings_tab(city)
	_fill_recruit_tab(city)
	building_constructed.emit(city.id, building_id)

func _on_recruit_pressed(unit_id: String, count: int) -> void:
	var city = _get_city()
	if not city:
		return
	var base = GameData.UNIT_TYPES.get(unit_id, {})
	var cost_gold = base.get("cost_gold", 0) * count
	var cost_wood = base.get("cost_wood", 0) * count
	var cost_ore = base.get("cost_ore", 0) * count
	if _gold < cost_gold or _wood < cost_wood or _ore < cost_ore:
		return
	_gold -= cost_gold
	_wood -= cost_wood
	_ore -= cost_ore
	units_recruited.emit(city.id, unit_id, count)
	_update_resources_display()

func _update_resources_display() -> void:
	if _resources_label:
		_resources_label.text = "💰 %d   🪵 %d   ⛏ %d" % [_gold, _wood, _ore]

func _get_city() -> GameData.City:
	if _city_id >= 0 and _city_id < GameData.cities.size():
		return GameData.cities[_city_id]
	return null

func _close() -> void:
	visible = false
	if _panel:
		_panel.queue_free()
		_panel = null
	city_closed.emit()

func get_current_gold() -> int:
	return _gold

func get_current_wood() -> int:
	return _wood

func get_current_ore() -> int:
	return _ore
