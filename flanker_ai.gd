# flanker_ai.gd
# Steers to position directly behind the player (opposite to player velocity).
# Only fires when in the blind spot and within range.
# Dodges missiles with a full lateral impulse.

const SPEED          := 160.0  # px/s
const FLANK_DISTANCE := 180.0  # px — how far behind the player to target
const FIRE_ANGLE     := 30.0   # degrees — firing arc when behind player
const FIRE_RANGE     := 200.0  # px — max range to fire (avoids wasting ammo)
const EVADE_STRENGTH := 220.0  # px/s lateral impulse when dodging a missile

static func steer(enemy: Dictionary, game: Game, _game_delta: float) -> Vector2:
	var behind_dir: Vector2
	if game.player_vel.length() > 1.0:
		behind_dir = -game.player_vel.normalized()
	else:
		# Player nearly stopped — approach from the opposite side of current position
		var to_player := game.player_pos - (enemy.pos as Vector2)
		if to_player.length() > 0.001:
			behind_dir = -to_player.normalized()
		else:
			behind_dir = Vector2.UP

	var target_pos := game.player_pos + behind_dir * FLANK_DISTANCE
	var to_target  := target_pos - (enemy.pos as Vector2)
	if to_target.length() < 0.001:
		return Vector2.ZERO
	return to_target.normalized() * SPEED

static func should_fire(enemy: Dictionary, game: Game) -> bool:
	# Can't fire if player velocity is near zero (can't determine "behind")
	if game.player_vel.length() <= 1.0:
		return false

	# Must be close enough to bother firing
	if (enemy.pos as Vector2).distance_to(game.player_pos) > FIRE_RANGE:
		return false

	# Must be positioned in the arc behind the player
	var from_player_to_enemy := ((enemy.pos as Vector2) - game.player_pos).normalized()
	var behind_facing        := -game.player_vel.normalized()
	var dot                  := clamp(from_player_to_enemy.dot(behind_facing), -1.0, 1.0)
	var angle_deg            := rad_to_deg(acos(dot))
	return angle_deg < FIRE_ANGLE

static func evade_missile(enemy: Dictionary, missile_pos: Vector2, missile_vel: Vector2, _game_delta: float) -> Vector2:
	# Full lateral impulse perpendicular to missile velocity, toward the safer side
	var missile_norm := missile_vel.normalized()
	var perp         := Vector2(-missile_norm.y, missile_norm.x)
	var side         := sign(perp.dot((enemy.pos as Vector2) - missile_pos))
	if side == 0.0:
		side = 1.0
	return perp * side * EVADE_STRENGTH
	# steer() will naturally reapproach from the new angle — no extra state needed
