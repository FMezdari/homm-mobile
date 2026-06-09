extends CanvasLayer

signal combat_ended(won: bool)
signal combat_victory(gold_reward: int, xp_reward: int)
signal combat_defeat()
signal combat_fled()

# ============================================
# COMBAT MANAGER v3 — combat 1v1 avec sprites
# ============================================

var _combat_panel: Panel
var _combat_bg: TextureRect
var _combat_fog: ColorRect = null
var _fog_time: float = 0.0
const FOG_SHADER_CODE := """
shader_type canvas_item;

uniform float time : hint_range(0.0, 100.0) = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float n1 = noise(uv * 3.0 + time * 0.02);
	float n2 = noise(uv * 5.0 - time * 0.03 + 100.0);
	float fog = n1 * 0.6 + n2 * 0.4;
	fog = smoothstep(0.2, 0.6, fog);
	vec2 d = min(UV, 1.0 - UV);
	float vignette = 1.0 - smoothstep(0.0, 0.2, min(d.x, d.y));
	float alpha = fog * 0.20 + vignette * 0.25;
	COLOR = vec4(0.02, 0.03, 0.06, alpha);
}
"""
var _vfx: CombatVFX
var _action_bar: HBoxContainer
var _hero_card: Panel
var _enemy_card: Panel
var _hero_sprite_node: Sprite2D
var _enemy_sprite_node: Sprite2D
var _hero_hp_fill: ColorRect = null
var _enemy_hp_fill: ColorRect = null
var _hero_info_label: Label
var _enemy_info_label: Label
var _combat_log: RichTextLabel
var _combat_title: Label
var _round_label: Label
var _turn_label: Label
var _spell_panel: Panel
var _spell_buttons: Array = []
var _defense_indicator: Label
var _rage_indicator: Label

var _hero_unit: Dictionary = {}
var _enemy_unit: Dictionary = {}
var _current_turn: int = 0
var _round_count: int = 1
var _in_combat: bool = false
var _hero_defending: bool = false
var _hero_attack_buff: bool = false
var _hero_mana: int = 80
var _hero_max_mana: int = 80
var _mana_label: Label
var _sprite_generator: SpriteGenerator

const SPELL_COST: Dictionary = {
	"fireball": 8,
	"lightning": 7,
	"heal": 5,
	"rage": 4,
	"ice_shard": 10,
}

var _hero_data: Dictionary = {}
var _enemy_data: Dictionary = {}
var _enemy_index: int = -1
var _combat_outcome: String = ""

var _top_bar_style: StyleBoxFlat
var _action_btn_normal: StyleBoxFlat
var _action_btn_hover: StyleBoxFlat
var _action_btn_pressed: StyleBoxFlat
var _result_panel_style: StyleBoxFlat
var _result_btn_normal: StyleBoxFlat
var _result_btn_hover: StyleBoxFlat
var _result_btn_pressed: StyleBoxFlat

const COLOR_BG_DARK := Color(0.04, 0.03, 0.06)
const COLOR_PANEL_BG := Color(0.08, 0.06, 0.10, 0.92)
const COLOR_GOLD := Color(0.92, 0.75, 0.18)
const COLOR_GOLD_DIM := Color(0.55, 0.42, 0.18)
const COLOR_CRIMSON := Color(0.75, 0.12, 0.14)
const COLOR_TEAL := Color(0.12, 0.55, 0.62)
const COLOR_HERO_BLUE := Color(0.08, 0.22, 0.42)
const COLOR_ENEMY_RED := Color(0.42, 0.08, 0.08)
const COLOR_TEXT_LIGHT := Color(0.92, 0.90, 0.86)
const COLOR_TEXT_DIM := Color(0.60, 0.58, 0.52)
const COLOR_MANA_PURPLE := Color(0.55, 0.30, 0.90)
const COLOR_GREEN := Color(0.18, 0.65, 0.22)
const COLOR_RED := Color(0.75, 0.18, 0.12)
const COLOR_WHITE := Color(0.95, 0.95, 0.92)

# Nom → créature : permet de mapper les noms français des unités vers les sprites existants
const NAME_TO_CREATURE: Dictionary = {
	"samurai": "hero_samurai",
	"archer": "archer",
	"piquier": "skeleton",
	"pikeman": "skeleton",
	"épéiste": "swordsman",
	"epeiste": "swordsman",
	"goblin": "goblin",
	"knight": "knight",
	"skeleton": "skeleton",
	"swordsman": "swordsman",
	"griffon": "knight",
	"cavalier": "knight",
	"ange": "knight",
	"horde": "goblin",
	"horde ennemie": "goblin",
	"ennemi": "goblin",
	"boss": "skeleton",
	"oni": "skeleton",
	"dragon": "skeleton",
}

# Hero sprite cache (samurai de la carte)
var _hero_samurai_texture: Texture2D = null

# Creature sprite cache
var _creature_sprites: Dictionary = {}
var _creature_frames: Dictionary = {}

var _hero_sprites_container: Control
var _enemy_sprites_container: Control

var _visual_env: WorldEnvironment = null
var _vignette_overlay: ColorRect = null

func _ready() -> void:
	visible = false
	_setup_styles()
	_setup_ui()
	_vfx = CombatVFX.new(self)
	_preload_creature_sprites()
	_visual_env = VisualEnhancer.add_world_environment(self)
	_vignette_overlay = VisualEnhancer.add_vignette_overlay(self)
	_sprite_generator = SpriteGenerator.new()

func _preload_creature_sprites() -> void:
	_hero_samurai_texture = load("res://assets/heroes/hero_samurai_down.png")
	if _hero_samurai_texture:
		print("✓ Sprite samurai chargé")
	else:
		print("⚠ Sprite samurai non trouvé")
	var base_path: String = "res://assets/homm3_advanced/units/"
	var creature_types: Array[String] = ["archer", "goblin", "knight", "skeleton", "swordsman"]
	var dirs: Array[String] = ["south", "east", "west", "north", "southeast", "southwest", "northeast", "northwest"]
	for creature in creature_types:
		for d in dirs:
			var first_path: String = base_path + creature + "_" + d + "_0.png"
			var first_tex: Texture2D = load(first_path)
			if first_tex:
				if not _creature_sprites.has(creature):
					_creature_sprites[creature] = first_tex
				var frames_key: String = creature + "_" + d
				_creature_frames[frames_key] = [first_tex]
				for f in range(1, 4):
					var fp: String = base_path + creature + "_" + d + "_" + str(f) + ".png"
					var ft: Texture2D = load(fp)
					if ft:
						_creature_frames[frames_key].append(ft)
				if d == "south":
					_creature_frames[creature] = _creature_frames[frames_key]
		if _creature_sprites.has(creature):
			print("✓ Sprites chargés: " + creature)
		else:
			print("⚠ Sprite non trouvé: " + creature)

func _get_creature_texture(unit_name: String, direction: String = "south") -> Texture2D:
	var key: String = unit_name.to_lower().strip_edges()
	var mapped: String = NAME_TO_CREATURE.get(key, "")
	if mapped == "hero_samurai":
		return _hero_samurai_texture
	if mapped != "":
		var mk: String = mapped + "_" + direction
		var mf: Array = _creature_frames.get(mk, _creature_frames.get(mapped, []))
		if mf.size() > 0:
			return mf[randi() % mf.size()]
	for creature in _creature_sprites.keys():
		if key.find(creature) != -1:
			var frames_key: String = creature + "_" + direction
			var frames: Array = _creature_frames.get(frames_key, _creature_frames.get(creature, []))
			if frames.size() > 0:
				return frames[randi() % frames.size()]
	var fallback: Texture2D = _creature_sprites.get("knight")
	if fallback:
		return fallback
	var generated: ImageTexture = _generate_unit_sprite(unit_name)
	return generated

func _generate_enemy_texture(unit_name: String) -> Texture2D:
	var key: String = unit_name.to_lower().strip_edges()
	var mapped: String = NAME_TO_CREATURE.get(key, "")
	if mapped == "":
		for c in _creature_sprites.keys():
			if key.find(c) != -1:
				mapped = c
				break
	if mapped == "" or mapped == "hero_samurai":
		mapped = "skeleton"

	var enemy_type: String = "enemy_" + mapped
	if mapped == "knight" or mapped == "hero_samurai":
		enemy_type = "enemy_skeleton"
	var variant_seed: int = abs(key.hash()) % 100000
	return _sprite_generator._generate_sprite(enemy_type, 64, variant_seed)

func _generate_unit_sprite(unit_name: String) -> ImageTexture:
	var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hs: int = 32
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var body_color: Color
	match unit_name.to_lower():
		"archer": body_color = Color(0.35, 0.25, 0.18)
		"goblin": body_color = Color(0.75, 0.15, 0.15)
		"skeleton": body_color = Color(0.78, 0.82, 0.78)
		"swordsman": body_color = Color(0.12, 0.08, 0.06)
		"knight": body_color = Color(0.15, 0.15, 0.45)
		_: body_color = Color(0.50, 0.50, 0.50)
	for x in range(64):
		for y in range(64):
			var ox: float = (x - hs) / 20.0
			var oy: float = (y - hs) / 20.0
			var dist: float = ox * ox + oy * oy
			if dist <= 1.0:
				var shade: float = 1.0 - dist * 0.5
				var c: Color = body_color
				img.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade))
	for x in range(20, 44):
		for y in range(8, 28):
			var ox: float = float(x - 32) / 12.0
			var oy: float = float(y - 18) / 10.0
			if ox*ox + oy*oy <= 1.0:
				img.set_pixel(x, y, Color(0.90, 0.75, 0.60))
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	_fog_time += delta
	if _in_combat and _combat_fog and _combat_fog.material:
		_combat_fog.material.set_shader_parameter("time", _fog_time)
	if _vignette_overlay:
		VisualEnhancer.set_vignette_time(_vignette_overlay, _fog_time)

