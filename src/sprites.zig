const std = @import("std");
const rl = @import("raylib");

const alloc = @import("alloc.zig");
//const console = @import("../console.zig");

pub var g_sprites: SpriteManager = undefined;

pub const SpriteManager = struct {
    frame_sprites: std.StringHashMap([]rl.Texture2D),

    pub fn init() SpriteManager {
        var frame_sprites = std.StringHashMap([]rl.Texture2D).init(alloc.gpa.allocator());

        frame_sprites.put("fnt_blob", load_frames(.{ .filename = "sprites/spr_font_blob_black.png", .frame_count = 26 })) catch unreachable;
        frame_sprites.put("fnt_blob_2", load_frames(.{ .filename = "sprites/spr_font_blob_black_2.png", .frame_count = 26 })) catch unreachable;
        frame_sprites.put("tree_small", load_frames(.{ .filename = "sprites/spr_tree_small.png", .frame_count = 2 })) catch unreachable;
        frame_sprites.put("char", load_frames(.{ .filename = "sprites/character_2.png", .frame_count = 6 })) catch unreachable;
        frame_sprites.put("cursor", load_frames(.{ .filename = "sprites/cursor.png", .frame_count = 1 })) catch unreachable;

        return .{
            .frame_sprites = frame_sprites,
        };
    }

    pub fn frame_count(self: *SpriteManager, name: []const u8) usize {
        var frames = self.frame_sprites.get(name).?;
        return frames.len;
    }

    pub fn draw(self: *SpriteManager, name: []const u8, pos: rl.Vector2) void {
        var m_sprite = self.sprites.get(name);
        if (m_sprite == null) {
            //console.err_fmt("Failed to find sprite '{s}'", .{name});
            m_sprite = self.sprites.get("sprite_missing");
        }

        var no_tint = rl.WHITE;
        rl.DrawTextureV(m_sprite.?, pos, no_tint);
    }

    pub fn draw_centered(self: *SpriteManager, name: []const u8, p_pos: rl.Vector2) void {
        var sprite = self.sprites.get(name).?;
        var pos = p_pos;
        pos.x -= @as(f32, @floatFromInt(sprite.width)) * 0.5;
        pos.y -= @as(f32, @floatFromInt(sprite.height)) * 0.5;
        var no_tint = rl.WHITE;
        rl.DrawTextureV(sprite, pos, no_tint);
    }

    pub fn draw_frame(self: *SpriteManager, name: []const u8, frame: usize, pos: rl.Vector2) void {
        var sprite = self.frame_sprites.get(name).?[frame];
        var no_tint = rl.WHITE;
        rl.DrawTextureV(sprite, pos, no_tint);
    }

    pub fn draw_frame_scaled(self: *SpriteManager, name: []const u8, frame: usize, pos: rl.Vector2, scale_x: f32, scale_y: f32) void {
        self.draw_frame_scaled_rotated(name, frame, pos, scale_x, scale_y, .{}, 0);
    }

    pub fn draw_frame_scaled_rotated(self: *SpriteManager, name: []const u8, p_frame: usize, pos: rl.Vector2, scale_x: f32, scale_y: f32, origin: rl.Vector2, rotation: f32) void {
        var m_sprite = self.frame_sprites.get(name);
        var frame = p_frame;
        if (m_sprite == null) {
            //console.err_fmt("Could not find sprite '{s}'", .{name});
            m_sprite = self.frame_sprites.get("sprite_missing");
            frame = 0;
        }

        var sprite = m_sprite.?[frame];

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

        var no_tint = rl.WHITE;
        rl.DrawTexturePro(sprite, rect, dest, origin, rotation, no_tint);
    }

    pub fn draw_frame_absolute_size(self: *SpriteManager, name: []const u8, frame: usize, pos: rl.Vector2, width: f32, height: f32, origin: rl.Vector2) void {
        var sprite = self.frame_sprites.get(name).?[frame];

        var rect = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = @as(f32, @floatFromInt(sprite.width)),
            .height = @as(f32, @floatFromInt(sprite.height)),
        };

        var dest = rl.Rectangle{
            .x = pos.x,
            .y = pos.y,
            .width = width,
            .height = height,
        };

        var no_tint = rl.WHITE;
        rl.DrawTexturePro(sprite, rect, dest, origin, 0, no_tint);
    }
};

const LoadFramesParams = struct {
    filename: [*c]const u8,
    frame_count: ?usize = null,
};

fn load_frames(params: LoadFramesParams) []rl.Texture {
    //console.print("Loading {s}\n", .{params.filename});
    var image = rl.LoadImage(params.filename);
    defer (rl.UnloadImage(image));

    var frame_count = params.frame_count;
    if (frame_count == null) {
        frame_count = @intCast(@divFloor(image.width, image.height));
    }

    var frame_w = @divFloor(image.width, @as(i32, @intCast(frame_count.?)));

    var frames = alloc.gpa_alloc_idk(rl.Texture2D, frame_count.?);

    for (0..frame_count.?) |iu| {
        var i: i32 = @intCast(iu);
        var xoff: f32 = @floatFromInt(i * frame_w);
        var frame_image = rl.ImageFromImage(image, rl.Rectangle{ .x = xoff, .y = 0, .width = @floatFromInt(frame_w), .height = @floatFromInt(image.height) });
        defer (rl.UnloadImage(frame_image));

        frames[iu] = rl.LoadTextureFromImage(frame_image);
    }

    //console.print("Loading done! Split into {} frames\n", .{frames.len});
    return frames;
}

pub var g_t: i32 = 0;

pub fn draw_blob_text(text: []const u8, p_pos: rl.Vector2) void {
    var pos = p_pos;
    for (text) |c| {
        var index: ?usize = null;
        if (c >= 'a' and c <= 'z') {
            index = @intCast(c - 'a');
        }
        if (c >= 'A' and c <= 'Z') {
            index = @intCast(c - 'A');
        }

        if (index) |i| {
            if (@mod(@divFloor(g_t, 8), 2) == 0) {
                g_sprites.draw_frame("fnt_blob", i, pos);
            } else {
                g_sprites.draw_frame("fnt_blob_2", i, pos);
            }
        }
        pos.x += 16;
    }
}
