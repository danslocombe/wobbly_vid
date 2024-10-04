const std = @import("std");
const rl = @import("raylib");
const consts = @import("consts.zig");
const alloc = @import("alloc.zig");

const utils = @import("utils.zig");
const TAU = std.math.tau;

pub const Oscillator = struct {
    t: f32,
    pos: f32,
    rate: f32,
    amp: f32,
    amp0: f32,

    const Self = @This();

    pub fn new(t0: f32, pos: f32, rate: f32, amp: f32) Self {
        return Self{
            .t = t0,
            .pos = pos,
            .rate = rate,
            .amp = amp,
            .amp0 = amp,
        };
    }

    // Gives result in [-1, 1]
    pub fn sample(self: *Self) f32 {
        return self.amp * std.math.sin(self.t);
    }

    pub fn tick(self: *Self) void {
        self.t += self.rate;
    }

    pub fn update_amp(self: *Self, delta: f32) void {
        self.amp = std.math.clamp((self.amp + delta), 0.0, 1.0);
    }

    //pub fn update_rate(self: *Self, delta : f32) {
    //    self.rate = std.math.clamp(self.rate + 1 * delta, MIN_RATE, BASE_RATE);
    //}

    pub fn slam(self: *Self, force: f32) void {
        self.update_amp(0.02 * force * self.amp); // * self.amp);
        //self.update_rate(-force);

        var move_val = force * 1.0;

        // If you imagine the oscillator tracing a sine wave, we want to
        // "move" the current time of the oscillator towards a trough (-1)
        //
        //                    _ _
        //  |               /     \
        //  |\            /         \
        //  |  |         |           |
        //  -----------------------------------------------
        //  |  |         |
        //  |    \ _ _ /
        //  |
        //          |
        //          target
        //

        // We start by finding the current cycle number we are on and isolating focusing just on that
        var a = std.math.floor((self.t / TAU));
        var b = self.t - TAU * a;

        // b is the local position in the current cycle and b_target will be the local minimum
        // We decide b_target by looking at where we are in the current cycle
        // We either want target_0 or target_1
        //
        //              _|_
        //          | /  |  \
        //          |/   |   \
        //          |    |    |
        //          -----|---------------------------------------
        //   |      |    |     |       |
        //    \_ _ /|    |      \ _ _ /
        //      |   |    |
        //      |   0    |         |
        //      |        |         target_1
        //      target_0 |
        //               |
        //               |
        //     Left of this line we go to target_0
        //     Right of this line we go to target_1

        var b_target: f32 = 0;

        if (b < 0.25 * TAU) {
            b_target = -0.25 * TAU;
        } else {
            b_target = 0.75 * TAU;
        }

        var delta = b_target - b;

        // If the difference between b and b_target is greater than the max move value determined by the force
        // we cap it.
        if (std.math.fabs(delta) > move_val) {
            delta = std.math.sign(delta) * move_val;
        }

        self.t += delta;
    }
};

//#[derive(Clone)]
//pub struct Oscillator
//{
//}
//
//impl Oscillator {
//    pub fn from_def(def: &OscillatorDefinition) -> Self {
//        Self {
//            t0: def.t0,
//            t: def.t0,
//            pos: def.pos,
//            rate: def.rate,
//            amp: def.amp,
//        }
//    }
//
//}
//

const BASE_RATE: f32 = TAU / 180.0;
const MIN_RATE: f32 = BASE_RATE * 0.50;

