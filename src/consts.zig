const std = @import("std");
const rl = @import("raylib");

pub const screen_width = 320;
pub const screen_width_f = @as(f32, @floatFromInt(320));
pub const screen_height = 240;
pub const screen_height_f = @as(f32, @floatFromInt(240));

fn from_hex(s: []const u8) rl.Color {
    const r_str = s[0..2];
    const r = std.fmt.parseInt(u8, r_str, 16) catch 0;
    const g_str = s[2..4];
    const g = std.fmt.parseInt(u8, g_str, 16) catch 0;
    const b_str = s[4..6];
    const b = std.fmt.parseInt(u8, b_str, 16) catch 0;
    return rl.Color{
        .r = r,
        .g = g,
        .b = b,
        .a = 255,
    };
}

pub const pico_black = from_hex("000000");
pub const pico_blue = from_hex("1d2b53");
pub const pico_purple = from_hex("7e2553");
pub const pico_leaf = from_hex("7e2553");

pub const pico_brown = from_hex("ab5236");
pub const pico_darkgrey = from_hex("5f574f");
pub const pico_grey = from_hex("c2c3c7");
pub const pico_white = from_hex("fff1e8");

pub const pico_red = from_hex("ff004d");
pub const pico_orange = from_hex("ffa300");
pub const pico_yellow = from_hex("ffec27");
pub const pico_green = from_hex("00e436");

pub const pico_sea = from_hex("29adff");
pub const pico_lilac = from_hex("83769c");
pub const pico_pink = from_hex("ff77a8");
pub const pico_beige = from_hex("ffccaa");
