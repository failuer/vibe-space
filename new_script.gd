extends Node2D

enum GamePhase { PLANNING, SIMULATING, ENDED }

const SIM_DURATION := 2.0 # seconds, tweakable
const PLAYER_RADIUS := 16.0
const ENEMY_RADIUS := 16.0
const MISSILE_RADIUS := 8.0

const PLAYER_SPEED_DEFAULT := 140.0 # units per second
const PLAYER_SPEED_MIN := 80.0
const PLAYER_SPEED_MAX := 220.0
const PLAYER_SPEED_STEP := 25.0
const ENEMY_SPEED := 140.0
const MISSILE_SPEED := 300.0
const SCENE_RADIUS := 1000.0 # missiles/enemies beyond this are considered gone
const MAX_TURN_RADIANS := PI / 2.0 # max turn per planning step (90 degrees)

const PLAYER_COLOR := Color(0.3, 0.9, 1.0)
const ENEMY_COLOR := Color(1.0, 0.4, 0.4)
const MISSILE_COLOR := Color(1.0, 1.0, 0.4)
const ENEMY_MISSILE_COLOR := Color(1.0, 0.6, 0.2)
const PLANNED_VECTOR_COLOR := Color(0.5, 1.0, 0.5)
const STAR_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const BORDER_COLOR := Color(1.0, 0.0, 0.0, 0.1)

const PLAY_AREA_HALF_EXTENTS := Vector2(975.0, 675.0) # 50% larger
const PLAY_BORDER_THICKNESS := 80.0

const PLAYER_TURN_RATE := MAX_TURN_RADIANS * 1.5 / SIM_DURATION # baseline sharper turns

const ARROW_MIN_DIST := PLAYER_SPEED_MIN * SIM_DURATION
const ARROW_MAX_DIST := PLAYER_SPEED_MAX * SIM_DURATION
const ARROW_NEAR_HALF_WIDTH := 40.0
const ARROW_FAR_HALF_WIDTH := 220.0

const STAR_TILE_SIZE := Vector2(900.0, 700.0)
const STAR_LAYER_COUNT := 3
const STAR_COUNTS_BY_LAYER := [120, 90, 60]
const STAR_PARALLAX_BY_LAYER := [0.15, 0.30, 0.55]
const STAR_RADIUS_BY_LAYER := [1.5, 1.2, 1.0]

@onready var camera: Camera2D = $Camera2D
@onready var message_label: Label = $CanvasLayer/MessageLabel
@onready var restart_button: Button = $CanvasLayer/RestartButton

var phase: GamePhase = GamePhase.PLANNING
var sim_time_left: float = 0.0

var player_pos: Vector2 = Vector2.ZERO
var player_vel: Vector2 = Vector2.UP * PLAYER_SPEED_DEFAULT
var player_speed: float = PLAYER_SPEED_DEFAULT
var player_alive: bool = true

var planned_player_vel: Vector2 = Vector2.UP * PLAYER_SPEED_DEFAULT
var planned_player_speed: float = PLAYER_SPEED_DEFAULT
var planned_fire: bool = false
var planned_player_target_dir: Vector2 = Vector2.UP # kept for reference but no longer used for homing
var planned_turn_angle: float = 0.0
var current_turn_rate: float = 0.0 # radians/sec for active slice
var planned_end_pos: Vector2 = Vector2.ZERO
var turn_limit_this_turn: float = MAX_TURN_RADIANS

var enemies: Array = [] # each: {pos: Vector2, vel: Vector2, alive: bool}
var missiles: Array = [] # each: {pos: Vector2, vel: Vector2, from_player: bool}

var end_state: StringName = ""
var end_timer: float = 0.0

var _stars_by_layer: Array = [] # each layer: Array[Vector2] positions inside STAR_TILE_SIZE


func _ready() -> void:
    randomize()
    _generate_stars()
    _reset_game()
    restart_button.pressed.connect(_on_restart_pressed)

func _generate_stars() -> void:
    _stars_by_layer.clear()
    for layer_idx in STAR_LAYER_COUNT:
        var stars: Array = []
        var count: int = int(STAR_COUNTS_BY_LAYER[layer_idx])
        for _i in count:
            stars.append(Vector2(
                randf_range(0.0, STAR_TILE_SIZE.x),
                randf_range(0.0, STAR_TILE_SIZE.y)
            ))
        _stars_by_layer.append(stars)


