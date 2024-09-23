const std = @import("std");
const rl = @import("raylib");

const consts = @import("consts.zig");
const alloc = @import("alloc.zig");

const utils = @import("utils.zig");

const FroggyRand = @import("froggy_rand.zig").FroggyRand;

pub const ground_y = 150;

const camera_min_x = -100;
const camera_max_x = 500;
const camera_min_y = -100;
const camera_max_y = 500;

pub var g_draw_wireframe = false;
pub var g_shader_noise_dump: f32 = 0.0;

pub var particle_frames: []rl.Texture = &.{};

pub const Game = struct {
    t: i32 = 0,

    camera_x: f32 = 0,
    camera_y: f32 = 0,
    camera_zoom: f32 = 1,
    screenshake_t: f32 = 0,

    particles: std.ArrayList(Particle),
    // Bitmap denoting which particles in the array are empty or "dead"
    // This can be used to allocate new particles into and should be skipped over for
    // ticking and drawing.
    particles_dead: std.bit_set.DynamicBitSet,

    scene_1: ScenePerlin1d,

    pub fn init() Game {
        var rand = FroggyRand.init(0);
        _ = rand;

        var scene = ScenePerlin1d{
            .state = ScenePerlin1DState{
                .Intro = .{ .t = 0 },
            },
        };

        return Game{
            .scene_1 = scene,
            .particles = std.ArrayList(Particle).init(alloc.gpa.allocator()),
            .particles_dead = std.bit_set.DynamicBitSet.initEmpty(alloc.gpa.allocator(), 4) catch unreachable,
        };
    }

    pub fn tick(self: *Game) void {
        self.t += 1;

        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_R)) {
            // TODO resett
        }

        self.scene_1.tick();

        // Update camera
        {
            //var camer
            //var target_camera_x = self.player.pos.x - consts.screen_width_f * 0.5;
            //var target_camera_y = self.player.pos.y - consts.screen_height_f * 0.5;
            const target_camera_x = 0.0;
            const target_camera_y = 0.0;
            //var k = 1500 / (1 + dt);
            //var k = 100 * dt_norm;
            const k = 100;
            self.camera_x = utils.dan_lerp(self.camera_x, target_camera_x, k);
            self.camera_y = utils.dan_lerp(self.camera_y, target_camera_y, k);

            self.camera_x = std.math.clamp(self.camera_x, camera_min_x, camera_max_x);
            self.camera_y = std.math.clamp(self.camera_y, camera_min_y, camera_max_y);

            //var player_speed_2 = self.player.vel.x * self.player.vel.x + self.player.vel.y * self.player.vel.y;
            //var player_speed = std.math.sqrt(player_speed_2);
            //var target_camera_zoom = 1 / (1 + player_speed * 0.02);
            //_ = target_camera_zoom;
            //self.camera_zoom = dan_lerp(self.camera_zoom, target_camera_zoom, 40);

            self.screenshake_t -= 1;
        }
    }

    pub fn draw(self: *Game, mapping: *utils.FrameBufferToScreenInfo) void {
        _ = mapping;
        var camera = rl.Camera2D{
            .target = rl.Vector2{ .x = self.camera_x + consts.screen_width_f * 0.5, .y = self.camera_y + consts.screen_height_f * 0.5 },
            .offset = rl.Vector2{ .x = consts.screen_width_f * 0.5, .y = consts.screen_height_f * 0.5 },
            .rotation = 0,
            .zoom = self.camera_zoom,
        };

        if (self.screenshake_t > 1) {
            var rand = FroggyRand.init(@as(u32, @intCast(self.t)));
            var angle = @as(f32, @floatFromInt(rand.gen_i32_range(.{}, 0, 1000))) / 1000.0 * 3.141 * 2.0;
            const r = self.screenshake_t * 0.5;
            var dx = r * std.math.cos(angle);
            var dy = r * std.math.sin(angle);
            camera.target.x += dx;
            camera.target.y += dy;
        }

        camera.Begin();
        rl.ClearBackground(consts.pico_white);

        self.scene_1.draw();

        //for (0..50) |i| {
        //    for (0..50) |j| {
        //        const w = 25;
        //        var color = consts.pico_sea;
        //        var a = ((i % 2) == 0);
        //        var b = ((j % 2) == 0);
        //        // No xor :(
        //        if ((a or b) and !(a and b)) {
        //            color = consts.pico_white;
        //        }

        //        rl.DrawRectangle(@as(i32, @intCast(i)) * w, @as(i32, @intCast(j)) * w, w, w, color);
        //    }
        //}

        //rl.DrawRectangle(camera_min_x, ground_y, camera_max_x + 500 - camera_min_x, camera_max_y + 200 - ground_y, consts.pico_black);

        for (self.particles.items, 0..) |*p, i| {
            if (self.particles_dead.isSet(i)) {
                continue;
            }

            p.draw();
        }

        camera.End();
    }

    pub fn create_particle(self: *Game, p_pos: rl.Vector2, n: usize, offset: f32) void {
        var rand = FroggyRand.init(0);

        for (0..n) |i| {
            var pos = p_pos;
            var theta = rand.gen_f32_uniform(.{ self.t, i }) * 3.141 * 2.0;
            var ox = offset * std.math.cos(theta);
            var oy = offset * std.math.sin(theta);
            pos.x += ox;
            pos.y += oy;

            var frame = rand.gen_usize_range(.{ self.t, i }, 0, particle_frames.len - 1);

            const speed_k = 0.01;
            const speed_k_x = 0.03;
            self.create_particle_internal(.{
                .frame = frame,
                .pos = pos,
                .vel = .{ .x = ox * speed_k_x, .y = oy * speed_k },
            });
        }
    }

    pub fn create_particle_internal(self: *Game, particle: Particle) void {
        if (self.particles_dead.findFirstSet()) |i| {
            if (i < self.particles.items.len) {
                self.particles_dead.unset(i);
                self.particles.items[i] = particle;
                return;
            }
        }

        var index = self.particles.items.len;
        self.particles.append(particle) catch unreachable;
        if (self.particles.items.len > self.particles_dead.capacity()) {
            self.particles_dead.resize(self.particles_dead.capacity() * 2, true) catch unreachable;
        }

        self.particles_dead.unset(index);
    }
};

