# aggressor_ai.gd
# Charges straight at the player. Fearless — never evades. High pressure up close.

const SPEED      := 140.0  # px/s — slightly slower so flanking is possible
const FIRE_RANGE := 120.0  # px — fires when within this distance
const TURN_RATE  := 1.5    # radians/second — caps turning so players can get behind it

static func steer(enemy: Dictionary, game: Game, game_delta: float) -> Vector2:
	var to_player: Vector2 = game.player_pos - (enemy.pos as Vector2)
	if to_player == Vector2.ZERO:
		return Vector2.ZERO
	var target_dir: Vector2 = to_player.normalized()
	var current_dir: Vector2 = (enemy.vel as Vector2).normalized()
	if current_dir == Vector2.ZERO:
		return target_dir * SPEED
	var angle: float = current_dir.angle_to(target_dir)
	var max_turn: float = TURN_RATE * game_delta
	return current_dir.rotated(clamp(angle, -max_turn, max_turn)) * SPEED

static func should_fire(enemy: Dictionary, game: Game) -> bool:
	return (enemy.pos as Vector2).distance_to(game.player_pos) < FIRE_RANGE

static func evade_missile(_enemy: Dictionary, _missile_pos: Vector2, _missile_vel: Vector2, _game_delta: float) -> Vector2:
	return Vector2.ZERO  # fearless — never evades