pub const World = struct {
    seed: u64,
    pos: rl.Vector2,
    base_radius: f32,
    radius_vary: f32,
    oscs: []Oscillator,

    const Self = @This();

    pub fn new_bad_layout(seed: usize, pos: rl.Vector2, base_radius: f32, radius_vary: f32) Self {
        //let mut oscs = Vec::with_capacity(osc_count);

        const osc_count = 8;
        var oscs = alloc.gpa.allocator().alloc(Oscillator, osc_count) catch unreachable;

        const levels = 2;

        for (0..osc_count) |i| {
            // In the compo game we don't really vary the frequency of the osciallators and setup the amplitudes
            // to a regular pattern.
            var amp_num: f32 = @floatFromInt(@mod(i + seed, levels) + 1);
            var amp = amp_num / (4 * levels);
            //std.debug.print("amp: {d}\n", .{amp});
            //0.25
            //0.1875
            // 0.125
            // 0.0625
            var t0: f32 = @floatFromInt(seed * 1235 + i * 100);

            oscs[i] = Oscillator{
                .pos = @as(f32, @floatFromInt(i)) / osc_count,
                .rate = BASE_RATE,
                .amp = amp,
                .t = t0,
                .amp0 = amp,
            };
        }

        return Self{
            .seed = @intCast(seed),
            .pos = pos,
            .oscs = oscs,
            .base_radius = base_radius,
            .radius_vary = radius_vary,
        };
    }

    pub fn new(seed: usize, pos: rl.Vector2, base_radius: f32, radius_vary: f32) Self {
        //let mut oscs = Vec::with_capacity(osc_count);

        const osc_count = 32;
        var oscs = alloc.gpa.allocator().alloc(Oscillator, osc_count) catch unreachable;

        const levels = 4;

        for (0..osc_count) |i| {
            // In the compo game we don't really vary the frequency of the osciallators and setup the amplitudes
            // to a regular pattern.
            var amp_num: f32 = @floatFromInt(@mod(i + seed, levels) + 1);
            var amp = amp_num / (4 * levels);
            //std.debug.print("amp: {d}\n", .{amp});
            //0.25
            //0.1875
            // 0.125
            // 0.0625
            var t0: f32 = @floatFromInt(seed * 1235 + i * 100);

            oscs[i] = Oscillator{
                .pos = @as(f32, @floatFromInt(i)) / osc_count,
                .rate = BASE_RATE,
                .amp = amp,
                .t = t0,
                .amp0 = amp,
            };
        }

        return Self{
            .seed = @intCast(seed),
            .pos = pos,
            .oscs = oscs,
            .base_radius = base_radius,
            .radius_vary = radius_vary,
        };
    }

    pub fn tick(self: *Self) void {
        for (self.oscs) |*osc| {
            osc.tick();
        }
    }

    pub fn pos_on_surface(self: *Self, world_angle: f32, half_height: f32) rl.Vector2 {
        var angle = normalize_angle(world_angle);
        var r = self.sample(angle) + half_height;
        return utils.add_v2(self.pos, .{ .x = std.math.cos(angle) * r, .y = std.math.sin(angle) * r });
    }

    pub fn sample(self: *Self, angle: f32) f32 {
        var pos = normalize_angle(angle) / TAU;
        return self.base_radius + self.radius_vary * self.sample_ld49(pos);
    }

    //// Sample the surface level of a world at a given "world position" or angle represented as a number in [0,1)
    //// The actual radius is then rendered as r_pos = r0 + r_vary * sample(pos)
    ////
    //// Gives result in [-1, 1]
    fn sample_ld49(self: *Self, pos: f32) f32 {

        // For now sample all oscilators using some simple weighting func
        var res: f32 = 0;
        for (self.oscs) |*osc| {
            var dist = min_dist(osc.pos, pos);
            const k = 30;
            var weighting = 1.0 / (1.0 + k * dist);

            if (weighting > 0.0) {
                res += weighting * osc.sample();
            }
        }

        return res;
    }

    pub fn sample_normal(self: *Self, angle: f32) rl.Vector2 {
        const EPSILON: f32 = 0.01 * TAU;
        var derive_sample_0 = self.pos_on_surface(angle - EPSILON * 0.5, 0.0);
        var derive_sample_1 = self.pos_on_surface(angle + EPSILON * 0.5, 0.0);
        var delta = utils.sub_v2(derive_sample_1, derive_sample_0);
        var norm_vector = .{ .x = delta.y, .y = -delta.x };

        return utils.norm(norm_vector);
        //var angle_from_samples = norm_vector.get_angle();

        //let frame = if self.destroyed { 1 } else { 0 };
        //let spr_tree = &draw::get_sprite("tree")[frame];
        //image_data.draw_sprite(spr_tree, p, angle_from_samples + PI * 0.5, V2::new(0.5, 1.0), 1.0);
        //image_data.draw_line(p, p + V2::norm_from_angle(angle_from_samples) * 10.0, draw::RED);
    }

    pub fn slam(self: *Self, force: f32, angle: f32) void {
        var world_angle = normalize_angle(angle);
        var pos = world_angle / TAU;
        self.slam_ld49(force, pos);
    }

    // Simulate an object slamming into the surface
    // Basically we change the value of t of all oscillators close to the impact position.
    fn slam_ld49(self: *Self, force: f32, pos: f32) void {
        for (self.oscs) |*osc| {
            var dist = min_dist(osc.pos, pos);
            if (dist < 0.125) {
                var weighting = 1.0 - 20.0 * dist;
                if (weighting > 0.0) {
                    osc.slam(force * weighting);
                }
            }
        }
    }
};