func _reset_game() -> void:
    # Initial player setup
    player_pos = Vector2.ZERO
    player_vel = Vector2.UP * PLAYER_SPEED_DEFAULT
    player_speed = PLAYER_SPEED_DEFAULT
    player_alive = true
    planned_player_vel = player_vel
    planned_player_speed = player_speed
    planned_player_target_dir = player_vel.normalized()
    planned_fire = false
    planned_turn_angle = 0.0
    current_turn_rate = 0.0
    planned_end_pos = player_pos
    turn_limit_this_turn = _compute_turn_limit_for_speed(player_speed)

    # Simple enemy setup: a few ships moving straight
    enemies.clear()
    enemies.append({
        "pos": Vector2(300.0, 0.0),
        "vel": Vector2.LEFT * ENEMY_SPEED,
        "alive": true,
    })
    enemies.append({
        "pos": Vector2(-250.0, -150.0),
        "vel": Vector2.RIGHT * ENEMY_SPEED,
        "alive": true,
    })
    enemies.append({
        "pos": Vector2(0.0, 250.0),
        "vel": Vector2.UP * ENEMY_SPEED,
        "alive": true,
    })

    missiles.clear()

    phase = GamePhase.PLANNING
    sim_time_left = 0.0
    end_state = ""
    end_timer = 0.0

    message_label.text = ""
    message_label.visible = false
    restart_button.visible = false

    queue_redraw()


func _process(delta: float) -> void:
    if phase == GamePhase.SIMULATING:
        _step_simulation(delta)
    elif phase == GamePhase.ENDED:
        _step_end_timer(delta)

    # Camera follows player
    camera.position = player_pos

    queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
    if phase == GamePhase.ENDED:
        return

    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_SPACE:
            if phase == GamePhase.PLANNING and player_alive:
                _start_simulation()

    if phase != GamePhase.PLANNING:
        return

    if event is InputEventMouseMotion:
        _update_planned_vector(get_global_mouse_position())
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            planned_fire = not planned_fire


func _start_simulation() -> void:
    phase = GamePhase.SIMULATING
    sim_time_left = SIM_DURATION

    # Commit planned movement intent for this turn (movement will curve at a constant rate over the whole slice)
    planned_player_target_dir = planned_player_vel.normalized()
    player_speed = planned_player_speed
    current_turn_rate = 0.0
    if SIM_DURATION > 0.0:
        current_turn_rate = planned_turn_angle / SIM_DURATION

    # Optionally spawn a missile straight ahead
    if planned_fire and player_alive:
        var dir := player_vel.normalized()
        var spawn_pos := player_pos + dir * (PLAYER_RADIUS + MISSILE_RADIUS + 2.0)
        missiles.append({
            "pos": spawn_pos,
            "vel": dir * MISSILE_SPEED,
            "from_player": true,
        })
        planned_fire = false

    # Enemies fire one missile each turn toward the player's current position (if alive)
    if player_alive:
        for enemy in enemies:
            if enemy.alive:
                var to_player: Vector2 = (player_pos - enemy.pos)
                if to_player != Vector2.ZERO:
                    var edir: Vector2 = to_player.normalized()
                    var e_spawn: Vector2 = enemy.pos + edir * (ENEMY_RADIUS + MISSILE_RADIUS + 2.0)
                    missiles.append({
                        "pos": e_spawn,
                        "vel": edir * MISSILE_SPEED,
                        "from_player": false,
                    })


func _step_simulation(delta: float) -> void:
    sim_time_left -= delta
    if sim_time_left <= 0.0:
        delta += sim_time_left # simulate only remaining time if overshoot
        sim_time_left = 0.0

    if delta > 0.0:
        _integrate_motion(delta)
        _handle_collisions()
        _check_leave_play_area()
        _cull_offscreen_objects()

    if _check_end_conditions():
        return

    if sim_time_left <= 0.0 and phase == GamePhase.SIMULATING:
        phase = GamePhase.PLANNING
        # Default next planned movement to "no new input"
        if player_alive:
            planned_player_vel = player_vel
            planned_player_speed = player_speed
            turn_limit_this_turn = _compute_turn_limit_for_speed(player_speed)


func _integrate_motion(delta: float) -> void:
    if player_alive:
        # Rotate at a constant rate for this slice, using the committed speed.
        var angle_step := current_turn_rate * delta
        if angle_step != 0.0:
            player_vel = player_vel.rotated(angle_step)
        player_vel = player_vel.normalized() * player_speed
        player_pos += player_vel * delta

    for enemy in enemies:
        if enemy.alive:
            enemy.pos += enemy.vel * delta

    for missile in missiles:
        missile.pos += missile.vel * delta


