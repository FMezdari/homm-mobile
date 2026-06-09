extends CanvasLayer

# TacticalCombat — Combat tactique sur grille hexagonale (style HoMM3)

# HexTile — Tuile hexagonale avec dessin vectoriel
class HexTile extends Control:
	signal hex_pressed(hq: int, hr: int)
	
	var hq: int
	var hr: int
	var hex_color: Color = Color(0.22, 0.38, 0.18)
	var border_color: Color = Color(0.15, 0.15, 0.12, 0.35)
	var is_hovered: bool = false
	
	func _init(p_q: int, p_r: int, p_color: Color):
		hq = p_q
		hr = p_r
		hex_color = p_color
		mouse_filter = MOUSE_FILTER_STOP
		mouse_entered.connect(_on_mouse_enter)
		mouse_exited.connect(_on_mouse_exit)
	
	func _draw():
		var pts := _hex_points()
		# Fond principal avec léger dégradé (bords plus sombres)
		draw_colored_polygon(pts, hex_color)
		# Sous-couche légèrement plus claire au centre (effet de profondeur)
		var inner_pts := _hex_points_inner(0.75)
		draw_colored_polygon(inner_pts, Color(
			hex_color.r * 1.15,
			hex_color.g * 1.15,
			hex_color.b * 1.15,
			0.50
		))
		var closed_pts := PackedVector2Array(pts)
		closed_pts.append(pts[0])
		# Bordure extérieure fine
		draw_polyline(closed_pts, border_color, 1.5)
		# Légère lueur interne sur le bord pour un effet « biseauté »
		draw_polyline(closed_pts, Color(
			hex_color.r * 1.5,
			hex_color.g * 1.5,
			hex_color.b * 1.5,
			0.08
		), 3.0)
		if is_hovered:
			# Lueur interne dorée au survol — plus intense
			draw_colored_polygon(pts, Color(0.95, 0.85, 0.40, 0.15))
			draw_colored_polygon(inner_pts, Color(0.95, 0.85, 0.40, 0.08))
			# Bordure lumineuse épaisse
			draw_polyline(closed_pts, Color(0.95, 0.85, 0.40, 0.55), 2.5)
	
	func _hex_points() -> PackedVector2Array:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var r = min(cx, cy) * 0.92
		var pts := PackedVector2Array()
		for i in range(6):
			var a = deg_to_rad(60.0 * i - 30.0)
			pts.append(Vector2(cx + r * cos(a), cy + r * sin(a)))
		return pts
	
	func _hex_points_inner(scale_factor: float) -> PackedVector2Array:
		var cx = size.x / 2.0
		var cy = size.y / 2.0
		var r = min(cx, cy) * 0.92 * scale_factor
		var pts := PackedVector2Array()
		for i in range(6):
			var a = deg_to_rad(60.0 * i - 30.0)
			pts.append(Vector2(cx + r * cos(a), cy + r * sin(a)))
		return pts
	
	func set_color(c: Color) -> void:
		hex_color = c
		queue_redraw()
	
	func set_border(c: Color) -> void:
		border_color = c
		queue_redraw()
	
	func _on_mouse_enter():
		is_hovered = true
		queue_redraw()
	
	func _on_mouse_exit():
		is_hovered = false
		queue_redraw()
	
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hex_pressed.emit(hq, hr)
			accept_event()

signal combat_ended(won: bool)
signal combat_victory(gold_reward: int, xp_reward: int)
signal combat_defeat()
signal combat_fled()

# Dimensions de la grille hexagonale
const HEX_COLS: int = 11
const HEX_ROWS: int = 7
const HEX_SIZE: float = 42.0
const HEX_W: float = HEX_SIZE * 2.0
const HEX_H: float = HEX_SIZE * sqrt(3.0)

# Couleurs
const COLOR_BG := Color(0.04, 0.03, 0.06)
const COLOR_GOLD := Color(0.92, 0.75, 0.18)
const COLOR_TEAL := Color(0.12, 0.55, 0.62)
const COLOR_CRIMSON := Color(0.75, 0.12, 0.14)
const COLOR_GREEN := Color(0.18, 0.65, 0.22)
const COLOR_BLUE := Color(0.15, 0.35, 0.65)

# Mapping des types d'unités GameData -> type de sprite procédural (SpriteGenerator)
# Utilise les types japonais du générateur procédural quand disponible
const UNIT_CREATURE_MAP: Dictionary = {
	"ashigaru": "ashigaru", "samurai": "samurai", "archer": "archer",
	"yari": "ashigaru", "cavalier": "samurai", "ninja": "ninja",
	"monk": "monk", "onmyoji": "tengu", "oni": "goblin",
	"daimyo": "samurai", "sohei": "monk",
	"goblin": "goblin", "skeleton": "skeleton",
	"oni_brute": "goblin", "bandit": "ashigaru", "oni_mage": "tengu",
}

# État du combat
enum Phase { HERO_TURN, ENEMY_TURN, ANIMATING, VICTORY, DEFEAT }
var _phase: int = Phase.HERO_TURN

# Armées
var _hero_army: GameData.Army = null
var _enemy_army: GameData.Army = null

# Unités sur la grille (indexés par position hex)
var _grid_units: Dictionary = {}  # "q,r" -> CombatUnit
var _all_units: Array[CombatUnit] = []
var _turn_order: Array[CombatUnit] = []
var _current_unit_index: int = 0
var _selected_unit: CombatUnit = null
var _active_unit: CombatUnit = null

# UI
var _panel: Panel
var _bg_rect: ColorRect
var _hex_container: Control
var _info_label: Label
var _action_bar: HBoxContainer
var _turn_queue: Control  # Devenu un container plus riche
var _combat_log: RichTextLabel
var _round_label: Label
var _phase_label: Label
var _end_turn_btn: Button
var _context_banner: Label  # Bannière contextuelle pour messages importants

# Panneau de stats d'unité
var _stat_panel: Panel
var _stat_panel_visible: bool = false

# Timing pour animations de pulsation
var _pulse_time: float = 0.0

# Hex tiles visuals
var _hex_tiles: Dictionary = {}  # "q,r" -> Button

# Movement/Action state
var _unit_moved: bool = false
var _unit_acted: bool = false
var _current_round: int = 1
var _rng: RandomNumberGenerator

# Mode tracking
var _move_mode_active: bool = false
var _attack_mode_active: bool = false
var _tooltip: Panel = null

# Combat stats tracking
var _player_dmg_dealt: int = 0
var _player_units_killed: int = 0
var _player_units_lost: int = 0

# Sprites
var _sprite_generator: SpriteGenerator
var _hero_samurai_texture: Texture2D
var _creature_sprites: Dictionary = {}
var _creature_frames: Dictionary = {}

# Animations
var _samurai_anims: Dictionary = {}  # "anim_name" -> Array[Texture2D]
var _effect_frames: Dictionary = {}  # "effect_name" -> Array[Texture2D]

# VFX
var _vfx: CombatVFX = null

# Background
var _bg_texture: Texture2D = null
var _bg_texture_rect: TextureRect = null
var _bg_particles: Array[ColorRect] = []
var _bg_particle_tweens: Array[Tween] = []
var _grid_shadow: ColorRect = null

# ============================================
# CombatUnit — Représente une unité sur la grille
# ============================================
class CombatUnit:
	var stack: GameData.UnitStack
	var q: int  # hex coord q (column)
	var r: int  # hex coord r (row)
	var is_hero: bool
	var has_moved: bool = false
	var has_acted: bool = false
	var defending: bool = false
	var node: Node2D
	var sprite: Sprite2D
	var hp_bar: ColorRect
	var selection_ring: ColorRect
	var tint_overlay: ColorRect
	
	# Animation state
	var anim_frames: Array[Texture2D] = []
	var anim_index: int = 0
	var anim_timer: float = 0.0
	var anim_fps: float = 5.0
	var anim_loop: bool = true
	var anim_playing: bool = false
	var anim_on_finish: Callable = Callable()
	
	func _init(p_stack: GameData.UnitStack, p_q: int, p_r: int, p_is_hero: bool):
		stack = p_stack
		q = p_q
		r = p_r
		is_hero = p_is_hero
	
	func get_speed() -> int:
		return stack.get_speed()
	
	func get_attack() -> int:
		return stack.get_attack()
	
	func get_defense() -> int:
		return stack.get_defense()
	
	func get_damage_min() -> int:
		var dmg = stack.get_damage_min()
		if defending:
			dmg = max(1, dmg / 2)
		return dmg
	
	func get_damage_max() -> int:
		var dmg = stack.get_damage_max()
		if defending:
			dmg = max(1, dmg / 2)
		return dmg
	
	func get_name() -> String:
		return stack.get_name()
	
	func is_alive() -> bool:
		return stack.is_alive()
	
	func take_damage(dmg: int) -> int:
		var defense = get_defense()
		var reduced = max(1, dmg - defense / 2)
		return stack.take_damage(reduced)
	
	func can_act() -> bool:
		return is_alive() and not (has_moved and has_acted)

# ============================================
# INIT
# ============================================
func _ready() -> void:
	visible = false
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_sprite_generator = SpriteGenerator.new()
	if ResourceLoader.exists("res://assets/heroes/hero_samurai_down.png"):
		_hero_samurai_texture = load("res://assets/heroes/hero_samurai_down.png")
	else:
		# Générer un sprite héro procédural
		_hero_samurai_texture = _sprite_generator._generate_sprite("hero", 64, randi())
	_preload_combat_sprites()
	_vfx = CombatVFX.new(self) if ClassDB.class_exists("CombatVFX") else null

# ============================================
# DÉMARRAGE DU COMBAT
# ============================================
func start_combat(hero_army: GameData.Army, enemy_army: GameData.Army) -> void:
	_hero_army = hero_army
	_enemy_army = enemy_army
	_current_round = 1
	_phase = Phase.HERO_TURN

	_build_ui()
	place_units()
	determine_turn_order()
	show_combat()
	start_round()

func show_combat() -> void:
	visible = true
	# Flash d'entrée
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 1.0, 1.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 30
	_panel.add_child(flash)
	var ftw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	ftw.tween_property(flash, "modulate:a", 0.0, 0.3)
	ftw.tween_callback(func():
		if is_instance_valid(flash): flash.queue_free()
	)

	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.3)
	tw.tween_callback(func():
		_show_turn_banner("COMBAT!", COLOR_GOLD)
	)

func hide_combat() -> void:
	var tw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(_panel, "scale", Vector2(0.9, 0.9), 0.3)
	tw.tween_callback(func(): visible = false)

# ============================================
# HEX GRID UTILITIES
# ============================================
static func hex_to_pixel(q: int, r: int) -> Vector2:
	var x = HEX_SIZE * (3.0 / 2.0 * q)
	var y = HEX_SIZE * (sqrt(3.0) / 2.0 * q + sqrt(3.0) * r)
	return Vector2(x, y)

static func pixel_to_hex(px: float, py: float) -> Vector2i:
	var q = (2.0 / 3.0 * px) / HEX_SIZE
	var r = (-1.0 / 3.0 * px + sqrt(3.0) / 3.0 * py) / HEX_SIZE
	return _hex_round(q, r)

static func _hex_round(q: float, r: float) -> Vector2i:
	var s = -q - r
	var rq = round(q)
	var rr = round(r)
	var rs = round(s)
	var q_diff = abs(rq - q)
	var r_diff = abs(rr - r)
	var s_diff = abs(rs - s)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))

static func hex_distance(a_q: int, a_r: int, b_q: int, b_r: int) -> int:
	var dq = a_q - b_q
	var dr = a_r - b_r
	var ds = (-a_q - a_r) - (-b_q - b_r)
	return max(abs(dq), abs(dr), abs(ds))

static func hex_neighbors(q: int, r: int) -> Array[Vector2i]:
	return [
		Vector2i(q+1, r), Vector2i(q-1, r),
		Vector2i(q, r+1), Vector2i(q, r-1),
		Vector2i(q+1, r-1), Vector2i(q-1, r+1),
	]

static func hex_key(q: int, r: int) -> String:
	return str(q) + "," + str(r)

func is_valid_hex(q: int, r: int) -> bool:
	return q >= 0 and q < HEX_COLS and r >= 0 and r < HEX_ROWS

func is_hex_occupied(q: int, r: int) -> bool:
	return _grid_units.has(hex_key(q, r))

func get_unit_at(q: int, r: int) -> CombatUnit:
	return _grid_units.get(hex_key(q, r), null)

# ============================================
# ANIMATION IDLE (bob)
# ============================================
var _idle_time: float = 0.0
var _anim_paused: bool = false
var _unit_base_positions: Dictionary = {}  # CombatUnit -> Vector2 base

func _process(delta: float) -> void:
	if not visible:
		return
	_idle_time += delta
	_pulse_time += delta
	# Pulsation des hexagones en surbrillance
	var pulse = (sin(_pulse_time * 3.0) * 0.5 + 0.5) * 0.15
	if _phase == Phase.HERO_TURN:
		for key in _hex_tiles:
			var tile = _hex_tiles[key] as HexTile
			if not tile: continue
			# Ne pulser que les cases avec highlight (move range ou attack)
			var c = tile.hex_color
			if c.a > 0.3 and c.a < 0.9:
				var bright = c.lightened(pulse * 0.5)
				# On ne modifie que la couleur de dessus via queue_redraw périodique
				# Simplification: juste un petit tween par tile est trop lourd, on skip
				pass

	for u in _all_units:
		if u.node and is_instance_valid(u.node):
			# Frame animation (joue même pendant anim pause)
			if u.anim_playing and u.anim_frames.size() > 0 and u.sprite and is_instance_valid(u.sprite):
				u.anim_timer += delta
				if u.anim_timer >= 1.0 / u.anim_fps:
					u.anim_timer = 0.0
					u.anim_index += 1
					if u.anim_index >= u.anim_frames.size():
						if u.anim_loop:
							u.anim_index = 0
						else:
							u.anim_index = u.anim_frames.size() - 1
							u.anim_playing = false
							if u.anim_on_finish.is_valid():
								var cb = u.anim_on_finish
								u.anim_on_finish = Callable()
								cb.call()
					if u.anim_index < u.anim_frames.size():
						u.sprite.texture = u.anim_frames[u.anim_index]
			# Idle bob (skip si paused)
			if _anim_paused or not u.is_alive():
				continue
			var bob = sin(_idle_time * 1.5 + u.q * 2.0 + u.r * 3.0) * 1.2
			var base_pos = _unit_base_positions.get(u)
			if base_pos:
				u.node.position.y = base_pos.y + bob

