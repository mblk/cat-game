const std = @import("std");

const vec2 = @import("../engine/math.zig").vec2;

pub fn isClockwisePolygon(points: []const vec2) bool {
    var area: f32 = 0.0;
    const len = points.len;
    if (len < 3) return false; // Kein gültiges Polygon

    for (points, 0..) |p, i| {
        const next = points[(i + 1) % len];
        area += (next.x - p.x) * (next.y + p.y);
    }

    // Negativer Wert bedeutet CW, positiver Wert CCW
    return area > 0;
}

// TODO
// fn isSimplePolygon -> check for intersections etc