func _setup_styles() -> void:
	_top_bar_style = StyleBoxFlat.new()
	_top_bar_style.bg_color = Color(0.06, 0.04, 0.08)
	_top_bar_style.border_color = COLOR_GOLD_DIM
	_top_bar_style.border_width_bottom = 2
	_top_bar_style.corner_radius_bottom_left = 14
	_top_bar_style.corner_radius_bottom_right = 14
	_top_bar_style.shadow_color = Color(0, 0, 0, 0.60)
	_top_bar_style.shadow_size = 10
	_top_bar_style.shadow_offset = Vector2(0, 4)

	var btn_base := Color(0.14, 0.10, 0.06)
	var btn_border := Color(0.50, 0.38, 0.20)
	var btn_hover_bg := Color(0.24, 0.18, 0.10)
	var btn_hover_border := Color(0.72, 0.55, 0.28)

	_action_btn_normal = StyleBoxFlat.new()
	_action_btn_normal.bg_color = btn_base
	_action_btn_normal.border_color = btn_border
	_action_btn_normal.border_width_left = 1
	_action_btn_normal.border_width_right = 1
	_action_btn_normal.border_width_top = 1
	_action_btn_normal.border_width_bottom = 3
	_action_btn_normal.corner_radius_top_left = 12
	_action_btn_normal.corner_radius_top_right = 12
	_action_btn_normal.corner_radius_bottom_left = 12
	_action_btn_normal.corner_radius_bottom_right = 12
	_action_btn_normal.shadow_color = Color(0, 0, 0, 0.50)
	_action_btn_normal.shadow_size = 8
	_action_btn_normal.shadow_offset = Vector2(0, 3)

	_action_btn_hover = StyleBoxFlat.new()
	_action_btn_hover.bg_color = btn_hover_bg
	_action_btn_hover.border_color = btn_hover_border
	_action_btn_hover.border_width_left = 1
	_action_btn_hover.border_width_right = 1
	_action_btn_hover.border_width_top = 1
	_action_btn_hover.border_width_bottom = 3
	_action_btn_hover.corner_radius_top_left = 12
	_action_btn_hover.corner_radius_top_right = 12
	_action_btn_hover.corner_radius_bottom_left = 12
	_action_btn_hover.corner_radius_bottom_right = 12
	_action_btn_hover.shadow_color = Color(0, 0, 0, 0.60)
	_action_btn_hover.shadow_size = 10
	_action_btn_hover.shadow_offset = Vector2(0, 4)

	_action_btn_pressed = StyleBoxFlat.new()
	_action_btn_pressed.bg_color = Color(0.08, 0.06, 0.04)
	_action_btn_pressed.border_color = Color(0.38, 0.28, 0.14)
	_action_btn_pressed.border_width_left = 1
	_action_btn_pressed.border_width_right = 1
	_action_btn_pressed.border_width_top = 3
	_action_btn_pressed.border_width_bottom = 1
	_action_btn_pressed.corner_radius_top_left = 12
	_action_btn_pressed.corner_radius_top_right = 12
	_action_btn_pressed.corner_radius_bottom_left = 12
	_action_btn_pressed.corner_radius_bottom_right = 12
	_action_btn_pressed.shadow_color = Color(0, 0, 0, 0.20)
	_action_btn_pressed.shadow_size = 4
	_action_btn_pressed.shadow_offset = Vector2(0, 1)

	_result_panel_style = StyleBoxFlat.new()
	_result_panel_style.bg_color = Color(0.05, 0.04, 0.07, 0.96)
	_result_panel_style.border_color = COLOR_GOLD_DIM
	_result_panel_style.border_width_left = 2
	_result_panel_style.border_width_right = 2
	_result_panel_style.border_width_top = 2
	_result_panel_style.border_width_bottom = 2
	_result_panel_style.corner_radius_top_left = 24
	_result_panel_style.corner_radius_top_right = 24
	_result_panel_style.corner_radius_bottom_left = 24
	_result_panel_style.corner_radius_bottom_right = 24
	_result_panel_style.shadow_color = Color(0, 0, 0, 0.70)
	_result_panel_style.shadow_size = 30
	_result_panel_style.shadow_offset = Vector2(0, 12)

	var result_btn_base := Color(0.18, 0.45, 0.18)
	var result_btn_border := Color(0.30, 0.65, 0.30)

	_result_btn_normal = StyleBoxFlat.new()
	_result_btn_normal.bg_color = Color(0.16, 0.40, 0.16)
	_result_btn_normal.border_color = result_btn_border
	_result_btn_normal.border_width_left = 1
	_result_btn_normal.border_width_right = 1
	_result_btn_normal.border_width_top = 1
	_result_btn_normal.border_width_bottom = 3
	_result_btn_normal.corner_radius_top_left = 14
	_result_btn_normal.corner_radius_top_right = 14
	_result_btn_normal.corner_radius_bottom_left = 14
	_result_btn_normal.corner_radius_bottom_right = 14
	_result_btn_normal.shadow_color = Color(0, 0, 0, 0.50)
	_result_btn_normal.shadow_size = 8
	_result_btn_normal.shadow_offset = Vector2(0, 3)

	_result_btn_hover = StyleBoxFlat.new()
	_result_btn_hover.bg_color = Color(0.22, 0.55, 0.22)
	_result_btn_hover.border_color = Color(0.35, 0.78, 0.35)
	_result_btn_hover.border_width_left = 1
	_result_btn_hover.border_width_right = 1
	_result_btn_hover.border_width_top = 1
	_result_btn_hover.border_width_bottom = 3
	_result_btn_hover.corner_radius_top_left = 14
	_result_btn_hover.corner_radius_top_right = 14
	_result_btn_hover.corner_radius_bottom_left = 14
	_result_btn_hover.corner_radius_bottom_right = 14
	_result_btn_hover.shadow_color = Color(0, 0, 0, 0.60)
	_result_btn_hover.shadow_size = 10
	_result_btn_hover.shadow_offset = Vector2(0, 4)

	_result_btn_pressed = StyleBoxFlat.new()
	_result_btn_pressed.bg_color = Color(0.10, 0.30, 0.10)
	_result_btn_pressed.border_color = Color(0.22, 0.50, 0.22)
	_result_btn_pressed.border_width_left = 1
	_result_btn_pressed.border_width_right = 1
	_result_btn_pressed.border_width_top = 3
	_result_btn_pressed.border_width_bottom = 1
	_result_btn_pressed.corner_radius_top_left = 14
	_result_btn_pressed.corner_radius_top_right = 14
	_result_btn_pressed.corner_radius_bottom_left = 14
	_result_btn_pressed.corner_radius_bottom_right = 14
	_result_btn_pressed.shadow_color = Color(0, 0, 0, 0.20)
	_result_btn_pressed.shadow_size = 4
	_result_btn_pressed.shadow_offset = Vector2(0, 1)

func _setup_ui() -> void:
	_combat_bg = TextureRect.new()
	_combat_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_combat_bg.visible = false
	_combat_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_bg.texture = _generate_battlefield_bg()
	_combat_bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_combat_bg)

	_combat_fog = ColorRect.new()
	_combat_fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_combat_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_fog.visible = false
	var fog_shader := Shader.new()
	fog_shader.code = FOG_SHADER_CODE
	var fog_mat := ShaderMaterial.new()
	fog_mat.shader = fog_shader
	_combat_fog.material = fog_mat
	add_child(_combat_fog)

	_combat_panel = Panel.new()
	_combat_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_combat_panel.visible = false
	add_child(_combat_panel)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = Color(0.30, 0.25, 0.16)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.corner_radius_bottom_right = 20
	panel_style.shadow_color = Color(0, 0, 0, 0.80)
	panel_style.shadow_size = 30
	panel_style.shadow_offset = Vector2(0, 12)
	_combat_panel.add_theme_stylebox_override("panel", panel_style)

	var top_bar = Panel.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 56)
	top_bar.add_theme_stylebox_override("panel", _top_bar_style)
	_combat_panel.add_child(top_bar)

	_combat_title = Label.new()
	_combat_title.text = "COMBAT 1v1"
	_combat_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_combat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combat_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combat_title.custom_minimum_size = Vector2(0, 56)
	_combat_title.add_theme_font_size_override("font_size", 30)
	_combat_title.add_theme_color_override("font_color", COLOR_GOLD)
	_combat_panel.add_child(_combat_title)

	_round_label = Label.new()
	_round_label.position = Vector2(20, 16)
	_round_label.text = "Round 1"
	_round_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_round_label.add_theme_font_size_override("font_size", 14)
	_combat_panel.add_child(_round_label)

	_turn_label = Label.new()
	_turn_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_turn_label.position = Vector2(-180, 16)
	_turn_label.text = "Votre tour"
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_turn_label.add_theme_color_override("font_color", COLOR_TEAL)
	_turn_label.add_theme_font_size_override("font_size", 14)
	_combat_panel.add_child(_turn_label)

	_defense_indicator = Label.new()
	_defense_indicator.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_defense_indicator.position = Vector2(40, -210)
	_defense_indicator.text = "DEFENSE +"
	_defense_indicator.add_theme_color_override("font_color", COLOR_TEAL)
	_defense_indicator.add_theme_font_size_override("font_size", 16)
	_defense_indicator.visible = false
	_combat_panel.add_child(_defense_indicator)

	_rage_indicator = Label.new()
	_rage_indicator.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_rage_indicator.position = Vector2(40, -190)
	_rage_indicator.text = "FUREUR +"
	_rage_indicator.add_theme_color_override("font_color", Color(0.95, 0.55, 0.10))
	_rage_indicator.add_theme_font_size_override("font_size", 16)
	_rage_indicator.visible = false
	_combat_panel.add_child(_rage_indicator)

	_mana_label = Label.new()
	_mana_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_mana_label.position = Vector2(40, -140)
	_mana_label.add_theme_color_override("font_color", COLOR_MANA_PURPLE)
	_mana_label.add_theme_font_size_override("font_size", 14)
	_combat_panel.add_child(_mana_label)

	_hero_info_label = Label.new()
	_hero_info_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hero_info_label.position = Vector2(40, -160)
	_hero_info_label.add_theme_color_override("font_color", Color(0.30, 0.65, 0.85))
	_hero_info_label.add_theme_font_size_override("font_size", 12)
	_combat_panel.add_child(_hero_info_label)

	_enemy_info_label = Label.new()
	_enemy_info_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_enemy_info_label.position = Vector2(-240, -160)
	_enemy_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_info_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.25))
	_enemy_info_label.add_theme_font_size_override("font_size", 12)
	_combat_panel.add_child(_enemy_info_label)

	_action_bar = HBoxContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_bar.position = Vector2(-270, -80)
	_action_bar.custom_minimum_size = Vector2(540, 54)
	_action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_bar.add_theme_constant_override("separation", 16)
	_combat_panel.add_child(_action_bar)

	_add_action_button("Attaquer", _on_attack_pressed, Color(0.75, 0.18, 0.12))
	_add_action_button("Defendre", _on_defend_pressed, Color(0.18, 0.55, 0.65))
	_add_action_button("Magie", _on_magic_pressed, Color(0.55, 0.18, 0.65))
	_add_action_button("Fuir", _on_flee_pressed, Color(0.35, 0.30, 0.25))

	_combat_log = RichTextLabel.new()
	_combat_log.set_anchors_preset(Control.PRESET_CENTER, false)
	_combat_log.position = Vector2(-430, 180)
	_combat_log.size = Vector2(860, 100)
	_combat_log.bbcode_enabled = true
	_combat_log.add_theme_color_override("default_color", COLOR_TEXT_DIM)
	_combat_log.add_theme_font_size_override("normal_font_size", 12)
	_combat_log.scroll_active = true
	_combat_log.scroll_following = true
	var log_style = StyleBoxFlat.new()
	log_style.bg_color = Color(0.03, 0.02, 0.04, 0.50)
	log_style.corner_radius_top_left = 8
	log_style.corner_radius_top_right = 8
	log_style.corner_radius_bottom_left = 8
	log_style.corner_radius_bottom_right = 8
	_combat_log.add_theme_stylebox_override("normal", log_style)
	_combat_panel.add_child(_combat_log)

	_spell_panel = Panel.new()
	_spell_panel.set_anchors_preset(Control.PRESET_CENTER)
	_spell_panel.offset_left = -210
	_spell_panel.offset_top = -120
	_spell_panel.offset_right = 210
	_spell_panel.offset_bottom = 120
	_spell_panel.visible = false
	var spell_style = StyleBoxFlat.new()
	spell_style.bg_color = Color(0.05, 0.03, 0.08, 0.97)
	spell_style.border_color = Color(0.55, 0.18, 0.65)
	spell_style.border_width_left = 2
	spell_style.border_width_right = 2
	spell_style.border_width_top = 2
	spell_style.border_width_bottom = 2
	spell_style.corner_radius_top_left = 20
	spell_style.corner_radius_top_right = 20
	spell_style.corner_radius_bottom_left = 20
	spell_style.corner_radius_bottom_right = 20
	spell_style.shadow_color = Color(0, 0, 0, 0.70)
	spell_style.shadow_size = 24
	spell_style.shadow_offset = Vector2(0, 10)
	_spell_panel.add_theme_stylebox_override("panel", spell_style)
	_combat_panel.add_child(_spell_panel)

	var spell_title = Label.new()
	spell_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	spell_title.position = Vector2(0, 15)
	spell_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spell_title.text = "— Choisir un sort —"
	spell_title.add_theme_font_size_override("font_size", 22)
	spell_title.add_theme_color_override("font_color", Color(0.75, 0.45, 0.95))
	spell_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.60))
	_spell_panel.add_child(spell_title)

	var spell_container = HBoxContainer.new()
	spell_container.set_anchors_preset(Control.PRESET_CENTER)
	spell_container.position = Vector2(-160, 55)
	spell_container.custom_minimum_size = Vector2(320, 120)
	spell_container.alignment = BoxContainer.ALIGNMENT_CENTER
	spell_container.add_theme_constant_override("separation", 12)
	_spell_panel.add_child(spell_container)

	_add_spell_button("Boule de Feu", Color(0.95, 0.35, 0.15), "fireball", spell_container)
	_add_spell_button("Éclair", Color(0.65, 0.75, 0.95), "lightning", spell_container)
	_add_spell_button("Soin", Color(0.25, 0.75, 0.35), "heal", spell_container)
	_add_spell_button("Fureur", Color(0.95, 0.65, 0.15), "rage", spell_container)
	_add_spell_button("Glace", Color(0.5, 0.7, 1.0), "ice_shard", spell_container)

