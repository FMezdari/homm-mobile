extends Node2D

# Constants pour la carte
const TILE_SIZE: int = 64
const COMBAT_SCENE := preload("res://scenes/combat_manager.tscn")
const TACTICAL_COMBAT_SCENE := preload("res://scenes/tactical_combat.tscn")

# Pixel art terrain tiles preloadés
var _pixel_tiles: Dictionary = {}  # int -> Array[Image] (3 variants per type)
var _pixel_tiles_loaded: bool = false

# Dimensions du monde (NOUVEAUX noms pour éviter le cache Godot)
var _map_width: int = 120
var _map_height: int = 80
var _play_w: int = 120
var _play_h: int = 80
var _zx: int = 0
var _zy: int = 0
var _zex: int = 120
var _zey: int = 80

# Aliases pour compatibilité (propriétés dynamiques)
var _world_w: int:
	get: return _map_width
	set(value): _map_width = value
var _world_h: int:
	get: return _map_height
	set(value): _map_height = value
var _zone_w: int:
	get: return _play_w
	set(value): _play_w = value
var _zone_h: int:
	get: return _play_h
	set(value): _play_h = value

# Références aux objets
var _hero: Node2D = null
var _camera: Camera2D = null
var _movement_indicator: Node2D = null  # Indicateur de portée de déplacement
var _floating_texts: Array = []  # Textes flottants (effets visuels)
const MAX_FLOATING_TEXTS: int = 6
var rng: RandomNumberGenerator = RandomNumberGenerator.new()  # Générateur de nombres aléatoires global

# Références UI (pointent vers les labels du HUD)
var _label_gold: Label = null
var _label_wood: Label = null
var _label_ore: Label = null

# Position du héros
var _hero_tile: Vector2i = Vector2i.ZERO


# Référence vers le générateur de sprites extrait
var _sg := SpriteGenerator.new()
var _vignette_overlay: ColorRect = null
var _visual_env: WorldEnvironment = null

# Ressources du joueur
var _gold: int = 800
var _wood: int = 50
var _ore: int = 30

func _ready() -> void:
	rng.randomize()
	print("=== WORLD SIZE === ", _world_w, "x", _world_h)
	print("=== ZONE SIZE === ", _zone_w, "x", _zone_h, " (toute la map colorée)")
	print("=== VÉRIFICATION: _play_w = ", _play_w, " _play_h = ", _play_h)
	print("=== HoMM3: Heroes of Conquest - Étape 10 : Niveau et Expérience ===")
	print("Création de la carte avec TileMapLayer")
	_async_init()

func _restore_save_seed() -> void:
	if not FileAccess.file_exists("user://save_game.json"):
		return
	var file = FileAccess.open("user://save_game.json", FileAccess.READ)
	if not file:
		return
	var json_string = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY or not data.has("rng_seed"):
		return
	rng.seed = data["rng_seed"]
	print("🌱 Graine RNG restaurée: ", rng.seed)

func _async_init() -> void:
	if GameData.should_load_save:
		_restore_save_seed()
	await _create_map()
	await get_tree().process_frame

	_create_cities()
	_create_enemies()
	await get_tree().process_frame

	_create_resources()
	_create_hero()
	_hero_army = []
	await get_tree().process_frame

	_create_ui()
	_create_town_overlay()
	_register_game_data()

	# Donner une armée de départ au héros via ArmyManager
	if GameData.heroes.size() > 0:
		var army_mgr: Node = load("res://scripts/army_manager.gd").new()
		add_child(army_mgr)
		army_mgr.give_starting_army(0)
		_hero_army = GameData.heroes[0].army.stacks
		army_mgr.queue_free()
	else:
		# Fallback: armée minimale
		var fallback_army := GameData.Army.new()
		fallback_army.add_stack("ashigaru", 10)
		fallback_army.add_stack("samurai", 3)
		_hero_army = fallback_army.stacks
	_hero_mp = _hero_max_mp
	_init_fog_of_war()
	await get_tree().process_frame

	_create_bosses()
	_create_merchants()
	_init_enemy_armies()
	_init_quests()
	_update_fog_of_war()
	_create_sky_background()
	_setup_visual_enhancements()

	_combat_manager = COMBAT_SCENE.instantiate()
	_combat_manager.combat_victory.connect(_on_combat_victory)
	_combat_manager.combat_defeat.connect(_on_combat_defeat)
	_combat_manager.combat_fled.connect(_on_combat_fled)
	_combat_manager.combat_ended.connect(_on_combat_ended)
	add_child(_combat_manager)
	
	# Initialiser le combat tactique (HoMM3-style)
	_tactical_combat = TACTICAL_COMBAT_SCENE.instantiate()
	_tactical_combat.combat_victory.connect(_on_combat_victory)
	_tactical_combat.combat_defeat.connect(_on_combat_defeat)
	_tactical_combat.combat_fled.connect(_on_combat_fled)
	_tactical_combat.combat_ended.connect(_on_combat_ended)
	add_child(_tactical_combat)
	print("✓ Combat Tactique initialisé")

	_llm_client = LLMClient.new()
	add_child(_llm_client)
	print("✓ Combat Manager initialisé")

	if GameData.should_load_save:
		_load_game()
	else:
		_spawn_neutral_creatures()

	print("✓ Carte créée : ", _world_w, "x", _world_h, " tuiles")
	print("✓ ", CITY_COUNT, " villes créées sur la carte")
	print("✓ ", WANDERER_COUNT, " ennemis errants créés")
	print("✓ ", _bosses.size(), " boss créés")
	print("✓ ", RESOURCE_COUNT, " ressources à collecter")
	print("✓ Arbres: tuiles forêt pixel art (pas de sprites d'arbres externes)")
	print("✓ Rochers créés : ", ROCK_COUNT, " rochers")
	print("✓ Effet de sélection doré autour du héros")
	print("✓ Prêt pour l'aventure !")
	LoadingScreen.hide_loading()
	if RetroBGM and RetroBGM.has_method("switch_to_exploration"):
		RetroBGM.switch_to_exploration()

func _create_map() -> void:
	print("=== _create_map ===")
	print("World: ", _world_w, "x", _world_h, " | Zone: ", _zx, ",", _zy, " to ", _zex, ",", _zey)
	
	# === DÉTRUIRE ANCIEN TERRAIN ===
	for child in get_children():
		if child.name == "MapSprite" or child is TileMapLayer:
			child.queue_free()
			print("=== ANCIEN TERRAIN DÉTRUIT ===")
	
	# Générer l'image du terrain
	var map_texture: ImageTexture = await _generate_map_image()
	
	# Créer un Sprite2D pour afficher le terrain
	_map_sprite = Sprite2D.new()
	_map_sprite.name = "MapSprite"
	_map_sprite.texture = map_texture
	_map_sprite.position = Vector2(_zone_w * TILE_SIZE / 2, _zone_h * TILE_SIZE / 2)  # Centré sur la map
	_map_sprite.set_z_index(-10)
	_map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_map_sprite)
	_create_fog_overlay()
	print("=== TERRAIN SPRITE CRÉÉ: ", _zone_w, "×", _zone_h, " tuiles ===")

	print("Carte générée : ", _zone_w, "×", _zone_h, " = ", _zone_w * _zone_h, " tuiles")
	_create_decorations()
	_create_mountain_sprites()
	_create_bridges()
	_create_japanese_decorations()

func _generate_tile_texture(tile_type: int) -> Image:
	"""Génère une tuile de terrain 64x64 avec texture détaillée procédurale"""
	var img: Image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	match tile_type:
		0, 5:  # Herbe / Prairie
			# Fond herbe avec variations riches - style japonais (plus doux)
			var base_g: Color = Color(0.32, 0.52, 0.28)
			if tile_type == 5:
				base_g = Color(0.38, 0.58, 0.32)
			img.fill(base_g)
			# Variations de ton (plus nombreuses)
			for _i in range(120):
				var gx: int = rng.randi_range(0, TILE_SIZE - 1)
				var gy: int = rng.randi_range(0, TILE_SIZE - 1)
				var gshade: float = rng.randf_range(-0.05, 0.05)
				var gc: Color = base_g
				gc.r = clamp(gc.r + gshade + rng.randf_range(-0.03, 0.03), 0, 1)
				gc.g = clamp(gc.g + gshade + rng.randf_range(-0.03, 0.08), 0, 1)
				gc.b = clamp(gc.b + gshade, 0, 1)
				img.set_pixel(gx, gy, gc)
			# Touffes d'herbe (plus sombres et nombreuses)
			for _i in range(10):
				var tx: int = rng.randi_range(4, TILE_SIZE - 8)
				var ty: int = rng.randi_range(4, TILE_SIZE - 8)
				for dx in range(-4, 5):
					for dy in range(-4, 5):
						if dx*dx + dy*dy < 14 and rng.randf() < 0.55:
							var tcol: Color = Color(0.22, 0.42, 0.12)
							if rng.randf() < 0.35:
								tcol = Color(0.26, 0.46, 0.16)
							img.set_pixel(clamp(tx + dx, 0, TILE_SIZE - 1), clamp(ty + dy, 0, TILE_SIZE - 1), tcol)
			# Touffes d'herbe claire (contrastes)
			for _i in range(8):
				var tx: int = rng.randi_range(4, TILE_SIZE - 8)
				var ty: int = rng.randi_range(4, TILE_SIZE - 8)
				for dx in range(-3, 4):
					for dy in range(-3, 4):
						if dx*dx + dy*dy < 8 and rng.randf() < 0.45:
							var tcol: Color = Color(0.36, 0.58, 0.26)
							if rng.randf() < 0.3:
								tcol = Color(0.40, 0.64, 0.30)
							img.set_pixel(clamp(tx + dx, 0, TILE_SIZE - 1), clamp(ty + dy, 0, TILE_SIZE - 1), tcol)
			# Petites fleurs colorées (style japonais - sakura)
			if rng.randf() < 0.5:
				for _j in range(rng.randi_range(3, 8)):
					var fx: int = rng.randi_range(8, TILE_SIZE - 10)
					var fy: int = rng.randi_range(8, TILE_SIZE - 10)
					var flower_type: float = rng.randf()
					var fcol: Color = Color(0.95, 0.85, 0.20)
					if flower_type < 0.33:
						fcol = Color(0.92, 0.35, 0.38)  # Rose sakura
					elif flower_type < 0.66:
						fcol = Color(0.82, 0.65, 0.92)  # Lavande
					img.set_pixel(fx, fy, fcol)
					img.set_pixel(fx + 1, fy, fcol)
					img.set_pixel(fx, fy + 1, Color(0.22, 0.44, 0.14))
			# Petits cailloux
			for _i in range(4):
				var cx: int = rng.randi_range(4, TILE_SIZE - 6)
				var cy: int = rng.randi_range(4, TILE_SIZE - 6)
				img.set_pixel(cx, cy, Color(0.55, 0.52, 0.48))
				img.set_pixel(cx + 1, cy, Color(0.60, 0.58, 0.52))
				img.set_pixel(cx, cy + 1, Color(0.50, 0.48, 0.42))
			# Mouches d'herbe fines
			for _i in range(15):
				var lx: int = rng.randi_range(0, TILE_SIZE - 2)
				var ly: int = rng.randi_range(0, TILE_SIZE - 1)
				var lcol: Color = Color(0.16, 0.38, 0.12)
				if rng.randf() < 0.5:
					lcol = Color(0.36, 0.58, 0.22)
				img.set_pixel(lx, ly, lcol)
				img.set_pixel(lx + 1, ly, lcol)
			if rng.randf() < 0.4:
				var px: int = rng.randi_range(8, TILE_SIZE - 12)
				var py: int = rng.randi_range(8, TILE_SIZE - 12)
				for pdx in range(2, 4):
					for pdy in range(2, 3):
						img.set_pixel(px + pdx, py + pdy, Color(0.34, 0.52, 0.22))
		
		1:  # Terre
			img.fill(Color(0.52, 0.40, 0.26))  # Terre plus douce style japonais
			# Variations
			for _i in range(120):
				var tx: int = rng.randi_range(0, TILE_SIZE - 1)
				var ty: int = rng.randi_range(0, TILE_SIZE - 1)
				var dshade: float = rng.randf_range(-0.06, 0.04)
				var dc: Color = Color(0.52 + dshade, 0.40 + dshade * 0.8, 0.26 + dshade * 0.6)
				img.set_pixel(tx, ty, dc)
			# Cailloux
			for _i in range(5):
				var cx: int = rng.randi_range(4, TILE_SIZE - 6)
				var cy: int = rng.randi_range(4, TILE_SIZE - 6)
				var cw: int = rng.randi_range(3, 6)
				var ch: int = rng.randi_range(2, 4)
				var cc: Color = Color(0.48, 0.44, 0.38)
				if rng.randf() < 0.5:
					cc = Color(0.52, 0.48, 0.42)
				for dx in range(cw):
					for dy in range(ch):
						if cx + dx < TILE_SIZE and cy + dy < TILE_SIZE:
							img.set_pixel(cx + dx, cy + dy, cc)
			# Fissures
			for _i in range(3):
				var fx: int = rng.randi_range(0, TILE_SIZE - 1)
				var fy: int = rng.randi_range(0, TILE_SIZE - 1)
				for j in range(rng.randi_range(5, 12)):
					if fx >= 0 and fx < TILE_SIZE and fy >= 0 and fy < TILE_SIZE:
						img.set_pixel(fx, fy, Color(0.40, 0.33, 0.23))
						fx += rng.randi_range(-1, 1)
						fy += rng.randi_range(0, 1)

		2:  # Eau
			img.fill(Color(0.12, 0.38, 0.62))  # Eau plus douce style japonais
			# Reflets plus riches
			for _i in range(30):
				var rx = rng.randi_range(4, TILE_SIZE - 8)
				var ry = rng.randi_range(4, TILE_SIZE - 8)
				for dx in range(4):
					img.set_pixel(rx + dx, ry, Color(0.22, 0.50, 0.78))
					img.set_pixel(rx + dx, ry + 1, Color(0.18, 0.42, 0.70))
			# Profondeur
			for _i in range(40):
				var dx = rng.randi_range(0, TILE_SIZE - 1)
				var dy = rng.randi_range(0, TILE_SIZE - 1)
				img.set_pixel(dx, dy, Color(0.10, 0.34, 0.56))
			# Bulles/écume
			for _i in range(15):
				var bx = rng.randi_range(0, TILE_SIZE - 2)
				var by = rng.randi_range(0, TILE_SIZE - 1)
				img.set_pixel(bx, by, Color(0.20, 0.52, 0.82, 0.6))
				img.set_pixel(bx + 1, by, Color(0.18, 0.46, 0.76, 0.4))
			# Vagues légères
			for x in range(TILE_SIZE):
				for y in range(TILE_SIZE):
					if (x + y) % 7 == 0:
						img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.05))

		3:  # Montagne
			img.fill(Color(0.50, 0.48, 0.44))
			# Pierres
			for _i in range(8):
				var sx = rng.randi_range(4, TILE_SIZE - 10)
				var sy = rng.randi_range(4, TILE_SIZE - 10)
				for dx in range(6):
					for dy in range(6):
						if (dx-3)*(dx-3) + (dy-3)*(dy-3) < 9:
							img.set_pixel(sx+dx, sy+dy, Color(0.60, 0.58, 0.54))
			# Neige sommités
			for x in range(TILE_SIZE):
				for y in range(12):
					if rng.randf() < 0.4 - y*0.025:
						img.set_pixel(x, y, Color(0.88, 0.90, 0.92))
					elif rng.randf() < 0.2 - y*0.015:
						img.set_pixel(x, y, Color(0.75, 0.78, 0.82))
			# Ombres
			for _i in range(50):
				var ox = rng.randi_range(0, TILE_SIZE - 1)
				var oy = rng.randi_range(0, TILE_SIZE - 1)
				img.set_pixel(ox, oy, Color(0.40, 0.38, 0.34))
			# Minerais brillants
			for _i in range(6):
				var mx = rng.randi_range(0, TILE_SIZE - 1)
				var my = rng.randi_range(0, TILE_SIZE - 1)
				img.set_pixel(mx, my, Color(0.65, 0.60, 0.55))
				img.set_pixel(mx + 1, my, Color(0.55, 0.50, 0.45))

		4:  # Forêt
			img.fill(Color(0.10, 0.26, 0.08))
			# Sous-bois plus clair par endroits
			for _i in range(30):
				var sx: int = rng.randi_range(0, TILE_SIZE - 1)
				var sy: int = rng.randi_range(0, TILE_SIZE - 1)
				img.set_pixel(sx, sy, Color(0.12, 0.30, 0.10))
			# Troncs d'arbres
			for _i in range(4):
				var tx: int = rng.randi_range(8, TILE_SIZE - 12)
				var ty: int = rng.randi_range(8, TILE_SIZE - 16)
				for dy in range(rng.randi_range(8, 16)):
					var tw: int = rng.randi_range(3, 5)
					for dx in range(tw):
						img.set_pixel(clamp(tx + dx, 0, TILE_SIZE - 1), clamp(ty + dy, 0, TILE_SIZE - 1), Color(0.32, 0.20, 0.10))
			# Taches de mousse
			for _i in range(8):
				var mx: int = rng.randi_range(4, TILE_SIZE - 6)
				var my: int = rng.randi_range(4, TILE_SIZE - 6)
				for dx in range(-2, 3):
					for dy in range(-2, 3):
						if rng.randf() < 0.5:
							img.set_pixel(clamp(mx + dx, 0, TILE_SIZE - 1), clamp(my + dy, 0, TILE_SIZE - 1), Color(0.14, 0.32, 0.12))
			# Champignons
			if rng.randf() < 0.3:
				var mx: int = rng.randi_range(10, TILE_SIZE - 14)
				var my: int = rng.randi_range(10, TILE_SIZE - 14)
				img.set_pixel(mx, my, Color(0.72, 0.55, 0.35))
				img.set_pixel(mx + 1, my, Color(0.72, 0.55, 0.35))
				img.set_pixel(mx, my + 1, Color(0.55, 0.42, 0.28))
	
	return img

func _preload_terrain_tiles() -> void:
	if _pixel_tiles_loaded:
		return
	var type_names: Array[String] = ["grass", "dirt", "water", "mountain", "forest", "plains"]
	for t in range(type_names.size()):
		var variants: Array[Image] = []
		for v in range(3):
			var path: String = "res://assets/terrain/%s_%d.png" % [type_names[t], v]
			var tex: Texture2D = load(path)
			if tex:
				var img: Image = tex.get_image()
				if img and img.get_size() == Vector2i(TILE_SIZE, TILE_SIZE):
					if img.get_format() != Image.FORMAT_RGBA8:
						img.convert(Image.FORMAT_RGBA8)
					variants.append(img)
		if variants.size() > 0:
			_pixel_tiles[t] = variants
			print("✓ Tuiles pixel art chargées: ", type_names[t], " (", variants.size(), " variantes)")
		else:
			_pixel_tiles[t] = []
			print("⚠ Tuiles pixel art non trouvées: ", type_names[t], " (fallback procédural)")
	_pixel_tiles_loaded = true

func _generate_map_image() -> ImageTexture:
	var w: int = _zone_w
	var h: int = _zone_h
	
	# Grille de terrain (stockée globalement)
	_terrain_move_cost = {
		0: 1,  # Herbe
		1: 2,  # Terre
		2: 999,  # Eau
		3: 3,  # Montagne
		4: 2,  # Forêt
		5: 1,  # Prairie
	}
	_terrain_grid = []
	for x in range(w):
		_terrain_grid.append([])
		for y in range(h):
			_terrain_grid[x].append(0)  # Herbe par défaut
	
	# === 1. ZONES DE TERRE (plus grandes) ===
	for _i in range(3):
		var blob_x: int = rng.randi_range(3, w - 4)
		var blob_y: int = rng.randi_range(3, h - 4)
		var blob_size: int = rng.randi_range(2, 4)
		for dx in range(-blob_size, blob_size + 1):
			for dy in range(-blob_size, blob_size + 1):
				var dist: float = sqrt(dx * dx + dy * dy)
				if dist <= blob_size and rng.randf() < (1.0 - dist / blob_size * 0.6):
					var px: int = blob_x + dx
					var py: int = blob_y + dy
					if px >= 0 and px < w and py >= 0 and py < h:
						_terrain_grid[px][py] = 1
	
	# === 2. LACS (plus grands) ===
	for _i in range(3):
		var lake_x: int = rng.randi_range(4, w - 5)
		var lake_y: int = rng.randi_range(4, h - 5)
		var lake_size: int = rng.randi_range(2, 4)
		for dx in range(-lake_size, lake_size + 1):
			for dy in range(-lake_size, lake_size + 1):
				if sqrt(dx * dx + dy * dy) <= lake_size + rng.randf() * 0.8:
					var px: int = lake_x + dx
					var py: int = lake_y + dy
					if px >= 0 and px < w and py >= 0 and py < h:
						_terrain_grid[px][py] = 2
	
	# === 3. CHAÎNES DE MONTAGNES (plus longues) ===
	for _i in range(2):
		var start_x: int = rng.randi_range(2, w - 3)
		var start_y: int = rng.randi_range(2, h - 3)
		var chain_length: int = rng.randi_range(5, 10)
		var dir_x: int = rng.randi_range(-1, 1)
		var dir_y: int = rng.randi_range(-1, 1)
		if dir_x == 0 and dir_y == 0:
			dir_x = 1
		var cur_x: int = start_x
		var cur_y: int = start_y
		for _j in range(chain_length):
			if cur_x >= 0 and cur_x < w and cur_y >= 0 and cur_y < h:
				_terrain_grid[cur_x][cur_y] = 3
				# Épaissir la chaîne
				for _k in range(rng.randi_range(1, 3)):
					var adj_x: int = cur_x + rng.randi_range(-1, 1)
					var adj_y: int = cur_y + rng.randi_range(-1, 1)
					if adj_x >= 0 and adj_x < w and adj_y >= 0 and adj_y < h:
						_terrain_grid[adj_x][adj_y] = 3
			cur_x += dir_x + rng.randi_range(-1, 1)
			cur_y += dir_y + rng.randi_range(-1, 1)
			cur_x = clamp(cur_x, 0, w - 1)
			cur_y = clamp(cur_y, 0, h - 1)
	
	# === 4. FORÊTS DENSES (beaucoup plus) ===
	for _i in range(8):
		var forest_x: int = rng.randi_range(2, w - 3)
		var forest_y: int = rng.randi_range(2, h - 3)
		var forest_size: int = rng.randi_range(2, 4)
		for dx in range(-forest_size, forest_size + 1):
			for dy in range(-forest_size, forest_size + 1):
				var dist: float = sqrt(dx * dx + dy * dy)
				if dist <= forest_size and rng.randf() < (1.0 - dist / forest_size * 0.5):
					var px: int = forest_x + dx
					var py: int = forest_y + dy
					if px >= 0 and px < w and py >= 0 and py < h and _terrain_grid[px][py] == 0:
						_terrain_grid[px][py] = 4
	
	# === 5. RIVIÈRE (plus sinueuse) ===
	var river_x: int = rng.randi_range(5, w - 6)
	for ry in range(h):
		# Rivière de 1-2 tuiles de large
		_terrain_grid[river_x][ry] = 2
		if rng.randf() < 0.35 and river_x > 0:
			_terrain_grid[river_x - 1][ry] = 2
		if rng.randf() < 0.35 and river_x < w - 1:
			_terrain_grid[river_x + 1][ry] = 2
		river_x += rng.randi_range(-1, 1)
		river_x = clamp(river_x, 3, w - 4)
	
	# === 6. ROUTES (plus fines - 1 tuile) ===
	var road_y: int = h / 2
	for x in range(w):
		if _terrain_grid[x][road_y] != 2:  # Pas sur l'eau
			_terrain_grid[x][road_y] = 1
	
	var road_x: int = w / 2
	for y in range(h):
		if _terrain_grid[road_x][y] != 2:  # Pas sur l'eau
			_terrain_grid[road_x][y] = 1
	
	# === 7. PRAIRIES ===
	for _i in range(6):
		var meadow_x: int = rng.randi_range(2, w - 3)
		var meadow_y: int = rng.randi_range(2, h - 3)
		var meadow_size: int = rng.randi_range(2, 3)
		for dx in range(-meadow_size, meadow_size + 1):
			for dy in range(-meadow_size, meadow_size + 1):
				var dist: float = abs(dx) + abs(dy)
				if dist <= meadow_size and rng.randf() < (1.0 - dist / float(meadow_size + 1) * 0.3):
					var px: int = meadow_x + dx
					var py: int = meadow_y + dy
					if px >= 0 and px < w and py >= 0 and py < h and _terrain_grid[px][py] == 0:
						_terrain_grid[px][py] = 5
	
	# === 8. LISSAGE montagnes isolées ===
	for x in range(1, w - 1):
		for y in range(1, h - 1):
			if _terrain_grid[x][y] == 3:
				var neighbors_mountain: int = 0
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						if _terrain_grid[x + dx][y + dy] == 3:
							neighbors_mountain += 1
				if neighbors_mountain < 2:
					_terrain_grid[x][y] = 0
	
	# === 9. ZONE PROPRE autour du spawn ===
	var hero_tile_x: int = w / 2
	var hero_tile_y: int = h / 2
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var px: int = hero_tile_x + dx
			var py: int = hero_tile_y + dy
			if px >= 0 and px < w and py >= 0 and py < h:
				_terrain_grid[px][py] = 0
	
	# === DESSINER L'IMAGE AVEC TUILES PIXEL ART ===
	var img_width: int = w * TILE_SIZE
	var img_height: int = h * TILE_SIZE
	var map_image: Image = Image.create(img_width, img_height, false, Image.FORMAT_RGBA8)

	_preload_terrain_tiles()

	var tile_rect := Rect2i(0, 0, TILE_SIZE, TILE_SIZE)
	for x in range(w):
		if x % 30 == 0 and x > 0:
			await get_tree().process_frame
		for y in range(h):
			var tile_type: int = _terrain_grid[x][y]
			var variants: Array = _pixel_tiles.get(tile_type, [])
			if variants.size() > 0:
				var idx: int = (x * 7 + y * 13) % variants.size()
				map_image.blit_rect(variants[idx] as Image, tile_rect, Vector2i(x * TILE_SIZE, y * TILE_SIZE))
			else:
				map_image.blit_rect(_generate_tile_texture(tile_type), tile_rect, Vector2i(x * TILE_SIZE, y * TILE_SIZE))

	# === TEXTURATION DES ROUTES (cailloux, traces, bordures) ===
	for x in range(w):
		for y in range(h):
			if _terrain_grid[x][y] != 1:
				continue
			var tx: int = x * TILE_SIZE
			var ty: int = y * TILE_SIZE
			var is_road: bool = false
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx >= 0 and nx < w and ny >= 0 and ny < h and _terrain_grid[nx][ny] == 1:
						is_road = true
						break
				if is_road:
					break

			if is_road:
				for _i in range(6):
					var rx: int = tx + rng.randi_range(2, TILE_SIZE - 4)
					var ry: int = ty + rng.randi_range(2, TILE_SIZE - 4)
					map_image.set_pixel(rx, ry, Color(0.62, 0.52, 0.38))

				if rng.randf() < 0.35:
					var track_x: int = tx + rng.randi_range(8, TILE_SIZE - 16)
					var track_y: int = ty + rng.randi_range(10, TILE_SIZE - 14)
					for ddx in range(rng.randi_range(4, 8)):
						map_image.set_pixel(track_x + ddx, track_y, Color(0.48, 0.38, 0.24))
						map_image.set_pixel(track_x + ddx, track_y + 2, Color(0.48, 0.38, 0.24))

				for dx in range(-1, 2):
					for dy in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var nx: int = x + dx
						var ny: int = y + dy
						if nx >= 0 and nx < w and ny >= 0 and ny < h:
							if _terrain_grid[nx][ny] == 0 or _terrain_grid[nx][ny] == 5:
								var edge_px: int = tx + (TILE_SIZE - 4 if dx == 1 else 4) if dx != 0 else tx + rng.randi_range(4, TILE_SIZE - 4)
								var edge_py: int = ty + (TILE_SIZE - 4 if dy == 1 else 4) if dy != 0 else ty + rng.randi_range(4, TILE_SIZE - 4)
								for _j in range(2):
									var gx: int = edge_px + rng.randi_range(-2, 2)
									var gy: int = edge_py + rng.randi_range(-2, 2)
									map_image.set_pixel(clamp(gx, tx, tx + TILE_SIZE - 1), clamp(gy, ty, ty + TILE_SIZE - 1), Color(0.24, 0.46, 0.14))
	
	await get_tree().process_frame
	
	# === BORDS DE PLAGE (sable) autour de l'eau ===
	for x in range(w):
		for y in range(h):
			if _terrain_grid[x][y] != 2:
				continue
			var tx: int = x * TILE_SIZE
			var ty: int = y * TILE_SIZE
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or nx >= w or ny < 0 or ny >= h or _terrain_grid[nx][ny] == 2:
						continue
					var beach_w: int = 10
					var sand_base: Color = Color(0.72, 0.62, 0.44)
					if dx == -1:
						for px in range(beach_w):
							var alpha: float = 1.0 - (px / float(beach_w))
							for py in range(TILE_SIZE):
								if rng.randf() < alpha * 0.5:
									map_image.set_pixel(tx + px, ty + py, sand_base)
					elif dx == 1:
						for px in range(TILE_SIZE - beach_w, TILE_SIZE):
							var alpha: float = (px - (TILE_SIZE - beach_w)) / float(beach_w)
							for py in range(TILE_SIZE):
								if rng.randf() < alpha * 0.5:
									map_image.set_pixel(tx + px, ty + py, sand_base)
					if dy == -1:
						for py in range(beach_w):
							var alpha: float = 1.0 - (py / float(beach_w))
							for px in range(TILE_SIZE):
								if rng.randf() < alpha * 0.5:
									map_image.set_pixel(tx + px, ty + py, sand_base)
					elif dy == 1:
						for py in range(TILE_SIZE - beach_w, TILE_SIZE):
							var alpha: float = (py - (TILE_SIZE - beach_w)) / float(beach_w)
							for px in range(TILE_SIZE):
								if rng.randf() < alpha * 0.5:
									map_image.set_pixel(tx + px, ty + py, sand_base)
	
	await get_tree().process_frame

	# === DÉTAILS DE SOL (hautes herbes, buissons, souches) ===
	for x in range(w):
		for y in range(h):
			if _terrain_grid[x][y] != 0 and _terrain_grid[x][y] != 5:
				continue
			var tx: int = x * TILE_SIZE
			var ty: int = y * TILE_SIZE

			for _i in range(rng.randi_range(0, 2)):
				var hx: int = tx + rng.randi_range(4, TILE_SIZE - 8)
				var hy: int = ty + rng.randi_range(4, TILE_SIZE - 8)
				for dy in range(rng.randi_range(2, 3)):
					for dx in range(rng.randi_range(2, 3)):
						map_image.set_pixel(hx + dx, hy + dy, Color(0.18, 0.40, 0.10, 0.9))

			if rng.randf() < 0.04:
				var sx: int = tx + rng.randi_range(12, TILE_SIZE - 16)
				var sy: int = ty + rng.randi_range(12, TILE_SIZE - 16)
				for dy in range(3):
					for dx in range(4):
						map_image.set_pixel(sx + dx, sy + dy, Color(0.38, 0.24, 0.12))
				map_image.set_pixel(sx + 1, sy + 1, Color(0.50, 0.35, 0.18))
				map_image.set_pixel(sx + 2, sy + 1, Color(0.50, 0.35, 0.18))
				map_image.set_pixel(sx + 1, sy + 2, Color(0.42, 0.28, 0.14))
				map_image.set_pixel(sx + 2, sy + 2, Color(0.42, 0.28, 0.14))

			if rng.randf() < 0.06:
				var bx: int = tx + rng.randi_range(8, TILE_SIZE - 12)
				var by: int = ty + rng.randi_range(8, TILE_SIZE - 12)
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						if dx*dx + dy*dy <= 5 and rng.randf() < 0.7:
							map_image.set_pixel(bx + dx, by + dy, Color(0.20, 0.44, 0.12) if rng.randf() < 0.5 else Color(0.26, 0.50, 0.16))

			if rng.randf() < 0.25:
				for _j in range(rng.randi_range(2, 4)):
					var fx: int = tx + rng.randi_range(8, TILE_SIZE - 12)
					var fy: int = ty + rng.randi_range(8, TILE_SIZE - 12)
					var fcol: Color = Color(0.85, 0.20, 0.20)
					var flower_type: float = rng.randf()
					if flower_type < 0.33:
						fcol = Color(0.85, 0.78, 0.20)
					elif flower_type < 0.66:
						fcol = Color(0.72, 0.55, 0.82)
					else:
						fcol = Color(0.20, 0.60, 0.85)
					map_image.set_pixel(fx, fy, fcol)
					map_image.set_pixel(fx + 1, fy, fcol)
					map_image.set_pixel(fx, fy + 1, Color(0.20, 0.42, 0.12))

			if rng.randf() < 0.15:
				for _j in range(rng.randi_range(2, 3)):
					var cx: int = tx + rng.randi_range(4, TILE_SIZE - 6)
					var cy: int = ty + rng.randi_range(4, TILE_SIZE - 6)
					map_image.set_pixel(cx, cy, Color(0.55, 0.52, 0.48))
	
	await get_tree().process_frame
	
	print("✓ Terrain pixel art: ", img_width, "x", img_height, " avec tuiles HoMM3, routes texturées, plages et détails de sol")
	return ImageTexture.create_from_image(map_image)

