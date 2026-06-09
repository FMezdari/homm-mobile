extends CanvasLayer

var gbi_texture: TextureRect
var gbt_label: Label
var dbi_label: Label
var dbt_button: Button

var bt1_label: Label
var bt2_color: ColorRect
var bt3_label: Label
var bt4_label: Label
var creature_bar: HBoxContainer

var h_btns: Array[Button] = []
var v_btns: Array[Button] = []
var gh_btn: Button
var dh_btn: Button
var gm_btn: Button
var dm_btn: Button

var selection_panel: Panel
var _jap_theme := JapaneseUITheme.new()

# Resource / info labels (referenced from tile_map_world.gd)
var label_gold: Label
var label_wood: Label
var label_ore: Label
var label_mp: Label
var label_date: Label

var _in_submenu: bool = false
var _pause_active: bool = false
var _pause_overlay: Panel = null
var _pause_layer: CanvasLayer = null
var _pause_btn: Button

signal hero_selected(id: int)
signal city_selected(id: int)
signal gh_pressed()
signal dh_pressed()
signal gm_pressed()
signal dm_pressed()
signal quest_pressed()
signal dbt_pressed()
signal pause_state_changed(is_paused: bool)
signal save_requested()
signal zoom_in_requested()
signal zoom_out_requested()

func _ready() -> void:
	_build_layout()
	GameData.selection_changed.connect(_on_selection_changed)
	GameData.turn_ended.connect(_on_turn_ended)
	_clear_all()

func _exit_tree() -> void:
	if GameData.selection_changed.is_connected(_on_selection_changed):
		GameData.selection_changed.disconnect(_on_selection_changed)
	if GameData.turn_ended.is_connected(_on_turn_ended):
		GameData.turn_ended.disconnect(_on_turn_ended)

