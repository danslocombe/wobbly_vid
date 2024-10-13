const std = @import("std");
const rl = @import("raylib");

const consts = @import("consts.zig");
const alloc = @import("alloc.zig");

const utils = @import("utils.zig");

const fonts = @import("fonts.zig");
const sprites = @import("sprites.zig");
const FroggyRand = @import("froggy_rand.zig").FroggyRand;
const Styling = @import("adlib.zig").Styling;
const world = @import("world.zig");

pub const perlin_yscale_base_octaves = consts.screen_height_f * 0.105;

pub const Perlin = struct {
    points: []const f32 = &[_]f32{ 0.0, 0.5, -1.0, 0.75, 0.6, 0.2 },

    pub fn sample(self: *Perlin, t: f32) f32 {
        var t_big = t * @as(f32, @floatFromInt(self.points.len - 1));
        var before_f = std.math.floor(t_big);
        var after_f = std.math.ceil(t_big);
        var before_i: usize = @intFromFloat(before_f);
        var after_i: usize = @intFromFloat(after_f);
        if (after_i >= self.points.len) {
            after_i = self.points.len - 1;
        }

        var frac = t_big - before_f;
        //return utils.straight_lerp(self.points[before_i], self.points[after_i], frac);
        return utils.cosine_interp(self.points[before_i], self.points[after_i], frac);
        //return self.points[before_i];
    }
};

pub const AnimatedPerlin = struct {
    t: i32 = 0,

    perlin: Perlin = .{},

    y0: f32 = consts.screen_height_f * 0.5,
    yscale: f32 = consts.screen_height_f * 0.25,

    point_popin_inc: i32 = 20,
    interp_popin_base: i32 = 150,
    interp_popin_inc: i32 = 1,

    point_col: rl.Color = consts.pico_sea,

    pub fn tick(self: *AnimatedPerlin) void {
        self.t += 1;
    }

    pub fn draw_axis(self: *AnimatedPerlin, t_n: f32) void {
        var border_x = consts.screen_width_f * 0.2;
        var line_end_n = @min(1.0, t_n);
        var line_end = border_x + (consts.screen_width_f - (border_x * 2.0)) * line_end_n;
        rl.DrawLineV(.{ .x = border_x, .y = self.y0 }, .{ .x = line_end, .y = self.y0 }, consts.pico_blue);
    }

    pub fn draw_points(self: *AnimatedPerlin, t: i32, r_mult: f32) void {
        var border_x = consts.screen_width_f * 0.2;
        for (self.perlin.points, 0..) |val, i| {
            var popin_time = @as(i32, @intCast(i)) * self.point_popin_inc;
            if (t < popin_time) {
                break;
            }

            var time_since_popin = t - @as(i32, @intCast(popin_time));
            var tt = @as(f32, @floatFromInt(time_since_popin)) / 30.0;

            var r = @max(3, 5 * std.math.sqrt(tt) * 1.0 / (0.1 + tt)) * r_mult;

            var i_n = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.perlin.points.len - 1));
            var px = border_x + (consts.screen_width_f - (border_x * 2.0)) * i_n;
            var py = self.y0 + val * self.yscale;

            //rl.DrawLineV(.{ .x = px, .y = consts.screen_height_f * 0.5 }, .{ .x = px, .y = py }, consts.pico_blue);
            rl.DrawLineV(.{ .x = px, .y = self.y0 + 2 }, .{ .x = px, .y = self.y0 - 2 }, consts.pico_blue);
            rl.DrawCircleLines(@intFromFloat(std.math.round(px)), @intFromFloat(std.math.round(py)), r, self.point_col);
        }
    }

    pub fn draw_line(self: *AnimatedPerlin, t: i32, col: rl.Color, broken: bool) void {
        var border_x = consts.screen_width_f * 0.2;
        var border_x_r = consts.screen_width_f * 0.8;
        var x0: i32 = @intFromFloat(border_x);
        var x1: i32 = @intFromFloat(border_x_r);
        var i = x0;
        var prev: f32 = 0.0;
        while (i < x1) {
            var popin_time = self.interp_popin_base + @as(i32, @intCast(i)) * self.interp_popin_inc;
            if (t < popin_time) {
                break;
            }

            var x0_f: f32 = @floatFromInt(x0);
            var x1_f: f32 = @floatFromInt(x1);
            var i_n = (@as(f32, @floatFromInt(i)) - x0_f) / (x1_f - x0_f);
            var sample = self.perlin.sample(i_n);
            var py = self.y0 + sample * self.yscale;
            //rl.DrawPixel(i, @intFromFloat(py), consts.pico_blue);
            if (i > x0) {
                if (broken) {
                    if (@mod(i, 2) == 0) {
                        utils.draw_broken_line_i(i - 1, @intFromFloat(prev), i, @intFromFloat(py), 1.0, 1.0, col);
                    }
                } else {
                    rl.DrawLine(i - 1, @intFromFloat(prev), i, @intFromFloat(py), col);
                }
            }
            i += 1;
            prev = py;
        }
    }

    pub fn draw(self: *AnimatedPerlin) void {
        // Draw line
        self.draw_axis(@as(f32, @floatFromInt(self.t)) / @as(f32, @floatFromInt((self.perlin.points.len - 1) * @as(usize, @intCast(self.point_popin_inc)))));

        self.draw_points(self.t, 1);
        self.draw_line(self.t, consts.pico_blue, false);
    }

    pub fn draw_merged(self: *AnimatedPerlin, others: []*AnimatedPerlin, t_merge: f32) void {
        self.draw_axis(1.0);

        self.draw_points(1000, 0.5);
        for (others) |other| {
            other.draw_points(1000, 0.5);
        }

        self.draw_line(1000, self.point_col, true);
        for (others) |other| {
            other.draw_line(1000, other.point_col, true);
        }

        var border_x = consts.screen_width_f * 0.2;
        var border_x_r = consts.screen_width_f * 0.8;
        var x0: i32 = @intFromFloat(border_x);
        var x1: i32 = @intFromFloat(border_x_r);
        var i = x0;
        var prev: f32 = 0.0;
        while (i < x1) {
            var x0_f: f32 = @floatFromInt(x0);
            var x1_f: f32 = @floatFromInt(x1);
            var i_n = (@as(f32, @floatFromInt(i)) - x0_f) / (x1_f - x0_f);

            if (t_merge < i_n) {
                break;
            }

            var sample = self.perlin.sample(i_n);
            for (others) |other| {
                var other_sample = other.perlin.sample(i_n);
                sample += other_sample;
            }
            var py = self.y0 + sample * self.yscale;
            //rl.DrawPixel(i, @intFromFloat(py), consts.pico_blue);
            if (i > x0) {
                rl.DrawLine(i - 1, @intFromFloat(prev), i, @intFromFloat(py), consts.pico_blue);
            }

            i += 1;
            prev = py;
        }
    }
};