func _create_decorations() -> void:
	# Créer des arbres et rochers sur la carte pour la rendre plus vivante
	
	# Les arbres viennent de assets/external/arbre/*.png (sprite sheets avec 2 arbres par image)
	# Le fallback procédural est supprimé — seules les textures PNG sont utilisées

	# === NOUVEAU SYSTÈME ARBRES : images individuelles avec 2 arbres par image ===
	# Chaque image fait 224x128 → 2 arbres de 112x128 chacun
	var tree_files: Array[String] = [
		"res://assets/external/arbre/autumn.png",
		"res://assets/external/arbre/autumn 2.png",
		"res://assets/external/arbre/autumn 3.png",
		"res://assets/external/arbre/blue trees.png",
		"res://assets/external/arbre/brown trees.png",
		"res://assets/external/arbre/brown trees 2.png",
		"res://assets/external/arbre/cherry_blossom_trees.png",
		"res://assets/external/arbre/green trees.png",
		"res://assets/external/arbre/yellow.png",
		"res://assets/external/arbre/yellow 2.png"
	]
	# Charger toutes les textures disponibles
	var tree_textures: Array[Texture2D] = []
	for f in tree_files:
		var tex: Texture2D = load(f)
		if tex != null:
			tree_textures.append(tex)
	# === CRÉER DES VRAIES FORÊTS ET ARBRES SOLITAIRES ===
	# Grille pour tracker les positions occupées (éviter les superpositions)
	var occupied: Dictionary = {}
	
	for i in range(TREE_COUNT):
		var center_x: int = rng.randi_range(2, _zone_w - 3)
		var center_y: int = rng.randi_range(2, _zone_h - 3)
		
		# Déterminer le type d'emplacement
		var density_roll: float = rng.randf()
		var is_forest: bool = density_roll < 0.28      # 28% = VRAIE FORÊT (8-16 arbres sur 3×3 tuiles)
		var is_group: bool = density_roll < 0.55 and not is_forest  # 27% = Petit groupe (2-4 arbres sur 2×2)
		# 45% = Arbre solitaire
		
		# Choisir UNE image d'arbre pour toute la forêt/groupe
		var tex_idx: int = rng.randi_range(0, tree_textures.size() - 1)
		var base_tex: Texture2D = tree_textures[tex_idx]
		var tex_size: Vector2 = base_tex.get_size()
		var half_w: float = tex_size.x / 2.0
		var full_h: float = tex_size.y
		
		# Régions gauche et droite
		var region_left: Rect2 = Rect2(0, 0, half_w, full_h)
		var region_right: Rect2 = Rect2(half_w, 0, half_w, full_h)
		
		# Taille cible d'un arbre en jeu
		var target_h: float = rng.randf_range(68.0, 88.0)
		var base_scale: float = target_h / full_h
		
		if is_forest:
			# === VRAIE FORÊT : 8-16 arbres sur 3×3 tuiles ===
			var forest_size: int = rng.randi_range(8, 16)
			var placed: int = 0
			var attempts: int = 0
			
			while placed < forest_size and attempts < 50:
				attempts += 1
				var dx: int = rng.randi_range(-1, 1)
				var dy: int = rng.randi_range(-1, 1)
				var tx: int = center_x + dx
				var ty: int = center_y + dy
				var key: String = str(tx) + "," + str(ty)
				
				if occupied.has(key):
					continue
				occupied[key] = true
				
				var world_x: float = (tx * TILE_SIZE) + TILE_SIZE / 2
				var world_y: float = (ty * TILE_SIZE) + TILE_SIZE / 2
				
				var tree_node: Node2D = Node2D.new()
				tree_node.name = "Tree_F" + str(i) + "_" + str(placed)
				tree_node.position = Vector2(world_x, world_y)
				add_child(tree_node)
				
				# Choisir gauche ou droite aléatoirement
				var atlas: AtlasTexture = AtlasTexture.new()
				atlas.atlas = base_tex
				atlas.region = region_left if rng.randf() < 0.5 else region_right
				
				var tree_sprite: Sprite2D = Sprite2D.new()
				tree_sprite.texture = atlas
				var svar: float = rng.randf_range(0.82, 1.12)
				tree_sprite.scale = Vector2(base_scale * svar, base_scale * svar)
				
				# Position légèrement aléatoire dans la tuile
				var offset_x: float = rng.randf_range(-18.0, 18.0)
				var offset_y: float = rng.randf_range(-10.0, 8.0)
				tree_sprite.position = Vector2(offset_x, offset_y - target_h * 0.35)
				tree_sprite.set_z_index(int(offset_y))
				tree_node.add_child(tree_sprite)
				
				_sg._create_elliptical_shadow(tree_node, 24, 8, 6, 0.22)
				_decorations.append(tree_node)
				placed += 1
			
			if placed >= 3:
				# Ombre de forêt plus grande sous le groupe
				var forest_shadow: Node2D = Node2D.new()
				forest_shadow.position = Vector2(center_x * TILE_SIZE + TILE_SIZE / 2, center_y * TILE_SIZE + TILE_SIZE / 2)
				add_child(forest_shadow)
				_sg._create_elliptical_shadow(forest_shadow, 90, 32, 14, 0.12)
				_decorations.append(forest_shadow)
		
		elif is_group:
			# === PETIT GROUPE : 2-4 arbres sur 2×2 tuiles ===
			var group_size: int = rng.randi_range(2, 4)
			var placed: int = 0
			var attempts: int = 0
			
			while placed < group_size and attempts < 20:
				attempts += 1
				var dx: int = rng.randi_range(0, 1)
				var dy: int = rng.randi_range(0, 1)
				var tx: int = center_x + dx
				var ty: int = center_y + dy
				var key: String = str(tx) + "," + str(ty)
				
				if occupied.has(key):
					continue
				occupied[key] = true
				
				var world_x: float = (tx * TILE_SIZE) + TILE_SIZE / 2
				var world_y: float = (ty * TILE_SIZE) + TILE_SIZE / 2
				
				var tree_node: Node2D = Node2D.new()
				tree_node.name = "Tree_G" + str(i) + "_" + str(placed)
				tree_node.position = Vector2(world_x, world_y)
				add_child(tree_node)
				
				var atlas: AtlasTexture = AtlasTexture.new()
				atlas.atlas = base_tex
				atlas.region = region_left if rng.randf() < 0.5 else region_right
				
				var tree_sprite: Sprite2D = Sprite2D.new()
				tree_sprite.texture = atlas
				var svar: float = rng.randf_range(0.85, 1.15)
				tree_sprite.scale = Vector2(base_scale * svar, base_scale * svar)
				tree_sprite.position = Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-8.0, 4.0) - target_h * 0.35)
				tree_node.add_child(tree_sprite)
				
				_sg._create_elliptical_shadow(tree_node, 26, 9, 7, 0.24)
				_decorations.append(tree_node)
				placed += 1
		
		else:
			# === ARBRE SOLITAIRE ===
			var key: String = str(center_x) + "," + str(center_y)
			if not occupied.has(key):
				occupied[key] = true
				
				var world_x: float = (center_x * TILE_SIZE) + TILE_SIZE / 2
				var world_y: float = (center_y * TILE_SIZE) + TILE_SIZE / 2
				
				var tree_node: Node2D = Node2D.new()
				tree_node.name = "Tree_S" + str(i)
				tree_node.position = Vector2(world_x, world_y)
				add_child(tree_node)
				
				var atlas: AtlasTexture = AtlasTexture.new()
				atlas.atlas = base_tex
				atlas.region = region_left if rng.randf() < 0.5 else region_right
				
				var tree_sprite: Sprite2D = Sprite2D.new()
				tree_sprite.texture = atlas
				var svar: float = rng.randf_range(0.88, 1.18)
				tree_sprite.scale = Vector2(base_scale * svar, base_scale * svar)
				tree_sprite.position = Vector2(0, -target_h * 0.35)
				tree_node.add_child(tree_sprite)
				
				_sg._create_elliptical_shadow(tree_node, 28, 10, 8, 0.26)
				_decorations.append(tree_node)

	for i in range(ROCK_COUNT):
		var rock_x: int = rng.randi_range(1, _zone_w - 2)
		var rock_y: int = rng.randi_range(1, _zone_h - 2)
		var world_x: float = (rock_x * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (rock_y * TILE_SIZE) + TILE_SIZE / 2
		var rock_pos: Vector2 = Vector2(world_x, world_y)
		
		# Créer le rocher
		var rock_node: Node2D = Node2D.new()
		rock_node.name = "Rock_" + str(i)
		rock_node.position = rock_pos
		add_child(rock_node)
		
		# Sprite procédural rocher
		var rock_sprite: Sprite2D = Sprite2D.new()
		rock_sprite.texture = _sg._generate_sprite("rock", 96, rock_x * 1000 + rock_y)
		rock_sprite.position = Vector2(0, -24)
		rock_node.add_child(rock_sprite)
		_apply_outline_shader(rock_sprite, Color(0, 0, 0, 0.65), 1.0, Color(0, 0, 0, 0), 0.0, 0.0)

		# Ombre elliptique sous le rocher
		_sg._create_elliptical_shadow(rock_node, 28, 10, 8, 0.30)
		
		_decorations.append(rock_node)
	
	# Créer des tours abandonnées (dans la zone colorée 16×9)
	for i in range(TOWER_COUNT):
		var tower_x: int = rng.randi_range(2, _zone_w - 3)
		var tower_y: int = rng.randi_range(2, _zone_h - 3)
		var world_x: float = (tower_x * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (tower_y * TILE_SIZE) + TILE_SIZE / 2
		var tower_pos: Vector2 = Vector2(world_x, world_y)
		
		# Créer la tour
		var tower_node: Node2D = Node2D.new()
		tower_node.name = "Tower_" + str(i)
		tower_node.position = tower_pos
		add_child(tower_node)
		
		# Sprite procédural tour
		var tower_sprite: Sprite2D = Sprite2D.new()
		tower_sprite.texture = _sg._generate_sprite("tower", 96, tower_x * 1000 + tower_y)
		tower_sprite.position = Vector2(0, -24)
		tower_node.add_child(tower_sprite)
		_apply_outline_shader(tower_sprite, Color(0, 0, 0, 0.7), 1.0, Color(0, 0, 0, 0), 0.0, 0.0)
		
		# Ombre elliptique sous la tour
		_sg._create_elliptical_shadow(tower_node, 48, 14, 16, 0.35)
		
		_decorations.append(tower_node)
	
	print("✓ ", TREE_COUNT, " arbres, ", ROCK_COUNT, " rochers et ", TOWER_COUNT, " tours créés")

func _extract_building_texture(sheet_texture: Texture2D, index: int) -> Texture2D:
	var sheet_img: Image = sheet_texture.get_image()
	
	# Bounding boxes précises des 12 sprites dans bat.png (1024x1024)
	# Déterminées par analyse pixel-parfaite des zones non-transparentes
	const BOXES: Array = [
		Rect2i(59, 32, 394, 251),    # 0: Grand bâtiment principal (château)
		Rect2i(511, 46, 162, 138),   # 1: Petit bâtiment/tour
		Rect2i(767, 47, 162, 202),   # 2: Bâtiment moyen
		Rect2i(528, 256, 128, 188),  # 3: Bâtiment
		Rect2i(766, 268, 164, 173),  # 4: Bâtiment
		Rect2i(259, 320, 208, 346),  # 5: Grand bâtiment
		Rect2i(69, 347, 144, 189),   # 6: Bâtiment
		Rect2i(529, 478, 126, 188),  # 7: Bâtiment
		Rect2i(767, 492, 162, 202),  # 8: Bâtiment
		Rect2i(34, 693, 220, 107),   # 9: Bannière/décoration longue
		Rect2i(553, 714, 78, 150),   # 10: Lanterne/statue étroite
		Rect2i(128, 897, 256, 85),   # 11: Bannière large
	]
	
	var i: int = clampi(index, 0, BOXES.size() - 1)
	var box: Rect2i = BOXES[i]
	
	var cropped: Image = Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
	cropped.blit_rect(sheet_img, box, Vector2i.ZERO)
	return ImageTexture.create_from_image(cropped)

func _create_building_shadow(parent: Node2D, width: float, height: float, alpha: float = 0.25) -> void:
	"""Ajoute une ombre portée elliptique sous un bâtiment."""
	var shadow: ColorRect = ColorRect.new()
	shadow.size = Vector2(width, height)
	shadow.position = Vector2(-width * 0.5, -height * 0.5)
	shadow.color = Color(0, 0, 0, alpha)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style = StyleBoxFlat.new()
	shadow_style.bg_color = Color(0, 0, 0, alpha)
	shadow_style.corner_radius_top_left = int(height * 0.5)
	shadow_style.corner_radius_top_right = int(height * 0.5)
	shadow_style.corner_radius_bottom_left = int(height * 0.5)
	shadow_style.corner_radius_bottom_right = int(height * 0.5)
	shadow.add_theme_stylebox_override("panel", shadow_style)
	shadow.set_z_index(-1)
	parent.add_child(shadow)

func _create_japanese_decorations() -> void:
	"""Crée des éléments décoratifs japonais : torii, cerisiers, lanternes, temples"""
	
	# Charger le sprite sheet de bâtiments japonais
	var japanese_sheet: Texture2D = load("res://assets/bat.png")
	
	# Nombre d'éléments japonais
	const TORII_COUNT: int = 8
	const SAKURA_COUNT: int = 6
	const LANTERN_COUNT: int = 24
	const SHRINE_COUNT: int = 5
	const BUILDING_COUNT: int = 12
	
		# === BÂTIMENTS JAPONAIS DU SPRITE SHEET ===
	if japanese_sheet != null:
		var _excluded_terrains: Array = [2, 3]  # éviter eau et marécage
		for i in range(BUILDING_COUNT):
			var tx: int
			var ty: int
			var attempts: int = 0
			while attempts < 20:
				tx = rng.randi_range(3, _zone_w - 4)
				ty = rng.randi_range(3, _zone_h - 4)
				if tx < _terrain_grid.size() and ty < _terrain_grid[tx].size():
					if not _excluded_terrains.has(_terrain_grid[tx][ty]):
						break
				attempts += 1
			var world_x: float = (tx * TILE_SIZE) + TILE_SIZE / 2
			var world_y: float = (ty * TILE_SIZE) + TILE_SIZE / 2
			
			var building_node: Node2D = Node2D.new()
			building_node.name = "JapaneseBuilding_" + str(i)
			building_node.position = Vector2(world_x, world_y)
			add_child(building_node)
			
			# Ombre portée elliptique
			_create_building_shadow(building_node, 80, 20, 0.20)
			
			# Extraction pixel-parfaite du sprite
			var building_texture: Texture2D = _extract_building_texture(japanese_sheet, i)
			var building_sprite: Sprite2D = Sprite2D.new()
			building_sprite.texture = building_texture
			building_sprite.scale = Vector2(1.5, 1.5)
			building_sprite.position = Vector2(0, -32)
			building_node.add_child(building_sprite)
			_apply_outline_shader(building_sprite, Color(0, 0, 0, 0.75), 1.0, Color(1.0, 0.95, 0.7, 0.08), 3.0, 0.06)
			
			building_node.set_z_index(-7)
			_japanese_buildings.append(building_node)
			_japanese_building_data.append({
				"node": building_node,
				"sprite": building_sprite,
				"base_y": building_sprite.position.y
			})
		
		print("✓ Bâtiments japonais créés : ", BUILDING_COUNT)
	else:
		print("⚠ Impossible de charger bat.png")
	
	# === TORII GATES ===
	for i in range(TORII_COUNT):
		var tx: int = rng.randi_range(3, _zone_w - 4)
		var ty: int = rng.randi_range(3, _zone_h - 4)
		var world_x: float = (tx * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (ty * TILE_SIZE) + TILE_SIZE / 2
		
		var torii_node: Node2D = Node2D.new()
		torii_node.name = "Torii_" + str(i)
		torii_node.position = Vector2(world_x, world_y)
		add_child(torii_node)
		
		_create_building_shadow(torii_node, 80, 16, 0.22)
		
		var torii_sprite: Sprite2D = Sprite2D.new()
		torii_sprite.texture = _sg._generate_sprite("torii", 96, i * 7243)
		torii_sprite.position = Vector2(0, -24)
		torii_node.add_child(torii_sprite)
		
		torii_node.set_z_index(-5)
	
	# === CERISIERS (SAKURA) ===
	for i in range(SAKURA_COUNT):
		var tx: int = rng.randi_range(2, _zone_w - 3)
		var ty: int = rng.randi_range(2, _zone_h - 3)
		var world_x: float = (tx * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (ty * TILE_SIZE) + TILE_SIZE / 2
		
		var sakura_node: Node2D = Node2D.new()
		sakura_node.name = "Sakura_" + str(i)
		sakura_node.position = Vector2(world_x, world_y)
		add_child(sakura_node)
		
		_create_building_shadow(sakura_node, 52, 14, 0.20)
		
		var sakura_sprite: Sprite2D = Sprite2D.new()
		sakura_sprite.texture = _sg._generate_sprite("sakura", 64, i * 5557)
		sakura_sprite.position = Vector2(0, -20)
		sakura_node.add_child(sakura_sprite)
		
		sakura_node.set_z_index(-3)
	
	# === LANTERNES DE PIERRE ===
	for i in range(LANTERN_COUNT):
		var tx: int = rng.randi_range(3, _zone_w - 4)
		var ty: int = rng.randi_range(3, _zone_h - 4)
		var world_x: float = (tx * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (ty * TILE_SIZE) + TILE_SIZE / 2
		
		var lantern_node: Node2D = Node2D.new()
		lantern_node.name = "Lantern_" + str(i)
		lantern_node.position = Vector2(world_x, world_y)
		add_child(lantern_node)
		
		_create_building_shadow(lantern_node, 28, 8, 0.20)
		
		var lantern_sprite: Sprite2D = Sprite2D.new()
		lantern_sprite.texture = _sg._generate_sprite("lantern", 64, i * 7919)
		lantern_sprite.position = Vector2(0, -18)
		lantern_node.add_child(lantern_sprite)
		
		# Halo lumineux (ambiance)
		var glow_img: Image = Image.create(40, 40, false, Image.FORMAT_RGBA8)
		glow_img.fill(Color(0, 0, 0, 0))
		for gx in range(40):
			for gy in range(40):
				var gdist: float = sqrt((gx - 20)**2 + (gy - 20)**2)
				if gdist < 18:
					var galpha: float = (1.0 - gdist / 18.0) * 0.20
					glow_img.set_pixel(gx, gy, Color(1.0, 0.9, 0.5, galpha))
		var glow: Sprite2D = Sprite2D.new()
		glow.texture = ImageTexture.create_from_image(glow_img)
		glow.position = Vector2(0, -14)
		glow.name = "LanternGlow"
		glow.set_z_index(-1)
		lantern_node.add_child(glow)
		_lantern_glows.append(glow)
		
		lantern_node.set_z_index(-4)
	
	# === PETITS SANCTUAIRES ===
	for i in range(SHRINE_COUNT):
		var tx: int = rng.randi_range(4, _zone_w - 5)
		var ty: int = rng.randi_range(4, _zone_h - 5)
		var world_x: float = (tx * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (ty * TILE_SIZE) + TILE_SIZE / 2
		
		var shrine_node: Node2D = Node2D.new()
		shrine_node.name = "Shrine_" + str(i)
		shrine_node.position = Vector2(world_x, world_y)
		add_child(shrine_node)
		
		_create_building_shadow(shrine_node, 48, 12, 0.20)
		
		var shrine_sprite: Sprite2D = Sprite2D.new()
		shrine_sprite.texture = _sg._generate_sprite("shrine", 64, i * 3571)
		shrine_sprite.position = Vector2(0, -16)
		shrine_node.add_child(shrine_sprite)
		
		shrine_node.set_z_index(-6)
	
	print("✓ Éléments japonais créés : ", TORII_COUNT, " torii, ", SAKURA_COUNT, " cerisiers, ", LANTERN_COUNT, " lanternes, ", SHRINE_COUNT, " sanctuaires")

	# === LUEUR DES BÂTIMENTS (ambiance lumineuse) ===
	# Ajoute un halo doux autour de chaque bâtiment japonais
	for building_node in _japanese_buildings:
		var bg_img: Image = Image.create(60, 60, false, Image.FORMAT_RGBA8)
		bg_img.fill(Color(0, 0, 0, 0))
		for gx in range(60):
			for gy in range(60):
				var gdist: float = sqrt((gx - 30)**2 + (gy - 30)**2)
				if gdist < 25:
					var galpha: float = (1.0 - gdist / 25.0) * 0.06
					bg_img.set_pixel(gx, gy, Color(1.0, 0.95, 0.7, galpha))
		var building_glow: Sprite2D = Sprite2D.new()
		building_glow.texture = ImageTexture.create_from_image(bg_img)
		building_glow.position = Vector2(0, -20)
		building_glow.name = "BuildingGlow"
		building_node.add_child(building_glow)
	
	# === LUCIOLES ===
	_create_fireflies()
	
	# === PÉTALES DE CERISIER ===
	_create_cherry_blossom_particles()
	
	# === PARTICULES AMBIANTES (poussières lumineuses) ===
	_create_light_motes()

func _create_cherry_blossom_particles() -> void:
	"""Crée des particules de pétales de cerisier qui tombent - version améliorée"""
	var view_w := _world_w * TILE_SIZE
	var view_h := _world_h * TILE_SIZE
	
	for i in range(24):
		var petal: ColorRect = ColorRect.new()
		petal.name = "Petal_" + str(i)
		var petal_size := rng.randf_range(5, 9)
		petal.size = Vector2(petal_size, petal_size * rng.randf_range(1.3, 2.0))
		var pink_shade := rng.randf_range(0.5, 0.9)
		petal.color = Color(0.95, pink_shade, pink_shade * 0.75, rng.randf_range(0.3, 0.6))
		
		var start_x: float = rng.randf_range(0, view_w)
		var start_y: float = rng.randf_range(-20, view_h)
		petal.position = Vector2(start_x, start_y)
		petal.rotation = rng.randf() * TAU
		petal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		add_child(petal)
		_petals.append({
			"node": petal,
			"speed_y": rng.randf_range(12, 28),
			"speed_x": rng.randf_range(3, 10) * (1 if rng.randf() > 0.3 else -1),
			"rotation": petal.rotation,
			"rotation_speed": rng.randf_range(0.3, 0.8) * (1 if rng.randf() > 0.5 else -1),
			"phase": rng.randf() * TAU,
			"offset": rng.randf() * TAU,
		})
	
	print("✓ Particules de pétales de cerisier : 24")

func _create_fireflies() -> void:
	"""Crée des lucioles près des bâtiments et villes pour l'ambiance"""
	var firefly_positions: Array = []
	for b in _japanese_buildings:
		firefly_positions.append(b.position)
	for c in _cities:
		firefly_positions.append(c)
	for _i in range(12):
		if firefly_positions.is_empty():
			break
		var origin: Vector2 = firefly_positions[rng.randi() % firefly_positions.size()]
		var firefly: ColorRect = ColorRect.new()
		firefly.name = "Firefly_" + str(_i)
		firefly.size = Vector2(3, 3)
		firefly.color = Color(1.0, 0.95, 0.6)
		firefly.position = origin + Vector2(rng.randf_range(-80, 80), rng.randf_range(-60, 40))
		firefly.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(firefly)
		_fireflies.append({
			"node": firefly,
			"base": firefly.position,
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.3, 0.8),
			"radius": rng.randf_range(8, 24),
			"blink_speed": rng.randf_range(2.0, 5.0),
		})
	print("✓ Lucioles créées : ", _fireflies.size())

func _create_light_motes() -> void:
	var view_w := _world_w * TILE_SIZE
	var view_h := _world_h * TILE_SIZE
	for i in range(8):
		var mote := ColorRect.new()
		mote.name = "LightMote_%d" % i
		mote.size = Vector2(3, 3)
		mote.color = Color(1.0, 0.95, 0.8, 0.15)
		mote.position = Vector2(randf_range(0, view_w), randf_range(0, view_h))
		mote.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(mote)
		_light_motes.append({
			"node": mote,
			"base": mote.position,
			"speed": randf_range(3, 8),
			"drift": randf_range(0.2, 0.6),
			"phase": randf() * TAU,
			"size": randf_range(2, 5),
		})

func _create_mountain_sprites() -> void:
	# Créer des sprites de montagnes sur les tuiles montagne (type 3)
	# Les montagnes débordent sur les tuiles voisines pour un effet imposant

	# Collecter toutes les positions montagne
	var mountain_positions: Array[Vector2] = []
	for x in range(_zone_w):
		for y in range(_zone_h):
			if _terrain_grid[x][y] == 3:
				mountain_positions.append(Vector2(x, y))
	
	# Pour chaque zone de montagne, créer un sprite imposant
	for mpos in mountain_positions:
		var mx: int = int(mpos.x)
		var my: int = int(mpos.y)
		var world_x: float = (mx * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (my * TILE_SIZE) + TILE_SIZE / 2
		
		var mountain_node: Node2D = Node2D.new()
		mountain_node.name = "Mountain_" + str(mx) + "_" + str(my)
		mountain_node.position = Vector2(world_x, world_y)
		mountain_node.set_z_index(2)  # Au-dessus du terrain
		add_child(mountain_node)
		
		# Générer sprite de montagne procédural
		var m_img: Image = Image.create(96, 80, false, Image.FORMAT_RGBA8)
		m_img.fill(Color(0, 0, 0, 0))  # Transparent
		
		# Base rocheuse (forme trapézoïdale)
		var base_w: int = 72
		var base_h: int = 24
		var peak_h: int = 44
		for py in range(base_h + peak_h):
			var y_ratio: float = float(py) / float(base_h + peak_h)
			var current_w: float = base_w * (1.0 - y_ratio * 0.6)  # Rétrécit vers le haut
			var center_x: int = 48
			var start_x: int = int(center_x - current_w / 2.0)
			var end_x: int = int(center_x + current_w / 2.0)
			for px in range(start_x, end_x):
				if px >= 0 and px < 96 and py >= 0 and py < 80:
					# Couleur avec variation
					var rock_col: Color = Color(0.50, 0.48, 0.44)
					if rng.randf() < 0.3:
						rock_col = Color(0.56, 0.54, 0.50)
					if rng.randf() < 0.15:
						rock_col = Color(0.44, 0.42, 0.38)
					# Plus clair en haut (neige)
					if y_ratio < 0.25 and rng.randf() < 0.6:
						rock_col = Color(0.78, 0.76, 0.74)
					m_img.set_pixel(px, py, rock_col)
		
		# Strates horizontales (bandes de roche)
		for sy in [20, 32, 44, 56]:
			for px in range(12, 84):
				if sy < 80 and m_img.get_pixel(px, sy).a > 0.1:
					var streak: Color = Color(0.40, 0.38, 0.34)
					if rng.randf() < 0.5:
						streak = Color(0.60, 0.58, 0.54)
					m_img.set_pixel(px, sy + rng.randi_range(-1, 1), streak)
		
		# Fissures verticales
		for _i in range(2):
			var fx: int = rng.randi_range(24, 72)
			for fy in range(rng.randi_range(10, 30)):
				if fy < 80 and m_img.get_pixel(fx, fy).a > 0.1:
					m_img.set_pixel(fx + rng.randi_range(-1, 1), fy, Color(0.28, 0.26, 0.22))
		
		# Créer la texture
		var m_tex: ImageTexture = ImageTexture.create_from_image(m_img)
		var m_sprite: Sprite2D = Sprite2D.new()
		m_sprite.texture = m_tex
		m_sprite.position = Vector2(0, -28)
		mountain_node.add_child(m_sprite)
		_apply_outline_shader(m_sprite, Color(0, 0, 0, 0.65), 1.0, Color(0, 0, 0, 0), 0.0, 0.0)
		
		# Ombre sous la montagne
		_sg._create_elliptical_shadow(mountain_node, 34, 10, 8, 0.30)
		
		_decorations.append(mountain_node)

func _create_bridges() -> void:
	# Détecter où les routes (type 1) croisent l'eau (type 2) et placer des ponts

	for x in range(1, _zone_w - 1):
		for y in range(1, _zone_h - 1):
			if _terrain_grid[x][y] == 2:  # Eau
				# Vérifier si une route est de chaque côté (horizontal ou vertical)
				var has_left_road: bool = _terrain_grid[x - 1][y] == 1
				var has_right_road: bool = _terrain_grid[x + 1][y] == 1
				var has_top_road: bool = _terrain_grid[x][y - 1] == 1
				var has_bottom_road: bool = _terrain_grid[x][y + 1] == 1
				
				var world_x: float = (x * TILE_SIZE) + TILE_SIZE / 2
				var world_y: float = (y * TILE_SIZE) + TILE_SIZE / 2
				
				if has_left_road and has_right_road:
					# Pont horizontal — rendre la tuile praticable
					_terrain_grid[x][y] = 1
					var bridge_node: Node2D = Node2D.new()
					bridge_node.name = "Bridge_H_" + str(x) + "_" + str(y)
					bridge_node.position = Vector2(world_x, world_y)
					bridge_node.set_z_index(3)
					add_child(bridge_node)
					
					var b_img: Image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
					b_img.fill(Color(0, 0, 0, 0))
					
					# Planches de bois
					for by in range(20, 44):
						for bx in range(2, TILE_SIZE - 2):
							var plank: Color = Color(0.55, 0.40, 0.22)
							if (bx % 8) < 2:
								plank = Color(0.45, 0.32, 0.16)  # Joint
							b_img.set_pixel(bx, by, plank)
					
					# Garde-corps
					for bx in range(2, TILE_SIZE - 2):
						b_img.set_pixel(bx, 18, Color(0.35, 0.22, 0.12))
						b_img.set_pixel(bx, 46, Color(0.35, 0.22, 0.12))
					# Poteaux
					for bx in [6, 18, 30, 42, 54]:
						for py in range(14, 22):
							b_img.set_pixel(bx, py, Color(0.30, 0.18, 0.10))
						for py in range(42, 50):
							b_img.set_pixel(bx, py, Color(0.30, 0.18, 0.10))
					
					var b_tex: ImageTexture = ImageTexture.create_from_image(b_img)
					var b_sprite: Sprite2D = Sprite2D.new()
					b_sprite.texture = b_tex
					bridge_node.add_child(b_sprite)
					_apply_outline_shader(b_sprite, Color(0, 0, 0, 0.55), 1.0, Color(0, 0, 0, 0), 0.0, 0.0)
					_decorations.append(bridge_node)
				
				elif has_top_road and has_bottom_road:
					# Pont vertical — rendre la tuile praticable
					_terrain_grid[x][y] = 1
					var bridge_node: Node2D = Node2D.new()
					bridge_node.name = "Bridge_V_" + str(x) + "_" + str(y)
					bridge_node.position = Vector2(world_x, world_y)
					bridge_node.set_z_index(3)
					add_child(bridge_node)
					
					var b_img: Image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
					b_img.fill(Color(0, 0, 0, 0))
					
					# Planches de bois (rotation 90° = x et y inversés)
					for bx in range(20, 44):
						for by in range(2, TILE_SIZE - 2):
							var plank: Color = Color(0.55, 0.40, 0.22)
							if (by % 8) < 2:
								plank = Color(0.45, 0.32, 0.16)
							b_img.set_pixel(bx, by, plank)
					
					# Garde-corps verticaux
					for by in range(2, TILE_SIZE - 2):
						b_img.set_pixel(18, by, Color(0.35, 0.22, 0.12))
						b_img.set_pixel(46, by, Color(0.35, 0.22, 0.12))
					
					var b_tex: ImageTexture = ImageTexture.create_from_image(b_img)
					var b_sprite: Sprite2D = Sprite2D.new()
					b_sprite.texture = b_tex
					bridge_node.add_child(b_sprite)
					_apply_outline_shader(b_sprite, Color(0, 0, 0, 0.55), 1.0, Color(0, 0, 0, 0), 0.0, 0.0)
					_decorations.append(bridge_node)
	
	# Créer les coffres au trésor
	_create_treasures()

func _create_sky_background() -> void:
	var sky_tex := ImageTexture.create_from_image(_generate_sky_image())
	_sky_sprite = Sprite2D.new()
	_sky_sprite.name = "SkyBackground"
	_sky_sprite.texture = sky_tex
	_sky_sprite.z_index = -20
	_sky_sprite.position = Vector2(_world_w * TILE_SIZE / 2, _world_h * TILE_SIZE / 2)
	var sky_shader := load("res://shaders/sky.gdshader")
	if sky_shader:
		var mat := ShaderMaterial.new()
		mat.shader = sky_shader
		_sky_sprite.material = mat
	add_child(_sky_sprite)

func _setup_visual_enhancements() -> void:
	VisualEnhancer.add_world_environment(self)
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "PostProcessLayer"
	canvas_layer.layer = 127
	add_child(canvas_layer)
	_vignette_overlay = VisualEnhancer.add_vignette_overlay(canvas_layer)

func _apply_outline_shader(sprite: Sprite2D, outline_color: Color = Color(0, 0, 0, 0.85), width: float = 1.0, glow_color: Color = Color(0, 0, 0, 0), glow_width: float = 0.0, glow_intensity: float = 0.0) -> void:
	var shader := load("res://shaders/sprite_outline.gdshader")
	if not shader:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("outline_color", outline_color)
	mat.set_shader_parameter("outline_width", width)
	mat.set_shader_parameter("glow_color", glow_color)
	mat.set_shader_parameter("glow_width", glow_width)
	mat.set_shader_parameter("glow_intensity", glow_intensity)
	sprite.material = mat

func _generate_sky_image() -> Image:
	var w := _world_w * TILE_SIZE
	var h := _world_h * TILE_SIZE
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top := Color(0.15, 0.22, 0.40)
	var bottom := Color(0.55, 0.70, 0.85)
	var strip_h := 16
	for y in range(0, h, strip_h):
		var t := float(y) / float(h)
		var c := top.lerp(bottom, t)
		img.fill_rect(Rect2i(0, y, w, min(strip_h, h - y)), c)
	return img

func _create_treasures() -> void:
	# Créer des coffres au trésor contenant des récompenses

	for i in range(TREASURE_COUNT):
		var chest_x: int = rng.randi_range(1, _zone_w - 2)
		var chest_y: int = rng.randi_range(1, _zone_h - 2)
		var world_x: float = (chest_x * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (chest_y * TILE_SIZE) + TILE_SIZE / 2
		var chest_pos: Vector2 = Vector2(world_x, world_y)
		
		# Données du coffre
		var chest_data: Dictionary = {
			"position": chest_pos,
			"opened": false,
			"gold_reward": rng.randi_range(20, 50),
			"xp_reward": rng.randi_range(15, 30)
		}
		_treasures.append(chest_data)
		
		# Créer le visuel du coffre
		var chest_node: Node2D = Node2D.new()
		chest_node.name = "Treasure_" + str(i)
		chest_node.position = chest_pos
		add_child(chest_node)
		
		# Sprite procédural coffre
		var chest_sprite: Sprite2D = Sprite2D.new()
		chest_sprite.texture = _sg._generate_sprite("chest", 64, chest_x * 1000 + chest_y)
		chest_sprite.position = Vector2(0, -8)
		chest_node.add_child(chest_sprite)
		_apply_outline_shader(chest_sprite, Color(0, 0, 0, 0.8), 1.0, Color(1.0, 0.85, 0.2, 0.25), 4.0, 0.15)
		
		# Ombre elliptique sous le coffre
		_sg._create_elliptical_shadow(chest_node, 36, 12, 8, 0.35)
		
		# Glow doré autour du coffre (effet de trésor)
		var chest_glow: Image = Image.create(48, 48, false, Image.FORMAT_RGBA8)
		chest_glow.fill(Color(0, 0, 0, 0))
		for gx in range(48):
			for gy in range(48):
				var gnx: float = (gx - 24) / 22.0
				var gny: float = (gy - 24) / 22.0
				var gdist: float = sqrt(gnx * gnx + gny * gny)
				if gdist <= 1.0:
					var galpha: float = (1.0 - gdist) * 0.2
					chest_glow.set_pixel(gx, gy, Color(1.0, 0.85, 0.2, galpha))
		var chest_glow_sprite: Sprite2D = Sprite2D.new()
		chest_glow_sprite.name = "ChestGlow"
		chest_glow_sprite.texture = ImageTexture.create_from_image(chest_glow)
		chest_glow_sprite.position = Vector2(0, -8)
		chest_glow_sprite.set_z_index(-1)
		chest_node.add_child(chest_glow_sprite)
		
		_treasure_visuals.append(chest_node)
	
	print("✓ ", TREASURE_COUNT, " coffres au trésor créés")

func _create_hero() -> void:
	# Supprimer l'ancien héros s'il existe (éviter les doublons)
	if _hero != null:
		_hero.queue_free()
		_heroes_data.clear()
		_hero = null
	
	_heroes_data = []
	var hero_name: String = GameData.hero_name if GameData.hero_name != "" else "Samurai"
	
	# Positionner le héros loin des villes (coin opposé de la carte)
	var spawn_pos: Vector2 = Vector2(_zone_w / 2 * TILE_SIZE + TILE_SIZE / 2, _zone_h / 2 * TILE_SIZE + TILE_SIZE / 2)
	if not _cities_data.is_empty():
		var avg_x: float = 0
		var avg_y: float = 0
		for cd in _cities_data:
			var ct: Vector2i = Vector2i(int(cd["position"].x / TILE_SIZE), int(cd["position"].y / TILE_SIZE))
			avg_x += ct.x
			avg_y += ct.y
		avg_x /= _cities_data.size()
		avg_y /= _cities_data.size()
		var spawn_tile: Vector2i = Vector2i(
			clampi(_zone_w - int(avg_x) - 5, 3, _zone_w - 4),
			clampi(_zone_h - int(avg_y) - 5, 3, _zone_h - 4)
		)
		var safety: int = 0
		while (_terrain_move_cost.get(_terrain_grid[spawn_tile.x][spawn_tile.y], 1) >= 999 or safety < 10):
			spawn_tile = Vector2i(rng.randi_range(3, _zone_w - 4), rng.randi_range(3, _zone_h - 4))
			safety += 1
		spawn_pos = Vector2(spawn_tile.x * TILE_SIZE + TILE_SIZE / 2, spawn_tile.y * TILE_SIZE + TILE_SIZE / 2)
		print("Héros spawn loin des villes à : ", spawn_tile)
	
	# Créer le héros principal (index 0)
	_active_hero_index = 0
	var main_node: Node2D = Node2D.new()
	main_node.name = "Hero"
	main_node.position = spawn_pos
	add_child(main_node)
	_hero = main_node
	_create_hero_sprites()
	
	_heroes_data.append({
		"name": hero_name,
		"hp": _hero_hp, "max_hp": _hero_max_hp,
		"attack": _hero_attack, "defense": _hero_defense,
		"mp": _hero_max_mp, "max_mp": _hero_max_mp,
		"level": 1, "xp": 0,
		"node": main_node,
		"position": spawn_pos,
		"unlocked": true,
	})
	
	# Créer les nodes pour les héros débloqués (invisibles au début)
	for h_unlock in _unlocked_heroes:
		_add_unlocked_hero_node(h_unlock)
	
	_update_hud_hero_buttons()
	
	# Créer la caméra centrée sur le héros
	_camera = Camera2D.new()
	_camera.position = _hero.position
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)
	_camera.make_current()
	
	var zone_width_pixels: float = _zone_w * TILE_SIZE
	var zone_height_pixels: float = _zone_h * TILE_SIZE
	
	_setup_camera_zoom()
	
	print("Caméra centrée sur la zone colorée: ", _camera.position)
	print("Zone: ", _zone_w, "×", _zone_h, " tuiles (", zone_width_pixels, "×", zone_height_pixels, " pixels)")
	print("Zoom min: ", _camera_zoom_min, " | défaut: ", _camera_zoom_default)
	_clamp_camera_to_map()
	
	print("Héros créé avec visuel à la position : ", _hero.position)
	print("Caméra créée pour suivre le héros")
	
	# Créer l'indicateur de portée de déplacement
	_create_movement_indicator()
	
func _create_hero_sprites() -> void:
	"""Crée le héros avec sprite samurai pixel art CC0"""
	_make_hero_label()
	
	# 1. Nouveau sprite samurai CC0 d'OpenGameArt (48x48)
	var samurai_tex: Texture2D = load("res://assets/heroes/hero_samurai_down.png")
	if samurai_tex:
		var spr: Sprite2D = Sprite2D.new()
		spr.name = "HeroSprite"
		spr.texture = samurai_tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(1.33, 1.33)
		spr.position = Vector2(0, -16)
		_apply_outline_shader(spr, Color(0, 0, 0, 0.8), 1.0, Color(1.0, 0.9, 0.5, 0.4), 4.0, 0.3)
		_hero.add_child(spr)
		print("✓ Héros créé avec sprite samurai pixel art CC0")
		return
	
	# 2. Fallback: perso.jpg
	var texture: Texture2D = load("res://assets/heroes/perso.jpg")
	if texture:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = "HeroSprite"
		sprite.texture = texture
		var tex_size: Vector2 = texture.get_size()
		var target_h: float = 56.0
		sprite.scale = Vector2(target_h / tex_size.y, target_h / tex_size.y)
		sprite.position = Vector2(0, -target_h / 2)
		_hero.add_child(sprite)
		print("✓ Héros créé avec perso.jpg")
		return
	
	# 3. Fallback procédural
	var fallback: Sprite2D = Sprite2D.new()
	fallback.texture = _sg._generate_sprite("hero", 64, 42)
	fallback.position = Vector2(0, -16)
	_hero.add_child(fallback)
	print("⚠ Aucun sprite trouvé, fallback procédural")
	
	# === HALO LUMINEUX AUTOUR DU HÉROS ===
	var glow_texture: Image = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	glow_texture.fill(Color(0, 0, 0, 0))
	var glow_hw: int = 40
	var glow_hh: int = 40
	for gx in range(80):
		for gy in range(80):
			var gnx: float = (gx - glow_hw) / 38.0
			var gny: float = (gy - glow_hh) / 38.0
			var gdist: float = sqrt(gnx * gnx + gny * gny)
			if gdist <= 1.0:
				var galpha: float = (1.0 - gdist) * 0.25
				glow_texture.set_pixel(gx, gy, Color(1.0, 0.9, 0.5, galpha))
	var glow_sprite: Sprite2D = Sprite2D.new()
	glow_sprite.name = "HeroGlow"
	glow_sprite.texture = ImageTexture.create_from_image(glow_texture)
	glow_sprite.position = Vector2(0, -16)
	glow_sprite.set_z_index(-3)
	_hero.add_child(glow_sprite)
	
	# Anneau de sélection avec coins (amélioré)
	var selection_ring: ColorRect = ColorRect.new()
	selection_ring.name = "SelectionRing"
	selection_ring.size = Vector2(64, 64)
	selection_ring.position = Vector2(-32, -32)
	selection_ring.color = Color(1.0, 0.85, 0.3, 0.25)
	_hero.add_child(selection_ring)
	selection_ring.set_z_index(-2)
	
	# Coins dorés décoratifs
	for corner in range(4):
		var corner_marker: ColorRect = ColorRect.new()
		corner_marker.size = Vector2(6, 6)
		var cx: float = -32 if corner % 2 == 0 else 26
		var cy: float = -32 if corner < 2 else 26
		corner_marker.position = Vector2(cx, cy)
		corner_marker.color = Color(1.0, 0.75, 0.15)
		corner_marker.set_z_index(-1)
		_hero.add_child(corner_marker)

	# Hero HP bar on world map
	var hero_hp_bg: ColorRect = ColorRect.new()
	hero_hp_bg.name = "HeroHPBG"
	hero_hp_bg.position = Vector2(-20, 24)
	hero_hp_bg.size = Vector2(40, 5)
	hero_hp_bg.color = Color(0.08, 0.08, 0.08)
	_hero.add_child(hero_hp_bg)

	var hero_hp_fill: ColorRect = ColorRect.new()
	hero_hp_fill.name = "HeroHPFill"
	hero_hp_fill.position = Vector2(-20, 24)
	hero_hp_fill.size = Vector2(40, 5)
	hero_hp_fill.color = Color(0.2, 0.7, 0.3)
	_hero.add_child(hero_hp_fill)

func _make_hero_label() -> void:
	var hero_label: Label = Label.new()
	hero_label.name = "HeroLabel"
	hero_label.text = _get_active_hero_name()
	hero_label.add_theme_font_size_override("font_size", 9)
	hero_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
	hero_label.position = Vector2(-24, 26)
	hero_label.size = Vector2(48, 14)
	hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero.add_child(hero_label)

func _get_active_hero_name() -> String:
	if _active_hero_index >= 0 and _active_hero_index < _heroes_data.size():
		return _heroes_data[_active_hero_index].get("name", "Heros")
	return "Heros"

func _add_unlocked_hero_node(h_unlock: Dictionary) -> void:
	var h_node: Node2D = Node2D.new()
	h_node.name = "HeroUnlocked_" + h_unlock.get("name", "unknown")
	h_node.position = _hero.position + Vector2(rng.randi_range(-100, 100), rng.randi_range(-100, 100))
	add_child(h_node)
	h_node.visible = true

	var hero_idx: int = _heroes_data.size()
	var hero_colors: Array[Color] = [
		Color(1.0, 1.0, 1.0),
		Color(0.6, 0.8, 1.0),
		Color(1.0, 0.8, 0.5),
		Color(1.0, 0.6, 1.0),
	]
	_add_hero_sprite(h_node, hero_colors[hero_idx % hero_colors.size()])

	_heroes_data.append({
		"name": h_unlock.get("name", "Heros"),
		"hp": h_unlock.get("hp", 80), "max_hp": h_unlock.get("max_hp", 80),
		"attack": h_unlock.get("attack", 12), "defense": h_unlock.get("defense", 8),
		"mp": 20, "max_mp": 20,
		"level": 1, "xp": 0,
		"node": h_node,
		"position": h_node.position,
		"unlocked": true,
	})
	print("★ Héros débloqué ajouté: ", h_unlock.get("name", "?"))

func _add_hero_sprite(hero_node: Node2D, tint: Color) -> void:
	var knight_path: String = "res://assets/units/knight.png"
	var texture: Texture2D = load(knight_path) if ResourceLoader.exists(knight_path) else null
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "KnightSprite"
	if texture:
		sprite.texture = texture
		sprite.scale = Vector2(2.0, 2.0)
	else:
		sprite.texture = _sg._generate_sprite("hero", 64, 42)
	sprite.position = Vector2(0, -16)
	sprite.modulate = tint
	hero_node.add_child(sprite)
	_apply_outline_shader(sprite, Color(0, 0, 0, 0.8), 1.0, Color(1.0, 0.9, 0.5, 0.15), 3.0, 0.1)

	var hero_label: Label = Label.new()
	hero_label.name = "HeroLabel"
	hero_label.add_theme_font_size_override("font_size", 9)
	hero_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
	hero_label.position = Vector2(-24, 26)
	hero_label.size = Vector2(48, 14)
	hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_node.add_child(hero_label)

	var hero_hp_bg: ColorRect = ColorRect.new()
	hero_hp_bg.name = "HeroHPBG"
	hero_hp_bg.position = Vector2(-20, 24)
	hero_hp_bg.size = Vector2(40, 5)
	hero_hp_bg.color = Color(0.08, 0.08, 0.08)
	hero_node.add_child(hero_hp_bg)

	var hero_hp_fill: ColorRect = ColorRect.new()
	hero_hp_fill.name = "HeroHPFill"
	hero_hp_fill.position = Vector2(-20, 24)
	hero_hp_fill.size = Vector2(40, 5)
	hero_hp_fill.color = Color(0.2, 0.7, 0.3)
	hero_node.add_child(hero_hp_fill)

func _switch_hero(index: int) -> void:
	if index < 0 or index >= _heroes_data.size():
		return
	_camera_follow_hero = true
	if index == _active_hero_index:
		if _camera:
			_camera.position = _hero.position
		return
	if _merchant_screen_open:
		_close_merchant_screen()
	if _town_screen_open:
		_close_town_screen()
	var old_idx: int = _active_hero_index
	if old_idx >= 0 and old_idx < _heroes_data.size():
		_heroes_data[old_idx]["position"] = _hero.position
	
	_active_hero_index = index
	_hero = _heroes_data[index]["node"]
	_hero.position = _heroes_data[index].get("position", _hero.position)
	
	_hero_hp = _heroes_data[index].get("hp", _hero_hp)
	_hero_max_hp = _heroes_data[index].get("max_hp", _hero_max_hp)
	_hero_attack = _heroes_data[index].get("attack", _hero_attack)
	_hero_defense = _heroes_data[index].get("defense", _hero_defense)
	_hero_mp = _heroes_data[index].get("mp", _hero_mp)
	_hero_max_mp = _heroes_data[index].get("max_mp", _hero_max_mp)
	
	var label: Label = _hero.get_node_or_null("HeroLabel")
	if label:
		label.text = _get_active_hero_name()
	
	if _camera:
		_camera.position = _hero.position
	
	if _movement_indicator:
		_movement_indicator.queue_free()
		_movement_indicator = null
	_create_movement_indicator()
	
	print("Héros changé: ", _get_active_hero_name())

func _update_hud_hero_buttons() -> void:
	if not _hud:
		return
	var names: Array = []
	for h in _heroes_data:
		names.append(h.get("name", "Heros"))
	_hud.set_hero_names(names)

func _add_sprite_layer(parent: Node2D, texture_path: String, layer_name: String) -> void:
	"""Ajoute une couche de sprite"""
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = layer_name
	
	# Charger la texture
	var texture: Texture2D = load(texture_path) if ResourceLoader.exists(texture_path) else null
	
	if texture:
		sprite.texture = texture
		sprite.centered = false
		# Les sprites LPC sont des spritesheets 8x1 (8 frames horizontales)
		# Configurer pour n'afficher qu'une seule frame
		sprite.hframes = 8  # 8 frames horizontaux
		sprite.vframes = 1  # 1 frame vertical
		sprite.frame = 0    # Afficher la première frame
		parent.add_child(sprite)
	else:
		push_warning("Texture non trouvée: " + texture_path)

func _create_movement_indicator() -> void:
	# Créer un indicateur visuel montrant la portée de déplacement du héros
	_movement_indicator = Node2D.new()
	_movement_indicator.name = "MovementIndicator"
	add_child(_movement_indicator)
	
	# Créer une grille de tuiles colorées autour du héros (portée de 3 tuiles)
	var move_range: int = 3  # Portée de déplacement en tuiles
	
	for dx in range(-move_range, move_range + 1):
		for dy in range(-move_range, move_range + 1):
			# Distance de Manhattan (comme dans HoMM3)
			var distance: int = abs(dx) + abs(dy)
			if distance <= move_range and distance > 0:  # Exclure la position du héros
				var indicator: ColorRect = ColorRect.new()
				indicator.size = Vector2(TILE_SIZE - 8, TILE_SIZE - 8)
				
				# Couleur selon la distance
				var alpha: float = 0.3 - (distance * 0.08)  # Plus transparent avec la distance
				indicator.color = Color(0.2, 0.8, 0.4, alpha)  # Vert avec transparence
				
				# Position relative au héros (sera mis à jour dans _process)
				indicator.position = Vector2(
					dx * TILE_SIZE - (TILE_SIZE - 8) / 2,
					dy * TILE_SIZE - (TILE_SIZE - 8) / 2
				)
				
				_movement_indicator.add_child(indicator)
	
	_movement_indicator.position = _hero.position
	print("✓ Indicateur de portée créé (", move_range, " tuiles)")

func _input(event: InputEvent) -> void:
	if _in_combat or _town_screen_open or _merchant_screen_open or _game_over_active:
		return

	if _pause_active:
		return

	if _llm_dialogue_screen or _fallback_dialogue_overlay:
		return

	if _is_pathfinding:
		return

	if _is_event_on_hud(event):
		return

	# Zoom avec la molette
	if _camera != null and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_wheel_debounce = 0.2
			_zoom_in()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel_debounce = 0.2
			_zoom_out()
			return

	# Drag tactile ou souris pour déplacer la caméra
	if event is InputEventScreenTouch:
		if _wheel_debounce > 0.0:
			return
		if event.pressed:
			_touch_points[event.index] = event.position
			if _touch_points.size() >= 2:
				var positions := _touch_points.values()
				_pinch_last_dist = positions[0].distance_to(positions[1])
			else:
				_is_dragging = false
				_drag_start_pos = event.position
		else:
			_touch_points.erase(event.index)
			if _touch_points.size() < 2 and _is_dragging:
				_is_dragging = false
				return
			if _touch_points.size() < 2 and not _is_dragging:
				_handle_tap(event.position)
		return

	if event is InputEventScreenDrag:
		if _wheel_debounce > 0.0:
			return
		_touch_points[event.index] = event.position
		if _touch_points.size() >= 2:
			var positions: Array = _touch_points.values()
			var dist: float = (positions[0] as Vector2).distance_to(positions[1] as Vector2)
			if _pinch_last_dist > 0:
				var ratio: float = dist / _pinch_last_dist
				if ratio > 1.02:
					_zoom_in()
					_pinch_last_dist = dist
				elif ratio < 0.98:
					_zoom_out()
					_pinch_last_dist = dist
				else:
					_pinch_last_dist = dist
			else:
				_pinch_last_dist = dist
		elif not _is_dragging:
			if _drag_start_pos.distance_to(event.position) > _drag_threshold:
				_is_dragging = true
				_camera_follow_hero = false
		if _is_dragging and _camera and _touch_points.size() < 2:
			_camera.position -= event.relative * 2.5
			_clamp_camera_to_map()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _wheel_debounce > 0.0:
			return
		if event.pressed:
			_is_dragging = false
			_drag_start_pos = event.position
		elif _is_dragging:
			_is_dragging = false
			return
		else:
			# Click court → déplacement héros
			_handle_tap(event.position)
		return

	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if _wheel_debounce > 0.0:
			return
		if not _is_dragging:
			if _drag_start_pos.distance_to(event.position) > _drag_threshold:
				_is_dragging = true
				_camera_follow_hero = false
		if _is_dragging and _camera:
			_camera.position -= event.relative * 2.5
			_clamp_camera_to_map()
		return

	# Raccourcis clavier HoMM3
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_H:
				# Changer de héros (cycle)
				if _heroes_data.size() > 1:
					var next_idx: int = (_active_hero_index + 1) % _heroes_data.size()
					_switch_hero(next_idx)
					print("🔄 Héros changé: ", _get_active_hero_name())
			KEY_T:
				# Fin de tour rapide
				_end_turn()
				print("🔄 Fin de tour (touche T)")
			KEY_C:
				# Construire dans la ville sélectionnée
				if _town_screen_open and _selected_city_index >= 0:
					print("=== CONSTRUCTION ===")
					print("Tapez le numéro du bâtiment à construire:")
					var idx: int = 1
					for b_key in CITY_BUILDINGS:
						var b_data: Dictionary = CITY_BUILDINGS[b_key]
						print("  ", idx, ": ", b_data["name"], " (", b_data["cost_g"], "🪙, ", b_data["cost_w"], "🪵, ", b_data["cost_o"], "💎)")
						idx += 1
				print("  0: Annuler")
			KEY_R:
				# Recruter dans la ville sélectionnée
				if _town_screen_open and _selected_city_index >= 0:
					print("=== RECRUTEMENT ===")
					print("Tapez le numéro de l'unité à recruter:")
					var idx: int = 1
					for u_key in UNIT_TYPES:
						var u_data: Dictionary = UNIT_TYPES[u_key]
						print("  ", idx, ": ", u_data["name"], " (", u_data["cost_g"], "🪙)")
						idx += 1
				print("  0: Annuler")
			KEY_Q:
				# Quitter l'écran de ville
				if _town_screen_open:
					_close_town_screen()
					_selected_city_index = -1
					print("=== FERMÉ ===")
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0:
				# Construction ou recrutement par numéro
				if _town_screen_open and _selected_city_index >= 0:
					var num: int = event.keycode - KEY_1 + 1
					if event.keycode == KEY_0:
						num = 0
					print("Sélection: ", num)

func _handle_tap(screen_pos: Vector2) -> void:
	var tile: Vector2i = _screen_to_tile(screen_pos)
	if tile.x < 0:
		return
	var hero_tile: Vector2i = Vector2i(
		int(_hero.position.x / TILE_SIZE),
		int(_hero.position.y / TILE_SIZE)
	)
	if tile == hero_tile:
		return
	
	# Vérifier si on clique sur un boss
	for bi in range(_bosses.size()):
		var boss_tile: Vector2i = Vector2i(
			int(_bosses[bi].position.x / TILE_SIZE),
			int(_bosses[bi].position.y / TILE_SIZE)
		)
		if tile == boss_tile and _bosses[bi].get("alive", true):
			var dist: int = absi(hero_tile.x - tile.x) + absi(hero_tile.y - tile.y)
			if dist <= 1:
				_start_enemy_dialogue(bi, true)
			else:
				_create_floating_text("Approchez-vous du boss !", Color(0.9, 0.2, 0.2), _hero.position)
			return
	
	# Vérifier si on clique sur un ennemi errant
	for ei in range(_enemies.size()):
		var enemy_tile: Vector2i = Vector2i(
			int(_enemies[ei].position.x / TILE_SIZE),
			int(_enemies[ei].position.y / TILE_SIZE)
		)
		if tile == enemy_tile and _enemies[ei].get("alive", true):
			var dist: int = absi(hero_tile.x - tile.x) + absi(hero_tile.y - tile.y)
			if dist <= 1:
				_create_floating_text("🗣 Dialogue...", Color(0.3, 1.0, 0.3), _hero.position)
				_start_enemy_dialogue(ei)
			else:
				_create_floating_text("Approchez-vous de l'ennemi !", Color(0.9, 0.2, 0.2), _hero.position)
			return

	# Vérifier si on clique sur un marchand
	for mi in range(_merchants.size()):
		var m_tile: Vector2i = Vector2i(
			int(_merchants[mi].position.x / TILE_SIZE),
			int(_merchants[mi].position.y / TILE_SIZE)
		)
		if tile == m_tile:
			var dist: int = absi(hero_tile.x - tile.x) + absi(hero_tile.y - tile.y)
			if dist <= 1:
				_open_merchant_screen(mi)
			else:
				_create_floating_text("Approchez-vous du marchand !", Color(0.9, 0.7, 0.3), _hero.position)
			return

	if _terrain_move_cost.get(_terrain_grid[tile.x][tile.y], 1) >= 999:
		if _water_walk_turns > 0:
			_hero_mp -= 1
			var target_pos: Vector2 = Vector2(tile.x * TILE_SIZE + TILE_SIZE / 2, tile.y * TILE_SIZE + TILE_SIZE / 2)
			if _move_tween:
				_move_tween.kill()
			_move_tween = create_tween()
			_move_tween.tween_property(_hero, "position", target_pos, 0.12)
			if _movement_indicator:
				_move_tween.parallel().tween_property(_movement_indicator, "position", target_pos, 0.12)
			_move_tween.tween_callback(_on_path_step_done)
			_create_floating_text("🌊 Marche sur l'eau !", Color(0.3, 0.7, 1.0), _hero.position)
			return
		_create_floating_text("Eau !", Color(0.9, 0.2, 0.2), _hero.position)
		return

	var path: Array = AStarPathfinding.find_path(
		_terrain_grid, _terrain_move_cost,
		hero_tile, tile, _hero_mp
	)
	if path.size() <= 1:
		_create_floating_text("Pas de chemin !", Color(0.9, 0.2, 0.2), _hero.position)
		return

	var total_cost: int = AStarPathfinding.path_cost(path, _terrain_grid, _terrain_move_cost)
	if total_cost > _hero_mp:
		_create_floating_text("MP insuffisants !", Color(0.9, 0.2, 0.2), _hero.position)
		return

	_path_queue = path
	_is_pathfinding = true
	_advance_path_step()

func _is_event_on_hud(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag):
		return false
	if _hud == null:
		return false
	var pos: Vector2 = event.position
	for child in _hud.get_children():
		if _is_control_at_pos(child, pos):
			return true
	return false

func _is_control_at_pos(node: Node, pos: Vector2) -> bool:
	if node is Control and node.visible:
		var rect := Rect2(node.global_position, node.size)
		if rect.has_point(pos):
			return true
		for c in node.get_children():
			if _is_control_at_pos(c, pos):
				return true
	return false

func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	return Vector2i(
		clampi(int(world_pos.x / TILE_SIZE), 0, _zone_w - 1),
		clampi(int(world_pos.y / TILE_SIZE), 0, _zone_h - 1)
	)

func _is_tap_or_click(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	if event is InputEventScreenTouch and event.pressed:
		return true
	return false

func _event_to_tile(event: InputEvent) -> Vector2i:
	var pos: Vector2
	if event is InputEventMouseButton:
		pos = get_global_mouse_position()
	elif event is InputEventScreenTouch:
		pos = get_canvas_transform().affine_inverse() * event.position
	else:
		return Vector2i(-1, -1)
	return Vector2i(
		clampi(int(pos.x / TILE_SIZE), 0, _zone_w - 1),
		clampi(int(pos.y / TILE_SIZE), 0, _zone_h - 1)
	)

func _advance_path_step() -> void:
	if _path_queue.is_empty():
		_is_pathfinding = false
		return

	var target_tile: Vector2i = _path_queue.pop_front()
	var target_pos: Vector2 = Vector2(
		target_tile.x * TILE_SIZE + TILE_SIZE / 2,
		target_tile.y * TILE_SIZE + TILE_SIZE / 2
	)

	var terrain: int = _terrain_grid[target_tile.x][target_tile.y]
	var step_cost: int = _terrain_move_cost.get(terrain, 1)
	_hero_mp -= step_cost

	if _move_tween:
		_move_tween.kill()
	_move_tween = create_tween()

	# Direction-based lean
	var knight: Sprite2D = _hero.get_node_or_null("KnightSprite") if _hero else null
	if knight:
		var dir: Vector2 = target_pos - _hero.position
		var lean_angle: float = clampf(dir.x * 0.08, -6.0, 6.0)
		knight.rotation_degrees = lean_angle

	_move_tween.tween_property(_hero, "position", target_pos, 0.12)
	if _movement_indicator:
		_move_tween.parallel().tween_property(_movement_indicator, "position", target_pos, 0.12)
	_move_tween.tween_callback(_on_path_step_done)

func _on_path_step_done() -> void:
	_hero_tile = _tile_at_world(_hero.position)
	_update_fog_of_war()
	_update_minimap()
	_clamp_camera_to_map()
	_update_resource_labels()

	if _path_queue.is_empty():
		_is_pathfinding = false
		if _active_hero_index >= 0 and _active_hero_index < _heroes_data.size():
			_heroes_data[_active_hero_index]["position"] = _hero.position
		var knight: Sprite2D = _hero.get_node_or_null("KnightSprite") if _hero else null
		if knight:
			var rt = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			rt.tween_property(knight, "rotation_degrees", 0.0, 0.15)
		_check_city_visit()
		_check_merchant_visit()
		_check_resource_collection()
		_check_treasure_collection()
	else:
		_advance_path_step()

func _process(delta: float) -> void:
	if _game_over_active:
		return
	_anim_time += delta
	_fx_frame += 1
	if _wheel_debounce > 0:
		_wheel_debounce -= delta
	if _map_sprite and _map_sprite.material is ShaderMaterial:
		_map_sprite.material.set_shader_parameter("time", _anim_time * 0.5)
	if _sky_sprite and _sky_sprite.material is ShaderMaterial:
		_sky_sprite.material.set_shader_parameter("time", _anim_time)
	if _vignette_overlay:
		VisualEnhancer.set_vignette_time(_vignette_overlay, _anim_time)
	
	if _hero and _camera_follow_hero and _camera:
		_camera.position = _hero.position
	
	# Halo héros seulement (léger)
	if _hero != null:
		var hero_glow: Sprite2D = _hero.get_node_or_null("HeroGlow")
		if hero_glow != null:
			var pulse: float = (sin(_anim_time * 3.0) + 1.0) * 0.5
			hero_glow.modulate.a = 0.6 + pulse * 0.35
	# Fog dissolve animation (seulement si des tuiles sont en cours d'animation)
	if not _fog_animating.is_empty():
		if _fog_overlay and _fog_overlay.material is ShaderMaterial:
			_fog_overlay.material.set_shader_parameter("time", _anim_time)
	_process_fog_animation(delta)

	# === AMBIANCE SONORE (vent aléatoire) ===
	if _ambient_timer <= 0:
		_ambient_timer = randf_range(8.0, 20.0)
		if SFX and SFX.has_method("play_wind"):
			SFX.play_wind()
	else:
		_ambient_timer -= delta

	# === EFFETS VISUELS (1 frame sur 2 pour le CPU) ===
	var t: float = _anim_time
	if _fx_frame & 1 == 0:
		for mdata in _light_motes:
			var m: ColorRect = mdata["node"]
			if not is_instance_valid(m):
				continue
			var m_at := t
			var m_phase: float = mdata["phase"]
			m.position.x = mdata["base"].x + sin(m_at * mdata["drift"] + m_phase) * 20.0
			m.position.y = mdata["base"].y + sin(m_at * mdata["drift"] * 0.7 + m_phase * 1.3) * 15.0
			m.position.y -= sin(m_at * mdata["speed"] * 0.1) * 5.0
			m.modulate.a = 0.08 + (sin(m_at + m_phase) * 0.5 + 0.5) * 0.08
			var ms: float = mdata["size"]
			m.size = Vector2(ms, ms) * (0.8 + sin(m_at * 0.5 + m_phase) * 0.2)

		for bdata in _japanese_building_data:
			var sp: Sprite2D = bdata["sprite"]
			if is_instance_valid(sp):
				sp.position.y = bdata["base_y"] + sin(t * 1.2 + bdata["node"].position.x * 0.01) * 3.0

		for pdata in _petals:
			var n: ColorRect = pdata["node"]
			if not is_instance_valid(n):
				continue
			var wind_x := sin(t * 0.3 + pdata["offset"]) * 0.5
			n.position.y += pdata["speed_y"] + sin(t * 0.7 + pdata["phase"]) * 0.4
			n.position.x += pdata["speed_x"] + wind_x
			n.rotation += pdata["rotation_speed"]
			var wobble := sin(t * 1.2 + pdata["phase"]) * 0.08
			n.scale = Vector2(1.0 + wobble, 1.0 - wobble * 0.5)
			var view_h := _world_h * TILE_SIZE
			var view_w := _world_w * TILE_SIZE
			if n.position.y > view_h + 20 or n.position.x < -30 or n.position.x > view_w + 30:
				n.position.y = randf_range(-20, -5)
				n.position.x = randf_range(0, view_w)
				n.modulate.a = randf_range(0.3, 0.6)
				pdata.speed_y = randf_range(12, 28)
				pdata.speed_x = randf_range(4, 10) * (1 if randf() > 0.5 else -1)
				pdata.rotation_speed = randf_range(0.3, 0.8) * (1 if randf() > 0.5 else -1)
				pdata.offset = randf() * TAU

		for lg in _lantern_glows:
			if is_instance_valid(lg):
				var gp: float = (sin(t * 2.0) + 1.0) * 0.5
				lg.modulate.a = 0.12 + gp * 0.10

	# Coffres / fumée : 1 frame sur 4 (cosmétique)
	if _fx_frame % 4 != 0:
		return
	for chest_node in _treasure_visuals:
		if not chest_node.visible:
			continue
		var chest_glow: Sprite2D = chest_node.get_node_or_null("ChestGlow")
		if chest_glow != null:
			var chest_pulse: float = (sin(t * 4.0 + chest_node.position.x * 0.1) + 1.0) * 0.5
			chest_glow.modulate.a = 0.5 + chest_pulse * 0.45
	for smoke_data in _smoke_particles:
		var smoke: Sprite2D = smoke_data["sprite"]
		var cycle: float = fmod(t + smoke_data["offset"], smoke_data["speed"]) / smoke_data["speed"]
		smoke.position.y = smoke_data["base_pos"].y - cycle * 20.0
		smoke.position.x = smoke_data["base_pos"].x + sin(cycle * TAU) * 3.0
	for fly in _fireflies:
		var n: ColorRect = fly["node"]
		if not is_instance_valid(n):
			continue
		var phase: float = t * fly["speed"] + fly["phase"]
		var dx: float = sin(phase) * fly["radius"]
		var dy: float = cos(phase * 0.7) * fly["radius"] * 0.5
		n.position = fly["base"] + Vector2(dx, dy)
		var blink: float = (sin(t * fly["blink_speed"] + fly["phase"]) + 1.0) * 0.5 * 0.7 + 0.3
		n.modulate.a = blink
		var s: float = 1.0 + sin(t * fly["blink_speed"] * 1.5 + fly["phase"]) * 0.3
		n.scale = Vector2(s, s)

# ============================================================
# SYSTÈME HOMURA : BROUILLARD DE GUERRE
# ============================================================

func _process_fog_animation(delta: float) -> void:
	if _fog_animating.is_empty() or _fog_image == null or _fog_texture == null:
		return
	var texture_needs_update: bool = false
	var finished_keys: Array = []
	for key in _fog_animating:
		var anim: Dictionary = _fog_animating[key]
		var parts: PackedStringArray = key.split(",")
		var tx: int = int(parts[0])
		var ty: int = int(parts[1])
		if tx < 0 or ty < 0 or tx >= _zone_w or ty >= _zone_h:
			finished_keys.append(key)
			continue
		anim["current"] = move_toward(anim["current"], anim["target"], anim["speed"] * delta)
		_fog_current_alpha[tx][ty] = anim["current"]
		_paint_fog_tile(tx, ty)
		texture_needs_update = true
		if absf(anim["current"] - anim["target"]) < 0.01:
			_fog_current_alpha[tx][ty] = anim["target"]
			_paint_fog_tile(tx, ty)
			finished_keys.append(key)
	for key in finished_keys:
		_fog_animating.erase(key)
	if texture_needs_update and _fx_frame & 1 == 0:
		_fog_texture.update(_fog_image)

func _init_fog_of_war() -> void:
	"""Initialise la grille de brouillard de guerre"""
	_fog_grid = []
	_fog_current_alpha = []
	for x in range(_zone_w):
		_fog_grid.append([])
		_fog_current_alpha.append([])
		for y in range(_zone_h):
			_fog_grid[x].append(0)  # 0 = inconnu
			_fog_current_alpha[x].append(1.0)  # alpha initial = 1.0 (caché)
	print("✓ Brouillard de guerre initialisé: ", _zone_w, "x", _zone_h)

func _create_fog_overlay() -> void:
	_fog_overlay = Sprite2D.new()
	_fog_overlay.name = "FogOverlay"
	_fog_overlay.z_index = 8
	if _map_sprite:
		_fog_overlay.position = _map_sprite.position
	add_child(_fog_overlay)
	var img_w: int = _zone_w * TILE_SIZE
	var img_h: int = _zone_h * TILE_SIZE
	_fog_image = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0.04, 0.06, 0.10, 1.0))
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	_fog_overlay.texture = _fog_texture
	var fog_shader := load("res://shaders/fog.gdshader")
	if fog_shader:
		var mat := ShaderMaterial.new()
		mat.shader = fog_shader
		_fog_overlay.material = mat

func _paint_fog_tile(tx: int, ty: int) -> void:
	if _fog_image == null or tx < 0 or ty < 0 or tx >= _zone_w or ty >= _zone_h:
		return
	var rect := Rect2i(tx * TILE_SIZE, ty * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	var state: int = _fog_grid[tx][ty]
	if state == 2:
		var alpha: float = _fog_current_alpha[tx][ty] if tx < _fog_current_alpha.size() and ty < _fog_current_alpha[tx].size() else 0.0
		_fog_image.fill_rect(rect, Color(0.04, 0.06, 0.10, alpha))
	else:
		var alpha: float = _fog_current_alpha[tx][ty] if tx < _fog_current_alpha.size() and ty < _fog_current_alpha[tx].size() else 1.0
		_fog_image.fill_rect(rect, Color(0.04, 0.06, 0.10, alpha))

func _refresh_fog_tiles(tiles: Array) -> void:
	if tiles.is_empty() or _fog_image == null or _fog_texture == null:
		return
	for tile in tiles:
		if tile is Vector2i:
			var state: int = _fog_grid[tile.x][tile.y]
			var target_alpha: float
			if state == 2:
				target_alpha = 0.0
			elif state == 1:
				target_alpha = 0.5
			else:
				target_alpha = 1.0
			var key: String = "%d,%d" % [tile.x, tile.y]
			if not _fog_animating.has(key):
				if _fog_current_alpha[tile.x][tile.y] != target_alpha:
					_fog_animating[key] = {
						"current": _fog_current_alpha[tile.x][tile.y],
						"target": target_alpha,
						"speed": 2.0  # alpha per second
					}
			else:
				_fog_animating[key]["target"] = target_alpha
			# Paint first frame immediately
			_paint_fog_tile(tile.x, tile.y)
	_fog_texture.update(_fog_image)

func _tile_at_world(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(world_pos.x / TILE_SIZE), 0, _zone_w - 1),
		clampi(int(world_pos.y / TILE_SIZE), 0, _zone_h - 1)
	)

func _is_tile_visible(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= _zone_w or ty >= _zone_h:
		return false
	return _fog_grid[tx][ty] == 2

func _update_entity_visibility() -> void:
	for i in range(_enemies.size()):
		if not _enemies[i].get("alive", true):
			continue
		if i >= _enemy_visuals.size():
			continue
		var t: Vector2i = _tile_at_world(_enemies[i]["position"])
		_enemy_visuals[i].visible = _is_tile_visible(t.x, t.y)
	for i in range(_cities.size()):
		if i >= _city_visuals.size():
			continue
		var t: Vector2i = _tile_at_world(_cities[i])
		_city_visuals[i].visible = _is_tile_visible(t.x, t.y)
	for i in range(_resources.size()):
		if _resources[i].get("collected", false):
			continue
		if i >= _resource_visuals.size():
			continue
		var t: Vector2i = _tile_at_world(_resources[i]["position"])
		_resource_visuals[i].visible = _is_tile_visible(t.x, t.y)
	for i in range(_treasures.size()):
		if _treasures[i].get("opened", false):
			continue
		if i >= _treasure_visuals.size():
			continue
		var t: Vector2i = _tile_at_world(_treasures[i]["position"])
		_treasure_visuals[i].visible = _is_tile_visible(t.x, t.y)

func _update_fog_of_war() -> void:
	if _fog_grid.is_empty() or _hero == null:
		return
	
	var hero_tile: Vector2i = _tile_at_world(_hero.position)
	var newly_discovered: int = 0
	var changed_tiles: Array = []
	var scan_r: int = FOG_VISION_RANGE + 1
	
	for dx in range(-scan_r, scan_r + 1):
		for dy in range(-scan_r, scan_r + 1):
			if absi(dx) + absi(dy) > scan_r:
				continue
			var x: int = hero_tile.x + dx
			var y: int = hero_tile.y + dy
			if x < 0 or y < 0 or x >= _zone_w or y >= _zone_h:
				continue
			var dist: int = absi(dx) + absi(dy)
			var old_state: int = _fog_grid[x][y]
			if dist <= FOG_VISION_RANGE:
				if old_state == 0:
					_fog_grid[x][y] = 1
					newly_discovered += 1
				if _fog_grid[x][y] != 2:
					_fog_grid[x][y] = 2
					changed_tiles.append(Vector2i(x, y))
			elif old_state == 2:
				_fog_grid[x][y] = 1
				changed_tiles.append(Vector2i(x, y))
	
	if newly_discovered > 0:
		var discover_xp: int = min(newly_discovered * XP_DISCOVER_TILE, 30)
		_gain_xp(discover_xp)
	
	_refresh_fog_tiles(changed_tiles)
	_update_entity_visibility()

# ============================================================
# SYSTÈME HOMURA : ARMÉES ENNEMIES
# ============================================================
func _init_enemy_armies() -> void:
	"""Initialise les armées des ennemis errants avec les nouveaux types d'unités"""
	_enemy_armies = []
	var new_unit_ids: Array = GameData.UNIT_TYPES.keys()

	for i in range(_enemies.size()):
		var army: Array = []
		var army_size: int = rng.randi_range(1, 3)
		var used: Array[String] = []

		for _j in range(army_size):
			var unit_id: String
			var safety: int = 0
			while true:
				unit_id = new_unit_ids[rng.randi_range(0, new_unit_ids.size() - 1)]
				safety += 1
				if not used.has(unit_id) or safety > 20:
					break
			var unit_data: Dictionary = GameData.UNIT_TYPES.get(unit_id, {})
			if unit_data.is_empty():
				unit_id = "ashigaru"
				unit_data = GameData.UNIT_TYPES["ashigaru"]
			used.append(unit_id)
			var count: int = rng.randi_range(3, 8 + _game_week)
			army.append({
				"type": unit_id,
				"count": count,
				"hp": unit_data.get("hp", 6),
				"max_hp": unit_data.get("hp", 6),
				"attack": unit_data.get("attack", 4),
				"defense": unit_data.get("defense", 3)
			})
		
		_enemy_armies.append(army)
	
	print("✓ ", _enemy_armies.size(), " armées errantes initialisées (nouveaux types)")

# ============================================================
# SYSTÈME HOMURA : FIN DE TOUR
# ============================================================
func _end_turn() -> void:
	"""Gère la fin de tour (HoMM style)"""
	print("=== FIN DE TOUR ===")
	
	# 1. Restaurer les MP
	_hero_mp = _hero_max_mp
	print("🚶 MP restaurés: ", _hero_mp, "/", _hero_max_mp)
	
	# 1b. Décompter la marche sur l'eau
	if _water_walk_turns > 0:
		_water_walk_turns -= 1
		if _water_walk_turns <= 0:
			_create_floating_text("🌊 Amulette aquatique épuisée", Color(0.5, 0.7, 1.0), _hero.position)
			print("🌊 Marche sur l'eau terminée")
		else:
			print("🌊 Marche sur l'eau: ", _water_walk_turns, " tours restants")
	
	# 2. Incrémenter le temps
	_game_day += 1
	if _game_day > 7:
		_game_day = 1
		_game_week += 1
		print("📅 Nouvelle semaine ! Semaine ", _game_week)
		
		# Événement de semaine
		if _game_week > 4:
			_game_week = 1
			_game_month += 1
			print("📅 Nouveau mois ! Mois ", _game_month)
	
	# 3. MOUVEMENT DES ENNEMIS (IA)
	if _hero != null:
		var hero_tile: Vector2i = Vector2i(
			int(_hero.position.x / TILE_SIZE),
			int(_hero.position.y / TILE_SIZE)
		)
		for i in range(_enemies.size()):
			var ed: Dictionary = _enemies[i]
			if not ed.get("alive", true):
				continue
			var enemy_tile: Vector2i = Vector2i(
				int(ed.position.x / TILE_SIZE),
				int(ed.position.y / TILE_SIZE)
			)
			var dist: int = absi(hero_tile.x - enemy_tile.x) + absi(hero_tile.y - enemy_tile.y)
			if dist > ed.get("detection_range", 8):
				continue
			var path: Array = AStarPathfinding.find_path(
				_terrain_grid, _terrain_move_cost,
				enemy_tile, hero_tile
			)
			if path.size() <= 1:
				continue
			var enemy_mp: int = ed.get("mp", 8)
			var steps: int = 0
			for step_idx in range(1, path.size()):
				var step_tile: Vector2i = path[step_idx]
				var step_terrain: int = _terrain_grid[step_tile.x][step_tile.y]
				var step_cost: int = _terrain_move_cost.get(step_terrain, 1)
				if step_cost > enemy_mp:
					break
				enemy_mp -= step_cost
				steps = step_idx
				if step_tile == hero_tile:
					break
			if steps > 0:
				var new_tile: Vector2i = path[steps]
				var new_pos: Vector2 = Vector2(
					new_tile.x * TILE_SIZE + TILE_SIZE / 2,
					new_tile.y * TILE_SIZE + TILE_SIZE / 2
				)
				ed.position = new_pos
				ed.mp = enemy_mp
				if i < _enemy_visuals.size():
					var et = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
					et.tween_property(_enemy_visuals[i], "position", new_pos, 0.25)
		# Restaurer MP des ennemis pour le prochain tour
		for ed in _enemies:
			ed.mp = ed.get("max_mp", 8)

	# 5. Mettre à jour l'interface
	if _label_date:
		_label_date.text = "Month %d  Week %d  Day %d" % [_game_month, _game_week, _game_day]
	_update_resource_labels()
	
	print("Date : Month ", _game_month, ", Week ", _game_week, ", Day ", _game_day)
	print("=== NOUVEAU TOUR ===")

func _check_resource_collection() -> void:
	# Vérifier si le héros est proche d'une ressource
	for i in range(_resources.size()):
		var res_data: Dictionary = _resources[i]
		
		# Ignorer les ressources déjà collectées
		if res_data["collected"]:
			continue
		
		var res_pos: Vector2 = res_data["position"]
		var distance: float = _hero.position.distance_to(res_pos)
		
		# Si le héros est assez proche (moins d'une tuile), il collecte la ressource
		if distance < TILE_SIZE:
			var res_type: String = res_data["type"]
			var res_name: String = res_data["name"]
			
			print("⛏️ Ressource collectée : ", res_name, " !")
			
			# Bonus selon le type + textes flottants
			match res_type:
				"gold":
					_gold += 50
					print("   🪙 +50 Or !")
					_create_floating_text("+50 🪙", Color(1.0, 0.85, 0.2), _hero.position)
				"wood":
					_wood += 15
					print("   🪵 +15 Bois !")
					_create_floating_text("+15 🪵", Color(0.6, 0.9, 0.4), _hero.position)
				"ore":
					_ore += 10
					print("   💎 +10 Minerai !")
					_create_floating_text("+10 💎", Color(0.75, 0.75, 0.85), _hero.position)
			
			_update_resource_labels()
			GameData.track_action("A collecté " + res_type + " (" + res_name + ")")
			res_data["collected"] = true
			var burst_color: Color = Color(1.0, 0.85, 0.2) if res_type == "gold" else (Color(0.6, 0.9, 0.4) if res_type == "wood" else Color(0.75, 0.75, 0.85))
			_spawn_burst_particles(res_pos, burst_color, 8)
			if i < _resource_visuals.size():
				var res_node: Node2D = _resource_visuals[i]
				var rt = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				rt.tween_property(res_node, "scale", Vector2(1.6, 1.6), 0.25)
				rt.parallel().tween_property(res_node, "modulate:a", 0.0, 0.25)
				rt.tween_callback(func(): res_node.visible = false)
			_refresh_minimap()
			_gain_xp(XP_COLLECT_RESOURCE)
			break

func _check_treasure_collection() -> void:
	for i in range(_treasures.size()):
		var chest_data: Dictionary = _treasures[i]
		if chest_data.get("opened", false):
			continue
		if _hero.position.distance_to(chest_data["position"]) >= TILE_SIZE:
			continue
		chest_data["opened"] = true
		var gold_gain: int = chest_data.get("gold_reward", 40)
		var xp_gain: int = chest_data.get("xp_reward", XP_OPEN_TREASURE)
		_gold += gold_gain
		_update_resource_labels()
		GameData.track_action("A ouvert un coffre (+" + str(gold_gain) + " or)")
		_create_floating_text("+" + str(gold_gain) + " 🪙", Color(1.0, 0.85, 0.2), _hero.position)
		_spawn_burst_particles(chest_data["position"], Color(1.0, 0.85, 0.2), 10)
		_gain_xp(xp_gain)
		if i < _treasure_visuals.size():
			var chest: Node2D = _treasure_visuals[i]
			var ct = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			ct.tween_property(chest, "scale", Vector2(1.8, 1.8), 0.3)
			ct.parallel().tween_property(chest, "modulate:a", 0.0, 0.3)
			ct.tween_callback(func(): chest.visible = false)
		_refresh_minimap()
		print("📦 Coffre ouvert ! +", gold_gain, " or, +", xp_gain, " XP")
		break

func _update_resource_labels() -> void:
	if _label_gold:
		_label_gold.text = str(_gold)
	if _label_wood:
		_label_wood.text = str(_wood)
	if _label_ore:
		_label_ore.text = str(_ore)
	if "q_rich" not in _quest_completed:
		if _gold >= 10000:
			for q in QUESTS:
				if q["id"] == "q_rich":
					_complete_quest(q)
					break

func _get_viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _setup_camera_zoom() -> void:
	var vp: Vector2 = _get_viewport_size()
	var map_w: float = _zone_w * TILE_SIZE
	var map_h: float = _zone_h * TILE_SIZE
	# Dézoom max : la carte remplit l'écran (juste avant les bords)
	_camera_zoom_min = maxf(vp.x / map_w, vp.y / map_h) * 1.008
	_camera_zoom_default = _camera_zoom_min * ZOOM_DEFAULT_FACTOR
	_camera.zoom = Vector2(_camera_zoom_default, _camera_zoom_default)

func _clamp_camera_to_map() -> void:
	if not _camera:
		return
	var vp := _get_viewport_size()
	var map_w: float = _zone_w * TILE_SIZE
	var map_h: float = _zone_h * TILE_SIZE
	var zx: float = _camera.zoom.x
	var zy: float = _camera.zoom.y
	var half_w: float = vp.x / 2.0 * zx
	var half_h: float = vp.y / 2.0 * zy
	var min_x: float = half_w
	var max_x: float = map_w - half_w
	var min_y: float = half_h
	var max_y: float = map_h - half_h
	if max_x < min_x:
		var center: float = map_w / 2.0
		min_x = center
		max_x = center
	if max_y < min_y:
		var center: float = map_h / 2.0
		min_y = center
		max_y = center
	_camera.position.x = clampf(_camera.position.x, min_x, max_x)
	_camera.position.y = clampf(_camera.position.y, min_y, max_y)

func _zoom_in() -> void:
	if not _camera:
		return
	var new_zoom: float = _camera.zoom.x + ZOOM_STEP
	new_zoom = clamp(new_zoom, _camera_zoom_min, ZOOM_MAX)
	_camera.zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera_to_map()
	_update_minimap()

func _zoom_out() -> void:
	if not _camera:
		return
	var new_zoom: float = _camera.zoom.x - ZOOM_STEP
	new_zoom = clamp(new_zoom, _camera_zoom_min, ZOOM_MAX)
	_camera.zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera_to_map()
	_update_minimap()

func _check_enemy_encounter() -> void:
	# Vérifier si le héros est proche d'un ennemi
	for i in range(_enemies.size()):
		var enemy_data: Dictionary = _enemies[i]
		
		# Ignorer les ennemis morts
		if not enemy_data["alive"]:
			continue
		
		var enemy_pos: Vector2 = enemy_data["position"]
		var distance: float = _hero.position.distance_to(enemy_pos)
		
		# Si le héros est assez proche (moins d'une tuile), combat !
		if distance < TILE_SIZE:
			_start_combat(i)
			break

func _army_to_combat_units(army: Array) -> Array:
	# Combat 1v1 : fusionner toute l'armée en 1 unité ennemie
	var total_hp: int = 0
	var total_attack: int = 0
	var total_defense: int = 0
	var name_parts: Array = []
	for stack in army:
		var count: int = stack.get("count", 0)
		if count <= 0:
			continue
		var unit_type: String = stack.get("type", "pikeman")
		var unit_data: Dictionary = UNIT_TYPES.get(unit_type, {})
		var per_hp: int = unit_data.get("hp", stack.get("hp", 10))
		total_hp += count * per_hp
		total_attack += unit_data.get("attack", stack.get("attack", 5))
		total_defense += unit_data.get("defense", stack.get("defense", 5))
		name_parts.append(unit_data.get("name", unit_type))
	
	if army.is_empty():
		return [{"type": "enemy", "name": "Ennemi", "hp": 30, "max_hp": 30, "attack": 5, "defense": 3, "magic_res": 2}]
	
	var avg_attack: int = ceili(float(total_attack) / float(army.size()))
	var avg_defense: int = ceili(float(total_defense) / float(army.size()))
	var enemy_name: String = "Armée ennemie"
	if name_parts.size() > 0:
		enemy_name = name_parts[0] if name_parts.size() == 1 else "Horde ennemie"
	
	return [{
		"type": "enemy",
		"name": enemy_name,
		"hp": total_hp,
		"max_hp": total_hp,
		"attack": avg_attack,
		"defense": avg_defense,
		"magic_res": 2,
	}]

func _combat_units_to_army(combat_units: Array) -> Array:
	return []

func _enemy_army_to_army(enemy_index: int) -> GameData.Army:
	var army := GameData.Army.new()
	var old_army: Array = _enemy_armies[enemy_index] if enemy_index >= 0 and enemy_index < _enemy_armies.size() else []
	if old_army.is_empty():
		army.add_stack("goblin", 10)
		army.add_stack("bandit", 5)
		return army
	var unit_map := {
		"pikeman": "ashigaru", "archer": "archer", "griffin": "samurai",
		"swordsman": "oni_brute", "cavalier": "cavalry", "angel": "oni_mage"
	}
	for stack in old_army:
		var old_type: String = stack.get("type", "pikeman")
		var new_type: String = unit_map.get(old_type, "ashigaru")
		var count: int = stack.get("count", 5)
		army.add_stack(new_type, count)
	return army

func _build_hero_combat_units() -> Array:
	var hero_name: String = _get_active_hero_name()
	# Combat 1v1 : un seul héros
	return [{
		"type": "hero",
		"name": hero_name,
		"hp": _hero_hp,
		"max_hp": _hero_max_hp,
		"attack": _hero_attack,
		"defense": _hero_defense,
		"magic": 10,
		"magic_res": 4,
		"is_hero": true,
	}]

func _on_wanderer_clicked(index: int) -> void:
	if _in_combat or _llm_dialogue_screen:
		return
	_start_enemy_dialogue(index)

func _start_combat(enemy_index: int) -> void:
	if _in_combat:
		return
	
	_in_combat = true
	_in_boss_fight = false
	_current_enemy_index = enemy_index
	_current_boss_index = -1
	var map_enemy: Dictionary = _enemies[enemy_index] if enemy_index < _enemies.size() else {}
	
	print("⚔️ COMBAT TACTIQUE ! vs ", map_enemy.get("name", "ennemi"))
	
	# Utiliser le combat tactique (HoMM3-style)
	if _tactical_combat:
		var hero_army: GameData.Army = GameData.heroes[0].army if GameData.heroes.size() > 0 else null
		if hero_army == null or hero_army.stacks.is_empty():
			hero_army = GameData.Army.new()
			hero_army.add_stack("ashigaru", 5)
		var enemy_army: GameData.Army = _enemy_army_to_army(enemy_index)
		_tactical_combat.start_combat(hero_army, enemy_army)
	else:
		_in_combat = false
		print("ERREUR: Combat Tactique non initialisé !")

func _start_boss_fight(boss_index: int) -> void:
	if _in_combat:
		return
	
	_in_combat = true
	_in_boss_fight = true
	_current_boss_index = boss_index
	_current_enemy_index = -1
	var boss_data: Dictionary = _bosses[boss_index]
	var boss_army: Array = boss_data.get("army", [])
	
	print("⚔️ COMBAT CONTRE LE BOSS ! ", boss_data.get("name", "Boss"))
	
	if _combat_manager:
		var hero_data: Dictionary = {
			"units": _build_hero_combat_units(),
			"name": _get_active_hero_name(),
		}
		var enemy_units: Array = []
		var total_hp: int = 0
		var total_atk: int = 0
		var total_def: int = 0
		for stack in boss_army:
			var unit_type: String = stack.get("type", "swordsman")
			var unit_data: Dictionary = UNIT_TYPES.get(unit_type, {})
			var count: int = stack.get("count", 5)
			var per_hp: int = unit_data.get("hp", 20)
			total_hp += count * per_hp
			total_atk += unit_data.get("attack", 12)
			total_def += unit_data.get("defense", 10)
		var avg_atk: int = ceili(float(total_atk) / max(1, boss_army.size()))
		var avg_def: int = ceili(float(total_def) / max(1, boss_army.size()))
		if boss_army.is_empty():
			total_hp = boss_data.get("boss_hp", 100)
			avg_atk = boss_data.get("boss_attack", 15)
			avg_def = boss_data.get("boss_defense", 10)
		enemy_units.append({
			"type": "boss",
			"name": boss_data.get("name", "Boss"),
			"hp": total_hp,
			"max_hp": total_hp,
			"attack": avg_atk,
			"defense": avg_def,
			"magic_res": 8,
		})
		var enemy_data: Dictionary = {
			"units": enemy_units,
			"name": boss_data.get("name", "Boss"),
			"gold": boss_data.get("gold_reward", 1500),
			"xp": boss_data.get("xp_reward", 500),
		}
		_combat_manager.start_combat(hero_data, enemy_data, -1)
	else:
		_in_combat = false
		print("ERREUR: Combat Manager non initialisé !")

func _count_total_units(army: Array) -> int:
	var total: int = 0
	for unit in army:
		total += unit["count"]
	return total

func _find_alive_unit(army: Array):
	for unit in army:
		if unit["count"] > 0:
			return unit
	return null

func _print_army_status(army_name: String, army: Array) -> void:
	print("   ", army_name, " armée:")
	for unit in army:
		if unit["count"] > 0:
			print("      ", unit["count"], " ", UNIT_TYPES[unit["type"]]["name"])

func _on_combat_ended(won: bool) -> void:
	# Synchroniser l'armée du héros depuis GameData (modifiée par le combat tactique)
	if GameData.heroes.size() > 0:
		_hero_army = GameData.heroes[0].army.stacks
		# Mettre à jour _heroes_data pour compatibilité
		if _active_hero_index >= 0 and _active_hero_index < _heroes_data.size():
			_heroes_data[_active_hero_index]["hp"] = _hero_hp
			_heroes_data[_active_hero_index]["max_hp"] = _hero_max_hp
	if not won:
		_hero_hp = 0
	_in_combat = false
	_in_boss_fight = false
	if won and _hero_hp <= 0:
		_trigger_game_over(false, "Victoire sans survivants — campagne terminée.")

func _on_combat_victory(gold_reward: int, xp_reward: int) -> void:
	print("🎉 VICTOIRE ! +", gold_reward, " Or, +", xp_reward, " XP")
	
	if _in_boss_fight:
		# === VICTOIRE SUR UN BOSS ===
		if _current_boss_index < 0 or _current_boss_index >= _bosses.size():
			_in_boss_fight = false
			return
		
		var boss_data: Dictionary = _bosses[_current_boss_index]
		boss_data["alive"] = false
		
		_create_floating_text("☠️ BOSS VAINCU!", Color(0.9, 0.1, 0.1), boss_data["position"] - Vector2(0, 30))
		_create_floating_text("+" + str(gold_reward) + " 🪙", Color(1.0, 0.85, 0.2), _hero.position - Vector2(0, 40))
		
		_gold += gold_reward
		_update_resource_labels()
		
		var total_xp: int = xp_reward + XP_KILL_ENEMY
		_gain_xp(total_xp)
		
		# Death animation du boss
		_spawn_burst_particles(boss_data["position"], Color(0.9, 0.1, 0.1), 20)
		if _current_boss_index < _boss_visuals.size():
			var boss_node: Node2D = _boss_visuals[_current_boss_index]
			var dt = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			dt.tween_property(boss_node, "scale", Vector2(2.0, 2.0), 0.4)
			dt.parallel().tween_property(boss_node, "modulate:a", 0.0, 0.4)
			dt.tween_callback(func(): boss_node.visible = false)
		_refresh_minimap()
		
		# Débloquer un nouveau héros !
		var hero_unlock: Dictionary = boss_data.get("hero_unlock", {})
		if not hero_unlock.is_empty():
			_unlocked_heroes.append(hero_unlock)
			GameData.unlocked_heroes.append(hero_unlock.get("name", "Heros"))
			GameData.bosses_defeated += 1
			var hero_name: String = hero_unlock.get("name", "Inconnu")
			_create_floating_text("★ " + hero_name + " vous rejoint!", Color(1.0, 0.85, 0.2), _hero.position - Vector2(0, 80))
			print("★ Nouveau héros débloqué : ", hero_name)
			_add_unlocked_hero_node(hero_unlock)
			_update_hud_hero_buttons()
		
		_in_boss_fight = false
		_check_boss_victory()
	else:
		# === VICTOIRE SUR UN ENNEMI ERRANT ===
		if _current_enemy_index < 0 or _current_enemy_index >= _enemies.size():
			return
		
		var enemy_data: Dictionary = _enemies[_current_enemy_index]
		enemy_data["alive"] = false
		
		_create_floating_text("☠️ VAINCU!", Color(0.9, 0.1, 0.1), enemy_data["position"] - Vector2(0, 30))
		_create_floating_text("+" + str(gold_reward) + " 🪙", Color(1.0, 0.85, 0.2), _hero.position - Vector2(0, 40))
		
		_gold += gold_reward
		_update_resource_labels()
		
		var total_xp: int = xp_reward + XP_KILL_ENEMY
		_gain_xp(total_xp)
		
		_spawn_burst_particles(enemy_data["position"], Color(0.8, 0.1, 0.1), 12)
		if _current_enemy_index < _enemy_visuals.size():
			var enemy_node: Node2D = _enemy_visuals[_current_enemy_index]
			var dt = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			dt.tween_property(enemy_node, "scale", Vector2(1.5, 1.5), 0.3)
			dt.parallel().tween_property(enemy_node, "modulate:a", 0.0, 0.3)
			dt.tween_callback(func(): enemy_node.visible = false)
		_refresh_minimap()
		_check_quest("q_warrior")
	
	# Mettre à jour l'XP générale après chaque combat
	_update_hero_panel()

func _check_boss_victory() -> void:
	for boss_data in _bosses:
		if boss_data.get("alive", true):
			return
	_trigger_game_over(true, "Vous avez vaincu tous les boss !\nLa région est libérée !\n\n★ Tous les héros sont débloqués ★")

func _on_combat_defeat() -> void:
	print("💀 DÉFAITE !")
	_hero_army = []
	if GameData.heroes.size() > 0:
		GameData.heroes[0].army.stacks.clear()
	_hero_hp = 0
	_in_boss_fight = false
	_update_hero_panel()
	_trigger_game_over(false, "Votre armée a été vaincue.\nLa campagne est terminée.")

func _on_combat_fled() -> void:
	print("🏃 Fuite reussie !")
	_in_combat = false
	_in_boss_fight = false
	# Synchroniser l'armée (peut avoir perdu des unités pendant le combat)
	if GameData.heroes.size() > 0:
		_hero_army = GameData.heroes[0].army.stacks


# ---------------------------------------------------------------
# Dialogue LLM avec les ennemis
# ---------------------------------------------------------------

func _start_enemy_dialogue(enemy_index: int, is_boss: bool = false) -> void:
	if _in_combat or _llm_dialogue_screen:
		return

	var map_enemy: Dictionary
	var is_boss_actual: bool = is_boss
	if is_boss_actual:
		map_enemy = _bosses[enemy_index] if enemy_index < _bosses.size() else {}
	else:
		map_enemy = _enemies[enemy_index] if enemy_index < _enemies.size() else {}

	if not map_enemy.get("alive", true):
		return

	_current_enemy_index = enemy_index
	_current_boss_index = enemy_index if is_boss_actual else -1

	if not _llm_client or not _llm_client.is_ready():
		_create_floating_text("⚠ Dialogue simplifié", Color(0.9, 0.9, 0.3), _hero.position)
		_start_fallback_dialogue(map_enemy, enemy_index, is_boss_actual)
		return

	var personalities = preload("res://scripts/llm/llm_enemy_personalities.gd")
	var personality: Dictionary = personalities.get_personality(enemy_index, map_enemy.get("name", "Ennemi"))

	var player_history := GameData.get_player_history_dict(
		_hero_level, _hero_hp, _hero_attack, _hero_defense, _gold
	)

	_llm_dialogue_screen = LLMDialogueScreen.new()
	_llm_dialogue_screen.dialogue_ended.connect(_on_dialogue_ended)
	add_child(_llm_dialogue_screen)

	_llm_dialogue_screen.start_dialogue(map_enemy, personality, player_history, _llm_client)


func _make_fallback_choice(action: String, overlay: Panel, map_enemy: Dictionary, is_boss: bool, flee_chance: int, help_chance: int) -> Callable:
	return func():
		var outcome_action: String = action
		var roll: int = rng.randi_range(0, 100)

		if action == "flee" and roll > flee_chance:
			outcome_action = "attack"
		elif action == "help" and roll > help_chance:
			outcome_action = "attack"

		_overlay_dialogue_close(overlay)
		_on_dialogue_ended({
			"action": outcome_action,
			"enemy_data": map_enemy,
			"is_boss": is_boss,
		})


func _start_fallback_dialogue(map_enemy: Dictionary, enemy_index: int, is_boss: bool) -> void:
	print("⚠ LLM non configuré — dialogue simplifié")
	var enemy_name: String = map_enemy.get("name", "Ennemi")

	var screen_size := get_viewport().get_visible_rect().size
	var margin := screen_size.x * 0.05

	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	var overlay := Panel.new()
	overlay.position = Vector2.ZERO
	overlay.size = screen_size
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.92)
	overlay.add_theme_stylebox_override("panel", style)
	layer.add_child(overlay)

	var title := Label.new()
	title.text = "🗣 " + enemy_name
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.position = Vector2(margin, 40)
	title.size = Vector2(screen_size.x - margin * 2, 40)
	overlay.add_child(title)

	var mood_options := [
		"agressif",
		"méfiant",
		"neutre",
		"amical",
		"effrayé",
	]
	var mood: String = mood_options[enemy_index % mood_options.size()]
	var subtitle := Label.new()
	subtitle.text = "Humeur : " + mood
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	subtitle.position = Vector2(margin, 76)
	subtitle.size = Vector2(screen_size.x - margin * 2, 28)
	overlay.add_child(subtitle)

	var dialog_text := Label.new()
	dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_text.add_theme_font_size_override("font_size", 18)
	dialog_text.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	dialog_text.position = Vector2(margin, 120)
	dialog_text.size = Vector2(screen_size.x - margin * 2, screen_size.y - 320)
	overlay.add_child(dialog_text)

	var greetings := [
		"Que fais-tu sur mes terres, voyageur ?",
		"Encore un intrus... Que veux-tu ?",
		"Oh, un visiteur ! Je ne vais pas te manger... peut-être.",
		"Tu as du courage pour venir jusqu'ici.",
		"S-s'il te plaît, ne me fais pas de mal...",
	]
	dialog_text.text = greetings[enemy_index % greetings.size()]

	var choices_container := VBoxContainer.new()
	choices_container.position = Vector2(margin, screen_size.y - 180)
	choices_container.size = Vector2(screen_size.x - margin * 2, 130)
	overlay.add_child(choices_container)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.25, 0.35)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6

	var heroes_killed: int = GameData.enemies_killed
	var heroes_spared: int = GameData.enemies_spared

	var choices := [
		{
			"text": "😤 \"Dégage de mon chemin ou je te réduis en miettes !\"",
			"action": "attack",
		},
		{
			"text": "🤝 \"Je ne cherche pas la bagarre. Laissons-nous passer.\"",
			"action": "flee",
		},
		{
			"text": "💰 \"J'ai de l'or. Peut-être qu'on peut s'arranger ?\"",
			"action": "help",
		},
	]

	# Ajuster les chances selon l'historique
	var aggression_bonus: int = heroes_killed - heroes_spared * 2
	var flee_chance: int = 40 - aggression_bonus * 5
	var help_chance: int = 20 + heroes_spared * 5 - heroes_killed * 3
	var attack_chance: int = 40 + aggression_bonus * 5

	attack_chance = clampi(attack_chance, 10, 80)
	flee_chance = clampi(flee_chance, 10, 60)
	help_chance = clampi(help_chance, 5, 50)

	for c in choices:
		var btn := Button.new()
		btn.text = c.text
		btn.custom_minimum_size = Vector2(0, 38)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_stylebox_override("normal", btn_style)
		btn.pressed.connect(_make_fallback_choice(c.action, overlay, map_enemy, is_boss, flee_chance, help_chance))
		choices_container.add_child(btn)

	var close_btn := Button.new()
	close_btn.text = "✕ Fermer (attaquer)"
	close_btn.custom_minimum_size = Vector2(0, 32)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
	close_btn.pressed.connect(func():
		_overlay_dialogue_close(overlay)
		_on_dialogue_ended({
			"action": "attack",
			"enemy_data": map_enemy,
			"is_boss": is_boss,
		})
	)
	overlay.add_child(close_btn)
	close_btn.position = Vector2(screen_size.x - margin - 180, 8)
	close_btn.size = Vector2(170, 32)

	_fallback_dialogue_overlay = overlay


func _overlay_dialogue_close(overlay: Panel) -> void:
	if overlay and is_instance_valid(overlay):
		var parent = overlay.get_parent()
		if parent and is_instance_valid(parent):
			parent.queue_free()
		else:
			overlay.queue_free()
	_fallback_dialogue_overlay = null


func _on_dialogue_ended(outcome: Dictionary) -> void:
	var action: String = outcome.get("action", "attack")
	var enemy_index: int = _current_enemy_index
	var is_boss: bool = outcome.get("is_boss", false) or _current_boss_index >= 0

	_cleanup_dialogue()

	if _in_combat:
		return

	match action:
		"attack":
			print("⚔️ Dialogue → COMBAT !")
			GameData.track_action("A combattu " + ("un boss" if is_boss else "un ennemi"))
			if is_boss:
				_start_boss_fight(enemy_index)
			else:
				GameData.enemies_killed += 1
				_start_combat(enemy_index)

		"flee":
			print("🏃 Dialogue → l'ennemi fuit !")
			GameData.enemies_spared += 1
			GameData.track_action("A épargné " + ("un boss" if is_boss else "un ennemi") + " qui a fui")
			if is_boss:
				_resolve_boss_defeated(enemy_index, 0, 0)
			else:
				_resolve_enemy_defeated(enemy_index, 0, 0)

		"help":
			print("⭐ Dialogue → l'ennemi aide !")
			GameData.enemies_spared += 1
			GameData.track_action("Un " + ("boss" if is_boss else "ennemi") + " a offert son aide")
			var bonus_gold: int = rng.randi_range(10, 40) * (3 if is_boss else 1)
			var bonus_xp: int = rng.randi_range(10, 30) * (3 if is_boss else 1)
			_gold += bonus_gold
			_update_resource_labels()
			_create_floating_text("+" + str(bonus_gold) + " 🪙 Aide!", Color(0.3, 1.0, 0.3), _hero.position)
			_gain_xp(bonus_xp)
			if is_boss:
				_resolve_boss_defeated(enemy_index, bonus_gold, bonus_xp)
			else:
				_resolve_enemy_defeated(enemy_index, bonus_gold, bonus_xp)

		_:
			print("⚔️ Dialogue → issue inconnue, combat par défaut")
			if is_boss:
				_start_boss_fight(enemy_index)
			else:
				GameData.enemies_killed += 1
				_start_combat(enemy_index)


func _cleanup_dialogue() -> void:
	if _llm_dialogue_screen:
		if _llm_dialogue_screen.dialogue_ended.is_connected(_on_dialogue_ended):
			_llm_dialogue_screen.dialogue_ended.disconnect(_on_dialogue_ended)
		_llm_dialogue_screen.queue_free()
		_llm_dialogue_screen = null
	if _fallback_dialogue_overlay:
		_overlay_dialogue_close(_fallback_dialogue_overlay)


func _resolve_enemy_defeated(enemy_index: int, extra_gold: int, extra_xp: int) -> void:
	if enemy_index < 0 or enemy_index >= _enemies.size():
		return

	var enemy_data: Dictionary = _enemies[enemy_index]
	enemy_data["alive"] = false

	_create_floating_text("☠️ Disparu!", Color(0.7, 0.7, 0.7), enemy_data["position"] - Vector2(0, 30))

	if enemy_index < _enemy_visuals.size():
		var enemy_node: Node2D = _enemy_visuals[enemy_index]
		var dt := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		dt.tween_property(enemy_node, "scale", Vector2(1.5, 1.5), 0.3)
		dt.parallel().tween_property(enemy_node, "modulate:a", 0.0, 0.3)
		dt.tween_callback(func(): enemy_node.visible = false)

	_refresh_minimap()


func _resolve_boss_defeated(boss_index: int, extra_gold: int, extra_xp: int) -> void:
	if boss_index < 0 or boss_index >= _bosses.size():
		return

	var boss_data: Dictionary = _bosses[boss_index]
	boss_data["alive"] = false

	_create_floating_text("💀 Boss vaincu !", Color(1, 0.6, 0), boss_data["position"] - Vector2(0, 30))

	var hero_unlock: Dictionary = boss_data.get("hero_unlock", {})
	if not hero_unlock.is_empty():
		var hero_name: String = hero_unlock.get("name", "")
		if not hero_name.is_empty() and not GameData.unlocked_heroes.has(hero_name):
			GameData.unlocked_heroes.append(hero_name)
			_create_floating_text("⭐ " + hero_name + " débloqué !", Color(0.4, 1.0, 0.4), boss_data["position"] - Vector2(0, 60))

	GameData.bosses_defeated += 1

	_refresh_minimap()


func _on_surrender_pressed() -> void:
	_trigger_game_over(false, "Vous avez abandonné la campagne.")

func _trigger_game_over(victory: bool, message: String) -> void:
	if _game_over_active:
		return
	_game_over_active = true
	set_process(false)
	_in_combat = false
	_town_screen_open = false
	if _town_overlay:
		_town_overlay.visible = false
	if _combat_manager:
		_combat_manager.visible = false
	_show_game_overlay(victory, message)

func _show_game_overlay(victory: bool, message: String) -> void:
	if _game_over_layer == null:
		_game_over_layer = CanvasLayer.new()
		_game_over_layer.name = "GameOverLayer"
		_game_over_layer.layer = 100
		add_child(_game_over_layer)
	else:
		for child in _game_over_layer.get_children():
			child.queue_free()

	var root := Control.new()
	root.name = "GameOverRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over_layer.add_child(root)
	_game_overlay = root

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.90)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(560, 320)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280.0
	panel.offset_top = -160.0
	panel.offset_right = 280.0
	panel.offset_bottom = 160.0
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.8, 0.8)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.05, 0.04, 0.95)
	if victory:
		panel_style.border_color = Color(0.85, 0.72, 0.18)
	else:
		panel_style.border_color = Color(0.70, 0.12, 0.12)
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.shadow_color = Color(0, 0, 0, 0.60)
	panel_style.shadow_size = 30
	panel_style.shadow_offset = Vector2(0, 10)
	panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(panel)

	# Decorative top bar
	var deco_top := ColorRect.new()
	deco_top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	deco_top.size = Vector2(560, 70)
	deco_top.position = Vector2(-280, 0)
	if victory:
		deco_top.color = Color(0.15, 0.10, 0.02, 0.90)
	else:
		deco_top.color = Color(0.18, 0.04, 0.03, 0.90)
	deco_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(deco_top)

	# Accent line
	var accent_line := ColorRect.new()
	accent_line.set_anchors_preset(Control.PRESET_CENTER_TOP)
	accent_line.size = Vector2(560, 3)
	accent_line.position = Vector2(-280, 67)
	if victory:
		accent_line.color = Color(0.85, 0.72, 0.18)
	else:
		accent_line.color = Color(0.70, 0.12, 0.12)
	panel.add_child(accent_line)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 28.0
	box.offset_top = 20.0
	box.offset_right = -28.0
	box.offset_bottom = -24.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	# Title with larger size
	var title := Label.new()
	title.text = "VICTOIRE !" if victory else "DÉFAITE..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	if victory:
		title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.20))
	else:
		title.add_theme_color_override("font_color", Color(0.92, 0.28, 0.22))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.60))
	box.add_child(title)

	# Description
	var desc := Label.new()
	desc.text = message
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(480, 0)
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.90, 0.86, 0.78))
	box.add_child(desc)

	# Spacer
	var spacer := ColorRect.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	# Button with improved style
	var btn := Button.new()
	btn.text = "Retour au menu"
	btn.custom_minimum_size = Vector2(260, 50)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.18, 0.14, 0.10)
	if victory:
		btn_style.border_color = Color(0.85, 0.72, 0.18)
	else:
		btn_style.border_color = Color(0.70, 0.20, 0.18)
	btn_style.border_width_left = 1
	btn_style.border_width_right = 1
	btn_style.border_width_top = 1
	btn_style.border_width_bottom = 3
	btn_style.corner_radius_top_left = 14
	btn_style.corner_radius_top_right = 14
	btn_style.corner_radius_bottom_left = 14
	btn_style.corner_radius_bottom_right = 14
	btn_style.shadow_color = Color(0, 0, 0, 0.50)
	btn_style.shadow_size = 8
	btn_style.shadow_offset = Vector2(0, 3)
	btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.26, 0.20, 0.14)
	if victory:
		btn_hover.border_color = Color(0.95, 0.82, 0.28)
	else:
		btn_hover.border_color = Color(0.85, 0.30, 0.25)
	btn_hover.border_width_left = 1
	btn_hover.border_width_right = 1
	btn_hover.border_width_top = 1
	btn_hover.border_width_bottom = 3
	btn_hover.corner_radius_top_left = 14
	btn_hover.corner_radius_top_right = 14
	btn_hover.corner_radius_bottom_left = 14
	btn_hover.corner_radius_bottom_right = 14
	btn_hover.shadow_color = Color(0, 0, 0, 0.60)
	btn_hover.shadow_size = 10
	btn_hover.shadow_offset = Vector2(0, 4)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	box.add_child(btn)

	# Entrance animation
	var pt = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	pt.tween_property(panel, "modulate:a", 1.0, 0.5)
	pt.parallel().tween_property(panel, "scale", Vector2(1.0, 1.0), 0.5)