func _build_layout():
	var vp_size = get_viewport().get_visible_rect().size
	var W = vp_size.x
	var H = vp_size.y

	# --- Top bar (180px) ---
	var top = Control.new()
	top.name = "TopBar"
	top.size = Vector2(W, 180)
	top.position = Vector2(0, 0)
	add_child(top)

	# Hero buttons column (left)
	var hero_col = VBoxContainer.new()
	hero_col.name = "HeroButtons"
	hero_col.position = Vector2(4, 4)
	hero_col.size = Vector2(160, 172)
	hero_col.add_theme_constant_override("separation", 4)
	top.add_child(hero_col)
	for i in range(3):
		var btn = _make_top_btn("H%d" % (i+1))
		btn.custom_minimum_size = Vector2(160, 54)
		btn.tooltip_text = "Héros %d (sélectionne et centre la vue)" % [i+1]
		btn.pressed.connect(_on_hero_btn_pressed.bind(i))
		hero_col.add_child(btn)
		h_btns.append(btn)

	# City buttons column (right) — individual buttons, absolute right edge
	var v_col_w = 200.0
	for i in range(3):
		var btn = _make_top_btn("V%d" % (i+1))
		btn.name = "V%d" % (i+1)
		btn.custom_minimum_size = Vector2(v_col_w, 54)
		btn.tooltip_text = "Ville %d (sélectionne la ville)" % [i+1]
		btn.pressed.connect(_on_city_btn_pressed.bind(i))
		top.add_child(btn)
		btn.position = Vector2(W - v_col_w, 4 + i * 58)
		btn.size = Vector2(v_col_w, 54)
		v_btns.append(btn)

	# Center buttons (GH, DH, GM, DM) — 2x2 grid, centered
	var center = Control.new()
	center.name = "CenterButtons"
	center.size = Vector2(400, 172)
	center.position = Vector2(W / 2 - 200, 4)
	top.add_child(center)

	gh_btn = _make_top_btn("GH")
	gh_btn.custom_minimum_size = Vector2(190, 80)
	gh_btn.position = Vector2(4, 4)
	gh_btn.tooltip_text = "Carte (affiche/masque la minimap)"
	gh_btn.pressed.connect(func(): gh_pressed.emit())
	center.add_child(gh_btn)

	dh_btn = _make_top_btn("DH")
	dh_btn.custom_minimum_size = Vector2(190, 80)
	dh_btn.position = Vector2(206, 4)
	dh_btn.tooltip_text = "Détails du Héros (stats et armée)"
	dh_btn.pressed.connect(func(): dh_pressed.emit())
	center.add_child(dh_btn)

	gm_btn = _make_top_btn("GM")
	gm_btn.custom_minimum_size = Vector2(190, 80)
	gm_btn.position = Vector2(4, 90)
	gm_btn.tooltip_text = "Carte du Monde (zoom arrière)"
	gm_btn.pressed.connect(func(): gm_pressed.emit())
	center.add_child(gm_btn)

	dm_btn = _make_top_btn("DM")
	dm_btn.custom_minimum_size = Vector2(190, 80)
	dm_btn.position = Vector2(206, 90)
	dm_btn.tooltip_text = "Détails du contexte sélectionné"
	dm_btn.pressed.connect(func(): dm_pressed.emit())
	center.add_child(dm_btn)

	# --- Selection Panel (shows when something selected) ---
	selection_panel = Panel.new()
	selection_panel.name = "SelectionPanel"
	selection_panel.size = Vector2(W, 280)
	selection_panel.position = Vector2(0, 180)
	selection_panel.visible = false
	selection_panel.add_theme_stylebox_override("panel", _jap_theme.panel_style(8))
	add_child(selection_panel)

	# Top row: BT1 (name) | BT2 (color) | BT3 (res amount)
	var top_row = HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.position = Vector2(10, 8)
	top_row.size = Vector2(W - 20, 30)
	top_row.add_theme_constant_override("separation", 12)
	selection_panel.add_child(top_row)

	bt1_label = Label.new()
	bt1_label.name = "BT1"
	bt1_label.add_theme_font_size_override("font_size", 14)
	bt1_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.75))
	bt1_label.custom_minimum_size = Vector2(200, 30)
	top_row.add_child(bt1_label)

	bt2_color = ColorRect.new()
	bt2_color.name = "BT2"
	bt2_color.custom_minimum_size = Vector2(24, 24)
	bt2_color.color = Color.TRANSPARENT
	top_row.add_child(bt2_color)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	bt3_label = Label.new()
	bt3_label.name = "BT3"
	bt3_label.add_theme_font_size_override("font_size", 14)
	bt3_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	bt3_label.custom_minimum_size = Vector2(100, 30)
	bt3_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(bt3_label)

	# Creature bar: C1-C7
	creature_bar = HBoxContainer.new()
	creature_bar.name = "CreatureBar"
	creature_bar.position = Vector2(10, 44)
	creature_bar.size = Vector2(W - 20, 160)
	creature_bar.add_theme_constant_override("separation", 6)
	selection_panel.add_child(creature_bar)
	for i in range(7):
		var btn = Button.new()
		btn.name = "C%d" % (i+1)
		btn.custom_minimum_size = Vector2((W - 76) / 7, 160)
		btn.visible = false
		var cs = StyleBoxFlat.new()
		cs.bg_color = Color(0.15, 0.10, 0.08)
		cs.border_color = Color(0.45, 0.38, 0.22)
		cs.border_width_left = 1
		cs.border_width_right = 1
		cs.border_width_top = 1
		cs.border_width_bottom = 2
		cs.corner_radius_top_left = 4
		cs.corner_radius_top_right = 4
		cs.corner_radius_bottom_left = 4
		cs.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", cs)
		var ch = cs.duplicate()
		ch.bg_color = Color(0.25, 0.18, 0.10)
		btn.add_theme_stylebox_override("hover", ch)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.8))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		creature_bar.add_child(btn)

	# Bottom row: BT4 (res type)
	var bottom_row = HBoxContainer.new()
	bottom_row.name = "BottomRow"
	bottom_row.position = Vector2(10, 212)
	bottom_row.size = Vector2(W - 20, 24)
	bottom_row.add_theme_constant_override("separation", 12)
	bottom_row.alignment = BoxContainer.ALIGNMENT_END
	selection_panel.add_child(bottom_row)

	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(spacer2)

	bt4_label = Label.new()
	bt4_label.name = "BT4"
	bt4_label.add_theme_font_size_override("font_size", 13)
	bt4_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.4))
	bt4_label.custom_minimum_size = Vector2(200, 24)
	bt4_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom_row.add_child(bt4_label)

	# --- Minimap container (hidden by default, toggled via GH) ---
	_minimap_container = Panel.new()
	_minimap_container.name = "MinimapContainer"
	_minimap_container.size = Vector2(570, 530)
	_minimap_container.position = Vector2(W / 2 - 285, 120)
	_minimap_container.visible = false
	var mm_style := StyleBoxFlat.new()
	mm_style.bg_color = Color(0.07, 0.06, 0.05, 0.97)
	mm_style.border_color = Color(0.55, 0.45, 0.25)
	mm_style.border_width_top = 2
	mm_style.border_width_bottom = 2
	mm_style.border_width_left = 2
	mm_style.border_width_right = 2
	mm_style.corner_radius_top_left = 10
	mm_style.corner_radius_top_right = 10
	mm_style.corner_radius_bottom_left = 10
	mm_style.corner_radius_bottom_right = 10
	mm_style.content_margin_top = 10
	mm_style.content_margin_bottom = 10
	mm_style.content_margin_left = 10
	mm_style.content_margin_right = 10
	_minimap_container.add_theme_stylebox_override("panel", mm_style)
	add_child(_minimap_container)

	# --- Bottom bar (180px) ---
	var bot = Panel.new()
	bot.name = "BottomBar"
	bot.size = Vector2(W, 180)
	bot.position = Vector2(0, H - 180)
	var bot_style := StyleBoxFlat.new()
	bot_style.bg_color = Color(0.08, 0.06, 0.04, 0.95)
	bot_style.border_color = Color(0.45, 0.38, 0.22)
	bot_style.border_width_top = 2
	bot.add_theme_stylebox_override("panel", bot_style)
	add_child(bot)

	# Left block: GBI + GBT
	# Center info: resources + MP + date
	var info_center = VBoxContainer.new()
	info_center.name = "InfoCenter"
	info_center.position = Vector2(190, 4)
	info_center.size = Vector2(W - 370, 172)
	info_center.add_theme_constant_override("separation", 4)
	bot.add_child(info_center)

	var res_hbox = HBoxContainer.new()
	res_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	res_hbox.add_theme_constant_override("separation", 20)
	info_center.add_child(res_hbox)

	var gold_lbl = Label.new()
	gold_lbl.text = "🪙"
	gold_lbl.add_theme_font_size_override("font_size", 16)
	res_hbox.add_child(gold_lbl)
	label_gold = Label.new()
	label_gold.add_theme_font_size_override("font_size", 16)
	label_gold.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	res_hbox.add_child(label_gold)

	var wood_lbl = Label.new()
	wood_lbl.text = "🪵"
	wood_lbl.add_theme_font_size_override("font_size", 16)
	res_hbox.add_child(wood_lbl)
	label_wood = Label.new()
	label_wood.add_theme_font_size_override("font_size", 16)
	label_wood.add_theme_color_override("font_color", Color(0.6, 0.9, 0.4))
	res_hbox.add_child(label_wood)

	var ore_lbl = Label.new()
	ore_lbl.text = "⛏"
	ore_lbl.add_theme_font_size_override("font_size", 16)
	res_hbox.add_child(ore_lbl)
	label_ore = Label.new()
	label_ore.add_theme_font_size_override("font_size", 16)
	label_ore.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	res_hbox.add_child(label_ore)

	label_mp = Label.new()
	label_mp.add_theme_font_size_override("font_size", 14)
	label_mp.add_theme_color_override("font_color", Color(0.35, 0.65, 0.45))
	label_mp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_center.add_child(label_mp)

	var quest_row = HBoxContainer.new()
	quest_row.alignment = BoxContainer.ALIGNMENT_CENTER
	quest_row.add_theme_constant_override("separation", 8)
	info_center.add_child(quest_row)

	var quest_btn = Button.new()
	quest_btn.text = "📜 Quetes"
	quest_btn.tooltip_text = "Objectifs et quêtes en cours"
	quest_btn.add_theme_font_size_override("font_size", 11)
	quest_btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	var qs = StyleBoxFlat.new()
	qs.bg_color = Color(0.15, 0.10, 0.05)
	qs.border_color = Color(0.6, 0.5, 0.2)
	qs.border_width_left = 1
	qs.border_width_right = 1
	qs.border_width_top = 1
	qs.border_width_bottom = 2
	qs.corner_radius_top_left = 4
	qs.corner_radius_top_right = 4
	qs.corner_radius_bottom_left = 4
	qs.corner_radius_bottom_right = 4
	quest_btn.add_theme_stylebox_override("normal", qs)
	quest_btn.pressed.connect(func(): quest_pressed.emit())
	quest_row.add_child(quest_btn)

	label_date = Label.new()
	label_date.add_theme_font_size_override("font_size", 12)
	label_date.add_theme_color_override("font_color", Color(0.7, 0.6, 0.4))
	label_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_center.add_child(label_date)

	var left_block = Control.new()
	left_block.name = "LeftBlock"
	left_block.size = Vector2(180, 176)
	left_block.position = Vector2(4, 2)
	bot.add_child(left_block)

	gbi_texture = TextureRect.new()
	gbi_texture.name = "GBI"
	gbi_texture.size = Vector2(80, 80)
	gbi_texture.position = Vector2(4, 4)
	gbi_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var gbi_bg = StyleBoxFlat.new()
	gbi_bg.bg_color = Color(0.15, 0.10, 0.08)
	gbi_bg.border_color = Color(0.45, 0.38, 0.22)
	gbi_bg.border_width_left = 1
	gbi_bg.border_width_right = 1
	gbi_bg.border_width_top = 1
	gbi_bg.border_width_bottom = 2
	gbi_bg.corner_radius_top_left = 4
	gbi_bg.corner_radius_top_right = 4
	gbi_bg.corner_radius_bottom_left = 4
	gbi_bg.corner_radius_bottom_right = 4
	gbi_texture.add_theme_stylebox_override("normal", gbi_bg)
	left_block.add_child(gbi_texture)

	gbt_label = Label.new()
	gbt_label.name = "GBT"
	gbt_label.size = Vector2(170, 86)
	gbt_label.position = Vector2(4, 88)
	gbt_label.add_theme_font_size_override("font_size", 12)
	gbt_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	gbt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_block.add_child(gbt_label)

	# Right block: DBI + DBT
	var right_block = Control.new()
	right_block.name = "RightBlock"
	right_block.size = Vector2(180, 176)
	right_block.position = Vector2(W - 184, 2)
	bot.add_child(right_block)

	dbi_label = Label.new()
	dbi_label.name = "DBI"
	dbi_label.size = Vector2(172, 40)
	dbi_label.position = Vector2(4, 4)
	dbi_label.add_theme_font_size_override("font_size", 16)
	dbi_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	dbi_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_block.add_child(dbi_label)

	dbt_button = Button.new()
	dbt_button.name = "DBT"
	dbt_button.size = Vector2(172, 126)
	dbt_button.position = Vector2(4, 46)
	dbt_button.text = "Terminer le tour"
	dbt_button.tooltip_text = "Passe au tour suivant"
	dbt_button.add_theme_font_size_override("font_size", 13)
	dbt_button.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	var dbt_normal = StyleBoxFlat.new()
	dbt_normal.bg_color = Color(0.65, 0.20, 0.20)
	dbt_normal.border_color = Color(0.90, 0.35, 0.35)
	dbt_normal.border_width_left = 2
	dbt_normal.border_width_right = 2
	dbt_normal.border_width_top = 2
	dbt_normal.border_width_bottom = 2
	dbt_normal.corner_radius_top_left = 6
	dbt_normal.corner_radius_top_right = 6
	dbt_normal.corner_radius_bottom_left = 6
	dbt_normal.corner_radius_bottom_right = 6
	dbt_button.add_theme_stylebox_override("normal", dbt_normal)
	var dbt_hover = dbt_normal.duplicate()
	dbt_hover.bg_color = Color(0.80, 0.30, 0.30)
	dbt_button.add_theme_stylebox_override("hover", dbt_hover)
	dbt_button.pressed.connect(func(): dbt_pressed.emit())
	var dbt_s = dbt_normal.duplicate()
	dbt_s.bg_color = Color(0.50, 0.14, 0.14)
	dbt_button.add_theme_stylebox_override("pressed", dbt_s)
	dbt_button.mouse_entered.connect(func():
		var ht := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		ht.tween_property(dbt_button, "scale", Vector2(1.06, 1.06), 0.12)
	)
	dbt_button.mouse_exited.connect(func():
		var ht := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		ht.tween_property(dbt_button, "scale", Vector2(1.0, 1.0), 0.08)
	)
	right_block.add_child(dbt_button)

	# --- Fullscreen toggle (tiny button, bottom-right corner) ---
	var fs_btn = Button.new()
	fs_btn.name = "FullscreenBtn"
	fs_btn.text = "⛶"
	fs_btn.tooltip_text = "Plein écran / Fenêtré"
	fs_btn.custom_minimum_size = Vector2(28, 28)
	fs_btn.size = Vector2(28, 28)
	fs_btn.position = Vector2(W - 108, H - 164)
	var fs_style = StyleBoxFlat.new()
	fs_style.bg_color = Color(0.15, 0.10, 0.06, 0.5)
	fs_style.border_color = Color(0.45, 0.38, 0.22, 0.5)
	fs_style.border_width_left = 1
	fs_style.border_width_right = 1
	fs_style.border_width_top = 1
	fs_style.border_width_bottom = 1
	fs_style.corner_radius_top_left = 4
	fs_style.corner_radius_top_right = 4
	fs_style.corner_radius_bottom_left = 4
	fs_style.corner_radius_bottom_right = 4
	fs_btn.add_theme_stylebox_override("normal", fs_style)
	var fs_hover = fs_style.duplicate()
	fs_hover.bg_color = Color(0.25, 0.18, 0.10, 0.7)
	fs_btn.add_theme_stylebox_override("hover", fs_hover)
	fs_btn.add_theme_font_size_override("font_size", 14)
	fs_btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75, 0.7))
	fs_btn.pressed.connect(func():
		var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	)
	add_child(fs_btn)

	# --- Pause button (bottom-left, opposite of End Turn) ---
	_pause_btn = Button.new()
	_pause_btn.name = "PauseBtn"
	_pause_btn.text = "⏸"
	_pause_btn.position = Vector2(8, H - 224)
	_pause_btn.size = Vector2(50, 44)
	var pbs := StyleBoxFlat.new()
	pbs.bg_color = Color(0.12, 0.10, 0.06, 0.85)
	pbs.border_color = Color(0.45, 0.38, 0.22)
	pbs.border_width_left = 1
	pbs.border_width_right = 1
	pbs.border_width_top = 1
	pbs.border_width_bottom = 1
	pbs.corner_radius_top_left = 6
	pbs.corner_radius_top_right = 6
	pbs.corner_radius_bottom_left = 6
	pbs.corner_radius_bottom_right = 6
	_pause_btn.add_theme_stylebox_override("normal", pbs)
	var pbs_hover := pbs.duplicate()
	pbs_hover.bg_color = Color(0.22, 0.18, 0.10, 0.9)
	_pause_btn.add_theme_stylebox_override("hover", pbs_hover)
	_pause_btn.add_theme_font_size_override("font_size", 18)
	_pause_btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.75))
	_pause_btn.pressed.connect(_on_pause_pressed)
	add_child(_pause_btn)

	# --- Zoom buttons (below pause button) ---
	var zoom_in_btn := Button.new()
	zoom_in_btn.name = "ZoomInBtn"
	zoom_in_btn.text = "+"
	zoom_in_btn.position = Vector2(8, H - 176)
	zoom_in_btn.size = Vector2(50, 36)
	var zbs := StyleBoxFlat.new()
	zbs.bg_color = Color(0.12, 0.10, 0.06, 0.85)
	zbs.border_color = Color(0.45, 0.38, 0.22)
	zbs.border_width_left = 1
	zbs.border_width_right = 1
	zbs.border_width_top = 1
	zbs.border_width_bottom = 1
	zbs.corner_radius_top_left = 6
	zbs.corner_radius_top_right = 6
	zbs.corner_radius_bottom_left = 6
	zbs.corner_radius_bottom_right = 6
	zoom_in_btn.add_theme_stylebox_override("normal", zbs)
	var zbs_hover := zbs.duplicate()
	zbs_hover.bg_color = Color(0.22, 0.18, 0.10, 0.9)
	zoom_in_btn.add_theme_stylebox_override("hover", zbs_hover)
	zoom_in_btn.add_theme_font_size_override("font_size", 20)
	zoom_in_btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.75))
	zoom_in_btn.pressed.connect(func(): zoom_in_requested.emit())
	add_child(zoom_in_btn)

	var zoom_out_btn := Button.new()
	zoom_out_btn.name = "ZoomOutBtn"
	zoom_out_btn.text = "−"
	zoom_out_btn.position = Vector2(8, H - 136)
	zoom_out_btn.size = Vector2(50, 36)
	zoom_out_btn.add_theme_stylebox_override("normal", zbs)
	zoom_out_btn.add_theme_stylebox_override("hover", zbs_hover)
	zoom_out_btn.add_theme_font_size_override("font_size", 20)
	zoom_out_btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.75))
	zoom_out_btn.pressed.connect(func(): zoom_out_requested.emit())
	add_child(zoom_out_btn)

