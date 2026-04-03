extends Node2D
class_name Game

const AggressorAI = preload("res://aggressor_ai.gd")
const OrbiterAI   = preload("res://orbiter_ai.gd")
const FlankerAI   = preload("res://flanker_ai.gd")

enum GamePhase { PLANNING, SIMULATING, ENDED }

const SIM_DURATION := 2.0 # seconds, tweakable
const SIM_WINDUP_REAL := 0.25   # real seconds to ramp up to full speed at sim start
const SIM_WINDDOWN_GAME := 0.25  # game seconds over which to ramp down at sim end
const PLAYER_RADIUS := 16.0
const ENEMY_RADIUS := 16.0
const MISSILE_RADIUS := 8.0

const ENEMY_SPEED := 140.0
const MISSILE_SPEED := 300.0
const SCENE_RADIUS := 1000.0 # missiles/enemies beyond this are considered gone

# ── Physics ─────────────────────────────────────────────────────────────────
const PLAYER_MASS             := 10.0   # tonnes
const ENEMY_MASS              := 8.0    # tonnes
const MAX_PLAYER_THRUST       := 1200.0 # force units — gives ~120 units/s² at base mass
const MAX_ENEMY_THRUST        := 1000.0
const GRAVITY_EMIT_MIN_MASS   := 6.0    # bodies below this mass don't emit gravity

# ── Planning UI ──────────────────────────────────────────────────────────────
# Mouse distance (world units) that maps to MAX_PLAYER_THRUST.
const THRUST_ARROW_MAX_LEN    := 180.0

const PLAYER_COLOR := Color(1.0, 1.0, 1.0)          # white
const ENEMY_COLOR := Color(1.0, 0.4, 0.4)
const MISSILE_COLOR       := Color(1.0, 0.267, 0.267)   # red   #ff4444
const HOMING_COLOR        := Color(0.412, 1.0,  0.490)   # lime  #69ff7d
const MINE_COLOR          := Color(1.0, 0.667, 0.200)    # amber #ffaa33
const SCRAP_COLOR         := Color(0.627, 0.659, 0.690)  # grey  #a0a8b0
const ENEMY_MISSILE_COLOR := Color(1.0, 0.6, 0.2)
const PLANNED_VECTOR_COLOR := Color(0.5, 1.0, 0.5)
const STAR_COLOR := Color(0.85, 0.90, 1.0, 0.45)
const BORDER_COLOR := Color(1.0, 0.0, 0.0, 0.1)

const PLAY_AREA_HALF_EXTENTS := Vector2(975.0, 675.0) # 50% larger
const PLAY_BORDER_THICKNESS := 80.0

const PLAYER_MAX_HP := 5
const ENEMY_MAX_HP := 3
const MISSILE_POWER := 2  # base power for all missiles

const EXPLOSION_RING_DURATION := 0.6
const EXPLOSION_MAX_RADIUS_SHIP := 80.0
const EXPLOSION_MAX_RADIUS_MISSILE := 35.0
const EXPLOSION_BLAST_RADIUS_SHIP := 120.0
const EXPLOSION_BLAST_RADIUS_MISSILE := 60.0
const EXPLOSION_BLAST_FORCE := 300.0
const DEBRIS_SPEED_MIN := 80.0
const DEBRIS_SPEED_MAX := 220.0
const DEBRIS_LIFETIME := 3.0
const DEBRIS_SIZE_SHIP := 7.0
const DEBRIS_SIZE_MISSILE := 4.0
const DEBRIS_COUNT_SHIP := 10
const DEBRIS_COUNT_MISSILE := 4
const DEBRIS_HP_DAMAGE := 1

const PLAYER_MAX_MISSILES := 10
const PLAYER_FIRE_COOLDOWN := 4.0

# ── Homing missile ───────────────────────────────────────────────────────────
const PLAYER_MAX_HOMING      := 5
const PLAYER_HOMING_COOLDOWN := 4.5
const HOMING_TURN_RATE       := 1.2   # radians/sec steering correction

# ── Mine ─────────────────────────────────────────────────────────────────────
const PLAYER_MAX_MINES     := 3
const PLAYER_MINE_COOLDOWN := 2.0
const MINE_RADIUS          := 9.0
const MINE_ARM_TIME        := 1.0   # seconds before proximity trigger activates
const MINE_TRIGGER_RADIUS  := 40.0  # proximity detection radius
const MINE_TRIGGER_DELAY   := 0.2   # seconds after trigger before detonation

const ENEMY_MAX_MISSILES := 6
const ENEMY_FIRE_COOLDOWN := 3.5
const ENEMY_FIRE_ANGLE_THRESHOLD := PI / 4.0  # 45 degrees

const EVASION_DETECT_RADIUS := 80.0   # px — missile proximity triggering evasion
const ARCHETYPE_ROSTER := ["aggressor", "orbiter", "flanker"]