func _victory_combat(_enemy_index: int, _enemy_data: Dictionary) -> void:
	# OBSOLETE - remplacé par _on_combat_victory
	pass

func _combat_round(_enemy_index: int) -> void:
	# OBSOLETE - remplacé par le CombatManager
	pass

func _check_city_visit() -> void:
	var city_keys: Array = MAJOR_CITIES.keys()
	for i in range(_cities.size()):
		var city_pos: Vector2 = _cities[i]
		var distance: float = _hero.position.distance_to(city_pos)
		if distance < TILE_SIZE:
			if i != _last_city_visit_index:
				_last_city_visit_index = i
				var city_name: String = _cities_data[i].get("name", "Ville " + str(i + 1))

				if not _visited_cities.get(i, false):
					print("🏛️ Visite de ", city_name, " !")
					_add_units_to_army("ashigaru", 8)
					_add_units_to_army("archer", 4)
					_create_floating_text("Renforts ! +8 Ashigaru +4 Archers", Color(0.5, 0.9, 0.5), _hero.position)
					
					# Révéler le brouillard autour de la ville
					var city_tile: Vector2i = _cities_data[i].get("tile", Vector2i(
						int(city_pos.x / TILE_SIZE),
						int(city_pos.y / TILE_SIZE)
					))
					_reveal_fog_around_pos(city_tile, 5)

			_open_town_screen(i)
			return
	_last_city_visit_index = -1

