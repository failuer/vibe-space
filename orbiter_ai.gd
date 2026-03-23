# orbiter_ai.gd
# Circles the player at a target orbit radius. Fires continuously.
# Reverses orbit direction briefly when a player missile gets close.

const SPEED           := 140.0  # px/s
const ORBIT_RADIUS    := 250.0  # px — target distance from player
const RADIAL_STRENGTH := 0.6    # blend: how hard to correct distance vs. circle tangentially
const EVADE_DURATION  := 0.4    # seconds to hold the reversed orbit direction
const EVADE_NUDGE     := 40.0   # px/s immediate lateral impulse when evasion triggers

static func steer(enemy: Dictionary, game: Game, game_delta: float) -> Vector2:
	# Decrement evade timer; flip orbit_dir back when it expires
	if float(enemy.ai_state.evade_timer) > 0.0:
		enemy.ai_state.evade_timer = float(enemy.ai_state.evade_timer) - game_delta
		if float(enemy.ai_state.evade_timer) <= 0.0:
			enemy.ai_state.evade_timer = 0.0
			enemy.ai_state.orbit_dir   = -int(enemy.ai_state.orbit_dir)  # flip back

	var to_player: Vector2 = game.player_pos - (enemy.pos as Vector2)
	var dist: float = to_player.length()
	if dist < 0.001:
		return Vector2.ZERO  # on top of player — avoid zero-vector normalization

	var radial: Vector2 = to_player / dist                                                  # toward player
	var tangent: Vector2 = Vector2(-radial.y, radial.x) * int(enemy.ai_state.orbit_dir)  # perpendicular

	# Blend: push toward orbit radius radially, circle tangentially
	var correction: float = clamp((dist - ORBIT_RADIUS) / ORBIT_RADIUS, -1.0, 1.0)
	var desired: Vector2 = radial * correction * RADIAL_STRENGTH + tangent * (1.0 - RADIAL_STRENGTH)
	if desired.length() < 0.001:
		return tangent * SPEED
	return desired.normalized() * SPEED

static func should_fire(_enemy: Dictionary, _game: Game) -> bool:
	return true  # always wants to fire; _try_fire_enemy rate-limits via fire_cooldown

static func evade_missile(enemy: Dictionary, missile_pos: Vector2, missile_vel: Vector2, _game_delta: float) -> Vector2:
	# Only trigger evasion if not already evading (prevents per-frame jitter)
	if float(enemy.ai_state.evade_timer) <= 0.0:
		enemy.ai_state.orbit_dir   = -int(enemy.ai_state.orbit_dir)  # flip direction
		enemy.ai_state.evade_timer = EVADE_DURATION

	# Small immediate lateral nudge away from missile path
	var missile_norm := missile_vel.normalized()
	var perp         := Vector2(-missile_norm.y, missile_norm.x)
	var side         := sign(perp.dot((enemy.pos as Vector2) - missile_pos))
	if side == 0.0:
		side = float(int(enemy.ai_state.orbit_dir))
	return perp * side * EVADE_NUDGE
