const std = @import("std");
const rl = @import("raylib");
const consts = @import("consts.zig");
pub var g_mouse_screen: rl.Vector2 = .{ .x = 0, .y = 0 };
pub var g_mouse_world: rl.Vector2 = .{};

pub fn scale_v2(k: f32, p: rl.Vector2) rl.Vector2 {
    return .{ .x = k * p.x, .y = k * p.y };
}

pub fn add_v2(p0: rl.Vector2, p1: rl.Vector2) rl.Vector2 {
    return .{ .x = p0.x + p1.x, .y = p0.y + p1.y };
}

pub fn avg_v2(p0: rl.Vector2, p1: rl.Vector2) rl.Vector2 {
    return .{ .x = 0.5 * (p0.x + p1.x), .y = 0.5 * (p0.y + p1.y) };
}

pub fn sub_v2(p0: rl.Vector2, p1: rl.Vector2) rl.Vector2 {
    return .{ .x = p0.x - p1.x, .y = p0.y - p1.y };
}

pub fn mag2_v2(p: rl.Vector2) f32 {
    return p.x * p.x + p.y * p.y;
}

pub fn mag_v2(p: rl.Vector2) f32 {
    return std.math.sqrt(mag2_v2(p));
}

pub fn dot(p0: rl.Vector2, p1: rl.Vector2) f32 {
    return p0.x * p1.x + p0.y * p1.y;
}

pub fn rotate_point(p: rl.Vector2, theta: f32) rl.Vector2 {
    var c = std.math.cos(theta);
    var s = std.math.sin(theta);

    return .{
        .x = p.x * c - p.y * s,
        .y = p.x * s + p.y * c,
    };
}

pub fn eq_v2(p0: rl.Vector2, p1: rl.Vector2) bool {
    return p0.x == p1.x and p0.y == p1.y;
}

pub fn zero_v2(p: rl.Vector2) bool {
    return eq_v2(p, .{});
}

pub fn norm(p: rl.Vector2) rl.Vector2 {
    var mag = mag_v2(p);
    if (mag == 0) {
        return .{};
    }

    return scale_v2(1.0 / mag, p);
}

pub fn dan_lerp(x0: f32, x1: f32, k: f32) f32 {
    return (x1 + x0 * (k - 1)) / k;
}

pub fn straight_lerp(x0: f32, x1: f32, t: f32) f32 {
    return x1 * t + x0 * (1.0 - t);
}

pub const FrameBufferToScreenInfo = struct {
    mouse_x: i32,
    mouse_y: i32,
    source: rl.Rectangle,
    destination: rl.Rectangle,

    pub fn compute(framebuffer: *rl.Texture) FrameBufferToScreenInfo {
        var rl_screen_width_f = @as(f32, @floatFromInt(rl.GetScreenWidth()));
        var rl_screen_height_f = @as(f32, @floatFromInt(rl.GetScreenHeight()));
        var screen_scale = @min(rl_screen_width_f / consts.screen_width_f, rl_screen_height_f / consts.screen_height_f);

        var source_width = @as(f32, @floatFromInt(framebuffer.width));

        // This minus is needed to avoid flipping the rendering (for some reason)
        var source_height = -@as(f32, @floatFromInt(framebuffer.height));

        var destination = rl.Rectangle{
            .x = (rl_screen_width_f - consts.screen_width_f * screen_scale) * 0.5,
            .y = (rl_screen_height_f - consts.screen_height_f * screen_scale) * 0.5,
            .width = consts.screen_width_f * screen_scale,
            .height = consts.screen_height_f * screen_scale,
        };

        // TODO move this out
        // HAcky we put here as we have the remapping maths
        // Makes the mouse pos a frame out but should be fine right?
        var mouse_screen = rl.GetMousePosition();
        var mouse_x: i32 = @intFromFloat((mouse_screen.x - destination.x) / screen_scale);
        var mouse_y: i32 = @intFromFloat((mouse_screen.y - destination.y) / screen_scale);
        g_mouse_screen.x = @floatFromInt(mouse_x);
        g_mouse_screen.y = @floatFromInt(mouse_y);

        var source = rl.Rectangle{ .x = 0.0, .y = 0.0, .width = source_width, .height = source_height };

        return .{
            .mouse_x = mouse_x,
            .mouse_y = mouse_y,
            .source = source,
            .destination = destination,
        };
    }
};

pub fn draw_broken_line_i(x0: i32, y0: i32, x1: i32, y1: i32, stripe_off_len: f32, stripe_on_len: f32, color: rl.Color) void {
    draw_broken_line(.{ .x = @as(f32, @floatFromInt(x0)), .y = @as(f32, @floatFromInt(y0)) }, .{ .x = @as(f32, @floatFromInt(x1)), .y = @as(f32, @floatFromInt(y1)) }, stripe_off_len, stripe_on_len, color);
}

pub fn draw_broken_line(p0: rl.Vector2, p1: rl.Vector2, stripe_off_len: f32, stripe_on_len: f32, color: rl.Color) void {
    var delta = .{ .x = p1.x - p0.x, .y = p1.y - p0.y };
    var len = mag_v2(delta);
    if (len == 0) {
        // Nothing to do, p0 == p1.
        return;
    }

    var delta_norm = .{ .x = delta.x / len, .y = delta.y / len };
    var p = p0;

    var cum_dist: f32 = 0;

    var reached_dest = false;
    var stripe_on = true;
    while (!reached_dest) {
        if (stripe_on) {
            cum_dist += stripe_on_len;
        } else {
            cum_dist += stripe_off_len;
        }

        if (cum_dist > len) {
            cum_dist = len;
            reached_dest = true;
        }

        var pnext = .{ .x = p0.x + delta_norm.x * cum_dist, .y = p0.y + delta_norm.y * cum_dist };

        if (stripe_on) {
            rl.DrawLineV(p, pnext, color);
        }

        stripe_on = !stripe_on;

        p = pnext;
    }
}

pub fn draw_arrow_f(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: rl.Color, arrow_size: i32) void {
    draw_arrow(@intFromFloat(start_x), @intFromFloat(start_y), @intFromFloat(end_x), @intFromFloat(end_y), col, arrow_size);
}

pub fn draw_arrow(start_x: i32, start_y: i32, end_x: i32, end_y: i32, col: rl.Color, arrow_size: i32) void {
    if (start_x == end_x and start_y == end_y) {
        return;
    }

    rl.DrawLine(start_x, start_y, end_x, end_y, col);

    var dx = end_x - start_x;
    var dy = end_y - start_y;

    var angle = std.math.atan2(f32, @as(f32, @floatFromInt(dy)), @as(f32, @floatFromInt(dx))) + std.math.pi;
    var arrowhead_angle: f32 = std.math.pi * 0.125;

    var l: f32 = @floatFromInt(arrow_size);
    var xx = end_x + @as(i32, @intFromFloat(l * std.math.cos(angle + arrowhead_angle)));
    var yy = end_y + @as(i32, @intFromFloat(l * std.math.sin(angle + arrowhead_angle)));
    rl.DrawLine(end_x, end_y, xx, yy, col);

    xx = end_x + @as(i32, @intFromFloat(l * std.math.cos(angle - arrowhead_angle)));
    yy = end_y + @as(i32, @intFromFloat(l * std.math.sin(angle - arrowhead_angle)));
    rl.DrawLine(end_x, end_y, xx, yy, col);
}
