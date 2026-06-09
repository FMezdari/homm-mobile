class_name SpriteGenerator extends RefCounted
# Generateur de sprites pixel art proceduraux - extrait de tile_map_world.gd

const TILE_SIZE: int = 64
var _sprite_cache: Dictionary = {}  # "type_size_seed" -> ImageTexture
# ============================================================
# GÉNÉRATEUR DE SPRITES PROCÉDURAUX PIXEL ART
# ============================================================
func _generate_sprite(type: String, size: int, variant_seed: int = -1) -> ImageTexture:
	var cache_key: String = "%s_%d_%d" % [type, size, maxi(variant_seed, 0)]
	if _sprite_cache.has(cache_key):
		return _sprite_cache[cache_key]
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if variant_seed >= 0:
		rng.seed = variant_seed
	else:
		rng.randomize()
	
	# Fond transparent
	img.fill(Color(0, 0, 0, 0))
	
	match type:
		"castle":
			_generate_castle_sprite(img, size, rng)
		"house":
			_generate_house_sprite(img, size, rng)
		"mine_gold":
			_generate_mine_sprite(img, size, rng, Color(0.9, 0.75, 0.1))
		"mine_wood":
			_generate_mine_sprite(img, size, rng, Color(0.5, 0.35, 0.2))
		"mine_ore":
			_generate_mine_sprite(img, size, rng, Color(0.6, 0.6, 0.65))
		"tower":
			_generate_tower_sprite(img, size, rng)
		"tree":
			_generate_tree_sprite(img, size, rng)
		"rock":
			_generate_rock_sprite(img, size, rng)
		"chest":
			_generate_chest_sprite(img, size, rng)
		"enemy_skeleton":
			_generate_enemy_sprite(img, size, rng, "skeleton")
		"enemy_goblin":
			_generate_enemy_sprite(img, size, rng, "goblin")
		"enemy_archer":
			_generate_archer_sprite_v2(img, size, rng)
		"enemy_swordsman":
			_generate_enemy_sprite(img, size, rng, "swordsman")
		"enemy_tengu":
			_generate_enemy_sprite(img, size, rng, "tengu")
		"enemy_kappa":
			_generate_enemy_sprite(img, size, rng, "kappa")
		"enemy_samurai":
			_generate_samurai_sprite(img, size, rng)
		"enemy_knight":
			_generate_samurai_sprite(img, size, rng)
		"enemy_ashigaru":
			_generate_ashigaru_sprite(img, size, rng)
		"enemy_ninja":
			_generate_enemy_sprite(img, size, rng, "ninja")
		"enemy_monk":
			_generate_enemy_sprite(img, size, rng, "monk")
		"hero":
			_generate_hero_sprite(img, size, rng)
		"merchant":
			_generate_merchant_sprite(img, size, rng)
		"torii":
			_generate_torii_sprite(img, size, rng)
		"lantern":
			_generate_lantern_sprite(img, size, rng)
		"shrine":
			_generate_shrine_sprite(img, size, rng)
		"sakura":
			_generate_sakura_sprite(img, size, rng)
		"well":
			_generate_well_sprite(img, size, rng)
		"bell":
			_generate_bell_sprite(img, size, rng)
		_:   
			# Fallback : cercle coloré
			for x in range(size):
				for y in range(size):
					if (x - size/2)**2 + (y - size/2)**2 < (size/3)**2:
						img.set_pixel(x, y, Color(0.5, 0.5, 0.5))
	
	# Ajouter un contour noir autour du sprite (2px pour les unités)
	var outline_thick := 1
	if type.begins_with("enemy_") or type == "hero":
		outline_thick = 2
	_add_outline(img, Color(0, 0, 0, 0.85), outline_thick)

	# Effet de lueur douce pour les éléments importants
	if type in ["mine_gold", "mine_ore", "chest", "tower"]:
		var glow_color = Color(0.9, 0.8, 0.3, 0.15) if type == "mine_gold" else Color(0.5, 0.5, 0.6, 0.12) if type == "mine_ore" else Color(0.85, 0.7, 0.2, 0.18) if type == "chest" else Color(0.3, 0.3, 0.35, 0.10)
		for x in range(size):
			for y in range(size):
				if img.get_pixel(x, y).a > 0:
					for dx in range(-2, 3):
						for dy in range(-2, 3):
							var nx = x + dx
							var ny = y + dy
							if nx >= 0 and nx < size and ny >= 0 and ny < size:
								if img.get_pixel(nx, ny).a == 0:
									var dist = sqrt(dx*dx + dy*dy)
									var alpha = glow_color.a * (1.0 - dist / 3.0)
									if alpha > 0:
										var existing = img.get_pixel(nx, ny)
										if existing.a == 0:
											img.set_pixel(nx, ny, Color(glow_color.r, glow_color.g, glow_color.b, alpha))

	var result := ImageTexture.create_from_image(img)
	_sprite_cache[cache_key] = result
	return result

func _draw_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	if w <= 0 or h <= 0:
		return
	var rx: int = max(x, 0)
	var ry: int = max(y, 0)
	var rw: int = min(w, img.get_width() - rx)
	var rh: int = min(h, img.get_height() - ry)
	if rw > 0 and rh > 0:
		img.fill_rect(Rect2i(rx, ry, rw, rh), color)

func _draw_pixel(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)

func _draw_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	for x in range(-rx, rx + 1):
		for y in range(-ry, ry + 1):
			if (x*x * ry*ry + y*y * rx*rx) <= rx*rx * ry*ry:
				_draw_pixel(img, cx + x, cy + y, color)