# ── Tractor beam ─────────────────────────────────────────────────────────────
const TRACTOR_RANGE        := 250.0   # search radius (units)
const TRACTOR_SPRING_K     := 0.2     # spring constant for reel-in force
const TRACTOR_DOCKING_DIST := 30.0   # distance at which scrap is absorbed
const TETHER_LENGTH        := 200.0   # max tether length when over-capacity
const PLAYER_CARGO_CAP     := 4.0     # max tonnes that can be absorbed

# ── Scrap ────────────────────────────────────────────────────────────────────
const SCRAP_RADIUS         := 10.0
const SCRAP_MASS_MIN       := 1.0   # tonnes
const SCRAP_MASS_MAX       := 3.0
const SCRAP_SPAWN_COUNT    := 3     # pieces placed at game start
const SCRAP_FROM_EXPLOSION := 2     # pieces per destroyed enemy ship

const STAR_TILE_SIZE := Vector2(900.0, 700.0)
const STAR_LAYER_COUNT := 3
const STAR_COUNTS_BY_LAYER := [120, 90, 60]
const STAR_PARALLAX_BY_LAYER := [0.15, 0.30, 0.55]
const STAR_RADIUS_BY_LAYER := [1.5, 1.2, 1.0]

@onready var camera: Camera2D = $Camera2D
@onready var message_label: Label = $CanvasLayer/MessageLabel
@onready var restart_button: Button = $CanvasLayer/RestartButton
@onready var fire_button: Button = $CanvasLayer/FireButtonContainer/FireButton
@onready var cooldown_fill: ColorRect = $CanvasLayer/FireButtonContainer/FireButton/CooldownFill
@onready var ammo_display: Control = $CanvasLayer/FireButtonContainer/AmmoDisplay

var phase: GamePhase = GamePhase.PLANNING
var sim_time_left: float = 0.0
var sim_real_elapsed: float = 0.0

var player_pos: Vector2 = Vector2.ZERO
var player_vel: Vector2 = Vector2.UP * 80.0    # initial drift velocity
var player_mass: float = PLAYER_MASS
var player_force_acc: Vector2 = Vector2.ZERO
var planned_thrust: Vector2 = Vector2.ZERO     # set each planning phase
var player_alive: bool = true
var player_hp: int = PLAYER_MAX_HP
var player_missiles_remaining: int = PLAYER_MAX_MISSILES
var player_fire_cooldown: float = 0.0
var player_homing_remaining: int   = PLAYER_MAX_HOMING
var player_homing_cooldown:  float = 0.0
var active_weapon: int = 0   # 0 = missile, 1 = homing, 2 = mine
var player_mine_remaining: int   = PLAYER_MAX_MINES
var player_mine_cooldown:  float = 0.0
var mines: Array = []
# mine dict: {pos, vel, arm_timer, trigger_timer, triggered, alive}

var enemies: Array = [] # each: {pos, vel, alive, missiles_remaining, fire_cooldown}
var missiles: Array = [] # each: {pos: Vector2, vel: Vector2, from_player: bool}
var explosions: Array = []  # each: {pos, vel, lifetime, max_lifetime, radius, is_ship}
var debris: Array = []  # each: {pos, vel, angle, angular_vel, lifetime, max_lifetime, size, hp_dealt: bool}
var scrap: Array = []  # each: {pos, vel, mass, force_acc, angle, angular_vel}

# ── Tractor beam state ────────────────────────────────────────────────────────
var tractor_active: bool       = false
var tractor_target: int        = -1    # index into scrap[], -1 = no target
var player_cargo_aboard: float = 0.0

var end_state: StringName = ""
var end_timer: float = 0.0

var _stars_by_layer: Array = [] # each layer: Array[Vector2] positions inside STAR_TILE_SIZE


func _ready() -> void:
    randomize()
    _generate_stars()
    _reset_game()
    restart_button.pressed.connect(_on_restart_pressed)
    fire_button.pressed.connect(_try_fire_player)

    var style := StyleBoxFlat.new()
    style.bg_color = Color(0, 0, 0, 0)
    style.border_width_left = 2
    style.border_width_right = 2
    style.border_width_top = 2
    style.border_width_bottom = 2
    style.border_color = Color(0.3, 0.91, 1.0, 1.0)
    style.corner_radius_top_left = 22
    style.corner_radius_top_right = 22
    style.corner_radius_bottom_left = 22
    style.corner_radius_bottom_right = 22
    fire_button.add_theme_stylebox_override("normal", style)
    fire_button.add_theme_stylebox_override("hover", style)
    fire_button.add_theme_stylebox_override("pressed", style)
    fire_button.add_theme_stylebox_override("disabled", style)
    fire_button.add_theme_color_override("font_color", Color(0.3, 0.91, 1.0))
    fire_button.add_theme_color_override("font_disabled_color", Color(0.3, 0.91, 1.0, 0.3))

    ammo_display.missiles_max = PLAYER_MAX_MISSILES
    ammo_display.missiles_remaining = player_missiles_remaining

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


func _make_ai_state(archetype: String) -> Dictionary:
    match archetype:
        "orbiter": return { "orbit_dir": 1, "evade_timer": 0.0 }
        _:         return {}


