const std = @import("std");
const this_module = @This();

pub fn ArcObject(comptime T: type) !type {
    return struct {
        reference_count: usize,
        item_ptr: *T,
    };
}

pub fn ArcAllocator(comptime of_allocator: type) !type {
    return struct {
        const this = @This();
        of_allocator: of_allocator,

        reference_count: usize,
    };
}