func _make_top_btn(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.75))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.9))
	var s := _jap_theme.button_style(Color(0.12, 0.10, 0.06), Color(0.45, 0.38, 0.22))
	var sh := _jap_theme.button_style(Color(0.22, 0.18, 0.10), Color(0.70, 0.55, 0.30))
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", sh)
	_jap_theme.add_hover_scale(btn, 1.04)
	btn.pressed.connect(func():
		if SFX and SFX.has_method("play_click"):
			SFX.play_click()
	)
	return btn

func _on_selection_changed(mode, id, tile):
	_in_submenu = false
	selection_panel.visible = false

	var gd = GameData
	match mode:
		GameData.SelectionMode.HERO:
			if id >= 0 and id < gd.heroes.size():
				var h = gd.heroes[id]
				gbi_texture.texture = h.sprite
				gbt_label.text = h.name
				_fill_top_bar(h.owner, "", "", "")
				# Afficher l'armée (stacks) dans la barre de créatures
				var display_units: Array = []
				if h.army and h.army.stacks.size() > 0:
					for stack in h.army.stacks:
						var unit_name: String = stack.unit_id
						var u_data = GameData.UNIT_TYPES.get(stack.unit_id, {})
						if u_data:
							unit_name = u_data.get("name", stack.unit_id)
						display_units.append({"name": unit_name, "amount": stack.count})
				elif h.creatures.size() > 0:
					for c in h.creatures:
						display_units.append(c)
				else:
					display_units = h.creatures
				_fill_creature_bar(display_units)
				selection_panel.visible = true
				dbi_label.text = "⏳ %d/%d" % [GameData.turn_counter, GameData.max_turns]
				dbt_button.text = "Terminer le tour"

		GameData.SelectionMode.CITY:
			if id >= 0 and id < gd.cities.size():
				var c = gd.cities[id]
				gbi_texture.texture = null
				gbt_label.text = c.name
				_fill_top_bar(c.owner, c.resource_type, str(c.resource_per_day), "")
				dbi_label.text = "⏳ %d/%d" % [GameData.turn_counter, GameData.max_turns]
				dbt_button.text = "Terminer le tour"

		GameData.SelectionMode.BUILDING:
			if id >= 0 and id < gd.buildings.size():
				var b = gd.buildings[id]
				gbi_texture.texture = null
				gbt_label.text = b.type
				_fill_top_bar(b.owner, b.resource_type, str(b.resource_per_day), "")
				_clear_creature_bar()
				selection_panel.visible = true
				dbi_label.text = "⏳ %d/%d" % [GameData.turn_counter, GameData.max_turns]
				dbt_button.text = "Terminer le tour"

		GameData.SelectionMode.TILE:
			var creature = _creature_on_tile(tile)
			if creature:
				gbi_texture.texture = null
				gbt_label.text = "%s x%d" % [creature.name, creature.amount]
			else:
				gbi_texture.texture = null
				gbt_label.text = ""
			_clear_top_bar()
			_clear_creature_bar()
			selection_panel.visible = false
			dbi_label.text = "⏳ %d/%d" % [GameData.turn_counter, GameData.max_turns]
			dbt_button.text = "Terminer le tour"

		_:
			_clear_all()