func _reset_game() -> void:
    # Initial player setup
    player_pos = Vector2.ZERO
    player_vel       = Vector2.UP * 80.0
    player_mass      = PLAYER_MASS
    player_force_acc = Vector2.ZERO
    planned_thrust   = Vector2.ZERO
    player_alive = true
    player_hp = PLAYER_MAX_HP
    player_missiles_remaining = PLAYER_MAX_MISSILES
    player_fire_cooldown = 0.0
    player_homing_remaining = PLAYER_MAX_HOMING
    player_homing_cooldown  = 0.0
    active_weapon           = 0
    player_mine_remaining = PLAYER_MAX_MINES
    player_mine_cooldown  = 0.0
    mines.clear()

    # Enemy setup — each slot maps to an archetype in ARCHETYPE_ROSTER
    enemies.clear()
    var enemy_spawns := [
        { "pos": Vector2(300.0, 0.0),     "vel": Vector2.LEFT  * ENEMY_SPEED },
        { "pos": Vector2(-250.0, -150.0), "vel": Vector2.RIGHT * ENEMY_SPEED },
        { "pos": Vector2(0.0, 250.0),     "vel": Vector2.UP    * ENEMY_SPEED },
        { "pos": Vector2(-300.0, 200.0),  "vel": Vector2.RIGHT * ENEMY_SPEED },
        { "pos": Vector2(150.0, -280.0),  "vel": Vector2.DOWN  * ENEMY_SPEED },
    ]
    for i in enemy_spawns.size():
        var archetype: String = ARCHETYPE_ROSTER[i % ARCHETYPE_ROSTER.size()]
        enemies.append({
            "pos":                enemy_spawns[i].pos,
            "vel":                enemy_spawns[i].vel,
            "alive":              true,
            "missiles_remaining": ENEMY_MAX_MISSILES,
            "fire_cooldown":      0.0,
            "hp":                 ENEMY_MAX_HP,
            "archetype":          archetype,
            "ai_state":           _make_ai_state(archetype),
            "mass":               ENEMY_MASS,       # ← new
            "force_acc":          Vector2.ZERO,     # ← new
        })

    missiles.clear()
    explosions.clear()
    debris.clear()
    scrap.clear()
    for _i in SCRAP_SPAWN_COUNT:
        var angle: float  = randf() * TAU
        var dist: float   = randf_range(200.0, 500.0)
        var spawn_pos: Vector2 = Vector2(cos(angle), sin(angle)) * dist
        var drift_vel: Vector2 = Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
        _spawn_scrap_piece(spawn_pos, drift_vel)

    tractor_active      = false
    tractor_target      = -1
    player_cargo_aboard = 0.0

    phase = GamePhase.PLANNING
    sim_time_left = 0.0
    end_state = ""
    end_timer = 0.0

    message_label.text = ""
    message_label.visible = false
    restart_button.visible = false

    if is_node_ready():
        $Renderer.queue_redraw()
    if is_node_ready():
        _update_fire_button_ui()


func _process(delta: float) -> void:
    if phase == GamePhase.SIMULATING:
        _step_simulation(delta)
    elif phase == GamePhase.ENDED:
        _step_end_timer(delta)

    camera.position = player_pos
    $Renderer.queue_redraw()
    _update_fire_button_ui()


func _unhandled_input(event: InputEvent) -> void:
    if phase == GamePhase.ENDED:
        return

    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_SPACE:
            _try_fire_player()
        if event.keycode == KEY_T:
            tractor_active = not tractor_active
            if not tractor_active:
                tractor_target = -1
        if event.keycode == KEY_1:
            active_weapon = 0
        elif event.keycode == KEY_2:
            active_weapon = 1
        elif event.keycode == KEY_3:
            active_weapon = 2

    if phase != GamePhase.PLANNING:
        return

    if event is InputEventMouseMotion:
        _update_planned_vector(get_global_mouse_position())

    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if player_alive:
            _start_simulation()


func _start_simulation() -> void:
    phase = GamePhase.SIMULATING
    sim_time_left = SIM_DURATION
    sim_real_elapsed = 0.0
    # planned_thrust was set by _update_planned_vector during planning phase — nothing to commit



func _get_ai(archetype: String) -> GDScript:
    match archetype:
        "aggressor": return AggressorAI
        "orbiter":   return OrbiterAI
        "flanker":   return FlankerAI
    return AggressorAI  # fallback for unknown archetypes


