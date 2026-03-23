extends Node2D

var game: Game

func _ready() -> void:
	game = get_parent() as Game

func _draw() -> void:
	_draw_starfield()
	_draw_outside_dark_mask()
	_draw_play_area_inner_border()

	if game.player_alive:
		_draw_ship_triangle(game.player_pos, game.player_vel, game.PLAYER_RADIUS, game.PLAYER_COLOR)

	for enemy in game.enemies:
		if enemy.alive:
			_draw_ship_triangle(enemy.pos as Vector2, enemy.vel as Vector2, game.ENEMY_RADIUS, game.ENEMY_COLOR)

	for missile in game.missiles:
		var col: Color = game.MISSILE_COLOR
		if not missile.from_player:
			col = game.ENEMY_MISSILE_COLOR
		_draw_missile_triangle(missile.pos as Vector2, missile.vel as Vector2, game.MISSILE_RADIUS, col)

	if game.phase == Game.GamePhase.PLANNING and game.player_alive:
		_draw_turn_wedge()
		_draw_planned_path()
		_draw_planned_ghost()


func _draw_ship_triangle(center: Vector2, vel: Vector2, radius: float, color: Color) -> void:
	var fwd := vel.normalized() if vel != Vector2.ZERO else Vector2.UP
	var right := Vector2(-fwd.y, fwd.x)
	var tip := center + fwd * radius
	var back_left := center - fwd * radius * 0.5 + right * radius * 0.65
	var back_right := center - fwd * radius * 0.5 - right * radius * 0.65
	draw_polygon(PackedVector2Array([tip, back_left, back_right]), PackedColorArray([color, color, color]))


func _draw_missile_triangle(center: Vector2, vel: Vector2, radius: float, color: Color) -> void:
	var fwd := vel.normalized() if vel != Vector2.ZERO else Vector2.UP
	var right := Vector2(-fwd.y, fwd.x)
	var tip := center + fwd * radius * 1.4
	var back_left := center - fwd * radius * 0.6 + right * radius * 0.4
	var back_right := center - fwd * radius * 0.6 - right * radius * 0.4
	draw_polygon(PackedVector2Array([tip, back_left, back_right]), PackedColorArray([color, color, color]))


func _draw_play_area_inner_border() -> void:
	var r := game._play_area_rect()
	var vt := game.PLAY_BORDER_THICKNESS * 3.0  # visual thickness only — collision uses PLAY_BORDER_THICKNESS

	var hazard_color := Color(1.0, 0.65, 0.0, 0.55)
	var black_color  := Color(0.0, 0.0, 0.0, 0.45)
	var stripe_width := 48.0

	# Left/right strips span full play area height.
	# Top/bottom strips span only the inner width (excluding left/right strip columns)
	# to avoid double-drawing corners.
	var inner_x := r.position.x + vt
	var inner_w := r.size.x - vt * 2.0

	# Top strip (inner width only)
	_draw_stripe_band(Rect2(Vector2(inner_x, r.position.y), Vector2(inner_w, vt)), hazard_color, black_color, stripe_width)
	# Bottom strip (inner width only)
	_draw_stripe_band(Rect2(Vector2(inner_x, r.position.y + r.size.y - vt), Vector2(inner_w, vt)), hazard_color, black_color, stripe_width)
	# Left strip (full height)
	_draw_stripe_band(Rect2(r.position, Vector2(vt, r.size.y)), hazard_color, black_color, stripe_width)
	# Right strip (full height)
	_draw_stripe_band(Rect2(Vector2(r.position.x + r.size.x - vt, r.position.y), Vector2(vt, r.size.y)), hazard_color, black_color, stripe_width)