func _on_turn_ended(counter, max):
	dbi_label.text = "⏳ %d/%d" % [counter, max]
	dbt_button.text = "Terminer le tour"
	_in_submenu = false

func enter_submenu(menu_title: String):
	_in_submenu = true
	dbi_label.text = "←"
	dbt_button.text = "Sortir"
	gbi_texture.texture = null
	gbt_label.text = menu_title
	selection_panel.visible = false

func exit_submenu():
	_in_submenu = false
	dbi_label.text = "⏳ %d/%d" % [GameData.turn_counter, GameData.max_turns]
	dbt_button.text = "Terminer le tour"

func _fill_top_bar(owner_id: int, res_type: String, res_amount: String, extra: String):
	bt1_label.text = "Joueur %d" % owner_id
	if owner_id >= 0 and owner_id < GameData.player_colors.size():
		bt2_color.color = GameData.player_colors[owner_id]
	else:
		bt2_color.color = Color.TRANSPARENT
	bt3_label.text = res_amount
	bt4_label.text = res_type

func _clear_top_bar():
	bt1_label.text = ""
	bt2_color.color = Color.TRANSPARENT
	bt3_label.text = ""
	bt4_label.text = ""

func _fill_creature_bar(creatures: Array):
	_clear_creature_bar()
	creature_bar.visible = not creatures.is_empty()
	var slots = creature_bar.get_children()
	for i in range(min(creatures.size(), slots.size())):
		var c = creatures[i]
		var btn = slots[i] as Button
		btn.visible = true
		btn.text = "%s\nx%d" % [c.name, c.amount]