func _open_town_screen(city_index: int) -> void:
	if _town_screen_open or _town_overlay == null or _merchant_screen_open:
		return
	_town_screen_open = true
	_selected_city_index = city_index
	var city_name: String = _cities_data[city_index].get("name", "Ville " + str(city_index + 1))
	if _town_title_label:
		_town_title_label.text = city_name
	_town_overlay.visible = true
	_refresh_town_ui()

	# Ouvrir aussi le CityManager moderne si le script est disponible
	var cm_path := "res://scripts/city_manager.gd"
	if ResourceLoader.exists(cm_path):
		var city_mgr: Node = load(cm_path).new()
		city_mgr.name = "CityManagerInstance"
		city_mgr.open_city(city_index, _gold, _wood, _ore)
		city_mgr.city_closed.connect(func():
			_close_town_screen()
		)
		add_child(city_mgr)

	if not _visited_cities.get(city_index, false):
		_visited_cities[city_index] = true
		_gain_xp(XP_VISIT_CITY)
		_create_floating_text(city_name + " decouverte!", Color(0.7, 0.85, 1.0), _hero.position)
		_check_quest("q_explorer")

func _close_town_screen() -> void:
	_town_screen_open = false
	_selected_city_index = -1
	_last_city_visit_index = -1
	if _town_overlay:
		_town_overlay.visible = false
	# Nettoyer le CityManager moderne s'il existe
	var cm_node = get_node_or_null("CityManagerInstance")
	if cm_node:
		cm_node.queue_free()

