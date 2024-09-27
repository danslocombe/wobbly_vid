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

pub const ground_y = 150;

const camera_min_x = -100;
const camera_max_x = 500;
const camera_min_y = -100;
const camera_max_y = 500;

const TAU = std.math.tau;

pub var g_shader_noise_dump: f32 = 0.0;
pub var g_screenshake: f32 = 0.0;

pub var particle_frames: []rl.Texture = &.{};

pub const perlin_yscale_base_octaves = consts.screen_height_f * 0.105;

pub const Game = struct {
    t: i32 = 0,

    camera_x: f32 = 0,
    camera_y: f32 = 0,
    camera_x_base: f32 = 0,
    camera_y_base: f32 = 0,
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
        sprites.g_t += 1;

        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_R)) {
            // TODO resett
        }

        self.scene_1.tick();

        // Update camera
        {
            //var camer
            //var target_camera_x = self.player.pos.x - consts.screen_width_f * 0.5;
            //var target_camera_y = self.player.pos.y - consts.screen_height_f * 0.5;
            var target_camera_x: f32 = 0.0;
            var target_camera_y: f32 = 0.0;

            var dx = (utils.g_mouse_screen.x - consts.screen_width_f * 0.5);
            var dy = (utils.g_mouse_screen.y - consts.screen_height_f * 0.5);
            //std.debug.print("g_mouse_screen: {d} {d}, diff {d} {d}\n", .{ utils.g_mouse_screen.x, utils.g_mouse_screen.y, dx, dy });

            target_camera_x = dx * 0.04; // + consts.screen_width_f * 0.5;
            target_camera_y = dy * 0.04; // + consts.screen_height_f * 0.5;
            //target_camera_x = (mouse_pos.x - consts.screen_width_f * 0.5) * 0.1; // + consts.screen_width_f * 0.5;
            //target_camera_y = (mouse_pos.y - consts.screen_height_f * 0.5) * 0.1; // + consts.screen_height_f * 0.5;

            //var k = 1500 / (1 + dt);
            //var k = 100 * dt_norm;
            const k = 10;
            self.camera_x_base = utils.dan_lerp(self.camera_x_base, target_camera_x, k);
            self.camera_y_base = utils.dan_lerp(self.camera_y_base, target_camera_y, k);

            var screenshake_mag = g_screenshake * 3;
            g_screenshake *= 0.88;

            var screenshake_angle = FroggyRand.init(self.t).gen_angle(0);

            self.camera_x = std.math.clamp(self.camera_x_base + std.math.cos(screenshake_angle) * screenshake_mag, camera_min_x, camera_max_x);
            self.camera_y = std.math.clamp(self.camera_y_base + std.math.sin(screenshake_angle) * screenshake_mag, camera_min_y, camera_max_y);

            utils.g_mouse_world = utils.sub_v2(utils.g_mouse_screen, .{ .x = self.camera_x, .y = self.camera_y });

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

        // Math dots
        for (0..consts.screen_width / 16) |x| {
            for (0..consts.screen_height / 16) |y| {
                rl.DrawPixel(@intCast(x * 16), @as(i32, @intCast(y * 16)) - 8, consts.pico_grey);
            }
        }

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
        return utils.straight_lerp(self.points[before_i], self.points[after_i], frac);
        //return self.points[before_i];
    }
};

pub const ScenePerlin1DState = union(enum) {
    Intro: struct { t: i32 },
    SinglePerlin: struct { t: i32, perlin: AnimatedPerlin },
    PerlinOctaves: struct { t: i32, perlins: [3]AnimatedPerlin },
    MergedPerlin: struct { t: i32, perlins: [3]AnimatedPerlin },
    Trick1: struct { t: i32 },
    IntroOsc: struct { t: i32 },
    OscStackedCentral: struct { t: i32 },
    OscStackedTipTail: struct { t: i32 },
    OscStackedMovable: struct { t: i32, small_offset: f32 = 0 },
    OscLandscapeSingle: struct { t: i32, playing: bool = false, landscape: Landscape },
    OscLandscape: struct { t: i32, landscapes: []Landscape },
    Trick2: struct { t: i32 },
    WrapStatic: struct { t: i32, perlin: CircularMappingPerlin },
    PlanetInterp: struct { t: i32, planet: Planet },
    PlanetProps: struct {
        t: i32,
        planet: Planet,
        rocks: std.ArrayList(Rock),
        trees: std.ArrayList(Tree),
    },
    End: void,
};

