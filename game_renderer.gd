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
			_draw_ship_triangle(enemy.pos, enemy.vel, game.ENEMY_RADIUS, game.ENEMY_COLOR)

	for missile in game.missiles:
		var col: Color = game.MISSILE_COLOR
		if not missile.from_player:
			col = game.ENEMY_MISSILE_COLOR
		_draw_missile_triangle(missile.pos, missile.vel, game.MISSILE_RADIUS, col)

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
	var t := game.PLAY_BORDER_THICKNESS

	draw_rect(Rect2(r.position, Vector2(r.size.x, t)), game.BORDER_COLOR, true)
	draw_rect(Rect2(Vector2(r.position.x, r.position.y + r.size.y - t), Vector2(r.size.x, t)), game.BORDER_COLOR, true)
	draw_rect(Rect2(r.position, Vector2(t, r.size.y)), game.BORDER_COLOR, true)
	draw_rect(Rect2(Vector2(r.position.x + r.size.x - t, r.position.y), Vector2(t, r.size.y)), game.BORDER_COLOR, true)


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
	var end_pos := game._arc_endpoint(game.player_pos, game.player_vel.normalized(), game.planned_player_speed, game.planned_turn_angle)
	var end_facing := game.player_vel.normalized().rotated(game.planned_turn_angle)
	_draw_ship_triangle(end_pos, end_facing, game.PLAYER_RADIUS, col)


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
		outer_pts.append(game._arc_endpoint(game.player_pos, forward_dir, game.PLAYER_SPEED_MAX, ang))

	var inner_pts: Array[Vector2] = []
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var ang := game.turn_limit_this_turn - 2.0 * game.turn_limit_this_turn * t
		inner_pts.append(game._arc_endpoint(game.player_pos, forward_dir, game.PLAYER_SPEED_MIN, ang))

	for i in range(outer_pts.size() - 1):
		draw_line(outer_pts[i], outer_pts[i + 1], col, 1.0)
	for i in range(inner_pts.size() - 1):
		draw_line(inner_pts[i], inner_pts[i + 1], col, 1.0)

	draw_line(outer_pts[0], inner_pts[inner_pts.size() - 1], col, 1.0)
	draw_line(outer_pts[outer_pts.size() - 1], inner_pts[0], col, 1.0)