func _add_action_button(text: String, callback: Callable, accent_color: Color) -> void:
	var action_icons := {
		"Attaquer": "",
		"Defendre": "",
		"Magie": "",
		"Fuir": "",
	}
	var btn = Button.new()
	btn.text = action_icons.get(text, "") + text
	btn.custom_minimum_size = Vector2(123, 54)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	btn.add_theme_color_override("font_hover_color", COLOR_WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.75, 0.72, 0.68))
	btn.add_theme_stylebox_override("normal", _action_btn_normal)
	btn.add_theme_stylebox_override("hover", _action_btn_hover)
	btn.add_theme_stylebox_override("pressed", _action_btn_pressed)
	btn.pressed.connect(callback)
	btn.mouse_entered.connect(func():
		var ht = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		ht.tween_property(btn, "scale", Vector2(1.06, 1.06), 0.15)
		ht.parallel().tween_property(btn, "modulate", Color(1.10, 1.06, 1.02), 0.15)
	)
	btn.mouse_exited.connect(func():
		var ht = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		ht.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1)
		ht.parallel().tween_property(btn, "modulate", Color.WHITE, 0.1)
	)
	_action_bar.add_child(btn)

func _add_spell_button(text: String, accent_color: Color, spell_type: String, container: HBoxContainer) -> void:
	var btn = Button.new()
	var cost: int = SPELL_COST.get(spell_type, 0)
	btn.text = text + "\n[" + str(cost) + " PM]"
	btn.custom_minimum_size = Vector2(82, 100)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	var spell_normal = StyleBoxFlat.new()
	spell_normal.bg_color = accent_color.darkened(0.50)
	spell_normal.border_color = accent_color.lightened(0.15)
	spell_normal.border_width_left = 1
	spell_normal.border_width_right = 1
	spell_normal.border_width_top = 1
	spell_normal.border_width_bottom = 3
	spell_normal.corner_radius_top_left = 12
	spell_normal.corner_radius_top_right = 12
	spell_normal.corner_radius_bottom_left = 12
	spell_normal.corner_radius_bottom_right = 12
	spell_normal.shadow_color = Color(0, 0, 0, 0.50)
	spell_normal.shadow_size = 6
	spell_normal.shadow_offset = Vector2(0, 3)
	btn.add_theme_stylebox_override("normal", spell_normal)
	btn.mouse_entered.connect(func():
		btn.scale = Vector2(1.0, 1.0)
		var ht = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		ht.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.12)
	)
	btn.mouse_exited.connect(func():
		btn.scale = Vector2(1.08, 1.08)
		var ht = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		ht.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.08)
	)
	btn.pressed.connect(func(): _on_spell_selected(spell_type))
	container.add_child(btn)
	_spell_buttons.append(btn)

# ============================================
# BATTLEFIELD BACKGROUND (identique)
# ============================================

func _generate_battlefield_bg() -> ImageTexture:
	var w: int = 540
	var h: int = 1200
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var sky_h: int = int(h * 0.55)
	var half_w: float = float(w) * 0.5
	var half_h: float = float(h) * 0.5
	var half_w_int: int = w / 2

	for y in range(sky_h):
		var t: float = float(y) / sky_h
		var r: float = 0.55 - t * 0.30
		var g: float = 0.28 + t * 0.25
		var b: float = 0.15 + t * 0.55
		img.set_pixel(half_w_int, y, Color(r, g, b))
		var edge_falloff: float = 1.0
		for x in range(half_w_int):
			edge_falloff = 1.0 - pow((half_w_int - x) / half_w, 1.5) * 0.25
			img.set_pixel(x, y, Color(r * edge_falloff, g * edge_falloff, b * edge_falloff))
		for x in range(half_w_int, w):
			edge_falloff = 1.0 - pow((x - half_w_int) / half_w, 1.5) * 0.25
			img.set_pixel(x, y, Color(r * edge_falloff, g * edge_falloff, b * edge_falloff))

	for x in range(w):
		for y in range(sky_h - 15, sky_h + 10):
			var mist_t: float = float(y - (sky_h - 15)) / 25.0
			mist_t = clamp(mist_t, 0, 1)
			var mist_strength: float = 0.15 * (1.0 - abs(mist_t - 0.5) * 2.0)
			var px := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(
				lerp(px.r, 0.70, mist_strength),
				lerp(px.g, 0.50, mist_strength),
				lerp(px.b, 0.30, mist_strength)
			))

	for y in range(sky_h, h):
		var gy: float = float(y - sky_h) / (h - sky_h)
		var grass_r_base: float = 0.15 + gy * 0.10
		var grass_g_base: float = 0.30 + gy * 0.12
		var grass_b_base: float = 0.08 + gy * 0.04
		var sunset_tint: float = maxf(0, 1.0 - gy * 2.0) * 0.10
		for x in range(w):
			var gx_noise: float = sin(x * 0.05 + y * 0.08) * 0.03
			img.set_pixel(x, y, Color(
				grass_r_base + gx_noise + sunset_tint * 0.10,
				grass_g_base + gx_noise + sunset_tint * 0.05,
				grass_b_base - sunset_tint * 0.02
			))

	var sun_cx: int = half_w_int
	var sun_cy: int = sky_h - 40
	var sun_r: int = 12
	for dy in range(-sun_r, sun_r + 1):
		for dx in range(-sun_r, sun_r + 1):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= sun_r:
				var sx: int = sun_cx + dx
				var sy: int = sun_cy + dy
				if sx >= 0 and sx < w and sy >= 0 and sy < h:
					var alpha: float = 1.0
					if dist > sun_r * 0.6:
						alpha = 1.0 - (dist - sun_r * 0.6) / (sun_r * 0.4)
					var sun_bright: float = maxf(0, 1.0 - dist / sun_r)
					img.set_pixel(sx, sy, Color(1.0, 0.85 + sun_bright * 0.15, 0.45 + sun_bright * 0.35, alpha))

	var halo_r: int = 40
	for dy in range(-halo_r, halo_r + 1):
		for dx in range(-halo_r, halo_r + 1):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= halo_r and dist > sun_r:
				var hx: int = sun_cx + dx
				var hy: int = sun_cy + dy
				if hx >= 0 and hx < w and hy >= 0 and hy < h:
					var glow: float = maxf(0, 1.0 - (dist - sun_r) / (halo_r - sun_r))
					glow *= glow * 0.12
					var px := img.get_pixel(hx, hy)
					img.set_pixel(hx, hy, Color(
						lerp(px.r, 1.0, glow),
						lerp(px.g, 0.90, glow),
						lerp(px.b, 0.55, glow)
					))

	var mountain_layers: Array = [
		{ "horizon_offset": 0, "colors": [Color(0.05, 0.04, 0.08), Color(0.04, 0.03, 0.07), Color(0.06, 0.05, 0.09)], "peaks": [0, 0.08, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 1.0], "heights": [0, -40, -25, -60, -35, -70, -45, -65, -30, -50, 0] },
		{ "horizon_offset": -3, "colors": [Color(0.08, 0.06, 0.10), Color(0.07, 0.05, 0.09), Color(0.09, 0.07, 0.11)], "peaks": [0, 0.10, 0.22, 0.32, 0.42, 0.52, 0.62, 0.72, 0.82, 0.92, 1.0], "heights": [-5, -50, -30, -70, -45, -80, -55, -75, -40, -55, -10] },
	]
	for layer in mountain_layers:
		var base_y: int = sky_h + layer["horizon_offset"]
		var pts: Array = []
		var peaks_arr: Array = layer["peaks"]
		var heights_arr: Array = layer["heights"]
		for i in range(peaks_arr.size()):
			var px_x: int = int(w * peaks_arr[i])
			var px_y: int = base_y + heights_arr[i]
			pts.append([px_x, px_y])
		for i in range(pts.size() - 1):
			var x1: int = pts[i][0]
			var y1: int = pts[i][1]
			var x2: int = pts[i + 1][0]
			var y2: int = pts[i + 1][1]
			var col: Color = layer["colors"][i % layer["colors"].size()]
			var y_start: int = mini(y1, y2)
			var y_end: int = base_y + 5
			for my in range(y_start, y_end):
				var t_seg: float = float(my - y_start) / float(y_end - y_start) if y_end > y_start else 0
				var left_x: int = int(x1 + (x2 - x1) * float(my - y1) / float(y2 - y1)) if y2 != y1 else x1
				for mx in range(left_x - 2, left_x + 3):
					if mx >= 0 and mx < w:
						var existing := img.get_pixel(mx, my)
						if existing.a < 0.1:
							var fade: float = 1.0 - t_seg * 0.25
							img.set_pixel(mx, my, Color(col.r * fade, col.g * fade, col.b * fade, 1.0))

	# --- Birds in the sky ---
	var bird_rng := RandomNumberGenerator.new()
	bird_rng.randomize()
	for b in 6:
		var bx: int = 30 + bird_rng.randi() % int(w - 60)
		var by: int = 60 + bird_rng.randi() % 120
		var bird_size: int = 2 + bird_rng.randi() % 2
		for i in range(bird_size):
			var bxx := bx + i * 3
			var byy := by + i
			if bxx >= 0 and bxx < w and byy >= 0 and byy < h:
				img.set_pixel(bxx, byy, Color(0.10, 0.08, 0.12, 0.50))
			bxx = bx - i * 3
			if bxx >= 0 and bxx < w and byy >= 0 and byy < h:
				img.set_pixel(bxx, byy, Color(0.10, 0.08, 0.12, 0.50))

	# --- Clouds ---
	var cloud_rng2 := RandomNumberGenerator.new()
	cloud_rng2.randomize()
	for c in 4:
		var cx: int = cloud_rng2.randi() % w
		var cy: int = 30 + cloud_rng2.randi() % 80
		var cw2: int = 40 + cloud_rng2.randi() % 60
		var ch2: int = 8 + cloud_rng2.randi() % 8
		var alpha2: float = 0.06 + cloud_rng2.randf() * 0.08
		for x in range(cx, cx + cw2):
			for y in range(cy, cy + ch2):
				var dx: float = (x - cx - cw2 / 2) / (cw2 / 2)
				var dy: float = (y - cy - ch2 / 2) / (ch2 / 2)
				if dx * dx + dy * dy <= 1.0 and x >= 0 and x < w and y >= 0 and y < h:
					var existing2 := img.get_pixel(x, y)
					var cloud_c2 := Color(0.70, 0.60, 0.50, alpha2)
					img.set_pixel(x, y, existing2.lerp(cloud_c2, alpha2))

	# --- Ground details (bushes, rocks) ---
	var detail_rng := RandomNumberGenerator.new()
	detail_rng.randomize()
	for d in 30:
		var dx2: int = detail_rng.randi() % w
		var dy2: int = sky_h + 10 + detail_rng.randi() % int(h - sky_h - 20)
		if detail_rng.randf() > 0.5:
			for i in range(4):
				var dxx := dx2 + detail_rng.randi() % 4 - 2
				var dyy := dy2 + detail_rng.randi() % 3
				if dxx >= 0 and dxx < w and dyy >= 0 and dyy < h:
					img.set_pixel(dxx, dyy, Color(0.10, 0.25, 0.08))
		else:
			for i in range(3):
				var dxx := dx2 + detail_rng.randi() % 3 - 1
				var dyy := dy2 + detail_rng.randi() % 2
				if dxx >= 0 and dxx < w and dyy >= 0 and dyy < h:
					img.set_pixel(dxx, dyy, Color(0.18, 0.15, 0.12))

	for y in range(h):
		var vig_y: float = pow((float(y) - half_h) / half_h, 2) * 0.10
		for x in range(w):
			var vig: float = 1.0 - pow((float(x) - half_w) / half_w, 2) * 0.15 - vig_y
			var px := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(px.r * vig, px.g * vig, px.b * vig))

	return ImageTexture.create_from_image(img)