# Configuration d'animation pour sprites samurai
const SAMURAI_ANIM_CONFIG: Dictionary = {
	"idle":   { "row": 0, "cols": 6, "fps": 5.0, "loop": true },
	"walk":   { "row": 1, "cols": 6, "fps": 9.0, "loop": true },
	"attack": { "row": 2, "cols": 6, "fps": 12.0, "loop": false },
	"hurt":   { "row": 3, "cols": 6, "fps": 8.0, "loop": false },
	"block":  { "row": 4, "cols": 6, "fps": 6.0, "loop": false },
	"death":  { "row": 5, "cols": 6, "fps": 8.0, "loop": false },
}

# ============================================
# SPRITES DES CRÉATURES
# ============================================
func _preload_combat_sprites() -> void:
	# Charger les frames samurai
	var _samurai_frames: Array[Texture2D] = []
	for r in range(10):
		for c in range(6):
			var path: String = "res://assets/samurai_units/frames/samurai_%d_%d.png" % [r, c]
			var tex: Texture2D = load(path)
			if tex:
				_samurai_frames.append(tex)
	if _samurai_frames.size() > 0:
		print("✓ " + str(_samurai_frames.size()) + " frames samurai chargées")
	else:
		print("⚠ Aucune frame samurai chargée")
	
	# Créer les dictionnaires d'animations à partir des frames chargées
	_samurai_anims.clear()
	for anim_name in SAMURAI_ANIM_CONFIG:
		var cfg = SAMURAI_ANIM_CONFIG[anim_name]
		var start_idx = cfg.row * 6
		var frames: Array[Texture2D] = []
		for i in range(cfg.cols):
			var idx = start_idx + i
			if idx < _samurai_frames.size():
				frames.append(_samurai_frames[idx])
		_samurai_anims[anim_name] = frames
	
	# Charger les effets
	_effect_frames.clear()
	for effect_name in ["slash", "blood"]:
		var eff_frames: Array[Texture2D] = []
		for i in range(2):
			var path: String = "res://assets/samurai_units/frames/%s/%s_%d.png" % [effect_name, effect_name, i]
			var tex: Texture2D = load(path)
			if tex:
				eff_frames.append(tex)
		if eff_frames.size() > 0:
			_effect_frames[effect_name] = eff_frames
	
	# Charger les sprites HoMM3 legacy
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
			print("✓ Sprites HoMM3 chargés: " + creature)
		else:
			print("⚠ Sprite HoMM3 non trouvé: " + creature)

func _play_unit_anim(unit: CombatUnit, anim_name: String, fps: float = -1.0, loop: bool = true, on_finish: Callable = Callable()) -> void:
	if not unit:
		return
	var frames: Array = _samurai_anims.get(anim_name, [])
	if frames.size() == 0:
		return
	unit.anim_frames = frames
	unit.anim_index = 0
	unit.anim_timer = 0.0
	unit.anim_fps = fps if fps > 0 else SAMURAI_ANIM_CONFIG.get(anim_name, {}).get("fps", 6.0)
	unit.anim_loop = loop
	unit.anim_playing = true
	unit.anim_on_finish = on_finish
	if unit.sprite and is_instance_valid(unit.sprite) and frames.size() > 0:
		unit.sprite.texture = frames[0]

func _get_unit_texture(unit_id: String, is_hero_side: bool) -> Texture2D:
	if is_hero_side:
		# Les héros ont un sprite généré spécial
		if unit_id == "samurai" and _hero_samurai_texture:
			return _hero_samurai_texture
		var hero_tex: Texture2D = _sprite_generator._generate_sprite("hero", 64, _rng.randi())
		if hero_tex:
			return hero_tex
	var creature_name: String = UNIT_CREATURE_MAP.get(unit_id, "skeleton")
	# Priorité : sprite procédural japonais, puis HoMM3 legacy
	var generated_type: String = "enemy_" + creature_name
	var gen: ImageTexture = _sprite_generator._generate_sprite(generated_type, 48, _rng.randi())
	if gen:
		# Vérifier que le sprite n'est pas juste un cercle gris (fallback)
		var gen_size = gen.get_size()
		if gen_size.x > 0 and gen_size.y > 0:
			var gen_img: Image = gen.get_image()
			if gen_img:
				var is_fallback = true
				# Échantillonner quelques pixels pour vérifier que ce n'est pas le fallback gris
				for sx in [12, 24, 36]:
					for sy in [12, 24, 36]:
						var pix = gen_img.get_pixel(sx, sy)
						if pix.a > 0 and (pix.r > 0.05 or pix.g > 0.05 or pix.b > 0.05):
							if abs(pix.r - 0.5) > 0.1 or abs(pix.g - 0.5) > 0.1 or abs(pix.b - 0.5) > 0.1:
								is_fallback = false
								break
					if not is_fallback:
						break
				if not is_fallback:
					return gen
	# Fallback HoMM3
	var frames: Array = _creature_frames.get(creature_name, _creature_frames.get("skeleton", []))
	if frames.size() > 0:
		return frames[_rng.randi() % frames.size()]
	var static_sprite: Texture2D = _creature_sprites.get(creature_name)
	if static_sprite:
		return static_sprite
	return _sprite_generator._generate_sprite("enemy_skeleton", 48, _rng.randi())
# PLACEMENT DES UNITÉS
# ============================================
func place_units() -> void:
	_grid_units.clear()
	_all_units.clear()

	var hero_stacks = _hero_army.get_alive_stacks()
	var enemy_stacks = _enemy_army.get_alive_stacks()

	var hero_cols: Array[int] = [0, 1, 2]
	var hero_rows: Array[int] = [0, 1, 2, 3, 4, 5, 6]
	var enemy_cols: Array[int] = [8, 9, 10]
	var enemy_rows: Array[int] = [0, 1, 2, 3, 4, 5, 6]

	var shuffled_hero_rows = hero_rows.duplicate()
	shuffled_hero_rows.shuffle()
	var shuffled_enemy_rows = enemy_rows.duplicate()
	shuffled_enemy_rows.shuffle()

	var hero_idx = 0
	for s in hero_stacks:
		if hero_idx >= hero_rows.size():
			break
		var col = hero_cols[hero_idx % hero_cols.size()]
		var row = shuffled_hero_rows[hero_idx]
		var unit = CombatUnit.new(s, col, row, true)
		_all_units.append(unit)
		_grid_units[hex_key(col, row)] = unit
		_create_unit_visual(unit)
		hero_idx += 1

	var enemy_idx = 0
	for s in enemy_stacks:
		if enemy_idx >= enemy_rows.size():
			break
		var col = enemy_cols[enemy_idx % enemy_cols.size()]
		var row = shuffled_enemy_rows[enemy_idx]
		var unit = CombatUnit.new(s, col, row, false)
		_all_units.append(unit)
		_grid_units[hex_key(col, row)] = unit
		_create_unit_visual(unit)
		enemy_idx += 1

func _create_unit_visual(unit: CombatUnit) -> void:
	var hex_center = hex_to_pixel(unit.q, unit.r)
	var px = hex_center.x + _hex_container.position.x + HEX_SIZE
	var py = hex_center.y + _hex_container.position.y + HEX_SIZE

	var unit_node = Node2D.new()
	unit_node.position = Vector2(px, py)
	# L'unité apparaît d'abord hors-écran (au-dessus) pour l'animation drop-in
	unit_node.position.y = -80
	add_child(unit_node)
	unit.node = unit_node
	_unit_base_positions[unit] = Vector2(px, py)
	unit_node.modulate.a = 0.0

	# Animation drop-in: l'unité tombe du ciel avec un petit rebond
	var drop_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	drop_tw.set_parallel(true)
	drop_tw.tween_property(unit_node, "position", Vector2(px, py), 0.5)
	drop_tw.tween_property(unit_node, "modulate:a", 1.0, 0.3)
	# Petite traînée de poussière à l'atterrissage
	drop_tw.tween_callback(func():
		if not _hex_container or not is_instance_valid(_hex_container):
			return
		var dust_pos = Vector2(px, py + 20)
		for d in 6:
			var dust = ColorRect.new()
			dust.size = Vector2(4, 4)
			dust.color = Color(0.60, 0.50, 0.35, 0.50)
			dust.position = dust_pos + Vector2(randf_range(-8, 8), 0)
			dust.z_index = 20
			dust.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(dust)
			var dtw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			dtw.tween_property(dust, "position", dust.position + Vector2(randf_range(-15, 15), randf_range(5, 15)), 0.3)
			dtw.parallel().tween_property(dust, "modulate:a", 0.0, 0.3)
			dtw.parallel().tween_property(dust, "size", Vector2(2, 2), 0.3)
			dtw.tween_callback(func(): if is_instance_valid(dust): dust.queue_free())
	)

	var unit_id: String = unit.stack.unit_id
	var tex: Texture2D = _get_unit_texture(unit_id, unit.is_hero)
	var sprite = Sprite2D.new()
	sprite.texture = tex
	if tex:
		var tex_size = tex.get_size()
		var scale_val = 38.0 / max(tex_size.x, tex_size.y)
		sprite.scale = Vector2(scale_val, scale_val)
	sprite.z_index = 5
	unit_node.add_child(sprite)
	unit.sprite = sprite
	
	# Démarrer l'animation idle si on a des frames samurai
	if _samurai_anims.has("idle") and _samurai_anims["idle"].size() > 0:
		_play_unit_anim(unit, "idle")
	
	# Halo de camp (cercle coloré sous l'unité) — plus grand et plus présent
	var camp_color := Color(0.30, 0.55, 0.95, 0.30) if unit.is_hero else Color(0.90, 0.18, 0.12, 0.30)
	var halo = ColorRect.new()
	halo.size = Vector2(60, 60)
	halo.position = Vector2(-30, -30)
	halo.color = camp_color
	halo.z_index = 0
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(halo)
	unit.tint_overlay = halo

	# Second halo plus subtil (pour la profondeur)
	var halo_outer = ColorRect.new()
	var camp_color_outer := Color(0.25, 0.45, 0.85, 0.12) if unit.is_hero else Color(0.75, 0.12, 0.08, 0.12)
	halo_outer.size = Vector2(72, 72)
	halo_outer.position = Vector2(-36, -36)
	halo_outer.color = camp_color_outer
	halo_outer.z_index = 0
	halo_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(halo_outer)

	# Ombre portée (ellipse) — plus large et douce
	var shadow = ColorRect.new()
	shadow.size = Vector2(40, 10)
	shadow.position = Vector2(-20, 36)
	shadow.color = Color(0, 0, 0, 0.40)
	shadow.z_index = 4
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(shadow)
	# Seconde couche d'ombre (plus large, plus légère)
	var shadow_soft = ColorRect.new()
	shadow_soft.size = Vector2(52, 14)
	shadow_soft.position = Vector2(-26, 34)
	shadow_soft.color = Color(0, 0, 0, 0.15)
	shadow_soft.z_index = 3
	shadow_soft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(shadow_soft)

	# Anneau de sélection / indicateur actif (caché par défaut)
	var ring = ColorRect.new()
	ring.size = Vector2(56, 56)
	ring.position = Vector2(-28, -28)
	ring.color = Color(0.70, 0.90, 0.30, 0.0)
	ring.z_index = 3
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(ring)
	unit.selection_ring = ring

	# Repère lumineux pour l'unité active (triangle + halo)
	var active_marker = ColorRect.new()
	active_marker.size = Vector2(18, 10)
	active_marker.position = Vector2(-9, -36)
	active_marker.color = Color(0, 0, 0, 0)
	active_marker.z_index = 7
	active_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(active_marker)
	unit_node.set_meta("active_marker", active_marker)

	# Halo doré pulsant autour de l'unité active (invisible par défaut)
	var active_glow = ColorRect.new()
	active_glow.size = Vector2(72, 72)
	active_glow.position = Vector2(-36, -36)
	active_glow.color = Color(0, 0, 0, 0)
	active_glow.z_index = 2
	active_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(active_glow)
	unit_node.set_meta("active_glow", active_glow)

	# Nom de l'unité
	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.50))
	name_label.add_theme_constant_override("outline_size", 1)
	name_label.text = unit.get_name()
	name_label.position = Vector2(-26, -32)
	name_label.z_index = 6
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(name_label)

	# Compteur d'unités — plus visible avec fond
	var count_bg = ColorRect.new()
	count_bg.size = Vector2(24, 18)
	count_bg.position = Vector2(-12, 18)
	count_bg.color = Color(0, 0, 0, 0.45)
	count_bg.z_index = 5
	count_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(count_bg)

	var count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", 13)
	count_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.90))
	count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	count_label.add_theme_constant_override("shadow_offset_x", 1)
	count_label.add_theme_constant_override("shadow_offset_y", 1)
	count_label.text = str(unit.stack.get_alive_count())
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.size = Vector2(24, 18)
	count_label.position = Vector2(-12, 18)
	count_label.z_index = 6
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(count_label)

	# Barre de vie (fond avec bordure)
	var hp_bar_bg = ColorRect.new()
	hp_bar_bg.size = Vector2(48, 8)
	hp_bar_bg.position = Vector2(-24, 32)
	hp_bar_bg.color = Color(0.08, 0.02, 0.02, 0.90)
	hp_bar_bg.z_index = 6
	hp_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(hp_bar_bg)

	# Bordure de la barre de vie
	var hp_bar_border = ColorRect.new()
	hp_bar_border.size = Vector2(48, 1)
	hp_bar_border.position = Vector2(-24, 32)
	hp_bar_border.color = Color(0.30, 0.20, 0.15, 0.40)
	hp_bar_border.z_index = 7
	hp_bar_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(hp_bar_border)

	# Barre de vie (remplissage)
	var hp_bar = ColorRect.new()
	var hp_ratio = float(unit.stack.current_hp) / float(max(unit.stack.get_max_hp_display(), 1))
	hp_bar.size = Vector2(max(2, 44 * hp_ratio), 6)
	hp_bar.position = Vector2(-22, 33)
	if hp_ratio > 0.6:
		hp_bar.color = Color(0.10, 0.72, 0.18, 0.95)
	elif hp_ratio > 0.3:
		hp_bar.color = Color(0.80, 0.58, 0.08, 0.95)
	else:
		hp_bar.color = Color(0.85, 0.10, 0.10, 0.95)
	hp_bar.z_index = 7
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(hp_bar)
	unit.hp_bar = hp_bar

	# Reflet lumineux sur la barre de vie (effet de brillance)
	var hp_bar_highlight = ColorRect.new()
	hp_bar_highlight.size = Vector2(max(2, 44 * hp_ratio), 2)
	hp_bar_highlight.position = Vector2(-22, 33)
	hp_bar_highlight.color = Color(1, 1, 1, 0.20)
	hp_bar_highlight.z_index = 8
	hp_bar_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_node.add_child(hp_bar_highlight)
	unit_node.set_meta("hp_highlight", hp_bar_highlight)

	_update_unit_visual(unit)

