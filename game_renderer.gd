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
        _draw_hp_bar(game.player_pos, game.player_vel, game.PLAYER_RADIUS, game.player_hp, game.PLAYER_MAX_HP)

    for enemy in game.enemies:
        if enemy.alive:
            var ecol: Color = _enemy_color(enemy.archetype as String)
            _draw_ship_triangle(enemy.pos as Vector2, enemy.vel as Vector2, game.ENEMY_RADIUS, ecol)
            _draw_hp_bar(enemy.pos as Vector2, enemy.vel as Vector2, game.ENEMY_RADIUS, enemy.hp as int, game.ENEMY_MAX_HP)

    for missile in game.missiles:
        var col: Color = game.MISSILE_COLOR
        if not missile.from_player:
            col = game.ENEMY_MISSILE_COLOR
        _draw_missile_triangle(missile.pos as Vector2, missile.vel as Vector2, game.MISSILE_RADIUS, col)

    _draw_explosions()
    _draw_debris()

    if game.phase == Game.GamePhase.PLANNING and game.player_alive:
        _draw_thrust_arrow()
        _draw_thrust_preview()


func _draw_hp_bar(center: Vector2, vel: Vector2, radius: float, current_hp: int, max_hp: int) -> void:
    var fwd := vel.normalized() if vel != Vector2.ZERO else Vector2.UP
    var bar_width := radius * 2.0
    var bar_height := 4.0
    var bar_offset := radius * 1.8
    var bar_center := center - fwd * bar_offset
    var bar_start := bar_center - Vector2(-fwd.y, fwd.x) * bar_width * 0.5

    draw_rect(Rect2(bar_start - Vector2(0, bar_height * 0.5), Vector2(bar_width, bar_height)), Color(0, 0, 0, 0.5), true)

    var ratio := float(current_hp) / float(max_hp)
    var bar_color: Color
    if ratio > 0.5:
        bar_color = Color(0.3, 1.0, 0.3, 0.8)
    elif ratio > 0.25:
        bar_color = Color(1.0, 0.8, 0.1, 0.8)
    else:
        bar_color = Color(1.0, 0.2, 0.2, 0.8)

    var fill_width := bar_width * ratio
    draw_rect(Rect2(bar_start - Vector2(0, bar_height * 0.5), Vector2(fill_width, bar_height)), bar_color, true)


func _enemy_color(archetype: String) -> Color:
    match archetype:
        "orbiter": return Color(1.0, 0.55, 0.1)   # orange
        "flanker": return Color(0.65, 0.4, 1.0)   # purple
        _:         return game.ENEMY_COLOR          # red (aggressor)


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
    # Stripes run at 45° along (1,1); perpendicular axis is (-1,1).
    # NOTE: parallelogram U-axis is in world space; _play_area_rect() is always centered at
    # world origin (Rect2(-half_extents, half_extents*2)), so this is always valid.

    const S2 := 1.41421356237  # sqrt(2), hoisted out of inner loop

    # Clip polygon — use Rect2.end for the bottom-right corner.
    var clip_poly := PackedVector2Array([
        rect.position,
        Vector2(rect.end.x, rect.position.y),
        rect.end,
        Vector2(rect.position.x, rect.end.y)
    ])

    # Project rect corners onto perpendicular axis p = (-x + y) to find stripe range.
    var proj_min := INF
    var proj_max := -INF
    for c: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
        var p := -c.x + c.y
        if p < proj_min: proj_min = p
        if p > proj_max: proj_max = p

    # Each stripe occupies stripe_width * sqrt2 in un-normalised projected space (~10 iterations for typical play area).
    var band := stripe_width * S2
    var start: float = floor(proj_min / (2.0 * band)) * (2.0 * band)
    var half_ext := (rect.size.x + rect.size.y) * 2.0

    var offset := start
    while offset < proj_max:
        for pass_idx in 2:
            var color: Color = stripe_color if pass_idx == 0 else gap_color
            var lo := offset + float(pass_idx) * band
            var hi := lo + band
            var v_lo := lo / S2
            var v_hi := hi / S2
            var u_lo := -half_ext / S2
            var u_hi :=  half_ext / S2
            var p0 := Vector2(u_lo - v_lo, u_lo + v_lo)
            var p1 := Vector2(u_hi - v_lo, u_hi + v_lo)
            var p2 := Vector2(u_hi - v_hi, u_hi + v_hi)
            var p3 := Vector2(u_lo - v_hi, u_lo + v_hi)
            var clipped_arrays := Geometry2D.intersect_polygons(PackedVector2Array([p0, p1, p2, p3]), clip_poly)
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


