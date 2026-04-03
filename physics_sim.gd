# physics_sim.gd
# Static utility for Newtonian force calculations.
# Owns gravity math only. Integration is done in game.gd.
extends Object
class_name PhysicsSim

# Gameplay-scaled gravitational constant.
# Two 10 t ships 300 px apart feel ~4 units/s² pull — subtle but present.
# Tune freely; higher = more dramatic gravity wells.
const G_SCALED := 40000.0

# Returns the gravitational force vector that body_a exerts ON body_b
# (i.e., directed from b toward a, attracting b toward a).
# Call twice with args swapped to get the equal-and-opposite force on a.
static func gravity_force(pos_a: Vector2, mass_a: float,
                           pos_b: Vector2, mass_b: float) -> Vector2:
    var diff: Vector2 = pos_a - pos_b          # points from b toward a
    var dist_sq: float = diff.length_squared()
    if dist_sq < 100.0:                        # avoid singularity at very close range
        return Vector2.ZERO
    var magnitude: float = G_SCALED * mass_a * mass_b / dist_sq
    return diff.normalized() * magnitude
