const std = @import("std");
const rl = @import("raylib");

const FroggyRand = @import("froggy_rand.zig").FroggyRand;
const consts = @import("consts.zig");
const alloc = @import("alloc.zig");
const utils = @import("utils.zig");
const game_lib = @import("game.zig");
const fonts = @import("fonts.zig");
const sprites = @import("sprites.zig");

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
    //rl.InitWindow(2560, 1440, "Video");
    //rl.ToggleBorderlessWindowed();
    rl.HideCursor();

    //rl.SetTargetFPS(144);
    rl.SetTargetFPS(60);

    rl.ToggleFullscreen();

    const args = try std.process.argsAlloc(alloc.gpa.allocator());
    _ = args;
    //rl.SetConfigFlags(rl.ConfigFlags.FLAG_VSYNC_HINT);
    //rl.SetExitKey(rl.KeyboardKey.KEY_NULL);

    fonts.load_fonts();
    sprites.g_sprites = sprites.SpriteManager.init();

    game_lib.particle_frames = load_frames("dust.png");
    var framebuffer = rl.LoadRenderTexture(consts.screen_width, consts.screen_height);

    var game = game_lib.Game.init();

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

var g_shader_time: i32 = 0;

fn draw_framebuffer_to_screen(p_framebuffer: *rl.RenderTexture2D, mapping: *utils.FrameBufferToScreenInfo) void {
    var framebuffer: rl.Texture = undefined;
    var unload_framebuffer = false;

    game_lib.g_shader_noise_dump *= 0.86;
    g_shader_time += 1;
    if (game_lib.g_shader_noise_dump > 0.01) {
        // What are we doing here?
        // Load the framebuffer into memory
        // Dump a load of random data into it
        // Load it back. Graphics!
        var image_framebuffer = rl.LoadImageFromTexture(p_framebuffer.texture);
        dump_noise(&image_framebuffer, g_shader_time, game_lib.g_shader_noise_dump);

        framebuffer = rl.LoadTextureFromImage(image_framebuffer);
        unload_framebuffer = true;

        rl.UnloadImage(image_framebuffer);
    } else {
        framebuffer = p_framebuffer.texture;
    }

    rl.BeginDrawing();
    rl.ClearBackground(consts.pico_black);

    rl.DrawTexturePro(framebuffer, mapping.source, mapping.destination, .{ .x = 0.0, .y = 0.0 }, 0.0, rl.WHITE);

    //rl.DrawFPS(10, 10);
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

fn dump_noise(framebuffer_in_memory: *rl.Image, t: i32, amp: f32) void {
    // Assert that we are in the pixel format we expect.
    if (framebuffer_in_memory.format != rl.PixelFormat.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
        return;
    }

    var rand = FroggyRand.init(t);
    var max_offset_bytes = framebuffer_in_memory.width * framebuffer_in_memory.height * 4;
    var count: usize = @intFromFloat(30 * amp);

    for (0..count) |i| {
        // Generate a position in the framebuffer memory and length
        var len = rand.gen_usize_range(i, 50 * 4, 150 * 4) * 8;
        var pos = rand.gen_usize_range(i, 0, @as(usize, @intCast(max_offset_bytes)) - len);
        // Shouldnt be needed with -len in above but keep to be safe.
        len = @min(len, @as(usize, @intCast(max_offset_bytes)) - len - 1);

        // We want an interesting pattern when we dump data
        // so we memset using a u64 instead of a single color or set of bytes.
        // Take our pos / len and convert as if framebuffer is an array of u64s.
        var pos_u64 = @divTrunc(pos, 8);
        var len_u64 = @divTrunc(len, 8);
        var data_ptr_u64: [*]align(1) u64 = @ptrCast(framebuffer_in_memory.data.?);
        var color_0 = consts.all_colors[rand.gen_usize_range(.{ i, "col_0" }, 0, consts.all_colors.len - 1)];
        var color_1 = consts.all_colors[rand.gen_usize_range(.{ i, "col_1" }, 0, consts.all_colors.len - 1)];

        var color_0_u64_ptr: *align(1) u64 = @ptrCast(&color_0);
        var color_1_u64_ptr: *align(1) u64 = @ptrCast(&color_1);

        var value: u64 = (color_0_u64_ptr.* << 8) | (color_1_u64_ptr.*);
        @memset(data_ptr_u64[pos_u64 .. pos_u64 + len_u64], value);
    }
}