pub const ScenePerlin1d = struct {
    state: ScenePerlin1DState,

    pub fn tick(self: *ScenePerlin1d) void {
        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_R)) {
            // Reset
            self.state = .{ .Intro = .{ .t = 0 } };
            return;
        }

        var clicked = rl.IsMouseButtonPressed(rl.MouseButton.MOUSE_BUTTON_LEFT) or rl.IsKeyPressed(rl.KeyboardKey.KEY_F);
        var space_down = rl.IsKeyDown(rl.KeyboardKey.KEY_SPACE);
        switch (self.state) {
            .Intro => |*x| {
                x.t += 1;
                if (clicked) {
                    g_shader_noise_dump = 0.5;
                    g_screenshake = 1.0;
                    self.state = .{ .SinglePerlin = .{
                        .t = 0,
                        .perlin = .{},
                    } };
                }
            },
            .SinglePerlin => |*x| {
                x.t += 1;
                x.perlin.tick();
                if (clicked) {
                    self.state = .{
                        .PerlinOctaves = .{
                            .t = 0,
                            .perlins = make_three_perlins(),
                        },
                    };
                }
            },
            .PerlinOctaves => |*x| {
                x.t += 1;
                for (&x.perlins) |*p| {
                    p.tick();
                }

                if (clicked) {
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

                if (x.t > 0 and x.t < 150) {
                    x.perlins[0].y0 = utils.dan_lerp(x.perlins[0].y0, consts.screen_height_f * 0.35, 5.0);
                    x.perlins[1].y0 = utils.dan_lerp(x.perlins[1].y0, x.perlins[0].y0, 12.0);

                    const k = 1.5;
                    x.perlins[0].yscale = perlin_yscale_base_octaves * k;
                    x.perlins[1].yscale = perlin_yscale_base_octaves * k;
                    x.perlins[2].yscale = perlin_yscale_base_octaves * k;
                }

                if (x.t > 400 and x.t < 800) {
                    x.perlins[0].y0 = utils.dan_lerp(x.perlins[1].y0, consts.screen_height_f * 0.5, 5.0);
                    x.perlins[1].y0 = utils.dan_lerp(x.perlins[1].y0, x.perlins[0].y0, 5.0);
                    x.perlins[2].y0 = utils.dan_lerp(x.perlins[2].y0, x.perlins[0].y0, 12.0);

                    const k = 1.5;
                    x.perlins[0].yscale = perlin_yscale_base_octaves * k;
                    x.perlins[1].yscale = perlin_yscale_base_octaves * k;
                    x.perlins[2].yscale = perlin_yscale_base_octaves * k;
                }

                if (clicked) {
                    self.state = .{ .Trick1 = .{ .t = 0 } };
                }
            },
            .Trick1 => |*x| {
                x.t += 1;
                if (clicked) {
                    self.state = .{ .IntroOsc = .{ .t = 0 } };
                    g_shader_noise_dump = 0.5;
                    g_screenshake = 1.0;
                }
            },
            .IntroOsc => |*x| {
                if (!space_down) {
                    x.t += 1;
                }
                if (clicked) {
                    // Carry over t so that the animations line up
                    self.state = .{ .OscStackedCentral = .{ .t = x.t } };
                }
            },
            .OscStackedCentral => |*x| {
                if (!space_down) {
                    x.t += 1;
                }
                if (clicked) {
                    self.state = .{ .OscStackedTipTail = .{ .t = x.t } };
                }
            },
            .OscStackedTipTail => |*x| {
                if (!space_down) {
                    x.t += 1;
                }
                if (clicked) {
                    self.state = .{ .OscStackedMovable = .{ .t = x.t } };
                }
            },
            .OscStackedMovable => |*x| {
                if (!space_down) {
                    x.t += 1;
                }

                //if (rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT)) {
                //x.small_offset = utils.g_mouse_screen.x / 60;
                if (rl.IsKeyDown(rl.KeyboardKey.KEY_UP)) {
                    x.small_offset -= 0.08 + 0.02;
                }
                if (rl.IsKeyDown(rl.KeyboardKey.KEY_DOWN)) {
                    x.small_offset += 0.08;
                }

                //}

                if (clicked) {
                    self.state = .{ .OscLandscapeSingle = .{
                        .t = 0,
                        .landscape = .{},
                    } };

                    g_shader_noise_dump = 0.5;
                    g_screenshake = 1.0;
                }
            },
            .OscLandscapeSingle => |*x| {
                x.t += 1;
                x.playing = space_down;
                if (x.playing) {
                    x.landscape.tick();
                }
                if (clicked) {
                    var rand = FroggyRand.init(1);
                    var landscapes = alloc.gpa.allocator().alloc(Landscape, 3) catch unreachable;
                    var r: f32 = 18;
                    landscapes[0] = .{
                        .y0 = consts.screen_height_f * 0.2,
                        .point_col = consts.pico_red,
                        .r = r,
                    };

                    var offsets_1 = alloc.gpa.allocator().alloc(f32, 5) catch unreachable;
                    for (0..5) |i| {
                        offsets_1[i] = rand.gen_angle(.{ 0, i });
                    }

                    landscapes[1] = .{
                        .offsets = offsets_1,
                        .y0 = consts.screen_height_f * 0.5,
                        .r = r * 0.5,
                    };

                    var offsets_2 = alloc.gpa.allocator().alloc(f32, 9) catch unreachable;
                    for (0..9) |i| {
                        offsets_2[i] = rand.gen_angle(.{ 0, i });
                    }

                    landscapes[2] = .{
                        .offsets = offsets_2,
                        .y0 = consts.screen_height_f * 0.8,
                        .point_col = consts.pico_green,
                        .r = r * 0.25,
                    };

                    self.state = .{ .OscLandscape = .{
                        .t = 0,
                        .landscapes = landscapes,
                    } };
                }
            },
            .OscLandscape => |*x| {
                x.t += 1;
                for (x.landscapes) |*landscape| {
                    landscape.tick();
                }

                if (x.t > 60 and x.t < 150) {
                    x.landscapes[0].draw_circles = false;
                    x.landscapes[1].draw_circles = false;

                    x.landscapes[0].y0 = utils.dan_lerp(x.landscapes[0].y0, consts.screen_height_f * 0.35, 5.0);
                    x.landscapes[1].y0 = utils.dan_lerp(x.landscapes[1].y0, x.landscapes[0].y0, 12.0);
                }

                if (x.t > 400 and x.t < 800) {
                    x.landscapes[0].draw_circles = false;
                    x.landscapes[1].draw_circles = false;
                    x.landscapes[2].draw_circles = false;

                    x.landscapes[0].y0 = utils.dan_lerp(x.landscapes[1].y0, consts.screen_height_f * 0.5, 5.0);
                    x.landscapes[1].y0 = utils.dan_lerp(x.landscapes[1].y0, x.landscapes[0].y0, 5.0);
                    x.landscapes[2].y0 = utils.dan_lerp(x.landscapes[2].y0, x.landscapes[0].y0, 12.0);
                }

                if (clicked) {
                    self.state = .{ .Trick2 = .{ .t = 0 } };
                }
            },
            .Trick2 => |*x| {
                x.t += 1;
                if (clicked) {
                    //var perlins = make_three_perlins();
                    //perlins[0].y0 = consts.screen_height_f * 0.5;
                    //perlins[1].y0 = consts.screen_height_f * 0.5;
                    //perlins[2].y0 = consts.screen_height_f * 0.5;

                    //self.state = .{
                    //    .WrapStatic = .{
                    //        .t = 0,
                    //        .perlin = .{
                    //            .perlins = perlins,
                    //        },
                    //    },
                    //};
                    g_shader_noise_dump = 0.5;
                    g_screenshake = 1.0;

                    var rand = FroggyRand.init(1);
                    var landscapes = alloc.gpa.allocator().alloc(Landscape, 3) catch unreachable;
                    var r: f32 = 18;
                    landscapes[0] = .{
                        .y0 = consts.screen_height_f * 0.2,
                        .point_col = consts.pico_red,
                        .r = r,
                    };

                    var offsets_1 = alloc.gpa.allocator().alloc(f32, 5) catch unreachable;
                    for (0..5) |i| {
                        offsets_1[i] = rand.gen_angle(.{ 0, i });
                    }

                    landscapes[1] = .{
                        .offsets = offsets_1,
                        .y0 = consts.screen_height_f * 0.5,
                        .r = r * 0.5,
                    };

                    var offsets_2 = alloc.gpa.allocator().alloc(f32, 9) catch unreachable;
                    for (0..9) |i| {
                        offsets_2[i] = rand.gen_angle(.{ 0, i });
                    }

                    landscapes[2] = .{
                        .offsets = offsets_2,
                        .y0 = consts.screen_height_f * 0.8,
                        .point_col = consts.pico_green,
                        .r = r * 0.25,
                    };

                    self.state = .{
                        .WrapStatic = .{
                            .t = 0,
                            .perlin = .{
                                .landscapes = landscapes,
                            },
                        },
                    };
                }
            },
            .WrapStatic => |*x| {
                x.t += 1;
                x.perlin.landscapes[0].tick();
                x.perlin.landscapes[1].tick();
                x.perlin.landscapes[2].tick();
                if (clicked) {
                    g_screenshake = 0.5;
                    g_shader_noise_dump = 0.5;
                    self.state = .{
                        .PlanetInterp = .{
                            .t = 0,
                            .planet = Planet{
                                .world = world.World.new(0, .{ .x = consts.screen_width_f * 0.5, .y = consts.screen_height_f * 0.5 }, 64, 16),
                            },
                        },
                    };
                }
            },
            .PlanetInterp => |*x| {
                x.t += 1;
                x.planet.world.tick();
                if (clicked) {
                    var new_planet = x.planet;
                    //new_planet.draw_oscs = false;
                    new_planet.draw_oscs_arrows = true;
                    var trees = std.ArrayList(Tree).init(alloc.gpa.allocator());
                    trees.append(.{
                        .angle = 0.723 * TAU,
                    }) catch unreachable;
                    trees.append(.{
                        .angle = 0.89 * TAU,
                    }) catch unreachable;
                    trees.append(.{
                        .angle = 0.4 * TAU,
                    }) catch unreachable;
                    var rocks = std.ArrayList(Rock).init(alloc.gpa.allocator());
                    self.state = .{
                        .PlanetProps = .{
                            .t = 0,
                            .planet = new_planet,
                            .trees = trees,
                            .rocks = rocks,
                        },
                    };
                }
            },
            .PlanetProps => |*x| {
                x.t += 1;
                x.planet.world.tick();

                var new_rocks = std.ArrayList(Rock).init(alloc.gpa.allocator());

                for (x.rocks.items) |*rock| {
                    if (rock.tick(&x.planet)) {
                        new_rocks.append(rock.*) catch unreachable;
                    } else {
                        g_screenshake = @max(g_screenshake, rock.r * 0.2);
                    }
                }

                x.rocks.deinit();
                x.rocks = new_rocks;

                if (clicked) {
                    x.rocks.append(Rock.new(x.t)) catch unreachable;
                }

                for (x.trees.items) |*tree| {
                    tree.tick(&x.planet);
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
                //fonts.g_linssen.draw_text(0, "making interesting things boring", 60, 150, consts.pico_black);
                sprites.draw_blob_text("maths", .{ .x = 100, .y = 100 });
                //sprites.draw_blob_text("maths", .{ .x = 100, .y = 100 });

                var styling = Styling{
                    .color = consts.pico_black,
                    .wavy = true,
                    //.rainbow = true,
                };
                var font_state = fonts.DrawTextState{};
                //fonts.g_linssen.draw_text_state(x.t, "rigorous fun!", 30, 210, styling, &font_state);
                fonts.g_ui.draw_text_state(x.t, "perlin noise!", 80, 130, styling, &font_state);
            },
            .SinglePerlin => |*x| {
                x.perlin.draw();

                fonts.g_linssen.draw_text(0, "Perlin Noise in 1d", 120, 20, consts.pico_black);
                fonts.g_linssen.draw_text(0, "sample random points in [-1,1]", 80, 220, consts.pico_black);
            },
            .PerlinOctaves => |*x| {
                for (&x.perlins) |*p| {
                    p.draw();
                }
                fonts.g_linssen.draw_text(0, "three octaves, each with double", 80, 210, consts.pico_black);
                fonts.g_linssen.draw_text(0, "the points, half the amplitude", 80, 220, consts.pico_black);
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

                fonts.g_linssen.draw_text(0, "sum the layers together", 100, 215, consts.pico_black);
            },
            .IntroOsc => |*state| {
                var tt = @as(f32, @floatFromInt(state.t)) * 0.02;
                const r = 32;
                const col = consts.pico_sea;
                draw_generator(tt, r, r, col);

                //fonts.g_linssen.draw_text(0, "sine wave generated as time increases", 80, 215, consts.pico_black);
                fonts.g_linssen.draw_text(0, "y = sin(t)", 80, 215, consts.pico_black);
            },
            .Trick1 => |*x| {
                sprites.draw_blob_text("trick one", .{ .x = 100, .y = 100 });
                var styling = Styling{
                    .color = consts.pico_black,
                    .wavy = true,
                };
                var font_state = fonts.DrawTextState{};
                fonts.g_linssen.draw_text_state(x.t, "(making things move)", 80, 130, styling, &font_state);
            },
            .OscStackedCentral => |*state| {
                var tt = @as(f32, @floatFromInt(state.t)) * 0.02;
                const r = 32;
                const col = consts.pico_sea;
                var t1 = tt + 0.25 * 3.141;
                var t2 = tt + 0.55 * 3.141;
                //const osc_1_start = 60;
                //_ = osc_1_start;
                //const osc_2_start = 120;
                //_ = osc_2_start;
                //const joined_view = 200;
                //_ = joined_view;

                draw_generator(tt, r, r, col);
                draw_generator(t1, r * 0.5, r, consts.pico_red);
                draw_generator(t2, r * 0.25, r, consts.pico_green);

                var angle0 = tt;
                var angle1 = t1;
                var angle2 = t2;

                var cx = consts.screen_width_f * 0.3;
                var cy = consts.screen_height_f * 0.5;
                var p = .{ .x = cx, .y = cy };
                var p_dotted_end = p;
                p_dotted_end.x = cx + r * 1.5;

                var x0: i32 = @intFromFloat(p_dotted_end.x);
                var x_end: i32 = @intFromFloat(consts.screen_width_f * 0.85);
                var x = x0;
                var prev_y: f32 = 0;
                while (x < x_end) {
                    var y_n: f32 = 0;
                    // Sum all the things
                    y_n += std.math.sin(angle0);
                    y_n += std.math.sin(angle1) * 0.5;
                    y_n += std.math.sin(angle2) * 0.25;
                    var y = cy + y_n * r;

                    if (x != x0) {
                        rl.DrawLine(x - 1, @intFromFloat(prev_y), x, @intFromFloat(y), consts.pico_blue);
                    }

                    angle0 -= 0.02;
                    angle1 -= 0.02;
                    angle2 -= 0.02;
                    x += 1;
                    prev_y = y;
                }

                fonts.g_linssen.draw_text(0, "three sine waves stacked", 70, 210, consts.pico_black);
                fonts.g_linssen.draw_text(0, "each with same period but decreasing amplitudes", 30, 220, consts.pico_black);
            },
            .OscStackedTipTail => |*state| {
                var t0 = @as(f32, @floatFromInt(state.t)) * 0.02;
                const r = 32;
                var t1 = t0 + 0.25 * 3.141;
                var t2 = t0 + 0.55 * 3.141;
                var angle0 = t0;
                var angle1 = t1;
                var angle2 = t2;

                var cx = consts.screen_width_f * 0.3;
                var cy = consts.screen_height_f * 0.5;

                var end_0_x = cx + std.math.cos(angle0) * r;
                var end_0_y = cy + std.math.sin(angle0) * r;
                rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), r, consts.pico_sea);
                utils.draw_arrow(@intFromFloat(cx), @intFromFloat(cy), @intFromFloat(end_0_x), @intFromFloat(end_0_y), consts.pico_blue, 10);

                var end_1_x = end_0_x + std.math.cos(angle1) * r * 0.5;
                var end_1_y = end_0_y + std.math.sin(angle1) * r * 0.5;
                rl.DrawCircleLines(@intFromFloat(end_0_x), @intFromFloat(end_0_y), r * 0.5, consts.pico_red);
                //utils.draw_arrow(@intFromFloat(end_0_x), @intFromFloat(end_0_y), @intFromFloat(end_1_x), @intFromFloat(end_1_y), consts.pico_red, 4);
                utils.draw_arrow(@intFromFloat(end_0_x), @intFromFloat(end_0_y), @intFromFloat(end_1_x), @intFromFloat(end_1_y), consts.pico_blue, 4);

                var end_2_x = end_1_x + std.math.cos(angle2) * r * 0.25;
                var end_2_y = end_1_y + std.math.sin(angle2) * r * 0.25;
                rl.DrawCircleLines(@intFromFloat(end_1_x), @intFromFloat(end_1_y), r * 0.25, consts.pico_green);
                //utils.draw_arrow(@intFromFloat(end_1_x), @intFromFloat(end_1_y), @intFromFloat(end_2_x), @intFromFloat(end_2_y), consts.pico_green, 3);
                utils.draw_arrow(@intFromFloat(end_1_x), @intFromFloat(end_1_y), @intFromFloat(end_2_x), @intFromFloat(end_2_y), consts.pico_blue, 3);

                var p = .{ .x = end_2_x, .y = end_2_y };
                var p_dotted_end = p;
                p_dotted_end.x = cx + r * 1.5;
                utils.draw_broken_line(p, p_dotted_end, 2.0, 2.0, consts.pico_blue);

                var x0: i32 = @intFromFloat(p_dotted_end.x);
                var x_end: i32 = @intFromFloat(consts.screen_width_f * 0.85);
                var x = x0;
                var prev_y: f32 = 0;
                while (x < x_end) {
                    var y_n: f32 = 0;
                    // Sum all the things
                    y_n += std.math.sin(angle0);
                    y_n += std.math.sin(angle1) * 0.5;
                    y_n += std.math.sin(angle2) * 0.25;
                    var y = cy + y_n * r;

                    if (x != x0) {
                        rl.DrawLine(x - 1, @intFromFloat(prev_y), x, @intFromFloat(y), consts.pico_blue);
                    }

                    angle0 -= 0.02;
                    angle1 -= 0.02;
                    angle2 -= 0.02;
                    x += 1;
                    prev_y = y;
                }

                //fonts.g_linssen.draw_text(0, "y = r0*sin(t + t0) + r1*sin(t + t1) + r2*sin(t + t2)", 70, 210, consts.pico_black);
                var font_state = fonts.DrawTextState{};
                var styling = Styling{
                    .color = consts.pico_black,
                    .wavy = true,
                };
                fonts.g_linssen.draw_text_state(state.t, "y = r0*sin(t + t0) + r1*sin(t + t1) + r2*sin(t + t2)", 30, 210, styling, &font_state);
            },
            .OscStackedMovable => |*state| {
                var cx = consts.screen_width_f * 0.3;
                var cy = consts.screen_height_f * 0.5;

                var tt = @as(f32, @floatFromInt(state.t)) * 0.02;
                const r = 32;
                const col = consts.pico_sea;
                var t1 = tt + 0.25 * 3.141;
                var t2 = tt + 0.55 * 3.141 + state.small_offset;

                rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), 32 * 0.25 - 0.5, consts.pico_green);
                rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), 32 * 0.25 + 0.5, consts.pico_green);

                draw_generator(tt, r, r, col);
                draw_generator(t1, r * 0.5, r, consts.pico_red);

                draw_generator(t2, r * 0.25, r, consts.pico_green);

                var angle0 = tt;
                var angle1 = t1;
                var angle2 = t2;

                //rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), 32 * 0.25 + 0.5, consts.pico_green);

                var p = .{ .x = cx, .y = cy };
                var p_dotted_end = p;
                p_dotted_end.x = cx + r * 1.5;

                var x0: i32 = @intFromFloat(p_dotted_end.x);
                var x_end: i32 = @intFromFloat(consts.screen_width_f * 0.85);
                var x = x0;
                var prev_y: f32 = 0;
                while (x < x_end) {
                    var y_n: f32 = 0;
                    // Sum all the things
                    y_n += std.math.sin(angle0);
                    y_n += std.math.sin(angle1) * 0.5;
                    y_n += std.math.sin(angle2) * 0.25;
                    var y = cy + y_n * r;

                    if (x != x0) {
                        rl.DrawLine(x - 1, @intFromFloat(prev_y), x, @intFromFloat(y), consts.pico_blue);
                    }

                    angle0 -= 0.02;
                    angle1 -= 0.02;
                    angle2 -= 0.02;
                    x += 1;
                    prev_y = y;
                }

                fonts.g_linssen.draw_text(0, "varying the inner oscillator", 70, 210, consts.pico_black);
            },
            .OscLandscapeSingle => |*state| {
                state.landscape.draw();
                if (!state.playing) {
                    rl.DrawLine(10, 10, 10, 20, consts.pico_black);
                    rl.DrawLine(11, 10, 11, 20, consts.pico_black);
                    rl.DrawLine(15, 10, 15, 20, consts.pico_black);
                    rl.DrawLine(16, 10, 16, 20, consts.pico_black);
                } else {}
                fonts.g_linssen.draw_text(0, std.fmt.allocPrintZ(alloc.temp_alloc.allocator(), "t = {d:.1}", .{state.landscape.t}) catch unreachable, 40, 20, consts.pico_blue);

                fonts.g_linssen.draw_text(0, "Instead of sampling a number in [-1,1]", 70, 210, consts.pico_black);
                fonts.g_linssen.draw_text(0, "sample angle offset in [0, 2pi]", 70, 220, consts.pico_black);
            },
            .OscLandscape => |*state| {
                if (state.t < 60) {
                    for (state.landscapes) |*landscape| {
                        landscape.draw();
                    }
                } else if (state.t < 400) {
                    var xx = [_]*Landscape{&state.landscapes[1]};
                    state.landscapes[0].draw();
                    state.landscapes[1].draw();
                    state.landscapes[0].draw_merged(&xx);
                    state.landscapes[2].draw();
                } else {
                    var xx = [_]*Landscape{ &state.landscapes[1], &state.landscapes[2] };
                    state.landscapes[0].draw();
                    state.landscapes[1].draw();
                    state.landscapes[2].draw();
                    state.landscapes[0].draw_merged(&xx);
                }
            },
            .Trick2 => |*x| {
                sprites.draw_blob_text("trick two", .{ .x = 100, .y = 100 });
                var styling = Styling{
                    .color = consts.pico_black,
                    .wavy = true,
                };
                var font_state = fonts.DrawTextState{};
                fonts.g_linssen.draw_text_state(x.t, "(making things round)", 90, 130, styling, &font_state);
            },
            .WrapStatic => |*x| {
                //const t_merge = 10000;
                //var perlin_1_and_2 = [2]*AnimatedPerlin{ &x.perlins[1], &x.perlins[2] };
                //x.perlins[0].draw_merged(&perlin_1_and_2, @min(t_merge, 1.0));

                var tt: f32 = 0;

                if (x.t > 180) {
                    tt = @as(f32, @floatFromInt(x.t - 180)) * 0.003;
                    tt = std.math.pow(f32, tt, 1.5);
                }

                x.perlin.draw(@min(tt, 1.0));

                fonts.g_linssen.draw_text(0, "wrap onto a circle", 70, 210, consts.pico_black);
                fonts.g_linssen.draw_text(0, "place oscilators at equal spacing in [0,2pi]", 70, 220, consts.pico_black);
            },
            .PlanetInterp => |*x| {
                x.planet.draw();
                fonts.g_linssen.draw_text(0, "interpolation", 70, 210, consts.pico_black);
            },
            .PlanetProps => |*x| {
                x.planet.draw();

                for (x.trees.items) |*tree| {
                    tree.draw(&x.planet);
                }
                for (x.rocks.items) |*rock| {
                    rock.draw();
                }

                fonts.g_linssen.draw_text(0, "props", 70, 210, consts.pico_black);
            },
            else => {
                // Todo
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

pub fn draw_generator(theta: f32, r: f32, r_big: f32, col: rl.Color) void {
    var cx = consts.screen_width_f * 0.3;
    var cy = consts.screen_height_f * 0.5;
    rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), r, col);

    var px = cx + r * std.math.cos(theta);
    var py = cy + r * std.math.sin(theta);
    var arrow_size = 4 + 6 * r / r_big;
    utils.draw_arrow_f(cx, cy, px, py, col, @intFromFloat(arrow_size));

    var p = .{ .x = px, .y = py };
    var p_dotted_end = p;
    p_dotted_end.x = cx + r_big * 1.5;
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
    return utils.straight_lerp(generators[prev].y, generators[i].y, frac);
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