# ============================================
# COMBAT LOGIC
# ============================================

func start_combat(hero_data: Dictionary, enemy_data: Dictionary, enemy_index: int = -1) -> void:
	_hero_data = hero_data
	_enemy_data = enemy_data
	if RetroBGM and RetroBGM.has_method("switch_to_combat"):
		RetroBGM.switch_to_combat()
	_enemy_index = enemy_index

	var raw_hero_units: Array = hero_data.get("units", [])
	_hero_unit = raw_hero_units[0].duplicate(true) if raw_hero_units.size() > 0 else {
		"name": "Heros", "hp": 80, "max_hp": 80, "attack": 15, "defense": 8, "magic": 10
	}
	var raw_enemy_units: Array = enemy_data.get("units", [])
	_enemy_unit = raw_enemy_units[0].duplicate(true) if raw_enemy_units.size() > 0 else {
		"name": "Ennemi", "hp": 50, "max_hp": 50, "attack": 10, "defense": 5
	}

	_current_turn = 0
	_round_count = 1
	_in_combat = true
	_combat_outcome = ""
	_hero_defending = false
	_hero_attack_buff = false
	_hero_mana = _hero_max_mana

	_combat_title.text = "COMBAT"
	_round_label.text = "Round 1"
	_turn_label.text = "Votre tour"
	_combat_log.clear()
	_action_bar.visible = true
	_defense_indicator.visible = false
	_rage_indicator.visible = false

	_update_unit_displays()
	_update_mana_display()
	_log_message("[color=#6ec3e0]Combat 1v1: " + _hero_unit.get("name", "Heros") + " vs " + _enemy_unit.get("name", "Ennemi") + "![/color]")
	if SFX and SFX.has_method("play_combat_start"):
		SFX.play_combat_start()

	visible = true
	_combat_bg.visible = true
	_combat_bg.modulate.a = 0.0
	if _combat_fog:
		_combat_fog.visible = true
	_combat_panel.visible = true
	_combat_panel.modulate.a = 0.0
	_combat_panel.scale = Vector2(0.9, 0.9)

	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_combat_bg, "modulate:a", 1.0, 0.6)
	tween.parallel().tween_property(_combat_panel, "modulate:a", 1.0, 0.4)
	tween.parallel().tween_property(_combat_panel, "scale", Vector2(1.0, 1.0), 0.4)
	tween.tween_callback(func():
		_show_turn_banner("COMBAT!", COLOR_GOLD)
	)

func get_hero_units() -> Array:
	return [_hero_unit.duplicate(true)]

func _end_combat(won: bool) -> void:
	_in_combat = false
	_combat_outcome = "victory" if won else "defeat"
	_action_bar.visible = false

	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_combat_panel, "modulate:a", 0.0, 0.5)
	tween.parallel().tween_property(_combat_panel, "scale", Vector2(0.9, 0.9), 0.5)
	tween.tween_callback(func():
		_spawn_result_panel(_combat_outcome)
	)

func _show_flee_result() -> void:
	_in_combat = false
	_combat_outcome = "flee"
	_action_bar.visible = false
	_spawn_result_panel("flee")