func _update_unit_visual(unit: CombatUnit) -> void:
	if not unit.is_alive():
		unit.node.visible = false
		return
	unit.node.visible = true
	if unit.hp_bar:
		var hp_ratio = float(unit.stack.current_hp) / float(max(1, unit.stack.get_max_hp_display()))
		var target_width = max(2, 44 * hp_ratio)
		var target_color: Color
		if hp_ratio > 0.6:
			target_color = Color(0.10, 0.72, 0.18, 0.95)
		elif hp_ratio > 0.3:
			target_color = Color(0.80, 0.58, 0.08, 0.95)
		else:
			target_color = Color(0.85, 0.10, 0.10, 0.95)
		# Transition en douceur de la barre de vie
		var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(unit.hp_bar, "size:x", target_width, 0.25)
		tw.parallel().tween_property(unit.hp_bar, "color", target_color, 0.25)
		# Reflet suit la largeur
		var hl: ColorRect = unit.node.get_meta("hp_highlight") if unit.node.has_meta("hp_highlight") else null
		if hl and is_instance_valid(hl):
			var tw2 = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw2.tween_property(hl, "size:x", target_width, 0.25)
		# Petite lueur de dégâts subis
		if unit.hp_bar.get_meta("_flash_timer", 0) == 0:
			var ftw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			ftw.tween_property(unit.hp_bar, "modulate", Color(1.4, 1.4, 1.4), 0.05)
			ftw.tween_property(unit.hp_bar, "modulate", Color.WHITE, 0.15)
			unit.hp_bar.set_meta("_flash_timer", 1)
			create_tween().tween_callback(func():
				if unit.hp_bar and is_instance_valid(unit.hp_bar):
					unit.hp_bar.remove_meta("_flash_timer")
			).set_delay(0.3)

# ============================================
# UI CONSTRUCTION
# ============================================
func _generate_combat_bg() -> ImageTexture:
	var w: int = 540
	var h: int = 1200
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var sky_h: int = int(h * 0.55)
	var half_w_int: int = int(w / 2)

	# Ciel nocturne: bleu nuit profond → violet sombre → lueur froide à l'horizon
	for y in range(sky_h):
		var t: float = float(y) / sky_h
		var r: float
		var g: float
		var b: float
		if t < 0.6:
			var t2: float = t / 0.6
			r = 0.04 + t2 * (0.08 - 0.04)
			g = 0.02 + t2 * (0.06 - 0.02)
			b = 0.12 + t2 * (0.18 - 0.12)
		else:
			var t2: float = (t - 0.6) / 0.4
			r = 0.08 + t2 * (0.20 - 0.08)
			g = 0.06 + t2 * (0.14 - 0.06)
			b = 0.18 + t2 * (0.25 - 0.18)
		for x in range(w):
			var edge: float = 1.0 - pow(abs(x - half_w_int) / half_w_int, 1.8) * 0.10
			img.set_pixel(x, y, Color(
				clampf(r * edge, 0, 1),
				clampf(g * edge, 0, 1),
				clampf(b * edge, 0, 1)
			))

	# Étoiles
	var star_rng := RandomNumberGenerator.new()
	star_rng.randomize()
	for s in 120:
		var sx: int = star_rng.randi() % w
		var sy: int = star_rng.randi() % int(sky_h * 0.85)
		var brightness: float = 0.3 + star_rng.randf() * 0.7
		var size: int = 1 + (star_rng.randi() % 2)
		for dx in range(-size, size + 1):
			for dy in range(-size, size + 1):
				var px = sx + dx
				var py = sy + dy
				if px >= 0 and px < w and py >= 0 and py < sky_h:
					var d = sqrt(dx * dx + dy * dy)
					if d <= size:
						var a = brightness * (1.0 - d / (size + 1))
						img.set_pixel(px, py, Color(
							clampf(0.80 + brightness * 0.20, 0, 1),
							clampf(0.75 + brightness * 0.25, 0, 1),
							clampf(0.70 + brightness * 0.30, 0, 1)
						))

	# Lune pâle (haut-gauche)
	var moon_cx: int = int(w * 0.22)
	var moon_cy: int = int(sky_h * 0.18)
	for dy in range(-50, 51):
		for dx in range(-50, 51):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= 50:
				var sx: int = moon_cx + dx
				var sy: int = moon_cy + dy
				if sx >= 0 and sx < w and sy >= 0 and sy < h:
					if dist <= 18:
						img.set_pixel(sx, sy, Color(0.92, 0.90, 0.85))
					elif dist <= 28:
						var g2 = maxf(0, 1.0 - (dist - 18) / 10.0) * 0.30
						var px := img.get_pixel(sx, sy)
						img.set_pixel(sx, sy, Color(
							lerp(px.r, 0.92, g2), lerp(px.g, 0.90, g2), lerp(px.b, 0.85, g2)
						))
					else:
						var g3 = maxf(0, 1.0 - (dist - 28) / 22.0) * 0.12
						var px := img.get_pixel(sx, sy)
						img.set_pixel(sx, sy, Color(
							lerp(px.r, 0.70, g3), lerp(px.g, 0.68, g3), lerp(px.b, 0.65, g3)
						))

	# Brume fine à l'horizon
	for y in range(sky_h - 6, sky_h + 15):
		var mist_t: float = 1.0 - abs(float(y - sky_h) / 10.0)
		mist_t = maxf(0, mist_t)
		for x in range(w):
			var mist_noise: float = sin(x * 0.015 + y * 0.04) * 0.3 + 0.7
			var alpha: float = mist_t * 0.15 * mist_noise
			var px := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(
				lerp(px.r, 0.12, alpha),
				lerp(px.g, 0.10, alpha),
				lerp(px.b, 0.18, alpha)
			))

	# Nuages sombres et fins
	var cloud_rng := RandomNumberGenerator.new()
	cloud_rng.randomize()
	for c in 4:
		var cx: int = cloud_rng.randi() % w
		var cy: int = 30 + cloud_rng.randi() % int(sky_h * 0.35)
		for dy in range(-4, 5):
			for dx in range(-20, 21):
				var cdist: float = sqrt(dx * dx + dy * dy * 0.5)
				if cdist <= 8 + cloud_rng.randi() % 4:
					var sx = cx + dx
					var sy = cy + dy
					if sx >= 0 and sx < w and sy >= 0 and sy < sky_h:
						var ca = maxf(0, 1.0 - cdist / 10.0) * 0.08
						var px := img.get_pixel(sx, sy)
						img.set_pixel(sx, sy, Color(
							lerp(px.r, 0.02, ca), lerp(px.g, 0.01, ca), lerp(px.b, 0.04, ca)
						))

	# Montagnes — silhouettes japonaises sombres
	var mountain_colors: Array = [
		[Color(0.03, 0.01, 0.04), Color(0.02, 0.01, 0.03)],
		[Color(0.05, 0.02, 0.06), Color(0.04, 0.02, 0.05)],
	]
	var m_offsets: Array = [0, -5]
	var m_peaks: Array = [
		[0, 0.05, 0.12, 0.20, 0.28, 0.35, 0.42, 0.50, 0.58, 0.65, 0.72, 0.80, 0.88, 0.95, 1.0],
		[0, 0.08, 0.18, 0.25, 0.32, 0.40, 0.48, 0.55, 0.62, 0.70, 0.78, 0.85, 0.92, 1.0],
	]
	var m_heights: Array = [
		[0, -50, -30, -70, -45, -80, -55, -85, -50, -75, -40, -65, -35, -55, 0],
		[0, -40, -20, -55, -30, -65, -35, -70, -45, -60, -30, -50, -25, -45, 0],
	]
	for li in range(mountain_colors.size()):
		var base_y: int = sky_h + m_offsets[li]
		var px_arr: Array = m_peaks[li]
		var hy_arr: Array = m_heights[li]
		var cols = mountain_colors[li]
		for i in range(px_arr.size() - 1):
			var x1: int = int(w * px_arr[i])
			var y1: int = base_y + hy_arr[i]
			var x2: int = int(w * px_arr[i + 1])
			var y2: int = base_y + hy_arr[i + 1]
			var col: Color = cols[i % cols.size()]
			var y_start: int = mini(y1, y2)
			var y_end: int = base_y + 3
			for my in range(y_start, y_end):
				var left_x: int = int(x1 + (x2 - x1) * float(my - y1) / float(y2 - y1)) if y2 != y1 else x1
				for mx in range(left_x - 3, left_x + 4):
					if mx >= 0 and mx < w:
						var existing := img.get_pixel(mx, my)
						if existing.a < 0.5:
							var depth: float = float(my - y_start) / max(1, y_end - y_start)
							var c = Color(
								lerp(col.r, col.r * 0.7, depth),
								lerp(col.g, col.g * 0.5, depth),
								lerp(col.b, col.b * 0.6, depth)
							)
							img.set_pixel(mx, my, c)

	# Mt. Fuji-like cone (center-left, silhouette sombre)
	var fuji_base_x: int = int(w * 0.38)
	var fuji_base_y: int = sky_h
	var fuji_peak_y: int = sky_h - 110
	var fuji_color: Color = Color(0.04, 0.02, 0.05)
	for my in range(fuji_peak_y, fuji_base_y):
		var progress: float = float(my - fuji_peak_y) / float(fuji_base_y - fuji_peak_y)
		var half_width: int = int(20 + progress * 45)
		for mx in range(fuji_base_x - half_width, fuji_base_x + half_width + 1):
			if mx >= 0 and mx < w:
				var existing := img.get_pixel(mx, my)
				if existing.a < 0.5:
					var depth: float = float(my - fuji_peak_y) / float(fuji_base_y - fuji_peak_y)
					var c = Color(
						lerp(fuji_color.r, fuji_color.r * 0.6, depth),
						lerp(fuji_color.g, fuji_color.g * 0.4, depth),
						lerp(fuji_color.b, fuji_color.b * 0.5, depth)
					)
					img.set_pixel(mx, my, c)
	# Neige au sommet (légère lueur lunaire)
	for my in range(fuji_peak_y, fuji_peak_y + 6):
		var progress: float = float(my - fuji_peak_y) / 6.0
		var half_width: int = int(5 - progress * 3)
		for mx in range(fuji_base_x - half_width, fuji_base_x + half_width + 1):
			if mx >= 0 and mx < w:
				var cap_alpha: float = 1.0 - progress * 0.5
				var existing := img.get_pixel(mx, my)
				if existing.a < 0.5:
					img.set_pixel(mx, my, Color(
						lerp(existing.r, 0.35, cap_alpha * 0.4),
						lerp(existing.g, 0.32, cap_alpha * 0.3),
						lerp(existing.b, 0.40, cap_alpha * 0.3)
					))

	# Sol: texturé sombre, presque noir avec nuances
	for y in range(sky_h, h):
		var gy: float = float(y - sky_h) / (h - sky_h)
		for x in range(w):
			var gx_ratio: float = float(x) / w
			var ground_r: float = lerp(0.06, 0.10, gy)
			var ground_g: float = lerp(0.04, 0.08, gy)
			var ground_b: float = lerp(0.03, 0.06, gy)
			var blend: float = smoothstep(0.3, 0.7, gx_ratio)
			var r: float = lerp(ground_r, ground_r * 1.3, blend)
			var g: float = lerp(ground_g, ground_g * 1.2, blend)
			var b: float = lerp(ground_b, ground_b * 1.1, blend)
			var noise: float = sin(x * 0.04 + y * 0.06) * 0.015 + cos(x * 0.07 - y * 0.05) * 0.015
			img.set_pixel(x, y, Color(
				clampf(r + noise, 0, 1),
				clampf(g + noise * 0.8, 0, 1),
				clampf(b + noise * 0.5, 0, 1)
			))

	# Herbes sombres (détails)
	var grass_rng := RandomNumberGenerator.new()
	grass_rng.randomize()
	for g in 60:
		var gx: int = grass_rng.randi() % w
		var gy: int = sky_h + 20 + grass_rng.randi() % (h - sky_h - 40)
		var gh: int = 2 + grass_rng.randi() % 4
		var gc: Color = Color(0.03 + grass_rng.randf() * 0.04, 0.05 + grass_rng.randf() * 0.04, 0.02)
		for i in range(gh):
			var sx = gx + int((i - int(gh / 2)) / 2)
			var sy = gy - i
			if sx >= 0 and sx < w and sy >= sky_h and sy < h:
				img.set_pixel(sx, sy, gc)

	# Branches d'arbres (cerisier/pin) encadrant les bords
	var branch_rng := RandomNumberGenerator.new()
	branch_rng.randomize()
	for b in 6:
		var is_left: bool = b < 3
		var base_x: int = branch_rng.randi() % 20
		if not is_left:
			base_x = w - base_x - 1
		var base_y: int = int(sky_h * (0.08 + branch_rng.randf() * 0.45))
		var branch_len: int = 12 + branch_rng.randi() % 22
		var dir: int = 1 if is_left else -1
		var bc: Color = Color(0.02, 0.01, 0.02, 0.30 + branch_rng.randf() * 0.20)
		for step in range(branch_len):
			var sx: int = base_x + dir * step
			var sy: int = base_y + int(sin(step * 0.3) * 3)
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					var px: int = sx + ox
					var py: int = sy + oy
					if px >= 0 and px < w and py >= 0 and py < sky_h:
						var existing := img.get_pixel(px, py)
						if existing.a < 0.3:
							img.set_pixel(px, py, bc)
		# Fleurs de cerisier sombres sur les branches
		if branch_rng.randf() > 0.5:
			var flower_x: int = base_x + dir * int(branch_len * 0.7)
			var flower_y: int = base_y + int(sin(int(branch_len * 0.7) * 0.3) * 3)
			var fc: Color = Color(
				0.50 + branch_rng.randf() * 0.15,
				0.15 + branch_rng.randf() * 0.10,
				0.25 + branch_rng.randf() * 0.10,
				0.25
			)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var d: float = sqrt(dx * dx + dy * dy)
					if d <= 2.5:
						var fx = flower_x + dx
						var fy = flower_y + dy
						if fx >= 0 and fx < w and fy >= 0 and fy < sky_h:
							var existing := img.get_pixel(fx, fy)
							if existing.a < 0.3:
								img.set_pixel(fx, fy, fc)

	# Pétales de sakura sombres
	var sakura_rng := RandomNumberGenerator.new()
	sakura_rng.randomize()
	for p in 20:
		var px: int = sakura_rng.randi() % w
		var py: int = sakura_rng.randi() % h
		var ps: int = 1 + sakura_rng.randi() % 2
		var pc: Color = Color(
			0.50 + sakura_rng.randf() * 0.15,
			0.20 + sakura_rng.randf() * 0.10,
			0.30 + sakura_rng.randf() * 0.10,
			0.15 + sakura_rng.randf() * 0.20
		)
		for dy in range(-ps, ps + 1):
			for dx in range(-ps, ps + 1):
				var d: float = sqrt(dx * dx + dy * dy)
				if d <= ps and d >= ps - 0.5:
					var sx = px + dx
					var sy = py + dy
					if sx >= 0 and sx < w and sy >= 0 and sy < h:
						var existing := img.get_pixel(sx, sy)
						if existing.a < 0.5:
							img.set_pixel(sx, sy, pc)

	# Bambous en silhouettes (bords)
	var bamboo_rng := RandomNumberGenerator.new()
	bamboo_rng.randomize()
	for b in 6:
		var bx_base: int = bamboo_rng.randi() % max(1, int(w / 8))
		if bamboo_rng.randf() > 0.5:
			bx_base = w - bx_base - 1
		var bh: int = 30 + bamboo_rng.randi() % 70
		var b_segments: int = 2 + bamboo_rng.randi() % 4
		var seg_h: int = int(bh / b_segments)
		var seg_w: int = 2 + bamboo_rng.randi() % 2
		var bc: Color = Color(0.02, 0.03, 0.02, 0.20 + bamboo_rng.randf() * 0.15)
		var bx_off: int = 0
		for s in range(b_segments):
			var sy_start: int = h - (s + 1) * seg_h
			var sy_end: int = sy_start + seg_h
			if bamboo_rng.randf() > 0.5:
				bx_off += bamboo_rng.randi() % 3 - 1
			for sy in range(sy_start, sy_end):
				var sway = int(sin(sy * 0.03 + bx_base) * 2)
				var cx = bx_base + sway + bx_off
				for sx in range(cx - int(seg_w / 2), cx + int(seg_w / 2) + 1):
					if sx >= 0 and sx < w and sy >= 0 and sy < h:
						var existing := img.get_pixel(sx, sy)
						if existing.a < 0.3:
							img.set_pixel(sx, sy, bc)
			if s > 0:
				var ny: int = sy_start
				for sx in range(bx_base - seg_w, bx_base + seg_w + 1):
					if sx >= 0 and sx < w and ny >= 0 and ny < h:
						img.set_pixel(sx, ny, Color(0.01, 0.02, 0.01, 0.30))

	# Torii (portail japonais) silhouette
	var torii_x: int = int(w * 0.85)
	var torii_scale: float = 0.45
	var torii_color: Color = Color(0.03, 0.02, 0.03, 0.30)
	for pil in [torii_x, torii_x + int(35 * torii_scale)]:
		for sy in range(sky_h - int(55 * torii_scale), sky_h + int(15 * torii_scale)):
			for sx in range(pil - 2, pil + 3):
				if sx >= 0 and sx < w and sy >= 0 and sy < h:
					var existing := img.get_pixel(sx, sy)
					if existing.a < 0.3:
						img.set_pixel(sx, sy, torii_color)
	var kasagi_y: int = sky_h - int(55 * torii_scale)
	for sx in range(torii_x - int(10 * torii_scale), torii_x + int(45 * torii_scale)):
		for sy in range(kasagi_y - 2, kasagi_y + 3):
			if sx >= 0 and sx < w and sy >= 0 and sy < h:
				var existing := img.get_pixel(sx, sy)
				if existing.a < 0.3:
					img.set_pixel(sx, sy, torii_color)
	var nuki_y: int = sky_h - int(35 * torii_scale)
	for sx in range(torii_x - int(5 * torii_scale), torii_x + int(45 * torii_scale)):
		for sy in range(nuki_y - 1, nuki_y + 2):
			if sx >= 0 and sx < w and sy >= 0 and sy < h:
				var existing := img.get_pixel(sx, sy)
				if existing.a < 0.3:
					img.set_pixel(sx, sy, torii_color)
	# Second torii, smaller, on the right
	var torii2_x: int = int(w * 0.85)
	var ts2: float = 0.35
	var tc2: Color = Color(0.06, 0.04, 0.05, 0.18)
	for pil in [torii2_x, torii2_x + int(30 * ts2)]:
		for sy in range(sky_h - int(45 * ts2), sky_h + int(15 * ts2)):
			for sx in range(pil - 1, pil + 2):
				if sx >= 0 and sx < w and sy >= 0 and sy < h:
					var existing := img.get_pixel(sx, sy)
					if existing.a < 0.3:
						img.set_pixel(sx, sy, tc2)
	var k2_y: int = sky_h - int(45 * ts2)
	for sx in range(torii2_x - int(8 * ts2), torii2_x + int(38 * ts2)):
		for sy in range(k2_y - 1, k2_y + 2):
			if sx >= 0 and sx < w and sy >= 0 and sy < h:
				var existing := img.get_pixel(sx, sy)
				if existing.a < 0.3:
					img.set_pixel(sx, sy, tc2)

	var tex := ImageTexture.create_from_image(img)
	return tex