pub fn draw_generator(theta: f32, r: f32, r_big: f32, col: rl.Color) void {
    draw_generator_ext(theta, r, r_big, col, 0);
}

pub fn draw_generator_ext(theta: f32, r: f32, r_big: f32, col: rl.Color, xoff: f32) void {
    var cx = consts.screen_width_f * 0.3;
    var cy = consts.screen_height_f * 0.5;
    rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), r, col);

    var px = cx + r * std.math.cos(theta);
    var py = cy + r * std.math.sin(theta);
    var arrow_size = 4 + 6 * r / r_big;
    utils.draw_arrow_f(cx, cy, px, py, col, @intFromFloat(arrow_size));

    var p = .{ .x = px, .y = py };
    var p_dotted_end = p;
    p_dotted_end.x = cx + r_big * 1.5 + xoff;
    utils.draw_broken_line(p, p_dotted_end, 2.0, 2.0, col);

    var x0: i32 = @intFromFloat(p_dotted_end.x);
    var x_end: i32 = @intFromFloat(consts.screen_width_f * 0.85);

    var x = x0;
    var prev_y: f32 = 0;
    var angle = theta;
    while (x < x_end) {
        angle -= 0.02;
        var y = cy + std.math.sin(angle) * r;

        if (x != x0) {
            rl.DrawLine(x - 1, @intFromFloat(prev_y), x, @intFromFloat(y), col);
        }

        x += 1;
        prev_y = y;
    }
}