func _draw_stripe_band(rect: Rect2, stripe_color: Color, gap_color: Color, stripe_width: float) -> void:
	# Draw alternating diagonal (45°) stripes clipped to rect.
	# Stripes run at 45°: a stripe parallelogram has two edges parallel to (1,1) direction.
	# Each stripe covers a band of width stripe_width measured perpendicular to the (1,1) direction.
	# We parameterise stripes by their offset along the (-1,1) axis (perpendicular to stripe direction).

	# The rect as a clip polygon (4 corners, clockwise).
	var clip_poly := PackedVector2Array([
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
		Vector2(rect.position.y + rect.size.y, rect.position.y + rect.size.y)  # placeholder – corrected below
	])
	clip_poly[3] = Vector2(rect.position.x, rect.position.y + rect.size.y)

	# Stripe direction: (1, 1) normalised → actual draw extends far past the rect.
	# Perpendicular axis for offset: (-1, 1) / sqrt2 — but we work in 45° projected coords.
	# Project rect corners onto perpendicular axis p = (-x + y) to find range of stripes needed.
	var corners := [
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
		Vector2(rect.position.x, rect.position.y + rect.size.y)
	]

	var proj_min := INF
	var proj_max := -INF
	for c: Vector2 in corners:
		var p := -c.x + c.y  # projection along (-1, 1) (un-normalised; width in this space = stripe_width * sqrt2)
		if p < proj_min:
			proj_min = p
		if p > proj_max:
			proj_max = p

	# Each stripe occupies stripe_width * sqrt2 in projected space (alternating with equal gap).
	var band := stripe_width * sqrt(2.0)
	# Snap start to a multiple of 2*band so pattern tiles consistently in world space.
	var start := floor(proj_min / (2.0 * band)) * (2.0 * band)

	var half_ext := (rect.size.x + rect.size.y) * 2.0  # generous extent along stripe direction

	var offset := start
	while offset < proj_max:
		# Build two parallelograms per iteration: one colored, one black (gap).
		for pass_idx in 2:
			var color: Color = stripe_color if pass_idx == 0 else gap_color
			var lo := offset + float(pass_idx) * band
			var hi := lo + band
			# The stripe parallelogram in screen space:
			# Along perpendicular (-1,1)/sqrt2: from lo/sqrt2 to hi/sqrt2
			# Along direction  (1,1)/sqrt2:     from -half_ext/sqrt2 to +half_ext/sqrt2
			# A point in this 2D rotated frame: pos = u*(1,1) + v*(-1,1)  (un-normalised, scaled by 1/sqrt2)
			# We pick four corners: (u,v) = (±half, lo) and (±half, hi) in projected units / sqrt2
			var h := half_ext
			var s2 := sqrt(2.0)
			# lo and hi are in (un-normalised) projected coords; divide by s2 to get actual screen offset
			var v_lo := lo / s2
			var v_hi := hi / s2
			var u_lo := -h / s2
			var u_hi :=  h / s2
			var p0 := Vector2(u_lo - v_lo, u_lo + v_lo)  # u*(1,1) + v*(-1,1) with u=u_lo, v=v_lo
			var p1 := Vector2(u_hi - v_lo, u_hi + v_lo)  # u=u_hi, v=v_lo
			var p2 := Vector2(u_hi - v_hi, u_hi + v_hi)  # u=u_hi, v=v_hi
			var p3 := Vector2(u_lo - v_hi, u_lo + v_hi)  # u=u_lo, v=v_hi
			var stripe_poly := PackedVector2Array([p0, p1, p2, p3])
			var clipped_arrays := Geometry2D.clip_polygons(stripe_poly, clip_poly)
			for clipped in clipped_arrays:
				if (clipped as PackedVector2Array).size() >= 3:
					var n := (clipped as PackedVector2Array).size()
					var cols := PackedColorArray()
					cols.resize(n)
					cols.fill(color)
					draw_polygon(clipped as PackedVector2Array, cols)
		offset += 2.0 * band


func _draw_outside_dark_mask() -> void:
	var r := game._play_area_rect()
	var dark_color := Color(0.0, 0.0, 0.0, 0.9)
	var big_size := r.size * 4.0
	var big_origin := -big_size * 0.5

	draw_rect(Rect2(big_origin, Vector2(big_size.x, r.position.y - big_origin.y)), dark_color, true)
	var bottom_y := r.position.y + r.size.y
	var bottom_height := big_origin.y + big_size.y - bottom_y
	draw_rect(Rect2(Vector2(big_origin.x, bottom_y), Vector2(big_size.x, bottom_height)), dark_color, true)
	draw_rect(Rect2(Vector2(big_origin.x, r.position.y), Vector2(r.position.x - big_origin.x, r.size.y)), dark_color, true)
	var right_x := r.position.x + r.size.x
	var right_width := big_origin.x + big_size.x - right_x
	draw_rect(Rect2(Vector2(right_x, r.position.y), Vector2(right_width, r.size.y)), dark_color, true)