func _clear_creature_bar():
	for child in creature_bar.get_children():
		child.visible = false

func _clear_all():
	gbi_texture.texture = null
	gbt_label.text = ""
	_clear_top_bar()
	_clear_creature_bar()
	selection_panel.visible = false
	dbi_label.text = "⏳ 0/%d" % GameData.max_turns
	dbt_button.text = "Terminer le tour"

func _creature_on_tile(pos: Vector2i) -> GameData.Creature:
	if GameData.creatures_on_tile.has(pos):
		return GameData.creatures_on_tile[pos]
	return null

func _on_hero_btn_pressed(id: int):
	hero_selected.emit(id)

func set_hero_names(names: Array) -> void:
	for i in range(mini(names.size(), h_btns.size())):
		h_btns[i].text = names[i]
		h_btns[i].tooltip_text = names[i]
	for i in range(names.size(), h_btns.size()):
		h_btns[i].text = "H%d" % (i + 1)
		h_btns[i].tooltip_text = "Héros %d" % (i + 1)

func _on_city_btn_pressed(id: int):
	if id >= 0 and id < GameData.cities.size():
		GameData.set_selection(GameData.SelectionMode.CITY, id, GameData.cities[id].position)

func get_gold_label() -> Label:
	return label_gold

func get_wood_label() -> Label:
	return label_wood