func _draw_circle(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			if x*x + y*y <= r*r:
				_draw_pixel(img, cx + x, cy + y, color)

func _draw_line(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color, thickness: int = 1) -> void:
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	while true:
		for tx in range(-thickness/2, thickness/2 + 1):
			for ty in range(-thickness/2, thickness/2 + 1):
				_draw_pixel(img, x0 + tx, y0 + ty, color)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

func _add_noise_to_rect(img: Image, x: int, y: int, w: int, h: int, base_color: Color, noise_amount: float, rng: RandomNumberGenerator) -> void:
	for dx in range(w):
		for dy in range(h):
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and nx < img.get_width() and ny >= 0 and ny < img.get_height():
				var noise: float = rng.randf_range(-noise_amount, noise_amount)
				var c: Color = base_color
				c.r = clamp(c.r + noise, 0, 1)
				c.g = clamp(c.g + noise, 0, 1)
				c.b = clamp(c.b + noise, 0, 1)
				img.set_pixel(nx, ny, c)

func _draw_gradient_rect(img: Image, x: int, y: int, w: int, h: int, top_color: Color, bottom_color: Color) -> void:
	for dx in range(w):
		for dy in range(h):
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and nx < img.get_width() and ny >= 0 and ny < img.get_height():
				var t: float = dy / max(1.0, float(h - 1))
				img.set_pixel(nx, ny, top_color.lerp(bottom_color, t))

func _draw_shaded_circle(img: Image, cx: int, cy: int, r: int, base_color: Color, highlight_dir: Vector2 = Vector2(-1, -1)) -> void:
	var hr: float = highlight_dir.normalized().x
	var hy: float = highlight_dir.normalized().y
	for x in range(cx - r - 1, cx + r + 2):
		for y in range(cy - r - 1, cy + r + 2):
			var dx: float = float(x - cx) / max(1, r)
			var dy: float = float(y - cy) / max(1, r)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= 1.0 and x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
				var shade: float = (dx * hr + dy * hy) * 0.25
				var c: Color = base_color
				c.r = clamp(c.r + shade, 0, 1)
				c.g = clamp(c.g + shade, 0, 1)
				c.b = clamp(c.b + shade, 0, 1)
				var edge_alpha: float = 1.0 if dist < 0.85 else (1.0 - dist) / 0.15
				c.a = clamp(edge_alpha, 0, 1)
				img.set_pixel(x, y, c)

func _draw_triangle(img: Image, x1: int, y1: int, x2: int, y2: int, x3: int, y3: int, color: Color) -> void:
	var min_x: int = min(x1, min(x2, x3))
	var max_x: int = max(x1, max(x2, x3))
	var min_y: int = min(y1, min(y2, y3))
	var max_y: int = max(y1, max(y2, y3))
	for x in range(max(0, min_x), min(img.get_width(), max_x + 1)):
		for y in range(max(0, min_y), min(img.get_height(), max_y + 1)):
			var b1: float = float((y2 - y3) * (x - x3) + (x3 - x2) * (y - y3)) / float((y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3) + 0.001)
			var b2: float = float((y3 - y1) * (x - x3) + (x1 - x3) * (y - y3)) / float((y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3) + 0.001)
			var b3: float = 1.0 - b1 - b2
			if b1 >= 0 and b2 >= 0 and b3 >= 0:
				img.set_pixel(x, y, color)

func _draw_vertical_gradient_rect(img: Image, x: int, y: int, w: int, h: int, left_color: Color, right_color: Color) -> void:
	for dx in range(w):
		for dy in range(h):
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and nx < img.get_width() and ny >= 0 and ny < img.get_height():
				var t: float = dx / max(1.0, float(w - 1))
				img.set_pixel(nx, ny, left_color.lerp(right_color, t))

func _draw_ramp(img: Image, x1: int, y1: int, w: int, h: int, top_w: int, color: Color) -> void:
	var hw: int = w / 2
	var thw: int = top_w / 2
	for dy in range(h):
		var t: float = dy / max(1.0, float(h - 1))
		var cw: int = int(lerp(float(thw * 2), float(w), t))
		var chw: int = cw / 2
		var cx: int = x1 + hw - chw
		for dx in range(cw):
			var nx: int = cx + dx
			var ny: int = y1 + dy
			if nx >= 0 and nx < img.get_width() and ny >= 0 and ny < img.get_height():
				img.set_pixel(nx, ny, color)

func _add_bevel(img: Image, x: int, y: int, w: int, h: int, highlight: Color, shadow: Color) -> void:
	for dx in range(w):
		if x + dx >= 0 and x + dx < img.get_width():
			if y >= 0 and y < img.get_height():
				img.set_pixel(x + dx, y, highlight)
			if y + h - 1 >= 0 and y + h - 1 < img.get_height():
				img.set_pixel(x + dx, y + h - 1, shadow)
	for dy in range(h):
		if y + dy >= 0 and y + dy < img.get_height():
			if x >= 0 and x < img.get_width():
				img.set_pixel(x, y + dy, highlight)
			if x + w - 1 >= 0 and x + w - 1 < img.get_width():
				img.set_pixel(x + w - 1, y + dy, shadow)

func _add_outline(img: Image, outline_color: Color = Color(0, 0, 0, 0.85), thickness: int = 1) -> void:
	"""Ajoute un contour noir autour des pixels opaques de l'image"""
	var w: int = img.get_width()
	var h: int = img.get_height()
	var outline_pixels: Array = []
	for x in range(w):
		for y in range(h):
			if img.get_pixel(x, y).a > 0.1:
				for ox in range(-thickness, thickness + 1):
					for oy in range(-thickness, thickness + 1):
						if ox == 0 and oy == 0:
							continue
						var nx: int = x + ox
						var ny: int = y + oy
						if nx >= 0 and nx < w and ny >= 0 and ny < h:
							if img.get_pixel(nx, ny).a <= 0.1:
								outline_pixels.append(Vector2i(nx, ny))
	for p in outline_pixels:
		img.set_pixel(p.x, p.y, outline_color)

func _create_elliptical_shadow(parent: Node2D, width: int, height: int, y_offset: int, opacity: float = 0.35) -> void:
	"""Crée une ombre elliptique réaliste sous un sprite"""
	var shadow_texture: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	shadow_texture.fill(Color(0, 0, 0, 0))
	
	var hw: int = width / 2
	var hh: int = height / 2
	
	# Dessiner une ellipse avec dégradé
	for x in range(width):
		for y in range(height):
			# Normaliser les coordonnées (-1 à 1)
			var nx: float = (x - hw) / float(hw)
			var ny: float = (y - hh) / float(hh)
			# Distance depuis le centre de l'ellipse
			var dist: float = nx * nx + ny * ny
			if dist <= 1.0:
				# Alpha basé sur la distance (plus foncé au centre)
				var alpha: float = opacity * (1.0 - dist * 0.5)
				shadow_texture.set_pixel(x, y, Color(0, 0, 0, alpha))
	
	var shadow_sprite: Sprite2D = Sprite2D.new()
	shadow_sprite.texture = ImageTexture.create_from_image(shadow_texture)
	shadow_sprite.position = Vector2(0, y_offset)
	shadow_sprite.set_z_index(-1)
	parent.add_child(shadow_sprite)

# --- CHÂTEAU JAPONAIS 192x192 (Shiro) ---
func _generate_castle_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2
	
	# === 1. OMBRE AU SOL ===
	_draw_rect(img, 10, s - 12, s - 20, 12, Color(0, 0, 0, 0.30))
	
	# === 2. FONDATION EN PIERRE (ishigaki) ===
	_draw_rect(img, 8, hs + 8, s - 16, hs - 12, Color(0.45, 0.42, 0.40))
	_add_noise_to_rect(img, 8, hs + 8, s - 16, hs - 12, Color(0.45, 0.42, 0.40), 0.04, rng)
	# Lignes de maçonnerie
	for fy in range(hs + 16, s - 8, 8):
		_draw_rect(img, 8, fy, s - 16, 1, Color(0.35, 0.32, 0.30))
	
	# === 3. MURS BLANCS (shirokabe) avec bois noir ===
	var wall_base: int = hs - 40
	var wall_h: int = 60
	# Mur principal blanc
	_add_noise_to_rect(img, hs - 50, wall_base, 100, wall_h, Color(0.92, 0.90, 0.85), 0.02, rng)
	# Poutres en bois noir (horizontal)
	for py in [wall_base + 8, wall_base + 24, wall_base + 40]:
		_draw_rect(img, hs - 52, py, 104, 3, Color(0.12, 0.08, 0.06))
	# Poutres verticales
	for px in [hs - 40, hs - 20, hs, hs + 20, hs + 40]:
		_draw_rect(img, px, wall_base, 3, wall_h, Color(0.12, 0.08, 0.06))
	
	# === 4. TOIT COURBÉ IRIMOYA (niveaux superposés) ===
	# Toits en tuiles vermilion foncé avec reflets
	for level in range(4):
		var roof_y: int = wall_base - 10 - (level * 22)
		var roof_w: int = 110 - (level * 18)
		var roof_x: int = hs - roof_w / 2
		
		# Couche de tuiles avec dégradé vermilion
		for ty in range(12):
			var tw: int = roof_w - abs(ty - 6) * 2
			var tx: int = hs - tw / 2
			var shade: float = 0.18 + ty * 0.012
			var r: float = 0.55 + shade * 0.8
			var g: float = 0.08 + shade * 0.15
			var b: float = 0.04 + shade * 0.08
			_draw_rect(img, tx, roof_y - ty, tw, 2, Color(r, g, b))
		
		# Bordure du toit (kawara) dorée
		_draw_rect(img, roof_x - 2, roof_y + 10, roof_w + 4, 3, Color(0.55, 0.42, 0.18))
		# Extrémités courbées avec accent doré
		_draw_circle(img, roof_x - 4, roof_y + 8, 4, Color(0.50, 0.38, 0.15))
		_draw_circle(img, roof_x + roof_w + 4, roof_y + 8, 4, Color(0.50, 0.38, 0.15))
	
	# === 5. DONJON CENTRAL (tenshu) ===
	var tenshu_x: int = hs - 20
	var tenshu_y: int = wall_base - 100
	var tenshu_w: int = 40
	var tenshu_h: int = 50
	
	# Mur blanc du tenshu
	_add_noise_to_rect(img, tenshu_x, tenshu_y, tenshu_w, tenshu_h, Color(0.92, 0.90, 0.85), 0.02, rng)
	# Poutres horizontales
	for py in [tenshu_y + 8, tenshu_y + 24, tenshu_y + 40]:
		_draw_rect(img, tenshu_x - 2, py, tenshu_w + 4, 3, Color(0.12, 0.08, 0.06))
	# Poutres verticales
	for px in [tenshu_x + 8, tenshu_x + 20, tenshu_x + 32]:
		_draw_rect(img, px, tenshu_y, 3, tenshu_h, Color(0.12, 0.08, 0.06))
	
	# Toit du tenshu (courbé)
	for ty in range(14):
		var tw: int = tenshu_w + 8 - abs(ty - 7) * 2
		var tx: int = hs - tw / 2
		var shade: float = 0.18 + ty * 0.015
		_draw_rect(img, tx, tenshu_y - 14 - ty, tw, 2, Color(shade, shade * 0.12, shade * 0.08))
	
	# === 6. FENÊTRES JAPONAISES (shoji) ===
	var window_positions: Array = [
		Vector2(hs - 35, wall_base + 12), Vector2(hs - 15, wall_base + 12), Vector2(hs + 5, wall_base + 12), Vector2(hs + 25, wall_base + 12),
		Vector2(hs - 35, wall_base + 32), Vector2(hs - 15, wall_base + 32), Vector2(hs + 5, wall_base + 32), Vector2(hs + 25, wall_base + 32)
	]
	for wp in window_positions:
		var wx: int = int(wp.x)
		var wy: int = int(wp.y)
		# Cadre en bois noir
		_draw_rect(img, wx - 5, wy - 5, 14, 14, Color(0.12, 0.08, 0.06))
		# Papier shoji (blanc translucide)
		_draw_rect(img, wx - 3, wy - 3, 10, 10, Color(0.95, 0.93, 0.88))
		# Grille en bois
		_draw_rect(img, wx, wy - 3, 1, 10, Color(0.12, 0.08, 0.06))
		_draw_rect(img, wx - 3, wy, 10, 1, Color(0.12, 0.08, 0.06))
	
	# === 7. PORTE PRINCIPALE (ōtemon) ===
	var gate_w: int = 28
	var gate_h: int = 24
	var gate_x: int = hs - gate_w / 2
	var gate_y: int = hs + 12
	
	# Piliers en bois
	_draw_rect(img, gate_x - 4, gate_y - 8, 6, gate_h + 8, Color(0.12, 0.08, 0.06))
	_draw_rect(img, gate_x + gate_w - 2, gate_y - 8, 6, gate_h + 8, Color(0.12, 0.08, 0.06))
	# Linteau
	_draw_rect(img, gate_x - 6, gate_y - 12, gate_w + 12, 6, Color(0.12, 0.08, 0.06))
	# Porte en bois
	_add_noise_to_rect(img, gate_x + 2, gate_y, gate_w - 4, gate_h, Color(0.18, 0.12, 0.06), 0.03, rng)
	# Panneaux de la porte
	_draw_rect(img, gate_x + 2, gate_y, gate_w / 2 - 2, gate_h, Color(0.15, 0.10, 0.05))
	# Poignées en métal
	_draw_rect(img, gate_x + gate_w / 2 - 2, gate_y + 10, 4, 4, Color(0.65, 0.55, 0.45))
	
	# === 8. TORII (porte shintoïste) vermilion vif ===
	var torii_x: int = hs + 55
	var torii_y: int = hs + 4
	# Piliers rouges (vermilion vif)
	_draw_rect(img, torii_x, torii_y - 20, 4, 28, Color(0.92, 0.18, 0.16))
	_draw_rect(img, torii_x + 14, torii_y - 20, 4, 28, Color(0.92, 0.18, 0.16))
	# Linteau supérieur (kasagi) courbé
	for tx in range(torii_x - 4, torii_x + 22):
		var curve: int = 2 if tx < torii_x + 2 or tx > torii_x + 16 else 0
		_draw_rect(img, tx, torii_y - 24 - curve, 2, 6, Color(0.92, 0.18, 0.16))
	# Linteau inférieur (nuki)
	_draw_rect(img, torii_x - 2, torii_y - 8, 22, 3, Color(0.92, 0.18, 0.16))
	
	# === 9. BANNIÈRE (nobori) ===
	var banner_x: int = hs - 60
	var banner_y: int = wall_base - 60
	# Poteau
	_draw_rect(img, banner_x, banner_y - 30, 3, 50, Color(0.45, 0.35, 0.25))
	# Drapeau rouge avec cercle du soleil
	for i in range(20):
		var wv: int = 2 if i % 2 == 0 else 0
		_draw_rect(img, banner_x + 4 + wv, banner_y - 28 + i, 18, 2, Color(0.85, 0.25, 0.25))
	# Cercle du soleil (hinomaru)
	_draw_circle(img, banner_x + 13, banner_y - 18, 5, Color(0.95, 0.85, 0.20))
	
	# === 10. SAKURA (cerisiers en fleurs) ===
	for tree in [[hs - 55, hs + 20], [hs + 55, hs + 18]]:
		var tx: int = tree[0]
		var ty: int = tree[1]
		# Tronc
		_draw_rect(img, tx, ty - 20, 6, 24, Color(0.35, 0.22, 0.12))
		# Branches
		_draw_rect(img, tx - 8, ty - 28, 12, 4, Color(0.32, 0.20, 0.10))
		_draw_rect(img, tx + 4, ty - 32, 10, 4, Color(0.32, 0.20, 0.10))
		# Fleurs de sakura (rose pâle)
		for fx in range(tx - 12, tx + 14, 4):
			for fy in range(ty - 36, ty - 20, 4):
				if rng.randf() < 0.6:
					var petal_color: Color = Color(0.95, 0.75, 0.85) if rng.randf() < 0.5 else Color(0.90, 0.65, 0.78)
					_draw_circle(img, fx, fy, 3, petal_color)
	
	# === 11. JARDIN ZEN (gauche) ===
	var zen_x: int = hs - 65
	var zen_y: int = hs + 10
	# Sol de gravier
	_draw_rect(img, zen_x, zen_y, 20, 16, Color(0.65, 0.60, 0.55))
	_add_noise_to_rect(img, zen_x, zen_y, 20, 16, Color(0.65, 0.60, 0.55), 0.03, rng)
	# Pierres zen
	_draw_circle(img, zen_x + 5, zen_y + 8, 4, Color(0.45, 0.42, 0.40))
	_draw_circle(img, zen_x + 14, zen_y + 5, 3, Color(0.48, 0.45, 0.43))
	# Bambou
	for bx in [zen_x + 8, zen_x + 16]:
		_draw_rect(img, bx, zen_y - 8, 2, 18, Color(0.25, 0.45, 0.30))
		_draw_rect(img, bx, zen_y - 10, 2, 2, Color(0.30, 0.50, 0.35))


# --- MAISON JAPONAISE (Minka) ---
func _generate_house_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2
	
	# Sol de terre battue
	_draw_rect(img, 6, hs + 8, s - 12, hs - 10, Color(0.55, 0.45, 0.35))
	_add_noise_to_rect(img, 6, hs + 8, s - 12, hs - 10, Color(0.55, 0.45, 0.35), 0.03, rng)
	
	# Mur principal (bois sombre avec papier shoji)
	_add_noise_to_rect(img, hs - 18, hs - 6, 36, 24, Color(0.35, 0.25, 0.18), 0.04, rng)
	
	# Poutres de bois (verticales)
	for px in [hs - 14, hs - 6, hs + 2, hs + 10, hs + 18]:
		_draw_rect(img, px, hs - 6, 3, 24, Color(0.12, 0.08, 0.06))
	
	# Poutres horizontales
	for py in [hs + 2, hs + 12]:
		_draw_rect(img, hs - 18, py, 36, 2, Color(0.12, 0.08, 0.06))
	
	# Fenêtre shoji (papier translucide)
	_draw_rect(img, hs - 8, hs - 2, 8, 10, Color(0.95, 0.93, 0.88))
	# Grille en bois
	_draw_rect(img, hs - 4, hs - 2, 1, 10, Color(0.12, 0.08, 0.06))
	_draw_rect(img, hs - 8, hs + 2, 8, 1, Color(0.12, 0.08, 0.06))
	_draw_rect(img, hs, hs - 2, 1, 10, Color(0.12, 0.08, 0.06))
	
	# Toit courbé irimoya (tuiles sombres)
	for ty in range(16):
		var tw: int = 38 - abs(ty - 8) * 2
		var tx: int = hs - tw / 2
		var shade: float = 0.18 + ty * 0.012
		_draw_rect(img, tx, hs - 20 - ty, tw, 2, Color(shade, shade * 0.12, shade * 0.08))
	
	# Bordure du toit (kawara)
	_draw_rect(img, hs - 20, hs - 6, 40, 3, Color(0.20, 0.12, 0.08))
	# Extrémités courbées
	_draw_circle(img, hs - 22, hs - 8, 4, Color(0.18, 0.10, 0.06))
	_draw_circle(img, hs + 22, hs - 8, 4, Color(0.18, 0.10, 0.06))
	
	# Porte coulissante (shoji)
	_draw_rect(img, hs + 8, hs + 4, 8, 14, Color(0.95, 0.93, 0.88))
	_draw_rect(img, hs + 10, hs + 4, 1, 14, Color(0.12, 0.08, 0.06))
	_draw_rect(img, hs + 8, hs + 8, 8, 1, Color(0.12, 0.08, 0.06))
	_draw_rect(img, hs + 8, hs + 12, 8, 1, Color(0.12, 0.08, 0.06))
	
	# Ombre
	_draw_rect(img, 10, s - 5, s - 20, 3, Color(0, 0, 0, 0.25))

# --- MINE 96x96 MEGA DÉTAILLÉE ---
func _generate_mine_sprite(img: Image, size: int, rng: RandomNumberGenerator, accent_color: Color) -> void:
	var s: int = size
	var hs: int = s / 2

	_draw_rect(img, hs - 40, s - 8, 80, 6, Color(0, 0, 0, 0.22))

	var is_gold: bool = abs(accent_color.r - 0.9) < 0.1

	_draw_rect(img, 4, hs + 4, s - 8, hs - 8, Color(0.38, 0.30, 0.22))

	for _i in range(10):
		var gx: int = rng.randi_range(4, s - 8)
		var gy: int = rng.randi_range(hs + 6, s - 10)
		_draw_rect(img, gx, gy, rng.randi_range(3, 5), rng.randi_range(2, 3), Color(0.44, 0.37, 0.28))

	_draw_rect(img, hs - 24, hs - 14, 48, 40, Color(0.04, 0.03, 0.02))
	_draw_rect(img, hs - 20, hs - 10, 40, 32, Color(0.03, 0.02, 0.01))
	_draw_rect(img, hs - 16, hs - 6, 32, 24, Color(0.02, 0.01, 0.005))

	_draw_rect(img, hs - 28, hs - 20, 56, 8, Color(0.45, 0.28, 0.16))
	_draw_rect(img, hs - 26, hs - 22, 52, 4, Color(0.38, 0.24, 0.14))
	_draw_rect(img, hs - 28, hs + 26, 56, 6, Color(0.40, 0.26, 0.15))

	_draw_rect(img, hs - 26, hs - 14, 6, 40, Color(0.42, 0.26, 0.15))
	_draw_rect(img, hs + 20, hs - 14, 6, 40, Color(0.42, 0.26, 0.15))

	if is_gold:
		for _i in range(18):
			var fx: int = rng.randi_range(hs - 20, hs + 16)
			var fy: int = rng.randi_range(hs - 10, hs + 20)
			_draw_rect(img, fx, fy, rng.randi_range(3, 5), rng.randi_range(2, 3), Color(0.85, 0.70, 0.08))
			_draw_rect(img, fx + 1, fy, 2, 1, Color(0.95, 0.85, 0.30))

		for _i in range(6):
			var sx: int = rng.randi_range(hs - 16, hs + 14)
			var sy: int = rng.randi_range(hs - 6, hs + 16)
			_draw_rect(img, sx, sy, 3, 3, Color(1.0, 0.95, 0.70))
			_draw_rect(img, sx + 1, sy + 1, 1, 1, Color(1.0, 1.0, 0.95))

		_draw_rect(img, hs - 14, hs + 16, 28, 10, Color(0.20, 0.14, 0.06))
		_draw_rect(img, hs - 12, hs + 14, 24, 3, Color(0.28, 0.20, 0.10))
		for _j in range(5):
			var cx: int = rng.randi_range(hs - 10, hs + 6)
			var cy: int = rng.randi_range(hs + 14, hs + 22)
			_draw_rect(img, cx, cy, 4, 3, Color(0.90, 0.75, 0.10))
			_draw_rect(img, cx + 1, cy, 2, 1, Color(0.95, 0.88, 0.30))
	else:
		for _i in range(14):
			var fx: int = rng.randi_range(hs - 20, hs + 16)
			var fy: int = rng.randi_range(hs - 10, hs + 20)
			_draw_rect(img, fx, fy, rng.randi_range(3, 5), rng.randi_range(2, 3), accent_color)

		_draw_rect(img, hs - 14, hs + 16, 28, 10, Color(0.20, 0.14, 0.06))
		_draw_rect(img, hs - 12, hs + 14, 24, 3, Color(0.28, 0.20, 0.10))
		for _j in range(4):
			var cx: int = rng.randi_range(hs - 10, hs + 6)
			var cy: int = rng.randi_range(hs + 14, hs + 22)
			_draw_rect(img, cx, cy, 4, 3, accent_color)

	_draw_rect(img, hs + 18, hs - 22, 2, 12, Color(0.20, 0.16, 0.10))
	_draw_rect(img, hs + 16, hs - 10, 6, 8, Color(0.50, 0.50, 0.55))
	_draw_rect(img, hs + 17, hs - 8, 4, 4, Color(0.95, 0.80, 0.15))
	for gy in range(hs - 8, hs + 2, 3):
		_draw_rect(img, hs + 18, gy, 4, 2, Color(1.0, 0.95, 0.60, 0.30))

	_draw_rect(img, hs - 18, hs + 24, 6, 10, Color(0.38, 0.24, 0.14))
	_draw_rect(img, hs - 16, hs + 22, 3, 3, Color(0.50, 0.38, 0.25))
	_draw_rect(img, hs + 12, hs + 24, 6, 10, Color(0.38, 0.24, 0.14))
	_draw_rect(img, hs + 13, hs + 22, 3, 3, Color(0.50, 0.38, 0.25))

# --- TOUR 96x96 MEGA DÉTAILLÉE ---
func _generate_tower_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	# Ombre portée
	_draw_rect(img, 8, s - 6, s - 16, 8, Color(0, 0, 0, 0.30))

	# Base rocheuse texturée
	_add_noise_to_rect(img, hs - 22, hs + 10, 44, 14, Color(0.36, 0.34, 0.30), 0.05, rng)
	_draw_circle(img, hs - 8, hs + 14, 12, Color(0.40, 0.38, 0.34))
	_draw_circle(img, hs + 10, hs + 16, 10, Color(0.42, 0.40, 0.36))

	# Socle de la tour — pierre sombre
	var tw: int = 30
	var th: int = 56
	var tx: int = hs - tw / 2
	var ty: int = hs - 18

	# Murs en pierre texturés (bois/plâtre japonais)
	_add_noise_to_rect(img, tx, ty, tw, th, Color(0.42, 0.40, 0.36), 0.05, rng)
	# Colonnes d'angle (bois foncé)
	_draw_rect(img, tx, ty, 3, th, Color(0.24, 0.14, 0.06))
	_draw_rect(img, tx + tw - 3, ty, 3, th, Color(0.24, 0.14, 0.06))
	# Poutres horizontales (engawa)
	for by in [ty + 12, ty + 24, ty + 36, ty + 48]:
		_draw_rect(img, tx + 3, by, tw - 6, 2, Color(0.20, 0.12, 0.04))

	# Fenêtres style japonais (shoji) — 3 fenêtres
	var windows: Array = [
		Vector2i(hs - 8, ty + 14), Vector2i(hs + 2, ty + 14),
		Vector2i(hs - 4, ty + 38),
	]
	for wx in windows:
		var ww: int = 8
		var wh: int = 10
		# Cadre bois clair
		_draw_rect(img, wx.x - 1, wx.y - 1, ww + 2, 1, Color(0.30, 0.18, 0.08))
		_draw_rect(img, wx.x - 1, wx.y + wh, ww + 2, 1, Color(0.30, 0.18, 0.08))
		_draw_rect(img, wx.x - 1, wx.y, 1, wh, Color(0.30, 0.18, 0.08))
		_draw_rect(img, wx.x + ww, wx.y, 1, wh, Color(0.30, 0.18, 0.08))
		# Grille shoji (traits croisés)
		_draw_rect(img, wx.x, wx.y, ww, wh, Color(0.12, 0.14, 0.18))
		_draw_rect(img, wx.x + 3, wx.y, 2, wh, Color(0.34, 0.34, 0.36))
		_draw_rect(img, wx.x, wx.y + 4, ww, 2, Color(0.34, 0.34, 0.36))
		# Lueur tamisée (papier washi)
		_draw_rect(img, wx.x + 1, wx.y + 1, ww - 2, wh - 2, Color(0.20, 0.22, 0.28))
		_draw_rect(img, wx.x + 2, wx.y + 2, ww - 4, wh - 4, Color(0.28, 0.30, 0.36))

	# Porte (kido) — bois sombre avec ferrures
	_draw_rect(img, hs - 6, hs + 12, 12, 16, Color(0.16, 0.08, 0.03))
	for px in [hs - 4, hs, hs + 4]:
		_draw_rect(img, px, hs + 12, 2, 16, Color(0.12, 0.06, 0.02))
	# Ferrure bande
	_draw_rect(img, hs - 5, hs + 16, 10, 2, Color(0.50, 0.48, 0.44))
	_draw_rect(img, hs - 5, hs + 22, 10, 2, Color(0.50, 0.48, 0.44))
	_draw_rect(img, hs - 1, hs + 20, 2, 2, Color(0.55, 0.52, 0.48))

	# Premier étage toit (irimoya / hongawarabuki) — tuiles
	var roof_base: int = ty - 2
	# Débord de toit
	_draw_rect(img, tx - 4, roof_base, tw + 8, 4, Color(0.38, 0.12, 0.04))
	# Tuiles rangée 1
	_draw_rect(img, tx - 2, roof_base - 6, tw + 4, 6, Color(0.44, 0.16, 0.06))
	_draw_rect(img, tx - 2, roof_base - 5, tw + 4, 1, Color(0.34, 0.10, 0.03))
	# Lignes de tuiles
	for tl in [tx - 1, tx + 5, tx + 11, tx + 17, tx + 23]:
		_draw_rect(img, tl, roof_base - 5, 1, 4, Color(0.30, 0.08, 0.02))
	# Bord de tuile arrondi
	_draw_rect(img, tx - 2, roof_base - 7, 2, 2, Color(0.50, 0.22, 0.10))
	_draw_rect(img, tx + tw, roof_base - 7, 2, 2, Color(0.50, 0.22, 0.10))

	# Deuxième étage (retrait)
	var tw2: int = 22
	var tx2: int = hs - tw2 / 2
	var roof2_y: int = roof_base - 12
	_draw_rect(img, tx2 - 3, roof2_y, tw2 + 6, 4, Color(0.40, 0.14, 0.05))
	_draw_rect(img, tx2 - 1, roof2_y - 6, tw2 + 2, 6, Color(0.48, 0.18, 0.07))
	_draw_rect(img, tx2 - 1, roof2_y - 5, tw2 + 2, 1, Color(0.36, 0.10, 0.03))
	for tl in [tx2, tx2 + 5, tx2 + 10, tx2 + 15]:
		_draw_rect(img, tl, roof2_y - 5, 1, 4, Color(0.32, 0.08, 0.02))
	_draw_rect(img, tx2 - 1, roof2_y - 7, 2, 2, Color(0.52, 0.24, 0.12))
	_draw_rect(img, tx2 + tw2 - 1, roof2_y - 7, 2, 2, Color(0.52, 0.24, 0.12))

	# Troisième étage (dernier retrait) + flèche
	var tw3: int = 14
	var tx3: int = hs - tw3 / 2
	var roof3_y: int = roof2_y - 10
	_draw_rect(img, tx3 - 2, roof3_y, tw3 + 4, 3, Color(0.42, 0.16, 0.06))
	_draw_rect(img, tx3, roof3_y - 5, tw3, 5, Color(0.50, 0.20, 0.08))
	_draw_rect(img, tx3, roof3_y - 4, tw3, 1, Color(0.38, 0.12, 0.03))
	# Flèche dorée (so-ringe / onigawara)
	_draw_rect(img, hs - 2, roof3_y - 10, 4, 6, Color(0.80, 0.65, 0.15))
	_draw_rect(img, hs - 1, roof3_y - 12, 2, 3, Color(0.88, 0.72, 0.20))
	_draw_rect(img, hs, roof3_y - 14, 1, 3, Color(0.92, 0.78, 0.25))

	# Lanterne suspendue (tsuridoro) sous le premier débord
	var lantern_x: int = tx - 4
	var lantern_y: int = roof_base + 2
	_draw_rect(img, lantern_x, lantern_y + 2, 4, 6, Color(0.65, 0.15, 0.08))
	_draw_rect(img, lantern_x + 1, lantern_y + 3, 2, 4, Color(0.82, 0.20, 0.12))
	_draw_rect(img, lantern_x + 1, lantern_y + 2, 2, 1, Color(0.50, 0.10, 0.04))
	_draw_rect(img, lantern_x + 1, lantern_y + 7, 2, 1, Color(0.50, 0.10, 0.04))
	# Lueur de la lanterne
	_draw_circle(img, lantern_x + 2, lantern_y + 5, 4, Color(0.90, 0.60, 0.10, 0.25))

	# Mousse sur la base
	for mx in [tx + 2, tx + 8, tx + 16]:
		var my: int = ty + th - rng.randi_range(4, 10)
		_draw_circle(img, mx, my, rng.randi_range(3, 5), Color(0.18, 0.34, 0.10))
		_draw_circle(img, mx - 1, my + 1, rng.randi_range(2, 3), Color(0.22, 0.38, 0.12))

	# Petites brèches
	_draw_rect(img, tx + 6, ty + 20, 4, 3, Color(0.34, 0.32, 0.28))
	_draw_rect(img, tx + 18, ty + 32, 3, 4, Color(0.30, 0.28, 0.26))

	# Herbe et buissons autour
	_draw_circle(img, 10, hs + 20, 5, Color(0.35, 0.42, 0.16))
	_draw_circle(img, s - 10, hs + 18, 4, Color(0.32, 0.40, 0.14))
	_draw_circle(img, 16, hs + 24, 3, Color(0.40, 0.46, 0.18))
	# Petit caillou
	_draw_circle(img, hs + 20, hs + 26, 3, Color(0.48, 0.48, 0.52))

# --- ARBRE 96x96 MEGA DÉTAILLÉ ---
func _generate_tree_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2
	
	# Ombre large
	_draw_rect(img, 14, s - 8, s - 28, 8, Color(0, 0, 0, 0.22))
	
	# Tronc (beaucoup plus épais avec texture de bark)
	_add_noise_to_rect(img, hs - 8, hs + 6, 16, 36, Color(0.30, 0.18, 0.08), 0.05, rng)
	# Bark lines verticales
	for bx in [hs - 6, hs - 2, hs + 2, hs + 6]:
		_draw_rect(img, bx, hs + 8, 2, 32, Color(0.26, 0.15, 0.06))
	# Nœuds sur le tronc (plus nombreux)
	_draw_rect(img, hs - 6, hs + 12, 4, 4, Color(0.25, 0.14, 0.06))
	_draw_rect(img, hs + 2, hs + 22, 4, 4, Color(0.25, 0.14, 0.06))
	_draw_rect(img, hs - 5, hs + 30, 3, 5, Color(0.27, 0.16, 0.07))
	_draw_rect(img, hs + 3, hs + 16, 3, 3, Color(0.24, 0.13, 0.05))
	# Champignon sur tronc
	_draw_rect(img, hs + 8, hs + 18, 4, 3, Color(0.65, 0.15, 0.15))
	_draw_rect(img, hs + 9, hs + 21, 2, 3, Color(0.35, 0.28, 0.20))
	# Mousse sur le tronc
	for mry in [hs + 10, hs + 20, hs + 30]:
		_draw_rect(img, hs - 10, mry, 4, 3, Color(0.20, 0.36, 0.10))
	
	# Branches (plus nombreuses et détaillées)
	# Branche gauche bas
	_draw_rect(img, hs - 22, hs - 2, 16, 5, Color(0.28, 0.16, 0.08))
	_draw_rect(img, hs - 20, hs - 4, 12, 3, Color(0.26, 0.14, 0.06))
	# Branche droite bas
	_draw_rect(img, hs + 8, hs - 8, 18, 5, Color(0.28, 0.16, 0.08))
	_draw_rect(img, hs + 10, hs - 10, 14, 3, Color(0.26, 0.14, 0.06))
	# Branche gauche haut
	_draw_rect(img, hs - 18, hs - 14, 12, 4, Color(0.26, 0.15, 0.07))
	# Branche droite haut
	_draw_rect(img, hs + 6, hs - 18, 14, 4, Color(0.26, 0.15, 0.07))
	# Branche centrale
	_draw_rect(img, hs - 2, hs - 26, 4, 10, Color(0.27, 0.16, 0.08))
	
	# Feuillage en multiples couches (cercles plus grands et variés)
	# Couche 1 (fond sombre) - verts plus riches
	_draw_circle(img, hs, hs - 18, 34, Color(0.06, 0.22, 0.03))
	_draw_circle(img, hs - 10, hs - 26, 26, Color(0.07, 0.24, 0.04))
	_draw_circle(img, hs + 12, hs - 24, 24, Color(0.07, 0.24, 0.04))
	_draw_circle(img, hs - 6, hs - 34, 20, Color(0.08, 0.26, 0.05))
	# Couche 2 (moyen) - verts vifs
	_draw_circle(img, hs, hs - 22, 30, Color(0.10, 0.35, 0.06))
	_draw_circle(img, hs - 8, hs - 30, 22, Color(0.12, 0.38, 0.07))
	_draw_circle(img, hs + 10, hs - 28, 20, Color(0.12, 0.38, 0.07))
	_draw_circle(img, hs, hs - 38, 16, Color(0.14, 0.42, 0.09))
	# Couche 3 (clair) - verts lumineux
	_draw_circle(img, hs, hs - 26, 26, Color(0.15, 0.44, 0.10))
	_draw_circle(img, hs - 6, hs - 36, 18, Color(0.18, 0.48, 0.12))
	_draw_circle(img, hs + 6, hs - 40, 14, Color(0.20, 0.50, 0.14))
	_draw_circle(img, hs - 2, hs - 44, 10, Color(0.22, 0.52, 0.16))
	# Highlight (éclat lumineux)
	_draw_circle(img, hs + 10, hs - 38, 8, Color(0.28, 0.56, 0.20))
	_draw_circle(img, hs - 4, hs - 42, 6, Color(0.30, 0.58, 0.22))
	# Grappes de feuilles
	_draw_circle(img, hs + 14, hs - 16, 8, Color(0.12, 0.36, 0.08))
	_draw_circle(img, hs - 14, hs - 20, 8, Color(0.12, 0.36, 0.08))
	_draw_circle(img, hs + 8, hs - 48, 6, Color(0.18, 0.44, 0.12))
	
	# Nid d'oiseau (petit dans une branche)
	_draw_rect(img, hs + 10, hs - 22, 6, 4, Color(0.42, 0.32, 0.20))
	_draw_rect(img, hs + 11, hs - 23, 4, 2, Color(0.35, 0.25, 0.15))
	# Petit oiseau
	_draw_rect(img, hs + 8, hs - 26, 3, 2, Color(0.55, 0.20, 0.15))
	
	# Pommes/fruits (petits points rouges)
	for fx in [hs - 8, hs + 6, hs - 2, hs + 10]:
		var fy: int = rng.randi_range(hs - 18, hs - 8)
		_draw_rect(img, fx, fy, 2, 2, Color(0.75, 0.12, 0.12))
	
	# Racines visibles (plus nombreuses)
	_draw_rect(img, hs - 12, hs + 30, 8, 5, Color(0.26, 0.16, 0.08))
	_draw_rect(img, hs + 4, hs + 30, 8, 5, Color(0.26, 0.16, 0.08))
	_draw_rect(img, hs - 16, hs + 32, 6, 4, Color(0.24, 0.14, 0.07))
	_draw_rect(img, hs + 10, hs + 32, 6, 4, Color(0.24, 0.14, 0.07))
	_draw_rect(img, hs - 18, hs + 34, 4, 3, Color(0.22, 0.13, 0.06))
	
	# Herbe et fleurs au pied
	_draw_circle(img, hs - 20, hs + 34, 5, Color(0.18, 0.38, 0.10))
	_draw_circle(img, hs + 18, hs + 34, 4, Color(0.18, 0.38, 0.10))
	_draw_circle(img, hs - 14, hs + 38, 3, Color(0.22, 0.42, 0.12))
	# Fleurs
	_draw_rect(img, hs - 16, hs + 36, 2, 2, Color(0.82, 0.18, 0.22))
	_draw_rect(img, hs + 14, hs + 36, 2, 2, Color(0.85, 0.70, 0.15))
	_draw_rect(img, hs - 8, hs + 38, 2, 2, Color(0.75, 0.12, 0.65))
	# Caillou
	_draw_circle(img, hs + 20, hs + 36, 2, Color(0.48, 0.48, 0.52))

# --- ROCHER 96x96 POLI JAPONAIS ---
func _generate_rock_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	# Ombre portée plus marquée
	_draw_rect(img, 8, s - 6, s - 16, 8, Color(0, 0, 0, 0.30))

	# Rocher principal — formes anguleuses superposées (style jardin zen)
	_add_noise_to_rect(img, hs - 24, hs + 8, 48, 18, Color(0.32, 0.32, 0.36), 0.04, rng)
	_add_noise_to_rect(img, hs - 20, hs - 4, 40, 16, Color(0.40, 0.40, 0.44), 0.04, rng)
	_add_noise_to_rect(img, hs - 16, hs - 14, 32, 14, Color(0.48, 0.48, 0.52), 0.04, rng)
	_add_noise_to_rect(img, hs - 12, hs - 22, 24, 12, Color(0.56, 0.56, 0.60), 0.04, rng)
	_add_noise_to_rect(img, hs - 8, hs - 28, 16, 10, Color(0.64, 0.64, 0.68), 0.04, rng)

	# Arêtes vives (lignes de fracture)
	_draw_rect(img, hs - 14, hs + 2, 28, 2, Color(0.28, 0.28, 0.32))
	_draw_rect(img, hs - 10, hs - 8, 20, 2, Color(0.36, 0.36, 0.40))
	_draw_rect(img, hs - 6, hs - 18, 12, 2, Color(0.44, 0.44, 0.48))

	# Facette lumineuse (highlight décalé)
	_draw_rect(img, hs - 6, hs - 26, 10, 6, Color(0.72, 0.72, 0.76))
	_draw_rect(img, hs - 4, hs - 28, 6, 4, Color(0.80, 0.80, 0.84))
	_draw_rect(img, hs - 2, hs - 30, 4, 3, Color(0.88, 0.88, 0.92))

	# Texture granitique (points)
	for _i in range(30):
		var gx: int = rng.randi_range(hs - 22, hs + 22)
		var gy: int = rng.randi_range(hs - 26, hs + 14)
		_draw_rect(img, gx, gy, 2, 2, Color(0.50, 0.50, 0.55))
		_draw_rect(img, gx + 1, gy + 1, 1, 1, Color(0.60, 0.60, 0.65))

	# Mousse japonaise (koke) — patches délibérés, pas aléatoires
	for mx in [hs - 18, hs - 14, hs - 22]:
		var my: int = rng.randi_range(hs - 2, hs + 10)
		_draw_circle(img, mx, my, rng.randi_range(4, 7), Color(0.14, 0.30, 0.10))
		_draw_circle(img, mx + 1, my - 1, rng.randi_range(2, 4), Color(0.20, 0.38, 0.14))
	# Lichen doré (accents)
	for lx in [hs + 10, hs + 16, hs - 8]:
		var ly: int = rng.randi_range(hs - 14, hs + 4)
		_draw_circle(img, lx, ly, rng.randi_range(2, 3), Color(0.55, 0.42, 0.20))
		_draw_circle(img, lx + 1, ly, 1, Color(0.62, 0.48, 0.24))

	# Petite veine de quartz/claire
	_draw_rect(img, hs + 4, hs - 6, 2, 14, Color(0.68, 0.66, 0.72))
	_draw_rect(img, hs + 5, hs - 4, 1, 10, Color(0.85, 0.83, 0.88))
	_draw_rect(img, hs - 8, hs + 6, 12, 2, Color(0.60, 0.58, 0.64))
	_draw_rect(img, hs - 6, hs + 7, 8, 1, Color(0.78, 0.76, 0.80))

	# Fissures — plus naturelles
	_draw_rect(img, hs - 6, hs - 4, 2, 10, Color(0.18, 0.18, 0.22))
	_draw_rect(img, hs - 5, hs - 2, 1, 8, Color(0.10, 0.10, 0.12))
	_draw_rect(img, hs + 10, hs - 12, 2, 8, Color(0.20, 0.20, 0.24))
	_draw_rect(img, hs + 11, hs - 10, 1, 6, Color(0.12, 0.12, 0.14))

	# Petits cailloux arrangés (style jardin zen)
	var pebbles: Array = [
		Vector2i(hs - 28, hs + 22), Vector2i(hs + 24, hs + 20),
		Vector2i(hs + 18, hs + 26), Vector2i(hs - 22, hs + 28),
		Vector2i(hs + 12, hs + 30), Vector2i(hs - 12, hs + 26),
		Vector2i(hs + 28, hs + 14), Vector2i(hs - 30, hs + 18),
	]
	for p in pebbles:
		var pr: int = rng.randi_range(2, 4)
		_draw_circle(img, p.x, p.y, pr, Color(0.40, 0.40, 0.44))
		_draw_rect(img, p.x - 1, p.y - 1, 2, 1, Color(0.55, 0.55, 0.58))

	# Herbe et feuilles mortes
	_draw_circle(img, hs + 22, hs + 16, 4, Color(0.28, 0.40, 0.14))
	_draw_circle(img, hs - 24, hs + 14, 3, Color(0.26, 0.38, 0.12))
	_draw_rect(img, hs + 16, hs + 20, 3, 4, Color(0.30, 0.42, 0.16))
	# Petite fleur
	_draw_rect(img, hs + 26, hs + 18, 2, 2, Color(0.85, 0.12, 0.18))
	_draw_rect(img, hs + 27, hs + 20, 2, 3, Color(0.15, 0.35, 0.08))

# --- COFFRE 64x64 DÉTAILLÉ ---
func _generate_chest_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2
	var wood_dark: Color = Color(0.38, 0.22, 0.10)
	var wood_mid: Color = Color(0.52, 0.32, 0.16)
	var wood_light: Color = Color(0.62, 0.40, 0.22)
	var gold: Color = Color(0.92, 0.78, 0.20)
	var gold_dark: Color = Color(0.75, 0.60, 0.12)
	
	# Ombre
	_draw_rect(img, 8, s - 6, s - 16, 6, Color(0, 0, 0, 0.30))
	
	# Corps du coffre (base)
	_add_noise_to_rect(img, hs - 18, hs - 4, 36, 24, wood_dark, 0.04, rng)
	# Planches verticales
	for px in [hs - 14, hs - 6, hs + 2, hs + 10]:
		_draw_rect(img, px, hs - 4, 2, 24, Color(0.28, 0.16, 0.08))
	
	# Couvercle (plus clair, légèrement arrondi en haut)
	_add_noise_to_rect(img, hs - 18, hs - 20, 36, 18, wood_mid, 0.04, rng)
	# Planches du couvercle
	for px in [hs - 14, hs - 6, hs + 2, hs + 10]:
		_draw_rect(img, px, hs - 20, 2, 18, Color(0.35, 0.20, 0.10))
	
	# Courbe du couvercle (highlight au centre)
	_draw_rect(img, hs - 12, hs - 22, 24, 4, wood_light)
	_draw_rect(img, hs - 8, hs - 24, 16, 3, Color(0.68, 0.44, 0.24))
	
	# Bandes métalliques dorées (verticales)
	_draw_rect(img, hs - 18, hs - 20, 4, 40, gold_dark)
	_draw_rect(img, hs + 14, hs - 20, 4, 40, gold_dark)
	# Rivets sur les bandes
	for ry in [hs - 16, hs - 8, hs, hs + 8, hs + 14]:
		_draw_rect(img, hs - 17, ry, 2, 2, gold)
		_draw_rect(img, hs + 15, ry, 2, 2, gold)
	
	# Serrure centrale
	_draw_rect(img, hs - 5, hs - 6, 10, 10, gold_dark)
	_draw_rect(img, hs - 3, hs - 4, 6, 6, gold)
	_draw_rect(img, hs - 1, hs - 2, 2, 2, Color(0.20, 0.15, 0.05))
	
	# Trou de la serrure
	_draw_rect(img, hs - 1, hs - 4, 2, 3, Color(0.15, 0.10, 0.05))
	
	# Éclats de lumière sur le couvercle (reflet)
	_draw_rect(img, hs - 8, hs - 18, 4, 2, Color(1.0, 0.95, 0.80))
	_draw_rect(img, hs + 4, hs - 16, 3, 2, Color(1.0, 0.95, 0.80))

# --- SAMOURAÏ 64x64 — écusson / mon style kabuto ---
func _generate_samurai_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	# Ombre au sol
	_draw_ellipse(img, hs, s - 3, 14, 4, Color(0, 0, 0, 0.30))

	# Cercle de fond (écusson noir)
	_draw_circle(img, hs, hs, 22, Color(0.08, 0.05, 0.04))
	_draw_circle(img, hs, hs, 18, Color(0.12, 0.08, 0.06))

	# === KABUTO (casque) — forme épaisse et lisible ===
	# Dôme du casque
	_draw_rect(img, hs - 14, hs - 18, 28, 16, Color(0.08, 0.05, 0.04))
	_draw_rect(img, hs - 12, hs - 16, 24, 12, Color(0.25, 0.15, 0.12))
	# Rebord du casque (mabizashi)
	_draw_rect(img, hs - 16, hs - 4, 32, 4, Color(0.08, 0.05, 0.04))
	_draw_rect(img, hs - 16, hs - 4, 32, 2, Color(0.85, 0.18, 0.16))
	# Shikoro (protège-nuque) — 3 lames
	for i in range(3):
		var sy = hs + 2 + i * 3
		_draw_rect(img, hs - 14 + i * 2, sy, 28 - i * 4, 3, Color(0.08, 0.05, 0.04))
		_draw_rect(img, hs - 14 + i * 2, sy, 28 - i * 4, 1, Color(0.85, 0.18, 0.16))

	# Maedate (crête avant) — ornement doré en V
	_draw_rect(img, hs - 1, hs - 30, 2, 14, Color(0.95, 0.82, 0.18))
	_draw_rect(img, hs - 6, hs - 32, 12, 3, Color(0.95, 0.82, 0.18))
	_draw_rect(img, hs - 4, hs - 34, 8, 2, Color(0.85, 0.70, 0.10))

	# Mon (blason central) — petit cercle rouge
	_draw_circle(img, hs, hs + 4, 4, Color(0.85, 0.18, 0.16))
	_draw_circle(img, hs, hs + 4, 2, Color(0.95, 0.82, 0.18))

	# === KATANA (lame diagonale traversant l'écusson) ===
	# Lame
	_draw_line(img, hs - 8, hs + 18, hs + 16, hs - 18, Color(0.82, 0.80, 0.75), 4)
	# Brillance
	_draw_line(img, hs - 7, hs + 18, hs + 17, hs - 18, Color(0.95, 0.93, 0.90), 1)
	# Tsuba (garde)
	_draw_circle(img, hs + 4, hs + 6, 5, Color(0.85, 0.18, 0.16))
	_draw_circle(img, hs + 4, hs + 6, 3, Color(0.95, 0.82, 0.18))


# --- ASHIGARU 64x64 — écusson / mon style yari ---
func _generate_ashigaru_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	# Ombre au sol
	_draw_ellipse(img, hs, s - 3, 14, 4, Color(0, 0, 0, 0.30))

	# Fond losange (écusson brun)
	_draw_triangle(img, hs, hs - 24, hs - 22, hs, hs, hs + 24, Color(0.32, 0.22, 0.14))
	_draw_triangle(img, hs, hs - 24, hs + 22, hs, hs, hs + 24, Color(0.32, 0.22, 0.14))
	_draw_triangle(img, hs, hs - 20, hs - 18, hs, hs, hs + 20, Color(0.40, 0.28, 0.18))
	_draw_triangle(img, hs, hs - 20, hs + 18, hs, hs, hs + 20, Color(0.40, 0.28, 0.18))

	# === JINGASA (chapeau conique) en haut du losange ===
	_draw_rect(img, hs - 12, hs - 26, 24, 8, Color(0.50, 0.35, 0.22))
	_draw_rect(img, hs - 8, hs - 30, 16, 6, Color(0.45, 0.32, 0.20))
	_draw_rect(img, hs - 4, hs - 32, 8, 4, Color(0.42, 0.30, 0.18))
	# Bord large
	_draw_rect(img, hs - 16, hs - 18, 32, 3, Color(0.52, 0.38, 0.24))

	# === DEUX YARI (lances croisées en X) ===
	# Lance 1 (gauche → droite)
	_draw_line(img, hs - 18, hs + 14, hs + 18, hs - 14, Color(0.75, 0.73, 0.68), 3)
	# Pointe lance 1
	_draw_triangle(img, hs + 20, hs - 18, hs + 14, hs - 12, hs + 24, hs - 14, Color(0.85, 0.82, 0.78))
	# Lance 2 (droite → gauche)
	_draw_line(img, hs + 18, hs + 14, hs - 18, hs - 14, Color(0.75, 0.73, 0.68), 3)
	# Pointe lance 2
	_draw_triangle(img, hs - 20, hs - 18, hs - 14, hs - 12, hs - 24, hs - 14, Color(0.85, 0.82, 0.78))
	
	# Petits fanions rouges aux lances
	_draw_rect(img, hs + 8, hs - 6, 6, 4, Color(0.85, 0.25, 0.25))
	_draw_rect(img, hs - 14, hs - 6, 6, 4, Color(0.85, 0.25, 0.25))

	# Petit bouclier rond au centre
	_draw_circle(img, hs, hs + 2, 6, Color(0.40, 0.28, 0.16))
	_draw_circle(img, hs, hs + 2, 4, Color(0.48, 0.34, 0.22))
	_draw_circle(img, hs, hs + 2, 2, Color(0.85, 0.25, 0.25))


# --- ARCHER 64x64 — écusson / mon style yumi ---
func _generate_archer_sprite_v2(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	# Ombre au sol
	_draw_ellipse(img, hs, s - 3, 14, 4, Color(0, 0, 0, 0.30))

	# Fond ovale vertical (écusson vert)
	_draw_ellipse(img, hs, hs, 20, 24, Color(0.18, 0.32, 0.14))
	_draw_ellipse(img, hs, hs, 16, 20, Color(0.22, 0.38, 0.16))
	# Bordure rouge fine
	_draw_ellipse(img, hs, hs, 18, 22, Color(0.85, 0.25, 0.25, 0.5))

	# === YUMI (grand arc) — courbe élégante à gauche ===
	for by in range(0, 36):
		var bx = hs - 10 + int(sin((by - 18) / 18.0 * PI * 0.5) * 3)
		var by_pos = hs - 20 + by
		_draw_rect(img, bx, by_pos, 3, 3, Color(0.55, 0.38, 0.20))
		_draw_rect(img, bx + 1, by_pos, 1, 3, Color(0.35, 0.22, 0.12))
	# Corde d'arc (blanche)
	for cy in range(0, 34):
		var cx = hs - 7 + int(sin((cy - 17) / 17.0 * PI * 0.5) * 2)
		_draw_rect(img, cx, hs - 18 + cy, 1, 2, Color(0.92, 0.90, 0.88))

	# === FLÈCHE diagonale ===
	_draw_line(img, hs - 4, hs + 16, hs + 14, hs - 16, Color(0.65, 0.50, 0.25), 2)
	# Pointe de flèche
	_draw_triangle(img, hs + 16, hs - 20, hs + 12, hs - 14, hs + 18, hs - 16, Color(0.75, 0.75, 0.80))
	# Empennes
	_draw_rect(img, hs - 4, hs + 14, 3, 4, Color(0.85, 0.25, 0.25))
	_draw_rect(img, hs - 4, hs + 12, 5, 2, Color(0.75, 0.20, 0.18))

	# CARQUOIS (visible à droite)
	_draw_rect(img, hs + 16, hs - 6, 4, 18, Color(0.35, 0.28, 0.18))
	_draw_rect(img, hs + 17, hs - 6, 2, 18, Color(0.42, 0.34, 0.22))
	# Plumes dépassant
	for fy in [0, 1, 2]:
		_draw_rect(img, hs + 14 + fy * 2, hs - 8, 5, 3, Color(0.85, 0.25, 0.25))
		_draw_rect(img, hs + 15 + fy * 2, hs - 10, 3, 2, Color(0.75, 0.20, 0.18))


# --- ENNEMI JAPONAIS 64x64 ---
func _generate_enemy_sprite(img: Image, size: int, rng: RandomNumberGenerator, enemy_type: String) -> void:
	var s: int = size
	var hs: int = s / 2
	
	var body_color: Color = Color(0.7, 0.75, 0.72)
	var head_color: Color = Color(0.8, 0.85, 0.82)
	var detail_color: Color = Color(0.5, 0.5, 0.5)
	var eye_color: Color = Color(0.15, 0.6, 0.15)
	var weapon_color: Color = Color(0.55, 0.55, 0.6)
	
	match enemy_type:
		"skeleton":
			body_color = Color(0.78, 0.82, 0.78)
			head_color = Color(0.88, 0.90, 0.88)
			detail_color = Color(0.25, 0.25, 0.25)
			weapon_color = Color(0.65, 0.65, 0.70)
			eye_color = Color(0.85, 0.20, 0.15)
		"goblin":
			body_color = Color(0.82, 0.12, 0.10)
			head_color = Color(0.90, 0.18, 0.15)
			detail_color = Color(0.60, 0.08, 0.06)
			weapon_color = Color(0.30, 0.22, 0.12)
			eye_color = Color(0.98, 0.90, 0.18)
		"archer":
			body_color = Color(0.35, 0.25, 0.18)
			head_color = Color(0.90, 0.75, 0.60)
			detail_color = Color(0.20, 0.12, 0.08)
			weapon_color = Color(0.45, 0.30, 0.15)
			eye_color = Color(0.12, 0.08, 0.06)
		"swordsman":
			body_color = Color(0.08, 0.05, 0.04)
			head_color = Color(0.92, 0.78, 0.62)
			detail_color = Color(0.92, 0.20, 0.18)
			weapon_color = Color(0.88, 0.85, 0.80)
			eye_color = Color(0.08, 0.05, 0.04)
		"tengu":
			body_color = Color(0.50, 0.38, 0.25)
			head_color = Color(0.60, 0.48, 0.35)
			detail_color = Color(0.92, 0.72, 0.12)
			weapon_color = Color(0.35, 0.25, 0.18)
			eye_color = Color(0.90, 0.18, 0.08)
		"kappa":
			body_color = Color(0.25, 0.55, 0.65)
			head_color = Color(0.30, 0.60, 0.70)
			detail_color = Color(0.20, 0.45, 0.55)
			weapon_color = Color(0.35, 0.25, 0.18)
			eye_color = Color(0.85, 0.85, 0.20)
		"ninja":
			body_color = Color(0.08, 0.08, 0.10)
			head_color = Color(0.10, 0.10, 0.12)
			detail_color = Color(0.20, 0.20, 0.22)
			weapon_color = Color(0.55, 0.55, 0.60)
			eye_color = Color(0.85, 0.85, 0.20)
		"monk":
			body_color = Color(0.85, 0.70, 0.45)
			head_color = Color(0.90, 0.75, 0.60)
			detail_color = Color(0.70, 0.55, 0.30)
			weapon_color = Color(0.55, 0.45, 0.30)
			eye_color = Color(0.12, 0.08, 0.06)
	
	# Ombre elliptique
	for x in range(s):
		for y in range(s):
			var ox: float = (x - hs) / 16.0
			var oy: float = (y - (s - 4)) / 4.0
			var dist: float = ox * ox + oy * oy
			if dist <= 1.0:
				var alpha: float = 0.30 * (1.0 - dist * 0.5)
				img.set_pixel(x, y, Color(0, 0, 0, alpha))
	
	if enemy_type == "skeleton":
		# Aura d'âme rouge
		for x in range(s):
			for y in range(s):
				var dx: float = float(x - hs) / 18.0
				var dy: float = float(y - hs) / 18.0
				var dist: float = sqrt(dx * dx + dy * dy)
				if dist >= 0.85 and dist <= 1.0:
					var existing: Color = img.get_pixel(x, y)
					if existing.a < 0.1:
						img.set_pixel(x, y, Color(0.85, 0.12, 0.12, 0.20))
	
	# === CORPS ===
	_draw_shaded_circle(img, hs, hs + 8, 18, body_color, Vector2(-0.3, -0.8))
	
	# === TÊTE ===
	if enemy_type == "swordsman":
		# Kabuto (casque samurai) - comme le héros
		_draw_gradient_rect(img, hs - 12, hs - 24, 24, 12, Color(0.12, 0.08, 0.06), Color(0.08, 0.05, 0.04))
		_draw_rect(img, hs - 2, hs - 30, 4, 8, Color(0.85, 0.25, 0.25))
		_reflect(img, hs - 8, hs - 24, 8, 4, Color(0.30, 0.22, 0.18))
		# Shikoro (nuchae - protège-nuque)
		_draw_gradient_rect(img, hs - 14, hs - 12, 28, 4, Color(0.10, 0.06, 0.04), Color(0.08, 0.05, 0.04))
		# Mempo (masque facial)
		_draw_gradient_rect(img, hs - 10, hs - 16, 20, 6, Color(0.15, 0.10, 0.08), Color(0.10, 0.06, 0.04))
		_draw_rect(img, hs - 8, hs - 16, 16, 1, Color(0.25, 0.18, 0.12))
		# Chignon
		_draw_circle(img, hs + 8, hs - 22, 5, Color(0.06, 0.04, 0.02))
		# Maedate (crête avant)
		_draw_gradient_rect(img, hs - 1, hs - 32, 2, 14, Color(0.85, 0.25, 0.25), Color(0.65, 0.15, 0.15))
		_draw_rect(img, hs - 3, hs - 34, 6, 3, Color(0.90, 0.30, 0.30))
	elif enemy_type == "archer":
		# Jingasa (chapeau conique) avec détails
		_draw_gradient_rect(img, hs - 14, hs - 26, 28, 8, Color(0.35, 0.25, 0.18), Color(0.25, 0.18, 0.12))
		_draw_rect(img, hs - 10, hs - 26, 20, 2, Color(0.28, 0.18, 0.10))
		_draw_rect(img, hs - 2, hs - 28, 4, 4, Color(0.35, 0.25, 0.18))
		# Lanière
		_draw_line(img, hs - 8, hs - 18, hs + 8, hs - 14, Color(0.55, 0.40, 0.20), 1)
	elif enemy_type == "goblin":
		# Tête d'Oni avec cornes
		_draw_shaded_circle(img, hs, hs - 12, 14, Color(0.90, 0.18, 0.15), Vector2(-0.3, -0.8))
		_draw_shaded_circle(img, hs - 3, hs - 15, 10, Color(0.92, 0.22, 0.18), Vector2(-0.3, -0.8))
		# Grandes cornes courbées
		_draw_triangle(img, hs - 12, hs - 18, hs - 20, hs - 32, hs - 6, hs - 22, Color(0.30, 0.08, 0.06))
		_draw_triangle(img, hs + 12, hs - 18, hs + 20, hs - 32, hs + 6, hs - 22, Color(0.30, 0.08, 0.06))
		# Reflets sur les cornes
		_draw_triangle(img, hs - 14, hs - 20, hs - 18, hs - 28, hs - 10, hs - 22, Color(0.40, 0.12, 0.10))
		_draw_triangle(img, hs + 10, hs - 20, hs + 14, hs - 28, hs + 8, hs - 22, Color(0.40, 0.12, 0.10))
		# Cheveux hirsutes
		for hx in range(-8, 9, 4):
			_draw_triangle(img, hs + hx, hs - 20, hs + hx - 3, hs - 26, hs + hx + 3, hs - 24, Color(0.15, 0.05, 0.04))
	elif enemy_type == "tengu":
		# Tête de Tengu avec masque démoniaque
		_draw_shaded_circle(img, hs, hs - 14, 14, Color(0.55, 0.45, 0.35), Vector2(-0.3, -0.8))
		# Long nez rouge caractéristique
		_draw_triangle(img, hs, hs - 14, hs + 6, hs - 34, hs - 6, hs - 14, Color(0.85, 0.20, 0.10))
		_draw_triangle(img, hs - 1, hs - 14, hs + 4, hs - 30, hs - 4, hs - 14, Color(0.92, 0.30, 0.18))
		# Plumes hérissées sur la tête
		for py in [hs - 22, hs - 26, hs - 30]:
			_draw_rect(img, hs - 8, py, 16, 2, Color(0.45, 0.35, 0.25))
			_draw_rect(img, hs - 6, py - 1, 12, 1, Color(0.55, 0.45, 0.35))
		# Oreilles pointues
		_draw_triangle(img, hs - 16, hs - 12, hs - 20, hs - 18, hs - 14, hs - 16, Color(0.55, 0.45, 0.35))
		_draw_triangle(img, hs + 16, hs - 12, hs + 20, hs - 18, hs + 14, hs - 16, Color(0.55, 0.45, 0.35))
	elif enemy_type == "kappa":
		# Tête de Kappa
		_draw_shaded_circle(img, hs, hs - 14, 14, Color(0.30, 0.60, 0.70), Vector2(-0.3, -0.8))
		# Assiette sur la tête
		_draw_circle(img, hs, hs - 22, 7, Color(0.65, 0.65, 0.60))
		_draw_circle(img, hs, hs - 22, 5, Color(0.55, 0.55, 0.50))
		_draw_circle(img, hs, hs - 22, 3, Color(0.50, 0.50, 0.45))
		# Yeux de grenouille (globuleux)
		_draw_shaded_circle(img, hs - 8, hs - 14, 5, Color(0.85, 0.85, 0.80), Vector2(-0.2, -0.2))
		_draw_shaded_circle(img, hs + 8, hs - 14, 5, Color(0.85, 0.85, 0.80), Vector2(-0.2, -0.2))
		_draw_circle(img, hs - 8, hs - 14, 3, Color(0.12, 0.08, 0.06))
		_draw_circle(img, hs + 8, hs - 14, 3, Color(0.12, 0.08, 0.06))
		_draw_rect(img, hs - 9, hs - 15, 2, 2, Color(0.05, 0.05, 0.05))
		_draw_rect(img, hs + 7, hs - 15, 2, 2, Color(0.05, 0.05, 0.05))
		_draw_rect(img, hs - 7, hs - 15, 1, 1, Color(1, 1, 1))
		_draw_rect(img, hs + 9, hs - 15, 1, 1, Color(1, 1, 1))
		# Bouche en bec
		_draw_triangle(img, hs - 3, hs - 4, hs + 3, hs - 4, hs, hs - 1, Color(0.60, 0.75, 0.80))
	elif enemy_type == "ninja":
		# Tête masquée
		_draw_shaded_circle(img, hs, hs - 14, 14, Color(0.10, 0.10, 0.12), Vector2(-0.3, -0.8))
		# Bandeau noir sur les yeux
		_draw_rect(img, hs - 12, hs - 16, 24, 4, Color(0.08, 0.08, 0.10))
		# Hachimaki (bandeau rouge)
		_draw_line(img, hs - 14, hs - 20, hs + 14, hs - 20, Color(0.75, 0.15, 0.12), 2)
		# Extrémité du bandeau qui flotte
		_draw_triangle(img, hs + 14, hs - 22, hs + 18, hs - 24, hs + 14, hs - 18, Color(0.75, 0.15, 0.12))
	elif enemy_type == "monk":
		# Tête rasée (moine bouddhiste)
		_draw_shaded_circle(img, hs, hs - 14, 14, Color(0.90, 0.75, 0.60), Vector2(-0.3, -0.8))
		_draw_shaded_circle(img, hs - 3, hs - 17, 10, Color(0.92, 0.78, 0.65), Vector2(-0.3, -0.8))
		# Bosse crânienne (usui - sommet du crâne)
		_draw_shaded_circle(img, hs - 1, hs - 22, 5, Color(0.88, 0.72, 0.58), Vector2(-0.3, -0.8))
		# Sourcils rasés (légères marques)
		_draw_rect(img, hs - 6, hs - 17, 5, 1, Color(0.85, 0.70, 0.55))
		_draw_rect(img, hs + 1, hs - 17, 5, 1, Color(0.85, 0.70, 0.55))
		# Point de tiki (tilak) sur le front
		_draw_circle(img, hs, hs - 20, 2, Color(0.75, 0.15, 0.12))
	elif enemy_type == "skeleton":
		# Crâne détaillé
		_draw_shaded_circle(img, hs, hs - 14, 14, Color(0.88, 0.90, 0.88), Vector2(-0.3, -0.8))
		_draw_shaded_circle(img, hs - 3, hs - 17, 10, Color(0.90, 0.92, 0.90), Vector2(-0.3, -0.8))
		# Orbites profondes (creux sombres)
		_draw_shaded_circle(img, hs - 5, hs - 14, 4, Color(0.05, 0.05, 0.05), Vector2(-0.2, -0.2))
		_draw_shaded_circle(img, hs + 5, hs - 14, 4, Color(0.05, 0.05, 0.05), Vector2(-0.2, -0.2))
		# Lueur rouge dans les orbites
		_draw_circle(img, hs - 5, hs - 14, 2, Color(0.85, 0.15, 0.12))
		_draw_circle(img, hs + 5, hs - 14, 2, Color(0.85, 0.15, 0.12))
		# Fente nasale
		_draw_rect(img, hs - 2, hs - 8, 4, 2, Color(0.05, 0.05, 0.05))
		_draw_rect(img, hs - 1, hs - 9, 2, 3, Color(0.05, 0.05, 0.05))
		# Mâchoire
		_draw_gradient_rect(img, hs - 6, hs - 5, 12, 4, Color(0.75, 0.78, 0.75), Color(0.70, 0.72, 0.70))
		# Dents supérieures
		for td in range(-4, 5, 2):
			_draw_rect(img, hs + td - 1, hs - 5, 1, 2, Color(0.92, 0.94, 0.92))
		# Dents inférieures
		for td in range(-3, 4, 2):
			_draw_rect(img, hs + td, hs - 1, 1, 2, Color(0.92, 0.94, 0.92))
		# Fissures sur le crâne
		_draw_line(img, hs + 2, hs - 20, hs + 5, hs - 16, Color(0.60, 0.62, 0.60), 1)
		_draw_line(img, hs - 3, hs - 12, hs, hs - 10, Color(0.60, 0.62, 0.60), 1)
	
	# Yeux (pour les types non-skeleton)
	if enemy_type != "skeleton" and enemy_type != "kappa" and enemy_type != "ninja":
		_draw_shaded_circle(img, hs - 5, hs - 14, 4, Color(0.95, 0.95, 0.95), Vector2(-0.2, -0.2))
		_draw_shaded_circle(img, hs + 5, hs - 14, 4, Color(0.95, 0.95, 0.95), Vector2(-0.2, -0.2))
		_draw_circle(img, hs - 5, hs - 14, 3, eye_color)
		_draw_circle(img, hs + 5, hs - 14, 3, eye_color)
		_draw_rect(img, hs - 6, hs - 15, 2, 2, Color(0.05, 0.05, 0.05))
		_draw_rect(img, hs + 4, hs - 15, 2, 2, Color(0.05, 0.05, 0.05))
		_draw_rect(img, hs - 4, hs - 15, 1, 1, Color(1, 1, 1))
		_draw_rect(img, hs + 5, hs - 15, 1, 1, Color(1, 1, 1))
	
	# Yeux pour ninja (juste les yeux visibles)
	if enemy_type == "ninja":
		_draw_rect(img, hs - 6, hs - 16, 4, 2, Color(0.90, 0.90, 0.90))
		_draw_rect(img, hs + 2, hs - 16, 4, 2, Color(0.90, 0.90, 0.90))
		_draw_rect(img, hs - 5, hs - 16, 2, 2, Color(0.05, 0.05, 0.05))
		_draw_rect(img, hs + 3, hs - 16, 2, 2, Color(0.05, 0.05, 0.05))
		_draw_rect(img, hs - 4, hs - 17, 1, 1, Color(1, 1, 1))
		_draw_rect(img, hs + 5, hs - 17, 1, 1, Color(1, 1, 1))
	
	# === ARMURE / VÊTEMENTS ===
	if enemy_type == "swordsman":
		# Do (armure de poitrine) - comme le héros
		_draw_shaded_circle(img, hs, hs + 2, 14, Color(0.12, 0.08, 0.06), Vector2(-0.5, -0.8))
		_draw_gradient_rect(img, hs - 8, hs - 2, 16, 16, Color(0.18, 0.12, 0.08), Color(0.06, 0.03, 0.02))
		_add_bevel(img, hs - 8, hs - 2, 16, 16, Color(0.25, 0.18, 0.12), Color(0.04, 0.02, 0.01))
		# Reflet sur l'armure
		_draw_rect(img, hs - 6, hs, 2, 6, Color(0.40, 0.32, 0.25, 0.30))
		# Bordures vermilion
		_draw_rect(img, hs - 8, hs - 2, 16, 2, Color(0.85, 0.25, 0.25))
		_draw_rect(img, hs - 8, hs + 14, 16, 2, Color(0.85, 0.25, 0.25))
		# Mon (blason) - crâne noir sur fond vermilion
		_draw_circle(img, hs, hs + 6, 4, Color(0.85, 0.25, 0.25))
		_draw_circle(img, hs, hs + 6, 2, Color(0.95, 0.85, 0.20))
		# Sode (épaulières)
		_draw_gradient_rect(img, hs - 16, hs - 4, 8, 12, Color(0.10, 0.06, 0.04), Color(0.06, 0.03, 0.02))
		_draw_rect(img, hs - 16, hs - 4, 8, 2, Color(0.85, 0.25, 0.25))
		_draw_gradient_rect(img, hs + 8, hs - 4, 8, 12, Color(0.10, 0.06, 0.04), Color(0.06, 0.03, 0.02))
		_draw_rect(img, hs + 8, hs - 4, 8, 2, Color(0.85, 0.25, 0.25))
	elif enemy_type == "archer":
		# Kimono avec dégradés
		_draw_gradient_rect(img, hs - 14, hs, 6, 20, Color(0.35, 0.25, 0.18), Color(0.22, 0.12, 0.08))
		_draw_gradient_rect(img, hs + 8, hs, 6, 20, Color(0.35, 0.25, 0.18), Color(0.22, 0.12, 0.08))
		_draw_gradient_rect(img, hs - 8, hs + 2, 16, 16, Color(0.42, 0.30, 0.20), Color(0.28, 0.18, 0.10))
		_add_noise_to_rect(img, hs - 6, hs + 2, 12, 12, Color(0.42, 0.30, 0.20), 0.03, rng)
		# Obi (ceinture)
		_draw_rect(img, hs - 8, hs + 10, 16, 4, Color(0.85, 0.25, 0.25))
		_draw_rect(img, hs - 8, hs + 12, 16, 1, Color(0.75, 0.18, 0.18))
	elif enemy_type == "goblin":
		# Torse d'Oni musclé
		_draw_gradient_rect(img, hs - 10, hs, 20, 12, Color(0.75, 0.15, 0.15), Color(0.55, 0.10, 0.10))
		_draw_shaded_circle(img, hs, hs + 4, 12, Color(0.70, 0.12, 0.12), Vector2(-0.3, -0.6))
		# Lignes musculaires
		_draw_line(img, hs - 4, hs + 2, hs + 4, hs + 2, Color(0.45, 0.08, 0.08), 1)
		_draw_line(img, hs, hs + 4, hs, hs + 8, Color(0.45, 0.08, 0.08), 1)
		# Fundoshi (loincloth)
		_draw_gradient_rect(img, hs - 6, hs + 10, 12, 4, Color(0.85, 0.25, 0.25), Color(0.65, 0.18, 0.18))
		_draw_rect(img, hs - 6, hs + 10, 12, 1, Color(0.90, 0.35, 0.35))
	elif enemy_type == "tengu":
		# Plumage du corps
		_draw_gradient_rect(img, hs - 10, hs, 20, 14, Color(0.45, 0.35, 0.25), Color(0.35, 0.25, 0.15))
		_add_noise_to_rect(img, hs - 8, hs, 16, 10, Color(0.45, 0.35, 0.25), 0.06, rng)
		# Ailes déployées
		for wy in [hs - 2, hs + 2, hs + 6, hs + 10]:
			_draw_rect(img, hs - 16, wy, 6, 3, Color(0.50, 0.40, 0.30))
			_draw_rect(img, hs + 10, wy, 6, 3, Color(0.50, 0.40, 0.30))
		# Détail des plumes des ailes
		for f in range(3):
			_draw_rect(img, hs - 18, hs + f * 4, 3, 2, Color(0.55, 0.45, 0.35))
			_draw_rect(img, hs + 15, hs + f * 4, 3, 2, Color(0.55, 0.45, 0.35))
	elif enemy_type == "kappa":
		# Carapace de tortue
		_draw_gradient_rect(img, hs - 10, hs - 2, 20, 16, Color(0.25, 0.55, 0.65), Color(0.18, 0.42, 0.50))
		_apply_kappa_shell_pattern(img, hs, rng)
		# Membre antérieur palmé
		_draw_gradient_rect(img, hs - 4, hs + 14, 8, 4, Color(0.25, 0.55, 0.65), Color(0.20, 0.45, 0.55))
	elif enemy_type == "ninja":
		# Tenue noire avec détails
		_draw_gradient_rect(img, hs - 10, hs, 20, 14, Color(0.08, 0.08, 0.10), Color(0.06, 0.06, 0.08))
		# Ceinture
		_draw_rect(img, hs - 8, hs + 10, 16, 3, Color(0.15, 0.15, 0.18))
		_draw_rect(img, hs - 8, hs + 10, 16, 1, Color(0.20, 0.20, 0.22))
		# Kusarigama (faucille à chaîne) à la ceinture
		_draw_line(img, hs + 10, hs + 12, hs + 16, hs + 18, Color(0.55, 0.55, 0.60), 1)
		_draw_triangle(img, hs + 16, hs + 16, hs + 18, hs + 20, hs + 14, hs + 20, Color(0.60, 0.60, 0.65))
	elif enemy_type == "monk":
		# Robe safran
		_draw_gradient_rect(img, hs - 10, hs, 20, 14, Color(0.85, 0.70, 0.45), Color(0.70, 0.55, 0.30))
		_add_noise_to_rect(img, hs - 8, hs + 2, 16, 10, Color(0.85, 0.70, 0.45), 0.03, rng)
		# Kesa (écharpe)
		_draw_rect(img, hs - 8, hs + 2, 16, 4, Color(0.60, 0.45, 0.25))
		_draw_rect(img, hs - 8, hs + 3, 16, 1, Color(0.70, 0.55, 0.35))
		# Juzu (chapelet)
		for bx in range(-6, 8, 4):
			_draw_circle(img, hs + bx, hs + 8, 1, Color(0.50, 0.35, 0.20))
		# Manche large gauche
		_draw_gradient_rect(img, hs - 16, hs + 4, 6, 10, Color(0.85, 0.70, 0.45), Color(0.70, 0.55, 0.30))
	elif enemy_type == "skeleton":
		# Cage thoracique (os du torse)
		_draw_gradient_rect(img, hs - 8, hs - 2, 16, 16, Color(0.78, 0.82, 0.78), Color(0.70, 0.74, 0.70))
		# Côtes
		for ry in [hs + 2, hs + 6, hs + 10]:
			_draw_rect(img, hs - 10, ry, 20, 2, Color(0.82, 0.85, 0.82))
			_draw_rect(img, hs - 8, ry + 1, 16, 1, Color(0.70, 0.74, 0.70))
		# Colonne vertébrale
		_draw_rect(img, hs - 2, hs - 2, 4, 16, Color(0.82, 0.85, 0.82))
		_draw_rect(img, hs - 1, hs - 2, 2, 16, Color(0.75, 0.78, 0.75))
		# Clavicules
		_draw_line(img, hs - 10, hs - 4, hs + 10, hs - 4, Color(0.80, 0.83, 0.80), 2)
		# Restes d'armure rouillée
		_draw_rect(img, hs - 12, hs - 4, 4, 6, Color(0.30, 0.18, 0.10, 0.50))
		_draw_rect(img, hs + 8, hs - 4, 4, 6, Color(0.30, 0.18, 0.10, 0.50))
	
	# === BOUCHE ===
	if enemy_type == "skeleton":
		pass
	elif enemy_type == "kappa":
		pass
	elif enemy_type == "ninja":
		pass
	elif enemy_type == "goblin":
		_draw_rect(img, hs - 4, hs - 6, 8, 3, Color(0.12, 0.08, 0.06))
		_draw_rect(img, hs - 2, hs - 5, 2, 2, Color(0.90, 0.90, 0.85))
		_draw_rect(img, hs + 1, hs - 5, 2, 2, Color(0.90, 0.90, 0.85))
	else:
		_draw_rect(img, hs - 3, hs - 6, 6, 2, Color(0.12, 0.08, 0.06))
		_draw_rect(img, hs - 2, hs - 6, 4, 1, Color(0.75, 0.25, 0.20))
	
	# === JAMBES ===
	if enemy_type == "swordsman":
		_draw_gradient_rect(img, hs - 8, hs + 16, 6, 10, Color(0.12, 0.08, 0.06), Color(0.08, 0.05, 0.04))
		_draw_gradient_rect(img, hs + 2, hs + 16, 6, 10, Color(0.12, 0.08, 0.06), Color(0.08, 0.05, 0.04))
		_draw_rect(img, hs - 9, hs + 24, 8, 3, Color(0.35, 0.25, 0.18))
		_draw_rect(img, hs + 1, hs + 24, 8, 3, Color(0.35, 0.25, 0.18))
		_draw_rect(img, hs - 6, hs + 26, 2, 2, Color(0.35, 0.25, 0.18))
		_draw_rect(img, hs + 4, hs + 26, 2, 2, Color(0.35, 0.25, 0.18))
	elif enemy_type == "archer":
		_draw_gradient_rect(img, hs - 7, hs + 16, 5, 10, Color(0.35, 0.25, 0.18), Color(0.22, 0.12, 0.08))
		_draw_gradient_rect(img, hs + 2, hs + 16, 5, 10, Color(0.35, 0.25, 0.18), Color(0.22, 0.12, 0.08))
		_draw_rect(img, hs - 8, hs + 24, 6, 3, Color(0.90, 0.90, 0.88))
		_draw_rect(img, hs + 2, hs + 24, 6, 3, Color(0.90, 0.90, 0.88))
	elif enemy_type == "goblin":
		_draw_gradient_rect(img, hs - 6, hs + 12, 5, 8, Color(0.70, 0.12, 0.12), Color(0.50, 0.08, 0.08))
		_draw_gradient_rect(img, hs + 1, hs + 12, 5, 8, Color(0.70, 0.12, 0.12), Color(0.50, 0.08, 0.08))
		_draw_rect(img, hs - 8, hs + 18, 6, 3, Color(0.35, 0.08, 0.06))
		_draw_rect(img, hs + 2, hs + 18, 6, 3, Color(0.35, 0.08, 0.06))
	elif enemy_type == "tengu":
		_draw_gradient_rect(img, hs - 6, hs + 12, 5, 6, Color(0.55, 0.45, 0.35), Color(0.45, 0.35, 0.25))
		_draw_gradient_rect(img, hs + 1, hs + 12, 5, 6, Color(0.55, 0.45, 0.35), Color(0.45, 0.35, 0.25))
		_draw_triangle(img, hs - 6, hs + 18, hs - 8, hs + 22, hs - 4, hs + 18, Color(0.85, 0.65, 0.15))
		_draw_triangle(img, hs + 6, hs + 18, hs + 8, hs + 22, hs + 4, hs + 18, Color(0.85, 0.65, 0.15))
	elif enemy_type == "kappa":
		_draw_gradient_rect(img, hs - 6, hs + 12, 5, 6, Color(0.30, 0.60, 0.70), Color(0.20, 0.45, 0.55))
		_draw_gradient_rect(img, hs + 1, hs + 12, 5, 6, Color(0.30, 0.60, 0.70), Color(0.20, 0.45, 0.55))
		_draw_rect(img, hs - 8, hs + 18, 6, 2, Color(0.25, 0.55, 0.65))
		_draw_rect(img, hs + 2, hs + 18, 6, 2, Color(0.25, 0.55, 0.65))
		_draw_rect(img, hs - 10, hs + 20, 3, 2, Color(0.25, 0.55, 0.65))
		_draw_rect(img, hs + 7, hs + 20, 3, 2, Color(0.25, 0.55, 0.65))
	elif enemy_type == "ninja":
		_draw_gradient_rect(img, hs - 6, hs + 12, 5, 8, Color(0.08, 0.08, 0.10), Color(0.06, 0.06, 0.08))
		_draw_gradient_rect(img, hs + 1, hs + 12, 5, 8, Color(0.08, 0.08, 0.10), Color(0.06, 0.06, 0.08))
		# Kyahan (jambières)
		_draw_rect(img, hs - 7, hs + 14, 6, 4, Color(0.15, 0.08, 0.06))
		_draw_rect(img, hs + 1, hs + 14, 6, 4, Color(0.15, 0.08, 0.06))
		# Tabi (chaussettes) et waraji (sandales)
		_draw_rect(img, hs - 7, hs + 20, 5, 3, Color(0.50, 0.50, 0.55))
		_draw_rect(img, hs + 2, hs + 20, 5, 3, Color(0.50, 0.50, 0.55))
	elif enemy_type == "monk":
		_draw_gradient_rect(img, hs - 10, hs + 14, 20, 8, Color(0.85, 0.70, 0.45), Color(0.70, 0.55, 0.30))
		_draw_rect(img, hs - 10, hs + 22, 8, 3, Color(0.55, 0.10, 0.10))
		_draw_rect(img, hs + 2, hs + 22, 8, 3, Color(0.55, 0.10, 0.10))
	elif enemy_type == "skeleton":
		_draw_rect(img, hs - 6, hs + 16, 3, 10, Color(0.78, 0.82, 0.78))
		_draw_rect(img, hs + 3, hs + 16, 3, 10, Color(0.78, 0.82, 0.78))
		_draw_rect(img, hs - 8, hs + 24, 6, 3, Color(0.75, 0.78, 0.75))
		_draw_rect(img, hs + 2, hs + 24, 6, 3, Color(0.75, 0.78, 0.75))
	
	# === ARMES ===
	if enemy_type == "skeleton":
		_draw_gradient_rect(img, hs + 18, hs - 6, 5, 26, Color(0.72, 0.75, 0.80), Color(0.55, 0.58, 0.62))
		_draw_rect(img, hs + 20, hs - 6, 2, 26, Color(0.82, 0.85, 0.90))
		_draw_rect(img, hs + 16, hs - 10, 9, 6, Color(0.55, 0.55, 0.60))
		_draw_gradient_rect(img, hs + 17, hs + 14, 7, 4, Color(0.45, 0.35, 0.25), Color(0.35, 0.25, 0.18))
		_draw_rect(img, hs + 19, hs + 18, 3, 3, Color(0.65, 0.55, 0.30))
		_draw_rect(img, hs + 19, hs + 2, 2, 4, Color(0.55, 0.30, 0.15))
		_draw_rect(img, hs + 18, hs - 4, 2, 3, Color(0.55, 0.30, 0.15))
	elif enemy_type == "goblin":
		_draw_gradient_rect(img, hs + 20, hs - 8, 5, 26, Color(0.42, 0.28, 0.15), Color(0.30, 0.18, 0.10))
		_draw_gradient_rect(img, hs + 18, hs - 12, 10, 10, Color(0.55, 0.55, 0.60), Color(0.45, 0.45, 0.50))
		_draw_gradient_rect(img, hs + 18, hs - 2, 10, 10, Color(0.55, 0.55, 0.60), Color(0.45, 0.45, 0.50))
		_draw_rect(img, hs + 20, hs - 14, 4, 14, Color(0.65, 0.65, 0.70))
		for sy in [hs - 10, hs - 4, hs + 2]:
			_draw_rect(img, hs + 16, sy, 4, 3, Color(0.75, 0.75, 0.80))
			_draw_rect(img, hs + 24, sy, 4, 3, Color(0.75, 0.75, 0.80))
		_draw_rect(img, hs + 19, hs - 10, 2, 3, Color(0.75, 0.10, 0.10))
		_draw_rect(img, hs + 22, hs + 2, 2, 2, Color(0.75, 0.10, 0.10))
	elif enemy_type == "archer":
		for ay in range(hs - 16, hs + 16):
			var ax: int = hs - 20 + int(sin((ay - (hs - 16)) / 32.0 * PI) * 6)
			_draw_rect(img, ax, ay, 3, 2, Color(0.42, 0.28, 0.15))
			_draw_rect(img, ax + 1, ay, 1, 2, Color(0.50, 0.35, 0.18))
		_draw_rect(img, hs - 22, hs - 16, 1, 32, Color(0.80, 0.78, 0.72))
		_draw_rect(img, hs - 20, hs - 4, 18, 2, Color(0.55, 0.45, 0.30))
		_draw_rect(img, hs - 2, hs - 6, 4, 6, Color(0.55, 0.55, 0.60))
		_draw_triangle(img, hs - 2, hs - 8, hs + 2, hs - 8, hs, hs - 10, Color(0.55, 0.55, 0.60))
		_draw_rect(img, hs - 16, hs - 12, 5, 14, Color(0.28, 0.16, 0.08))
		for fy in [hs - 10, hs - 6, hs - 2]:
			_draw_rect(img, hs - 18, fy, 2, 8, Color(0.48, 0.38, 0.28))
			_draw_rect(img, hs - 16, fy - 2, 2, 2, Color(0.55, 0.55, 0.60))
	elif enemy_type == "swordsman":
		_draw_gradient_rect(img, hs + 18, hs - 8, 5, 28, Color(0.85, 0.82, 0.78), Color(0.70, 0.68, 0.65))
		_draw_rect(img, hs + 20, hs - 8, 2, 28, Color(0.92, 0.90, 0.88))
		_draw_rect(img, hs + 21, hs - 10, 1, 8, Color(1.0, 1.0, 1.0))
		_draw_rect(img, hs + 23, hs, 1, 6, Color(1.0, 1.0, 1.0))
		_draw_rect(img, hs + 16, hs - 12, 9, 6, Color(0.85, 0.25, 0.25))
		_draw_gradient_rect(img, hs + 17, hs + 16, 7, 4, Color(0.35, 0.25, 0.18), Color(0.25, 0.15, 0.10))
		for ty in [hs + 17, hs + 19]:
			_draw_rect(img, hs + 17, ty, 7, 1, Color(0.25, 0.15, 0.10))
		_draw_rect(img, hs + 19, hs + 18, 3, 3, Color(0.85, 0.25, 0.25))
		_draw_circle(img, hs + 20, hs + 18, 1, Color(0.95, 0.85, 0.20))
		# Bouclier
		for x in range(hs - 28, hs - 6):
			for y in range(hs - 4, hs + 14):
				var dx: float = float(x - (hs - 17)) / 11.0
				var dy: float = float(y - (hs + 5)) / 9.0
				if dx * dx + dy * dy <= 1.0:
					var t: float = dx * dx + dy * dy
					img.set_pixel(x, y, Color(lerp(0.65, 0.45, t), lerp(0.68, 0.48, t), lerp(0.75, 0.55, t)))
		for x in range(hs - 28, hs - 6):
			for y in range(hs - 4, hs + 14):
				var dx: float = float(x - (hs - 17)) / 11.0
				var dy: float = float(y - (hs + 5)) / 9.0
				var dist: float = dx * dx + dy * dy
				if dist >= 0.78 and dist <= 1.0:
					img.set_pixel(x, y, Color(0.85, 0.72, 0.20))
		_draw_circle(img, hs - 17, hs + 5, 4, Color(0.25, 0.28, 0.38))
		_draw_rect(img, hs - 19, hs + 3, 4, 2, Color(0.85, 0.72, 0.20))
		_draw_rect(img, hs - 15, hs + 3, 4, 2, Color(0.85, 0.72, 0.20))
		_draw_shaded_circle(img, hs - 17, hs + 5, 2, Color(0.72, 0.72, 0.78), Vector2(-0.3, -0.3))
	elif enemy_type == "tengu":
		_draw_rect(img, hs + 18, hs - 4, 4, 20, Color(0.35, 0.25, 0.18))
		_draw_rect(img, hs + 16, hs - 2, 2, 16, Color(0.85, 0.65, 0.15))
		_draw_rect(img, hs + 20, hs - 2, 2, 16, Color(0.85, 0.65, 0.15))
		for fy in [hs - 2, hs + 6, hs + 14]:
			_draw_rect(img, hs + 22, fy, 3, 2, Color(0.45, 0.35, 0.25))
	elif enemy_type == "kappa":
		_draw_rect(img, hs + 18, hs - 4, 4, 20, Color(0.35, 0.25, 0.18))
		_draw_rect(img, hs + 16, hs - 2, 2, 16, Color(0.30, 0.60, 0.70))
		_draw_rect(img, hs + 20, hs - 2, 2, 16, Color(0.30, 0.60, 0.70))
	elif enemy_type == "ninja":
		_draw_rect(img, hs + 18, hs - 2, 3, 16, Color(0.55, 0.55, 0.60))
		_draw_line(img, hs + 18, hs - 8, hs + 22, hs - 12, Color(0.55, 0.55, 0.60), 2)
		_draw_triangle(img, hs + 18, hs - 6, hs + 21, hs - 10, hs + 21, hs - 2, Color(0.55, 0.55, 0.60))
		_draw_rect(img, hs + 22, hs + 8, 8, 2, Color(0.55, 0.55, 0.60))
		_draw_rect(img, hs + 24, hs + 4, 2, 8, Color(0.55, 0.55, 0.60))
		_draw_rect(img, hs + 26, hs + 6, 2, 2, Color(0.55, 0.55, 0.60))
	elif enemy_type == "monk":
		_draw_rect(img, hs + 18, hs - 8, 4, 28, Color(0.55, 0.45, 0.30))
		_draw_rect(img, hs + 19, hs - 8, 2, 28, Color(0.65, 0.55, 0.40))
		for ry in [hs - 4, hs + 4, hs + 12]:
			_draw_circle(img, hs + 20, ry, 3, Color(0.75, 0.72, 0.68))
			_draw_circle(img, hs + 20, ry, 2, Color(0.55, 0.55, 0.60))
		_draw_rect(img, hs + 16, hs + 18, 14, 5, Color(0.48, 0.42, 0.28))
		_draw_rect(img, hs + 18, hs + 16, 10, 3, Color(0.62, 0.55, 0.38))
		_draw_rect(img, hs + 22, hs + 23, 3, 10, Color(0.42, 0.28, 0.15))
		_draw_shaded_circle(img, hs + 23, hs + 34, 4, Color(0.68, 0.58, 0.32), Vector2(-0.3, -0.5))
	
	# === AURAS ===
	if enemy_type == "goblin":
		for x in range(hs - 20, hs + 20):
			for y in range(hs - 20, hs + 20):
				var dx: float = float(x - hs) / 18.0
				var dy: float = float(y - hs) / 18.0
				var dist: float = sqrt(dx * dx + dy * dy)
				if dist >= 0.9 and dist <= 1.0:
					var existing: Color = img.get_pixel(x, y)
					if existing.a < 0.1:
						img.set_pixel(x, y, Color(0.20, 0.55, 0.10, 0.12))

func _apply_kappa_shell_pattern(img: Image, hs: int, rng: RandomNumberGenerator) -> void:
	for cy in [hs + 2, hs + 6, hs + 10]:
		_draw_rect(img, hs - 6, cy, 12, 2, Color(0.20, 0.50, 0.60))
		_draw_rect(img, hs - 4, cy + 1, 8, 1, Color(0.22, 0.52, 0.62))

func _reflect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for rx in range(x, x + w):
		for ry in range(y, y + h):
			var existing: Color = img.get_pixel(rx, ry)
			if existing.a > 0.1:
				var blended: Color = Color(
					lerp(existing.r, color.r, 0.3),
					lerp(existing.g, color.g, 0.3),
					lerp(existing.b, color.b, 0.3),
					existing.a
				)
				img.set_pixel(rx, ry, blended)

# --- HÉROS JAPONAIS 64x64 ---
func _generate_hero_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2
	
	# Ombre elliptique
	for x in range(s):
		for y in range(s):
			var ox: float = (x - hs) / 16.0
			var oy: float = (y - (s - 4)) / 4.0
			var dist: float = ox * ox + oy * oy
			if dist <= 1.0:
				var alpha: float = 0.30 * (1.0 - dist * 0.5)
				img.set_pixel(x, y, Color(0, 0, 0, alpha))
	
	# Corps (kimono sombre avec armure)
	_draw_shaded_circle(img, hs, hs + 8, 18, Color(0.35, 0.25, 0.18), Vector2(-0.3, -0.8))
	_add_noise_to_rect(img, hs - 10, hs - 2, 20, 20, Color(0.35, 0.25, 0.18), 0.04, rng)
	
	# Armure de poitrine (do) - lames laquées noires avec reflets satinés
	_draw_shaded_circle(img, hs, hs + 2, 14, Color(0.08, 0.05, 0.04), Vector2(-0.5, -0.8))
	_draw_gradient_rect(img, hs - 8, hs - 2, 16, 16, Color(0.18, 0.12, 0.08), Color(0.06, 0.03, 0.02))
	_add_bevel(img, hs - 8, hs - 2, 16, 16, Color(0.25, 0.18, 0.12), Color(0.04, 0.02, 0.01))
	# Bordures vermilion vif
	_draw_rect(img, hs - 8, hs - 2, 16, 2, Color(0.90, 0.20, 0.18))
	_draw_rect(img, hs - 8, hs + 14, 16, 2, Color(0.90, 0.20, 0.18))
	# Mon (crest) doré au centre
	_draw_circle(img, hs, hs + 6, 4, Color(0.92, 0.28, 0.22))
	_draw_circle(img, hs, hs + 6, 2, Color(0.98, 0.88, 0.22))
	# Highlight sur l'armure (reflet)
	_draw_rect(img, hs - 6, hs, 2, 6, Color(0.85, 0.82, 0.78, 0.25))
	
	# Épaulettes (sode) avec laque profonde
	_draw_gradient_rect(img, hs - 16, hs - 4, 8, 12, Color(0.10, 0.06, 0.04), Color(0.06, 0.03, 0.02))
	_draw_rect(img, hs - 16, hs - 4, 8, 2, Color(0.90, 0.20, 0.18))
	_draw_gradient_rect(img, hs + 8, hs - 4, 8, 12, Color(0.10, 0.06, 0.04), Color(0.06, 0.03, 0.02))
	_draw_rect(img, hs + 8, hs - 4, 8, 2, Color(0.90, 0.20, 0.18))
	
	# Tête (peau japonaise)
	_draw_shaded_circle(img, hs, hs - 12, 14, Color(0.90, 0.75, 0.60), Vector2(-0.3, -0.8))
	_draw_shaded_circle(img, hs - 3, hs - 15, 10, Color(0.92, 0.78, 0.65), Vector2(-0.3, -0.8))
	
	# Casque samurai (kabuto) avec crête
	_draw_gradient_rect(img, hs - 12, hs - 24, 24, 12, Color(0.12, 0.08, 0.06), Color(0.08, 0.05, 0.04))
	_draw_rect(img, hs - 2, hs - 30, 4, 8, Color(0.85, 0.25, 0.25))  # Crête vermilion
	# Visière (mempo)
	_draw_gradient_rect(img, hs - 10, hs - 16, 20, 6, Color(0.15, 0.10, 0.08), Color(0.10, 0.06, 0.04))
	# Chignon samurai
	_draw_circle(img, hs + 8, hs - 20, 4, Color(0.06, 0.04, 0.02))
	
	# Cheveux noirs visibles sous le casque
	_draw_shaded_circle(img, hs, hs - 18, 12, Color(0.06, 0.04, 0.02), Vector2(-0.3, -0.8))
	_draw_circle(img, hs + 6, hs - 22, 5, Color(0.06, 0.04, 0.02))  # Chignon
	
	# Yeux détaillés
	_draw_shaded_circle(img, hs - 5, hs - 14, 4, Color(0.95, 0.95, 0.95), Vector2(-0.2, -0.2))
	_draw_shaded_circle(img, hs + 5, hs - 14, 4, Color(0.95, 0.95, 0.95), Vector2(-0.2, -0.2))
	_draw_circle(img, hs - 5, hs - 14, 3, Color(0.12, 0.08, 0.06))
	_draw_circle(img, hs + 5, hs - 14, 3, Color(0.12, 0.08, 0.06))
	_draw_rect(img, hs - 6, hs - 15, 2, 2, Color(0.05, 0.05, 0.05))
	_draw_rect(img, hs + 4, hs - 15, 2, 2, Color(0.05, 0.05, 0.05))
	_draw_rect(img, hs - 4, hs - 15, 1, 1, Color(1, 1, 1))
	_draw_rect(img, hs + 5, hs - 15, 1, 1, Color(1, 1, 1))
	
	# Bouche
	_draw_rect(img, hs - 3, hs - 6, 6, 2, Color(0.12, 0.08, 0.06))
	_draw_rect(img, hs - 2, hs - 6, 4, 1, Color(0.75, 0.25, 0.20))
	
	# Obi (ceinture vermilion)
	_draw_rect(img, hs - 8, hs + 10, 16, 4, Color(0.85, 0.25, 0.25))
	
	# Hakama (pantalon)
	_draw_gradient_rect(img, hs - 8, hs + 16, 6, 10, Color(0.35, 0.25, 0.18), Color(0.22, 0.12, 0.08))
	_draw_gradient_rect(img, hs + 2, hs + 16, 6, 10, Color(0.35, 0.25, 0.18), Color(0.22, 0.12, 0.08))
	
	# Tabi (chaussettes)
	_draw_rect(img, hs - 8, hs + 24, 6, 3, Color(0.90, 0.90, 0.88))
	_draw_rect(img, hs + 2, hs + 24, 6, 3, Color(0.90, 0.90, 0.88))
	
	# Katana à droite
	_draw_gradient_rect(img, hs + 18, hs - 8, 5, 28, Color(0.85, 0.82, 0.78), Color(0.70, 0.68, 0.65))
	_draw_rect(img, hs + 20, hs - 8, 2, 28, Color(0.92, 0.90, 0.88))
	_draw_rect(img, hs + 16, hs - 12, 9, 6, Color(0.85, 0.25, 0.25))
	_draw_rect(img, hs + 17, hs + 16, 7, 4, Color(0.35, 0.25, 0.18))
	for ty in [hs + 17, hs + 19]:
		_draw_rect(img, hs + 17, ty, 7, 1, Color(0.25, 0.15, 0.10))
	_draw_rect(img, hs + 19, hs + 18, 3, 3, Color(0.85, 0.25, 0.25))
	_draw_circle(img, hs + 20, hs + 18, 1, Color(0.95, 0.85, 0.20))
	_draw_rect(img, hs + 21, hs - 10, 1, 8, Color(1.0, 1.0, 1.0))
	_draw_rect(img, hs + 23, hs, 1, 6, Color(1.0, 1.0, 1.0))

# --- MARCHAND JAPONAIS 64x64 ---
func _generate_merchant_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	# Ombre elliptique
	for x in range(s):
		for y in range(s):
			var ox: float = (x - hs) / 16.0
			var oy: float = (y - (s - 4)) / 4.0
			var dist: float = ox * ox + oy * oy
			if dist <= 1.0:
				var alpha: float = 0.30 * (1.0 - dist * 0.5)
				img.set_pixel(x, y, Color(0, 0, 0, alpha))

	# Robe de marchand (violette)
	_draw_shaded_circle(img, hs, hs + 8, 18, Color(0.55, 0.35, 0.65), Vector2(-0.3, -0.8))
	_add_noise_to_rect(img, hs - 10, hs - 2, 20, 20, Color(0.55, 0.35, 0.65), 0.04, rng)

	# Sur-habit (haori) avec bordures dorées
	_draw_gradient_rect(img, hs - 10, hs - 2, 20, 18, Color(0.50, 0.30, 0.60), Color(0.40, 0.22, 0.50))
	_draw_rect(img, hs - 10, hs - 2, 20, 2, Color(0.85, 0.70, 0.25))
	_draw_rect(img, hs - 10, hs + 14, 20, 2, Color(0.85, 0.70, 0.25))
	_draw_line(img, hs - 10, hs - 2, hs - 10, hs + 14, Color(0.85, 0.70, 0.25), 1)
	_draw_line(img, hs + 10, hs - 2, hs + 10, hs + 14, Color(0.85, 0.70, 0.25), 1)

	# Mon (blason) de marchand - pièce de monnaie
	_draw_circle(img, hs, hs + 6, 5, Color(0.85, 0.70, 0.25))
	_draw_circle(img, hs, hs + 6, 3, Color(0.95, 0.85, 0.30))
	_draw_rect(img, hs - 1, hs + 5, 2, 2, Color(0.65, 0.50, 0.15))

	# Tête (peau japonaise)
	_draw_shaded_circle(img, hs, hs - 12, 14, Color(0.90, 0.75, 0.60), Vector2(-0.3, -0.8))
	_draw_shaded_circle(img, hs - 3, hs - 15, 10, Color(0.92, 0.78, 0.65), Vector2(-0.3, -0.8))

	# Chapeau conique (sugegasa) de voyage
	_draw_gradient_rect(img, hs - 16, hs - 26, 32, 8, Color(0.45, 0.30, 0.15), Color(0.35, 0.22, 0.10))
	_draw_rect(img, hs - 2, hs - 28, 4, 4, Color(0.45, 0.30, 0.15))
	_draw_line(img, hs - 14, hs - 24, hs + 14, hs - 24, Color(0.35, 0.22, 0.10), 1)
	# Lanière du chapeau
	_draw_line(img, hs - 8, hs - 16, hs + 8, hs - 12, Color(0.55, 0.40, 0.20), 1)

	# Cheveux grisonnants (marchand âgé)
	_draw_shaded_circle(img, hs, hs - 18, 10, Color(0.25, 0.22, 0.20), Vector2(-0.3, -0.8))
	_draw_circle(img, hs + 6, hs - 20, 4, Color(0.25, 0.22, 0.20))

	# Yeux (petits, plissés - marchand souriant)
	_draw_shaded_circle(img, hs - 5, hs - 14, 3, Color(0.95, 0.95, 0.95), Vector2(-0.2, -0.2))
	_draw_shaded_circle(img, hs + 5, hs - 14, 3, Color(0.95, 0.95, 0.95), Vector2(-0.2, -0.2))
	_draw_circle(img, hs - 5, hs - 14, 2, Color(0.15, 0.10, 0.08))
	_draw_circle(img, hs + 5, hs - 14, 2, Color(0.15, 0.10, 0.08))
	_draw_rect(img, hs - 6, hs - 15, 2, 2, Color(0.05, 0.05, 0.05))
	_draw_rect(img, hs + 4, hs - 15, 2, 2, Color(0.05, 0.05, 0.05))
	# Pattes d'oie (rides de sourire)
	_draw_line(img, hs - 8, hs - 13, hs - 10, hs - 12, Color(0.65, 0.50, 0.40), 1)
	_draw_line(img, hs + 8, hs - 13, hs + 10, hs - 12, Color(0.65, 0.50, 0.40), 1)

	# Sourire bienveillant
	_draw_rect(img, hs - 4, hs - 7, 8, 2, Color(0.12, 0.08, 0.06))
	_draw_rect(img, hs - 3, hs - 7, 6, 1, Color(0.70, 0.20, 0.18))
	_draw_line(img, hs - 5, hs - 7, hs + 5, hs - 7, Color(0.75, 0.25, 0.22), 1)

	# Moustache fine
	_draw_line(img, hs - 8, hs - 10, hs - 2, hs - 9, Color(0.20, 0.18, 0.16), 1)
	_draw_line(img, hs + 2, hs - 9, hs + 8, hs - 10, Color(0.20, 0.18, 0.16), 1)
	# Petite barbiche
	_draw_line(img, hs - 2, hs - 6, hs, hs - 3, Color(0.20, 0.18, 0.16), 1)
	_draw_line(img, hs, hs - 3, hs + 2, hs - 6, Color(0.20, 0.18, 0.16), 1)

	# Obi (ceinture) large dorée
	_draw_rect(img, hs - 8, hs + 10, 16, 5, Color(0.75, 0.60, 0.20))
	_draw_rect(img, hs - 8, hs + 12, 16, 2, Color(0.85, 0.70, 0.25))

	# Sacoche de marchand à la ceinture
	_draw_gradient_rect(img, hs + 8, hs + 8, 10, 10, Color(0.50, 0.35, 0.20), Color(0.40, 0.25, 0.15))
	_draw_rect(img, hs + 8, hs + 7, 10, 2, Color(0.60, 0.45, 0.25))
	# Boucle de la sacoche
	_draw_circle(img, hs + 13, hs + 12, 2, Color(0.75, 0.65, 0.35))
	_draw_circle(img, hs + 13, hs + 12, 1, Color(0.85, 0.75, 0.40))

	# Bâton de marche (shakujō) à droite
	_draw_line(img, hs + 20, hs - 8, hs + 20, hs + 26, Color(0.55, 0.40, 0.25), 3)
	_draw_line(img, hs + 19, hs - 8, hs + 21, hs - 8, Color(0.65, 0.50, 0.30), 3)
	# Anneaux du bâton
	_draw_circle(img, hs + 20, hs - 2, 3, Color(0.75, 0.72, 0.68))
	_draw_circle(img, hs + 20, hs - 2, 2, Color(0.60, 0.55, 0.50))
	_draw_circle(img, hs + 20, hs + 6, 3, Color(0.75, 0.72, 0.68))
	_draw_circle(img, hs + 20, hs + 6, 2, Color(0.60, 0.55, 0.50))
	# Embout du bâton
	_draw_shaded_circle(img, hs + 20, hs + 26, 3, Color(0.65, 0.55, 0.35), Vector2(-0.3, -0.5))

	# Hakama (pantalon)
	_draw_gradient_rect(img, hs - 8, hs + 16, 6, 10, Color(0.45, 0.28, 0.55), Color(0.35, 0.20, 0.45))
	_draw_gradient_rect(img, hs + 2, hs + 16, 6, 10, Color(0.45, 0.28, 0.55), Color(0.35, 0.20, 0.45))

	# Geta (sandales en bois)
	_draw_rect(img, hs - 9, hs + 24, 8, 3, Color(0.35, 0.25, 0.18))
	_draw_rect(img, hs + 1, hs + 24, 8, 3, Color(0.35, 0.25, 0.18))
	# Dents des geta
	_draw_rect(img, hs - 6, hs + 26, 2, 2, Color(0.35, 0.25, 0.18))
	_draw_rect(img, hs + 4, hs + 26, 2, 2, Color(0.35, 0.25, 0.18))

	# Lueur dorée subtile autour du marchand
	for x in range(hs - 22, hs + 22):
		for y in range(hs - 22, hs + 22):
			var dx: float = float(x - hs) / 20.0
			var dy: float = float(y - hs) / 20.0
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist >= 0.85 and dist <= 1.0:
				var existing: Color = img.get_pixel(x, y)
				if existing.a < 0.1:
					img.set_pixel(x, y, Color(0.85, 0.72, 0.30, 0.10))

# ============================================================
# TORII (porte de sanctuaire shinto) 96x96
# ============================================================
func _generate_torii_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	_draw_rect(img, hs - 40, s - 8, 80, 6, Color(0, 0, 0, 0.22))

	_draw_rect(img, hs - 26, 20, 2, 66, Color(0.40, 0.06, 0.04))
	_draw_gradient_rect(img, hs - 24, 20, 6, 66, Color(0.92, 0.20, 0.16), Color(0.70, 0.12, 0.10))
	_draw_rect(img, hs - 18, 20, 2, 66, Color(0.96, 0.28, 0.22))

	_draw_rect(img, hs + 16, 20, 2, 66, Color(0.96, 0.28, 0.22))
	_draw_gradient_rect(img, hs + 18, 20, 6, 66, Color(0.88, 0.18, 0.14), Color(0.65, 0.10, 0.08))
	_draw_rect(img, hs + 24, 20, 2, 66, Color(0.40, 0.06, 0.04))

	_draw_rect(img, hs - 38, 12, 76, 3, Color(0.35, 0.04, 0.03))
	_draw_gradient_rect(img, hs - 36, 10, 72, 8, Color(0.95, 0.24, 0.20), Color(0.78, 0.14, 0.12))
	_draw_rect(img, hs - 36, 10, 72, 2, Color(0.98, 0.30, 0.24))
	_draw_rect(img, hs - 36, 16, 72, 2, Color(0.65, 0.10, 0.08))

	_draw_rect(img, hs - 32, 28, 64, 2, Color(0.40, 0.06, 0.04))
	_draw_gradient_rect(img, hs - 30, 26, 60, 6, Color(0.90, 0.22, 0.18), Color(0.72, 0.14, 0.12))
	_draw_rect(img, hs - 30, 26, 60, 2, Color(0.94, 0.26, 0.22))

	_draw_rect(img, hs - 44, 8, 8, 10, Color(0.90, 0.20, 0.16))
	_draw_rect(img, hs - 43, 6, 6, 4, Color(0.95, 0.24, 0.20))
	_draw_rect(img, hs + 36, 8, 8, 10, Color(0.90, 0.20, 0.16))
	_draw_rect(img, hs + 37, 6, 6, 4, Color(0.95, 0.24, 0.20))

	_draw_rect(img, hs - 2, 8, 4, 18, Color(0.90, 0.92, 0.88))
	_draw_rect(img, hs - 1, 10, 2, 14, Color(0.96, 0.96, 0.92))

	_draw_gradient_rect(img, hs - 38, 16, 10, 5, Color(0.50, 0.50, 0.55), Color(0.40, 0.40, 0.45))
	_draw_gradient_rect(img, hs + 28, 16, 10, 5, Color(0.50, 0.50, 0.55), Color(0.40, 0.40, 0.45))


# ============================================================
# LANTERNE DE PIERRE (toro) 64x64
# ============================================================
func _generate_lantern_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	_draw_rect(img, hs - 10, s - 6, 20, 6, Color(0, 0, 0, 0.22))

	_draw_rect(img, hs - 14, hs + 16, 28, 8, Color(0.45, 0.45, 0.50))
	_draw_rect(img, hs - 12, hs + 14, 24, 3, Color(0.50, 0.50, 0.55))

	_draw_rect(img, hs - 6, hs + 2, 12, 14, Color(0.48, 0.48, 0.52))
	_draw_rect(img, hs - 4, hs + 2, 8, 14, Color(0.52, 0.52, 0.56))
	_draw_rect(img, hs - 3, hs + 4, 6, 10, Color(0.55, 0.55, 0.60))

	_draw_rect(img, hs - 12, hs - 2, 24, 6, Color(0.42, 0.42, 0.48))
	_draw_rect(img, hs - 10, hs, 20, 4, Color(0.50, 0.50, 0.55))

	_draw_rect(img, hs - 10, hs - 10, 20, 10, Color(0.55, 0.55, 0.60))
	_draw_rect(img, hs - 8, hs - 8, 16, 6, Color(1.0, 0.95, 0.70, 0.40))
	_draw_rect(img, hs - 6, hs - 6, 12, 4, Color(1.0, 0.95, 0.70, 0.60))

	_draw_gradient_rect(img, hs - 14, hs - 16, 28, 8, Color(0.48, 0.48, 0.52), Color(0.42, 0.42, 0.46))
	_draw_rect(img, hs - 12, hs - 18, 24, 3, Color(0.45, 0.45, 0.50))

	_draw_rect(img, hs - 4, hs - 24, 8, 8, Color(0.40, 0.40, 0.45))
	_draw_rect(img, hs - 2, hs - 26, 4, 4, Color(0.48, 0.48, 0.52))

	_draw_rect(img, hs - 16, hs + 4, 4, 6, Color(0.50, 0.48, 0.45))
	_draw_rect(img, hs + 12, hs + 4, 4, 6, Color(0.50, 0.48, 0.45))

	for gx in range(hs - 8, hs + 8):
		for gy in range(hs - 10, hs):
			var gdist: float = sqrt(float(gx - hs)**2 + float(gy - hs + 5)**2)
			if gdist < 8:
				var alpha: float = (1.0 - gdist / 8.0) * 0.15
				img.set_pixel(gx, gy, Color(1.0, 0.90, 0.50, alpha))


# ============================================================
# PETIT SANCTUAIRE (hokora) 64x64
# ============================================================
func _generate_shrine_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	_draw_rect(img, hs - 24, s - 6, 48, 6, Color(0, 0, 0, 0.25))

	_draw_rect(img, hs - 24, hs + 6, 48, 12, Color(0.55, 0.55, 0.60))
	_draw_rect(img, hs - 22, hs + 4, 44, 3, Color(0.60, 0.60, 0.65))
	_add_noise_to_rect(img, hs - 22, hs + 6, 44, 10, Color(0.55, 0.55, 0.60), 0.03, rng)

	_draw_rect(img, hs - 20, hs - 22, 8, 26, Color(0.85, 0.85, 0.80))
	_draw_rect(img, hs + 12, hs - 22, 8, 26, Color(0.85, 0.85, 0.80))
	_draw_rect(img, hs - 18, hs - 22, 4, 26, Color(0.15, 0.10, 0.06))
	_draw_rect(img, hs + 14, hs - 22, 4, 26, Color(0.15, 0.10, 0.06))
	_draw_rect(img, hs - 18, hs - 22, 36, 4, Color(0.15, 0.10, 0.06))
	_draw_rect(img, hs - 18, hs + 4, 36, 4, Color(0.15, 0.10, 0.06))

	_draw_rect(img, hs - 4, hs - 16, 8, 18, Color(0.75, 0.30, 0.18))
	_draw_rect(img, hs - 2, hs - 14, 4, 14, Color(0.85, 0.35, 0.22))
	_draw_rect(img, hs - 3, hs - 12, 6, 2, Color(0.60, 0.22, 0.15))
	_draw_rect(img, hs - 3, hs - 6, 6, 2, Color(0.60, 0.22, 0.15))

	_draw_gradient_rect(img, hs - 26, hs - 32, 52, 12, Color(0.28, 0.12, 0.06), Color(0.22, 0.08, 0.04))
	_draw_rect(img, hs - 24, hs - 34, 48, 3, Color(0.32, 0.14, 0.08))
	_draw_rect(img, hs - 22, hs - 22, 44, 2, Color(0.30, 0.12, 0.06))

	for tx in [hs - 24, hs - 14, hs - 4, hs + 6, hs + 16]:
		_draw_rect(img, tx, hs - 32, 2, 10, Color(0.18, 0.06, 0.03))

	_draw_rect(img, hs - 6, hs - 38, 12, 8, Color(0.28, 0.12, 0.06))
	_draw_rect(img, hs - 4, hs - 40, 8, 4, Color(0.32, 0.14, 0.08))
	_draw_rect(img, hs - 2, hs - 42, 4, 3, Color(0.35, 0.16, 0.10))

	_draw_rect(img, hs - 14, hs - 34, 28, 3, Color(0.50, 0.22, 0.10))


# ============================================================
# CERISIER (sakura) 64x64
# ============================================================
func _generate_sakura_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	_draw_rect(img, hs - 6, s - 6, 12, 6, Color(0, 0, 0, 0.20))

	_draw_rect(img, hs - 4, hs, 8, 24, Color(0.35, 0.22, 0.12))
	_draw_rect(img, hs - 2, hs + 2, 4, 22, Color(0.40, 0.25, 0.14))
	_draw_rect(img, hs - 3, hs + 6, 6, 2, Color(0.30, 0.18, 0.10))
	_draw_rect(img, hs - 3, hs + 14, 6, 2, Color(0.30, 0.18, 0.10))

	_draw_rect(img, hs - 16, hs - 4, 14, 5, Color(0.32, 0.20, 0.10))
	_draw_rect(img, hs + 2, hs - 8, 16, 5, Color(0.32, 0.20, 0.10))
	_draw_rect(img, hs - 12, hs - 12, 10, 4, Color(0.30, 0.18, 0.10))
	_draw_rect(img, hs + 4, hs - 16, 12, 4, Color(0.32, 0.20, 0.10))
	_draw_rect(img, hs - 4, hs - 22, 6, 8, Color(0.30, 0.18, 0.10))

	_draw_circle(img, hs, hs - 16, 26, Color(0.88, 0.70, 0.80))
	_draw_circle(img, hs - 8, hs - 22, 20, Color(0.90, 0.75, 0.82))
	_draw_circle(img, hs + 10, hs - 20, 18, Color(0.90, 0.75, 0.82))
	_draw_circle(img, hs, hs - 24, 16, Color(0.92, 0.78, 0.85))
	_draw_circle(img, hs - 4, hs - 28, 12, Color(0.95, 0.80, 0.88))
	_draw_circle(img, hs + 6, hs - 28, 10, Color(0.95, 0.80, 0.88))

	_draw_circle(img, hs - 12, hs - 18, 8, Color(0.92, 0.78, 0.85))
	_draw_circle(img, hs + 14, hs - 14, 8, Color(0.90, 0.75, 0.82))
	_draw_circle(img, hs, hs - 34, 8, Color(0.95, 0.82, 0.90))

	_draw_circle(img, hs + 4, hs - 20, 4, Color(0.95, 0.85, 0.88))
	_draw_circle(img, hs - 6, hs - 24, 3, Color(0.95, 0.85, 0.88))
	_draw_circle(img, hs + 10, hs - 22, 3, Color(0.95, 0.85, 0.88))

	for _i in range(8):
		var px: int = rng.randi_range(hs - 24, hs + 24)
		var py: int = rng.randi_range(hs + 2, hs + 16)
		var size_f: float = rng.randf()
		if size_f < 0.3:
			_draw_circle(img, px, py, 2, Color(0.95, 0.78, 0.85))
		elif size_f < 0.6:
			_draw_circle(img, px, py, 2, Color(0.92, 0.72, 0.80))
		else:
			_draw_circle(img, px, py, 1, Color(0.96, 0.82, 0.88))


# ============================================================
# PUITS JAPONAIS (ido) 64x64
# ============================================================
func _generate_well_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	_draw_rect(img, hs - 16, s - 6, 32, 6, Color(0, 0, 0, 0.22))

	_draw_gradient_rect(img, hs - 16, hs + 4, 32, 8, Color(0.50, 0.48, 0.45), Color(0.42, 0.40, 0.38))
	_draw_rect(img, hs - 14, hs + 2, 28, 4, Color(0.55, 0.52, 0.48))
	_draw_rect(img, hs - 14, hs + 4, 28, 2, Color(0.48, 0.45, 0.42))
	_draw_rect(img, hs - 14, hs - 2, 28, 6, Color(0.35, 0.32, 0.30))
	_draw_rect(img, hs - 12, hs, 24, 4, Color(0.06, 0.04, 0.03))

	_draw_rect(img, hs - 18, hs - 6, 6, 10, Color(0.30, 0.18, 0.10))
	_draw_rect(img, hs + 12, hs - 6, 6, 10, Color(0.30, 0.18, 0.10))
	_draw_rect(img, hs - 16, hs - 8, 4, 8, Color(0.35, 0.22, 0.12))
	_draw_rect(img, hs + 12, hs - 8, 4, 8, Color(0.35, 0.22, 0.12))

	_draw_gradient_rect(img, hs - 20, hs - 18, 40, 12, Color(0.28, 0.12, 0.06), Color(0.22, 0.08, 0.04))
	_draw_rect(img, hs - 18, hs - 20, 36, 3, Color(0.32, 0.14, 0.08))
	_draw_rect(img, hs - 16, hs - 18, 32, 2, Color(0.35, 0.16, 0.10))

	for tx in [hs - 18, hs - 8, hs + 2, hs + 12]:
		_draw_rect(img, tx, hs - 18, 2, 10, Color(0.18, 0.06, 0.03))

	_draw_rect(img, hs - 4, hs - 26, 8, 10, Color(0.28, 0.12, 0.06))
	_draw_rect(img, hs - 2, hs - 28, 4, 4, Color(0.32, 0.14, 0.08))

	_draw_rect(img, hs - 12, hs - 26, 6, 4, Color(0.45, 0.30, 0.18))
	_draw_rect(img, hs + 6, hs - 26, 6, 4, Color(0.45, 0.30, 0.18))
	_draw_rect(img, hs - 12, hs - 28, 6, 3, Color(0.50, 0.35, 0.22))
	_draw_rect(img, hs + 6, hs - 28, 6, 3, Color(0.50, 0.35, 0.22))

	_draw_rect(img, hs - 10, hs - 22, 4, 6, Color(0.55, 0.45, 0.25))
	_draw_rect(img, hs + 6, hs - 22, 4, 6, Color(0.55, 0.45, 0.25))

	_draw_rect(img, hs - 1, hs - 6, 2, 10, Color(0.55, 0.45, 0.30))
	_draw_rect(img, hs - 2, hs - 8, 4, 4, Color(0.42, 0.32, 0.20))


# ============================================================
# CLOCHE DE TEMPLE (bonsho) 64x64
# ============================================================
func _generate_bell_sprite(img: Image, size: int, rng: RandomNumberGenerator) -> void:
	var s: int = size
	var hs: int = s / 2

	_draw_rect(img, hs - 14, s - 4, 28, 4, Color(0, 0, 0, 0.20))

	_draw_rect(img, hs - 18, hs - 22, 36, 6, Color(0.30, 0.18, 0.10))
	_draw_gradient_rect(img, hs - 16, hs - 24, 32, 4, Color(0.35, 0.22, 0.12), Color(0.28, 0.16, 0.08))
	_draw_rect(img, hs - 14, hs - 24, 28, 2, Color(0.38, 0.24, 0.14))
	for bx in [hs - 16, hs - 6, hs + 4, hs + 10]:
		_draw_rect(img, bx, hs - 22, 3, 5, Color(0.22, 0.12, 0.06))

	_draw_gradient_rect(img, hs - 14, hs - 16, 28, 28, Color(0.72, 0.62, 0.48), Color(0.55, 0.45, 0.32))
	_draw_rect(img, hs - 12, hs - 18, 24, 28, Color(0.65, 0.55, 0.42))
	_draw_rect(img, hs - 10, hs - 16, 20, 24, Color(0.68, 0.58, 0.45))

	_draw_rect(img, hs - 3, hs - 20, 6, 4, Color(0.40, 0.32, 0.22))
	_draw_rect(img, hs - 2, hs - 22, 4, 3, Color(0.50, 0.42, 0.30))

	_draw_rect(img, hs - 1, hs - 4, 2, 6, Color(0.45, 0.35, 0.25))

	_draw_rect(img, hs - 6, hs + 8, 12, 4, Color(0.60, 0.50, 0.38))
	_draw_rect(img, hs - 4, hs + 10, 8, 2, Color(0.50, 0.40, 0.30))

	var sd: int = 8
	for dx in range(-sd, sd + 1):
		for dy in range(-sd, sd + 1):
			var dist: float = sqrt(float(dx)**2 + float(dy)**2)
			if dist < sd:
				var nx: int = hs + dx
				var ny: int = hs + dy
				if nx >= 0 and nx < s and ny >= 0 and ny < s:
					var existing: Color = img.get_pixel(nx, ny)
					if existing.a > 0.1:
						var shade: float = float(dx * (-0.3) + dy * (-0.4)) / float(sd) * 0.15
						var c: Color = img.get_pixel(nx, ny)
						c.r = clamp(c.r + shade, 0, 1)
						c.g = clamp(c.g + shade, 0, 1)
						c.b = clamp(c.b + shade, 0, 1)
						img.set_pixel(nx, ny, c)

	_draw_rect(img, hs - 6, hs + 4, 12, 4, Color(0.35, 0.28, 0.18))
	_draw_rect(img, hs - 4, hs + 4, 8, 2, Color(0.50, 0.42, 0.30))

	_draw_rect(img, hs - 14, hs - 4, 28, 2, Color(0.40, 0.32, 0.22))
	_draw_rect(img, hs - 12, hs + 2, 24, 2, Color(0.40, 0.32, 0.22))

	_draw_rect(img, hs - 2, hs - 8, 4, 4, Color(0.55, 0.50, 0.45))
	_draw_rect(img, hs - 1, hs - 9, 2, 2, Color(0.65, 0.60, 0.55))


# ============================================================
# FIN GÉNÉRATEUR DE SPRITES
# ============================================================