func _create_stat_panel() -> void:
	_stat_panel = Panel.new()
	var sp_style = StyleBoxFlat.new()
	sp_style.bg_color = Color(0.05, 0.04, 0.07, 0.93)
	sp_style.border_color = Color(0.55, 0.42, 0.20, 0.80)
	sp_style.border_width_left = 2
	sp_style.border_width_right = 2
	sp_style.border_width_top = 2
	sp_style.border_width_bottom = 2
	sp_style.corner_radius_top_left = 10
	sp_style.corner_radius_top_right = 10
	sp_style.corner_radius_bottom_left = 10
	sp_style.corner_radius_bottom_right = 10
	_stat_panel.add_theme_stylebox_override("panel", sp_style)
	_stat_panel.size = Vector2(195, 200)
	_stat_panel.position = Vector2(8, 8)
	_stat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.modulate.a = 0.0
	_panel.add_child(_stat_panel)

func _show_unit_stat_panel(unit: CombatUnit) -> void:
	if not unit or not unit.is_alive():
		_hide_stat_panel()
		return
	for c in _stat_panel.get_children():
		c.queue_free()

	var y := 8

	# En-tête: portrait + nom
	var header := ColorRect.new()
	header.size = Vector2(191, 4)
	header.position = Vector2(2, 2)
	var camp_color := Color(0.35, 0.60, 0.85, 0.60) if unit.is_hero else Color(0.80, 0.25, 0.20, 0.60)
	header.color = camp_color
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(header)

	# "Portrait" (rectangle coloré avec initiale)
	var portrait_bg := ColorRect.new()
	portrait_bg.size = Vector2(42, 42)
	portrait_bg.position = Vector2(8, y)
	portrait_bg.color = Color(0.12, 0.10, 0.08, 0.90)
	portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(portrait_bg)
	# Bordure portrait
	var portrait_border := ColorRect.new()
	portrait_border.size = Vector2(44, 44)
	portrait_border.position = Vector2(7, y - 1)
	portrait_border.color = camp_color
	portrait_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(portrait_border)

	# Initiale dans le portrait
	var initial := Label.new()
	initial.text = unit.get_name().left(1).to_upper()
	initial.add_theme_font_size_override("font_size", 24)
	initial.add_theme_color_override("font_color", Color(0.90, 0.85, 0.75))
	initial.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.80))
	initial.position = Vector2(20, y + 6)
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(initial)

	# Nom
	var name_lbl := Label.new()
	name_lbl.text = unit.get_name()
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.97, 0.92, 0.65))
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
	name_lbl.position = Vector2(58, y + 2)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(name_lbl)

	# Camp
	var camp_lbl := Label.new()
	camp_lbl.text = "Allié" if unit.is_hero else "Ennemi"
	camp_lbl.add_theme_font_size_override("font_size", 10)
	camp_lbl.add_theme_color_override("font_color", camp_color)
	camp_lbl.position = Vector2(58, y + 18)
	camp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(camp_lbl)

	# Effectif
	var count_lbl := Label.new()
	count_lbl.text = "×" + str(unit.stack.get_alive_count())
	count_lbl.add_theme_font_size_override("font_size", 11)
	count_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.70))
	count_lbl.position = Vector2(58, y + 30)
	count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(count_lbl)

	y += 50

	# Barre de vie large
	var hp_max = unit.stack.get_max_hp_display()
	var hp_ratio = float(unit.stack.current_hp) / float(max(hp_max, 1))
	var hp_bg := ColorRect.new()
	hp_bg.size = Vector2(180, 12)
	hp_bg.position = Vector2(7, y)
	hp_bg.color = Color(0.10, 0.02, 0.02, 0.80)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	hp_fill.size = Vector2(max(2, 178 * hp_ratio), 10)
	hp_fill.position = Vector2(8, y + 1)
	if hp_ratio > 0.6:
		hp_fill.color = Color(0.15, 0.72, 0.20, 0.95)
	elif hp_ratio > 0.3:
		hp_fill.color = Color(0.80, 0.60, 0.10, 0.95)
	else:
		hp_fill.color = Color(0.85, 0.12, 0.12, 0.95)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(hp_fill)

	var hp_text := Label.new()
	hp_text.text = "HP %d / %d" % [unit.stack.current_hp, hp_max]
	hp_text.add_theme_font_size_override("font_size", 9)
	hp_text.add_theme_color_override("font_color", Color(0.90, 0.88, 0.82))
	hp_text.position = Vector2(90, y + 1)
	hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_child(hp_text)

	y += 18

	# Stats en grille 2×2
	var stat_data := [
		["ATK", str(unit.get_attack()), Color(0.80, 0.45, 0.50)],
		["DEF", str(unit.get_defense()), Color(0.45, 0.65, 0.85)],
		["DMG", "%d-%d" % [unit.get_damage_min(), unit.get_damage_max()], Color(0.85, 0.65, 0.25)],
		["VIT", str(unit.get_speed()), Color(0.40, 0.75, 0.70)],
	]
	for i in range(4):
		var col := i % 2
		var row := i / 2
		var sx := 10 + col * 95
		var sy := y + row * 30
		var d = stat_data[i]
		# Label de stat
		var stat_lbl := Label.new()
		stat_lbl.text = d[0]
		stat_lbl.add_theme_font_size_override("font_size", 9)
		stat_lbl.add_theme_color_override("font_color", Color(0.60, 0.58, 0.55))
		stat_lbl.position = Vector2(sx, sy)
		stat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stat_panel.add_child(stat_lbl)
		# Valeur
		var val_lbl := Label.new()
		val_lbl.text = d[1]
		val_lbl.add_theme_font_size_override("font_size", 15)
		val_lbl.add_theme_color_override("font_color", d[2])
		val_lbl.position = Vector2(sx, sy + 12)
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stat_panel.add_child(val_lbl)

	_stat_panel.visible = true
	_stat_panel_visible = true
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_stat_panel, "modulate:a", 1.0, 0.25)

func _hide_stat_panel() -> void:
	_stat_panel_visible = false
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_stat_panel, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): _stat_panel.visible = false)

func _cleanup_background_particles() -> void:
	for tw in _bg_particle_tweens:
		if is_instance_valid(tw):
			tw.kill()
	_bg_particle_tweens.clear()
	for p in _bg_particles:
		if is_instance_valid(p):
			p.queue_free()
	_bg_particles.clear()
	if _grid_shadow and is_instance_valid(_grid_shadow):
		_grid_shadow.queue_free()
		_grid_shadow = null

func _setup_background_particles() -> void:
	_cleanup_background_particles()
	var vp = get_viewport().get_visible_rect().size
	for i in range(12):
		var petal := ColorRect.new()
		var sz: float = 4.0 + _rng.randf() * 6.0
		petal.size = Vector2(sz, sz * 0.6)
		petal.position = Vector2(_rng.randf() * vp.x, -20 - _rng.randf() * 100)
		var shade: float = 0.7 + _rng.randf() * 0.3
		petal.color = Color(0.95 * shade, 0.55 * shade, 0.65 * shade, 0.3 + _rng.randf() * 0.3)
		petal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		petal.pivot_offset = petal.size / 2.0
		_panel.add_child(petal)
		_bg_particles.append(petal)
		_animate_petal(petal)

func _animate_petal(petal: ColorRect) -> void:
	var vp = get_viewport().get_visible_rect().size
	var duration: float = 8.0 + _rng.randf() * 6.0
	var end_x: float = petal.position.x + (_rng.randf() - 0.5) * 80.0
	var end_y: float = vp.y + 20
	var tw: Tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(petal, "position:x", end_x, duration * 0.5).set_delay(duration * 0.5)
	tw.parallel().tween_property(petal, "position:y", end_y, duration)
	tw.parallel().tween_property(petal, "rotation", _rng.randf() * 360.0, duration)
	tw.parallel().tween_property(petal, "modulate:a", 0.0, duration * 0.3).set_delay(duration * 0.7)
	tw.finished.connect(func():
		if is_instance_valid(petal) and _panel and is_instance_valid(_panel):
			petal.position.x = _rng.randf() * vp.x
			petal.position.y = -20 - _rng.randf() * 60
			petal.modulate.a = 0.3 + _rng.randf() * 0.3
			_animate_petal(petal)
	)
	_bg_particle_tweens.append(tw)

