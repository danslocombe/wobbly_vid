const std = @import("std");

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub var temp_alloc = std.heap.ArenaAllocator.init(gpa.allocator());
pub fn gpa_alloc_idk(comptime T: type, n: usize) []T {
    return gpa.allocator().alloc(T, n) catch {
        @panic("We aren't linux, Crashing on allocation failure");
    };
}