func _draw_thrust_arrow() -> void:
    var thrust: Vector2 = game.planned_thrust
    if thrust == Vector2.ZERO:
        return
    var raw_len: float = thrust.length()
    if raw_len < 1.0:
        return
    var ratio: float    = minf(raw_len / game.MAX_PLAYER_THRUST, 1.0)
    var dir: Vector2    = thrust.normalized()
    var arrow_len: float = ratio * game.THRUST_ARROW_MAX_LEN

    var tip: Vector2    = game.player_pos + dir * arrow_len
    var shaft_col: Color = Color(0.3, 1.0, 0.45, 0.7)
    var head_size: float = 8.0

    # Shaft
    draw_line(game.player_pos, tip, shaft_col, 2.0)

    # Arrowhead
    var perp: Vector2 = Vector2(-dir.y, dir.x)
    draw_line(tip, tip - dir * head_size + perp * head_size * 0.5, shaft_col, 2.0)
    draw_line(tip, tip - dir * head_size - perp * head_size * 0.5, shaft_col, 2.0)

    # Dim indicator dot when thrust is at max (mouse beyond max range)
    if ratio >= 1.0:
        draw_circle(tip, 3.0, Color(0.3, 1.0, 0.45, 0.4))


func _draw_thrust_preview() -> void:
    var thrust: Vector2  = game.planned_thrust
    var steps: int       = 20
    var dt: float        = game.SIM_DURATION / float(steps)
    var mass: float      = game.player_mass

    var ppos: Vector2 = game.player_pos
    var pvel: Vector2 = game.player_vel
    var accel: Vector2 = thrust / mass
    # Gravity intentionally omitted — this is a "dumb" preview (see design spec Section 2).

    var dot_col: Color = Color(0.3, 1.0, 0.45, 0.35)
    for i in steps:
        pvel += accel * dt
        ppos += pvel * dt
        draw_circle(ppos, 2.5, dot_col)

    # Ghost ship at endpoint, facing predicted velocity
    if pvel.length() > 0.1:
        var ghost_col: Color = game.PLAYER_COLOR
        ghost_col.a   = 0.3
        _draw_ship_triangle(ppos, pvel, game.PLAYER_RADIUS, ghost_col)


func _draw_explosions() -> void:
    for explosion in game.explosions:
        var t := 1.0 - (explosion.lifetime as float) / (explosion.max_lifetime as float)
        var current_r := (explosion.radius as float) * t
        var alpha := (1.0 - t) * 0.8
        var is_ship: bool = explosion.is_ship as bool
        var ring_color := Color(1.0, 0.5, 0.1, alpha) if is_ship else Color(1.0, 0.9, 0.3, alpha)
        if current_r > 1.0:
            draw_arc(explosion.pos as Vector2, current_r, 0.0, TAU, 32, ring_color, 2.5)


func _draw_debris() -> void:
    for d in game.debris:
        var t := 1.0 - (d.lifetime as float) / (d.max_lifetime as float)
        var alpha := (1.0 - t) * 0.9
        var color := Color(1.0, 0.55, 0.15, alpha)
        var size: float = d.size as float
        var pos: Vector2 = d.pos as Vector2
        var angle: float = d.angle as float
        var p0 := pos + Vector2(cos(angle), sin(angle)) * size
        var p1 := pos + Vector2(cos(angle + TAU * 0.333), sin(angle + TAU * 0.333)) * size
        var p2 := pos + Vector2(cos(angle + TAU * 0.667), sin(angle + TAU * 0.667)) * size
        draw_polygon(PackedVector2Array([p0, p1, p2]), PackedColorArray([color, color, color]))