pub const Particle = struct {
    pos: rl.Vector2,
    vel: rl.Vector2,
    t: i32 = 0,
    scale: f32 = 1.6,
    frame: usize = 0,

    pub fn tick(self: *Particle, dt_norm: f32) bool {
        self.pos.x += self.vel.x * dt_norm;
        self.pos.y += self.vel.y * dt_norm;
        self.pos.y -= 0.2 * dt_norm;
        self.scale = self.scale * std.math.pow(f32, 0.91, dt_norm);
        return self.scale > 0.001;
    }

    pub fn draw(self: *Particle) void {
        var p = self.pos;
        p.x -= self.scale * 4;
        p.y -= self.scale * 4;
        draw_particle_frame_scaled(self.frame, p, self.scale, self.scale);
    }
};

fn draw_particle_frame_scaled(frame: usize, pos: rl.Vector2, scale_x: f32, scale_y: f32) void {
    var sprite = particle_frames[frame];
    var rect = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(sprite.width)) * std.math.sign(scale_x),
        .height = @as(f32, @floatFromInt(sprite.height)) * std.math.sign(scale_y),
    };

    var dest = rl.Rectangle{
        .x = pos.x,
        .y = pos.y,
        .width = @as(f32, @floatFromInt(sprite.width)) * std.math.fabs(scale_x),
        .height = @as(f32, @floatFromInt(sprite.height)) * std.math.fabs(scale_y),
    };

    var origin = rl.Vector2{ .x = 0, .y = 0 };
    var no_tint = rl.WHITE;
    rl.DrawTexturePro(sprite, rect, dest, origin, 0, no_tint);
}

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
        return utils.straight_lerp(self.points[after_i], self.points[before_i], frac);
        //return self.points[before_i];
    }
};

pub const ScenePerlin1DState = union(enum) {
    Intro: struct { t: i32 },
    SinglePerlin: struct { t: i32, perlin: AnimatedPerlin },
    PerlinOctaves: struct { t: i32, perlins: [3]AnimatedPerlin },
    MergedPerlin: struct { t: i32, perlins: [3]AnimatedPerlin },
    MergedPerlin: struct { t: i32, perlins: [3]AnimatedPerlin },
    End: void,
};