func _step_simulation(delta: float) -> void:
    sim_real_elapsed += delta
    var windup := smoothstep(0.0, SIM_WINDUP_REAL, sim_real_elapsed)
    var winddown := smoothstep(0.0, SIM_WINDDOWN_GAME, sim_time_left)
    var time_scale := maxf(0.1, minf(windup, winddown))
    var game_delta := delta * time_scale

    sim_time_left -= game_delta
    if sim_time_left <= 0.0:
        game_delta += sim_time_left # trim overshoot
        sim_time_left = 0.0

    if game_delta > 0.0:
        # 1. Tick weapon cooldowns (before AI so should_fire sees updated cooldown)
        if player_fire_cooldown > 0.0:
            player_fire_cooldown = maxf(0.0, player_fire_cooldown - game_delta)
        if player_homing_cooldown > 0.0:
            player_homing_cooldown = maxf(0.0, player_homing_cooldown - game_delta)
        if player_mine_cooldown > 0.0:
            player_mine_cooldown = maxf(0.0, player_mine_cooldown - game_delta)
        for enemy in enemies:
            if enemy.alive and enemy.fire_cooldown > 0.0:
                enemy.fire_cooldown = maxf(0.0, enemy.fire_cooldown - game_delta)

        # 2. AI dispatcher — steer, fire, evade (only while player is alive)
        if player_alive:
            for enemy in enemies:
                if not enemy.alive:
                    continue
                var ai := _get_ai(enemy.archetype)

                # Steering — AI returns desired velocity; we convert to thrust
                var desired_vel: Vector2 = ai.steer(enemy, self, game_delta)
                var vel_error: Vector2   = desired_vel - (enemy.vel as Vector2)
                var raw_thrust: Vector2  = vel_error * float(enemy.mass) / maxf(game_delta, 0.001)
                var thrust: Vector2      = raw_thrust.clamped(MAX_ENEMY_THRUST)
                enemy.force_acc = (enemy.force_acc as Vector2) + thrust

                # Firing — archetype decides intent; _try_fire_enemy checks cooldown/ammo
                if ai.should_fire(enemy, self):
                    _try_fire_enemy(enemy)

                # Evasion — only the single nearest player missile within range
                var nearest_missile = null
                var nearest_dist    := EVASION_DETECT_RADIUS
                for missile in missiles:
                    if missile.from_player:
                        var d := (missile.pos as Vector2).distance_to(enemy.pos as Vector2)
                        if d < nearest_dist:
                            nearest_dist    = d
                            nearest_missile = missile
                if nearest_missile != null:
                    var evade_delta: Vector2 = ai.evade_missile(
                        enemy,
                        nearest_missile.pos as Vector2,
                        nearest_missile.vel as Vector2,
                        game_delta
                    )
                    var evade_impulse: Vector2 = evade_delta * float(enemy.mass) / maxf(game_delta, 0.001)
                    enemy.force_acc = (enemy.force_acc as Vector2) + evade_impulse

        # 3. Homing missile steering
        for missile in missiles:
            if not (missile.get("homing", false) as bool):
                continue
            if not (missile.from_player as bool):
                continue
            var nearest_enemy: Dictionary = {}
            var nearest_dist: float       = INF
            for enemy in enemies:
                if not enemy.alive:
                    continue
                var d: float = (missile.pos as Vector2).distance_to(enemy.pos as Vector2)
                if d < nearest_dist:
                    nearest_dist  = d
                    nearest_enemy = enemy
            if nearest_enemy.is_empty():
                continue
            var to_target: Vector2   = ((nearest_enemy.pos as Vector2) - (missile.pos as Vector2)).normalized()
            var current_dir: Vector2 = (missile.vel as Vector2).normalized()
            var new_dir: Vector2     = current_dir.lerp(to_target, HOMING_TURN_RATE * game_delta).normalized()
            missile.vel              = new_dir * MISSILE_SPEED

        # 4. Tractor beam spring / tether (before integration so forces are included)
        _step_tractor_beam(game_delta)

        # 5. Physics integration (uses velocities set by AI dispatcher)
        _integrate_motion(game_delta)
        _handle_collisions()
        _step_explosions(game_delta)
        _step_mines(game_delta)
        _check_leave_play_area()
        _cull_offscreen_objects()

    if _check_end_conditions():
        return

    if sim_time_left <= 0.0 and phase == GamePhase.SIMULATING:
        phase = GamePhase.PLANNING
        # player_vel naturally carries over — no momentum re-initialisation needed