func _spawn_result_panel(outcome: String) -> void:
	# Dim overlay with radial gradient (vignette)
	var grad := Gradient.new()
	grad.add_point(0.0, Color(0.05, 0.03, 0.02, 0.95))
	grad.add_point(0.5, Color(0.03, 0.02, 0.01, 0.98))
	grad.add_point(1.0, Color(0.01, 0.01, 0.00, 1.00))

	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 1.0)
	grad_tex.width = 540
	grad_tex.height = 1200

	var dim := TextureRect.new()
	dim.texture = grad_tex
	dim.stretch_mode = TextureRect.STRETCH_SCALE
	dim.anchor_left = 0
	dim.anchor_top = 0
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.modulate.a = 0.0
	add_child(dim)

	# Panel (centered, 520x400)
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -200
	panel.offset_right = 260
	panel.offset_bottom = 200
	panel.add_theme_stylebox_override("panel", _result_panel_style)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.8, 0.8)
	add_child(panel)

	# Decorative top bar (full panel width, 80px tall)
	var deco := ColorRect.new()
	deco.anchor_left = 0
	deco.anchor_top = 0
	deco.anchor_right = 1
	deco.anchor_bottom = 0
	deco.offset_left = 0
	deco.offset_top = 0
	deco.offset_right = 0
	deco.offset_bottom = 80
	deco.color = Color(0.18, 0.05, 0.04, 0.92)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(deco)

	# Gold accent line
	var accent := ColorRect.new()
	accent.anchor_left = 0
	accent.anchor_top = 0
	accent.anchor_right = 1
	accent.anchor_bottom = 0
	accent.offset_left = 0
	accent.offset_top = 77
	accent.offset_right = 0
	accent.offset_bottom = 80
	accent.color = COLOR_GOLD
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(accent)

	# Title (full width, vertically centered in top bar)
	var title := Label.new()
	title.anchor_left = 0
	title.anchor_top = 0
	title.anchor_right = 1
	title.anchor_bottom = 0
	title.offset_left = 20
	title.offset_top = 5
	title.offset_right = -20
	title.offset_bottom = 75
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.60))
	panel.add_child(title)

	# Description (indented, below top bar)
	var desc := RichTextLabel.new()
	desc.anchor_left = 0
	desc.anchor_top = 0
	desc.anchor_right = 1
	desc.anchor_bottom = 0
	desc.offset_left = 30
	desc.offset_top = 95
	desc.offset_right = -30
	desc.offset_bottom = 180
	desc.bbcode_enabled = true
	desc.scroll_active = false
	desc.fit_content = true
	desc.add_theme_color_override("default_color", Color(0.85, 0.82, 0.78))
	desc.add_theme_font_size_override("normal_font_size", 15)
	panel.add_child(desc)

	# Separator line
	var sep := ColorRect.new()
	sep.anchor_left = 0
	sep.anchor_top = 0
	sep.anchor_right = 1
	sep.anchor_bottom = 0
	sep.offset_left = 70
	sep.offset_top = 185
	sep.offset_right = -70
	sep.offset_bottom = 186
	sep.color = Color(0.50, 0.38, 0.20, 0.40)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sep)

	# Rewards label
	var reward := RichTextLabel.new()
	reward.anchor_left = 0
	reward.anchor_top = 0
	reward.anchor_right = 1
	reward.anchor_bottom = 0
	reward.offset_left = 30
	reward.offset_top = 195
	reward.offset_right = -30
	reward.offset_bottom = 260
	reward.bbcode_enabled = true
	reward.scroll_active = false
	reward.fit_content = true
	reward.add_theme_color_override("default_color", Color(0.85, 0.82, 0.78))
	reward.add_theme_font_size_override("normal_font_size", 16)
	reward.visible = false
	panel.add_child(reward)

	# Continue button (centered horizontally at bottom)
	var btn := Button.new()
	btn.anchor_left = 0.5
	btn.anchor_top = 0
	btn.anchor_right = 0.5
	btn.anchor_bottom = 0
	btn.offset_left = -100
	btn.offset_top = 275
	btn.offset_right = 100
	btn.offset_bottom = 335
	btn.text = "Continuer"
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.90))
	btn.add_theme_stylebox_override("normal", _result_btn_normal)
	btn.add_theme_stylebox_override("hover", _result_btn_hover)
	btn.add_theme_stylebox_override("pressed", _result_btn_pressed)
	panel.add_child(btn)

	# Content based on outcome
	match outcome:
		"victory":
			title.text = "VICTOIRE !"
			title.add_theme_color_override("font_color", COLOR_GOLD)
			var enemy_name = _enemy_data.get("name", "l'ennemi")
			desc.text = "[center]Vous avez vaincu\n[color=#ff6666]" + enemy_name + "[/color] ![/center]"
			var xp_val: int = int(_enemy_data.get("xp", 50)) + 50
			var gold_val: int = _enemy_data.get("gold", 50)
			reward.visible = true
			reward.text = "[center][color=#d4a017]Or :  " + str(gold_val) + "     [/color][color=#88ccff]XP :  " + str(xp_val) + "[/color][/center]"
			if SFX and SFX.has_method("play_victory"):
				SFX.play_victory()
		"defeat":
			title.text = "DÉFAITE..."
			title.add_theme_color_override("font_color", COLOR_CRIMSON)
			var enemy_name = _enemy_data.get("name", "l'ennemi")
			desc.text = "[center]Vous avez été vaincu par\n[color=#ff6666]" + enemy_name + "[/color]...[/center]\n\n[center][color=#666666]Votre héros a péri au combat.[/color][/center]"
			if SFX and SFX.has_method("play_defeat"):
				SFX.play_defeat()
		"flee":
			title.text = "FUITE"
			title.add_theme_color_override("font_color", COLOR_TEAL)
			desc.text = "[center]Vous avez réussi à\nfuir le combat.[/center]"

	# Particules de célébration
	if outcome == "victory":
		for i in range(15):
			var confetti = ColorRect.new()
			confetti.size = Vector2(randf_range(4, 8), randf_range(4, 8))
			confetti.color = Color(randf_range(0.8, 1.0), randf_range(0.4, 0.9), randf_range(0.1, 0.5), 0.7)
			confetti.position = Vector2(randf_range(0, 540), -20 - randf_range(0, 40))
			confetti.z_index = 50
			confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(confetti)
			var ctw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			ctw.tween_property(confetti, "position:y", 1200 + 20, randf_range(2.5, 4.5))
			ctw.parallel().tween_property(confetti, "position:x", confetti.position.x + randf_range(-30, 30), randf_range(2.5, 4.5))
			ctw.parallel().tween_property(confetti, "rotation", randf_range(-3, 3), randf_range(2.5, 4.5))
			ctw.tween_callback(func(): if is_instance_valid(confetti): confetti.queue_free())

	# Entrance animation
	var anim = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	anim.tween_property(dim, "modulate:a", 1.0, 0.3)
	anim.parallel().tween_property(panel, "modulate:a", 1.0, 0.4)
	anim.parallel().tween_property(panel, "scale", Vector2(1.0, 1.0), 0.4)
	anim.tween_callback(func():
		if RetroBGM and RetroBGM.has_method("switch_to_exploration"):
			RetroBGM.switch_to_exploration()
	)

	btn.pressed.connect(func():
		btn.disabled = true
		var hide = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		hide.tween_property(panel, "modulate:a", 0.0, 0.2)
		hide.parallel().tween_property(dim, "modulate:a", 0.0, 0.2)
		hide.parallel().tween_property(panel, "scale", Vector2(0.9, 0.9), 0.2)
		hide.tween_callback(func():
			if is_instance_valid(dim):
				dim.queue_free()
			if is_instance_valid(panel):
				panel.queue_free()
			visible = false
			_combat_bg.visible = false
			if _combat_fog:
				_combat_fog.visible = false
			_combat_panel.visible = false
			match outcome:
				"victory":
					combat_victory.emit(int(_enemy_data.get("gold", 50)), int(_enemy_data.get("xp", 100)))
					combat_ended.emit(true)
				"flee":
					combat_fled.emit()
					combat_ended.emit(false)
				"defeat":
					combat_defeat.emit()
					combat_ended.emit(false)
				_:
					combat_ended.emit(false)
		)
	)

func _on_attack_pressed() -> void:
	if not _in_combat or _current_turn != 0:
		return
	if SFX and SFX.has_method("play_sword_hit"):
		SFX.play_sword_hit()
	_process_hero_attack()

func _on_defend_pressed() -> void:
	if not _in_combat or _current_turn != 0:
		return
	_hero_defending = true
	_defense_indicator.visible = true
	_log_message("[color=#5a9eb8]Vous prenez une position defensive. (+50% defense)[/color]")
	if SFX and SFX.has_method("play_click"):
		SFX.play_click()

	# Effet de bouclier bleuté sur le sprite
	if _hero_sprite_node and is_instance_valid(_hero_sprite_node):
		var shield = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		shield.tween_property(_hero_sprite_node, "modulate", Color(0.6, 0.8, 1.2), 0.2)

	_process_next_turn()

func _on_magic_pressed() -> void:
	if not _in_combat or _current_turn != 0:
		return
	_spell_panel.visible = true
	_spell_panel.modulate.a = 0.0
	_spell_panel.scale = Vector2(0.8, 0.8)
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_spell_panel, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(_spell_panel, "scale", Vector2(1.0, 1.0), 0.3)

func _on_spell_selected(spell_type: String) -> void:
	_spell_panel.visible = false
	if not _can_cast(spell_type):
		_spell_panel.visible = true
		return
	_spend_mana(spell_type)
	_cast_spell(spell_type)

func _can_cast(spell_type: String) -> bool:
	var cost: int = SPELL_COST.get(spell_type, 0)
	if _hero_mana < cost:
		_log_message("[color=#ff4444]Pas assez de mana! (besoin: " + str(cost) + ")[/color]")
		return false
	return true

func _spend_mana(spell_type: String) -> void:
	var cost: int = SPELL_COST.get(spell_type, 0)
	_hero_mana = maxi(0, _hero_mana - cost)
	_update_mana_display()

func _update_mana_display() -> void:
	if _mana_label:
		_mana_label.text = "Mana: %d/%d" % [_hero_mana, _hero_max_mana]

func _spell_cast_announce(spell_name: String, color: Color) -> void:
	# Texte du nom du sort qui apparaît brièvement
	var announce = Label.new()
	announce.text = spell_name
	announce.add_theme_font_size_override("font_size", 20)
	announce.add_theme_color_override("font_color", color)
	announce.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.80))
	announce.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.50))
	announce.add_theme_constant_override("outline_size", 2)
	announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce.set_anchors_preset(Control.PRESET_CENTER)
	announce.offset_top = -60
	announce.custom_minimum_size = Vector2(200, 30)
	announce.z_index = 45
	announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_panel.add_child(announce)
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(announce, "offset_top", -80, 0.15)
	tw.tween_interval(0.3)
	tw.tween_property(announce, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): if is_instance_valid(announce): announce.queue_free())

func _spell_cast_effect(spell_type: String) -> void:
	# Cercle d'incantation runique
	var rune_colors := {
		"fireball": Color(1.0, 0.4, 0.1),
		"lightning": Color(0.6, 0.8, 1.0),
		"heal": Color(0.3, 0.9, 0.4),
		"rage": Color(1.0, 0.6, 0.1),
		"ice_shard": Color(0.5, 0.7, 1.0),
	}
	var color: Color = rune_colors.get(spell_type, Color(0.6, 0.4, 1.0))

	var cx: float = get_viewport().size.x * 0.5
	var cy: float = get_viewport().size.y * 0.5

	# Anneau runique externe
	for ring_i in 3:
		var ring := ColorRect.new()
		ring.size = Vector2(100 + ring_i * 20, 100 + ring_i * 20)
		ring.position = Vector2(cx - ring.size.x / 2, cy - ring.size.y / 2)
		ring.color = Color(color.r, color.g, color.b, 0.0)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.z_index = 40
		ring.set_anchors_preset(Control.PRESET_CENTER)
		_combat_panel.add_child(ring)
		var rtw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		rtw.tween_property(ring, "modulate", Color(color.r, color.g, color.b, 0.25 - ring_i * 0.05), 0.2)
		rtw.parallel().tween_property(ring, "size", Vector2(160 + ring_i * 30, 160 + ring_i * 30), 0.3)
		rtw.parallel().tween_property(ring, "position", Vector2(
			cx - (160 + ring_i * 30) / 2,
			cy - (160 + ring_i * 30) / 2
		), 0.3)
		rtw.tween_property(ring, "modulate:a", 0.0, 0.2)
		rtw.tween_callback(func():
			if is_instance_valid(ring): ring.queue_free()
		)

	# Particules runiques tournoyantes
	for i in 8:
		var rune := ColorRect.new()
		rune.size = Vector2(6, 6)
		rune.color = color
		rune.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rune.z_index = 41
		var angle := (float(i) / 8.0) * TAU
		var radius := 60.0
		rune.position = Vector2(cx + cos(angle) * radius, cy + sin(angle) * radius)
		_combat_panel.add_child(rune)
		var r2 = radius + 20.0
		var rtw2 = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		rtw2.tween_property(rune, "position", Vector2(
			cx + cos(angle + PI / 4) * r2,
			cy + sin(angle + PI / 4) * r2
		), 0.25)
		rtw2.parallel().tween_property(rune, "modulate:a", 0.0, 0.3)
		rtw2.tween_callback(func():
			if is_instance_valid(rune): rune.queue_free()
		)

	# Rayon lumineux ascendant
	var beam := ColorRect.new()
	beam.size = Vector2(4, 0)
	beam.color = Color(color.r, color.g, color.b, 0.30)
	beam.position = Vector2(cx - 2, cy)
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam.z_index = 39
	_combat_panel.add_child(beam)
	var btw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	btw.tween_property(beam, "size:y", 200, 0.25)
	btw.parallel().tween_property(beam, "position:y", cy - 100, 0.25)
	btw.parallel().tween_property(beam, "modulate:a", 0.0, 0.35)
	btw.tween_callback(func():
		if is_instance_valid(beam): beam.queue_free()
	)