pub const CircularMappingPerlin = struct {
    landscapes: []Landscape,

    pub fn draw(self: *CircularMappingPerlin, circle_t: f32) void {
        var theta = circle_t * 3.141;
        if (theta < 0.01) {
            // Dont want to divide by zero
            theta = 0.01;
            //return;
        }

        var arc_len = consts.screen_width_f * 0.3 + consts.screen_width_f * circle_t * 0.2;
        var radius = arc_len / theta;
        //var radius: f32 = 100;

        //fonts.g_linssen.draw_text(0, std.fmt.allocPrintZ(alloc.temp_alloc.allocator(), "Angle {d}", .{theta}) catch unreachable, 10, 10, consts.pico_blue);

        const n = 256;
        var samples = alloc.temp_alloc.allocator().alloc(f32, n) catch unreachable;

        var prev: rl.Vector2 = .{ .x = 0, .y = 0 };
        var prev_midline: rl.Vector2 = .{ .x = 0, .y = 0 };

        var cx = consts.screen_width_f * 0.5; // - radius;
        var cy = consts.screen_height_f * 0.4 + radius - consts.screen_width_f * circle_t * 0.12;

        //for ((n / 2)..n) |i| {
        //var i_n = 2.0 * (@as(f32, @floatFromInt(i)) / n - 0.5);
        var gen0 = self.landscapes[0].get_generators();
        var gen1 = self.landscapes[1].get_generators();
        var gen2 = self.landscapes[2].get_generators();

        for (0..n) |i| {
            var i_n = @as(f32, @floatFromInt(i)) / n;

            var i_sample = 0.5 + i_n * 0.5;
            var sample: f32 = 0;
            sample += self.landscapes[0].sample_with_generators(gen0, i_sample);
            sample += self.landscapes[1].sample_with_generators(gen1, i_sample);
            sample += self.landscapes[2].sample_with_generators(gen2, i_sample);

            samples[i] = sample;

            var angle = i_n * theta;

            const pi_by_two = 3.141 * 0.5;
            var xoff = std.math.cos(angle - pi_by_two) * radius;
            var yoff = std.math.sin(angle - pi_by_two) * radius;
            var pos_x = cx + xoff;
            var pos_y = cy + yoff;
            var pos0: rl.Vector2 = .{ .x = pos_x, .y = pos_y };

            var normal = utils.norm(.{ .x = xoff, .y = yoff });

            var pos = utils.add_v2(pos0, utils.scale_v2(3 * sample, normal));
            var pos_midline = pos0;
            //rl.DrawLineV(pos, utils.sub_v2(pos0, .{ .x = xoff, .y = yoff }), consts.pico_red);

            if (i != 0) {
                // Draw
                rl.DrawLineV(prev, pos, consts.pico_blue);

                if (@mod(i, 4) == 0) {
                    utils.draw_broken_line(prev_midline, pos_midline, 1.0, 1.0, consts.pico_blue);
                }
            }

            prev = pos;
            prev_midline = pos_midline;
        }

        for (0..n) |i| {
            var i_n = @as(f32, @floatFromInt(i)) / n;

            var i_sample = 0.5 - i_n * 0.5;
            var sample: f32 = 0;
            sample += self.landscapes[0].sample_with_generators(gen0, i_sample);
            sample += self.landscapes[1].sample_with_generators(gen1, i_sample);
            sample += self.landscapes[2].sample_with_generators(gen2, i_sample);

            samples[i] = sample;

            var angle = i_n * theta;

            const pi_by_two = 3.141 * 0.5;
            var xoff = std.math.cos(-angle - pi_by_two) * radius;
            var yoff = std.math.sin(-angle - pi_by_two) * radius;
            var pos_x = cx + xoff;
            var pos_y = cy + yoff;
            var pos0: rl.Vector2 = .{ .x = pos_x, .y = pos_y };

            var normal = utils.norm(.{ .x = xoff, .y = yoff });

            var pos = utils.add_v2(pos0, utils.scale_v2(3 * sample, normal));
            var pos_midline = pos0;

            //rl.DrawLineV(pos, utils.sub_v2(pos0, .{ .x = xoff, .y = yoff }), consts.pico_red);

            if (i != 0) {
                // Draw
                rl.DrawLineV(prev, pos, consts.pico_blue);

                if (@mod(i, 4) == 0) {
                    utils.draw_broken_line(prev_midline, pos_midline, 1.0, 1.0, consts.pico_blue);
                }
            }

            prev = pos;
            prev_midline = pos_midline;
        }
    }
};