func _step_tractor_beam(delta: float) -> void:
    if not tractor_active or not player_alive:
        return

    # Re-validate target index (scrap array may have changed)
    if tractor_target >= scrap.size():
        tractor_target = -1

    # Search for nearest target if none
    if tractor_target == -1:
        var nearest_dist: float = TRACTOR_RANGE
        var nearest_idx:  int   = -1
        for i: int in scrap.size():
            var d: float = player_pos.distance_to(scrap[i].pos as Vector2)
            if d < nearest_dist:
                nearest_dist = d
                nearest_idx  = i
        tractor_target = nearest_idx
        return  # start pulling next tick

    var piece: Dictionary = scrap[tractor_target]
    var diff: Vector2     = player_pos - (piece.pos as Vector2)
    var dist: float       = diff.length()
    if dist < 1.0:
        return

    var remaining_cap: float = PLAYER_CARGO_CAP - player_cargo_aboard
    var fits: bool           = float(piece.mass) <= remaining_cap + 0.01

    if fits:
        # ── Spring reel-in ───────────────────────────────────────────────────
        var spring_force: Vector2 = diff.normalized() * TRACTOR_SPRING_K * dist
        piece.force_acc = (piece.force_acc as Vector2) + spring_force
        # Reaction force on player (equal and opposite, mass-weighted feel)
        player_force_acc += -spring_force * (float(piece.mass) / player_mass)

        # Absorb when close enough
        if dist <= TRACTOR_DOCKING_DIST:
            player_cargo_aboard += float(piece.mass)
            player_mass         += float(piece.mass)
            scrap.remove_at(tractor_target)
            tractor_target = -1

    else:
        # ── Over-capacity: rigid tether (pendulum constraint) ─────────────────
        if dist > TETHER_LENGTH:
            var penetration: float = dist - TETHER_LENGTH
            var axis: Vector2      = diff.normalized()
            var total_mass: float  = player_mass + float(piece.mass)
            # Position correction split by mass ratio
            player_pos             += axis * penetration * (float(piece.mass) / total_mass)
            piece.pos               = (piece.pos as Vector2) + (-axis) * penetration * (player_mass / total_mass)
            # Remove outward velocity component from both bodies
            var player_outward: float = player_vel.dot(-axis)
            var piece_outward: float  = (piece.vel as Vector2).dot(axis)
            if player_outward < 0.0:
                player_vel -= -axis * player_outward
            if piece_outward < 0.0:
                piece.vel = (piece.vel as Vector2) - axis * piece_outward


func _integrate_motion(delta: float) -> void:
    # ── Gravity accumulation ──────────────────────────────────────────────────
    # Build list of gravity-emitting bodies for pairwise calculation.
    # Only bodies above GRAVITY_EMIT_MIN_MASS emit; all bodies receive.
    var emitters: Array = []
    if player_alive and player_mass >= GRAVITY_EMIT_MIN_MASS:
        emitters.append({
            "pos_ref":  "player",
            "pos":      player_pos,
            "mass":     player_mass,
        })
    for enemy in enemies:
        if enemy.alive and float(enemy.mass) >= GRAVITY_EMIT_MIN_MASS:
            emitters.append({
                "pos_ref": "enemy",
                "enemy":   enemy,
                "pos":     enemy.pos as Vector2,
                "mass":    float(enemy.mass),
            })

    # Apply gravity: each emitter attracts all other bodies
    for emitter in emitters:
        var ep: Vector2 = emitter.pos as Vector2
        var em: float   = float(emitter.mass)

        # → player
        if player_alive and emitter.get("pos_ref") != "player":
            player_force_acc += PhysicsSim.gravity_force(ep, em, player_pos, player_mass)

        # → enemies
        for enemy in enemies:
            if not enemy.alive:
                continue
            if emitter.get("pos_ref") == "enemy" and emitter.get("enemy") == enemy:
                continue  # skip self
            var gf: Vector2 = PhysicsSim.gravity_force(ep, em, enemy.pos as Vector2, float(enemy.mass))
            enemy.force_acc = (enemy.force_acc as Vector2) + gf

        # → scrap (receives gravity, does not emit)
        for piece in scrap:
            var gf: Vector2 = PhysicsSim.gravity_force(ep, em, piece.pos as Vector2, float(piece.mass))
            piece.force_acc = (piece.force_acc as Vector2) + gf

    # ── Player integration ────────────────────────────────────────────────────
    if player_alive:
        player_force_acc += planned_thrust
        var accel: Vector2 = player_force_acc / player_mass
        player_vel    += accel * delta
        player_pos    += player_vel * delta
        player_force_acc = Vector2.ZERO

    # ── Enemy integration ─────────────────────────────────────────────────────
    for enemy in enemies:
        if not enemy.alive:
            continue
        var accel: Vector2 = (enemy.force_acc as Vector2) / float(enemy.mass)
        enemy.vel       = (enemy.vel as Vector2) + accel * delta
        enemy.pos       = (enemy.pos as Vector2) + (enemy.vel as Vector2) * delta
        enemy.force_acc = Vector2.ZERO

    # ── Missiles (no mass — just kinematic) ───────────────────────────────────
    for missile in missiles:
        missile.pos = (missile.pos as Vector2) + (missile.vel as Vector2) * delta

    # ── Scrap integration ─────────────────────────────────────────────────────
    for piece in scrap:
        var accel: Vector2 = (piece.force_acc as Vector2) / float(piece.mass)
        piece.vel       = (piece.vel as Vector2) + accel * delta
        piece.pos       = (piece.pos as Vector2) + (piece.vel as Vector2) * delta
        piece.angle     = float(piece.angle) + float(piece.angular_vel) * delta
        piece.force_acc = Vector2.ZERO


