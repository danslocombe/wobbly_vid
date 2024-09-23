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

    pub fn init(seed: anytype) FroggyRand {
        return .{
            .seed = @as(u64, @intCast(seed)),
        };
    }

    pub fn subrand(self: FroggyRand, x: anytype) FroggyRand {
        var hasher = std.hash.Wyhash.init(0);
        var hash_val: u64 = 0;

        const T = @TypeOf(x);
        if (T == comptime_int) {
            hash_val = @intCast(x);
        } else {
            // We need deep to make sure that strings are properly hashed, not just using pointer address
            // as that is unstable.
            hash(&hasher, x, std.hash.Strategy.Deep);
            hash_val = @as(u64, hasher.final());
        }

        var new_seed = self.seed +% hash_val;
        return .{ .seed = new_seed };
    }

    pub fn gen(self: FroggyRand, x: anytype) u64 {
        var with_x = self.subrand(x);
        return split_mix_64(with_x.seed);
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

    pub fn gen_angle(self: FroggyRand, x: anytype) f32 {
        return self.gen_f32_uniform(x) * std.math.tau;
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

    /// Should be uniform in [min, max]
    pub fn gen_f32_range(self: FroggyRand, x: anytype, min: f32, max: f32) f32 {
        return min + self.gen_f32_uniform(x) * (max - min);
    }

    pub fn gen_f32_one_minus_one(self: FroggyRand, x: anytype) f32 {
        return self.gen_f32_uniform(x) * 2.0 - 1.0;
    }

    /// I dont know what a statistic is
    /// Approx normal dist https://en.wikipedia.org/wiki/Irwin%E2%80%93Hall_distribution
    pub fn gen_froggy(self: FroggyRand, x: anytype, min: f32, max: f32, n: u32) f32 {
        var sum: f32 = 0;
        var gen_min = min / @as(f32, @floatFromInt(n));
        var gen_max = max / @as(f32, @floatFromInt(n));

        for (0..n) |i| {
            sum += self.gen_f32_range(.{ x, i }, gen_min, gen_max);
        }

        return sum;
    }
};

//--------------------------------------------------------------
// Note: Below copypasted from std.hash to support comptime int / float
//--------------------------------------------------------------
//
/// Provides generic hashing for any eligible type.
/// Strategy is provided to determine if pointers should be followed or not.
pub fn hash(hasher: anytype, key: anytype, comptime strat: std.hash.Strategy) void {
    if (@typeInfo(@TypeOf(key)) == .ComptimeInt) {
        // Hacky
        var key_i32: i32 = @as(i32, @intCast(key));
        hash(hasher, key_i32, strat);
        return;
    }
    if (@typeInfo(@TypeOf(key)) == .ComptimeFloat) {
        // Hacky
        var key_f32: f32 = @as(f32, @intCast(key));
        hash(hasher, key_f32, strat);
        return;
    }

    const Key = @TypeOf(key);
    const Hasher = switch (@typeInfo(@TypeOf(hasher))) {
        .Pointer => |ptr| ptr.child,
        else => @TypeOf(hasher),
    };

    switch (@typeInfo(Key)) {
        .NoReturn,
        .Opaque,
        .Undefined,
        .Null,
        .Type,
        .Frame,
        => @compileError("unable to hash type " ++ @typeName(Key)),

        .ComptimeInt, .EnumLiteral => {
            // Dan, just cast to i32
            hash(hasher, @as(i32, @intCast(key)), strat);
        },

        .Float, .ComptimeFloat => {
            // Dan, oooh this is hacky.
            // Mult by 1000 and its prob fine?
            hash(hasher, @as(i32, @intFromFloat(key * 1000)), strat);
        },

        .Void => return,

        // Help the optimizer see that hashing an int is easy by inlining!
        // TODO Check if the situation is better after #561 is resolved.
        .Int => |int| switch (int.signedness) {
            .signed => hash(hasher, @as(@Type(.{ .Int = .{
                .bits = int.bits,
                .signedness = .unsigned,
            } }), @bitCast(key)), strat),
            .unsigned => {
                if (comptime std.meta.trait.hasUniqueRepresentation(Key)) {
                    @call(.always_inline, Hasher.update, .{ hasher, std.mem.asBytes(&key) });
                } else {
                    // Take only the part containing the key value, the remaining
                    // bytes are undefined and must not be hashed!
                    const byte_size = comptime std.math.divCeil(comptime_int, @bitSizeOf(Key), 8) catch unreachable;
                    @call(.always_inline, Hasher.update, .{ hasher, std.mem.asBytes(&key)[0..byte_size] });
                }
            },
        },

        .Bool => hash(hasher, @intFromBool(key), strat),
        .Enum => hash(hasher, @intFromEnum(key), strat),
        .ErrorSet => hash(hasher, @intFromError(key), strat),
        .AnyFrame, .Fn => hash(hasher, @intFromPtr(key), strat),

        .Pointer => @call(.always_inline, hashPointer, .{ hasher, key, strat }),

        .Optional => if (key) |k| hash(hasher, k, strat),

        .Array => hashArray(hasher, key, strat),

        .Vector => |info| {
            if (comptime std.meta.trait.hasUniqueRepresentation(Key)) {
                hasher.update(std.mem.asBytes(&key));
            } else {
                comptime var i = 0;
                inline while (i < info.len) : (i += 1) {
                    hash(hasher, key[i], strat);
                }
            }
        },

        .Struct => |info| {
            inline for (info.fields) |field| {
                // We reuse the hash of the previous field as the seed for the
                // next one so that they're dependant.
                hash(hasher, @field(key, field.name), strat);
            }
        },

        .Union => |info| {
            if (info.tag_type) |tag_type| {
                const tag = std.meta.activeTag(key);
                hash(hasher, tag, strat);
                inline for (info.fields) |field| {
                    if (@field(tag_type, field.name) == tag) {
                        if (field.type != void) {
                            hash(hasher, @field(key, field.name), strat);
                        }
                        // TODO use a labelled break when it does not crash the compiler. cf #2908
                        // break :blk;
                        return;
                    }
                }
                unreachable;
            } else @compileError("cannot hash untagged union type: " ++ @typeName(Key) ++ ", provide your own hash function");
        },

        .ErrorUnion => blk: {
            const payload = key catch |err| {
                hash(hasher, err, strat);
                break :blk;
            };
            hash(hasher, payload, strat);
        },
    }
}

pub fn hashPointer(hasher: anytype, key: anytype, comptime strat: std.hash.Strategy) void {
    const info = @typeInfo(@TypeOf(key));

    switch (info.Pointer.size) {
        .One => switch (strat) {
            .Shallow => hash(hasher, @intFromPtr(key), .Shallow),
            .Deep => hash(hasher, key.*, .Shallow),
            .DeepRecursive => hash(hasher, key.*, .DeepRecursive),
        },

        .Slice => {
            switch (strat) {
                .Shallow => {
                    hashPointer(hasher, key.ptr, .Shallow);
                },
                .Deep => hashArray(hasher, key, .Shallow),
                .DeepRecursive => hashArray(hasher, key, .DeepRecursive),
            }
            hash(hasher, key.len, .Shallow);
        },

        .Many,
        .C,
        => switch (strat) {
            .Shallow => hash(hasher, @intFromPtr(key), .Shallow),
            else => @compileError(
                \\ unknown-length pointers and C pointers cannot be hashed deeply.
                \\ Consider providing your own hash function.
            ),
        },
    }
}
pub fn hashArray(hasher: anytype, key: anytype, comptime strat: std.hash.Strategy) void {
    for (key) |element| {
        hash(hasher, element, strat);
    }
}