pub fn make_three_perlins() [3]AnimatedPerlin {
    var rand = FroggyRand.init(0);
    var perlins: [3]AnimatedPerlin = undefined;
    perlins[0] = .{};
    var pps = alloc.gpa.allocator().alloc(f32, 3) catch unreachable;
    pps[0] = 0.6;
    pps[1] = -1;
    pps[2] = 0.8;
    //for (0..3) |i| {
    //pps[i] = rand.gen_f32_one_minus_one(.{ 0, i });
    //}
    perlins[0].perlin.points = pps;
    perlins[0].y0 = consts.screen_height_f * 0.2;
    perlins[0].yscale = perlin_yscale_base_octaves;
    perlins[0].point_col = consts.pico_red;

    perlins[1] = .{};
    pps = alloc.gpa.allocator().alloc(f32, 5) catch unreachable;
    for (0..5) |i| {
        pps[i] = rand.gen_f32_one_minus_one(.{ 3, i }) * 0.5;
    }
    perlins[1].perlin.points = pps;
    perlins[1].yscale = perlin_yscale_base_octaves;

    perlins[2] = .{};
    pps = alloc.gpa.allocator().alloc(f32, 9) catch unreachable;
    for (0..9) |i| {
        pps[i] = rand.gen_f32_one_minus_one(.{ 2, i }) * 0.25;
    }
    perlins[2].perlin.points = pps;
    perlins[2].y0 = consts.screen_height_f * 0.8;
    perlins[2].yscale = perlin_yscale_base_octaves;
    perlins[2].point_col = consts.pico_green;

    return perlins;
}