func _handle_collisions() -> void:
    # Missiles vs ships
    for missile in missiles:
        var power: int = missile.get("power", 1) as int
        if missile.from_player:
            for enemy in enemies:
                if enemy.alive and _circles_overlap(missile.pos, MISSILE_RADIUS, enemy.pos, ENEMY_RADIUS):
                    enemy.hp = (enemy.hp as int) - power
                    if (enemy.hp as int) <= 0:
                        enemy.alive = false
                        _spawn_explosion(enemy.pos as Vector2, enemy.vel as Vector2, true)
                    var hit_pos: Vector2 = missile.pos as Vector2
                    _spawn_explosion(hit_pos, missile.vel as Vector2, false)
                    missile.pos.x = SCENE_RADIUS * 2.0
                    break  # one missile hits one target
        else:
            if player_alive and _circles_overlap(missile.pos, MISSILE_RADIUS, player_pos, PLAYER_RADIUS):
                player_hp -= power
                if player_hp <= 0:
                    player_alive = false
                    _spawn_explosion(player_pos, player_vel, true)
                var hit_pos: Vector2 = missile.pos as Vector2
                _spawn_explosion(hit_pos, missile.vel as Vector2, false)
                missile.pos.x = SCENE_RADIUS * 2.0

    # Missile hits on mines — mine detonates instantly
    for mine in mines:
        if not (mine.alive as bool):
            continue
        for missile in missiles:
            if _circles_overlap(missile.pos as Vector2, MISSILE_RADIUS, mine.pos as Vector2, MINE_RADIUS):
                _spawn_explosion(mine.pos as Vector2, mine.vel as Vector2, false)
                _apply_blast_impulse(mine.pos as Vector2, EXPLOSION_BLAST_RADIUS_MISSILE)
                mine.alive    = false
                missile.pos.x = SCENE_RADIUS * 2.0
                break

    # Ramming: damage based on relative speed, minimum 1
    if player_alive:
        for enemy in enemies:
            if not player_alive:
                break  # stop processing once player is dead
            if enemy.alive and _circles_overlap(player_pos, PLAYER_RADIUS, enemy.pos, ENEMY_RADIUS):
                var rel_speed := (player_vel - (enemy.vel as Vector2)).length()
                var ram_damage := maxi(1, int(rel_speed / 100.0))
                player_hp -= ram_damage
                enemy.hp = (enemy.hp as int) - ram_damage
                if player_hp <= 0:
                    player_alive = false
                    _spawn_explosion(player_pos, player_vel, true)
                if (enemy.hp as int) <= 0:
                    enemy.alive = false
                    _spawn_explosion(enemy.pos as Vector2, enemy.vel as Vector2, true)


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

    var live_scrap: Array = []
    for piece in scrap:
        if (piece.pos as Vector2).length() <= SCENE_RADIUS:
            live_scrap.append(piece)
    scrap = live_scrap

    var live_mines_culled: Array = []
    for mine in mines:
        if (mine.pos as Vector2).length() <= SCENE_RADIUS:
            live_mines_culled.append(mine)
    mines = live_mines_culled


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


func _try_fire_enemy(enemy: Dictionary) -> void:
    if enemy.fire_cooldown > 0.0:
        return
    if (enemy.missiles_remaining as int) <= 0:
        return
    var aim_dir := (player_pos - (enemy.pos as Vector2)).normalized()
    if aim_dir == Vector2.ZERO:
        return  # enemy is exactly on player — skip
    var spawn_pos := (enemy.pos as Vector2) + aim_dir * (ENEMY_RADIUS + MISSILE_RADIUS + 2.0)
    missiles.append({
        "pos":         spawn_pos,
        "vel":         aim_dir * MISSILE_SPEED,
        "from_player": false,
        "power":       MISSILE_POWER,
    })
    enemy.missiles_remaining = (enemy.missiles_remaining as int) - 1
    enemy.fire_cooldown      = ENEMY_FIRE_COOLDOWN


func _try_fire_player() -> void:
    if not player_alive:
        return
    match active_weapon:
        0: _fire_missile()
        1: _fire_homing()
        2: _fire_mine()


func _fire_missile() -> void:
    if player_missiles_remaining <= 0 or player_fire_cooldown > 0.0:
        return
    var dir: Vector2       = player_vel.normalized()
    if dir == Vector2.ZERO:
        return
    var spawn_pos: Vector2 = player_pos + dir * (PLAYER_RADIUS + MISSILE_RADIUS + 2.0)
    missiles.append({
        "pos":         spawn_pos,
        "vel":         dir * MISSILE_SPEED,
        "from_player": true,
        "power":       MISSILE_POWER,
        "homing":      false,
    })
    player_missiles_remaining -= 1
    player_fire_cooldown       = PLAYER_FIRE_COOLDOWN


func _fire_homing() -> void:
    if player_homing_remaining <= 0 or player_homing_cooldown > 0.0:
        return
    var dir: Vector2       = player_vel.normalized()
    if dir == Vector2.ZERO:
        return
    var spawn_pos: Vector2 = player_pos + dir * (PLAYER_RADIUS + MISSILE_RADIUS + 2.0)
    missiles.append({
        "pos":         spawn_pos,
        "vel":         dir * MISSILE_SPEED,
        "from_player": true,
        "power":       MISSILE_POWER,
        "homing":      true,
    })
    player_homing_remaining -= 1
    player_homing_cooldown   = PLAYER_HOMING_COOLDOWN