func _build_ui() -> void:
	_cleanup_background_particles()
	if _panel:
		_panel.queue_free()

	var vp = get_viewport().get_visible_rect().size

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.9, 0.9)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.01, 0.04)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 16
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	# Background de champ de bataille procédural
	_bg_texture = _generate_combat_bg()
	_bg_texture_rect = TextureRect.new()
	_bg_texture_rect.texture = _bg_texture
	_bg_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_bg_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_bg_texture_rect)

	# Zone sombre sous la grille hex pour la démarquer visuellement
	_grid_shadow = ColorRect.new()
	_grid_shadow.color = Color(0.0, 0.0, 0.0, 0.30)
	_grid_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(_grid_shadow)

	_round_label = Label.new()
	_round_label.position = Vector2(12, 10)
	_round_label.text = "Round 1"
	_round_label.add_theme_font_size_override("font_size", 16)
	_round_label.add_theme_color_override("font_color", Color(0.80, 0.75, 0.60))
	_round_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.60))
	_round_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.40))
	_round_label.add_theme_constant_override("outline_size", 1)
	_panel.add_child(_round_label)

	_phase_label = Label.new()
	_phase_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_phase_label.position = Vector2(-160, 10)
	_phase_label.text = "Votre tour"
	_phase_label.add_theme_font_size_override("font_size", 16)
	_phase_label.add_theme_color_override("font_color", COLOR_TEAL)
	_phase_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.60))
	_phase_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.40))
	_phase_label.add_theme_constant_override("outline_size", 1)
	_panel.add_child(_phase_label)

	# Bannière contextuelle (messages importants au centre, au-dessus des cases)
	_context_banner = Label.new()
	_context_banner.set_anchors_preset(Control.PRESET_CENTER)
	_context_banner.offset_top = -28
	_context_banner.add_theme_font_size_override("font_size", 20)
	_context_banner.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	_context_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	_context_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_context_banner.add_theme_constant_override("outline_size", 3)
	_context_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_context_banner.modulate.a = 0.0
	_context_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_context_banner.z_index = 60
	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(0, 0, 0, 0.55)
	banner_style.border_color = Color(0.55, 0.42, 0.18, 0.50)
	banner_style.border_width_left = 1
	banner_style.border_width_right = 1
	banner_style.border_width_top = 1
	banner_style.border_width_bottom = 1
	banner_style.corner_radius_top_left = 10
	banner_style.corner_radius_top_right = 10
	banner_style.corner_radius_bottom_left = 10
	banner_style.corner_radius_bottom_right = 10
	banner_style.content_margin_left = 16
	banner_style.content_margin_right = 16
	banner_style.content_margin_top = 6
	banner_style.content_margin_bottom = 6
	banner_style.shadow_color = Color(0, 0, 0, 0.40)
	banner_style.shadow_size = 8
	_context_banner.add_theme_stylebox_override("normal", banner_style)
	_panel.add_child(_context_banner)

	_create_stat_panel()

	# Tooltip pour survol unité ennemie
	_tooltip = Panel.new()
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 15
	var tt_style := StyleBoxFlat.new()
	tt_style.bg_color = Color(0.06, 0.05, 0.08, 0.93)
	tt_style.border_color = Color(0.55, 0.42, 0.20, 0.70)
	tt_style.border_width_left = 1
	tt_style.border_width_right = 1
	tt_style.border_width_top = 1
	tt_style.border_width_bottom = 1
	tt_style.corner_radius_top_left = 6
	tt_style.corner_radius_top_right = 6
	tt_style.corner_radius_bottom_left = 6
	tt_style.corner_radius_bottom_right = 6
	_tooltip.add_theme_stylebox_override("panel", tt_style)
	_panel.add_child(_tooltip)

	var battlefield_w = HEX_COLS * HEX_W * 0.75 + HEX_W * 0.5
	var battlefield_h = HEX_ROWS * HEX_H + HEX_H * 0.5
	var bx = (vp.x - battlefield_w) / 2
	var by = 20.0

	_hex_container = Control.new()
	_hex_container.position = Vector2(bx, by)
	_hex_container.size = Vector2(battlefield_w, battlefield_h)
	_panel.add_child(_hex_container)

	_draw_hex_grid()

	_info_label = Label.new()
	_info_label.position = Vector2(12, by + battlefield_h + 110)
	_info_label.size = Vector2(vp.x - 24, 32)
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	_info_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.50))
	_info_label.add_theme_constant_override("shadow_offset_x", 1)
	_info_label.add_theme_constant_override("shadow_offset_y", 1)
	_panel.add_child(_info_label)

	var action_y = by + battlefield_h + 200
	_action_bar = HBoxContainer.new()
	_action_bar.position = Vector2(vp.x / 2 - 260, action_y)
	_action_bar.custom_minimum_size = Vector2(520, 50)
	_action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_bar.add_theme_constant_override("separation", 6)
	_panel.add_child(_action_bar)

	_add_action_button("Déplacer", "»", _on_move_pressed, Color(0.30, 0.60, 0.85))
	_add_action_button("Attaquer", "†", _on_attack_pressed, Color(0.80, 0.18, 0.14))
	_add_action_button("Défendre", "#", _on_defend_pressed, Color(0.18, 0.55, 0.65))
	_add_action_button("Attendre", "~", _on_wait_pressed, Color(0.55, 0.55, 0.45))

	# Bouton Fin de tour
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "»» Fin de tour"
	_end_turn_btn.custom_minimum_size = Vector2(120, 50)
	_end_turn_btn.add_theme_font_size_override("font_size", 13)
	_end_turn_btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	_end_turn_btn.add_theme_color_override("font_hover_color", Color(1, 1, 0.90))
	var et_style := StyleBoxFlat.new()
	et_style.bg_color = Color(0.22, 0.10, 0.04)
	et_style.border_color = Color(0.75, 0.55, 0.18)
	et_style.border_width_left = 1
	et_style.border_width_right = 1
	et_style.border_width_top = 1
	et_style.border_width_bottom = 3
	et_style.corner_radius_top_left = 8
	et_style.corner_radius_top_right = 8
	et_style.corner_radius_bottom_left = 8
	et_style.corner_radius_bottom_right = 8
	et_style.shadow_color = Color(0.90, 0.60, 0.10, 0.15)
	et_style.shadow_size = 6
	_end_turn_btn.add_theme_stylebox_override("normal", et_style)
	var et_hover := StyleBoxFlat.new()
	et_hover.bg_color = Color(0.30, 0.14, 0.05)
	et_hover.border_color = Color(0.90, 0.65, 0.20)
	et_hover.border_width_left = 1
	et_hover.border_width_right = 1
	et_hover.border_width_top = 1
	et_hover.border_width_bottom = 3
	et_hover.corner_radius_top_left = 8
	et_hover.corner_radius_top_right = 8
	et_hover.corner_radius_bottom_left = 8
	et_hover.corner_radius_bottom_right = 8
	et_hover.shadow_color = Color(0.90, 0.60, 0.10, 0.30)
	et_hover.shadow_size = 8
	_end_turn_btn.add_theme_stylebox_override("hover", et_hover)
	_end_turn_btn.pressed.connect(_on_end_turn_pressed)
	_action_bar.add_child(_end_turn_btn)

	var turn_y = by + battlefield_h + 310
	_turn_queue = HBoxContainer.new()
	_turn_queue.position = Vector2(10, turn_y)
	_turn_queue.size = Vector2(vp.x - 20, 30)
	_turn_queue.add_theme_constant_override("separation", 4)
	_turn_queue.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(_turn_queue)

	var log_y = turn_y + 40
	_combat_log = RichTextLabel.new()
	_combat_log.position = Vector2(10, log_y)
	_combat_log.size = Vector2(vp.x - 20, 80)
	_combat_log.bbcode_enabled = true
	_combat_log.scroll_active = true
	_combat_log.add_theme_color_override("default_color", Color(0.65, 0.62, 0.55))
	_combat_log.add_theme_font_size_override("normal_font_size", 11)
	var log_style = StyleBoxFlat.new()
	log_style.bg_color = Color(0.02, 0.01, 0.03, 0.60)
	log_style.border_color = Color(0.40, 0.32, 0.20, 0.35)
	log_style.border_width_left = 1
	log_style.border_width_right = 1
	log_style.border_width_top = 1
	log_style.border_width_bottom = 1
	log_style.corner_radius_top_left = 8
	log_style.corner_radius_top_right = 8
	log_style.corner_radius_bottom_left = 8
	log_style.corner_radius_bottom_right = 8
	log_style.content_margin_left = 6
	log_style.content_margin_right = 6
	log_style.content_margin_top = 4
	log_style.content_margin_bottom = 4
	_combat_log.add_theme_stylebox_override("normal", log_style)
	_panel.add_child(_combat_log)

	_setup_background_particles()

func _draw_hex_grid() -> void:
	for child in _hex_container.get_children():
		child.queue_free()
	_hex_tiles.clear()

	for q in range(HEX_COLS):
		for r in range(HEX_ROWS):
			var center = hex_to_pixel(q, r)
			var px = center.x + HEX_SIZE
			var py = center.y + HEX_SIZE

			var base_color = _get_terrain_color(q, r)

			var tile = HexTile.new(q, r, base_color)
			tile.size = Vector2(HEX_W * 0.88, HEX_H * 0.88)
			tile.position = Vector2(px - tile.size.x / 2, py - tile.size.y / 2)
			tile.hex_pressed.connect(_on_hex_tile_clicked)
			tile.mouse_entered.connect(_on_hex_mouse_entered.bind(q, r))
			tile.mouse_exited.connect(_on_hex_mouse_exited.bind(q, r))
			_hex_container.add_child(tile)
			_hex_tiles[hex_key(q, r)] = tile

func _add_action_button(text: String, icon_char: String, callback: Callable, accent: Color) -> void:
	var btn = Button.new()
	btn.text = icon_char + " " + text
	btn.custom_minimum_size = Vector2(105, 48)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 0.95))
	btn.add_theme_color_override("font_disabled_color", Color(0.30, 0.28, 0.22, 0.50))
	var bg = Color(0.12, 0.09, 0.06)
	var border_base = Color(0.50, 0.38, 0.20)
	var accent_soft = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.25)

	var normal = StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = border_base
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 3
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = bg.lightened(0.15)
	hover.border_color = accent
	hover.border_width_left = 1
	hover.border_width_right = 1
	hover.border_width_top = 1
	hover.border_width_bottom = 3
	hover.corner_radius_top_left = 6
	hover.corner_radius_top_right = 6
	hover.corner_radius_bottom_left = 6
	hover.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("hover", hover)

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = bg.lightened(0.25)
	pressed.border_color = accent.lightened(0.2)
	pressed.border_width_left = 1
	pressed.border_width_right = 1
	pressed.border_width_top = 3
	pressed.border_width_bottom = 1
	pressed.corner_radius_top_left = 6
	pressed.corner_radius_top_right = 6
	pressed.corner_radius_bottom_left = 6
	pressed.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled = StyleBoxFlat.new()
	disabled.bg_color = Color(0.06, 0.05, 0.04, 0.60)
	disabled.border_color = Color(0.20, 0.18, 0.15, 0.40)
	disabled.border_width_left = 1
	disabled.border_width_right = 1
	disabled.border_width_top = 1
	disabled.border_width_bottom = 3
	disabled.corner_radius_top_left = 6
	disabled.corner_radius_top_right = 6
	disabled.corner_radius_bottom_left = 6
	disabled.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.pressed.connect(callback)
	_action_bar.add_child(btn)

# ============================================
# ORDRE DE TOUR
# ============================================
func determine_turn_order() -> void:
	var all: Array[CombatUnit] = []
	for u in _all_units:
		if u.is_alive():
			all.append(u)
	all.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool: return a.get_speed() > b.get_speed())
	_turn_order = all

func start_round() -> void:
	_round_label.text = "# Round %d" % _current_round
	_show_turn_banner("Round %d" % _current_round, Color(0.75, 0.65, 0.35))
	_show_context_message("Round %d - Tatakai!" % _current_round, Color(0.90, 0.80, 0.50), 1.8)
	for u in _all_units:
		if u.is_alive():
			u.has_moved = false
			u.has_acted = false
			u.defending = false
	determine_turn_order()
	_current_unit_index = 0
	_show_turn_queue()
	begin_current_turn()

func _show_turn_banner(text: String, color: Color) -> void:
	var vp = get_viewport().get_visible_rect().size

	# Barre décorative en haut
	var bar = ColorRect.new()
	bar.size = Vector2(vp.x, 50)
	bar.color = Color(0.04, 0.03, 0.05, 0.85)
	bar.position = Vector2(0, -50)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.z_index = 19
	_panel.add_child(bar)
	var bar_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	bar_tw.tween_property(bar, "position:y", 0, 0.2)
	bar_tw.tween_interval(0.4)
	bar_tw.tween_property(bar, "position:y", -50, 0.2)
	bar_tw.tween_callback(func():
		if is_instance_valid(bar): bar.queue_free()
	)

	# Ligne dorée décorative
	var line = ColorRect.new()
	line.size = Vector2(vp.x, 2)
	line.color = color
	line.position = Vector2(0, 50)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.z_index = 20
	_panel.add_child(line)
	var line_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	line_tw.tween_property(line, "modulate:a", 1.0, 0.15)
	line_tw.tween_interval(0.4)
	line_tw.tween_property(line, "modulate:a", 0.0, 0.2)
	line_tw.tween_callback(func():
		if is_instance_valid(line): line.queue_free()
	)

	var banner = Label.new()
	banner.text = text
	banner.add_theme_font_size_override("font_size", 26)
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.70))
	banner.add_theme_constant_override("outline_size", 3)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.position = Vector2(0, 0)
	banner.size = vp
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.z_index = 21
	banner.modulate.a = 0.0
	_panel.add_child(banner)
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(banner, "position", Vector2(0, -15), 0.15)
	tw.tween_interval(0.4)
	tw.tween_property(banner, "modulate:a", 0.0, 0.2)
	tw.parallel().tween_property(banner, "position", Vector2(0, -35), 0.2)
	tw.tween_callback(func():
		if is_instance_valid(banner):
			banner.queue_free()
	)

func begin_current_turn() -> void:
	while _current_unit_index < _turn_order.size():
		_active_unit = _turn_order[_current_unit_index]
		if _active_unit.is_alive() and _active_unit.can_act():
			_highlight_active_unit()
			if _active_unit.is_hero:
				_phase = Phase.HERO_TURN
				_phase_label.text = "Votre tour"
				_phase_label.add_theme_color_override("font_color", COLOR_TEAL)
				_update_info("Tour de: %s" % _active_unit.get_name())
				_show_turn_banner("Votre tour", Color(0.30, 0.75, 0.90))
				_select_unit(_active_unit)
				_update_action_buttons()
				return
			else:
				_phase = Phase.ENEMY_TURN
				_phase_label.text = "Tour ennemi"
				_phase_label.add_theme_color_override("font_color", COLOR_CRIMSON)
				_update_info("Tour de: %s" % _active_unit.get_name())
				_show_turn_banner("Tour ennemi", Color(0.85, 0.25, 0.20))
				await get_tree().create_timer(0.5).timeout
				_process_enemy_turn()
				return
		_current_unit_index += 1
	_current_unit_index = 0
	_current_round += 1
	start_round()

func _set_tile_color(tile: HexTile, color: Color) -> void:
	tile.set_color(color)