func _handle_collisions() -> void:
    # Missiles vs ships
    for missile in missiles:
        if missile.from_player:
            # Check enemies
            for enemy in enemies:
                if enemy.alive and _circles_overlap(missile.pos, MISSILE_RADIUS, enemy.pos, ENEMY_RADIUS):
                    enemy.alive = false
                    missile.pos.x = SCENE_RADIUS * 2.0 # push far away; will be culled
        else:
            # Enemy missiles vs player (not used in MVP, but left for extension)
            if player_alive and _circles_overlap(missile.pos, MISSILE_RADIUS, player_pos, PLAYER_RADIUS):
                player_alive = false
                missile.pos.x = SCENE_RADIUS * 2.0

    # Player vs enemies direct collision (1-hit kill)
    if player_alive:
        for enemy in enemies:
            if enemy.alive and _circles_overlap(player_pos, PLAYER_RADIUS, enemy.pos, ENEMY_RADIUS):
                player_alive = false
                enemy.alive = false


func _cull_offscreen_objects() -> void:
    # Culling relative to origin for simplicity
    var filtered_missiles: Array = []
    for missile in missiles:
        if missile.pos.length() <= SCENE_RADIUS:
            filtered_missiles.append(missile)
    missiles = filtered_missiles

    for enemy in enemies:
        if enemy.alive and enemy.pos.length() > SCENE_RADIUS:
            enemy.alive = false


func _check_leave_play_area() -> void:
    if not player_alive:
        return
    if not _is_inside_play_area(player_pos):
        player_alive = false


func _check_end_conditions() -> bool:
    var any_enemy_alive := false
    for enemy in enemies:
        if enemy.alive:
            any_enemy_alive = true
            break

    if player_alive and any_enemy_alive:
        return false

    if not player_alive:
        _begin_end_state("defeat")
        return true

    if not any_enemy_alive:
        _begin_end_state("victory")
        return true

    return false


func _begin_end_state(state: StringName) -> void:
    if phase == GamePhase.ENDED:
        return
    phase = GamePhase.ENDED
    end_state = state
    end_timer = 0.75


func _step_end_timer(delta: float) -> void:
    if end_timer > 0.0:
        end_timer -= delta
        if end_timer <= 0.0:
            _show_end_ui()


func _show_end_ui() -> void:
    if end_state == "victory":
        message_label.text = "Victory!"
    elif end_state == "defeat":
        message_label.text = "Defeat!"
    else:
        message_label.text = ""

    message_label.visible = true
    restart_button.visible = true


func _on_restart_pressed() -> void:
    _reset_game()


func _update_planned_vector(mouse_world: Vector2) -> void:
    if not player_alive:
        return

    var fwd := player_vel.normalized()
    var right := fwd.rotated(PI * 0.5)

    var raw := mouse_world - player_pos
    if raw == Vector2.ZERO:
        raw = fwd

    # Decompose mouse offset into the ship's local (forward, right) frame.
    var mx: float = raw.dot(fwd)
    var my: float = raw.dot(right)

    # Exact inversion of _arc_endpoint: the chord from start to arc endpoint points at θ/2
    # from the forward direction, so the required turn angle is twice the chord angle.
    var angle_raw := 2.0 * atan2(my, mx)
    var angle_clamped: float = clamp(angle_raw, -turn_limit_this_turn, turn_limit_this_turn)

    # After clamping, project the mouse onto the (possibly adjusted) chord direction
    # to get the chord length, then convert to arc length (= speed * SIM_DURATION).
    var chord_dir := fwd.rotated(angle_clamped * 0.5)
    var chord_len := maxf(0.0, raw.dot(chord_dir))
    var half_angle: float = angle_clamped * 0.5
    var arc_len: float = chord_len if abs(half_angle) < 1e-4 else chord_len * half_angle / sin(half_angle)

    planned_player_speed = clamp(arc_len / SIM_DURATION, PLAYER_SPEED_MIN, PLAYER_SPEED_MAX)
    planned_turn_angle = angle_clamped
    planned_player_vel = fwd.rotated(angle_clamped) * planned_player_speed