func _on_town_recruit(unit_type: String, count: int) -> void:
	if _selected_city_index >= 0:
		_recruit_unit(_selected_city_index, unit_type, count)

func _on_town_build(building_key: String) -> void:
	if _selected_city_index >= 0:
		_build_city_building(_selected_city_index, building_key)

func _build_city_building(city_index: int, building_key: String) -> void:
	"""Construit un bâtiment dans une ville"""
	var city_data: Dictionary = _cities_data[city_index]
	
	if building_key in city_data["buildings"]:
		print("⛔ Déjà construit !")
		return
	
	var b_data: Dictionary = CITY_BUILDINGS[building_key]
	
	# Vérifier les ressources
	if _gold < b_data["cost_g"] or _wood < b_data["cost_w"] or _ore < b_data["cost_o"]:
		print("⛔ Ressources insuffantes !")
		print("   Besoin: ", b_data["cost_g"], "🪙, ", b_data["cost_w"], "🪵, ", b_data["cost_o"], "💎")
		print("   Vous avez: ", _gold, "🪙, ", _wood, "🪵, ", _ore, "💎")
		return
	
	# Payer
	_gold -= b_data["cost_g"]
	_wood -= b_data["cost_w"]
	_ore -= b_data["cost_o"]
	city_data["buildings"].append(building_key)
	
	# Effets spéciaux
	if building_key == "town_hall":
		city_data["income"] += 750
	
	print("✅ ", b_data["name"], " construit !")
	_create_floating_text("+" + b_data["name"], Color(0.5, 0.9, 0.5), _cities[city_index])
	_check_quest("q_builder")
	
	# Mettre à jour l'UI
	if _label_gold:
		_label_gold.text = str(_gold)
	if _label_wood:
		_label_wood.text = str(_wood)
	if _label_ore:
		_label_ore.text = str(_ore)
	if _town_screen_open:
		_refresh_town_ui()

func _recruit_unit(city_index: int, unit_type: String, count: int) -> void:
	"""Recrute des unités dans une ville"""
	var city_data: Dictionary = _cities_data[city_index]
	var unit_data: Dictionary = UNIT_TYPES[unit_type]
	var total_cost: int = unit_data["cost_g"] * count
	
	if _gold < total_cost:
		print("⛔ Pas assez d'or ! Besoin: ", total_cost, "🪙")
		return
	
	# Vérifier si le bâtiment nécessaire existe
	var required_building: String = ""
	match unit_type:
		"pikeman": required_building = "barracks"
		"archer": required_building = "archery_range"
		"griffin": required_building = "griffin_tower"
		"swordsman": required_building = "training_ground"
		"cavalier": required_building = "stables"
		"angel": required_building = "angel_statue"
	
	if required_building != "" and not required_building in city_data["buildings"]:
		print("⛔ Bâtiment requis: ", CITY_BUILDINGS[required_building]["name"])
		return
	
	# Payer et recruter
	_gold -= total_cost
	
	# Ajouter à l'armée du héros ou à la garnison
	var found: bool = false
	for unit in _hero_army:
		if unit["type"] == unit_type:
			unit["count"] += count
			found = true
			break
	
	if not found:
		_hero_army.append({
			"type": unit_type,
			"count": count,
			"hp": unit_data["hp"],
			"attack": unit_data["attack"],
			"defense": unit_data["defense"]
		})
	
	print("✅ ", count, " ", unit_data["name"], " recrutés !")
	_create_floating_text("+" + str(count) + " " + unit_data["name"], Color(0.5, 0.7, 1.0), _hero.position)
	_check_quest("q_army", count)
	
	# Mettre à jour l'UI
	if _label_gold:
		_label_gold.text = str(_gold)
	if _label_wood:
		_label_wood.text = str(_wood)
	if _label_ore:
		_label_ore.text = str(_ore)
	if _town_screen_open:
		_refresh_town_ui()