func _highlight_active_unit() -> void:
	_deselect_hex_highlights()
	if _active_unit:
		var key = hex_key(_active_unit.q, _active_unit.r)
		if _hex_tiles.has(key):
			var tile = _hex_tiles[key]
			tile.set_color(Color(0.55, 0.42, 0.18))
			tile.set_border(Color(1.0, 0.85, 0.30, 0.80))
		if _active_unit.node and is_instance_valid(_active_unit.node):
			var marker: ColorRect = _active_unit.node.get_meta("active_marker")
			if marker:
				var tw = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE).set_loops()
				tw.tween_property(marker, "color", Color(1.0, 0.90, 0.30, 1.0), 0.4)
				tw.tween_property(marker, "color", Color(1.0, 0.90, 0.30, 0.30), 0.4)
				_active_unit.node.set_meta("marker_tween", tw)
			var glow: ColorRect = _active_unit.node.get_meta("active_glow")
			if glow:
				var gw = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE).set_loops()
				gw.tween_property(glow, "color", Color(1.0, 0.85, 0.20, 0.20), 0.6)
				gw.tween_property(glow, "color", Color(1.0, 0.85, 0.20, 0.05), 0.6)
				_active_unit.node.set_meta("glow_tween", gw)

func _show_turn_queue() -> void:
	for child in _turn_queue.get_children():
		child.queue_free()
	
	# Fond de la barre d'initiative
	var bar_bg := ColorRect.new()
	bar_bg.size = Vector2(580, 36)
	bar_bg.position = Vector2(0, 0)
	bar_bg.color = Color(0.04, 0.03, 0.05, 0.70)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_queue.add_child(bar_bg)

	var cx := 4
	var order_offset := 0
	for u in _turn_order:
		var is_current := _turn_order.size() > _current_unit_index and u == _turn_order[_current_unit_index]
		var already_acted := u.has_moved and u.has_acted
		var cell := ColorRect.new()
		cell.size = Vector2(60, 30)
		cell.position = Vector2(cx, 3)
		if is_current:
			cell.color = Color(0.30, 0.28, 0.22, 0.50)
		elif already_acted:
			cell.color = Color(0.08, 0.08, 0.10, 0.30)
		else:
			cell.color = Color(0.15, 0.13, 0.10, 0.35)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_turn_queue.add_child(cell)

		# Bordure camp
		var border_edge := ColorRect.new()
		border_edge.size = Vector2(60, 2)
		border_edge.position = Vector2(cx, 3)
		border_edge.color = Color(0.35, 0.60, 0.85, 0.70) if u.is_hero else Color(0.80, 0.25, 0.20, 0.70)
		border_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_turn_queue.add_child(border_edge)

		# Ordre
		var order_lbl := Label.new()
		order_lbl.text = str(order_offset + 1)
		order_lbl.add_theme_font_size_override("font_size", 8)
		order_lbl.add_theme_color_override("font_color", Color(0.50, 0.48, 0.42))
		order_lbl.position = Vector2(cx + 2, 5)
		order_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_turn_queue.add_child(order_lbl)

		# Nom tronqué
		var name_lbl := Label.new()
		var short_name = u.get_name()
		if short_name.length() > 6:
			short_name = short_name.left(5) + "."
		name_lbl.text = short_name
		name_lbl.add_theme_font_size_override("font_size", 9)
		if already_acted:
			name_lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
		else:
			name_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
		name_lbl.position = Vector2(cx + 4, 13)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_turn_queue.add_child(name_lbl)

		# Mini barre de vie
		var hp_ratio = float(u.stack.current_hp) / float(max(u.stack.get_max_hp_display(), 1))
		var mini_bg := ColorRect.new()
		mini_bg.size = Vector2(54, 3)
		mini_bg.position = Vector2(cx + 3, 26)
		mini_bg.color = Color(0.08, 0.02, 0.02, 0.70)
		mini_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_turn_queue.add_child(mini_bg)
		var mini_fill := ColorRect.new()
		mini_fill.size = Vector2(max(1, 52 * hp_ratio), 2)
		mini_fill.position = Vector2(cx + 4, 27)
		if hp_ratio > 0.6:
			mini_fill.color = Color(0.15, 0.70, 0.20, 0.90)
		elif hp_ratio > 0.3:
			mini_fill.color = Color(0.75, 0.55, 0.10, 0.90)
		else:
			mini_fill.color = Color(0.80, 0.12, 0.12, 0.90)
		mini_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_turn_queue.add_child(mini_fill)

		if already_acted:
			var done_icon := Label.new()
			done_icon.text = "v"
			done_icon.add_theme_font_size_override("font_size", 10)
			done_icon.add_theme_color_override("font_color", Color(0.40, 0.40, 0.40))
			done_icon.position = Vector2(cx + 48, 5)
			done_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_turn_queue.add_child(done_icon)

		cx += 64
		order_offset += 1

func _update_action_buttons() -> void:
	var can_move = _active_unit and _active_unit.is_hero and not _active_unit.has_moved
	var can_attack = _active_unit and _active_unit.is_hero and not _active_unit.has_acted
	var can_defend = _active_unit and _active_unit.is_hero and not _active_unit.has_acted
	var can_wait = _active_unit and _active_unit.is_hero and not _active_unit.has_acted

	for child in _action_bar.get_children():
		var btn = child as Button
		if not btn:
			continue
		btn.disabled = false
		var txt: String = btn.text
		if "Déplacer" in txt:
			btn.disabled = not can_move
		elif "Attaquer" in txt:
			btn.disabled = not can_attack
		elif "Défendre" in txt:
			btn.disabled = not can_defend
		elif "Attendre" in txt:
			btn.disabled = not can_wait

# ============================================
# SÉLECTION D'UNITÉ
# ============================================
func _select_unit(unit: CombatUnit) -> void:
	# Cacher l'anneau de l'ancienne sélection
	if _selected_unit and _selected_unit.selection_ring and is_instance_valid(_selected_unit.selection_ring):
		var tw_old = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw_old.tween_property(_selected_unit.selection_ring, "modulate:a", 0.0, 0.15)
	
	_selected_unit = unit
	# Afficher l'anneau de sélection
	if unit.selection_ring and is_instance_valid(unit.selection_ring):
		unit.selection_ring.modulate.a = 0.5
		var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(unit.selection_ring, "modulate", Color(0.70, 0.95, 0.35, 0.35), 0.3)
	
	_update_info("[%s] ATK:%d DEF:%d DMG:%d-%d HP:%d/%d" % [
		unit.get_name(), unit.get_attack(), unit.get_defense(),
		unit.get_damage_min(), unit.get_damage_max(),
		unit.stack.current_hp, unit.stack.get_max_hp_display()
	])
	_highlight_hexes(unit)
	_highlight_enemy_danger()
	_show_unit_stat_panel(unit)

func _highlight_hexes(unit: CombatUnit) -> void:
	for key in _hex_tiles:
		var parts = key.split(",")
		var q = int(parts[0])
		var r = int(parts[1])
		var tile = _hex_tiles[key]
		if not unit.has_moved:
			var dist = hex_distance(unit.q, unit.r, q, r)
			if dist <= unit.get_speed() and dist > 0 and not is_hex_occupied(q, r):
				if is_valid_hex(q, r):
					_set_tile_color(tile, Color(0.18, 0.35, 0.18, 0.60))
		if not unit.has_acted:
			var dist = hex_distance(unit.q, unit.r, q, r)
			if dist <= 1 and dist > 0 and is_hex_occupied(q, r):
				var target = get_unit_at(q, r)
				if target and target.is_hero != unit.is_hero:
					_set_tile_color(tile, Color(0.55, 0.15, 0.15, 0.60))

func _update_info(text: String) -> void:
	_info_label.text = text
	if _context_banner and _context_banner.modulate.a > 0:
		pass  # Garder la bannière contextuelle si active

func _show_context_message(text: String, color: Color = Color(0.95, 0.90, 0.70), duration: float = 1.5) -> void:
	if not _context_banner:
		return
	_context_banner.text = text
	_context_banner.add_theme_color_override("font_color", color)
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_context_banner, "modulate:a", 1.0, 0.1)
	tw.tween_interval(duration)
	tw.tween_property(_context_banner, "modulate:a", 0.0, 0.3)

func _log_message(msg: String) -> void:
	if _combat_log:
		_combat_log.append_text(msg + "\n")
		# Scroll automatique vers le bas
		_combat_log.scroll_to_line(_combat_log.get_line_count() - 1)

func _on_end_turn_pressed() -> void:
	if not _active_unit:
		return
	if _active_unit.is_hero:
		_active_unit.has_moved = true
		_active_unit.has_acted = true
		_log_message("[color=#aaaaaa][FIN] Fin de tour anticipée[/color]")
	_end_current_turn()

# ============================================
# ACTIONS DU JOUEUR
# ============================================
func _on_move_pressed() -> void:
	if not _active_unit or not _active_unit.is_hero or _active_unit.has_moved:
		return
	if _move_mode_active:
		_cancel_action_mode()
		return
	_enter_move_mode()

func _enter_move_mode() -> void:
	_move_mode_active = true
	_attack_mode_active = false
	_deselect_hex_highlights()
	_update_info("Cliquez sur une case bleue pour déplacer %s" % _active_unit.get_name())
	_show_context_message("Sélectionnez une case bleue pour déplacer " + _active_unit.get_name(), Color(0.30, 0.70, 0.90), 2.0)
	_set_hex_click_handler(_on_move_hex_clicked)
	_highlight_move_range(_active_unit)
	for key in _hex_tiles:
		var tile = _hex_tiles[key] as HexTile
		if tile:
			tile.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_attack_pressed() -> void:
	if not _active_unit or not _active_unit.is_hero or _active_unit.has_acted:
		return
	if _attack_mode_active:
		_cancel_action_mode()
		return
	_enter_attack_mode()

func _enter_attack_mode() -> void:
	_move_mode_active = false
	_attack_mode_active = true
	_deselect_hex_highlights()
	_update_info("Cliquez sur une unité ennemie pour attaquer")
	_show_context_message("Cliquez sur une case rouge pour attaquer!", Color(0.90, 0.30, 0.25), 2.0)
	_set_hex_click_handler(_on_attack_hex_clicked)
	_highlight_attack_targets(_active_unit)
	# Rendre toutes les cases cliquables pour que le joueur reçoive un retour
	# même si la cible est hors de portée
	for key in _hex_tiles:
		var tile = _hex_tiles[key] as HexTile
		if tile:
			tile.mouse_filter = Control.MOUSE_FILTER_STOP

func _cancel_action_mode() -> void:
	_move_mode_active = false
	_attack_mode_active = false
	_deselect_hex_handlers()
	_deselect_hex_highlights()
	_hex_click_callback = Callable()
	if _active_unit:
		_update_info("Action annulée — " + _active_unit.get_name())
		_select_unit(_active_unit)
	else:
		_update_info("Action annulée")
	_update_action_buttons()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _move_mode_active or _attack_mode_active:
			_cancel_action_mode()
			get_viewport().set_input_as_handled()

func _on_defend_pressed() -> void:
	if not _active_unit or not _active_unit.is_hero or _active_unit.has_acted:
		return
	_active_unit.defending = true
	_active_unit.has_acted = true
	_play_unit_anim(_active_unit, "block", 8.0, false, func():
		if _active_unit and _active_unit.is_alive():
			_play_unit_anim(_active_unit, "idle")
	)
	_log_message("[color=#5a9eb8][D] %s se défend![/color]" % _active_unit.get_name())
	_end_current_turn()

func _on_wait_pressed() -> void:
	if not _active_unit or not _active_unit.is_hero or _active_unit.has_acted:
		return
	_active_unit.has_moved = true
	_active_unit.has_acted = true
	_log_message("[color=#8a8a8a][~] %s attend.[/color]" % _active_unit.get_name())
	_end_current_turn()

func _on_move_hex_clicked(q: int, r: int) -> void:
	if not is_valid_hex(q, r):
		_show_context_message("Case invalide!", Color(0.90, 0.60, 0.20), 1.0)
		return
	if is_hex_occupied(q, r):
		_show_context_message("Case occupée par une unité!", Color(0.90, 0.60, 0.20), 1.0)
		return
	var dist = hex_distance(_active_unit.q, _active_unit.r, q, r)
	if dist > _active_unit.get_speed():
		_show_context_message("Trop loin! La portée de déplacement est de %d." % _active_unit.get_speed(), Color(0.90, 0.60, 0.20), 1.5)
		return
	_move_mode_active = false
	_move_unit(_active_unit, q, r)
	_active_unit.has_moved = true
	_deselect_hex_highlights()
	_select_unit(_active_unit)
	_update_action_buttons()

func _on_attack_hex_clicked(q: int, r: int) -> void:
	var target = get_unit_at(q, r)
	if not target:
		_show_context_message("Aucune cible à cet emplacement!", Color(0.90, 0.60, 0.20), 1.0)
		return
	if target.is_hero == _active_unit.is_hero:
		_show_context_message("Impossible d'attaquer un allié!", Color(0.90, 0.60, 0.20), 1.0)
		return
	var dist = hex_distance(_active_unit.q, _active_unit.r, q, r)
	if dist > 1:
		if not _active_unit.stack.get_base().get("is_ranged", false):
			_show_context_message("Cible trop éloignée! Déplacez-vous d'abord.", Color(0.90, 0.60, 0.20), 1.5)
			return
		if dist > 5:
			_show_context_message("Cible hors de portée!", Color(0.90, 0.60, 0.20), 1.0)
			return
	_attack_mode_active = false
	_resolve_attack(_active_unit, target)
	_active_unit.has_acted = true
	_deselect_hex_handlers()
	_deselect_hex_highlights()
	_update_action_buttons()
	_end_current_turn()

func _move_unit(unit: CombatUnit, target_q: int, target_r: int) -> void:
	var old_key = hex_key(unit.q, unit.r)
	var new_key = hex_key(target_q, target_r)

	_grid_units.erase(old_key)
	_grid_units[new_key] = unit
	unit.q = target_q
	unit.r = target_r

	var hex_center = hex_to_pixel(unit.q, unit.r)
	var target_px = hex_center.x + _hex_container.position.x + HEX_SIZE
	var target_py = hex_center.y + _hex_container.position.y + HEX_SIZE
	var target_pos = Vector2(target_px, target_py)
	_unit_base_positions[unit] = target_pos
	_play_unit_anim(unit, "walk", 10.0, true)
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(unit.node, "position", target_pos, 0.25)
	tw.tween_callback(func():
		if unit.is_alive():
			_play_unit_anim(unit, "idle")
	)

	_log_message("[color=#6ec3e0][>] %s se déplace.[/color]" % unit.get_name())

