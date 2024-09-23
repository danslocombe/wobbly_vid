const std = @import("std");

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub var temp_alloc = std.heap.ArenaAllocator.init(gpa.allocator());