func _create_town_overlay() -> void:
	_town_overlay = Panel.new()
	_town_overlay.name = "TownOverlay"
	_town_overlay.visible = false
	_town_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_town_overlay.custom_minimum_size = Vector2(min(580, int(_get_viewport_size().x * 0.9)), min(800, int(_get_viewport_size().y * 0.85)))
	var jap_theme := JapaneseUITheme.new()
	_town_overlay.add_theme_stylebox_override("panel", JapaneseUITheme.panel_style(12))
	add_child(_town_overlay)

	var margin := 12
	var main_vbox := VBoxContainer.new()
	main_vbox.position = Vector2(margin, margin)
	main_vbox.custom_minimum_size = _town_overlay.custom_minimum_size - Vector2(margin * 2, margin * 2)
	main_vbox.add_theme_constant_override("separation", 6)
	_town_overlay.add_child(main_vbox)

	_town_title_label = Label.new()
	_town_title_label.text = "Ville"
	_town_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_town_title_label.add_theme_font_size_override("font_size", 22)
	_town_title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	main_vbox.add_child(_town_title_label)

	var res_label := Label.new()
	res_label.name = "TownResLabel"
	res_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_label.add_theme_font_size_override("font_size", 14)
	res_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	main_vbox.add_child(res_label)
	_town_res_label = res_label

	var tab_container := TabContainer.new()
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	main_vbox.add_child(tab_container)

	var recruit_tab := VBoxContainer.new()
	recruit_tab.name = "Recrutement"
	recruit_tab.add_theme_constant_override("separation", 4)
	tab_container.add_child(recruit_tab)
	_town_recruit_container = recruit_tab

	var build_tab := VBoxContainer.new()
	build_tab.name = "Construction"
	build_tab.add_theme_constant_override("separation", 4)
	tab_container.add_child(build_tab)
	_town_build_container = build_tab

	var garrison_tab := VBoxContainer.new()
	garrison_tab.name = "Garnison"
	garrison_tab.add_theme_constant_override("separation", 4)
	tab_container.add_child(garrison_tab)
	_town_garrison_label = Label.new()
	_town_garrison_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_town_garrison_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garrison_tab.add_child(_town_garrison_label)

	var btn_close := Button.new()
	btn_close.text = "Fermer"
	btn_close.custom_minimum_size = Vector2(0, 36)
	btn_close.pressed.connect(_close_town_screen)
	JapaneseUITheme.style_button(btn_close)
	JapaneseUITheme.add_hover_scale(btn_close)
	main_vbox.add_child(btn_close)

func _refresh_town_ui() -> void:
	if _selected_city_index < 0 or _selected_city_index >= _cities_data.size():
		return
	var city_data: Dictionary = _cities_data[_selected_city_index]
	if _town_res_label:
		_town_res_label.text = "Or: %d  Bois: %d  Minerai: %d" % [_gold, _wood, _ore]

	# Vidanger et remplir les onglets
	if not _town_recruit_container:
		return

	# Recrutement
	for c in _town_recruit_container.get_children():
		c.queue_free()
	for u_key in UNIT_TYPES:
		var u_data: Dictionary = UNIT_TYPES[u_key]
		var req_building: String = ""
		match u_key:
			"pikeman": req_building = "barracks"
			"archer": req_building = "archery_range"
			"griffin": req_building = "griffin_tower"
			"swordsman": req_building = "training_ground"
			"cavalier": req_building = "stables"
			"angel": req_building = "angel_statue"
		if req_building != "" and not req_building in city_data["buildings"]:
			continue
		var btn := Button.new()
		btn.text = "%s - %d or (x5)" % [u_data["name"], u_data["cost_g"] * 5]
		btn.pressed.connect(func(ut=u_key): _on_town_recruit(ut, 5))
		btn.disabled = _gold < u_data["cost_g"] * 5
		_town_recruit_container.add_child(btn)

	# Construction
	for c in _town_build_container.get_children():
		c.queue_free()
	for b_key in CITY_BUILDINGS:
		var b_data: Dictionary = CITY_BUILDINGS[b_key]
		var owned: bool = b_key in city_data["buildings"]
		var btn := Button.new()
		if owned:
			btn.text = "✅ %s (construit)" % b_data["name"]
			btn.disabled = true
		else:
			btn.text = "%s - %d or, %d bois, %d minerai" % [b_data["name"], b_data["cost_g"], b_data["cost_w"], b_data["cost_o"]]
			btn.pressed.connect(func(bk=b_key): _on_town_build(bk))
			btn.disabled = _gold < b_data["cost_g"] or _wood < b_data["cost_w"] or _ore < b_data["cost_o"]
		_town_build_container.add_child(btn)

	# Garnison
	if _town_garrison_label:
		var gtext: String = ""
		for unit in _hero_army:
			if gtext != "":
				gtext += "\n"
			gtext += "%s x%d" % [UNIT_TYPES.get(unit["type"], {}).get("name", unit["type"]), unit.get("count", 0)]
		if gtext == "":
			gtext = "Aucune troupe"
		_town_garrison_label.text = gtext

# ============================================================
# SYSTÈME MARCHANDS
# ============================================================

func _create_merchant_overlay() -> void:
	var merchant_layer := CanvasLayer.new()
	merchant_layer.name = "MerchantCanvasLayer"
	add_child(merchant_layer)

	_merchant_overlay = Panel.new()
	_merchant_overlay.name = "MerchantOverlay"
	_merchant_overlay.visible = false
	var overlay_size := Vector2(min(520, int(_get_viewport_size().x * 0.88)), min(640, int(_get_viewport_size().y * 0.78)))
	var vp_size := _get_viewport_size()
	_merchant_overlay.position = Vector2((vp_size.x - overlay_size.x) / 2, 190)
	_merchant_overlay.size = overlay_size
	_merchant_overlay.custom_minimum_size = overlay_size
	var jap_theme := JapaneseUITheme.new()
	_merchant_overlay.add_theme_stylebox_override("panel", JapaneseUITheme.panel_style(12))
	merchant_layer.add_child(_merchant_overlay)

	var margin := 12
	var main_vbox := VBoxContainer.new()
	main_vbox.position = Vector2(margin, margin)
	main_vbox.size = overlay_size - Vector2(margin * 2, margin * 2)
	main_vbox.add_theme_constant_override("separation", 8)
	_merchant_overlay.add_child(main_vbox)

	var top_hbox := HBoxContainer.new()
	main_vbox.add_child(top_hbox)

	_merchant_title_label = Label.new()
	_merchant_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merchant_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_merchant_title_label.add_theme_font_size_override("font_size", 22)
	_merchant_title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	top_hbox.add_child(_merchant_title_label)

	var btn_x := Button.new()
	btn_x.text = "✕"
	btn_x.custom_minimum_size = Vector2(32, 32)
	btn_x.pressed.connect(_close_merchant_screen)
	btn_x.add_theme_font_size_override("font_size", 18)
	btn_x.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2))
	var x_style := StyleBoxFlat.new()
	x_style.bg_color = Color(0.3, 0.1, 0.1, 0.6)
	x_style.border_width_left = 1
	x_style.border_width_right = 1
	x_style.border_width_top = 1
	x_style.border_width_bottom = 1
	x_style.border_color = Color(0.6, 0.2, 0.15)
	x_style.corner_radius_top_left = 4
	x_style.corner_radius_top_right = 4
	x_style.corner_radius_bottom_left = 4
	x_style.corner_radius_bottom_right = 4
	btn_x.add_theme_stylebox_override("normal", x_style)
	top_hbox.add_child(btn_x)

	var gold_label := Label.new()
	gold_label.name = "MerchantGoldLabel"
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	main_vbox.add_child(gold_label)

	_merchant_items_container = VBoxContainer.new()
	_merchant_items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merchant_items_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_merchant_items_container.add_theme_constant_override("separation", 6)
	main_vbox.add_child(_merchant_items_container)

	var btn_close := Button.new()
	btn_close.text = "Quitter la boutique"
	btn_close.custom_minimum_size = Vector2(0, 36)
	btn_close.pressed.connect(_close_merchant_screen)
	JapaneseUITheme.style_button(btn_close)
	JapaneseUITheme.add_hover_scale(btn_close)
	main_vbox.add_child(btn_close)

func _open_merchant_screen(index: int) -> void:
	if _merchant_screen_open or _merchant_overlay == null or _town_screen_open:
		return
	_merchant_screen_open = true
	_selected_merchant_index = index
	var merchant_data: Dictionary = _merchants[index]
	if _merchant_title_label:
		_merchant_title_label.text = "🏪 " + merchant_data.get("name", "Marchand")
	_merchant_overlay.visible = true
	_refresh_merchant_ui()
	print("🏪 Marchand ouvert : ", merchant_data.get("name", "?"))

func _close_merchant_screen() -> void:
	_merchant_screen_open = false
	_selected_merchant_index = -1
	_last_merchant_visit_index = -1
	if _merchant_overlay:
		_merchant_overlay.visible = false

func _refresh_merchant_ui() -> void:
	if _merchant_items_container == null or _selected_merchant_index < 0:
		return

	for c in _merchant_items_container.get_children():
		c.queue_free()

	var gold_lbl: Label = _merchant_overlay.get_node_or_null("MerchantGoldLabel")
	if gold_lbl:
		gold_lbl.text = "🪙 Or: %d" % _gold

	for item_key in MERCHANT_ITEMS:
		var item: Dictionary = MERCHANT_ITEMS[item_key]
		var already_owned: bool = false
		for owned in _player_items:
			if owned.get("item_id") == item_key:
				already_owned = true
				break

		var cost_str: String = ""
		if item.get("cost_w", 0) > 0:
			cost_str += str(item.cost_w) + "🪵 "
		if item.get("cost_o", 0) > 0:
			cost_str += str(item.cost_o) + "💎 "
		cost_str += str(item.cost) + "🪙"

		var btn := Button.new()
		if already_owned:
			btn.text = "%s %s — %s [ACHETÉ]" % [item.icon, item.name, item.desc]
			btn.disabled = true
		else:
			btn.text = "%s %s — %s (%s)" % [item.icon, item.name, item.desc, cost_str]
			btn.disabled = _gold < item.cost or _wood < item.get("cost_w", 0) or _ore < item.get("cost_o", 0)
			btn.pressed.connect(_on_merchant_item_pressed.bind(item_key))

		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.12, 0.10, 0.06)
		s.border_color = Color(0.45, 0.38, 0.22)
		s.border_width_left = 1
		s.border_width_right = 1
		s.border_width_top = 1
		s.border_width_bottom = 2
		s.corner_radius_top_left = 4
		s.corner_radius_top_right = 4
		s.corner_radius_bottom_left = 4
		s.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.8))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 42)
		_merchant_items_container.add_child(btn)

func _on_merchant_item_pressed(item_key: String) -> void:
	_buy_merchant_item(item_key)

func _buy_merchant_item(item_key: String) -> void:
	if _selected_merchant_index < 0:
		return
	var item: Dictionary = MERCHANT_ITEMS.get(item_key, {})
	var cost_w: int = item.get("cost_w", 0)
	var cost_o: int = item.get("cost_o", 0)
	if item.is_empty() or _gold < item.cost or _wood < cost_w or _ore < cost_o:
		return

	_gold -= item.cost
	_wood -= cost_w
	_ore -= cost_o
	_update_resource_labels()

	_player_items.append({"item_id": item_key, "effect": item.effect, "value": item.value})

	var msg: String = ""
	match item.effect:
		"attack":
			_hero_attack += item.value
			msg = "ATK +%d !" % item.value
			if _active_hero_index >= 0 and _active_hero_index < _heroes_data.size():
				_heroes_data[_active_hero_index]["attack"] = _hero_attack
		"defense":
			_hero_defense += item.value
			msg = "DEF +%d !" % item.value
			if _active_hero_index >= 0 and _active_hero_index < _heroes_data.size():
				_heroes_data[_active_hero_index]["defense"] = _hero_defense
		"spell_fire":
			msg = "🔥 Sort de feu acquis !"
		"spell_heal":
			_hero_hp = min(_hero_hp + item.value, _hero_max_hp)
			msg = "Soin +%d PV !" % item.value
			if _active_hero_index >= 0 and _active_hero_index < _heroes_data.size():
				_heroes_data[_active_hero_index]["hp"] = _hero_hp
		"compass":
			msg = "🧭 Boussole activée !"
			_close_merchant_screen()
			_reveal_nearest_boss()
		"water_walk":
			_water_walk_turns = item.value
			msg = "🌊 Marche sur l'eau (%d tours) !" % item.value

	_create_floating_text(msg, Color(0.5, 0.9, 0.5), _hero.position)
	print("✅ Achat: ", item.name, " — ", msg)
	_refresh_merchant_ui()

func _reveal_nearest_boss() -> void:
	var hero_tile: Vector2i = Vector2i(int(_hero.position.x / TILE_SIZE), int(_hero.position.y / TILE_SIZE))
	var nearest_dist: int = 9999
	var nearest_pos: Vector2 = Vector2.ZERO
	var nearest_name: String = ""
	for boss_data in _bosses:
		if not boss_data.get("alive", true):
			continue
		var b_tile: Vector2i = Vector2i(int(boss_data.position.x / TILE_SIZE), int(boss_data.position.y / TILE_SIZE))
		# Ignorer les boss déjà découverts (brouillard levé sur leur case)
		if b_tile.x >= 0 and b_tile.y >= 0 and b_tile.x < _zone_w and b_tile.y < _zone_h:
			if _fog_grid[b_tile.x][b_tile.y] >= 1:
				continue
		var d: int = absi(hero_tile.x - b_tile.x) + absi(hero_tile.y - b_tile.y)
		if d < nearest_dist:
			nearest_dist = d
			nearest_pos = boss_data.position
			nearest_name = boss_data.get("name", "Boss")
	if nearest_dist < 9999:
		var boss_tile: Vector2i = Vector2i(int(nearest_pos.x / TILE_SIZE), int(nearest_pos.y / TILE_SIZE))
		_reveal_fog_around_pos(boss_tile, 2)
		_add_compass_marker(nearest_pos)
		_create_floating_text("🧭 Boss: %s (%d cases)" % [nearest_name, nearest_dist], Color(1.0, 0.85, 0.2), _hero.position)
		_spawn_burst_particles(nearest_pos, Color(1.0, 0.85, 0.2), 6)
	else:
		_create_floating_text("🧭 Aucun boss vivant trouvé !", Color(1.0, 0.5, 0.2), _hero.position)

func _add_compass_marker(world_pos: Vector2) -> void:
	if _compass_marker != null and is_instance_valid(_compass_marker):
		_compass_marker.queue_free()
		_compass_marker = null

	_compass_marker = Sprite2D.new()
	_compass_marker.name = "CompassMarker"
	_compass_marker.position = world_pos
	_compass_marker.z_index = 100

	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for px in range(32):
		for py in range(32):
			var d: float = sqrt((px - 16)**2 + (py - 16)**2)
			if d < 14:
				img.set_pixel(px, py, Color(1.0, 0.85, 0.1, 0.8))
			elif d < 16:
				img.set_pixel(px, py, Color(1.0, 0.7, 0.1, 0.6))
	for ax in range(10, 23):
		for ay in range(2, 16):
			if absi(ax - 16) <= (ay - 2) / 2:
				img.set_pixel(ax, ay, Color(1.0, 0.95, 0.5, 0.9))
	_compass_marker.texture = ImageTexture.create_from_image(img)
	_compass_marker.scale = Vector2(2.0, 2.0)

	add_child(_compass_marker)

func _check_merchant_visit() -> void:
	for i in range(_merchants.size()):
		var m_pos: Vector2 = _merchants[i].position
		var distance: float = _hero.position.distance_to(m_pos)
		if distance < TILE_SIZE:
			if i != _last_merchant_visit_index:
				_last_merchant_visit_index = i
				var m_name: String = _merchants[i].get("name", "Marchand")
				if not _merchants[i].get("greeted", false):
					_merchants[i]["greeted"] = true
					_create_floating_text("🏪 " + m_name + " — Appuyez pour acheter", Color(0.9, 0.7, 0.3), _hero.position)
					print("🏪 Marchand visité : ", m_name)
			return
	_last_merchant_visit_index = -1

func _create_ui() -> void:
	# Créer le HUD (CanvasLayer auto-contenu)
	_hud = load("res://scripts/hud.gd").new()
	_hud.name = "HUD"
	add_child(_hud)

	# Signaux du HUD
	_hud.gh_pressed.connect(_on_gh_pressed)
	_hud.dh_pressed.connect(_on_dh_pressed)
	_hud.gm_pressed.connect(_on_gm_pressed)
	_hud.dm_pressed.connect(_on_dm_pressed)
	_hud.dbt_pressed.connect(_end_turn)
	_hud.quest_pressed.connect(_toggle_quest_panel)
	_hud.hero_selected.connect(_on_hud_hero_selected)
	_hud.pause_state_changed.connect(_on_pause_state_changed)
	_hud.save_requested.connect(_on_save_requested)
	_hud.zoom_in_requested.connect(_zoom_in)
	_hud.zoom_out_requested.connect(_zoom_out)

	# Références aux labels du HUD
	_label_gold = _hud.get_gold_label()
	_label_wood = _hud.get_wood_label()
	_label_ore = _hud.get_ore_label()
	_label_date = _hud.get_date_label()

	_create_minimap()

	# Overlay système (pause, zoom) toujours au-dessus de tout
	var sys_overlay := CanvasLayer.new()
	sys_overlay.name = "SystemOverlay"
	sys_overlay.layer = 128
	add_child(sys_overlay)
	var pause_btn: Button = _hud.get_pause_button()
	if pause_btn:
		pause_btn.reparent(sys_overlay)
	var zin_btn: Button = _hud.get_zoom_in_button()
	if zin_btn:
		zin_btn.reparent(sys_overlay)
	var zout_btn: Button = _hud.get_zoom_out_button()
	if zout_btn:
		zout_btn.reparent(sys_overlay)

	print("✓ HUD instancié et connecté")

func _create_decorated_panel(size: Vector2) -> Panel:
	var panel: Panel = Panel.new()
	panel.size = size
	
	# Style avec fond sombre et bordure vermilion
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.10, 0.08)  # Fond sombre
	style.border_color = Color(0.85, 0.25, 0.25)  # Vermilion japonais
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	
	return panel

func _on_end_turn_pressed() -> void:
	_end_turn()

# Variables pour la minimap
var _minimap_panel: Control = null
var _minimap_hero_dot: TextureRect = null
var _minimap_hero_glow: TextureRect = null
var _minimap_bg: TextureRect = null
var _minimap_viewport_rect: Panel = null
var _minimap_city_dots: Array = []
var _minimap_enemy_dots: Array = []
var _minimap_boss_dots: Array = []
var _minimap_resource_dots: Array = []
var _minimap_treasure_dots: Array = []

# Zoom : min = carte pleine écran ; défaut = plus serré (pas de bande verte)
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 0.1
const ZOOM_DEFAULT_FACTOR: float = 1.42

# Système de quêtes
enum QuestType { VISIT_CITIES, BUILD_BUILDINGS, RECRUIT_UNITS, DEFEAT_ENEMIES, COLLECT_GOLD }
const QUESTS: Array = [
	{
		"id": "q_explorer",
		"title": "Explorateur",
		"desc": "Visitez 3 villes différentes",
		"type": QuestType.VISIT_CITIES,
		"target": 3,
		"reward_gold": 1000,
		"reward_xp": 200,
	},
	{
		"id": "q_builder",
		"title": "Bâtisseur",
		"desc": "Construisez 3 bâtiments",
		"type": QuestType.BUILD_BUILDINGS,
		"target": 3,
		"reward_gold": 1500,
		"reward_xp": 300,
	},
	{
		"id": "q_army",
		"title": "Petite armée",
		"desc": "Recrutez 15 unités",
		"type": QuestType.RECRUIT_UNITS,
		"target": 15,
		"reward_gold": 2000,
		"reward_xp": 400,
	},
	{
		"id": "q_warrior",
		"title": "Guerrier",
		"desc": "Vainquez 5 ennemis",
		"type": QuestType.DEFEAT_ENEMIES,
		"target": 5,
		"reward_gold": 3000,
		"reward_xp": 500,
	},
	{
		"id": "q_rich",
		"title": "Riche",
		"desc": "Amassez 10000 pièces d'or",
		"type": QuestType.COLLECT_GOLD,
		"target": 10000,
		"reward_gold": 5000,
		"reward_xp": 1000,
	},
]

# Villes sur la carte
var _cities: Array = []
var _city_visuals: Array = []
const CITY_COUNT: int = 3
const CITY_SIZE: int = 48

# === VILLES MAJEURES ===
const MAJOR_CITIES: Dictionary = {
	"ajim": {"name": "Ajim", "tile": Vector2i(24, 16), "desc": "Port de pêcheurs"},
	"houmt_souk": {"name": "Houmt Souk", "tile": Vector2i(60, 56), "desc": "Cité marchande"},
	"gullala": {"name": "Gullala", "tile": Vector2i(96, 16), "desc": "Village potier"},
}

# === BOSSES ===
const BOSS_DATA: Array = [
	{
		"id": "boss_ajim",
		"name": "Garde des Dunes d'Ajim",
		"city_key": "ajim",
		"offset": Vector2i(3, 2),
		"army": [
			{"type": "swordsman", "count": 15},
			{"type": "archer", "count": 12},
			{"type": "cavalier", "count": 5},
		],
		"gold_reward": 1500,
		"xp_reward": 400,
		"hero_unlock": {"name": "Ronin", "hp": 8, "max_hp": 8, "attack": 14, "defense": 9},
	},
	{
		"id": "boss_houmt",
		"name": "Seigneur des Docks",
		"city_key": "houmt_souk",
		"offset": Vector2i(-3, 2),
		"army": [
			{"type": "griffin", "count": 12},
			{"type": "swordsman", "count": 10},
			{"type": "angel", "count": 2},
		],
		"gold_reward": 2000,
		"xp_reward": 500,
		"hero_unlock": {"name": "Shugenja", "hp": 6, "max_hp": 6, "attack": 18, "defense": 6, "magic": 15},
	},
	{
		"id": "boss_gullala",
		"name": "Golem des Poteries",
		"city_key": "gullala",
		"offset": Vector2i(0, 3),
		"army": [
			{"type": "cavalier", "count": 10},
			{"type": "angel", "count": 4},
			{"type": "swordsman", "count": 20},
		],
		"gold_reward": 2500,
		"xp_reward": 600,
		"hero_unlock": {"name": "Moine-Guerrier", "hp": 7, "max_hp": 7, "attack": 12, "defense": 14},
	},
]

# Ennemis errants (non-boss)
var _enemies: Array = []
var _enemy_visuals: Array = []
const WANDERER_COUNT: int = 32
const ENEMY_SIZE: int = 40

# Bosses (runtime data)
var _bosses: Array = []
var _boss_visuals: Array = []
var _unlocked_heroes: Array = []
var _heroes_data: Array = []  # [{name, hp, max_hp, attack, defense, mp, max_mp, level, xp, node}]
var _active_hero_index: int = 0

# Marchands
var _merchants: Array = []
var _merchant_visuals: Array = []
var _merchant_overlay: Panel = null
var _merchant_title_label: Label = null
var _merchant_items_container: VBoxContainer = null
var _merchant_screen_open: bool = false
var _selected_merchant_index: int = -1
var _last_merchant_visit_index: int = -1

# Détails du héros
var _hero_details_overlay = null
var _hero_details_layer = null
var _hero_details_visible: bool = false

# Inventaire / effets du joueur
var _player_items: Array = []  # [{item_id: String, effect: String, value: int}]
var _water_walk_turns: int = 0
var _camera_follow_hero: bool = true
var _compass_marker: Sprite2D = null

# Système de combat
var _hero_hp: int = 80
var _hero_max_hp: int = 80
var _hero_attack: int = 15
var _hero_defense: int = 8
var _in_combat: bool = false
var _pause_active: bool = false
var _combat_manager: CanvasLayer = null
var _tactical_combat: CanvasLayer = null
var _current_enemy_index: int = -1
var _current_boss_index: int = -1
var _in_boss_fight: bool = false

# LLM / Dialogue system
var _llm_client: LLMClient = null
var _llm_dialogue_screen: LLMDialogueScreen = null
var _fallback_dialogue_overlay: Panel = null
var _town_overlay: Panel = null
var _town_title_label: Label = null
var _town_res_label: Label = null
var _town_recruit_container: VBoxContainer = null
var _town_build_container: VBoxContainer = null
var _town_garrison_label: Label = null
var _selected_city_index: int = -1
var _town_screen_open: bool = false
var _last_city_visit_index: int = -1

var _quest_progress: Dictionary = {}
var _quest_completed: Array = []
var _quest_panel: Panel = null
var _quest_panel_visible: bool = false

# === SYSTÈME DE TERRAIN / MONDE ===
var _map_sprite: Sprite2D = null
var _sky_sprite: Sprite2D = null
var _terrain_grid: Array = []  # tableau 2D [x][y] = type de terrain (int)
var _terrain_move_cost: Dictionary = {}  # terrain_type -> coût de déplacement
var _decorations: Array = []
var _petals: Array = []
var _japanese_buildings: Array = []
var _japanese_building_data: Array = []
var _ambient_timer: float = 0.0
var _light_motes: Array = []
var _smoke_particles: Array = []
var _fireflies: Array = []
var _lantern_glows: Array = []

# === SYSTÈME DE BROUILLARD ===
var _fog_grid: Array = []  # 0=inconnu, 1=découvert, 2=visible
var _fog_overlay: Sprite2D = null
var _fog_image: Image = null
var _fog_texture: ImageTexture = null
const FOG_VISION_RANGE: int = 5
var _fog_current_alpha: Array = []  # tableau 2D [x][y] = alpha actuel
var _fog_animating: Dictionary = {}  # "x,y" -> {"current": float, "target": float, "speed": float}

# === RESSOURCES / TRÉSORS ===
var _resources: Array = []
var _resource_visuals: Array = []
var _treasures: Array = []
var _treasure_visuals: Array = []

# === VILLES / ARMÉES ===
var _cities_data: Array = []
var _enemy_armies: Array = []
var _hero_army: Array = []
var _visited_cities: Dictionary = {}

# === HÉROS : STATS ===
var _hero_mp: int = 20
var _hero_max_mp: int = 20
var _hero_level: int = 1
var _hero_xp: int = 0
var _hero_xp_to_next: int = 100

# === CALENDRIER ===
var _game_day: int = 1
var _game_week: int = 1
var _game_month: int = 1

# === GAME OVER ===
var _game_over_active: bool = false
var _game_over_layer: CanvasLayer = null
var _game_overlay: Control = null

# === ZOOM CAMÉRA ===
var _camera_zoom_min: float = 0.0
var _camera_zoom_default: float = 1.42
var _touch_points: Dictionary = {}
var _pinch_last_dist: float = 0.0

# === HUD ===
var _hud: CanvasLayer = null
var _label_date: Label = null

# === ANIMATION / PATHFINDING ===
var _move_tween: Tween = null
var _path_queue: Array = []
var _is_pathfinding: bool = false
var _is_dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_threshold: float = 15.0
var _wheel_debounce: float = 0.0
var _anim_time: float = 0.0
var _fx_frame: int = 0
var _minimap_scale: float = 10.0

# === MINIMAP ===
const DEBUG_LOG: bool = false

# === CONSTANTES XP ===
const XP_VISIT_CITY: int = 100
const XP_KILL_ENEMY: int = 150
const XP_DISCOVER_TILE: int = 5
const XP_COLLECT_RESOURCE: int = 20
const XP_OPEN_TREASURE: int = 50
const XP_PER_LEVEL: int = 150

# === CONSTANTES RESSOURCES ===
const RESOURCE_COUNT: int = 60
const TREE_COUNT: int = 160
const ROCK_COUNT: int = 60
const TOWER_COUNT: int = 16
const TREASURE_COUNT: int = 20
const RESOURCE_TYPES: Array = ["gold", "wood", "ore"]

# === CONSTANTES UNITES ===
const UNIT_TYPES: Dictionary = {
	"pikeman": {"name": "Piquier", "hp": 5, "attack": 6, "defense": 6, "cost_g": 40, "magic": 0, "magic_res": 2, "speed": 5},
	"archer": {"name": "Archer", "hp": 5, "attack": 8, "defense": 5, "cost_g": 60, "magic": 0, "magic_res": 3, "speed": 6},
	"griffin": {"name": "Griffon", "hp": 10, "attack": 10, "defense": 8, "cost_g": 120, "magic": 0, "magic_res": 4, "speed": 7},
	"swordsman": {"name": "Épéiste", "hp": 10, "attack": 12, "defense": 12, "cost_g": 200, "magic": 0, "magic_res": 5, "speed": 5},
	"cavalier": {"name": "Cavalier", "hp": 15, "attack": 14, "defense": 10, "cost_g": 280, "magic": 0, "magic_res": 4, "speed": 8},
	"angel": {"name": "Ange", "hp": 20, "attack": 22, "defense": 14, "cost_g": 700, "magic": 15, "magic_res": 10, "speed": 9},
}

# === CONSTANTES BATIMENTS ===
const CITY_BUILDINGS: Dictionary = {
	"town_hall": {"name": "Hôtel de Ville", "cost_g": 500, "cost_w": 5, "cost_o": 5, "effect": "income+750"},
	"barracks": {"name": "Caserne", "cost_g": 300, "cost_w": 5, "cost_o": 3, "effect": "pikeman"},
	"archery_range": {"name": "Stand de Tir", "cost_g": 500, "cost_w": 8, "cost_o": 5, "effect": "archer"},
	"griffin_tower": {"name": "Tour aux Griffons", "cost_g": 1000, "cost_w": 10, "cost_o": 8, "effect": "griffin"},
	"training_ground": {"name": "Terrain d'Entraînement", "cost_g": 1400, "cost_w": 12, "cost_o": 10, "effect": "swordsman"},
	"stables": {"name": "Écuries", "cost_g": 2000, "cost_w": 15, "cost_o": 12, "effect": "cavalier"},
	"angel_statue": {"name": "Statue d'Ange", "cost_g": 3500, "cost_w": 20, "cost_o": 15, "effect": "angel"},
	"resource_silo": {"name": "Silo à Ressources", "cost_g": 400, "cost_w": 8, "cost_o": 6, "effect": "wood+1, ore+1/jour"},
}

# === CONSTANTES MARCHANDS ===
const MERCHANT_COUNT: int = 8
const MERCHANT_ITEMS: Dictionary = {
	"weapon_1": {"name": "Épine en acier", "desc": "ATK +3", "cost": 300, "cost_w": 2, "cost_o": 0, "icon": "⚔️", "effect": "attack", "value": 3},
	"weapon_2": {"name": "Katana du vent", "desc": "ATK +6", "cost": 600, "cost_w": 0, "cost_o": 3, "icon": "🗡️", "effect": "attack", "value": 6},
	"weapon_3": {"name": "Lame démoniaque", "desc": "ATK +10", "cost": 1200, "cost_w": 5, "cost_o": 5, "icon": "🔪", "effect": "attack", "value": 10},
	"armor_1": {"name": "Armure de bambou", "desc": "DEF +3", "cost": 250, "cost_w": 3, "cost_o": 0, "icon": "🛡️", "effect": "defense", "value": 3},
	"armor_2": {"name": "Armure de samouraï", "desc": "DEF +6", "cost": 500, "cost_w": 0, "cost_o": 4, "icon": "⛩️", "effect": "defense", "value": 6},
	"armor_3": {"name": "Armure ancestrale", "desc": "DEF +10", "cost": 1000, "cost_w": 4, "cost_o": 4, "icon": "🏯", "effect": "defense", "value": 10},
	"spell_fire": {"name": "Parchemin de feu", "desc": "Sort: Foudroie l'ennemi", "cost": 350, "cost_w": 0, "cost_o": 2, "icon": "🔥", "effect": "spell_fire", "value": 1},
	"spell_heal": {"name": "Parchemin de soin", "desc": "Soigne 30 PV", "cost": 300, "cost_w": 2, "cost_o": 0, "icon": "💚", "effect": "spell_heal", "value": 30},
	"compass": {"name": "Boussole sacrée", "desc": "Révèle le boss le plus proche", "cost": 200, "cost_w": 0, "cost_o": 0, "icon": "🧭", "effect": "compass", "value": 1},
	"water_amulet": {"name": "Amulette aquatique", "desc": "Marche sur l'eau (5 tours)", "cost": 500, "cost_w": 3, "cost_o": 3, "icon": "🌊", "effect": "water_walk", "value": 5},
}
func _init_quests() -> void:
	_quest_progress = {}
	for q in QUESTS:
		_quest_progress[q["id"]] = 0