func _spawn_projectile(from: Vector2, to: Vector2) -> void:
	# Shuriken à 4 pointes
	var shuriken = ColorRect.new()
	shuriken.size = Vector2(10, 10)
	shuriken.position = from - Vector2(5, 5)
	shuriken.color = Color(0.85, 0.80, 0.75, 0.95)
	shuriken.z_index = 30
	add_child(shuriken)
	var tw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(shuriken, "position", to - Vector2(5, 5), 0.18)
	tw.parallel().tween_property(shuriken, "rotation", deg_to_rad(360), 0.18)
	tw.tween_callback(func():
		# Éclat à l'impact (katana clash spark)
		var burst = ColorRect.new()
		burst.size = Vector2(18, 18)
		burst.position = to - Vector2(9, 9)
		burst.color = Color(1.0, 0.85, 0.40, 0.90)
		burst.z_index = 30
		add_child(burst)
		var btw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		btw.tween_property(burst, "size", Vector2(2, 2), 0.12)
		btw.parallel().tween_property(burst, "modulate:a", 0.0, 0.12)
		btw.tween_callback(func():
			if is_instance_valid(burst): burst.queue_free()
			if is_instance_valid(shuriken): shuriken.queue_free()
		)
		# Petites particules d'étincelles
		for i in 4:
			var sp = ColorRect.new()
			sp.size = Vector2(3, 3)
			var angle = _rng.randf_range(0, PI * 2)
			var dist = _rng.randf_range(8, 20)
			sp.position = to - Vector2(1.5, 1.5)
			sp.color = Color(1.0, _rng.randf_range(0.5, 0.9), 0.1, 0.9)
			sp.z_index = 30
			add_child(sp)
			var stw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			stw.tween_property(sp, "position", sp.position + Vector2(cos(angle), sin(angle)) * dist, 0.2)
			stw.parallel().tween_property(sp, "modulate:a", 0.0, 0.2)
			stw.tween_callback(func():
				if is_instance_valid(sp): sp.queue_free()
			)
	)

func _spawn_damage_number(pos: Vector2, dmg: int, color: Color) -> void:
	var lbl = Label.new()
	lbl.text = str(dmg)
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.80))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.position = pos + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-8, -3))
	lbl.z_index = 50
	add_child(lbl)
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lbl, "position", lbl.position + Vector2(0, -50), 0.7)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.5).set_delay(0.3)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.4, 1.4), 0.1)
	tw.tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free()
	)

func _spawn_slash_effect(from: Vector2, to: Vector2) -> void:
	var slash_frames: Array = _effect_frames.get("slash", [])
	if slash_frames.size() == 0:
		return
	var dir = (to - from).normalized()
	var mid = (from + to) / 2.0
	var slash = Sprite2D.new()
	slash.texture = slash_frames[0]
	slash.position = mid
	slash.z_index = 25
	slash.rotation = atan2(dir.y, dir.x)
	var tex_size = slash_frames[0].get_size()
	slash.scale = Vector2(1.5, 1.5)
	add_child(slash)
	# Animer à travers les frames
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	for i in range(1, slash_frames.size()):
		tw.tween_callback(func():
			if is_instance_valid(slash):
				slash.texture = slash_frames[i]
		)
		tw.tween_interval(0.04)
	tw.tween_property(slash, "modulate:a", 0.0, 0.08)
	tw.tween_callback(func():
		if is_instance_valid(slash):
			slash.queue_free()
	)

func _spawn_blood_effect(pos: Vector2) -> void:
	var blood_frames: Array = _effect_frames.get("blood", [])
	if blood_frames.size() == 0:
		return
	var blood = Sprite2D.new()
	blood.texture = blood_frames[0]
	blood.position = pos + Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
	blood.z_index = 25
	blood.rotation = _rng.randf_range(-0.3, 0.3)
	var tex_size = blood_frames[0].get_size()
	blood.scale = Vector2(1.3, 1.3)
	add_child(blood)
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(0.03)
	tw.tween_callback(func():
		if is_instance_valid(blood):
			blood.texture = blood_frames[1]
	)
	tw.tween_interval(0.6)
	tw.tween_property(blood, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		if is_instance_valid(blood):
			blood.queue_free()
	)

func _resolve_attack(attacker: CombatUnit, target: CombatUnit) -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	var atk = attacker.get_attack()
	var def = target.get_defense()
	var base_dmg = rng.randi_range(attacker.get_damage_min(), attacker.get_damage_max())
	var modified_dmg = max(1, base_dmg + atk - def)
	var final_dmg = rng.randi_range(max(1, modified_dmg - 2), modified_dmg + 2)

	var killed = target.take_damage(final_dmg)
	var is_ranged = attacker.stack.get_base().get("is_ranged", false)

	var atk_icon = "~>" if is_ranged else "><"
	_log_message("[color=#ffcc44]%s[/color] %s [color=#ff6666]%s[/color] → [color=#ff4444]%d[/color] dégâts! (×%d)" % [
		attacker.get_name(), atk_icon, target.get_name(), final_dmg, killed
	])

	_shake_unit(target)

	# Freeze-frame effect: court arrêt sur image avant l'impact pour dramatiser
	var hit_pause := 0.04
	if _panel:
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_anim_paused = true

	# Flash blanc sur la cible
	if target.sprite and is_instance_valid(target.sprite):
		var orig_mod = target.sprite.modulate
		target.sprite.modulate = Color(1.4, 1.4, 1.2)
		var ftw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		ftw.tween_property(target.sprite, "modulate", orig_mod, 0.2)

	if attacker.node:
		if is_ranged:
			_spawn_projectile(attacker.node.position, target.node.position)
			_play_unit_anim(attacker, "attack", 15.0, false)
		else:
			# Animation d'attaque mêlée avec effet de lunge plus dynamique
			_play_unit_anim(attacker, "attack", 14.0, false, func():
				_play_unit_anim(attacker, "idle")
			)
			var atk_dir = Vector2(target.node.position - attacker.node.position).normalized()
			var lunge_dist = 14.0
			var lunge_target = attacker.node.position + atk_dir * lunge_dist
			var lunge_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			lunge_tw.tween_property(attacker.node, "position", lunge_target, 0.04)
			lunge_tw.tween_interval(hit_pause)
			lunge_tw.tween_property(attacker.node, "position", attacker.node.position, 0.09)
			# Effet slash au point d'impact
			_spawn_slash_effect(lunge_target + atk_dir * 8, target.node.position)

	# Animation de dégâts sur la cible (après le freeze-frame)
	if target.node:
		_play_unit_anim(target, "hurt", 10.0, false, func():
			if target.is_alive():
				_play_unit_anim(target, "idle")
		)

	# Screen shake plus violent au moment de l'impact
	var shake_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	var shake_intensity = 4 if is_ranged else 7
	shake_tw.tween_interval(hit_pause)
	shake_tw.tween_callback(func():
		if _panel:
			var orig_pos = _panel.position
			var stw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			stw.tween_property(_panel, "position", orig_pos + Vector2(shake_intensity, 2), 0.03)
			stw.tween_property(_panel, "position", orig_pos - Vector2(shake_intensity - 2, shake_intensity - 2), 0.03)
			stw.tween_property(_panel, "position", orig_pos + Vector2(shake_intensity - 1, -2), 0.03)
			stw.tween_property(_panel, "position", orig_pos, 0.03)
			_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_anim_paused = false
	)

	# Effet visuel de l'attaque — cercle d'impact au point de contact
	if target.node:
		var target_pos = target.node.position + _hex_container.position
		if _vfx:
			_vfx.hit_impact(target_pos, 1.0)
			_vfx.spark_burst(target_pos, 12, Color(1.0, 0.7, 0.2), 0.90)
		# Effet de sang
		_spawn_blood_effect(target.node.position)
		_spawn_damage_number(target_pos + Vector2(0, -20), final_dmg, Color(1.0, 0.8, 0.1))
		# Flash rouge bref sur tout l'écran pour l'impact
		var dmg_flash = ColorRect.new()
		dmg_flash.color = Color(0.60, 0.06, 0.04, 0.25)
		dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dmg_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		dmg_flash.z_index = 55
		_panel.add_child(dmg_flash)
		var flash_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		flash_tw.tween_property(dmg_flash, "modulate:a", 0.0, 0.15)
		flash_tw.tween_callback(func():
			if is_instance_valid(dmg_flash):
				dmg_flash.queue_free()
		)

	# Effet de mort — dissolution avec particules
	if not target.is_alive():
		_log_message("[color=#ff4444]%s est vaincu![/color]" % target.get_name())
		_grid_units.erase(hex_key(target.q, target.r))
		target.anim_on_finish = Callable()
		if target.node and is_instance_valid(target.node):
			_anim_paused = true
			_play_unit_anim(target, "death", 10.0, false)
			if _vfx:
				_vfx.death_effect(target.node.position + _hex_container.position)
			# Éclatement d'âme vers le haut
			var soul_pos = target.node.position + _hex_container.position
			for s in 8:
				var soul = ColorRect.new()
				soul.size = Vector2(randf_range(3, 7), randf_range(3, 7))
				soul.color = Color(0.85, 0.75, 0.50, 0.80)
				soul.position = soul_pos + Vector2(randf_range(-10, 10), randf_range(-10, 10))
				soul.z_index = 30
				soul.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(soul)
				var stw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				stw.tween_property(soul, "position", soul.position + Vector2(randf_range(-20, 20), -30 - randf_range(0, 40)), 0.6)
				stw.parallel().tween_property(soul, "modulate:a", 0.0, 0.6)
				stw.parallel().tween_property(soul, "scale", Vector2(0.3, 0.3), 0.6)
				stw.tween_callback(func():
					if is_instance_valid(soul): soul.queue_free()
				)
			# Dissolution with scale + rotate
			var dtw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			dtw.set_parallel(true)
			dtw.tween_property(target.node, "modulate:a", 0.0, 0.5)
			dtw.tween_property(target.node, "scale", Vector2(0.2, 0.2), 0.5)
			dtw.tween_property(target.node, "rotation", deg_to_rad(randf_range(-15, 15)), 0.5)
			dtw.tween_callback(func():
				if is_instance_valid(target.node):
					target.node.visible = false
				_anim_paused = false
			)

	_update_unit_visual(target)

	var hero_alive = false
	var enemy_alive = false
	for u in _all_units:
		if u.is_alive():
			if u.is_hero:
				hero_alive = true
			else:
				enemy_alive = true

	# Track combat stats
	if attacker.is_hero:
		_player_dmg_dealt += final_dmg
		_player_units_killed += killed
	else:
		_player_units_lost += killed

	if not enemy_alive:
		_end_combat(true)
	elif not hero_alive:
		_end_combat(false)

func _shake_unit(unit: CombatUnit) -> void:
	if not unit.node:
		return
	var orig = unit.node.position
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(unit.node, "position", orig + Vector2(6, 0), 0.04)
	tw.tween_property(unit.node, "position", orig - Vector2(4, 0), 0.04)
	tw.tween_property(unit.node, "position", orig, 0.04)

# ============================================
# HEX CLICK HANDLING
# ============================================
var _hex_click_callback: Callable = Callable()

func _set_hex_click_handler(callback: Callable) -> void:
	_hex_click_callback = callback

func _set_hex_click_handler_for_hexes() -> void:
	for key in _hex_tiles:
		var tile = _hex_tiles[key] as HexTile
		if not tile: continue
		tile.mouse_filter = Control.MOUSE_FILTER_STOP

func _get_terrain_color(q: int, r: int) -> Color:
	var is_left = q < 3
	var is_right = q > 7
	var base_color: Color
	if is_left:
		base_color = Color(0.18, 0.42, 0.14)
	elif is_right:
		base_color = Color(0.35, 0.22, 0.12)
	else:
		base_color = Color(0.24, 0.36, 0.16)
	if q == 3:
		base_color = Color(0.18, 0.42, 0.14).lerp(Color(0.24, 0.36, 0.16), 0.5)
	elif q == 7:
		base_color = Color(0.24, 0.36, 0.16).lerp(Color(0.35, 0.22, 0.12), 0.5)
	var noise := sin(q * 1.7 + r * 2.3) * 0.05 + cos(q * 3.1 - r * 1.5) * 0.04
	var pattern := sin(q * 4.7 + r * 5.3) * 0.03 + cos(q * 6.1 - r * 3.7) * 0.02
	base_color = Color(
		clampf(base_color.r + noise + pattern, 0, 1),
		clampf(base_color.g + noise * 0.7 + pattern * 0.7, 0, 1),
		clampf(base_color.b + noise * 0.5 + pattern * 0.3, 0, 1)
	)
	if (q + r) % 2 == 0:
		base_color = base_color.lightened(0.08)
	return base_color

func _deselect_hex_highlights() -> void:
	for key in _hex_tiles:
		var parts = key.split(",")
		var q = int(parts[0])
		var r = int(parts[1])
		var tile = _hex_tiles[key] as HexTile
		if not tile: continue
		tile.set_color(_get_terrain_color(q, r))
		tile.set_border(Color(0.15, 0.15, 0.12, 0.35))
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _deselect_hex_handlers() -> void:
	_hex_click_callback = Callable()
	for key in _hex_tiles:
		var tile = _hex_tiles[key]
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if tile is HexTile:
			(tile as HexTile).set_border(Color(0.15, 0.15, 0.12, 0.35))

func _on_hex_mouse_entered(q: int, r: int) -> void:
	if _phase != Phase.HERO_TURN:
		return
	var unit = get_unit_at(q, r)
	if unit and not unit.is_hero and unit.is_alive():
		_show_tooltip(unit)

func _on_hex_mouse_exited(q: int, r: int) -> void:
	if _tooltip:
		_tooltip.visible = false

func _show_tooltip(unit: CombatUnit) -> void:
	if not _tooltip:
		return
	for c in _tooltip.get_children():
		c.queue_free()

	var y := 4

	var name_lbl := Label.new()
	name_lbl.text = unit.get_name()
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.88, 0.82))
	name_lbl.position = Vector2(6, y)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(name_lbl)

	y += 18
	var stats_lbl := Label.new()
	stats_lbl.text = "ATK:%d DEF:%d HP:%d/%d" % [unit.get_attack(), unit.get_defense(), unit.stack.current_hp, unit.stack.get_max_hp_display()]
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.70, 0.68, 0.62))
	stats_lbl.position = Vector2(6, y)
	stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(stats_lbl)

	y += 16
	var count_lbl := Label.new()
	count_lbl.text = "×%d" % unit.stack.get_alive_count()
	count_lbl.add_theme_font_size_override("font_size", 10)
	count_lbl.add_theme_color_override("font_color", Color(0.85, 0.25, 0.20))
	count_lbl.position = Vector2(6, y)
	count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(count_lbl)

	_tooltip.size = Vector2(140, y + 22)

	var hex_center = hex_to_pixel(unit.q, unit.r)
	var px = hex_center.x + _hex_container.position.x + HEX_SIZE
	var py = hex_center.y + _hex_container.position.y - _tooltip.size.y + 10
	var vp = get_viewport().get_visible_rect().size
	_tooltip.position = Vector2(min(px, vp.x - 150), max(py, 4))
	_tooltip.visible = true