# Returns the actual endpoint of a circular-arc move: constant speed v, constant turn rate,
# total heading change = turn_angle over SIM_DURATION. This is the single source of truth
# for where any planned (speed, angle) combination lands — used by both the wedge and ghost.
func _arc_endpoint(start: Vector2, facing: Vector2, speed: float, turn_angle: float) -> Vector2:
    var fwd := facing.normalized()
    var T := SIM_DURATION
    if abs(turn_angle) < 1e-4:
        return start + fwd * speed * T
    var vT := speed * T
    var right := fwd.rotated(PI * 0.5)
    var x := vT * sin(turn_angle) / turn_angle
    var y := vT * (1.0 - cos(turn_angle)) / turn_angle
    return start + fwd * x + right * y


func _circles_overlap(a_pos: Vector2, a_radius: float, b_pos: Vector2, b_radius: float) -> bool:
    var r := a_radius + b_radius
    return a_pos.distance_squared_to(b_pos) <= r * r


func _play_area_rect() -> Rect2:
    return Rect2(-PLAY_AREA_HALF_EXTENTS, PLAY_AREA_HALF_EXTENTS * 2.0)


func _is_inside_play_area(p: Vector2) -> bool:
    return _play_area_rect().has_point(p)


func _draw() -> void:
    _draw_starfield()
    _draw_outside_dark_mask()
    _draw_play_area_inner_border()

    # Draw player
    if player_alive:
        _draw_circle_outline(player_pos, PLAYER_RADIUS, PLAYER_COLOR)

    # Draw enemies
    for enemy in enemies:
        if enemy.alive:
            _draw_circle_outline(enemy.pos, ENEMY_RADIUS, ENEMY_COLOR)

    # Draw missiles
    for missile in missiles:
        var col: Color = MISSILE_COLOR
        if not missile.from_player:
            col = ENEMY_MISSILE_COLOR
        _draw_circle_outline(missile.pos, MISSILE_RADIUS, col)

    # Draw planned movement vector and affordances in planning phase
    if phase == GamePhase.PLANNING and player_alive:
        _draw_turn_wedge()
        _draw_planned_path()
        _draw_planned_ghost()


func _draw_circle_outline(center: Vector2, radius: float, color: Color) -> void:
    var points := 32
    var angle_step := TAU / float(points)
    for i in points:
        var a := angle_step * i
        var b := angle_step * (i + 1)
        var p1 := center + Vector2(cos(a), sin(a)) * radius
        var p2 := center + Vector2(cos(b), sin(b)) * radius
        draw_line(p1, p2, color, 1.5)


func _draw_play_area_inner_border() -> void:
    var r := _play_area_rect()
    var t := PLAY_BORDER_THICKNESS

    # Top strip
    draw_rect(Rect2(r.position, Vector2(r.size.x, t)), BORDER_COLOR, true)
    # Bottom strip
    draw_rect(Rect2(Vector2(r.position.x, r.position.y + r.size.y - t), Vector2(r.size.x, t)), BORDER_COLOR, true)
    # Left strip
    draw_rect(Rect2(r.position, Vector2(t, r.size.y)), BORDER_COLOR, true)
    # Right strip
    draw_rect(Rect2(Vector2(r.position.x + r.size.x - t, r.position.y), Vector2(t, r.size.y)), BORDER_COLOR, true)


func _draw_outside_dark_mask() -> void:
    # Draw a full-screen dark quad, then punch a transparent hole for the play area.
    var r := _play_area_rect()
    var dark_color := Color(0.0, 0.0, 0.0, 0.9)

    # Big rect covering around the origin (larger than play area)
    var big_size := r.size * 4.0
    var big_origin := -big_size * 0.5

    # Four rectangles around the play area to approximate a mask.
    # Top
    draw_rect(Rect2(big_origin, Vector2(big_size.x, r.position.y - big_origin.y)), dark_color, true)
    # Bottom
    var bottom_y := r.position.y + r.size.y
    var bottom_height := big_origin.y + big_size.y - bottom_y
    draw_rect(Rect2(Vector2(big_origin.x, bottom_y), Vector2(big_size.x, bottom_height)), dark_color, true)
    # Left
    draw_rect(Rect2(Vector2(big_origin.x, r.position.y), Vector2(r.position.x - big_origin.x, r.size.y)), dark_color, true)
    # Right
    var right_x := r.position.x + r.size.x
    var right_width := big_origin.x + big_size.x - right_x
    draw_rect(Rect2(Vector2(right_x, r.position.y), Vector2(right_width, r.size.y)), dark_color, true)


