//! **Fragile**, don't touch!
const RendererAllocator = @This();

const vk = @import("vulkan");

const std = @import("std");

callbacks: vk.AllocationCallbacks = undefined,
backing_allocator: std.mem.Allocator,

pub fn init(child_allocator: std.mem.Allocator) std.mem.Allocator.Error!*RendererAllocator {
    const self = try child_allocator.create(RendererAllocator);
    self.* = .{
        .backing_allocator = child_allocator,
        .callbacks = .{
            .p_user_data = @ptrCast(self),
            .pfn_allocation = vulkan.alloc,
            .pfn_reallocation = vulkan.realloc,
            .pfn_free = vulkan.free,
        },
    };
    return self;
}

pub fn deinit(self: *RendererAllocator) void {
    self.backing_allocator.destroy(self);
}

pub fn allocator(self: *RendererAllocator) std.mem.Allocator {
    return .{
        .ptr = @ptrCast(self),
        .vtable = &.{
            .alloc = rawAlloc,
            .resize = rawResize,
            .remap = rawRemap,
            .free = rawFree,
        },
    };
}

fn rawAlloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const self: *RendererAllocator = @ptrCast(@alignCast(context));
    return self.backing_allocator.rawAlloc(len, alignment, ret_addr);
}
fn rawResize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const self: *RendererAllocator = @ptrCast(@alignCast(context));
    return self.backing_allocator.rawResize(memory, alignment, new_len, ret_addr);
}
fn rawRemap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const self: *RendererAllocator = @ptrCast(@alignCast(context));
    return self.backing_allocator.rawRemap(memory, alignment, new_len, ret_addr);
}
fn rawFree(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    const self: *RendererAllocator = @ptrCast(@alignCast(context));
    self.backing_allocator.rawFree(memory, alignment, ret_addr);
}

const vulkan = struct {
    const Header = struct {
        size: usize,
        total_size: usize,
        offset: usize,
    };

    fn alloc(
        userdata: ?*anyopaque,
        size: usize,
        alignment: usize,
        _: vk.SystemAllocationScope,
    ) callconv(.c) ?*anyopaque {
        const self: *RendererAllocator = @ptrCast(@alignCast(userdata));
        const gpa = self.backing_allocator;

        const extra = @sizeOf(Header) + alignment;
        const total_size = size + extra;

        const memory = gpa.alignedAlloc(u8, .of(Header), total_size) catch return null;

        const base = @intFromPtr(memory.ptr);
        const aligned = std.mem.alignForward(usize, base + @sizeOf(Header), alignment);

        const header: *Header = @ptrFromInt(aligned - @sizeOf(Header));
        header.* = .{
            .size = size,
            .total_size = total_size,
            .offset = aligned - base,
        };

        return @ptrFromInt(aligned);
    }

    fn realloc(
        userdata: ?*anyopaque,
        old_memory: ?*anyopaque,
        new_size: usize,
        alignment: usize,
        scope: vk.SystemAllocationScope,
    ) callconv(.c) ?*anyopaque {
        if (old_memory == null) return alloc(userdata, new_size, alignment, scope);

        if (new_size == 0) {
            free(userdata, old_memory);
            return null;
        }

        const old_ptr: [*]u8 = @ptrCast(old_memory.?);
        const header: *Header = @ptrFromInt(@intFromPtr(old_ptr) - @sizeOf(Header));

        const new_memory = alloc(
            userdata,
            new_size,
            alignment,
            scope,
        ) orelse return null;

        @memcpy(@as([*]u8, @ptrCast(new_memory))[0..@min(header.size, new_size)], old_ptr[0..@min(header.size, new_size)]);

        free(userdata, old_memory);

        return new_memory;
    }

    fn free(userdata: ?*anyopaque, memory: ?*anyopaque) callconv(.c) void {
        if (memory == null) return;

        const self: *RendererAllocator = @ptrCast(@alignCast(userdata));
        const gpa = self.backing_allocator;

        const ptr: [*]u8 = @ptrCast(memory.?);

        const header: *Header = @ptrFromInt(@intFromPtr(ptr) - @sizeOf(Header));

        const original: [*]u8 = ptr - header.offset;

        gpa.rawFree(original[0..header.total_size], .of(Header), @returnAddress());
    }
};
