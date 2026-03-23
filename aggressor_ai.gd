# aggressor_ai.gd
# Charges straight at the player. Fearless — never evades. High pressure up close.

const SPEED      := 180.0  # px/s
const FIRE_RANGE := 120.0  # px — fires when within this distance

static func steer(enemy: Dictionary, game: Game, _game_delta: float) -> Vector2:
	var to_player := game.player_pos - (enemy.pos as Vector2)
	# If exactly on player, normalized() returns ZERO — acceptable, they'll collide.
	return to_player.normalized() * SPEED

static func should_fire(enemy: Dictionary, game: Game) -> bool:
	return (enemy.pos as Vector2).distance_to(game.player_pos) < FIRE_RANGE

static func evade_missile(_enemy: Dictionary, _missile_pos: Vector2, _missile_vel: Vector2, _game_delta: float) -> Vector2:
	return Vector2.ZERO  # fearless — never evades
