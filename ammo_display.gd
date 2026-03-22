extends Control

var missiles_remaining: int = 10
var missiles_max: int = 10

func _draw() -> void:
    var dot_radius := 6.0
    var gap := 7.0
    var step := dot_radius * 2.0 + gap
    var total_width := missiles_max * step - gap
    var start_x := (size.x - total_width) * 0.5
    var cy := size.y * 0.5

    for i in missiles_max:
        var cx := start_x + i * step + dot_radius
        var alpha := 1.0 if i < missiles_remaining else 0.22
        var color := Color(1.0, 1.0, 0.4, alpha)
        _draw_missile_glyph(Vector2(cx, cy), dot_radius, color)


func _draw_missile_glyph(center: Vector2, radius: float, color: Color) -> void:
    var points := 16
    var angle_step := TAU / float(points)
    for i in points:
        var a := angle_step * i
        var b := angle_step * (i + 1)
        draw_line(
            center + Vector2(cos(a), sin(a)) * radius,
            center + Vector2(cos(b), sin(b)) * radius,
            color, 1.5
        )
