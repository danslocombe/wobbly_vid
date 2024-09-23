const std = @import("std");

// Ported from https://github.com/danslocombe/froggy-rand/

fn split_mix_64(index: u64) u64 {
    // https://ziglang.org/documentation/master/#Wrapping-Operations
    var z = index +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return (z ^ (z >> 31));
}

pub const FroggyRand = struct {
    seed: u64,

    pub fn init(seed: u32) FroggyRand {
        return .{
            .seed = @as(u64, @intCast(seed)),
        };
    }

    pub fn gen(self: FroggyRand, x: anytype) u64 {
        var hasher = std.hash.Wyhash.init(0);
        // We need deep to make sure that strings are properly hashed, not just using pointer address
        // as that is unstable.
        std.hash.autoHashStrat(&hasher, x, std.hash.Strategy.Deep);
        const hash = @as(u64, hasher.final());
        return split_mix_64(self.seed +% hash);
    }

    pub fn gen_usize_range(self: FroggyRand, x: anytype, min: usize, max: usize) usize {
        const range = 1 + max - min;
        return min + @as(usize, @intCast(self.gen(x))) % range;
    }

    pub fn gen_i32_range(self: FroggyRand, x: anytype, min: i32, max: i32) i32 {
        const range = 1 + max - min;
        return min + @as(i32, @intCast(@as(usize, @intCast(self.gen(x))) % @as(usize, @intCast(range))));
    }

    pub fn gen_f32_uniform(self: FroggyRand, x: anytype) f32 {
        return @as(f32, @floatFromInt(self.gen_i32_range(x, 0, 1_000_000))) / 1_000_000;
    }

    pub fn shuffle(self: FroggyRand, x: anytype, xs: anytype) void {
        // Fisher-yates
        // See https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle#The_modern_algorithm
        for (0..(xs.len - 1)) |i| {
            var j = self.gen_usize_range(.{ x, i }, i, xs.len - 1);

            var value_at_i = xs[i];
            var value_at_j = xs[j];
            xs[j] = value_at_i;
            xs[i] = value_at_j;
        }
    }
};