pub fn normalize_angle(a: f32) f32 {
    // Assume we are no more than one cycle out
    // otherwise change to while loops
    if (a < 0) {
        return a + TAU;
    } else if (a > TAU) {
        return a - TAU;
    } else {
        return a;
    }
}

// The smallest difference between two angles represented as numbers in [0-1)
fn angle_diff(x: f32, y: f32) f32 {
    var diff = y - x;

    if (diff > 0.5) {
        return diff - 1.0;
    } else if (diff < -0.5) {
        return diff + 1.0;
    } else {
        return diff;
    }
}

fn min_dist(x: f32, y: f32) f32 {
    return std.math.fabs(angle_diff(x, y));
}

pub fn get_slam_target(t: f32) f32 {
    const k = 0.02;

    var tt = t * k + 0.5 * TAU;

    var move_val: f32 = 0.8;

    // If you imagine the oscillator tracing a sine wave, we want to
    // "move" the current time of the oscillator towards a trough (-1)
    //
    //                    _ _
    //  |               /     \
    //  |\            /         \
    //  |  |         |           |
    //  -----------------------------------------------
    //  |  |         |
    //  |    \ _ _ /
    //  |
    //          |
    //          target
    //

    // We start by finding the current cycle number we are on and isolating focusing just on that
    var a = std.math.floor(tt / TAU);
    var b = tt - TAU * a;

    // b is the local position in the current cycle and b_target will be the local minimum
    // We decide b_target by looking at where we are in the current cycle
    // We either want target_0 or target_1
    //
    //              _|_
    //          | /  |  \
    //          |/   |   \
    //          |    |    |
    //          -----|---------------------------------------
    //   |      |    |     |       |
    //    \_ _ /|    |      \ _ _ /
    //      |   |    |
    //      |   0    |         |
    //      |        |         target_1
    //      target_0 |
    //               |
    //               |
    //     Left of this line we go to target_0
    //     Right of this line we go to target_1

    std.debug.print("a: {d:.2}, b: {d:.2} ({d:.2}tau)\n", .{ a, b, b / TAU });
    var b_target: f32 = 0.0;
    if (b < 0.25 * TAU) {
        std.debug.print("CASE A\n", .{});
        b_target = -0.25 * TAU;
    } else {
        std.debug.print("CASE B\n", .{});
        b_target = 0.75 * TAU;
    }

    var delta = b_target - b;

    std.debug.print("delta: {d:.2} ({d:.2}tau)\n", .{ delta, delta / TAU });

    // If the difference between b and b_target is greater than the max move value determined by the force
    // we cap it.
    if (std.math.fabs(delta) > move_val) {
        delta = std.math.sign(delta) * move_val;
    }

    std.debug.print("realised delta: {d:.2} ({d:.2}tau)\n", .{ delta, delta / TAU });

    var target = tt + delta;
    return (target - 0.5 * TAU) / k;
}