func _cast_spell(spell_type: String) -> void:
	_spell_cast_effect(spell_type)
	match spell_type:
		"fireball":
			_cast_fireball()
		"lightning":
			_cast_lightning()
		"heal":
			_cast_heal()
		"rage":
			_cast_rage()
		"ice_shard":
			_cast_ice_shard()

func _cast_fireball() -> void:
	if _enemy_unit.get("hp", 0) <= 0:
		_end_combat(true)
		return

	_spell_cast_announce("Boule de Feu", Color(1.0, 0.4, 0.1))
	var base_damage = _hero_unit.get("magic", 15)
	_log_message("[color=#ff5522]Vous lancez Boule de Feu![/color]")
	if SFX and SFX.has_method("play_fireball"):
		SFX.play_fireball()
	_flash_screen(Color(1.0, 0.4, 0.1), 0.2)

	var magic_res = _enemy_unit.get("magic_res", 2)
	var damage = max(1, int((base_damage - magic_res) * randf_range(0.9, 1.1)))
	_enemy_unit["hp"] = max(0, _enemy_unit["hp"] - damage)

	_show_damage_number(_enemy_card, damage, true)
	_log_message("[color=#ff5522]Boule de Feu inflige [color=#ff4444]" + str(damage) + "[/color] degats![/color]")
	_shake_panel(8.0, 0.4, Vector2.RIGHT)
	_update_hp_bars_smooth()

	if _enemy_unit.get("hp", 0) <= 0:
		_end_combat(true)
		return

	_process_next_turn()

func _cast_lightning() -> void:
	if _enemy_unit.get("hp", 0) <= 0:
		_end_combat(true)
		return

	_spell_cast_announce("Éclair", Color(0.6, 0.8, 1.0))
	var base_damage = _hero_unit.get("magic", 20)
	var magic_res = _enemy_unit.get("magic_res", 2)
	var damage = max(1, int((base_damage - magic_res) * randf_range(1.2, 1.5)))
	_enemy_unit["hp"] = max(0, _enemy_unit["hp"] - damage)

	_log_message("[color=#5588ff]Vous lancez Eclair! [/color][color=#ff4444]" + str(damage) + "[/color] degats![/color]")
	if SFX and SFX.has_method("play_lightning"):
		SFX.play_lightning()
	_flash_screen(Color(0.6, 0.8, 1.0), 0.15)
	_shake_panel(6.0, 0.25)
	_show_damage_number(_enemy_card, damage, true)
	_update_hp_bars_smooth()

	if _enemy_unit.get("hp", 0) <= 0:
		_end_combat(true)
		return

	_process_next_turn()

func _cast_heal() -> void:
	_spell_cast_announce("Soin", Color(0.3, 0.9, 0.4))
	var heal_power = _hero_unit.get("magic", 12)
	var max_hp = _hero_unit.get("max_hp", _hero_unit.get("hp", 1))
	var current_hp = _hero_unit.get("hp", 0)
	var heal_amount = min(heal_power, max_hp - current_hp)
	_hero_unit["hp"] = min(max_hp, current_hp + heal_amount)

	_log_message("[color=#22aa44]Vous lancez Soin! +" + str(heal_amount) + " PV[/color]")
	if SFX and SFX.has_method("play_heal"):
		SFX.play_heal()
	_flash_screen(Color(0.3, 0.9, 0.4), 0.2)
	_show_heal_number(_hero_card, heal_amount)
	_update_hp_bars_smooth()
	_process_next_turn()

func _cast_rage() -> void:
	_spell_cast_announce("Fureur", Color(1.0, 0.5, 0.1))
	_hero_attack_buff = true
	_rage_indicator.visible = true
	_log_message("[color=#ff8822]Vous lancez Fureur! (+50% attaque)[/color]")
	_flash_screen(Color(1.0, 0.5, 0.1), 0.2)

	# Effet de lueur rage sur le sprite du héros
	if _hero_sprite_node and is_instance_valid(_hero_sprite_node):
		var glow = create_tween().set_loops().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		glow.tween_property(_hero_sprite_node, "modulate", Color(1.3, 0.8, 0.3), 0.5)
		glow.tween_property(_hero_sprite_node, "modulate", Color(1.0, 0.6, 0.2), 0.5)
		_hero_sprite_node.set_meta("rage_tween", glow)

	_update_unit_displays()
	_process_next_turn()

func _cast_ice_shard() -> void:
	if _enemy_unit.get("hp", 0) <= 0:
		_end_combat(true)
		return

	_spell_cast_announce("Éclat de Glace", Color(0.5, 0.7, 1.0))
	var base_damage = _hero_unit.get("magic", 18)
	var magic_res = _enemy_unit.get("magic_res", 2)
	var damage = max(1, int((base_damage - magic_res) * randf_range(1.5, 1.8)))
	_enemy_unit["hp"] = max(0, _enemy_unit["hp"] - damage)

	_log_message("[color=#6699ff]Eclat de Glace inflige [color=#ff4444]" + str(damage) + "[/color] degats![/color]")
	if SFX and SFX.has_method("play_ice"):
		SFX.play_ice()
	_flash_screen(Color(0.5, 0.7, 1.0), 0.15)
	_shake_panel(8.0, 0.3, Vector2.RIGHT)
	_show_damage_number(_enemy_card, damage, true)
	_update_hp_bars_smooth()

	if _enemy_unit.get("hp", 0) <= 0:
		_end_combat(true)
		return

	_process_next_turn()

func _on_flee_pressed() -> void:
	if not _in_combat or _current_turn != 0:
		return
	_log_message("[color=#8a8a8a]Vous tentez de fuir...[/color]")
	if randf() < 0.5:
		_log_message("[color=#5a9eb8]Fuite reussie![/color]")
		_show_flee_result()
	else:
		_log_message("[color=#c85a5a]Fuite echouee![/color]")
		_process_next_turn()

func _process_hero_attack() -> void:
	if not _in_combat:
		return
	if _enemy_unit.get("hp", 0) <= 0:
		_end_combat(true)
		return

	var attacker = _hero_unit
	var target = _enemy_unit
	var dmg_result := _calculate_damage(attacker, target, false)
	var damage: int = dmg_result.damage
	var is_critical: bool = dmg_result.critical

	target["hp"] = max(0, target["hp"] - damage)

	var crit_tag := "[color=#ffdd44]CRITIQUE! [/color]" if is_critical else ""
	_log_message("[color=#6ec3e0]" + attacker.get("name", "Heros") + "[/color] " + crit_tag + "inflige [color=#ff4444]" + str(damage) + "[/color] degats a " + target.get("name", "Ennemi"))

	_flash_screen(Color(1.0, 0.3, 0.2), 0.1)
	_shake_panel(4.0, 0.2, Vector2.RIGHT)

	_animate_unit_card_hit(_enemy_card)
	_show_damage_number(_enemy_card, damage, false)

	if not _hero_card or not _enemy_card:
		_update_hp_bars_smooth()
		if target["hp"] <= 0:
			_end_combat(true)
		else:
			_process_next_turn()
		return

	var start_pos: Vector2 = _hero_card.global_position + _hero_card.size / 2
	var end_pos: Vector2 = _enemy_card.global_position + _enemy_card.size / 2
	_vfx.projectile_trail(start_pos, end_pos, Color(1.0, 0.7, 0.2), 8)
	_vfx.sword_slash(end_pos, (end_pos - start_pos).normalized(), 1.0)
	_vfx.hit_impact(end_pos, 0.8)
	_vfx.fire_explosion(end_pos, 0.6)

	if is_critical:
		_show_critical_text(end_pos)
		_vfx.critical_hit(end_pos)
		if SFX and SFX.has_method("play_critical"):
			SFX.play_critical()

	if target["hp"] <= 0:
		_log_message("[color=#ff4444]" + target.get("name", "Ennemi") + " est vaincu![/color]")
		if SFX and SFX.has_method("play_death"):
			SFX.play_death()
		_animate_card_death(_enemy_card)
		_vfx.death_effect(end_pos)

	_update_hp_bars_smooth()

	if target["hp"] <= 0:
		_end_combat(true)
		return

	_process_next_turn()

func _process_enemy_turn() -> void:
	if not _in_combat:
		return
	if _hero_unit.get("hp", 0) <= 0:
		_end_combat(false)
		return

	var attacker = _enemy_unit
	var target = _hero_unit
	var dmg_result := _calculate_damage(attacker, target, false)
	var damage: int = dmg_result.damage
	var is_critical: bool = dmg_result.critical

	target["hp"] = max(0, target["hp"] - damage)

	var crit_tag := "[color=#ffdd44]CRITIQUE! [/color]" if is_critical else ""
	if SFX and SFX.has_method("play_sword_hit"):
		SFX.play_sword_hit()
	await get_tree().create_timer(0.3).timeout

	_log_message("[color=#ff6666]" + attacker.get("name", "Ennemi") + "[/color] " + crit_tag + "inflige [color=#ff4444]" + str(damage) + "[/color] degats a " + target.get("name", "Heros"))

	_flash_screen(Color(0.8, 0.1, 0.1), 0.1)
	_shake_panel(6.0, 0.25, Vector2.LEFT)

	_animate_unit_card_hit(_hero_card)
	_show_damage_number(_hero_card, damage, false)

	if _hero_card and _enemy_card:
		var e_start: Vector2 = _enemy_card.global_position + _enemy_card.size / 2
		var e_end: Vector2 = _hero_card.global_position + _hero_card.size / 2
		_vfx.projectile_trail(e_start, e_end, Color(1.0, 0.3, 0.1), 6)
		_vfx.sword_slash(e_end, (e_end - e_start).normalized(), 0.8)
		_vfx.hit_impact(e_end, 0.6)
		_vfx.fire_explosion(e_end, 0.4)

	if is_critical:
		if _hero_card:
			_show_critical_text(_hero_card.global_position + _hero_card.size / 2)
			_vfx.critical_hit(_hero_card.global_position + _hero_card.size / 2)
		if SFX and SFX.has_method("play_critical"):
			SFX.play_critical()

	if target["hp"] <= 0:
		_log_message("[color=#ff4444]" + target.get("name", "Heros") + " est vaincu![/color]")
		if SFX and SFX.has_method("play_death"):
			SFX.play_death()
		_animate_card_death(_hero_card)
		if _hero_card:
			_vfx.death_effect(_hero_card.global_position + _hero_card.size / 2)

	_update_hp_bars_smooth()

	if target["hp"] <= 0:
		_end_combat(false)
		return

	_process_next_turn()