func _draw_starfield() -> void:
    # Draw parallax stars in world-space so they scroll slower than gameplay objects.
    # We tile a small "screen-space" patch around the camera to avoid huge world coords.
    for layer_idx in STAR_LAYER_COUNT:
        var stars: Array = _stars_by_layer[layer_idx]
        var parallax: float = float(STAR_PARALLAX_BY_LAYER[layer_idx])
        var radius: float = float(STAR_RADIUS_BY_LAYER[layer_idx])

        var shift := player_pos * parallax
        var shift_mod := Vector2(
            fposmod(shift.x, STAR_TILE_SIZE.x),
            fposmod(shift.y, STAR_TILE_SIZE.y)
        )

        for oy in [-1, 0, 1]:
            for ox in [-1, 0, 1]:
                var tile_offset := Vector2(float(ox) * STAR_TILE_SIZE.x, float(oy) * STAR_TILE_SIZE.y)
                for s: Vector2 in stars:
                    var screen_pos: Vector2 = s + tile_offset - shift_mod
                    var world_pos: Vector2 = player_pos + screen_pos
                    draw_circle(world_pos, radius, STAR_COLOR)


func _draw_planned_path() -> void:
    # Preview the same constant-rate curving motion the ship will execute when unpausing.
    var steps := 18
    var dt := SIM_DURATION / float(steps)

    var preview_pos := player_pos
    var preview_vel := player_vel
    var preview_speed := planned_player_speed
    var preview_turn_rate: float = 0.0
    if SIM_DURATION > 0.0:
        preview_turn_rate = planned_turn_angle / SIM_DURATION

    var prev := preview_pos
    for i in steps:
        var step_angle := preview_turn_rate * dt
        if step_angle != 0.0:
            preview_vel = preview_vel.rotated(step_angle)
        preview_vel = preview_vel.normalized() * preview_speed
        preview_pos += preview_vel * dt
        draw_line(prev, preview_pos, PLANNED_VECTOR_COLOR, 2.0)
        prev = preview_pos

    planned_end_pos = preview_pos


func _draw_planned_ghost() -> void:
    # Draw a ghost of the player collider at the exact arc endpoint.
    var col := PLAYER_COLOR
    col.a = 0.35
    var end_pos := _arc_endpoint(player_pos, player_vel.normalized(), planned_player_speed, planned_turn_angle)
    _draw_circle_outline(end_pos, PLAYER_RADIUS, col)


func _draw_turn_wedge() -> void:
    # Visualize the true reachable endpoint region using the same circular-arc formula
    # the simulation executes. Outer boundary = max speed, inner = min speed, sides = ±turn_limit.
    var forward_dir := player_vel.normalized()
    if forward_dir == Vector2.ZERO:
        forward_dir = Vector2.UP

    var segments: int = 40
    var col := PLANNED_VECTOR_COLOR
    col.a = 0.25

    # Outer arc: max speed, sweep from -turn_limit to +turn_limit (left to right)
    var outer_pts: Array[Vector2] = []
    for i in range(segments + 1):
        var t := float(i) / float(segments)
        var ang := -turn_limit_this_turn + 2.0 * turn_limit_this_turn * t
        outer_pts.append(_arc_endpoint(player_pos, forward_dir, PLAYER_SPEED_MAX, ang))

    # Inner arc: min speed, sweep from +turn_limit to -turn_limit (right to left, closes shape)
    var inner_pts: Array[Vector2] = []
    for i in range(segments + 1):
        var t := float(i) / float(segments)
        var ang := turn_limit_this_turn - 2.0 * turn_limit_this_turn * t
        inner_pts.append(_arc_endpoint(player_pos, forward_dir, PLAYER_SPEED_MIN, ang))

    for i in range(outer_pts.size() - 1):
        draw_line(outer_pts[i], outer_pts[i + 1], col, 1.0)
    for i in range(inner_pts.size() - 1):
        draw_line(inner_pts[i], inner_pts[i + 1], col, 1.0)

    # Side edges at the two turn extremes
    draw_line(outer_pts[0], inner_pts[inner_pts.size() - 1], col, 1.0)
    draw_line(outer_pts[outer_pts.size() - 1], inner_pts[0], col, 1.0)


func _compute_turn_limit_for_speed(speed: float) -> float:
    if speed == 0.0:
        return MAX_TURN_RADIANS
    var speed_factor: float = clamp(PLAYER_SPEED_DEFAULT / speed, 0.5, 2.0)
    return MAX_TURN_RADIANS * speed_factor
