const std = @import("std");
const rl = @import("raylib");
const consts = @import("consts.zig");
const FroggyRand = @import("froggy_rand.zig").FroggyRand;
const Styling = @import("adlib.zig").Styling;

pub var g_argent: DanFont = undefined;
pub var g_argent_small: DanFont = undefined;
pub var g_argent_italic: DanFont = undefined;

pub var g_linssen: DanFont = undefined;
pub var g_monogram: DanFont = undefined;
pub var g_monogram_for_dialogue: DanFont = undefined;

pub var g_ui: DanFont = undefined;

pub fn load_fonts() void {
    g_argent = load_font("fonts/ArgentPixelCF-Regular.otf", 16);
    g_argent_small = load_font("fonts/ArgentPixelCF-Regular.otf", 12);
    g_argent_italic = load_font("fonts/ArgentPixelCF-Italic.otf", 16);

    g_linssen = load_font("fonts/linssen_m5x7.ttf", 12);
    g_monogram = load_font("fonts/monogram.ttf", 12);
    g_monogram_for_dialogue = load_font("fonts/monogram.ttf", 16);

    g_ui = load_font("fonts/CascadiaMono.ttf", 18);
}

pub const DrawTextState = struct {
    text_offset_x: f32 = 0,
    text_offset_y: f32 = 0,
};

pub const DanFont = struct {
    font: rl.Font,
    size: i32 = 16,

    pub fn measure(self: *DanFont, text: [:0]const u8) rl.Vector2 {
        return rl.MeasureTextEx(self.font, text, @floatFromInt(self.size), 1.0);
    }

    // Copied largely from DrawTextEx https://github.com/raysan5/raylib/blob/master/src/rtext.c
    pub fn draw_text(self: *DanFont, t: i32, text: [:0]const u8, x: f32, y: f32, col: rl.Color) void {
        var state = DrawTextState{};
        var styling = Styling{
            .color = col,
        };
        self.draw_text_state(t, text, x, y, styling, &state);
    }

    // Copied largely adapted from DrawTextEx https://github.com/raysan5/raylib/blob/master/src/rtext.c
    pub fn draw_text_state(self: *DanFont, t: i32, text: [:0]const u8, x: f32, y: f32, styling: Styling, state: *DrawTextState) void {
        var size = rl.TextLength(text);

        //var scaleFactor: f32 = 16.0 / @as(f32, @floatFromInt(self.size));
        const scaleFactor = 1;

        var i: usize = 0;

        while (i < size) {
            // Get next codepoint from byte string and glyph index in font
            var codepoint_byte_count: i32 = 0;
            var codepoint = rl.GetCodepointNext(&text[i], &codepoint_byte_count);

            if (codepoint == '\n') {
                state.text_offset_x = 0;
                state.text_offset_y += @floatFromInt(self.size);
            } else {
                if ((codepoint != ' ') and (codepoint != '\t')) {
                    var pos = .{ .x = x + state.text_offset_x, .y = y + state.text_offset_y };

                    if (styling.wavy) {
                        pos.y += std.math.sin((@as(f32, @floatFromInt(t)) + pos.x) * 0.1) * 2;
                    }

                    if (styling.jitter) {
                        var rand = FroggyRand.init(t).subrand(pos);
                        const k = 3;
                        const s = 2;
                        pos.x += rand.gen_froggy(0, -1, 1, k) * s;
                        pos.y += rand.gen_froggy(1, -1, 1, k) * s;
                    }

                    var col = styling.color;
                    if (styling.rainbow) {
                        // Note the -pos.x here
                        // We do this so that it looks like the colours are travelling forwards
                        // This means we have use modf to handle negative values in the mod.
                        var index_f: f32 = (@as(f32, @floatFromInt(t + 1000)) - pos.x) * 0.1;
                        const rtl_f: f32 = @floatFromInt(rainbow_text_colors.len);
                        var index_f_unit_range = std.math.modf(index_f / rtl_f).fpart;
                        var ii: usize = @intFromFloat(rtl_f * index_f_unit_range);
                        col = rainbow_text_colors[ii];
                    }

                    self.draw_codepoint(codepoint, pos, col);
                }

                var glyph_info = rl.GetGlyphInfo(self.font, codepoint);
                state.text_offset_x += @as(f32, @floatFromInt(glyph_info.advanceX)) * scaleFactor + 1.0;
            }

            i += @intCast(codepoint_byte_count);
        }
    }

    fn draw_codepoint(self: *DanFont, p_codepoint: c_int, p_pos: rl.Vector2, color: rl.Color) void {
        var codepoint = p_codepoint;
        var pos = p_pos;
        rl.DrawTextCodepoint(self.font, codepoint, pos, @floatFromInt(self.size), color);
    }
};

fn load_font(filename: [:0]const u8, size: i32) DanFont {
    // Rewrite from rl.LoadFont so we can pass in FONT_BITMAP and avoid anti-aliased fonts.
    var file_size: u32 = 0;
    var file_data = rl.LoadFileData(filename, &file_size);
    defer (rl.UnloadFileData(file_data));

    var font: rl.Font = undefined;
    font.baseSize = size;
    font.glyphCount = 95;
    font.glyphPadding = 0;
    font.glyphs = rl.LoadFontData(file_data, @intCast(file_size), size, null, 0, @intFromEnum(rl.FontType.FONT_BITMAP));
    font.glyphPadding = 4;

    var atlas = rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, font.baseSize, font.glyphPadding, 0);
    font.texture = rl.LoadTextureFromImage(atlas);

    for (0..@intCast(font.glyphCount)) |i| {
        rl.UnloadImage(font.glyphs[i].image);
        font.glyphs[i].image = rl.ImageFromImage(atlas, font.recs[i]);
    }

    rl.UnloadImage(atlas);

    return DanFont{
        .font = font,
        .size = size,
    };
}

pub fn draw_ui(text: [:0]const u8, x: f32, y: f32) void {
    var ww: f32 = @floatFromInt(rl.GetScreenWidth());
    var hh: f32 = @floatFromInt(rl.GetScreenHeight());
    rl.DrawText(text, @intFromFloat(x * ww), @intFromFloat(y * hh), 20, consts.pico_white);
}

const rainbow_text_colors = [_]rl.Color{
    //consts.pico_black
    consts.pico_blue,
    consts.pico_purple,
    consts.pico_leaf,

    consts.pico_brown,
    //consts.pico_darkgrey,
    //consts.pico_grey,
    //consts.pico_white,

    consts.pico_red,
    consts.pico_orange,
    consts.pico_yellow,
    consts.pico_green,

    consts.pico_sea,
    consts.pico_lilac,
    consts.pico_pink,
    //consts.pico_beige,
};