func _calculate_damage(attacker: Dictionary, target: Dictionary, is_magic: bool) -> Dictionary:
	var base_dmg = attacker.get("attack", 10)
	var defense = target.get("defense", 5)
	var random_factor: float = randf_range(0.8, 1.2)

	if is_magic:
		base_dmg = attacker.get("magic", 10)
		defense = target.get("magic_res", 2)

	if _hero_defending and not is_magic:
		defense = int(defense * 1.5)

	if _hero_attack_buff and not is_magic:
		base_dmg = int(base_dmg * 1.5)

	var damage = max(1, int((base_dmg - defense) * random_factor))
	var is_critical: bool = random_factor >= 1.1
	return {"damage": damage, "critical": is_critical}

func _process_next_turn() -> void:
	if not _in_combat:
		return
	_current_turn = 1 - _current_turn

	if _current_turn == 0:
		_round_count += 1
		_round_label.text = "Round " + str(_round_count)
		_turn_label.text = "Votre tour"
		_turn_label.add_theme_color_override("font_color", COLOR_TEAL)
		_action_bar.visible = true
		_hero_defending = false
		_hero_attack_buff = false
		_defense_indicator.visible = false
		_rage_indicator.visible = false
		_hero_mana = mini(_hero_max_mana, _hero_mana + 5)
		_update_mana_display()

		# Réinitialiser les effets visuels des buffs
		if _hero_sprite_node and is_instance_valid(_hero_sprite_node):
			_hero_sprite_node.modulate = Color.WHITE
			if _hero_sprite_node.has_meta("rage_tween"):
				var rt: Tween = _hero_sprite_node.get_meta("rage_tween")
				if rt and rt.is_valid(): rt.kill()
				_hero_sprite_node.remove_meta("rage_tween")
		if _enemy_sprite_node and is_instance_valid(_enemy_sprite_node):
			_enemy_sprite_node.modulate = Color.WHITE

		# Bordure de carte héros brille en bleu
		if _hero_card and is_instance_valid(_hero_card):
			var style = _hero_card.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				style.border_color = Color(0.35, 0.70, 1.0, 0.90)
			create_tween().tween_callback(func():
				if _hero_card and is_instance_valid(_hero_card):
					var s = _hero_card.get_theme_stylebox("panel") as StyleBoxFlat
					if s: s.border_color = Color(0.35, 0.60, 0.85)
			).set_delay(0.5)

		_show_turn_banner("Votre Tour", COLOR_TEAL)
	else:
		_turn_label.text = "Tour ennemi"
		_turn_label.add_theme_color_override("font_color", COLOR_CRIMSON)
		_action_bar.visible = false

		# Bordure de carte ennemi brille en rouge
		if _enemy_card and is_instance_valid(_enemy_card):
			var style = _enemy_card.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				style.border_color = Color(1.0, 0.25, 0.25, 0.90)
			create_tween().tween_callback(func():
				if _enemy_card and is_instance_valid(_enemy_card):
					var s = _enemy_card.get_theme_stylebox("panel") as StyleBoxFlat
					if s: s.border_color = Color(0.85, 0.25, 0.25)
			).set_delay(0.5)

		_show_turn_banner("Tour Ennemi", COLOR_CRIMSON)
		await get_tree().create_timer(0.8).timeout
		_process_enemy_turn()

# ============================================
# UI UPDATES — 1v1 cards
# ============================================

func _update_hp_bars_smooth() -> void:
	# Met à jour les barres de vie avec une transition fluide (sans recréer les cartes)
	var hero_hp = _hero_unit.get("hp", 0)
	var hero_max = _hero_unit.get("max_hp", 1)
	var enemy_hp = _enemy_unit.get("hp", 0)
	var enemy_max = _enemy_unit.get("max_hp", 1)

	if _hero_hp_fill and is_instance_valid(_hero_hp_fill):
		var hp_ratio = float(hero_hp) / max(1, hero_max)
		var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_hero_hp_fill, "size:x", max(1, 142 * hp_ratio), 0.25)
		var col = COLOR_GREEN if hp_ratio > 0.5 else (Color(0.95, 0.75, 0.10) if hp_ratio > 0.25 else COLOR_RED)
		tw.parallel().tween_property(_hero_hp_fill, "color", col, 0.25)
	if _enemy_hp_fill and is_instance_valid(_enemy_hp_fill):
		var hp_ratio = float(enemy_hp) / max(1, enemy_max)
		var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_enemy_hp_fill, "size:x", max(1, 142 * hp_ratio), 0.25)
		var col = COLOR_GREEN if hp_ratio > 0.5 else (Color(0.95, 0.75, 0.10) if hp_ratio > 0.25 else COLOR_RED)
		tw.parallel().tween_property(_enemy_hp_fill, "color", col, 0.25)

	# Mettre à jour les labels texte
	for c in _hero_card.get_children():
		if c is Label and c.position.y == 26:
			c.text = str(hero_hp) + "/" + str(hero_max)
		if c is Label and c.position.y == 60:
			var pct = int(float(hero_hp) / max(1, hero_max) * 100)
			c.text = "HP: " + str(pct) + "%"
	for c in _enemy_card.get_children():
		if c is Label and c.position.y == 26:
			c.text = str(enemy_hp) + "/" + str(enemy_max)
		if c is Label and c.position.y == 60:
			var pct = int(float(enemy_hp) / max(1, enemy_max) * 100)
			c.text = "HP: " + str(pct) + "%"

func _update_unit_displays() -> void:
	if _hero_card:
		_hero_card.queue_free()
	if _enemy_card:
		_enemy_card.queue_free()
	if _hero_sprites_container:
		_hero_sprites_container.queue_free()
	if _enemy_sprites_container:
		_enemy_sprites_container.queue_free()
	_hero_sprite_node = null
	_enemy_sprite_node = null
	_hero_hp_fill = null
	_enemy_hp_fill = null

	var vw: float = 	get_viewport().size.x
	var cx: float = vw * 0.5
	var spacing: float = vw * 0.22

	_hero_card = _create_unit_card(_hero_unit, true)
	_enemy_card = _create_unit_card(_enemy_unit, false)

	_hero_card.position = Vector2(cx - spacing - 80, 280)
	_hero_card.custom_minimum_size = Vector2(160, 85)
	_combat_panel.add_child(_hero_card)

	_enemy_card.position = Vector2(cx + spacing - 80, 280)
	_enemy_card.custom_minimum_size = Vector2(160, 85)
	_combat_panel.add_child(_enemy_card)

	_add_creature_sprite(_hero_unit, true)
	_add_creature_sprite(_enemy_unit, false)

	_hero_info_label.text = _hero_unit.get("name", "Heros") + " | ATK:" + str(_hero_unit.get("attack", 0)) + " DEF:" + str(_hero_unit.get("defense", 0))
	_enemy_info_label.text = _enemy_unit.get("name", "Ennemi") + " | ATK:" + str(_enemy_unit.get("attack", 0)) + " DEF:" + str(_enemy_unit.get("defense", 0))

func _add_creature_sprite(unit: Dictionary, is_hero: bool) -> void:
	var unit_name: String = unit.get("name", "Heros" if is_hero else "Ennemi")
	var direction: String = "east" if is_hero else "west"

	var tex: Texture2D
	var target_size: float = 240.0

	if is_hero:
		tex = _get_creature_texture(unit_name, direction)
		if not tex:
			return
	else:
		tex = _generate_enemy_texture(unit_name)
		if not tex:
			return

	var tex_size: float = 48.0 if is_hero else 64.0
	var scale_val: float = target_size / tex_size

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2(scale_val, scale_val)
	sprite.z_index = 10
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var outline_shader := load("res://shaders/sprite_outline.gdshader")
	if outline_shader:
		var mat := ShaderMaterial.new()
		mat.shader = outline_shader
		if is_hero:
			mat.set_shader_parameter("outline_color", Color(0, 0, 0, 0.8))
			mat.set_shader_parameter("outline_width", 1.0)
			mat.set_shader_parameter("glow_color", Color(1.0, 0.9, 0.5, 0.3))
			mat.set_shader_parameter("glow_width", 4.0)
			mat.set_shader_parameter("glow_intensity", 0.2)
		else:
			mat.set_shader_parameter("outline_color", Color(0, 0, 0, 0.85))
			mat.set_shader_parameter("outline_width", 1.0)
			mat.set_shader_parameter("glow_color", Color(0.8, 0.2, 0.2, 0.3))
			mat.set_shader_parameter("glow_width", 3.0)
			mat.set_shader_parameter("glow_intensity", 0.15)
		sprite.material = mat

	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.z_index = 10

	var vw: float = 	get_viewport().size.x
	var cx: float = vw * 0.5
	var spacing: float = vw * 0.22
	var sprite_centered_y: int = 490
	if is_hero:
		container.position = Vector2(cx - spacing, sprite_centered_y)
		_hero_sprite_node = sprite
	else:
		container.position = Vector2(cx + spacing, sprite_centered_y)
		_enemy_sprite_node = sprite

	var shadow := ColorRect.new()
	shadow.size = Vector2(120, 18)
	shadow.position = Vector2(-60, int(target_size * 0.5) + 4)
	shadow.color = Color(0, 0, 0, 0.30)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(shadow)

	container.add_child(sprite)
	_combat_panel.add_child(container)

	if is_hero:
		_hero_sprites_container = container
	else:
		_enemy_sprites_container = container

	var tw := create_tween().set_loops().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(container, "position:y", container.position.y + 10, 1.4)
	tw.tween_property(container, "position:y", container.position.y, 1.4)

