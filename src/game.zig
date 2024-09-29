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

const perlin = @import("perlin.zig");

pub const ground_y = 150;

const camera_min_x = -100;
const camera_max_x = 500;
const camera_min_y = -100;
const camera_max_y = 500;

const TAU = std.math.tau;

pub var g_shader_noise_dump: f32 = 0.0;
pub var g_screenshake: f32 = 0.0;

pub var particle_frames: []rl.Texture = &.{};

pub const Game = struct {
    t: i32 = 0,

    camera_x: f32 = 0,
    camera_y: f32 = 0,
    camera_x_base: f32 = 0,
    camera_y_base: f32 = 0,
    camera_zoom: f32 = 1,
    screenshake_t: f32 = 0,

    slideshow: Slideshow,

    pub fn init() Game {
        var rand = FroggyRand.init(0);
        _ = rand;

        var slideshow = Slideshow{
            .scene = Scene{
                .Intro = .{ .t = 0 },
            },
        };

        return Game{
            .slideshow = slideshow,
        };
    }

    pub fn tick(self: *Game) void {
        self.t += 1;
        sprites.g_t += 1;

        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_R)) {
            // TODO resett
        }

        self.slideshow.tick();

        // Update camera
        {
            var target_camera_x: f32 = 0.0;
            var target_camera_y: f32 = 0.0;

            var dx = (utils.g_mouse_screen.x - consts.screen_width_f * 0.5);
            var dy = (utils.g_mouse_screen.y - consts.screen_height_f * 0.5);

            target_camera_x = dx * 0.04;
            target_camera_y = dy * 0.04;
            const k = 10;
            self.camera_x_base = utils.dan_lerp(self.camera_x_base, target_camera_x, k);
            self.camera_y_base = utils.dan_lerp(self.camera_y_base, target_camera_y, k);

            var screenshake_mag = g_screenshake * 3;
            g_screenshake *= 0.88;

            var screenshake_angle = FroggyRand.init(self.t).gen_angle(0);

            self.camera_x = std.math.clamp(self.camera_x_base + std.math.cos(screenshake_angle) * screenshake_mag, camera_min_x, camera_max_x);
            self.camera_y = std.math.clamp(self.camera_y_base + std.math.sin(screenshake_angle) * screenshake_mag, camera_min_y, camera_max_y);

            utils.g_mouse_world = utils.sub_v2(utils.g_mouse_screen, .{ .x = self.camera_x, .y = self.camera_y });

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

        self.slideshow.draw();
        camera.End();
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

pub const Scene = union(enum) {
    Intro: struct { t: i32 },
    EndGoal: FinalSceneState,
    SinglePerlin: struct { t: i32, perlin: perlin.AnimatedPerlin },
    PerlinOctaves: struct { t: i32, perlins: [3]perlin.AnimatedPerlin },
    MergedPerlin: struct { t: i32, perlins: [3]perlin.AnimatedPerlin },
    Trick1: struct { t: i32 },
    IntroOsc: struct { t: i32 },
    OscStackedCentral: struct { t: i32 },
    OscStackedTipTail: struct { t: i32 },
    OscStackedMovable: struct { t: i32, small_offset: f32 = 0 },
    OscLandscapeSingle: struct { t: i32, playing: bool = false, landscape: perlin.Landscape },
    OscLandscape: struct { t: i32, landscapes: []perlin.Landscape },
    Trick2: struct { t: i32 },
    WrapStatic: struct { t: i32, perlin: perlin.CircularMappingPerlin },
    PlanetInterp: struct { t: i32, planet: Planet },
    PlanetPropPos: struct {
        t: i32,
        planet: Planet,
        tree: Tree,
    },
    PlanetPropTangent: struct {
        t: i32,
        planet: Planet,
        tree: Tree,
    },
    OscSlam: struct {
        t: f32,
        paused: bool = false,
        just_slammed: bool = false,
        planet: Planet,
        player_state: PlayerState = .{},
        particles: std.ArrayList(Particle),

        ongoing_slam_offset_t: f32 = 0,
    },
    PlanetProps: FinalSceneState,
    End: void,
};

pub const Slideshow = struct {
    scene: Scene,

    pub fn tick(self: *Slideshow) void {
        _ = self;
        // All tick logic moved to draw to make it easier to handle scene components.
        // (Its a lot easier when everything is next to each other.)
    }

    pub fn draw(self: *Slideshow) void {
        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_R)) {
            // Reset
            self.scene = .{ .Intro = .{ .t = 0 } };
            return;
        }

        var clicked = rl.IsMouseButtonPressed(rl.MouseButton.MOUSE_BUTTON_LEFT) or rl.IsKeyPressed(rl.KeyboardKey.KEY_F);
        var space_down = rl.IsKeyDown(rl.KeyboardKey.KEY_SPACE);

        switch (self.scene) {
            .Intro => |*x| {
                x.t += 1;
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

                if (clicked) {
                    g_shader_noise_dump = 0.5;
                    g_screenshake = 1.0;
                    self.scene = .{ .SinglePerlin = .{
                        .t = 0,
                        .perlin = .{},
                    } };
                }
            },
            .SinglePerlin => |*x| {
                x.t += 1;
                x.perlin.tick();
                x.perlin.draw();

                fonts.g_linssen.draw_text(0, "Perlin Noise in 1d", 120, 20, consts.pico_black);
                fonts.g_linssen.draw_text(0, "sample random points in [-1,1]", 80, 220, consts.pico_black);

                if (clicked) {
                    self.scene = .{
                        .PerlinOctaves = .{
                            .t = 0,
                            .perlins = perlin.make_three_perlins(),
                        },
                    };
                }
            },
            .PerlinOctaves => |*x| {
                x.t += 1;
                for (&x.perlins) |*p| {
                    p.tick();
                }

                for (&x.perlins) |*p| {
                    p.draw();
                }
                fonts.g_linssen.draw_text(0, "three octaves, each ascending level", 60, 210, consts.pico_black);
                fonts.g_linssen.draw_text(0, "with  double the points, half the amplitude", 60, 220, consts.pico_black);

                if (clicked) {
                    for (&x.perlins) |*p| {
                        p.t = 600;
                    }

                    self.scene = .{
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
                    x.perlins[0].yscale = perlin.perlin_yscale_base_octaves * k;
                    x.perlins[1].yscale = perlin.perlin_yscale_base_octaves * k;
                    x.perlins[2].yscale = perlin.perlin_yscale_base_octaves * k;
                }

                if (x.t > 400 and x.t < 800) {
                    x.perlins[0].y0 = utils.dan_lerp(x.perlins[1].y0, consts.screen_height_f * 0.5, 5.0);
                    x.perlins[1].y0 = utils.dan_lerp(x.perlins[1].y0, x.perlins[0].y0, 5.0);
                    x.perlins[2].y0 = utils.dan_lerp(x.perlins[2].y0, x.perlins[0].y0, 12.0);

                    const k = 1.5;
                    x.perlins[0].yscale = perlin.perlin_yscale_base_octaves * k;
                    x.perlins[1].yscale = perlin.perlin_yscale_base_octaves * k;
                    x.perlins[2].yscale = perlin.perlin_yscale_base_octaves * k;
                }

                if (x.t < 150) {
                    for (&x.perlins) |*p| {
                        p.draw();
                    }
                } else if (x.t < 400) {
                    // Merge 0 and 1
                    var t_merge = @as(f32, @floatFromInt(x.t - 150)) / 100.0;
                    var perlin_1_single = [1]*perlin.AnimatedPerlin{&x.perlins[1]};
                    x.perlins[0].draw_merged(&perlin_1_single, @min(t_merge, 1.0));
                    x.perlins[2].draw();
                } else {
                    // Merge 0 and 1
                    var t_merge = @as(f32, @floatFromInt(x.t - 400)) / 100.0;
                    var perlin_1_and_2 = [2]*perlin.AnimatedPerlin{ &x.perlins[1], &x.perlins[2] };
                    x.perlins[0].draw_merged(&perlin_1_and_2, @min(t_merge, 1.0));
                }

                fonts.g_linssen.draw_text(0, "sum the layers together", 100, 215, consts.pico_black);

                if (clicked) {
                    self.scene = .{ .Trick1 = .{ .t = 0 } };
                }
            },
            .Trick1 => |*x| {
                x.t += 1;
                sprites.draw_blob_text("trick one", .{ .x = 100, .y = 100 });
                var styling = Styling{
                    .color = consts.pico_black,
                    .wavy = true,
                };
                var font_state = fonts.DrawTextState{};
                fonts.g_linssen.draw_text_state(x.t, "(making things move)", 80, 130, styling, &font_state);

                if (clicked) {
                    self.scene = .{ .IntroOsc = .{ .t = 0 } };
                    g_shader_noise_dump = 0.5;
                    g_screenshake = 1.0;
                }
            },
            .IntroOsc => |*state| {
                if (!space_down) {
                    state.t += 1;
                }
                var tt = @as(f32, @floatFromInt(state.t)) * 0.02;
                const r = 32;
                const col = consts.pico_sea;
                perlin.draw_generator(tt, r, r, col);

                //fonts.g_linssen.draw_text(0, "sine wave generated as time increases", 80, 215, consts.pico_black);
                fonts.g_linssen.draw_text(0, "y = sin(t)", 80, 215, consts.pico_black);

                if (clicked) {
                    // Carry over t so that the animations line up
                    self.scene = .{ .OscStackedCentral = .{ .t = state.t } };
                }
            },
            .OscStackedCentral => |*state| {
                if (!space_down) {
                    state.t += 1;
                }

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

                perlin.draw_generator(tt, r, r, col);
                perlin.draw_generator(t1, r * 0.5, r, consts.pico_red);
                perlin.draw_generator(t2, r * 0.25, r, consts.pico_green);

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

                if (clicked) {
                    self.scene = .{ .OscStackedTipTail = .{ .t = state.t } };
                }
            },
            .OscStackedTipTail => |*state| {
                if (!space_down) {
                    state.t += 1;
                }

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

                if (clicked) {
                    self.scene = .{ .OscStackedMovable = .{ .t = state.t } };
                }
            },
            .OscStackedMovable => |*state| {
                if (!space_down) {
                    state.t += 1;
                }

                //if (rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT)) {
                //x.small_offset = utils.g_mouse_screen.x / 60;
                if (rl.IsKeyDown(rl.KeyboardKey.KEY_UP)) {
                    state.small_offset -= 0.08 + 0.02;
                }
                if (rl.IsKeyDown(rl.KeyboardKey.KEY_DOWN)) {
                    state.small_offset += 0.08;
                }

                var cx = consts.screen_width_f * 0.3;
                var cy = consts.screen_height_f * 0.5;

                var tt = @as(f32, @floatFromInt(state.t)) * 0.02;
                const r = 32;
                const col = consts.pico_sea;
                var t1 = tt + 0.25 * 3.141;
                var t2 = tt + 0.55 * 3.141 + state.small_offset;

                rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), 32 * 0.25 - 0.5, consts.pico_green);
                rl.DrawCircleLines(@intFromFloat(cx), @intFromFloat(cy), 32 * 0.25 + 0.5, consts.pico_green);

                perlin.draw_generator(tt, r, r, col);
                perlin.draw_generator(t1, r * 0.5, r, consts.pico_red);

                perlin.draw_generator(t2, r * 0.25, r, consts.pico_green);

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

                if (clicked) {
                    self.scene = .{ .OscLandscapeSingle = .{
                        .t = 0,
                        .landscape = .{},
                    } };

                    g_shader_noise_dump = 0.5;
                    g_screenshake = 1.0;
                }
            },
            .OscLandscapeSingle => |*state| {
                state.t += 1;
                state.playing = space_down;
                if (state.playing) {
                    state.landscape.tick();
                }

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

                if (clicked) {
                    var rand = FroggyRand.init(1);
                    var landscapes = alloc.gpa.allocator().alloc(perlin.Landscape, 3) catch unreachable;
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

                    self.scene = .{ .OscLandscape = .{
                        .t = 0,
                        .landscapes = landscapes,
                    } };
                }
            },
            .OscLandscape => |*state| {
                var x = state;
                x.t += 1;
                for (x.landscapes) |*landscape| {
                    landscape.tick();
                }

                if (x.t > 180 and x.t < 500) {
                    x.landscapes[0].draw_circles = false;
                    x.landscapes[1].draw_circles = false;

                    x.landscapes[0].y0 = utils.dan_lerp(x.landscapes[0].y0, consts.screen_height_f * 0.35, 5.0);
                    x.landscapes[1].y0 = utils.dan_lerp(x.landscapes[1].y0, x.landscapes[0].y0, 12.0);
                }

                if (x.t > 500 and x.t < 800) {
                    x.landscapes[0].draw_circles = false;
                    x.landscapes[1].draw_circles = false;
                    x.landscapes[2].draw_circles = false;

                    x.landscapes[0].y0 = utils.dan_lerp(x.landscapes[1].y0, consts.screen_height_f * 0.5, 5.0);
                    x.landscapes[1].y0 = utils.dan_lerp(x.landscapes[1].y0, x.landscapes[0].y0, 5.0);
                    x.landscapes[2].y0 = utils.dan_lerp(x.landscapes[2].y0, x.landscapes[0].y0, 12.0);
                }
                if (state.t < 180) {
                    for (state.landscapes) |*landscape| {
                        landscape.draw();
                    }
                } else if (state.t < 600) {
                    var xx = [_]*perlin.Landscape{&state.landscapes[1]};
                    state.landscapes[0].draw();
                    state.landscapes[1].draw();
                    state.landscapes[0].draw_merged(&xx);
                    state.landscapes[2].draw();
                } else {
                    var xx = [_]*perlin.Landscape{ &state.landscapes[1], &state.landscapes[2] };
                    state.landscapes[0].draw();
                    state.landscapes[1].draw();
                    state.landscapes[2].draw();
                    state.landscapes[0].draw_merged(&xx);
                }

                if (clicked) {
                    self.scene = .{ .Trick2 = .{ .t = 0 } };
                }
            },
            .Trick2 => |*x| {
                x.t += 1;
                sprites.draw_blob_text("trick two", .{ .x = 100, .y = 100 });
                var styling = Styling{
                    .color = consts.pico_black,
                    .wavy = true,
                };
                var font_state = fonts.DrawTextState{};
                fonts.g_linssen.draw_text_state(x.t, "(making things round)", 90, 130, styling, &font_state);

                if (clicked) {
                    //var perlins = make_three_perlins();
                    //perlins[0].y0 = consts.screen_height_f * 0.5;
                    //perlins[1].y0 = consts.screen_height_f * 0.5;
                    //perlins[2].y0 = consts.screen_height_f * 0.5;

                    //self.scene = .{
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
                    var landscapes = alloc.gpa.allocator().alloc(perlin.Landscape, 3) catch unreachable;
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

                    self.scene = .{
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
                //const t_merge = 10000;
                //var perlin_1_and_2 = [2]*AnimatedPerlin{ &x.perlins[1], &x.perlins[2] };
                //x.perlins[0].draw_merged(&perlin_1_and_2, @min(t_merge, 1.0));

                x.t += 1;
                x.perlin.landscapes[0].tick();
                x.perlin.landscapes[1].tick();
                x.perlin.landscapes[2].tick();

                var tt: f32 = 0;

                if (x.t > 60) {
                    tt = @as(f32, @floatFromInt(x.t - 60)) * 0.005;
                    tt = std.math.pow(f32, tt, 1.5);
                }

                x.perlin.draw(@min(tt, 1.0));

                fonts.g_linssen.draw_text(0, "wrap onto a circle", 70, 210, consts.pico_black);
                fonts.g_linssen.draw_text(0, "place oscilators at equal spacing in [0,2pi]", 70, 220, consts.pico_black);

                if (clicked) {
                    g_screenshake = 0.5;
                    g_shader_noise_dump = 0.5;
                    self.scene = .{
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

                x.planet.draw();
                rl.DrawCircleLines(@intFromFloat(x.planet.world.pos.x), @intFromFloat(x.planet.world.pos.y), 1.0, consts.pico_blue);

                if (x.t < 120) {
                    fonts.g_linssen.draw_text(0, "new interpolation", 70, 210, consts.pico_black);
                } else {
                    fonts.g_linssen.draw_text(0, "r = r_0 + r_vary * sample(angle)", 70, 210, consts.pico_black);
                }

                if (clicked) {
                    var new_planet = x.planet;
                    //new_planet.world.pos.y += 40;
                    //new_planet.draw_oscs = false;
                    new_planet.draw_oscs_arrows = true;
                    var tree = .{
                        .angle = 0.75 * TAU,
                    };
                    self.scene = .{
                        .PlanetPropPos = .{
                            .t = 0,
                            .planet = new_planet,
                            .tree = tree,
                        },
                    };
                }
            },
            .PlanetPropPos => |*x| {
                x.planet.world.pos.y = utils.dan_lerp(x.planet.world.pos.y, consts.screen_height_f * 0.5 + 40, 15);

                x.t += 1;
                x.planet.world.tick();
                x.tree.tick(&x.planet);
                x.planet.draw();
                x.tree.draw(&x.planet);

                var c = x.planet.world.pos;
                var tp = x.tree.pos;
                _ = tp;
                rl.DrawLineV(c, x.tree.pos, consts.pico_sea);
                rl.DrawLineV(c, utils.add_v2(x.planet.world.pos, .{ .x = 10 }), consts.pico_sea);
                rl.DrawCircleSectorLines(c, 5.0, 180, 90, 8, consts.pico_sea);

                fonts.g_linssen.draw_text(0, "a", c.x + 4, c.y - 16, consts.pico_blue);

                fonts.g_linssen.draw_text(0, "sticking object to the surface", 50, 210, consts.pico_black);

                if (clicked) {
                    self.scene = .{
                        .PlanetPropTangent = .{
                            .t = 0,
                            .planet = x.planet,
                            .tree = x.tree,
                        },
                    };
                }
            },
            .PlanetPropTangent => |*x| {
                x.t += 1;
                x.planet.world.tick();
                x.tree.tick(&x.planet);
                x.planet.draw();
                x.tree.draw(&x.planet);

                var c = x.planet.world.pos;
                var tp = x.tree.pos;
                var p0 = x.planet.world.pos_on_surface(x.tree.angle + 0.04, 0.0);
                var p1 = x.planet.world.pos_on_surface(x.tree.angle - 0.04, 0.0);
                rl.DrawLineV(c, p0, consts.pico_sea);
                rl.DrawLineV(c, p1, consts.pico_sea);
                rl.DrawLineV(c, utils.add_v2(x.planet.world.pos, .{ .x = 10 }), consts.pico_sea);
                rl.DrawCircleSectorLines(c, 5.0, 180, 90, 8, consts.pico_sea);

                var normal = x.planet.world.sample_normal(x.tree.angle);
                var tangent: rl.Vector2 = .{ .x = -normal.y, .y = normal.x };

                utils.draw_arrow_p(tp, utils.add_v2(utils.scale_v2(40, tangent), tp), consts.pico_red, 8);
                utils.draw_arrow_p(tp, utils.add_v2(utils.scale_v2(40, normal), tp), consts.pico_green, 8);

                fonts.g_linssen.draw_text(0, "a + 0.01", c.x + 4, c.y - 16, consts.pico_blue);
                fonts.g_linssen.draw_text(0, "a - 0.01", c.x - 50, c.y - 16, consts.pico_blue);

                //fonts.g_linssen.draw_text(0, "layout", 70, 210, consts.pico_black);

                if (clicked) {
                    g_screenshake = 0.5;
                    g_shader_noise_dump = 0.5;
                    self.scene = .{
                        .OscSlam = .{
                            .t = 0,
                            .planet = x.planet,
                            .particles = std.ArrayList(Particle).init(alloc.gpa.allocator()),
                        },
                    };
                }
            },
            .OscSlam => |*state| {
                var x = state;
                if (!x.paused) {
                    x.ongoing_slam_offset_t += 1;
                    x.t = utils.dan_lerp(x.t, x.ongoing_slam_offset_t, 8.0);
                    x.player_state.t += 1;

                    var new_particles = std.ArrayList(Particle).init(alloc.gpa.allocator());
                    for (x.particles.items) |*particle| {
                        if (particle.tick(1)) {
                            new_particles.append(particle.*) catch unreachable;
                        }
                    }

                    x.particles.deinit();
                    x.particles = new_particles;
                } else {
                    if (space_down) {
                        x.paused = false;
                        x.just_slammed = false;
                        x.player_state.space_up_since_unpause = false;
                    }
                }

                if (!x.player_state.jumping) {
                    if (space_down and x.player_state.space_up_since_unpause) {
                        x.player_state.charging = true;
                    } else if (x.player_state.charging) {
                        x.player_state.jumping = true;
                        x.player_state.yvel = -7;
                        x.player_state.charging = false;
                    }

                    if (!space_down) {
                        x.player_state.space_up_since_unpause = true;
                    }
                } else {
                    x.player_state.yvel += 0.35;
                    if (x.player_state.yvel > 0.0) {
                        x.player_state.yvel += 0.1;
                    }
                    x.player_state.y_off += x.player_state.yvel;

                    if (x.player_state.y_off > 0) {
                        x.player_state.jumping = false;
                        x.player_state.yvel = 0;
                        x.player_state.y_off = 0;
                        g_screenshake = 0.25;
                        x.paused = true;
                        x.just_slammed = true;

                        x.ongoing_slam_offset_t = get_slam_target(x.t);

                        create_particles(&x.particles, @intFromFloat(x.t), utils.add_v2(x.player_state.last_pos, .{ .x = 4 * 2, .y = 10 * 2 + 4 }), 4, 2.0);
                    }
                }

                for (state.particles.items) |*part| {
                    part.draw();
                }
                var tt = state.t * 0.02;
                const r = 32;
                const col = consts.pico_sea;
                draw_generator_slam(&state.player_state, state.just_slammed, tt, r, r, col, 32);

                //fonts.g_linssen.draw_text(0, "sine wave generated as time increases", 80, 215, consts.pico_black);
                fonts.g_linssen.draw_text(0, "slamming and altering terrain ", 80, 215, consts.pico_black);

                if (clicked) {
                    g_screenshake = 0.5;
                    g_shader_noise_dump = 0.5;
                    var new_planet = state.planet;
                    //new_planet.world.pos.y -= 40;
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
                    self.scene = .{
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
                var create_rock = clicked;
                x.draw(create_rock);
                fonts.g_linssen.draw_text(0, "it's all coming together", 70, 210, consts.pico_black);
            },
            else => {
                // Todo
            },
        }
    }
};

pub const PlayerState = struct {
    t: i32 = 0,
    jumping: bool = false,
    charging: bool = false,
    y_off: f32 = 0,
    yvel: f32 = 0,
    last_pos: rl.Vector2 = .{},
    space_up_since_unpause: bool = false,
};

pub fn draw_generator_slam(player_state: *PlayerState, show_arrow: bool, theta: f32, r: f32, r_big: f32, col: rl.Color, xoff: f32) void {
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

    var frame: usize = 0;

    var pp = p_dotted_end;
    pp.y -= 20;
    pp.x -= 10;
    pp.y += player_state.y_off;

    if (show_arrow) {
        frame = 4;
    } else if (player_state.charging) {
        frame = 2;
    } else if (!player_state.jumping) {
        if (@mod(@divFloor(player_state.t, 6), 2) == 0) {
            frame = 0;
        } else {
            frame = 1;
        }
    } else {
        frame = 3;
    }

    sprites.g_sprites.draw_frame_scaled("char", frame, pp, 2, 2);
    player_state.last_pos = pp;

    if (show_arrow) {
        var s = std.math.sin(theta);
        var c = .{ .x = cx, .y = cy };
        var deriv0 = std.math.cos(theta);
        var deriv = deriv0;
        if (s > 0) {
            if (deriv < 0) {
                utils.draw_arrow_p(utils.add_v2(c, .{ .y = 0 }), utils.add_v2(c, .{ .x = 0, .y = 16 }), consts.pico_red, 6);
            } else {
                utils.draw_arrow_p(utils.add_v2(c, .{ .y = 0 }), utils.add_v2(c, .{ .x = 0, .y = 16 }), consts.pico_red, 6);
            }
        } else {
            if (deriv < 0) {
                utils.draw_arrow_p(utils.add_v2(c, .{ .y = -8 }), utils.add_v2(c, .{ .x = -16, .y = 8 }), consts.pico_red, 6);
            } else {
                utils.draw_arrow_p(utils.add_v2(c, .{ .y = -8 }), utils.add_v2(c, .{ .x = 16, .y = 8 }), consts.pico_red, 6);
            }
        }

        //if (deriv < 0) {
        //deriv = -deriv;
        //}
        deriv = -deriv;

        const len_2 = 16 * 16;

        var deriv_2 = deriv * deriv;
        var dx_2 = len_2 / (1 + deriv_2);

        var dx = std.math.sqrt(dx_2);
        if (deriv0 > 0) {
            dx = -dx;
        }

        var dy = deriv * dx;

        // Arrow up

        //var alpha = std.math.atan2(f32, 1.0, deriv);
        //const len = 16;
        //var aa: rl.Vector2 = .{ .x = std.math.cos(alpha) * len, .y = std.math.sin(alpha) * len };
        //var arrow_end = utils.add_v2(ab, aa);
        //utils.draw_arrow_p(ab, arrow_end, consts.pico_red, 4);

        var ab = utils.add_v2(pp, .{ .x = 10, .y = 32 });
        var arrow_end = utils.add_v2(ab, .{ .x = dx, .y = dy });
        utils.draw_arrow_p(ab, arrow_end, consts.pico_red, 4);
    }
}

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
        sprites.g_sprites.draw_frame_scaled_rotated("tree_small", 0, self.pos, 1, 1, .{ .x = 9, .y = 24.0 }, angle * 360.0 / TAU);
    }
};

pub const Rock = struct {
    pos: rl.Vector2,
    vel: rl.Vector2,
    r: f32,
    sides: i32,
    lifetime: ?i32 = null,

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
        if (self.lifetime) |l| {
            if (l == 0) {
                return false;
            }

            self.r *= 0.95;
            self.lifetime = l - 1;
        }

        var delta = utils.sub_v2(planet.world.pos, self.pos);
        var delta_norm = utils.norm(delta);
        var dist_2 = utils.mag2_v2(delta);

        var angle = std.math.atan2(f32, -delta.y, -delta.x);
        var sample = planet.world.sample(angle);
        var dist = std.math.sqrt(dist_2);
        if (dist < sample + self.r) {
            if (self.r > 2.0) {
                planet.world.slam(10 * self.r, angle);
            }
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

pub fn create_particles(particles: *std.ArrayList(Particle), t: i32, p_pos: rl.Vector2, n: usize, offset: f32) void {
    var rand = FroggyRand.init(0);

    for (0..n) |i| {
        var pos = p_pos;
        var theta = rand.gen_f32_uniform(.{ t, i }) * 3.141 * 2.0;
        var ox = offset * std.math.cos(theta);
        var oy = offset * std.math.sin(theta);
        pos.x += ox;
        pos.y += oy;

        var frame = rand.gen_usize_range(.{ t, i }, 0, particle_frames.len - 1);

        const speed_k = 0.01;
        const speed_k_x = 0.03;
        particles.append(.{
            .frame = frame,
            .pos = pos,
            .vel = .{ .x = ox * speed_k_x, .y = oy * speed_k },
        }) catch unreachable;
    }
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

const FinalSceneState = struct {
    t: i32,
    planet: Planet,
    rocks: std.ArrayList(Rock),
    trees: std.ArrayList(Tree),

    pub fn draw(self: *FinalSceneState, create_rock: bool) void {
        self.planet.world.pos.y = utils.dan_lerp(self.planet.world.pos.y, consts.screen_height_f * 0.5, 15);

        self.t += 1;
        self.planet.world.tick();

        var new_rocks = std.ArrayList(Rock).init(alloc.gpa.allocator());

        for (self.rocks.items) |*rock| {
            if (rock.tick(&self.planet)) {
                new_rocks.append(rock.*) catch unreachable;
            } else {
                if (rock.r > 2.0) {
                    g_screenshake = @max(g_screenshake, rock.r * 0.2);
                }

                if (rock.r > 3) {
                    var delta = utils.sub_v2(rock.pos, self.planet.world.pos);
                    var angle = std.math.atan2(f32, delta.y, delta.x);
                    for (0..8) |i| {
                        var rand = FroggyRand.init(self.t);
                        rand = rand.subrand(i);
                        var r = rand.gen_froggy("r", 0.2, 1.8, 2);
                        var pos_on_surface = self.planet.world.pos_on_surface(angle, 0.1 + r);

                        var vel_angle = angle + rand.gen_f32_range("a", -1.0, 1.0) * 0.1;
                        var spd = rand.gen_froggy("s", 0.3, 2.5, 2) * 1.25;
                        var vel: rl.Vector2 = .{ .x = std.math.cos(vel_angle) * spd, .y = std.math.sin(vel_angle) * spd };

                        new_rocks.append(.{
                            .pos = pos_on_surface,
                            .vel = vel,
                            .r = r,
                            .sides = rand.gen_i32_range("sides", 3, 8),
                            .lifetime = rand.gen_i32_range("life", 20, 60),
                        }) catch unreachable;
                    }
                }
            }
        }

        self.rocks.deinit();
        self.rocks = new_rocks;

        if (create_rock) {
            self.rocks.append(Rock.new(self.t)) catch unreachable;
        }

        for (self.trees.items) |*tree| {
            tree.tick(&self.planet);
        }
        self.planet.draw();

        for (self.trees.items) |*tree| {
            tree.draw(&self.planet);
        }
        for (self.rocks.items) |*rock| {
            rock.draw();
        }
    }
};