func _fire_mine() -> void:
    if player_mine_remaining <= 0 or player_mine_cooldown > 0.0:
        return
    mines.append({
        "pos":           player_pos,
        "vel":           player_vel,
        "arm_timer":     MINE_ARM_TIME,
        "trigger_timer": 0.0,
        "triggered":     false,
        "alive":         true,
    })
    player_mine_remaining -= 1
    player_mine_cooldown   = PLAYER_MINE_COOLDOWN


func _step_mines(delta: float) -> void:
    var live_mines: Array = []
    for mine in mines:
        if not (mine.alive as bool):
            continue

        # Drift
        mine.pos = (mine.pos as Vector2) + (mine.vel as Vector2) * delta

        # Tick arm timer
        if float(mine.arm_timer) > 0.0:
            mine.arm_timer = maxf(0.0, float(mine.arm_timer) - delta)

        # Tick trigger countdown
        if (mine.triggered as bool):
            mine.trigger_timer = maxf(0.0, float(mine.trigger_timer) - delta)
            if float(mine.trigger_timer) <= 0.0:
                _spawn_explosion(mine.pos as Vector2, mine.vel as Vector2, false)
                _apply_blast_impulse(mine.pos as Vector2, EXPLOSION_BLAST_RADIUS_MISSILE)
                mine.alive = false
                continue

        # Proximity check (only when armed and not yet triggered)
        if float(mine.arm_timer) <= 0.0 and not (mine.triggered as bool):
            var mpos: Vector2    = mine.pos as Vector2
            var proximity_hit: bool  = false

            # Check player
            if player_alive and mpos.distance_to(player_pos) < MINE_TRIGGER_RADIUS:
                proximity_hit = true

            # Check enemies
            if not proximity_hit:
                for enemy in enemies:
                    if (enemy.alive as bool) and mpos.distance_to(enemy.pos as Vector2) < MINE_TRIGGER_RADIUS:
                        proximity_hit = true
                        break

            # Check scrap
            if not proximity_hit:
                for piece in scrap:
                    if mpos.distance_to(piece.pos as Vector2) < MINE_TRIGGER_RADIUS:
                        proximity_hit = true
                        break

            if proximity_hit:
                mine.triggered     = true
                mine.trigger_timer = MINE_TRIGGER_DELAY

        live_mines.append(mine)
    mines = live_mines


func _update_fire_button_ui() -> void:
    var fire_ready := player_fire_cooldown <= 0.0 and player_missiles_remaining > 0 and phase != GamePhase.ENDED

    fire_button.disabled = not fire_ready

    if player_missiles_remaining <= 0:
        fire_button.text = "NO AMMO"
    elif player_fire_cooldown > 0.0:
        fire_button.text = "RELOADING..."
    else:
        fire_button.text = "FIRE"

    # Cooldown fill sweeps left-to-right as cooldown expires (0 = just fired, full = ready)
    var fill_ratio := 1.0 - clampf(player_fire_cooldown / PLAYER_FIRE_COOLDOWN, 0.0, 1.0)
    cooldown_fill.size.x = fire_button.size.x * fill_ratio

    # Fade border to 25% opacity when out of ammo
    var border_alpha := 0.25 if player_missiles_remaining <= 0 else 1.0
    var s := fire_button.get_theme_stylebox("normal") as StyleBoxFlat
    if s:
        s.border_color = Color(0.3, 0.91, 1.0, border_alpha)

    # Ammo dots
    ammo_display.missiles_remaining = player_missiles_remaining
    ammo_display.queue_redraw()


func _update_planned_vector(mouse_world: Vector2) -> void:
    if not player_alive:
        return
    var offset: Vector2 = mouse_world - player_pos
    var raw_len: float  = offset.length()
    if raw_len < 1.0:
        planned_thrust = Vector2.ZERO
        return
    var ratio: float   = minf(raw_len, THRUST_ARROW_MAX_LEN) / THRUST_ARROW_MAX_LEN
    planned_thrust     = offset.normalized() * ratio * MAX_PLAYER_THRUST


func _spawn_scrap_piece(pos: Vector2, vel: Vector2) -> void:
    scrap.append({
        "pos":         pos,
        "vel":         vel,
        "mass":        randf_range(SCRAP_MASS_MIN, SCRAP_MASS_MAX),
        "force_acc":   Vector2.ZERO,
        "angle":       randf() * TAU,
        "angular_vel": randf_range(-1.5, 1.5),
    })