func _create_unit_card(unit: Dictionary, is_hero: bool) -> Panel:
	var card = Panel.new()
	card.size = Vector2(160, 85)

	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.04, 0.04, 0.08, 0.95)
	card_style.border_color = Color(0.35, 0.60, 0.85) if is_hero else Color(0.85, 0.25, 0.25)
	card_style.border_width_left = 2
	card_style.border_width_right = 2
	card_style.border_width_top = 2
	card_style.border_width_bottom = 2
	card_style.corner_radius_top_left = 12
	card_style.corner_radius_top_right = 12
	card_style.corner_radius_bottom_left = 12
	card_style.corner_radius_bottom_right = 12
	card.add_theme_stylebox_override("panel", card_style)

	var card_unit_name: String = unit.get("name", "Unite")
	var card_dir: String = "east" if is_hero else "west"

	var hp_ratio: float = float(unit.get("hp", 1)) / max(1, unit.get("max_hp", 1))

	var name_label = Label.new()
	name_label.position = Vector2(8, 4)
	name_label.size = Vector2(144, 18)
	name_label.text = card_unit_name
	name_label.add_theme_color_override("font_color", Color(0.35, 0.60, 0.85) if is_hero else Color(0.85, 0.25, 0.25))
	name_label.add_theme_font_size_override("font_size", 12)
	card.add_child(name_label)

	var hp_bar_bg = ColorRect.new()
	hp_bar_bg.position = Vector2(8, 26)
	hp_bar_bg.size = Vector2(144, 12)
	hp_bar_bg.color = Color(0.15, 0.03, 0.03)
	card.add_child(hp_bar_bg)

	var hp_fill = ColorRect.new()
	hp_fill.position = Vector2(9, 27)
	hp_fill.size = Vector2(max(1, 142 * hp_ratio), 10)
	hp_fill.color = COLOR_GREEN if hp_ratio > 0.5 else (Color(0.95, 0.75, 0.10) if hp_ratio > 0.25 else COLOR_RED)
	card.add_child(hp_fill)
	if is_hero:
		_hero_hp_fill = hp_fill
	else:
		_enemy_hp_fill = hp_fill

	var hp_text = Label.new()
	hp_text.position = Vector2(8, 26)
	hp_text.size = Vector2(144, 12)
	hp_text.text = str(unit.get("hp", 0)) + "/" + str(unit.get("max_hp", 1))
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_text.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	hp_text.add_theme_font_size_override("font_size", 9)
	card.add_child(hp_text)

	var stats = Label.new()
	stats.position = Vector2(8, 42)
	stats.size = Vector2(144, 16)
	var atk = unit.get("attack", 0)
	var def = unit.get("defense", 0)
	var sp = ""
	if unit.get("magic", 0) > 0:
		sp = " MAG:" + str(unit.get("magic", 0))
	stats.text = "ATK:" + str(atk) + " DEF:" + str(def) + sp
	stats.add_theme_color_override("font_color", Color(0.80, 0.78, 0.72))
	stats.add_theme_font_size_override("font_size", 10)
	card.add_child(stats)

	var hp_pct = int(hp_ratio * 100)
	var hp_pct_label = Label.new()
	hp_pct_label.position = Vector2(8, 60)
	hp_pct_label.size = Vector2(144, 14)
	hp_pct_label.text = "HP: " + str(hp_pct) + "%"
	var hp_pct_color = COLOR_GREEN if hp_pct > 50 else (Color(0.95, 0.75, 0.10) if hp_pct > 25 else COLOR_RED)
	hp_pct_label.add_theme_color_override("font_color", hp_pct_color)
	hp_pct_label.add_theme_font_size_override("font_size", 10)
	card.add_child(hp_pct_label)

	if _hero_defending and is_hero:
		var sh = Label.new()
		sh.position = Vector2(8, 72)
		sh.size = Vector2(144, 12)
		sh.text = "DEFENSE +"
		sh.add_theme_color_override("font_color", COLOR_TEAL)
		sh.add_theme_font_size_override("font_size", 10)
		card.add_child(sh)

	if _hero_attack_buff and is_hero:
		var ra = Label.new()
		ra.position = Vector2(8, 72)
		ra.size = Vector2(144, 12)
		ra.text = "FUREUR +"
		ra.add_theme_color_override("font_color", Color(0.95, 0.55, 0.10))
		ra.add_theme_font_size_override("font_size", 10)
		card.add_child(ra)

	return card

# ============================================
# VISUAL EFFECTS
# ============================================

func _show_turn_banner(text: String, color: Color) -> void:
	var vp = get_viewport().get_visible_rect().size

	# Barre décorative
	var bar = ColorRect.new()
	bar.size = Vector2(vp.x, 40)
	bar.color = Color(0.04, 0.03, 0.05, 0.85)
	bar.position = Vector2(0, -40)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.z_index = 25
	_combat_panel.add_child(bar)
	var bar_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	bar_tw.tween_property(bar, "position:y", 200, 0.25)
	bar_tw.tween_interval(0.5)
	bar_tw.tween_property(bar, "position:y", -40, 0.2)
	bar_tw.tween_callback(func():
		if is_instance_valid(bar): bar.queue_free()
	)

	# Ligne décorative
	var line = ColorRect.new()
	line.size = Vector2(vp.x, 2)
	line.color = color
	line.position = Vector2(0, 240)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.z_index = 26
	_combat_panel.add_child(line)
	var line_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	line_tw.tween_property(line, "modulate:a", 1.0, 0.2)
	line_tw.tween_interval(0.5)
	line_tw.tween_property(line, "modulate:a", 0.0, 0.2)
	line_tw.tween_callback(func():
		if is_instance_valid(line): line.queue_free()
	)

	var banner = Label.new()
	banner.text = text
	banner.add_theme_font_size_override("font_size", 24)
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.40))
	banner.add_theme_constant_override("outline_size", 2)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.position = Vector2(0, 200)
	banner.size = Vector2(0, 40)
	banner.z_index = 27
	_combat_panel.add_child(banner)

	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(banner, "position:y", 220, 0.6)
	tween.parallel().tween_property(banner, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func(): banner.queue_free())

func _show_damage_number(target_node: Control, damage: int, is_magic: bool) -> void:
	if not target_node:
		return
	var dmg_label = Label.new()
	dmg_label.text = "-" + str(damage)
	dmg_label.add_theme_font_size_override("font_size", 22 if not is_magic else 26)
	dmg_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2) if not is_magic else Color(0.9, 0.4, 1.0))
	dmg_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.80))

	var bounds: Vector2 = target_node.size
	dmg_label.position = target_node.position + Vector2(bounds.x * 0.5, -10)
	dmg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dmg_label.custom_minimum_size = Vector2(60, 30)
	target_node.add_child(dmg_label)

	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(dmg_label, "position:y", dmg_label.position.y - 30, 0.6)
	tween.parallel().tween_property(dmg_label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func(): if is_instance_valid(dmg_label): dmg_label.queue_free())

func _show_heal_number(target_node: Control, amount: int) -> void:
	if not target_node:
		return
	var heal_label = Label.new()
	heal_label.text = "+" + str(amount)
	heal_label.add_theme_font_size_override("font_size", 22)
	heal_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	heal_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.80))

	var bounds: Vector2 = target_node.size
	heal_label.position = target_node.position + Vector2(bounds.x * 0.5, -10)
	heal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heal_label.custom_minimum_size = Vector2(60, 30)
	target_node.add_child(heal_label)

	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(heal_label, "position:y", heal_label.position.y - 30, 0.6)
	tween.parallel().tween_property(heal_label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func(): if is_instance_valid(heal_label): heal_label.queue_free())

func _show_critical_text(pos: Vector2) -> void:
	var crit = Label.new()
	crit.text = "CRITIQUE!"
	crit.add_theme_font_size_override("font_size", 26)
	crit.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15))
	crit.add_theme_color_override("font_shadow_color", Color(0.5, 0.2, 0.0, 0.90))
	crit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crit.position = pos - _combat_panel.position
	crit.position.y -= 30
	crit.custom_minimum_size = Vector2(160, 36)
	crit.scale = Vector2(0.5, 0.5)
	_combat_panel.add_child(crit)

	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(crit, "scale", Vector2(1.2, 1.2), 0.15)
	tween.tween_property(crit, "scale", Vector2(1.0, 1.0), 0.1)
	tween.parallel().tween_property(crit, "position:y", crit.position.y - 30, 0.5)
	tween.parallel().tween_property(crit, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func(): if is_instance_valid(crit): crit.queue_free())

func _animate_unit_card_hit(card: Control) -> void:
	if not card:
		return
	# Freeze-frame visuel: la carte se décolore brièvement
	card.material = _get_hit_flash_material()
	var orig_pos = card.position
	var shake = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	shake.tween_property(card, "position", orig_pos + Vector2(10, 0), 0.04)
	shake.tween_property(card, "position", orig_pos - Vector2(7, 2), 0.04)
	shake.tween_property(card, "position", orig_pos + Vector2(5, -1), 0.04)
	shake.tween_property(card, "position", orig_pos, 0.05)

	var flash = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	flash.tween_property(card, "modulate", Color(1.4, 0.4, 0.4), 0.04)
	flash.tween_property(card, "modulate", Color.WHITE, 0.18)
	flash.tween_callback(func():
		if card and is_instance_valid(card):
			card.material = null
	)

func _get_hit_flash_material() -> ShaderMaterial:
	# Simple shader de flash lumineux
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb, tex.a);
}
"""
	mat.shader = shader
	return mat

func _animate_card_death(card: Control) -> void:
	if not card:
		return
	# Particules d'âme qui s'élèvent
	var card_center = card.global_position + card.size / 2
	for i in 6:
		var soul = ColorRect.new()
		soul.size = Vector2(randf_range(4, 8), randf_range(4, 8))
		soul.color = Color(0.7, 0.6, 0.4, 0.70)
		soul.position = card_center + Vector2(randf_range(-20, 20), randf_range(-10, 10))
		soul.z_index = 50
		soul.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_combat_panel.add_child(soul)
		var stw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		stw.tween_property(soul, "position", soul.position + Vector2(randf_range(-15, 15), -40 - randf_range(0, 20)), 0.5)
		stw.parallel().tween_property(soul, "modulate:a", 0.0, 0.5)
		stw.tween_callback(func(): if is_instance_valid(soul): soul.queue_free())

	# La carte rétrécit et devient sombre
	var dt = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	dt.tween_property(card, "modulate", Color(0.3, 0.0, 0.0), 0.3)
	dt.parallel().tween_property(card, "scale", Vector2(0.4, 0.4), 0.3)
	dt.parallel().tween_property(card, "rotation", deg_to_rad(randf_range(-5, 5)), 0.3)

	# Flash d'écran rouge sombre
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.3, 0.0, 0.0, 0.15)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_panel.add_child(flash)
	var ftw = create_tween()
	ftw.tween_property(flash, "modulate:a", 0.0, 0.3)
	ftw.tween_callback(func(): if is_instance_valid(flash): flash.queue_free())

func _flash_screen(color: Color, duration: float) -> void:
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_panel.add_child(flash)
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, duration)
	tween.tween_callback(func(): flash.queue_free())

func _shake_panel(strength: float, duration: float, direction: Vector2 = Vector2.RIGHT) -> void:
	if not _combat_panel:
		return
	var orig = _combat_panel.position
	var shake = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	shake.tween_property(_combat_panel, "position", orig + direction * strength, duration * 0.15)
	shake.tween_property(_combat_panel, "position", orig - direction * strength * 0.6, duration * 0.15)
	shake.tween_property(_combat_panel, "position", orig + direction * strength * 0.3, duration * 0.15)
	shake.tween_property(_combat_panel, "position", orig, duration * 0.15)

func _log_message(msg: String) -> void:
	if _combat_log:
		_combat_log.append_text(msg + "\n")