func _on_hex_tile_clicked(q: int, r: int) -> void:
	if _hex_click_callback.is_valid():
		_hex_click_callback.call(q, r)
	else:
		_default_hex_click(q, r)

func _default_hex_click(q: int, r: int) -> void:
	var unit = get_unit_at(q, r)
	if unit and unit.is_alive():
		var is_hero_turn = _phase == Phase.HERO_TURN
		if unit.is_hero == is_hero_turn:
			_select_unit(unit)

func _highlight_move_range(unit: CombatUnit) -> void:
	var speed = unit.get_speed()
	for q in range(HEX_COLS):
		for r in range(HEX_ROWS):
			if is_hex_occupied(q, r):
				continue
			var dist = hex_distance(unit.q, unit.r, q, r)
			if dist <= speed and dist > 0:
				var key = hex_key(q, r)
				if _hex_tiles.has(key):
					var tile = _hex_tiles[key] as HexTile
					if tile:
						tile.set_color(Color(0.15, 0.40, 0.20, 0.65))
						tile.set_border(Color(0.25, 0.65, 0.30, 0.55))
						tile.mouse_filter = Control.MOUSE_FILTER_STOP

func _highlight_attack_targets(unit: CombatUnit) -> void:
	for u in _all_units:
		if not u.is_alive() or u.is_hero == unit.is_hero:
			continue
		var dist = hex_distance(unit.q, unit.r, u.q, u.r)
		var max_range = 5 if unit.stack.get_base().get("is_ranged", false) else 1
		if dist <= max_range:
			var key = hex_key(u.q, u.r)
			if _hex_tiles.has(key):
				var tile = _hex_tiles[key] as HexTile
				if tile:
					tile.set_color(Color(0.65, 0.12, 0.12, 0.70))
					tile.set_border(Color(0.85, 0.22, 0.18, 0.55))
					tile.mouse_filter = Control.MOUSE_FILTER_STOP

func _highlight_enemy_danger() -> void:
	# Affiche la zone de danger des ennemis (où ils peuvent attaquer)
	for u in _all_units:
		if not u.is_alive() or u.is_hero or (u.has_moved and u.has_acted):
			continue
		var max_range = 5 if u.stack.get_base().get("is_ranged", false) else 1
		for q in range(HEX_COLS):
			for r in range(HEX_ROWS):
				var key = hex_key(q, r)
				if not _hex_tiles.has(key):
					continue
				var dist = hex_distance(u.q, u.r, q, r)
				if dist <= max_range and dist > 0:
					# Ne pas surcharger les cases déjà colorées
					var tile = _hex_tiles[key] as HexTile
					if tile and tile.hex_color.a < 0.1:
						tile.set_color(Color(0.50, 0.08, 0.08, 0.15))

# ============================================
# FIN DE TOUR
# ============================================
func _clear_active_marker(unit: CombatUnit) -> void:
	if not unit or not unit.node or not is_instance_valid(unit.node):
		return
	var marker: ColorRect = unit.node.get_meta("active_marker")
	if marker:
		marker.color = Color(0, 0, 0, 0)
	var tw: Tween = unit.node.get_meta("marker_tween")
	if tw and tw.is_valid():
		tw.kill()
		unit.node.remove_meta("marker_tween")
	var gw: Tween = unit.node.get_meta("glow_tween")
	if gw and gw.is_valid():
		gw.kill()
		unit.node.remove_meta("glow_tween")
	var glow: ColorRect = unit.node.get_meta("active_glow")
	if glow:
		glow.color = Color(0, 0, 0, 0)

func _end_current_turn() -> void:
	_current_unit_index += 1
	_deselect_hex_highlights()
	_deselect_hex_handlers()
	if _active_unit:
		_clear_active_marker(_active_unit)
	_selected_unit = null
	_active_unit = null
	_hide_stat_panel()
	begin_current_turn()

# ============================================
# IA ENNEMIE
# ============================================
func _process_enemy_turn() -> void:
	if not _active_unit or not _active_unit.is_alive():
		_end_current_turn()
		return

	var unit = _active_unit
	var best_target: CombatUnit = null
	var best_dist = 999
	for u in _all_units:
		if u.is_alive() and u.is_hero:
			var dist = hex_distance(unit.q, unit.r, u.q, u.r)
			if dist < best_dist:
				best_dist = dist
				best_target = u

	if not best_target:
		unit.has_acted = true
		_end_current_turn()
		return

	var attack_range = 5 if unit.stack.get_base().get("is_ranged", false) else 1

	if best_dist <= attack_range:
		_resolve_attack(unit, best_target)
		unit.has_acted = true
	else:
		var moved = _ai_move_towards(unit, best_target)
		unit.has_moved = moved
		if moved:
			var new_dist = hex_distance(unit.q, unit.r, best_target.q, best_target.r)
			if new_dist <= attack_range:
				await get_tree().create_timer(0.2).timeout
				if best_target.is_alive():
					_resolve_attack(unit, best_target)
				unit.has_acted = true
			else:
				unit.has_acted = true
		else:
			unit.has_acted = true

	await get_tree().create_timer(0.3).timeout
	_end_current_turn()

func _ai_move_towards(unit: CombatUnit, target: CombatUnit) -> bool:
	var speed = unit.get_speed()
	var best_q = unit.q
	var best_r = unit.r
	var best_dist = hex_distance(unit.q, unit.r, target.q, target.r)

	for q in range(max(0, unit.q - speed), min(HEX_COLS, unit.q + speed + 1)):
		for r in range(max(0, unit.r - speed), min(HEX_ROWS, unit.r + speed + 1)):
			if is_hex_occupied(q, r):
				continue
			var dist = hex_distance(unit.q, unit.r, q, r)
			if dist > speed or dist == 0:
				continue
			var target_dist = hex_distance(q, r, target.q, target.r)
			if target_dist < best_dist:
				best_q = q
				best_r = r
				best_dist = target_dist

	if best_q != unit.q or best_r != unit.r:
		_move_unit(unit, best_q, best_r)
		return true
	return false

# ============================================
# FIN DU COMBAT
# ============================================
func _end_combat(won: bool) -> void:
	_phase = Phase.VICTORY if won else Phase.DEFEAT
	_action_bar.visible = false

	var text = "VICTOIRE!" if won else "DÉFAITE..."
	var color = COLOR_GOLD if won else COLOR_CRIMSON
	var msg = "[color=%s]%s[/color]" % ["#d4a017" if won else "#cc3333", text]

	_log_message(msg)

	var total_gold = 0
	var total_xp = 100
	var enemy_killed = 0
	var enemy_remaining = 0
	if won:
		for u in _all_units:
			if not u.is_hero:
				total_gold += u.stack.count * 2
				if not u.is_alive():
					enemy_killed += 1
				else:
					enemy_remaining += 1

	var tw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_panel, "modulate:a", 0.5, 0.5)
	tw.tween_callback(func():
		_spawn_result_panel(text, won, total_gold, total_xp, enemy_killed)
	)

func _spawn_result_panel(title_text: String, won: bool, gold: int, xp: int, enemy_killed: int = 0) -> void:
	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.85)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Particules de fond (confettis pour victoire, cendres pour défaite)
	if won:
		for i in range(20):
			var confetti = ColorRect.new()
			confetti.size = Vector2(randf_range(4, 10), randf_range(4, 10))
			confetti.color = Color(
				randf_range(0.8, 1.0), randf_range(0.4, 0.9), randf_range(0.1, 0.6), 0.7
			)
			confetti.position = Vector2(randf_range(0, get_viewport().size.x), -20)
			confetti.z_index = 50
			confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(confetti)
			var ctw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			ctw.tween_property(confetti, "position:y", get_viewport().size.y + 20, randf_range(2.0, 4.0))
			ctw.parallel().tween_property(confetti, "position:x", confetti.position.x + randf_range(-40, 40), randf_range(2.0, 4.0))
			ctw.parallel().tween_property(confetti, "rotation", randf_range(-4, 4), randf_range(2.0, 4.0))
			ctw.tween_callback(func(): if is_instance_valid(confetti): confetti.queue_free())
	else:
		for i in range(12):
			var ash = ColorRect.new()
			ash.size = Vector2(randf_range(3, 6), randf_range(3, 6))
			ash.color = Color(0.15, 0.12, 0.10, 0.50)
			ash.position = Vector2(randf_range(0, get_viewport().size.x), get_viewport().size.y + 10)
			ash.z_index = 50
			ash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(ash)
			var atw = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			atw.tween_property(ash, "position:y", -20, randf_range(3.0, 5.0))
			atw.parallel().tween_property(ash, "position:x", ash.position.x + randf_range(-20, 20), randf_range(3.0, 5.0))
			atw.parallel().tween_property(ash, "modulate:a", 0.0, randf_range(3.0, 5.0)).set_delay(randf_range(1.0, 2.0))
			atw.tween_callback(func(): if is_instance_valid(ash): ash.queue_free())

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220
	panel.offset_top = -180
	panel.offset_right = 220
	panel.offset_bottom = 180
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.8, 0.8)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.04, 0.07, 0.96)
	ps.border_color = COLOR_GOLD if won else COLOR_CRIMSON
	ps.border_width_left = 2
	ps.border_width_right = 2
	ps.border_width_top = 2
	ps.border_width_bottom = 2
	ps.corner_radius_top_left = 24
	ps.corner_radius_top_right = 24
	ps.corner_radius_bottom_left = 24
	ps.corner_radius_bottom_right = 24
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	# Bannière décorative en haut du panneau
	var deco_bar = ColorRect.new()
	deco_bar.anchor_left = 0
	deco_bar.anchor_top = 0
	deco_bar.anchor_right = 1
	deco_bar.anchor_bottom = 0
	deco_bar.offset_left = 0
	deco_bar.offset_top = 0
	deco_bar.offset_right = 0
	deco_bar.offset_bottom = 55
	deco_bar.color = Color(0.18, 0.05, 0.04, 0.90) if won else Color(0.08, 0.04, 0.06, 0.90)
	deco_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(deco_bar)

	# Ligne dorée
	var accent_line = ColorRect.new()
	accent_line.anchor_left = 0
	accent_line.anchor_top = 0
	accent_line.anchor_right = 1
	accent_line.anchor_bottom = 0
	accent_line.offset_left = 0
	accent_line.offset_top = 53
	accent_line.offset_right = 0
	accent_line.offset_bottom = 55
	accent_line.color = COLOR_GOLD if won else Color(0.50, 0.38, 0.20, 0.60)
	accent_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(accent_line)

	var title = Label.new()
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(0, 50)
	title.text = title_text
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", COLOR_GOLD if won else COLOR_CRIMSON)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
	panel.add_child(title)

	if won:
		var reward = Label.new()
		reward.set_anchors_preset(Control.PRESET_TOP_WIDE)
		reward.offset_top = 60
		reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward.text = "Or: %d  |  XP: %d" % [gold, xp]
		reward.add_theme_font_size_override("font_size", 16)
		reward.add_theme_color_override("font_color", Color(0.92, 0.75, 0.18))
		reward.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.50))
		panel.add_child(reward)

	# Stats
	var stats_y := 85
	if won:
		stats_y = 95
	var stat_labels := []
	if won:
		stat_labels.append(["Ennemis vaincus", str(enemy_killed), Color(0.65, 0.85, 0.35)])
	stat_labels.append(["Dégâts infligés", str(_player_dmg_dealt), Color(0.90, 0.60, 0.20)])
	stat_labels.append(["Pertes alliées", str(_player_units_lost), Color(0.85, 0.25, 0.20)])
	stat_labels.append(["Rounds", str(_current_round), Color(0.50, 0.75, 0.80)])

	for s in stat_labels:
		var lbl := Label.new()
		lbl.text = s[0] + ":  " + s[1]
		lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		lbl.offset_top = stats_y
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", s[2])
		panel.add_child(lbl)
		stats_y += 24

	var btn = Button.new()
	btn.set_anchors_preset(Control.PRESET_CENTER)
	btn.offset_top = 50
	btn.custom_minimum_size = Vector2(200, 48)
	btn.text = "Continuer"
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.90))
	var bns = StyleBoxFlat.new()
	bns.bg_color = Color(0.18, 0.45, 0.18) if won else Color(0.45, 0.18, 0.18)
	bns.border_color = Color(0.30, 0.65, 0.30) if won else Color(0.65, 0.30, 0.30)
	bns.border_width_left = 1
	bns.border_width_right = 1
	bns.border_width_top = 1
	bns.border_width_bottom = 3
	bns.corner_radius_top_left = 12
	bns.corner_radius_top_right = 12
	bns.corner_radius_bottom_left = 12
	bns.corner_radius_bottom_right = 12
	btn.add_theme_stylebox_override("normal", bns)
	btn.modulate.a = 0.0
	panel.add_child(btn)

	# Animation d'entrée rebondissante
	var anim = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	anim.tween_property(panel, "modulate:a", 1.0, 0.3)
	anim.parallel().tween_property(panel, "scale", Vector2(1.0, 1.0), 0.4)
	anim.tween_callback(func():
		var btw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		btw.tween_property(btn, "modulate:a", 1.0, 0.2)
	)

	btn.pressed.connect(func():
		btn.disabled = true
		var h = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		h.tween_property(panel, "modulate:a", 0.0, 0.2)
		h.parallel().tween_property(panel, "scale", Vector2(0.9, 0.9), 0.2)
		h.parallel().tween_property(dim, "modulate:a", 0.0, 0.2)
		h.tween_callback(func():
			if is_instance_valid(dim): dim.queue_free()
			if is_instance_valid(panel): panel.queue_free()
			visible = false
			_panel.queue_free()
			_panel = null
			if won:
				combat_victory.emit(gold, xp)
				combat_ended.emit(true)
			else:
				combat_defeat.emit()
				combat_ended.emit(false)
		)
	)