func _check_quest(qid: String, increment: int = 1) -> void:
	if qid in _quest_completed:
		return
	var current: int = _quest_progress.get(qid, 0) + increment
	_quest_progress[qid] = current
	for q in QUESTS:
		if q["id"] == qid:
			if current >= q["target"]:
				_complete_quest(q)
			break

func _complete_quest(q: Dictionary) -> void:
	if q["id"] in _quest_completed:
		return
	_quest_completed.append(q["id"])
	GameData.quests_completed = _quest_completed.size()
	_gold += q["reward_gold"]
	_gain_xp(q["reward_xp"])
	var msg: String = "Quete terminee: %s! +%d or, +%d XP" % [q["title"], q["reward_gold"], q["reward_xp"]]
	print("🏆 ", msg)
	if _hero:
		_create_floating_text(msg, Color(1.0, 0.85, 0.2), _hero.position)
	_update_resource_labels()
	_update_quest_panel()

func _toggle_quest_panel() -> void:
	if not _quest_panel:
		_create_quest_panel()
	_quest_panel_visible = not _quest_panel_visible
	_quest_panel.visible = _quest_panel_visible

func _create_quest_panel() -> void:
	_quest_panel = Panel.new()
	_quest_panel.name = "QuestPanel"
	_quest_panel.visible = false
	_quest_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_quest_panel.position = Vector2(80, 140)
	_quest_panel.custom_minimum_size = Vector2(280, 260)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12, 0.92)
	style.border_color = Color(0.6, 0.5, 0.2)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	_quest_panel.add_theme_stylebox_override("panel", style)
	add_child(_quest_panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(10, 10)
	vbox.custom_minimum_size = Vector2(260, 240)
	vbox.add_theme_constant_override("separation", 4)
	_quest_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Objectifs"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for q in QUESTS:
		var hbox := HBoxContainer.new()
		vbox.add_child(hbox)

		var qlabel := Label.new()
		qlabel.add_theme_font_size_override("font_size", 11)
		qlabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		qlabel.custom_minimum_size = Vector2(240, 0)
		hbox.add_child(qlabel)
		_quest_panel.set_meta("label_" + q["id"], qlabel)

	_update_quest_panel()

	var btn_close := Button.new()
	btn_close.text = "Fermer"
	btn_close.pressed.connect(_toggle_quest_panel)
	vbox.add_child(btn_close)

func _update_quest_panel() -> void:
	if not _quest_panel:
		return
	for q in QUESTS:
		var label: Label = _quest_panel.get_meta("label_" + q["id"], null)
		if not label:
			continue
		var done: bool = q["id"] in _quest_completed
		var cur: int = _quest_progress.get(q["id"], 0)
		var status: String = "%s: %d/%d" % [q["title"], min(cur, q["target"]), q["target"]]
		if done:
			label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
			status += " ✓"
		else:
			label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
		label.text = status

func _create_cities() -> void:
	# Créer les 3 villes majeures à des positions fixes

	var japanese_sheet: Texture2D = load("res://assets/bat.png")
	var city_keys: Array = MAJOR_CITIES.keys()
	
	for i in range(CITY_COUNT):
		var key: String = city_keys[i]
		var city_def: Dictionary = MAJOR_CITIES[key]
		var city_tile: Vector2i = city_def["tile"]
		var world_x: float = (city_tile.x * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (city_tile.y * TILE_SIZE) + TILE_SIZE / 2
		var city_pos: Vector2 = Vector2(world_x, world_y)
		
		# Stocker la position de la ville
		_cities.append(city_pos)
		
		# Initialiser les données de la ville
		_cities_data.append({
			"position": city_pos,
			"name": city_def["name"],
			"tile": city_tile,
			"buildings": ["barracks", "archery_range", "griffin_tower"] if i == 0 else [],
			"garrison": [],
			"income": 1000,
			"owned": i == 0,
		})
		
		# Créer le visuel du château
		var city_node: Node2D = Node2D.new()
		city_node.name = "City_" + key
		city_node.position = city_pos
		add_child(city_node)
		
		var castle_sprite: Sprite2D = Sprite2D.new()
		var is_main_castle: bool = (i == 0)
		
		if japanese_sheet != null:
			var building_index: int = 0 if is_main_castle else (5 if i == 1 else 2)
			var building_texture: Texture2D = _extract_building_texture(japanese_sheet, building_index)
			castle_sprite.texture = building_texture
			if is_main_castle:
				_create_building_shadow(city_node, 120, 30, 0.30)
				castle_sprite.scale = Vector2(2.0, 2.0)
				castle_sprite.position = Vector2(0, -90)
			else:
				_create_building_shadow(city_node, 90, 22, 0.25)
				castle_sprite.scale = Vector2(1.5, 1.5)
				castle_sprite.position = Vector2(0, -64)
		else:
			if is_main_castle:
				var castle_texture: Texture2D = load("res://assets/external/castle.png")
				if castle_texture != null:
					castle_sprite.texture = castle_texture
					var target_size: float = 256.0
					var tex_size: Vector2 = castle_texture.get_size()
					var scale_factor: float = target_size / max(tex_size.x, tex_size.y)
					castle_sprite.scale = Vector2(scale_factor, scale_factor)
				else:
					castle_sprite.texture = _sg._generate_sprite("castle", 256, i * 1337)
				castle_sprite.position = Vector2(0, -90)
			else:
				var barracks_texture: Texture2D = load("res://assets/external/barracks.png")
				if barracks_texture != null:
					castle_sprite.texture = barracks_texture
					var target_size: float = 192.0
					var tex_size: Vector2 = barracks_texture.get_size()
					var scale_factor: float = target_size / max(tex_size.x, tex_size.y)
					castle_sprite.scale = Vector2(scale_factor, scale_factor)
				else:
					castle_sprite.texture = _sg._generate_sprite("castle", 192, i * 1337)
				castle_sprite.position = Vector2(0, -64)
		city_node.add_child(castle_sprite)
		_apply_outline_shader(castle_sprite, Color(0, 0, 0, 0.7), 1.0, Color(1.0, 0.9, 0.5, 0.2), 5.0, 0.12)
		
		var chimney_count: int = rng.randi_range(2, 4)
		if is_main_castle:
			chimney_count = rng.randi_range(4, 7)
		for chimney in range(chimney_count):
			var smoke: Sprite2D = Sprite2D.new()
			var smoke_img: Image = Image.create(12, 12, false, Image.FORMAT_RGBA8)
			smoke_img.fill(Color(0, 0, 0, 0))
			for sx in range(12):
				for sy in range(12):
					var sdist: float = sqrt((sx - 6)**2 + (sy - 6)**2)
					if sdist < 5:
						var salpha: float = (1.0 - sdist / 5.0) * 0.4
						smoke_img.set_pixel(sx, sy, Color(0.8, 0.8, 0.8, salpha))
			smoke.texture = ImageTexture.create_from_image(smoke_img)
			var smoke_y: float = -110 if not is_main_castle else -150
			smoke.position = Vector2(rng.randi_range(-40, 40), smoke_y)
			smoke.set_z_index(1)
			city_node.add_child(smoke)
			_smoke_particles.append({
				"sprite": smoke,
				"base_pos": smoke.position,
				"speed": rng.randf_range(2.0, 5.0),
				"offset": rng.randf() * 10.0,
				"size": 1.0
			})
		
		if is_main_castle:
			var banner: Sprite2D = Sprite2D.new()
			var banner_img: Image = Image.create(8, 24, false, Image.FORMAT_RGBA8)
			banner_img.fill(Color(0, 0, 0, 0))
			for by in range(24):
				banner_img.set_pixel(3, by, Color(0.4, 0.3, 0.2))
				banner_img.set_pixel(4, by, Color(0.35, 0.25, 0.18))
			for bx in range(4, 8):
				for by in range(4, 14):
					if rng.randf() < 0.8:
						var bcol: Color = Color(0.72, 0.08, 0.08)
						if rng.randf() < 0.3:
							bcol = Color(0.62, 0.06, 0.06)
						banner_img.set_pixel(bx, by, bcol)
			banner_img.set_pixel(5, 8, Color(0.9, 0.75, 0.2))
			banner_img.set_pixel(6, 8, Color(0.85, 0.7, 0.15))
			banner_img.set_pixel(5, 9, Color(0.85, 0.7, 0.15))
			banner_img.set_pixel(6, 9, Color(0.9, 0.75, 0.2))
			banner.texture = ImageTexture.create_from_image(banner_img)
			banner.position = Vector2(60, -160)
			banner.set_z_index(2)
			city_node.add_child(banner)
		
		_city_visuals.append(city_node)
		print("Ville ", city_def["name"], " créée à la position : ", city_pos)

func _create_enemies() -> void:
	# Créer des ennemis errants sur la carte (non-boss)

	for i in range(WANDERER_COUNT):
		var enemy_x: int = rng.randi_range(3, _zone_w - 4)
		var enemy_y: int = rng.randi_range(3, _zone_h - 4)
		var world_x: float = (enemy_x * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (enemy_y * TILE_SIZE) + TILE_SIZE / 2
		var enemy_pos: Vector2 = Vector2(world_x, world_y)
		
		var enemy_data: Dictionary = {
			"position": enemy_pos,
			"hp": 50,
			"max_hp": 50,
			"attack": 10,
			"alive": true,
			"name": "Armee errante #" + str(i + 1),
			"gold_reward": rng.randi_range(50, 150),
			"xp_reward": rng.randi_range(30, 80),
			"mp": 6,
			"max_mp": 6,
			"detection_range": 6 + rng.randi_range(0, 3),
		}
		_enemies.append(enemy_data)
		
		# Créer le visuel de l'ennemi
		var enemy_node: Node2D = Node2D.new()
		enemy_node.name = "Enemy_" + str(i)
		enemy_node.position = enemy_pos
		add_child(enemy_node)

		# Glow rouge autour de l'ennemi
		var glow_img: Image = Image.create(72, 72, false, Image.FORMAT_RGBA8)
		glow_img.fill(Color(0, 0, 0, 0))
		for gx in range(72):
			for gy in range(72):
				var gdist: float = sqrt((gx - 36) ** 2 + (gy - 36) ** 2)
				if gdist < 32:
					var alpha: float = (1.0 - gdist / 32.0) * 0.22
					glow_img.set_pixel(gx, gy, Color(0.85, 0.12, 0.12, alpha))
		var glow_sprite: Sprite2D = Sprite2D.new()
		glow_sprite.name = "EnemyGlow"
		glow_sprite.texture = ImageTexture.create_from_image(glow_img)
		glow_sprite.position = Vector2(0, -16)
		glow_sprite.set_z_index(-4)
		enemy_node.add_child(glow_sprite)

		# Sprite procédural japonais en priorité (thème samurai)
		var enemy_types: Array = ["enemy_skeleton", "enemy_goblin", "enemy_archer", "enemy_swordsman", "enemy_tengu", "enemy_kappa", "enemy_ninja", "enemy_monk"]
		var sprite_type: String = enemy_types[i % enemy_types.size()]
		var enemy_sprite: Sprite2D = Sprite2D.new()
		enemy_sprite.name = "EnemySprite"
		enemy_sprite.texture = _sg._generate_sprite(sprite_type, 64, i * 7919)
		enemy_sprite.position = Vector2(0, -16)
		_apply_outline_shader(enemy_sprite, Color(0, 0, 0, 0.85), 1.5, Color(0.85, 0.15, 0.15, 0.35), 4.0, 0.25)
		enemy_node.add_child(enemy_sprite)

		# Anneau de sélection avec coins (comme le héros)
		var selection_ring: ColorRect = ColorRect.new()
		selection_ring.name = "EnemySelectionRing"
		selection_ring.size = Vector2(64, 64)
		selection_ring.position = Vector2(-32, -48)
		selection_ring.color = Color(0.85, 0.15, 0.15, 0.20)
		selection_ring.set_z_index(-2)
		enemy_node.add_child(selection_ring)

		for corner in range(4):
			var corner_marker: ColorRect = ColorRect.new()
			corner_marker.size = Vector2(6, 6)
			var cx: float = -32 if corner % 2 == 0 else 26
			var cy: float = -48 if corner < 2 else -18
			corner_marker.position = Vector2(cx, cy)
			corner_marker.color = Color(0.85, 0.15, 0.15)
			corner_marker.set_z_index(-1)
			enemy_node.add_child(corner_marker)

		# Nom de l'ennemi
		var enemy_label: Label = Label.new()
		enemy_label.name = "EnemyLabel"
		enemy_label.text = enemy_data["name"]
		enemy_label.add_theme_font_size_override("font_size", 8)
		enemy_label.add_theme_color_override("font_color", Color(0.90, 0.80, 0.80))
		enemy_label.position = Vector2(-24, 24)
		enemy_label.size = Vector2(48, 12)
		enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		enemy_node.add_child(enemy_label)

		# HP bar background
		var enemy_hp_bg: ColorRect = ColorRect.new()
		enemy_hp_bg.name = "EnemyHPBG"
		enemy_hp_bg.position = Vector2(-18, 20)
		enemy_hp_bg.size = Vector2(36, 4)
		enemy_hp_bg.color = Color(0.08, 0.08, 0.08)
		enemy_hp_bg.z_index = 5
		enemy_node.add_child(enemy_hp_bg)

		# HP bar fill
		var enemy_hp_fill: ColorRect = ColorRect.new()
		enemy_hp_fill.name = "EnemyHPFill"
		enemy_hp_fill.position = Vector2(-18, 20)
		enemy_hp_fill.size = Vector2(36, 4)
		enemy_hp_fill.color = Color(0.7, 0.15, 0.15)
		enemy_hp_fill.z_index = 6
		enemy_node.add_child(enemy_hp_fill)

		_enemy_visuals.append(enemy_node)

		print("Ennemi ", i + 1, " créé à la position : ", enemy_pos, " (HP: 50)")

func _create_bosses() -> void:
	# Créer les 3 boss, chacun près d'une ville majeure
	
	for boss_def in BOSS_DATA:
		var city_def: Dictionary = MAJOR_CITIES[boss_def["city_key"]]
		var boss_tile: Vector2i = city_def["tile"] + boss_def["offset"]
		var world_x: float = (boss_tile.x * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (boss_tile.y * TILE_SIZE) + TILE_SIZE / 2
		var boss_pos: Vector2 = Vector2(world_x, world_y)
		
		var boss_data: Dictionary = {
			"id": boss_def["id"],
			"name": boss_def["name"],
			"position": boss_pos,
			"alive": true,
			"gold_reward": boss_def["gold_reward"],
			"xp_reward": boss_def["xp_reward"],
			"army": boss_def["army"],
			"hero_unlock": boss_def["hero_unlock"],
		}
		_bosses.append(boss_data)
		
		# Visuel du boss
		var boss_node: Node2D = Node2D.new()
		boss_node.name = "Boss_" + boss_def["id"]
		boss_node.position = boss_pos
		add_child(boss_node)
		
		# Sprite du boss (cercle rouge plus grand)
		var boss_sprite: Sprite2D = Sprite2D.new()
		var boss_img: Image = Image.create(48, 48, false, Image.FORMAT_RGBA8)
		boss_img.fill(Color(0, 0, 0, 0))
		for px in range(48):
			for py in range(48):
				var dist: float = sqrt((px - 24)**2 + (py - 24)**2)
				if dist < 20:
					boss_img.set_pixel(px, py, Color(0.8, 0.08, 0.08, 0.9))
				elif dist < 22:
					boss_img.set_pixel(px, py, Color(0.3, 0.05, 0.05, 0.7))
		# Skull symbol (simple cross pattern)
		var cx: int = 24
		var cy: int = 24
		for sk in range(-6, 7):
			boss_img.set_pixel(cx + sk, cy, Color(0.95, 0.95, 0.95, 0.8))
			boss_img.set_pixel(cx, cy + sk, Color(0.95, 0.95, 0.95, 0.8))
		boss_img.set_pixel(cx - 2, cy - 2, Color(0.95, 0.95, 0.95, 0.8))
		boss_img.set_pixel(cx + 2, cy - 2, Color(0.95, 0.95, 0.95, 0.8))
		boss_img.set_pixel(cx - 2, cy + 2, Color(0.95, 0.95, 0.95, 0.8))
		boss_img.set_pixel(cx + 2, cy + 2, Color(0.95, 0.95, 0.95, 0.8))
		boss_sprite.texture = ImageTexture.create_from_image(boss_img)
		boss_sprite.scale = Vector2(1.5, 1.5)
		boss_sprite.position = Vector2(0, -20)
		boss_node.add_child(boss_sprite)
		_apply_outline_shader(boss_sprite, Color(0, 0, 0, 0.85), 1.5, Color(0.9, 0.1, 0.1, 0.4), 5.0, 0.25)
		
		# Nom du boss
		var boss_label: Label = Label.new()
		boss_label.text = boss_def["name"]
		boss_label.add_theme_font_size_override("font_size", 10)
		boss_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		boss_label.position = Vector2(-60, 20)
		boss_label.size = Vector2(120, 20)
		boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_node.add_child(boss_label)
		
		# Glow effect
		var glow: Sprite2D = Sprite2D.new()
		var glow_img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		glow_img.fill(Color(0, 0, 0, 0))
		for gx in range(64):
			for gy in range(64):
				var gdist: float = sqrt((gx - 32)**2 + (gy - 32)**2)
				if gdist < 30:
					var alpha: float = (1.0 - gdist / 30.0) * 0.25
					glow_img.set_pixel(gx, gy, Color(0.8, 0.1, 0.1, alpha))
		glow.texture = ImageTexture.create_from_image(glow_img)
		glow.position = Vector2(0, -20)
		glow.set_z_index(-1)
		boss_node.add_child(glow)
		
		_boss_visuals.append(boss_node)
		print("Boss créé : ", boss_def["name"], " à ", boss_pos)

func _create_merchants() -> void:
	var merchant_names: Array[String] = ["Yamada le marchand", "Fujiwara l'antiquaire", "Takashi le colporteur", "Tanaka l'alchimiste"]

	for i in range(MERCHANT_COUNT):
		var mx: int = rng.randi_range(3, _zone_w - 4)
		var my: int = rng.randi_range(3, _zone_h - 4)
		var world_x: float = (mx * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (my * TILE_SIZE) + TILE_SIZE / 2
		var pos: Vector2 = Vector2(world_x, world_y)

		# Stocker les données du marchand
		_merchants.append({
			"name": merchant_names[i % merchant_names.size()],
			"position": pos,
			"tile": Vector2i(mx, my),
			"alive": true,
		})

		# Visuel
		var node: Node2D = Node2D.new()
		node.name = "Merchant_" + str(i)
		node.position = pos
		add_child(node)

		# Glow violet autour du marchand
		var glow_img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		glow_img.fill(Color(0, 0, 0, 0))
		for gx in range(64):
			for gy in range(64):
				var gdist: float = sqrt((gx - 32) ** 2 + (gy - 32) ** 2)
				if gdist < 28:
					var alpha: float = (1.0 - gdist / 28.0) * 0.20
					glow_img.set_pixel(gx, gy, Color(0.6, 0.35, 0.8, alpha))
		var glow_sprite: Sprite2D = Sprite2D.new()
		glow_sprite.name = "MerchantGlow"
		glow_sprite.texture = ImageTexture.create_from_image(glow_img)
		glow_sprite.position = Vector2(0, -16)
		glow_sprite.set_z_index(-3)
		node.add_child(glow_sprite)

		# Sprite procédural du marchand (64x64)
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = _sg._generate_sprite("merchant", 64, i * 5557)
		sprite.position = Vector2(0, -16)
		node.add_child(sprite)
		_apply_outline_shader(sprite, Color(0, 0, 0, 0.8), 1.0, Color(0.7, 0.5, 0.8, 0.25), 3.0, 0.1)

		# Icône boutique au-dessus
		var shop_icon: Label = Label.new()
		shop_icon.name = "MerchantIcon"
		shop_icon.text = "🏪"
		shop_icon.add_theme_font_size_override("font_size", 14)
		shop_icon.position = Vector2(-8, -30)
		shop_icon.size = Vector2(16, 16)
		shop_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		node.add_child(shop_icon)

		# Nom du marchand
		var name_label: Label = Label.new()
		name_label.name = "MerchantLabel"
		name_label.text = merchant_names[i % merchant_names.size()]
		name_label.add_theme_font_size_override("font_size", 8)
		name_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.90))
		name_label.position = Vector2(-30, 24)
		name_label.size = Vector2(60, 12)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		node.add_child(name_label)

		_merchant_visuals.append(node)
		print("Marchand créé : ", merchant_names[i % merchant_names.size()], " à (", mx, ",", my, ")")

	_create_merchant_overlay()

func _reveal_fog_around_pos(tile: Vector2i, radius: int) -> void:
	var changed: Array = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var tx: int = tile.x + dx
			var ty: int = tile.y + dy
			if tx < 0 or tx >= _zone_w or ty < 0 or ty >= _zone_h:
				continue
			var dist: int = absi(dx) + absi(dy)
			if dist <= radius:
				_fog_grid[tx][ty] = 2  # visible
				_fog_current_alpha[tx][ty] = 0.0
				changed.append(Vector2i(tx, ty))
	if not changed.is_empty():
		_refresh_fog_tiles(changed)

func _create_resources() -> void:
	# Créer des ressources à collecter sur la carte (mines, scieries)

	for i in range(RESOURCE_COUNT):
		var res_x: int = rng.randi_range(1, _zone_w - 2)
		var res_y: int = rng.randi_range(1, _zone_h - 2)
		var world_x: float = (res_x * TILE_SIZE) + TILE_SIZE / 2
		var world_y: float = (res_y * TILE_SIZE) + TILE_SIZE / 2
		var res_pos: Vector2 = Vector2(world_x, world_y)
		
		# Type de ressource
		var res_type: String = RESOURCE_TYPES[i % RESOURCE_TYPES.size()]
		var res_name: String = ""
		var _res_color: Color
		
		match res_type:
			"gold":
				res_name = "Mine d'Or"
				_res_color = Color(0.9, 0.7, 0.1)  # Or
			"wood":
				res_name = "Scierie"
				_res_color = Color(0.4, 0.25, 0.1)  # Marron bois
			"ore":
				res_name = "Mine de Minerai"
				_res_color = Color(0.5, 0.5, 0.5)  # Gris
		
		# Stocker les données de la ressource
		var res_data: Dictionary = {
			"position": res_pos,
			"type": res_type,
			"name": res_name,
			"collected": false
		}
		_resources.append(res_data)
		
		# Créer le visuel de la ressource (détaillé selon le type)
		var res_node: Node2D = Node2D.new()
		res_node.name = "Resource_" + str(i)
		res_node.position = res_pos
		add_child(res_node)
		
		# === SPRITE PROCÉDURAL POUR LA RESSOURCE ===
		var sprite_type: String = ""
		match res_type:
			"gold":
				res_name = "Mine d'Or"
				_res_color = Color(0.9, 0.7, 0.1)
				sprite_type = "mine_gold"
			"wood":
				res_name = "Scierie"
				_res_color = Color(0.4, 0.25, 0.1)
				sprite_type = "mine_wood"
			"ore":
				res_name = "Mine de Minerai"
				_res_color = Color(0.5, 0.5, 0.5)
				sprite_type = "mine_ore"
		
		var res_sprite: Sprite2D = Sprite2D.new()
		res_sprite.texture = _sg._generate_sprite(sprite_type, 96, i * 3571)
		res_sprite.position = Vector2(0, -24)
		res_node.add_child(res_sprite)
		_apply_outline_shader(res_sprite, Color(0, 0, 0, 0.75), 1.0, Color(1.0, 0.9, 0.5, 0.1), 3.0, 0.06)
		
		# Ombre elliptique sous la ressource
		_sg._create_elliptical_shadow(res_node, 44, 14, 14, 0.30)
		
		_resource_visuals.append(res_node)
		
		print("Ressource ", i + 1, " créée : ", res_name, " à la position : ", res_pos)

func _create_circle_tex(radius: int) -> ImageTexture:
	var diameter = radius * 2 + 1
	var img = Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r2 = radius * radius
	for x in range(diameter):
		for y in range(diameter):
			var dx = x - radius
			var dy = y - radius
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

func _create_minimap() -> void:
	if _hud == null:
		return
	var minimap_container: Control = _hud.get_minimap_container()
	if minimap_container == null:
		return

	const ZONE_W = 540
	const ZONE_H = 380

	# ── Terrain zone ──
	_minimap_panel = Control.new()
	_minimap_panel.name = "MinimapZone"
	_minimap_panel.size = Vector2(ZONE_W, ZONE_H)
	_minimap_panel.position = Vector2(10, 10)
	_minimap_panel.clip_contents = true
	minimap_container.add_child(_minimap_panel)

	var scale_mini = min(ZONE_W / float(_zone_w * TILE_SIZE), ZONE_H / float(_zone_h * TILE_SIZE))

	# ── Terrain background ──
	var bg_img = Image.create(ZONE_W, ZONE_H, false, Image.FORMAT_RGBA8)
	bg_img.fill(Color(0.04, 0.04, 0.06))
	var terrain_colors = {
		0: Color(0.28, 0.55, 0.22),
		1: Color(0.55, 0.42, 0.25),
		2: Color(0.10, 0.20, 0.55),
		3: Color(0.35, 0.28, 0.18),
		4: Color(0.50, 0.38, 0.25),
		5: Color(0.50, 0.45, 0.38),
	}
	for tx in range(_zone_w):
		for ty in range(_zone_h):
			var terrain = _terrain_grid[tx][ty] if tx < _terrain_grid.size() and ty < _terrain_grid[tx].size() else 0
			var color = terrain_colors.get(terrain, Color(0.2, 0.4, 0.2))
			var px = tx * TILE_SIZE * scale_mini
			var py = ty * TILE_SIZE * scale_mini
			var ps = maxf(1.0, TILE_SIZE * scale_mini - 0.5)
			var rect = Rect2i(int(px), int(py), int(ps), int(ps))
			if rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= ZONE_W and rect.end.y <= ZONE_H:
				bg_img.fill_rect(rect, color)
	_minimap_bg = TextureRect.new()
	_minimap_bg.texture = ImageTexture.create_from_image(bg_img)
	_minimap_bg.size = Vector2(ZONE_W, ZONE_H)
	_minimap_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.add_child(_minimap_bg)

	# ── Fog overlay (plus clair) ──
	var fog_img = Image.create(ZONE_W, ZONE_H, false, Image.FORMAT_RGBA8)
	fog_img.fill(Color(0, 0, 0, 0))
	if _fog_grid.size() > 0:
		for tx in range(_zone_w):
			for ty in range(_zone_h):
				var state = _fog_grid[tx][ty] if tx < _fog_grid.size() and ty < _fog_grid[tx].size() else 0
				var fog_alpha = 0.0 if state == 2 else (0.25 if state == 1 else 0.60)
				if fog_alpha > 0:
					var px = tx * TILE_SIZE * scale_mini
					var py = ty * TILE_SIZE * scale_mini
					var ps = maxf(1.0, TILE_SIZE * scale_mini - 0.5)
					var rect = Rect2i(int(px), int(py), int(ps), int(ps))
					if rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= ZONE_W and rect.end.y <= ZONE_H:
						fog_img.fill_rect(rect, Color(0.04, 0.04, 0.08, fog_alpha))
	var fog_rect = TextureRect.new()
	fog_rect.texture = ImageTexture.create_from_image(fog_img)
	fog_rect.size = Vector2(ZONE_W, ZONE_H)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.add_child(fog_rect)

	# ── Pre-generated circle textures ──
	var c3  = _create_circle_tex(3)
	var c4  = _create_circle_tex(4)
	var c5  = _create_circle_tex(5)
	var c6  = _create_circle_tex(6)
	var c8  = _create_circle_tex(8)
	var c10 = _create_circle_tex(10)

	# ── City dots ──
	_minimap_city_dots = []
	for i in range(_cities.size()):
		var city_pos = _cities[i]
		var is_main = (i == 0)
		var dot = TextureRect.new()
		dot.texture = c5
		dot.size = Vector2(13, 13)
		dot.modulate = Color(1.0, 0.8, 0.1) if is_main else Color(0.9, 0.45, 0.1)
		dot.position = Vector2(city_pos.x * scale_mini - 6.5, city_pos.y * scale_mini - 6.5)
		_minimap_panel.add_child(dot)
		if i < _cities_data.size():
			var label = Label.new()
			label.text = _cities_data[i].get("name", "Ville")
			label.add_theme_font_size_override("font_size", 8)
			label.add_theme_color_override("font_color", Color(1, 1, 0.85, 0.85))
			label.position = Vector2(city_pos.x * scale_mini + 7, city_pos.y * scale_mini - 4)
			_minimap_panel.add_child(label)
		_minimap_city_dots.append(dot)

	# ── Enemy dots ──
	_minimap_enemy_dots = []
	for enemy in _enemies:
		var dot = TextureRect.new()
		dot.texture = c3
		dot.size = Vector2(9, 9)
		dot.modulate = Color(0.6, 0.1, 0.8)
		dot.position = Vector2(enemy["position"].x * scale_mini - 4.5, enemy["position"].y * scale_mini - 4.5)
		_minimap_panel.add_child(dot)
		_minimap_enemy_dots.append(dot)

	# ── Boss dots ──
	_minimap_boss_dots = []
	for boss_data in _bosses:
		var dot = TextureRect.new()
		dot.texture = c6
		dot.size = Vector2(15, 15)
		dot.modulate = Color(0.95, 0.1, 0.1)
		dot.position = Vector2(boss_data["position"].x * scale_mini - 7.5, boss_data["position"].y * scale_mini - 7.5)
		_minimap_panel.add_child(dot)
		var glow = TextureRect.new()
		glow.texture = c8
		glow.size = Vector2(19, 19)
		glow.position = Vector2(-2, -2)
		glow.modulate = Color(1, 0.3, 0.1, 0.25)
		dot.add_child(glow)
		_minimap_boss_dots.append(dot)

	# ── Resource dots ──
	_minimap_resource_dots = []
	for res in _resources:
		var dot = TextureRect.new()
		dot.texture = c3
		dot.size = Vector2(7, 7)
		dot.modulate = Color(1, 0.85, 0.15)
		dot.position = Vector2(res["position"].x * scale_mini - 3.5, res["position"].y * scale_mini - 3.5)
		_minimap_panel.add_child(dot)
		_minimap_resource_dots.append(dot)

	# ── Treasure dots ──
	_minimap_treasure_dots = []
	for chest in _treasures:
		var dot = TextureRect.new()
		dot.texture = c4
		dot.size = Vector2(9, 9)
		dot.modulate = Color(0.7, 0.9, 1.0)
		dot.position = Vector2(chest["position"].x * scale_mini - 4.5, chest["position"].y * scale_mini - 4.5)
		_minimap_panel.add_child(dot)
		_minimap_treasure_dots.append(dot)

	# ── Viewport rectangle (shows camera visible area) ──
	_minimap_viewport_rect = Panel.new()
	var vp_style = StyleBoxFlat.new()
	vp_style.bg_color = Color(1, 1, 1, 0.06)
	vp_style.border_color = Color(0.8, 0.9, 1.0, 0.5)
	vp_style.border_width_top = 1
	vp_style.border_width_bottom = 1
	vp_style.border_width_left = 1
	vp_style.border_width_right = 1
	_minimap_viewport_rect.add_theme_stylebox_override("panel", vp_style)
	_minimap_viewport_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.add_child(_minimap_viewport_rect)

	# ── Hero dot with animated glow ──
	var hero_pos = _hero.position if _hero else Vector2(
		(_zone_w / 2.0) * TILE_SIZE + TILE_SIZE / 2.0,
		(_zone_h / 2.0) * TILE_SIZE + TILE_SIZE / 2.0
	)
	_minimap_hero_dot = TextureRect.new()
	_minimap_hero_dot.texture = c6
	_minimap_hero_dot.size = Vector2(15, 15)
	_minimap_hero_dot.modulate = Color(0.2, 0.6, 1.0)
	_minimap_hero_dot.position = Vector2(hero_pos.x * scale_mini - 7.5, hero_pos.y * scale_mini - 7.5)
	_minimap_hero_dot.z_index = 10
	_minimap_panel.add_child(_minimap_hero_dot)

	_minimap_hero_glow = TextureRect.new()
	_minimap_hero_glow.texture = c10
	_minimap_hero_glow.size = Vector2(25, 25)
	_minimap_hero_glow.position = Vector2(-5, -5)
	_minimap_hero_glow.modulate = Color(0.3, 0.7, 1.0, 0.3)
	_minimap_hero_dot.add_child(_minimap_hero_glow)
	var pulse = create_tween().set_loops()
	pulse.tween_property(_minimap_hero_glow, "modulate:a", 0.6, 1.0)
	pulse.tween_property(_minimap_hero_glow, "modulate:a", 0.2, 1.0)

	# ── Click-to-navigate (moves camera) ──
	_minimap_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_minimap_panel.gui_input.connect(_on_minimap_click)

	_minimap_scale = scale_mini

	# ═══════════════════════════════════════════
	#  LÉGENDE
	# ═══════════════════════════════════════════

	var leg_y = ZONE_H + 18
	var leg_x = 14
	var leg_items = [
		{ "tex": c5, "size": 9, "color": Color(1.0, 0.8, 0.1), "label": "Ville" },
		{ "tex": c3, "size": 8, "color": Color(0.6, 0.1, 0.8), "label": "Ennemi" },
		{ "tex": c6, "size": 10, "color": Color(0.95, 0.1, 0.1), "label": "Boss" },
		{ "tex": c3, "size": 7, "color": Color(1, 0.85, 0.15), "label": "Ressource" },
		{ "tex": c4, "size": 8, "color": Color(0.7, 0.9, 1.0), "label": "Trésor" },
		{ "tex": c6, "size": 10, "color": Color(0.2, 0.6, 1.0), "label": "Héros" },
	]
	var leg_spacing = 86
	var leg_start_x = leg_x
	for item in leg_items:
		var dot = TextureRect.new()
		dot.texture = item["tex"]
		dot.size = Vector2(item["size"], item["size"])
		dot.modulate = item["color"]
		dot.position = Vector2(leg_start_x, leg_y)
		minimap_container.add_child(dot)
		var lbl = Label.new()
		lbl.text = item["label"]
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
		lbl.position = Vector2(leg_start_x + item["size"] + 4, leg_y - 1)
		minimap_container.add_child(lbl)
		leg_start_x += leg_spacing
		if leg_start_x + leg_spacing > 560:
			leg_start_x = leg_x
			leg_y += 22

	if DEBUG_LOG:
		print("✓ Minimap créée (", ZONE_W, "×", ZONE_H, ") + légende")

func _on_minimap_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos = _minimap_panel.get_local_mouse_position()
		var world_x = local_pos.x / _minimap_scale
		var world_y = local_pos.y / _minimap_scale
		world_x = clampf(world_x, 0, _zone_w * TILE_SIZE)
		world_y = clampf(world_y, 0, _zone_h * TILE_SIZE)
		if _camera != null:
			_camera.position = Vector2(world_x, world_y)
			_update_minimap()

func _update_minimap() -> void:
	if _minimap_hero_dot == null or _hero == null or _camera == null:
		return
	var s = _minimap_scale
	_minimap_hero_dot.position = Vector2(
		_hero.position.x * s - 7.5,
		_hero.position.y * s - 7.5
	)
	if _minimap_viewport_rect != null:
		var view_size = get_viewport_rect().size / _camera.zoom
		var vp_x = (_camera.position.x - view_size.x * 0.5) * s
		var vp_y = (_camera.position.y - view_size.y * 0.5) * s
		var vp_w = view_size.x * s
		var vp_h = view_size.y * s
		_minimap_viewport_rect.position = Vector2(vp_x, vp_y)
		_minimap_viewport_rect.size = Vector2(vp_w, vp_h)

func _refresh_minimap() -> void:
	for i in range(_minimap_enemy_dots.size()):
		if i < _enemies.size():
			_minimap_enemy_dots[i].visible = _enemies[i].get("alive", true)
	for i in range(_minimap_boss_dots.size()):
		if i < _bosses.size():
			_minimap_boss_dots[i].visible = _bosses[i].get("alive", true)
	for i in range(_minimap_resource_dots.size()):
		if i < _resources.size():
			_minimap_resource_dots[i].visible = not _resources[i].get("collected", false)
	for i in range(_minimap_treasure_dots.size()):
		if i < _treasures.size():
			_minimap_treasure_dots[i].visible = not _treasures[i].get("opened", false)

func _create_floating_text(text: String, color: Color, pos: Vector2) -> void:
	while _floating_texts.size() >= MAX_FLOATING_TEXTS:
		var old: Node = _floating_texts.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var label: Label = Label.new()
	label.name = "FloatingText"
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Position dans le monde (au-dessus du héros/objet)
	label.position = pos - Vector2(40, 60)  # Décalé au-dessus
	
	add_child(label)
	_floating_texts.append(label)
	
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	
	# Monter de 40 pixels en 1.5 secondes
	tween.tween_property(label, "position:y", label.position.y - 40, 1.5)
	# S'effacer
	tween.tween_property(label, "modulate:a", 0.0, 1.5)
	
	# Supprimer après l'animation
	tween.chain().tween_callback(func():
		_floating_texts.erase(label)
		if is_instance_valid(label):
			label.queue_free()
	)

func _spawn_burst_particles(origin: Vector2, color: Color, count: int = 8) -> void:
	for i in range(count):
		var p: ColorRect = ColorRect.new()
		p.size = Vector2(4, 4)
		p.color = color
		p.position = origin - Vector2(2, 2)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(p)
		var angle: float = (float(i) / float(count)) * TAU
		var dist: float = 20.0 + randf() * 30.0
		var target: Vector2 = origin + Vector2(cos(angle), sin(angle)) * dist
		var pt = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		pt.tween_property(p, "position", target, 0.4)
		pt.parallel().tween_property(p, "modulate:a", 0.0, 0.4)
		pt.tween_callback(p.queue_free)

func _gain_xp(amount: int) -> void:
	if amount <= 0:
		return
	_hero_xp += amount
	_update_hero_panel()
	_create_floating_text("+" + str(amount) + " XP", Color(0.9, 0.7, 0.3), _hero.position - Vector2(0, 20))
	while _hero_xp >= _hero_xp_to_next:
		_level_up()

func _level_up() -> void:
	_hero_level += 1
	_hero_xp -= _hero_xp_to_next
	_hero_xp_to_next = _hero_level * XP_PER_LEVEL
	
	# Augmenter les stats du héros
	_hero_max_hp += 15
	_hero_hp = _hero_max_hp  # Soigner complètement
	_hero_attack += 3
	_hero_defense += 2
	
	# Screen flash doré
	var flash = ColorRect.new()
	flash.color = Color(1.0, 0.85, 0.2, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var ft = create_tween().set_ease(Tween.EASE_OUT)
	ft.tween_property(flash, "color:a", 0.4, 0.1).from(0.0)
	ft.tween_property(flash, "color:a", 0.0, 0.6)
	ft.tween_callback(flash.queue_free)

	# LEVEL UP banner animé
	var banner = Label.new()
	banner.text = "★ LEVEL UP! ★"
	banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	banner.add_theme_font_size_override("font_size", 36)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.position = Vector2(-200, -60)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	var bt = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	bt.tween_property(banner, "scale", Vector2(1.2, 1.2), 0.0)
	bt.tween_property(banner, "scale", Vector2(1.0, 1.0), 0.4)
	bt.parallel().tween_property(banner, "modulate:a", 1.0, 0.3).from(0.0)
	bt.tween_interval(1.0)
	bt.tween_property(banner, "modulate:a", 0.0, 0.8)
	bt.tween_callback(banner.queue_free)

	var level_label = Label.new()
	level_label.text = "Niveau " + str(_hero_level)
	level_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))
	level_label.add_theme_font_size_override("font_size", 24)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.set_anchors_preset(Control.PRESET_CENTER)
	level_label.position = Vector2(-100, -20)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(level_label)
	var lt = create_tween().set_ease(Tween.EASE_OUT)
	lt.tween_property(level_label, "modulate:a", 1.0, 0.3).from(0.0)
	lt.tween_interval(1.2)
	lt.tween_property(level_label, "modulate:a", 0.0, 0.8)
	lt.tween_callback(level_label.queue_free)
	
	print("🆙 LEVEL UP ! Niveau ", _hero_level, " atteint !")
	_update_hero_panel()

# ============================================
# SAUVEGARDE / CHARGEMENT
# ============================================

func _on_save_game_pressed() -> void:
	_save_game()
	# Feedback visuel
	_create_floating_text("💾 Partie sauvegardée !", Color(0.4, 0.8, 0.4), _hero.position)

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_fullscreen_toggled() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_hud_hero_selected(id: int) -> void:
	if id >= 0 and id < _heroes_data.size():
		_switch_hero(id)

func _on_gh_pressed() -> void:
	if _minimap_panel != null:
		var container: Control = _minimap_panel.get_parent() as Control
		if container != null:
			container.visible = not container.visible
			if container.visible:
				_update_minimap()

func _on_dh_pressed() -> void:
	# DH = Afficher les détails du héros
	if _hero_details_visible:
		_hide_hero_details()
		return
	if _hero == null:
		return
	var hero_name: String = _get_active_hero_name()
	_show_hero_details(hero_name)

func _show_hero_details(hero_name: String) -> void:
	if _hero_details_visible:
		return
	if _hud:
		var sel_panel = _hud.find_child("SelectionPanel", true, false)
		if sel_panel:
			sel_panel.visible = false
	var vp := get_viewport().get_visible_rect().size

	_hero_details_layer = CanvasLayer.new()
	_hero_details_layer.name = "HeroDetailsLayer"
	_hero_details_layer.layer = 128
	add_child(_hero_details_layer)

	_hero_details_overlay = Panel.new()
	_hero_details_overlay.name = "HeroDetailsOverlay"
	_hero_details_overlay.size = vp
	_hero_details_overlay.position = Vector2.ZERO
	var ol_style := StyleBoxFlat.new()
	ol_style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	_hero_details_overlay.add_theme_stylebox_override("panel", ol_style)
	_hero_details_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_hero_details_layer.add_child(_hero_details_overlay)

	var panel := Panel.new()
	panel.name = "HeroDetailsPanel"
	panel.size = Vector2(min(420, vp.x - 40), min(520, vp.y - 40))
	panel.position = Vector2(vp.x / 2 - panel.size.x / 2, vp.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", JapaneseUITheme.panel_style(12))
	_hero_details_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	var m := 16
	vbox.add_theme_constant_override("margin_left", m)
	vbox.add_theme_constant_override("margin_right", m)
	vbox.add_theme_constant_override("margin_top", m)
	vbox.add_theme_constant_override("margin_bottom", m)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "⚔ %s" % hero_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", JapaneseUITheme.COLOR_GOLD)
	vbox.add_child(title)

	var lvl := Label.new()
	lvl.text = "Niveau %d" % [_hero_level]
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl.add_theme_font_size_override("font_size", 14)
	lvl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	vbox.add_child(lvl)

	vbox.add_child(_make_hsep_d())

	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 24)
	stats_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(stats_grid)

	stats_grid.add_child(_hero_stat_lbl("ATK"))
	stats_grid.add_child(_hero_stat_val(str(_hero_attack), Color(0.95, 0.5, 0.5)))
	stats_grid.add_child(_hero_stat_lbl("DEF"))
	stats_grid.add_child(_hero_stat_val(str(_hero_defense), Color(0.5, 0.7, 0.95)))
	stats_grid.add_child(_hero_stat_lbl("HP"))
	stats_grid.add_child(_hero_stat_val("%d/%d" % [_hero_hp, _hero_max_hp], Color(0.5, 0.95, 0.5)))
	stats_grid.add_child(_hero_stat_lbl("MP"))
	stats_grid.add_child(_hero_stat_val("%d/%d" % [_hero_mp, _hero_max_mp], Color(0.5, 0.85, 0.95)))

	vbox.add_child(_make_hsep_d())

	var xp_label := Label.new()
	xp_label.text = "XP: %d / %d" % [_hero_xp, _hero_xp_to_next]
	xp_label.add_theme_font_size_override("font_size", 12)
	xp_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	vbox.add_child(xp_label)

	var xp_bar := ColorRect.new()
	xp_bar.custom_minimum_size = Vector2(0, 14)
	xp_bar.size = Vector2(panel.size.x - m * 2, 14)
	xp_bar.color = Color(0.15, 0.10, 0.08)
	xp_bar.add_theme_stylebox_override("panel", _bar_bg_style())
	var xp_fill := ColorRect.new()
	xp_fill.name = "XPFill"
	var xp_ratio := float(_hero_xp) / float(max(_hero_xp_to_next, 1))
	xp_fill.size = Vector2(max(2, (panel.size.x - m * 2) * xp_ratio), 14)
	xp_fill.color = Color(0.7, 0.55, 0.2)
	xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.add_child(xp_fill)
	vbox.add_child(xp_bar)

	vbox.add_child(_make_hsep_d())

	var army_title := Label.new()
	army_title.text = "Armée"
	army_title.add_theme_font_size_override("font_size", 14)
	army_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	vbox.add_child(army_title)

	if _hero_army.size() > 0:
		for unit in _hero_army:
			var u_type := str(unit.get("type", ""))
			var u_data: Dictionary = UNIT_TYPES.get(u_type, {})
			var u_name: String = u_data.get("name", u_type)
			var u_count: int = unit.get("count", 0)
			if u_count <= 0:
				continue
			var ulbl := Label.new()
			ulbl.text = "• %s x%d" % [u_name, u_count]
			ulbl.add_theme_font_size_override("font_size", 13)
			ulbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
			vbox.add_child(ulbl)
	else:
		var empty_lbl := Label.new()
		empty_lbl.text = "Aucune créature"
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.5))
		vbox.add_child(empty_lbl)

	vbox.add_child(_make_hsep_d())

	var close_hbox := HBoxContainer.new()
	close_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(close_hbox)

	var close_btn := Button.new()
	close_btn.text = "Fermer"
	close_btn.custom_minimum_size = Vector2(180, 40)
	close_btn.size = Vector2(180, 40)
	close_btn.add_theme_font_size_override("font_size", 15)
	JapaneseUITheme.style_button(close_btn)
	JapaneseUITheme.add_hover_scale(close_btn)
	close_btn.pressed.connect(_hide_hero_details)
	close_hbox.add_child(close_btn)

	_hero_details_visible = true