pub const Landscape = struct {
    t: f32 = 0,
    offsets: []const f32 = &.{ 0.0, 0.25 * 3.141, 0.55 * 3.141 },
    y0: f32 = consts.screen_height_f * 0.5,

    point_col: rl.Color = consts.pico_sea,
    r: f32 = 12,

    draw_circles: bool = true,

    pub fn tick(self: *Landscape) void {
        self.t += 0.02;
    }

    pub fn draw(self: *Landscape) void {
        const arrow_size = 5;

        var generators: []rl.Vector2 = alloc.temp_alloc.allocator().alloc(rl.Vector2, self.offsets.len) catch unreachable;

        const border_x = consts.screen_width_f * 0.3;
        const cx0 = border_x;
        const ww = consts.screen_width_f - (2 * border_x);

        var cy = self.y0;
        var tt = self.t;
        var r = self.r;

        rl.DrawLineV(.{ .x = cx0, .y = cy }, .{ .x = cx0 + ww, .y = cy }, consts.pico_blue);

        for (self.offsets, 0..) |offset, i| {
            var i_n = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.offsets.len - 1));
            var cx = border_x + ww * i_n;

            var t = tt + offset;
            if (self.draw_circles) {
                rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), r, consts.pico_blue);
            }
            var a_x = cx + std.math.cos(t) * r;
            var a_y = cy + std.math.sin(t) * r;
            utils.draw_arrow_f(cx, cy, a_x, a_y, self.point_col, arrow_size);
            var x_norm = (cx - cx0) / ww;
            generators[i] = .{ .x = x_norm, .y = std.math.sin(t) };
        }

        //cx = consts.screen_width_f * 0.5;
        //var t1 = tt + 0.2 * 3.141;
        //rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), r, consts.pico_blue);
        //var a1_x = cx + std.math.cos(t1) * r;
        //var a1_y = cy + std.math.sin(t1) * r;
        //utils.draw_arrow_f(cx, cy, a1_x, a1_y, consts.pico_sea, arrow_size);
        ////utils.draw_broken_line(.{ .x = a1_x, .y = a1_y }, .{ .x = cx, .y = a1_y }, 1.0, 1.0, consts.pico_blue);
        //x_norm = (cx - cx0) / ww;
        //generators[1] = .{ .x = x_norm, .y = std.math.sin(t1) };

        //cx = consts.screen_width_f * 0.7;
        //var t2 = tt + 0.8 * 3.141;
        //rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), r, consts.pico_blue);
        //var a2_x = cx + std.math.cos(t2) * r;
        //var a2_y = cy + std.math.sin(t2) * r;
        //utils.draw_arrow_f(cx, cy, a2_x, a2_y, consts.pico_sea, arrow_size);
        ////utils.draw_broken_line(.{ .x = a2_x, .y = a2_y }, .{ .x = cx, .y = a2_y }, 1.0, 1.0, consts.pico_blue);
        //x_norm = (cx - cx0) / ww;
        //generators[2] = .{ .x = x_norm, .y = std.math.sin(t2) };

        //var x_end: i32 = @intFromFloat(consts.screen_width_f * 0.7);
        //var x: i32 = cx0;

        var a0_x = border_x + std.math.cos(tt + self.offsets[0]) * r;
        var alast_x = border_x + ww + std.math.cos(tt + self.offsets[self.offsets.len - 1]) * r;

        var x0: i32 = @intFromFloat(a0_x);
        var x: i32 = x0;
        var x_end: i32 = @intFromFloat(alast_x);
        var prev_y: f32 = 0;

        while (x < x_end) {
            var x_n = (@as(f32, @floatFromInt(x)) - cx0) / ww;
            var y = cy + self.sample_with_generators(generators, x_n) * r;

            if (x != x0) {
                if (!self.draw_circles) {
                    // Draw dotted
                    if (@mod(x, 2) == 0) {
                        // Do nothing
                    } else {
                        utils.draw_broken_line_i(x - 1, @intFromFloat(prev_y), x, @intFromFloat(y), 1.0, 1.0, self.point_col);
                    }
                } else {
                    rl.DrawLine(x - 1, @intFromFloat(prev_y), x, @intFromFloat(y), self.point_col);
                }
            }

            prev_y = y;
            x += 1;
        }
    }

    pub fn sample_with_generators(self: *Landscape, generators: []const rl.Vector2, t: f32) f32 {
        _ = self;
        return interp_sample_closest(std.math.clamp(t, 0.0, 1.0), generators);
    }

    pub fn get_generators(self: *Landscape) []const rl.Vector2 {
        // @Cleanup ugh
        var generators: []rl.Vector2 = alloc.temp_alloc.allocator().alloc(rl.Vector2, self.offsets.len) catch unreachable;

        const border_x = consts.screen_width_f * 0.3;
        const cx0 = border_x;
        const ww = consts.screen_width_f - (2 * border_x);

        var tt = self.t;

        for (self.offsets, 0..) |offset, i| {
            var i_n = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.offsets.len - 1));
            var cx = border_x + ww * i_n;
            var t = tt + offset;
            var x_norm = (cx - cx0) / ww;
            generators[i] = .{ .x = x_norm, .y = std.math.sin(t) };
        }

        return generators;
    }

    pub fn draw_merged(self: *Landscape, others: []*Landscape) void {
        var border_x = consts.screen_width_f * 0.3;
        var border_x_r = consts.screen_width_f * 0.7;
        var x0: i32 = @intFromFloat(border_x);
        var x1: i32 = @intFromFloat(border_x_r);
        var i = x0;
        var prev: f32 = 0.0;

        var self_generators = self.get_generators();
        var other_generators = alloc.temp_alloc.allocator().alloc([]const rl.Vector2, others.len) catch unreachable;
        for (others, 0..) |other, ii| {
            other_generators[ii] = other.get_generators();
        }

        while (i < x1) {
            var x0_f: f32 = @floatFromInt(x0);
            var x1_f: f32 = @floatFromInt(x1);
            var t = (@as(f32, @floatFromInt(i)) - x0_f) / (x1_f - x0_f);

            //if (t_merge < i_n) {
            //break;
            //}

            var sample = self.sample_with_generators(self_generators, t) * self.r;
            for (others, 0..) |other, ii| {
                var other_sample = other.sample_with_generators(other_generators[ii], t) * other.r;
                sample += other_sample;
            }

            var py = self.y0 + sample;

            //rl.DrawPixel(i, @intFromFloat(py), consts.pico_blue);
            if (i > x0) {
                rl.DrawLine(i - 1, @intFromFloat(prev), i, @intFromFloat(py), consts.pico_blue);
            }

            i += 1;
            prev = py;
        }
    }
};

pub fn interp_sample_closest(x: f32, generators: []const rl.Vector2) f32 {
    // Assume generators are increasing
    var i: usize = 0;

    while (i < generators.len) {
        if (generators[i].x >= x) {
            break;
        }

        i += 1;
    }

    if (i >= generators.len) {
        i = generators.len - 1;
    }

    var prev = i -| 1;

    if (prev == i) {
        return generators[i].y;
    }

    var x_next: f32 = generators[i].x;
    var x_before: f32 = generators[prev].x;

    var frac = (x - x_before) / (x_next - x_before);
    //return utils.straight_lerp(generators[prev].y, generators[i].y, frac);
    return utils.cosine_interp(generators[prev].y, generators[i].y, frac);
}