pub const Planet = struct {
    world: world.World,
    draw_oscs: bool = true,
    draw_oscs_arrows: bool = false,

    pub fn draw(self: *Planet) void {
        const n = 128;
        var prev: rl.Vector2 = .{};

        for (0..(n + 1)) |i| {
            var i_n: f32 = @as(f32, @floatFromInt(i)) / n;

            var pos = self.world.pos_on_surface(i_n * TAU, 0.0);

            if (i != 0) {
                rl.DrawLineV(prev, pos, consts.pico_blue);
            }

            prev = pos;
        }

        if (self.draw_oscs) {
            for (self.world.oscs) |*osc| {
                var angle = osc.pos * TAU;
                var sample = self.world.base_radius + self.world.radius_vary * osc.sample();

                var pos = utils.add_v2(self.world.pos, .{ .x = std.math.cos(angle) * sample, .y = std.math.sin(angle) * sample });

                var col = consts.pico_blue;
                if (osc.amp0 >= 0.25) {
                    col = consts.pico_red;
                } else if (osc.amp0 > 0.18) {
                    col = consts.pico_sea;
                } else if (osc.amp0 > 0.125) {
                    col = consts.pico_green;
                }

                if (self.draw_oscs_arrows) {
                    var on_circle = utils.add_v2(self.world.pos, utils.scale_v2(self.world.base_radius, .{ .x = std.math.cos(angle), .y = std.math.sin(angle) }));
                    utils.draw_arrow_f(on_circle.x, on_circle.y, pos.x, pos.y, col, 4);
                } else {
                    rl.DrawCircleLines(@intFromFloat(pos.x), @intFromFloat(pos.y), osc.amp * 10, col);
                }
            }
        }
    }
};