func _draw_starfield() -> void:
	for layer_idx in game.STAR_LAYER_COUNT:
		var stars: Array = game._stars_by_layer[layer_idx]
		var parallax: float = float(game.STAR_PARALLAX_BY_LAYER[layer_idx])
		var radius: float = float(game.STAR_RADIUS_BY_LAYER[layer_idx])

		var shift := game.player_pos * parallax
		var shift_mod := Vector2(
			fposmod(shift.x, game.STAR_TILE_SIZE.x),
			fposmod(shift.y, game.STAR_TILE_SIZE.y)
		)

		for oy in [-1, 0, 1]:
			for ox in [-1, 0, 1]:
				var tile_offset := Vector2(float(ox) * game.STAR_TILE_SIZE.x, float(oy) * game.STAR_TILE_SIZE.y)
				for s: Vector2 in stars:
					var screen_pos: Vector2 = s + tile_offset - shift_mod
					var world_pos: Vector2 = game.player_pos + screen_pos
					draw_circle(world_pos, radius, game.STAR_COLOR)


func _draw_planned_path() -> void:
	var steps := 18
	var dt := game.SIM_DURATION / float(steps)

	var preview_pos := game.player_pos
	var preview_vel := game.player_vel
	var preview_speed := game.planned_player_speed
	var preview_turn_rate: float = 0.0
	if game.SIM_DURATION > 0.0:
		preview_turn_rate = game.planned_turn_angle / game.SIM_DURATION

	var prev := preview_pos
	for i in steps:
		var step_angle := preview_turn_rate * dt
		if step_angle != 0.0:
			preview_vel = preview_vel.rotated(step_angle)
		preview_vel = preview_vel.normalized() * preview_speed
		preview_pos += preview_vel * dt
		draw_line(prev, preview_pos, game.PLANNED_VECTOR_COLOR, 2.0)
		prev = preview_pos


func _draw_planned_ghost() -> void:
	var col := game.PLAYER_COLOR
	col.a = 0.35
	var tip_pos := game._arc_endpoint(game.player_pos, game.player_vel.normalized(), game.planned_player_speed, game.planned_turn_angle)
	var end_facing := game.player_vel.normalized().rotated(game.planned_turn_angle)
	# Offset center back so the triangle TIP lands exactly at tip_pos (arc endpoint)
	var center := tip_pos - end_facing.normalized() * game.PLAYER_RADIUS
	_draw_ship_triangle(center, end_facing, game.PLAYER_RADIUS, col)


func _draw_turn_wedge() -> void:
	var forward_dir := game.player_vel.normalized()
	if forward_dir == Vector2.ZERO:
		forward_dir = Vector2.UP

	var segments: int = 40
	var col := game.PLANNED_VECTOR_COLOR
	col.a = 0.25

	var outer_pts: Array[Vector2] = []
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var ang := -game.turn_limit_this_turn + 2.0 * game.turn_limit_this_turn * t
		var center := game._arc_endpoint(game.player_pos, forward_dir, game.turn_speed_max, ang)
		outer_pts.append(center + forward_dir.rotated(ang) * game.PLAYER_RADIUS)

	var inner_pts: Array[Vector2] = []
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var ang := game.turn_limit_this_turn - 2.0 * game.turn_limit_this_turn * t
		var center := game._arc_endpoint(game.player_pos, forward_dir, game.turn_speed_min, ang)
		inner_pts.append(center + forward_dir.rotated(ang) * game.PLAYER_RADIUS)

	for i in range(outer_pts.size() - 1):
		draw_line(outer_pts[i], outer_pts[i + 1], col, 1.0)
	for i in range(inner_pts.size() - 1):
		draw_line(inner_pts[i], inner_pts[i + 1], col, 1.0)

	draw_line(outer_pts[0], inner_pts[inner_pts.size() - 1], col, 1.0)
	draw_line(outer_pts[outer_pts.size() - 1], inner_pts[0], col, 1.0)
