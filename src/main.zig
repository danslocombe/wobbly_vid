const std = @import("std");
const rl = @import("raylib");

const FroggyRand = @import("froggy_rand.zig").FroggyRand;
const consts = @import("consts.zig");
const alloc = @import("alloc.zig");
const utils = @import("utils.zig");
const game_lib = @import("game.zig");

fn contains_arg(args: [][:0]u8, needle: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, needle)) {
            return true;
        }
    }

    return false;
}

pub fn main() anyerror!void {
    rl.SetConfigFlags(rl.ConfigFlags.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(640, 480, "Video");

    //rl.SetTargetFPS(144);
    rl.SetTargetFPS(60);

    const args = try std.process.argsAlloc(alloc.gpa.allocator());
    _ = args;
    //rl.SetConfigFlags(rl.ConfigFlags.FLAG_VSYNC_HINT);
    //rl.SetExitKey(rl.KeyboardKey.KEY_NULL);

    game_lib.particle_frames = load_frames("dust.png");
    var framebuffer = rl.LoadRenderTexture(consts.screen_width, consts.screen_height);

    var game = game_lib.Game{
        .particles = std.ArrayList(game_lib.Particle).init(alloc.gpa.allocator()),
        .particles_dead = std.bit_set.DynamicBitSet.initEmpty(alloc.gpa.allocator(), 4) catch unreachable,
    };

    while (!rl.WindowShouldClose()) {
        var mapping = utils.FrameBufferToScreenInfo.compute(&framebuffer.texture);

        {
            game.tick();

            // Draw game to framebuffer
            rl.BeginTextureMode(framebuffer);
            game.draw(&mapping);
            rl.EndTextureMode();
        }

        draw_framebuffer_to_screen(&framebuffer, &mapping);

        clear_temp_alloc();
    }
    rl.CloseWindow();
}

const add_v2 = utils.add_v2;
const scale_v2 = utils.scale_v2;
const sub_v2 = utils.sub_v2;
const dot = utils.dot;
const normalize = utils.normalize;
const mag_v2 = utils.mag_v2;
const mag2_v2 = utils.mag2_v2;

fn draw_framebuffer_to_screen(framebuffer: *rl.RenderTexture2D, mapping: *utils.FrameBufferToScreenInfo) void {
    rl.BeginDrawing();
    rl.ClearBackground(consts.pico_black);

    rl.DrawTexturePro(framebuffer.texture, mapping.source, mapping.destination, .{ .x = 0.0, .y = 0.0 }, 0.0, rl.WHITE);

    rl.DrawFPS(10, 10);
    rl.EndDrawing();
}

fn load_frames(filename: [*c]const u8) []rl.Texture {
    var image = rl.LoadImage(filename);
    defer (rl.UnloadImage(image));

    var frame_count: usize = @intCast(@divFloor(image.width, image.height));

    var frame_w = @divFloor(image.width, @as(i32, @intCast(frame_count)));

    var frames = alloc.gpa.allocator().alloc(rl.Texture2D, frame_count) catch unreachable;

    for (0..frame_count) |iu| {
        var i: i32 = @intCast(iu);
        var xoff: f32 = @floatFromInt(i * frame_w);
        var frame_image = rl.ImageFromImage(image, rl.Rectangle{ .x = xoff, .y = 0, .width = @floatFromInt(frame_w), .height = @floatFromInt(image.height) });
        defer (rl.UnloadImage(frame_image));

        frames[iu] = rl.LoadTextureFromImage(frame_image);
    }

    return frames;
}

pub fn clear_temp_alloc() void {
    _ = alloc.temp_alloc.reset(.{
        .retain_with_limit = 64 * 1024,
    });
}