func get_ore_label() -> Label:
	return label_ore

func get_date_label() -> Label:
	return label_date

func get_minimap_container() -> Control:
	return _minimap_container

func is_paused() -> bool:
	return _pause_active

func get_pause_button() -> Button:
	return _pause_btn

func get_zoom_in_button() -> Button:
	return find_child("ZoomInBtn", true, false) as Button

func get_zoom_out_button() -> Button:
	return find_child("ZoomOutBtn", true, false) as Button

func _on_pause_pressed() -> void:
	if SFX and SFX.has_method("play_click"):
		SFX.play_click()
	_pause_active = true
	pause_state_changed.emit(true)
	_show_pause_menu()

func _on_save_pressed() -> void:
	if SFX and SFX.has_method("play_click"):
		SFX.play_click()
	save_requested.emit()
	_hide_pause_menu()

func _show_pause_menu() -> void:
	if _pause_overlay:
		return
	var vp := get_viewport().get_visible_rect().size

	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseLayer"
	_pause_layer.layer = 128
	add_child(_pause_layer)

	_pause_overlay = Panel.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.size = vp
	_pause_overlay.position = Vector2.ZERO
	var ol_style := StyleBoxFlat.new()
	ol_style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	_pause_overlay.add_theme_stylebox_override("panel", ol_style)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(_pause_overlay)

	var menu_panel := Panel.new()
	menu_panel.name = "PauseMenuPanel"
	menu_panel.size = Vector2(360, 420)
	menu_panel.position = Vector2(vp.x / 2 - 180, vp.y / 2 - 210)
	var mp_style := _jap_theme.panel_style(12)
	_pause_overlay.add_child(menu_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	vbox.add_theme_constant_override("margin_left", 24)
	vbox.add_theme_constant_override("margin_right", 24)
	vbox.add_theme_constant_override("margin_top", 24)
	vbox.add_theme_constant_override("margin_bottom", 24)
	menu_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Pause"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.20))
	vbox.add_child(title)

	vbox.add_child(_make_spacer(8))

	var btn_continue := Button.new()
	btn_continue.text = "Continuer"
	btn_continue.custom_minimum_size = Vector2(280, 50)
	btn_continue.add_theme_font_size_override("font_size", 18)
	btn_continue.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	var bs := _jap_theme.button_style(Color(0.12, 0.10, 0.06), Color(0.50, 0.40, 0.25))
	var bs_hover := _jap_theme.button_style(Color(0.22, 0.18, 0.10), Color(0.75, 0.60, 0.35))
	btn_continue.add_theme_stylebox_override("normal", bs)
	btn_continue.add_theme_stylebox_override("hover", bs_hover)
	btn_continue.pressed.connect(_hide_pause_menu)
	_jap_theme.add_hover_scale(btn_continue, 1.04)
	vbox.add_child(btn_continue)

	vbox.add_child(_make_spacer(4))

	var btn_save := Button.new()
	btn_save.text = "Sauvegarder"
	btn_save.custom_minimum_size = Vector2(280, 50)
	btn_save.add_theme_font_size_override("font_size", 18)
	btn_save.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	btn_save.add_theme_stylebox_override("normal", bs)
	btn_save.add_theme_stylebox_override("hover", bs_hover)
	btn_save.pressed.connect(_on_save_pressed)
	_jap_theme.add_hover_scale(btn_save, 1.04)
	vbox.add_child(btn_save)

	vbox.add_child(_make_spacer(4))

	var llm_row := HBoxContainer.new()
	llm_row.custom_minimum_size = Vector2(280, 40)
	llm_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var llm_label := Label.new()
	llm_label.text = "Utilisation de l'IA"
	llm_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	llm_label.add_theme_font_size_override("font_size", 16)
	llm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	llm_row.add_child(llm_label)

	var llm_cfg := LLMConfig.new()
	llm_cfg.load_from_disk()
	var llm_check := CheckBox.new()
	llm_check.button_pressed = llm_cfg.enabled
	llm_check.toggled.connect(func(checked: bool):
		llm_cfg.enabled = checked
		llm_cfg.save()
	)
	llm_row.add_child(llm_check)

	vbox.add_child(llm_row)

	vbox.add_child(_make_spacer(4))

	var vol_label := Label.new()
	vol_label.text = "Volume Musique"
	vol_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	vbox.add_child(vol_label)

	var slider := HSlider.new()
	slider.min_value = -30.0
	slider.max_value = 0.0
	slider.value = _get_bgm_volume()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_set_bgm_volume)
	vbox.add_child(slider)

	vbox.add_child(_make_spacer(4))

	var btn_menu := Button.new()
	btn_menu.text = "Menu Principal"
	btn_menu.custom_minimum_size = Vector2(280, 50)
	btn_menu.add_theme_font_size_override("font_size", 18)
	btn_menu.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	btn_menu.add_theme_stylebox_override("normal", bs)
	btn_menu.add_theme_stylebox_override("hover", bs_hover)
	btn_menu.pressed.connect(_on_return_to_menu)
	_jap_theme.add_hover_scale(btn_menu, 1.04)
	vbox.add_child(btn_menu)

	var btn_quit := Button.new()
	btn_quit.text = "Quitter"
	btn_quit.custom_minimum_size = Vector2(280, 50)
	btn_quit.add_theme_font_size_override("font_size", 18)
	btn_quit.add_theme_color_override("font_color", Color(0.85, 0.75, 0.65))
	btn_quit.add_theme_stylebox_override("normal", bs)
	btn_quit.add_theme_stylebox_override("hover", bs_hover)
	btn_quit.pressed.connect(_on_quit_from_pause)
	_jap_theme.add_hover_scale(btn_quit, 1.04)
	vbox.add_child(btn_quit)

func _hide_pause_menu() -> void:
	if _pause_overlay:
		_pause_overlay.queue_free()
		_pause_overlay = null
	if _pause_layer:
		_pause_layer.queue_free()
		_pause_layer = null
	_pause_active = false
	pause_state_changed.emit(false)


func _get_bgm_volume() -> float:
	var bgm = get_node_or_null("/root/RetroBGM")
	if bgm and bgm.has_method("get_volume"):
		return bgm.get_volume()
	return -8.0

func _set_bgm_volume(value: float) -> void:
	var bgm = get_node_or_null("/root/RetroBGM")
	if bgm and bgm.has_method("set_volume"):
		bgm.set_volume(value)

func _on_return_to_menu() -> void:
	_hide_pause_menu()
	var bgm = get_node_or_null("/root/RetroBGM")
	if bgm and bgm.has_method("play_menu"):
		bgm.play_menu()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_quit_from_pause() -> void:
	get_tree().quit()

func _make_spacer(h: int) -> ColorRect:
	var s := ColorRect.new()
	s.custom_minimum_size = Vector2(0, h)
	s.color = Color.TRANSPARENT
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

var _minimap_container: Control