func _hide_hero_details() -> void:
	_hero_details_visible = false
	if _hero_details_overlay:
		_hero_details_overlay.queue_free()
		_hero_details_overlay = null
	if _hero_details_layer:
		_hero_details_layer.queue_free()
		_hero_details_layer = null

func _hero_stat_lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	l.custom_minimum_size = Vector2(80, 22)
	return l

func _hero_stat_val(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(80, 22)
	return l

func _make_hsep_d() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 8)
	r.color = Color.TRANSPARENT
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _bar_bg_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.10, 0.08)
	s.border_color = Color(0.35, 0.28, 0.18)
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	return s

func _on_gm_pressed() -> void:
	# GM = Afficher la carte du monde (zoom arrière)
	_camera.zoom = Vector2(_camera_zoom_min, _camera_zoom_min)
	_create_floating_text("Carte du monde", Color(0.7, 0.9, 0.7), _get_viewport_center())

func _on_dm_pressed() -> void:
	# DM = Afficher les détails du contexte sélectionné
	var gd = GameData
	match gd.current_mode:
		GameData.SelectionMode.CITY:
			if gd.current_id >= 0 and gd.current_id < gd.cities.size():
				var c = gd.cities[gd.current_id]
				var info = "🏯 %s\nRevenu: %d/jour\nGarnison: %d créatures" % [
					c.name, c.resource_per_day, _city_garrison_count(gd.current_id)
				]
				_create_floating_text(info, Color(0.85, 0.9, 0.5), _get_viewport_center())
		GameData.SelectionMode.HERO:
			_on_dh_pressed()
		GameData.SelectionMode.TILE:
			var ct = _creature_on_tile(gd.current_tile)
			if ct != null:
				_create_floating_text("%s x%d\nTappez pour interagir" % [ct.name, ct.amount], Color(0.9, 0.85, 0.7), _get_viewport_center())
			else:
				_create_floating_text("Terrain libre", Color(0.6, 0.7, 0.6), _get_viewport_center())
		_:
			_create_floating_text("Rien de sélectionné", Color(0.6, 0.6, 0.6), _get_viewport_center())

func _get_viewport_center() -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	return Vector2(vp.x / 2.0, vp.y / 2.0)

func _hero_army_count() -> int:
	var total = 0
	for unit in _hero_army:
		total += unit.get("count", 0)
	return total

func _city_garrison_count(city_index: int) -> int:
	if city_index >= 0 and city_index < _cities_data.size():
		return _cities_data[city_index].get("garrison", []).size()
	return 0

func _add_units_to_army(unit_type: String, count: int) -> void:
	var unit_data: Dictionary = UNIT_TYPES.get(unit_type, {})
	if unit_data.is_empty() and GameData.UNIT_TYPES.has(unit_type):
		unit_data = GameData.UNIT_TYPES[unit_type]
	if unit_data.is_empty():
		return
	for unit in _hero_army:
		if unit["type"] == unit_type:
			unit["count"] += count
			# Sync avec GameData
			if GameData.heroes.size() > 0:
				GameData.heroes[0].army.add_stack(unit_type, count)
			return
	_hero_army.append({
		"type": unit_type,
		"count": count,
		"hp": unit_data.get("hp", 10),
		"attack": unit_data.get("attack", 4),
		"defense": unit_data.get("defense", 4),
	})
	# Sync avec GameData
	if GameData.heroes.size() > 0:
		GameData.heroes[0].army.add_stack(unit_type, count)

func _creature_on_tile(tile: Vector2i) -> GameData.Creature:
	if GameData.creatures_on_tile.has(tile):
		return GameData.creatures_on_tile[tile]
	return null

func _on_pause_state_changed(is_paused: bool) -> void:
	_pause_active = is_paused

func _on_save_requested() -> void:
	_save_game()
	GameData.save_game()
	_create_floating_text("💾 Partie sauvegardée !", Color(0.4, 0.8, 0.4), _hero.position)

func _on_dbt_pressed() -> void:
	# DBT = Fin de tour + journal
	_end_turn()
	_create_floating_text("Tour terminé", Color(0.7, 0.9, 0.7), _get_viewport_center())

func _get_collected_indices(arr: Array, key: String) -> Array:
	var indices: Array = []
	for i in range(arr.size()):
		if arr[i].get(key, false):
			indices.append(i)
	return indices

func _save_game() -> void:
	var save_data = {
		"hero_level": _hero_level,
		"hero_xp": _hero_xp,
		"hero_xp_to_next": _hero_xp_to_next,
		"hero_hp": _hero_hp,
		"hero_max_hp": _hero_max_hp,
		"hero_attack": _hero_attack,
		"hero_defense": _hero_defense,
		"gold": _gold,
		"wood": _wood,
		"ore": _ore,
		"hero_pos": {"x": _hero.position.x, "y": _hero.position.y},
		"hero_tile": {"x": _hero_tile.x, "y": _hero_tile.y},
		"hero_mp": _hero_mp,
		"hero_army": _hero_army,
		"day": _game_day,
		"week": _game_week,
		"month": _game_month,
		"cities_data": _cities_data,
		"visited_cities": _visited_cities,
		"quest_progress": _quest_progress,
		"quest_completed": _quest_completed,
		"enemies": _enemies,
		"bosses": _bosses,
		"unlocked_heroes": _unlocked_heroes,
		"player_items": _player_items,
		"water_walk_turns": _water_walk_turns,
		"rng_seed": rng.seed,
		"fog_grid": _fog_grid,
		"fog_current_alpha": _fog_current_alpha,
		"resources_collected": _get_collected_indices(_resources, "collected"),
		"treasures_opened": _get_collected_indices(_treasures, "opened"),
		"camera_zoom": {"x": _camera.zoom.x, "y": _camera.zoom.y},
	}
	
	var json_string = JSON.stringify(save_data)
	var file = FileAccess.open("user://save_game.json", FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("💾 Partie sauvegardée avec succès!")
	else:
		print("❌ Erreur lors de la sauvegarde")

func _load_game() -> void:
	if not FileAccess.file_exists("user://save_game.json"):
		print("❌ Aucune sauvegarde trouvée")
		return
	
	var file = FileAccess.open("user://save_game.json", FileAccess.READ)
	if not file:
		print("❌ Impossible d'ouvrir le fichier de sauvegarde")
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		print("❌ Erreur de parsing JSON: ", json.get_error_message())
		return
	
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		print("❌ Données de sauvegarde invalides")
		return
	
	_hero_level = data.get("hero_level", 1)
	_hero_xp = data.get("hero_xp", 0)
	_hero_xp_to_next = data.get("hero_xp_to_next", XP_PER_LEVEL)
	_hero_hp = data.get("hero_hp", 100)
	_hero_max_hp = data.get("hero_max_hp", 100)
	_hero_attack = data.get("hero_attack", 10)
	_hero_defense = data.get("hero_defense", 5)
	_gold = data.get("gold", 500)
	_wood = data.get("wood", 10)
	_ore = data.get("ore", 5)
	
	var pos = data.get("hero_pos", {})
	if pos.has("x") and pos.has("y"):
		_hero.position = Vector2(pos.x, pos.y)
	
	var tile = data.get("hero_tile", {})
	if tile.has("x") and tile.has("y"):
		_hero_tile = Vector2i(tile.x, tile.y)
	
	_game_day = data.get("day", 1)
	_game_week = data.get("week", 1)
	_game_month = data.get("month", 1)
	
	_hero_mp = data.get("hero_mp", _hero_max_mp)
	_hero_army = data.get("hero_army", [])
	# Restaurer l'armée dans GameData pour le combat tactique
	if GameData.heroes.size() > 0:
		var restored_army := GameData.Army.new()
		for s in _hero_army:
			restored_army.add_stack(s.get("type", "ashigaru"), s.get("count", 1))
		GameData.heroes[0].army = restored_army
	_visited_cities = data.get("visited_cities", {})
	_quest_progress = data.get("quest_progress", {})
	_quest_completed = data.get("quest_completed", [])
	GameData.quests_completed = _quest_completed.size()
	
	var loaded_cities = data.get("cities_data", [])
	for i in range(loaded_cities.size()):
		if i < _cities_data.size():
			_cities_data[i]["owned"] = loaded_cities[i].get("owned", false)
			_cities_data[i]["garrison"] = loaded_cities[i].get("garrison", [])
			_cities_data[i]["income"] = loaded_cities[i].get("income", 500)
	
	var loaded_enemies = data.get("enemies", [])
	for i in range(loaded_enemies.size()):
		if i < _enemies.size():
			_enemies[i]["alive"] = loaded_enemies[i].get("alive", true)
	
	var loaded_bosses = data.get("bosses", [])
	for i in range(loaded_bosses.size()):
		if i < _bosses.size():
			_bosses[i]["alive"] = loaded_bosses[i].get("alive", true)
	
	var loaded_unlocked = data.get("unlocked_heroes", [])
	_unlocked_heroes = loaded_unlocked.duplicate()
	GameData.bosses_defeated = _unlocked_heroes.size()
	GameData.unlocked_heroes = []
	for h in _unlocked_heroes:
		GameData.unlocked_heroes.append(h.get("name", "Heros"))

	_player_items = data.get("player_items", [])
	_water_walk_turns = data.get("water_walk_turns", 0)

	# Restaurer le brouillard de guerre
	var loaded_fog = data.get("fog_grid", [])
	if loaded_fog.size() > 0:
		_fog_grid = loaded_fog.duplicate(true)
	var loaded_alpha = data.get("fog_current_alpha", [])
	if loaded_alpha.size() > 0:
		_fog_current_alpha = loaded_alpha.duplicate(true)

	# Restaurer l'état collecté/ouvert des ressources et trésors
	var res_collected = data.get("resources_collected", [])
	for i in res_collected:
		if i >= 0 and i < _resources.size():
			_resources[i]["collected"] = true
			if i < _resource_visuals.size():
				_resource_visuals[i].visible = false
	var tres_opened = data.get("treasures_opened", [])
	for i in tres_opened:
		if i >= 0 and i < _treasures.size():
			_treasures[i]["opened"] = true
			if i < _treasure_visuals.size():
				_treasure_visuals[i].visible = false

	# Restaurer le zoom caméra (sauvé en tant que dictionnaire x/y)
	var cam_zoom = data.get("camera_zoom", null)
	if cam_zoom != null and typeof(cam_zoom) == TYPE_DICTIONARY:
		_camera.zoom = Vector2(cam_zoom.get("x", 1.0), cam_zoom.get("y", 1.0))

	# Rafraîchir l'affichage du brouillard
	if _fog_image != null and _fog_texture != null:
		for x in range(_zone_w):
			for y in range(_zone_h):
				_paint_fog_tile(x, y)
		_fog_texture.update(_fog_image)
	_update_fog_of_war()
	_update_entity_visibility()
	_update_resource_labels()

	# Mettre à jour la caméra
	_camera.position = _hero.position
	
	# Mettre à jour l'UI
	_update_hero_panel()
	_update_date_label()
	
	print("📂 Partie chargée avec succès! Niveau ", _hero_level)

func _update_hero_panel() -> void:
	# Hero stats are managed by the HUD
	pass

func _update_date_label() -> void:
	if _label_date != null:
		_label_date.text = "Month %d  Week %d  Day %d" % [_game_month, _game_week, _game_day]

func _register_game_data() -> void:
	# Nettoyer les anciennes données
	GameData.heroes.clear()
	GameData.cities.clear()
	GameData.buildings.clear()
	GameData.creatures_on_tile.clear()

	# Enregistrer le héros du joueur
	var hero_data = GameData.Hero.new()
	hero_data.id = 0
	hero_data.name = "Samurai"
	var knight_sprite: Sprite2D = _hero.get_node_or_null("KnightSprite") if _hero else null
	hero_data.sprite = knight_sprite.texture if knight_sprite else null
	if not _cities_data.is_empty():
		var cw: Vector2 = _cities_data[0]["position"]
		var ct: Vector2i = Vector2i(int(cw.x / TILE_SIZE), int(cw.y / TILE_SIZE))
		hero_data.position = ct
		var offsets: Array[Vector2i] = [
			Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
			Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
			Vector2i(1, 2), Vector2i(-1, 2), Vector2i(1, -2), Vector2i(-1, -2),
			Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3),
		]
		for off in offsets:
			var tx: int = ct.x + off.x
			var ty: int = ct.y + off.y
			if tx < 0 or tx >= _zone_w or ty < 0 or ty >= _zone_h:
				continue
			if _terrain_move_cost.get(_terrain_grid[tx][ty], 1) >= 999:
				continue
			hero_data.position = Vector2i(tx, ty)
			break
	else:
		hero_data.position = Vector2i(_zone_w / 2, _zone_h / 2)
	hero_data.owner = 0
	hero_data.creatures = []
	# Synchroniser l'armée dans GameData
	if _hero_army.size() > 0:
		var sync_army := GameData.Army.new()
		for s in _hero_army:
			var stype: String = s.get("type", "ashigaru")
			var scount: int = s.get("count", 1)
			sync_army.add_stack(stype, scount)
		hero_data.army = sync_army
	GameData.heroes.append(hero_data)

	# Enregistrer les villes
	for i in range(_cities_data.size()):
		var cdata = _cities_data[i]
		var city_data = GameData.City.new()
		city_data.id = i
		city_data.name = cdata.get("name", "Ville %d" % (i + 1))
		city_data.position = _cities_data_to_tile(cdata["position"])
		city_data.owner = 0 if cdata.get("owned", false) else 1
		city_data.resource_type = "Or"
		city_data.resource_per_day = cdata.get("income", 500)
		city_data.creatures = []
		if cdata.get("owned", false):
			city_data.creatures = [
				_creature("Piquier", 20),
				_creature("Archer", 10),
			]
		GameData.cities.append(city_data)

	print("✓ GameData enregistré: %d héros, %d villes" % [GameData.heroes.size(), GameData.cities.size()])

func _spawn_neutral_creatures() -> void:
	var types = ["Loup", "Gobelin", "Squelette", "Araignée", "Lézard"]
	for i in range(36):
		var tx = rng.randi_range(3, _zone_w - 4)
		var ty = rng.randi_range(3, _zone_h - 4)
		var tile = Vector2i(tx, ty)
		if tile == GameData.heroes[0].position:
			continue
		var c = GameData.Creature.new()
		c.name = types[i % types.size()]
		c.amount = rng.randi_range(5, 25)
		GameData.creatures_on_tile[tile] = c
	print("✓ %d créatures neutres dispersées sur la carte" % GameData.creatures_on_tile.size())

func _creature(creature_name: String, amount: int) -> GameData.Creature:
	var c = GameData.Creature.new()
	c.name = creature_name
	c.amount = amount
	return c

func _cities_data_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x / TILE_SIZE),
		int(world_pos.y / TILE_SIZE)
	)