func _spawn_explosion(pos: Vector2, vel: Vector2, is_ship: bool) -> void:
    var max_r := EXPLOSION_MAX_RADIUS_SHIP if is_ship else EXPLOSION_MAX_RADIUS_MISSILE
    explosions.append({
        "pos": pos,
        "vel": vel,
        "lifetime": EXPLOSION_RING_DURATION,
        "max_lifetime": EXPLOSION_RING_DURATION,
        "radius": max_r,
        "is_ship": is_ship,
    })

    var count := DEBRIS_COUNT_SHIP if is_ship else DEBRIS_COUNT_MISSILE
    var size := DEBRIS_SIZE_SHIP if is_ship else DEBRIS_SIZE_MISSILE
    for i in count:
        var angle := randf() * TAU
        var speed := randf_range(DEBRIS_SPEED_MIN, DEBRIS_SPEED_MAX)
        debris.append({
            "pos": pos,
            "vel": vel + Vector2(cos(angle), sin(angle)) * speed,
            "angle": randf() * TAU,
            "angular_vel": randf_range(-3.0, 3.0),
            "lifetime": DEBRIS_LIFETIME * randf_range(0.6, 1.0),
            "max_lifetime": DEBRIS_LIFETIME,
            "size": size,
            "hp_dealt": false,
        })

    if is_ship:
        for _i in SCRAP_FROM_EXPLOSION:
            var scatter_angle: float = randf() * TAU
            var speed: float = randf_range(40.0, 120.0)
            var scatter_vel: Vector2 = vel + Vector2(cos(scatter_angle), sin(scatter_angle)) * speed
            _spawn_scrap_piece(pos + Vector2(cos(scatter_angle), sin(scatter_angle)) * 20.0, scatter_vel)

    var blast_r := EXPLOSION_BLAST_RADIUS_SHIP if is_ship else EXPLOSION_BLAST_RADIUS_MISSILE
    _apply_blast_impulse(pos, blast_r)


func _apply_blast_impulse(blast_pos: Vector2, blast_radius: float) -> void:
    for enemy in enemies:
        if not enemy.alive:
            continue
        var diff: Vector2 = (enemy.pos as Vector2) - blast_pos
        var dist: float = diff.length()
        if dist < blast_radius and dist > 0.1:
            var delta_v: Vector2 = diff.normalized() * EXPLOSION_BLAST_FORCE * (1.0 - dist / blast_radius)
            enemy.force_acc = (enemy.force_acc as Vector2) + delta_v * float(enemy.mass)

    for missile in missiles:
        var diff: Vector2 = (missile.pos as Vector2) - blast_pos
        var dist: float = diff.length()
        if dist < blast_radius and dist > 0.1:
            var force: float = EXPLOSION_BLAST_FORCE * (1.0 - dist / blast_radius)
            missile.vel = (missile.vel as Vector2) + diff.normalized() * force

    if player_alive:
        var diff: Vector2 = player_pos - blast_pos
        var dist: float = diff.length()
        if dist < blast_radius and dist > 0.1:
            var delta_v: Vector2 = diff.normalized() * EXPLOSION_BLAST_FORCE * (1.0 - dist / blast_radius)
            player_force_acc += delta_v * player_mass


func _step_explosions(delta: float) -> void:
    var living_explosions: Array = []
    for explosion in explosions:
        explosion.lifetime -= delta
        explosion.pos = (explosion.pos as Vector2) + (explosion.vel as Vector2) * delta
        if explosion.lifetime > 0.0:
            living_explosions.append(explosion)
    explosions = living_explosions

    # Swap out debris before iterating so _spawn_explosion() calls from chain kills
    # append to a fresh self.debris instead of the array we're processing.
    var processing := debris
    debris = []

    var living_debris: Array = []
    for d in processing:
        d.lifetime -= delta
        d.pos = (d.pos as Vector2) + (d.vel as Vector2) * delta
        d.angle = (d.angle as float) + (d.angular_vel as float) * delta

        if not (d.hp_dealt as bool):
            if player_alive and _circles_overlap(d.pos as Vector2, d.size as float, player_pos, PLAYER_RADIUS):
                player_hp -= DEBRIS_HP_DAMAGE
                if player_hp <= 0:
                    player_alive = false
                    _spawn_explosion(player_pos, player_vel, true)
                d.hp_dealt = true
            else:
                for enemy in enemies:
                    if enemy.alive and _circles_overlap(d.pos as Vector2, d.size as float, enemy.pos as Vector2, ENEMY_RADIUS):
                        enemy.hp = (enemy.hp as int) - DEBRIS_HP_DAMAGE
                        if (enemy.hp as int) <= 0:
                            enemy.alive = false
                            _spawn_explosion(enemy.pos as Vector2, enemy.vel as Vector2, true)
                        d.hp_dealt = true
                        break

        if (d.lifetime as float) > 0.0:
            living_debris.append(d)

    # Merge survivors with any chain-kill debris spawned during this pass
    debris = living_debris + debris


func _circles_overlap(a_pos: Vector2, a_radius: float, b_pos: Vector2, b_radius: float) -> bool:
    var r := a_radius + b_radius
    return a_pos.distance_squared_to(b_pos) <= r * r


func _play_area_rect() -> Rect2:
    return Rect2(-PLAY_AREA_HALF_EXTENTS, PLAY_AREA_HALF_EXTENTS * 2.0)


func _is_inside_play_area(p: Vector2) -> bool:
    return _play_area_rect().has_point(p)


