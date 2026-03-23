# vibe-space

A turn-based top-down space shooter built in Godot 4.5 (GDScript).

## Gameplay

The game alternates between two phases:

- **Planning** — aim your ship's movement arc with the mouse, then fire or hold your position.
- **Simulation** — the world plays out for a fixed slice of time, then pauses again.

Destroy all enemy ships to win. One hit kills.

## Controls

| Input | Action |
|-------|--------|
| Mouse | Aim movement arc |
| Left click | Confirm move and start simulation |
| Space | Fire |

## Project structure

| File | Role |
|------|------|
| `game.gd` | All game logic — state, phases, input, simulation, AI |
| `game_renderer.gd` | All rendering — reads game state, never writes it |
| `ammo_display.gd` | Missile-glyph ammo indicator widget |
| `game_world.tscn` | Main scene |

## Development workflow

Tasks and issues are tracked with [beads](https://github.com/yegge/beads) (`bd`). The `docs/superpowers/` directory holds design specs and implementation plans generated during development sessions.