pub const Tree = struct {
    angle: f32,
    pos: rl.Vector2 = .{},
    destroyed: bool = false,

    pub fn tick(self: *Tree, planet: *Planet) void {
        _ = planet;
        _ = self;
        //self.pos = planet.world.pos_on_surface(self.angle, 17.0);
    }

    pub fn draw(self: *Tree, planet: *Planet) void {
        //pub fn draw_frame_scaled_rotated(self: *SpriteManager, name: []const u8, p_frame: usize, pos: rl.Vector2, scale_x: f32, scale_y: f32, origin: rl.Vector2, rotation: f32) void {
        self.pos = planet.world.pos_on_surface(self.angle, 0.0);
        var normal = planet.world.sample_normal(self.angle);
        var angle = std.math.atan2(f32, normal.y, normal.x) + TAU / 4.0;
        //var angle = self.angle + TAU / 4.0;
        //rl.DrawCircleV(self.pos, 2, consts.pico_pink);
        sprites.g_sprites.draw_frame_scaled_rotated("tree_small", 0, self.pos, 1, 1, .{ .x = 8, .y = 18.0 }, angle * 360.0 / TAU);
    }
};

pub const Rock = struct {
    pos: rl.Vector2,
    vel: rl.Vector2,
    r: f32,
    sides: i32,

    pub fn new(t: i32) Rock {
        var rand = FroggyRand.init(t);
        var theta = rand.gen_angle("a");
        var speed = rand.gen_f32_range("s", 0.0, 0.2);
        //const speed = 0;

        var vel = .{ .x = std.math.cos(theta) * speed, .y = std.math.sin(theta) * speed };

        return Rock{
            .pos = utils.g_mouse_world,
            .vel = vel,
            .r = rand.gen_f32_range("r", 2.0, 8.0),
            .sides = rand.gen_i32_range("sides", 3, 8),
        };
    }

    pub fn tick(self: *Rock, planet: *Planet) bool {
        var delta = utils.sub_v2(planet.world.pos, self.pos);
        var delta_norm = utils.norm(delta);
        var dist_2 = utils.mag2_v2(delta);

        var angle = std.math.atan2(f32, -delta.y, -delta.x);
        var sample = planet.world.sample(angle);
        var dist = std.math.sqrt(dist_2);
        if (dist < sample + self.r) {
            planet.world.slam(10 * self.r, angle);
            return false;
        }

        var accel = 300.0 / dist_2;

        self.vel = utils.add_v2(self.vel, utils.scale_v2(accel, delta_norm));
        self.pos = utils.add_v2(self.pos, self.vel);

        return true;
    }

    pub fn draw(self: *Rock) void {
        var prev: rl.Vector2 = .{};
        for (0..@intCast(self.sides + 1)) |i| {
            var i_n: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.sides));
            var angle = i_n * TAU;
            var pos = utils.add_v2(self.pos, .{ .x = std.math.cos(angle) * self.r, .y = std.math.sin(angle) * self.r });

            if (i != 0) {
                rl.DrawLineV(prev, pos, consts.pico_blue);
            }

            prev = pos;
        }
        //rl.DrawCircleSectorLines(self.pos, self.r, 0, 360, self.sides, consts.pico_blue);
    }
};