pub const ScenePerlin1d = struct {
    state: ScenePerlin1DState,

    pub fn tick(self: *ScenePerlin1d) void {
        var clicked = rl.IsMouseButtonPressed(rl.MouseButton.MOUSE_BUTTON_LEFT);
        switch (self.state) {
            .Intro => |*x| {
                x.t += 1;
                if (x.t > 300 or clicked) {
                    g_shader_noise_dump = 0.5;
                    self.state = .{ .SinglePerlin = .{
                        .t = 0,
                        .perlin = .{},
                    } };
                }
            },
            .SinglePerlin => |*x| {
                x.t += 1;
                x.perlin.tick();
                if (x.t > 300 or clicked) {
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
                    perlins[0].yscale = consts.screen_height_f * 0.105;
                    perlins[0].point_col = consts.pico_red;

                    perlins[1] = .{};
                    pps = alloc.gpa.allocator().alloc(f32, 6) catch unreachable;
                    for (0..6) |i| {
                        pps[i] = rand.gen_f32_one_minus_one(.{ 10, i }) * 0.5;
                    }
                    perlins[1].perlin.points = pps;
                    perlins[1].yscale = consts.screen_height_f * 0.105;

                    perlins[2] = .{};
                    pps = alloc.gpa.allocator().alloc(f32, 12) catch unreachable;
                    for (0..12) |i| {
                        pps[i] = rand.gen_f32_one_minus_one(.{ 2, i }) * 0.25;
                    }
                    perlins[2].perlin.points = pps;
                    perlins[2].y0 = consts.screen_height_f * 0.8;
                    perlins[2].yscale = consts.screen_height_f * 0.105;
                    perlins[2].point_col = consts.pico_green;

                    self.state = .{
                        .PerlinOctaves = .{
                            .t = 0,
                            .perlins = perlins,
                        },
                    };
                }
            },
            .PerlinOctaves => |*x| {
                x.t += 1;
                for (&x.perlins) |*p| {
                    p.tick();
                }

                if (x.t > 600 or clicked) {
                    for (&x.perlins) |*p| {
                        p.t = 600;
                    }

                    self.state = .{
                        .MergedPerlin = .{
                            .t = 0,
                            .perlins = x.perlins,
                        },
                    };
                }
            },
            .MergedPerlin => |*x| {
                x.t += 1;
                for (&x.perlins) |*p| {
                    p.tick();
                }

                if (x.t > 20 and x.t < 150) {
                    x.perlins[0].y0 = utils.dan_lerp(x.perlins[0].y0, consts.screen_height_f * 0.35, 5.0);
                    x.perlins[1].y0 = utils.dan_lerp(x.perlins[1].y0, x.perlins[0].y0, 12.0);
                }

                if (x.t > 400 and x.t < 800) {
                    x.perlins[0].y0 = utils.dan_lerp(x.perlins[1].y0, consts.screen_height_f * 0.5, 5.0);
                    x.perlins[1].y0 = utils.dan_lerp(x.perlins[1].y0, x.perlins[0].y0, 5.0);
                    x.perlins[2].y0 = utils.dan_lerp(x.perlins[2].y0, x.perlins[0].y0, 12.0);
                }

                if (x.t > 1200 or clicked) {
                    self.state = Wrapping{};
                }
            },
            else => {
                // TODO
            },
        }
    }

    pub fn draw(self: *ScenePerlin1d) void {
        switch (self.state) {
            .Intro => |x| {
                _ = x;
                // Nothing to do
            },
            .SinglePerlin => |*x| {
                x.perlin.draw();
            },
            .PerlinOctaves => |*x| {
                for (&x.perlins) |*p| {
                    p.draw();
                }
            },
            .MergedPerlin => |*x| {
                if (x.t < 150) {
                    for (&x.perlins) |*p| {
                        p.draw();
                    }
                } else if (x.t < 400) {
                    // Merge 0 and 1
                    var t_merge = @as(f32, @floatFromInt(x.t - 150)) / 100.0;
                    var perlin_1_single = [1]*AnimatedPerlin{&x.perlins[1]};
                    x.perlins[0].draw_merged(&perlin_1_single, @min(t_merge, 1.0));
                    x.perlins[2].draw();
                } else {
                    // Merge 0 and 1
                    var t_merge = @as(f32, @floatFromInt(x.t - 400)) / 100.0;
                    var perlin_1_and_2 = [2]*AnimatedPerlin{ &x.perlins[1], &x.perlins[2] };
                    x.perlins[0].draw_merged(&perlin_1_and_2, @min(t_merge, 1.0));
                }
            },
            else => {
                // TODO
            },
        }
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
