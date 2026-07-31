const Renderer = @This();

const builtin = @import("builtin");

const std = @import("std");
const vk = @import("vulkan");

const DynLib = @import("DynLib.zig");
const Window = @import("Window.zig");

const Allocator = @import("Renderer/Allocator.zig");
const Instance = @import("Renderer/Instance.zig");
const DebugMessenger = @import("Renderer/DebugMessenger.zig");
const Surface = @import("Renderer/Surface.zig");
const PhysicalDevice = @import("Renderer/PhysicalDevice.zig");
const Device = @import("Renderer/Device.zig");
const Swapchain = @import("Renderer/Swapchain.zig");
const CommandHandler = @import("Renderer/CommandHandler.zig");
const Buffer = @import("Renderer/Buffer.zig");

pub const Pipeline = @import("Renderer/Pipeline.zig");
pub const ShaderObject = @import("Renderer/ShaderObject.zig");

gpa_impl: *Allocator,
gpa: std.mem.Allocator,

dynlib: DynLib,

vkb: vk.BaseWrapper,
instance: Instance,
debug_messenger: DebugMessenger,
surface: Surface,
physical_device: PhysicalDevice,
device: Device,
// vma: Vma,
swapchain: Swapchain,
command_handler: CommandHandler,

const libvulkan = switch (builtin.os.tag) {
    .windows => "vulkan-1.dll",
    .linux, .freebsd, .netbsd, .openbsd => "libvulkan.so.1",
    .macos => "libvulkan.1.dylib",
    else => @compileError("unsupported platform"),
};

const debug_instance_extensions: []const [*:0]const u8 = if (builtin.mode == .Debug)
    &.{"VK_EXT_debug_utils"}
else
    &.{};

const layers: []const [*:0]const u8 = if (builtin.mode == .Debug)
    &.{"VK_LAYER_KHRONOS_validation"}
else
    &.{};

pub fn init(allocator: std.mem.Allocator, window: *Window) !Renderer {
    const platform_extensions: []const [*:0]const u8 = switch (builtin.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd => switch (window.inner) {
            .wayland => &.{
                vk.extensions.khr_surface.name,
                vk.extensions.khr_wayland_surface.name,
            },
            .x11 => &.{
                vk.extensions.khr_surface.name,
                vk.extensions.khr_xcb_surface.name,
            },
        },
        .windows => &.{
            vk.extensions.khr_surface.name,
            vk.extensions.khr_win_32_surface.name,
        },
        .macos => &.{
            vk.extensions.khr_surface.name,
            "VK_MVK_macos_surface",
        },
        else => &.{},
    };

    const device_extensions: []const [*:0]const u8 = &.{
        vk.extensions.khr_swapchain.name,
        vk.extensions.ext_shader_object.name,
    };

    const gpa_impl = try Allocator.init(allocator);
    errdefer allocator.destroy(gpa_impl);
    const gpa = gpa_impl.allocator();

    var extensions: std.ArrayList([*:0]const u8) = try .initCapacity(gpa, debug_instance_extensions.len + 4);
    defer extensions.deinit(gpa);
    extensions.appendSliceAssumeCapacity(debug_instance_extensions);
    extensions.appendSliceAssumeCapacity(platform_extensions);

    var dynlib: DynLib = try .open(libvulkan);
    const getInstanceProcAddr = dynlib.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse return error.DynlibLookup;

    const vkb: vk.BaseWrapper = .load(getInstanceProcAddr);

    const instance: Instance = try .init(gpa, vkb, layers, extensions.items);
    errdefer instance.deinit(gpa);

    const debug_messenger: DebugMessenger = try .init(gpa, instance);
    errdefer debug_messenger.deinit(gpa, instance);

    const surface: Surface = try .init(gpa, instance, window);
    errdefer surface.deinit(gpa, instance);

    const physical_device: PhysicalDevice = try .pick(gpa, instance, surface);
    const device: Device = try .init(gpa, instance, physical_device, device_extensions);
    errdefer device.deinit(gpa);

    var swapchain: Swapchain = undefined;
    try swapchain.create(gpa, instance, surface, physical_device, device, window.size);
    errdefer swapchain.deinit(gpa, device);

    const command_handler: CommandHandler = try .init(gpa, physical_device, device);
    errdefer command_handler.deinit(gpa, device);

    return .{
        .gpa_impl = gpa_impl,
        .gpa = gpa,

        .dynlib = dynlib,

        .vkb = vkb,
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
        .command_handler = command_handler,
    };
}

pub fn deinit(self: *Renderer) void {
    const gpa = self.gpa;
    const instance = self.instance;
    const device = self.device;

    device.proxy.deviceWaitIdle() catch unreachable;

    self.command_handler.deinit(gpa, device);
    self.swapchain.deinit(gpa, device);
    device.deinit(gpa);
    self.surface.deinit(gpa, instance);
    self.debug_messenger.deinit(gpa, instance);
    instance.deinit(gpa);
    self.gpa_impl.deinit();

    self.dynlib.close();
    self.* = undefined;
}

fn getFrame(self: Renderer) CommandHandler.FrameData {
    return self.command_handler.frames[self.command_handler.frame_index % CommandHandler.frames_in_flight];
}

pub fn acquire(self: *Renderer, size: Window.Size) !void {
    const device = self.device;
    const swapchain = &self.*.swapchain;
    const frame = self.getFrame();

    _ = try device.proxy.waitForFences(&.{frame.in_flight_fence}, .true, std.math.maxInt(u64));
    try device.proxy.resetFences(&.{frame.in_flight_fence});

    swapchain.drain(self.gpa, device, self.command_handler.frame_index);

    const result = device.wrapper.dispatch.vkAcquireNextImageKHR.?(
        device.handle,
        swapchain.handle,
        std.math.maxInt(u64),
        frame.image_available,
        .null_handle,
        &swapchain.image_index,
    );
    if (result == .error_out_of_date_khr) try self.resize(size);

    try device.proxy.resetCommandBuffer(frame.command_buffer, .{});

    try self.command_handler.begin(self.device, swapchain.*);
}

pub fn submit(self: *Renderer, size: Window.Size) !void {
    const device = self.device;
    const swapchain = self.swapchain;
    const frame = self.getFrame();

    try self.command_handler.end(device, swapchain);

    const wait_semaphores: []const vk.Semaphore = &.{
        frame.image_available,
    };

    const signal_semaphores: []const vk.Semaphore = &.{
        swapchain.finished[swapchain.image_index],
    };

    const wait_stages: []const vk.PipelineStageFlags = &.{
        .{ .color_attachment_output_bit = true },
    };

    const submit_info: vk.SubmitInfo = .{
        .command_buffer_count = 1,
        .p_command_buffers = &.{frame.command_buffer},
        .wait_semaphore_count = @intCast(wait_semaphores.len),
        .p_wait_semaphores = wait_semaphores.ptr,
        .signal_semaphore_count = @intCast(signal_semaphores.len),
        .p_signal_semaphores = signal_semaphores.ptr,
        .p_wait_dst_stage_mask = wait_stages.ptr,
    };

    try device.proxy.queueSubmit(device.graphics_queue, &.{submit_info}, frame.in_flight_fence);

    const present_info: vk.PresentInfoKHR = .{
        .wait_semaphore_count = @intCast(signal_semaphores.len),
        .p_wait_semaphores = signal_semaphores.ptr,
        .swapchain_count = 1,
        .p_swapchains = &.{swapchain.handle},
        .p_image_indices = &.{swapchain.image_index},
    };

    _ = device.proxy.queuePresentKHR(device.graphics_queue, &present_info) catch |err| switch (err) {
        error.OutOfDateKHR => try self.resize(size),
        else => return err,
    };

    self.command_handler.frame_index += 1;
}

pub fn resize(self: *Renderer, size: Window.Size) !void {
    if (size.width == 0 or size.height == 0) return;
    if (size.width == self.swapchain.extent.width and size.height == self.swapchain.extent.height) return;

    try self.swapchain.recreate(
        self.gpa,
        self.instance,
        self.surface,
        self.physical_device,
        self.device,
        size,
        self.command_handler.frame_index,
    );
}

pub fn bindPipeline(self: Renderer, pipeline: Pipeline) void {
    const device = self.device;
    const frame = self.getFrame();
    device.proxy.cmdBindPipeline(frame.command_buffer, .graphics, pipeline.handle);
}

// pub const ShaderBinding = struct {
//     vertex: ShaderObject = .{ .handle = .null_handle, .stage = .vertex },
//     tessellation_control: ShaderObject = .{ .handle = .null_handle, .stage = .tessellation_control },
//     tessellation_evaluation: ShaderObject = .{ .handle = .null_handle, .stage = .tessellation_evaluation },
//     geometry: ShaderObject = .{ .handle = .null_handle, .stage = .geometry },
//     fragment: ShaderObject = .{ .handle = .null_handle, .stage = .fragment },
// };

pub fn bindShader(self: Renderer, shader_object: ShaderObject) void {
    // const shader_count = std.meta.fields(ShaderBinding).len;

    // var handles: [shader_count]vk.ShaderEXT = undefined;
    // var stages: [shader_count]ShaderObject.Stage = undefined;

    // inline for (std.meta.fields(ShaderBinding), 0..) |field, i| {
    //     const shader: ShaderObject = @field(shader_binding, field.name);
    //     handles[i] = shader.handle;
    //     stages[i] = if (shader.handle != .null_handle) shader.stage else ShaderObject.Stage.none;
    // }

    const device = self.device;
    const frame = self.getFrame();
    device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{@bitCast(@intFromEnum(shader_object.stage))}, &.{shader_object.handle});
    // viewport
    device.proxy.cmdSetViewportWithCount(
        frame.command_buffer,
        &.{.{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swapchain.extent.width),
            .height = @floatFromInt(self.swapchain.extent.height),
            .min_depth = 0.0,
            .max_depth = 1.0,
        }},
    );

    // scissor
    device.proxy.cmdSetScissorWithCount(
        frame.command_buffer,
        &.{.{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.extent,
        }},
    );

    // input assembly
    device.proxy.cmdSetPrimitiveTopology(
        frame.command_buffer,
        .triangle_list,
    );

    device.proxy.cmdSetPrimitiveRestartEnable(
        frame.command_buffer,
        .false,
    );

    // vertex input (empty)
    device.proxy.cmdSetVertexInputEXT(
        frame.command_buffer,
        null,
        null,
    );

    // rasterizer
    device.proxy.cmdSetRasterizerDiscardEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetPolygonModeEXT(
        frame.command_buffer,
        .fill,
    );

    device.proxy.cmdSetCullMode(
        frame.command_buffer,
        .{},
    );

    device.proxy.cmdSetFrontFace(
        frame.command_buffer,
        .counter_clockwise,
    );

    device.proxy.cmdSetDepthBiasEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetDepthClampEnableEXT(
        frame.command_buffer,
        .false,
    );

    // multisampling
    device.proxy.cmdSetRasterizationSamplesEXT(
        frame.command_buffer,
        .{ .@"1_bit" = true },
    );

    device.proxy.cmdSetSampleMaskEXT(
        frame.command_buffer,
        .{ .@"1_bit" = true },
        &.{0xffffffff},
    );

    device.proxy.cmdSetAlphaToCoverageEnableEXT(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetAlphaToOneEnableEXT(
        frame.command_buffer,
        .false,
    );

    // depth/stencil
    device.proxy.cmdSetDepthTestEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetDepthWriteEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetDepthCompareOp(
        frame.command_buffer,
        .less,
    );

    device.proxy.cmdSetDepthBoundsTestEnable(
        frame.command_buffer,
        .false,
    );

    device.proxy.cmdSetStencilTestEnable(
        frame.command_buffer,
        .false,
    );

    // blending
    device.proxy.cmdSetColorBlendEnableEXT(
        frame.command_buffer,
        0,
        &.{.true},
    );

    device.proxy.cmdSetColorBlendEquationEXT(
        frame.command_buffer,
        0,
        &.{.{
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
        }},
    );

    device.proxy.cmdSetColorWriteMaskEXT(
        frame.command_buffer,
        0,
        &.{.{
            .r_bit = true,
            .g_bit = true,
            .b_bit = true,
            .a_bit = true,
        }},
    );

    device.proxy.cmdSetLogicOpEnableEXT(
        frame.command_buffer,
        .false,
    );
}

/// Creates a mesh type with compile-time generated vertex input layout.
///
/// `streams` defines the vertex buffer streams used by the mesh.
/// Each stream becomes a Vulkan vertex binding and its fields become attributes.
///
/// `IndexType` defines the index buffer type (`u8`, `u16`, or `u32`).
/// Use `null` for a non-indexed mesh.
pub fn Mesh(comptime streams: []const type, opt_index_type: ?type) type {
    const VertexData = init: {
        var field_types: [streams.len]type = undefined;
        for (&field_types, streams) |*t, VertexType| {
            t.* = []const VertexType;
        }
        break :init @Tuple(&field_types);
    };

    const has_indices = if (opt_index_type) |IndexType| switch (IndexType) {
        u8, u16, u32 => true,
        else => @compileError(
            "expected index type u8, u16, u32, or null, found " ++ @typeName(IndexType),
        ),
    } else false;

    const IndexType = opt_index_type orelse u0;

    return struct {
        const Self = @This();

        buffers: [streams.len]Buffer,
        index_buffer: if (has_indices) Buffer else void,

        count: u32, // vertex or index count

        pub const bindings: [streams.len]vk.VertexInputBindingDescription2EXT = bindings: {
            var descriptions: [streams.len]vk.VertexInputBindingDescription2EXT = undefined;
            for (&descriptions, streams, 0..) |*description, VertexType, i| {
                description.* = .{
                    .binding = i,
                    .stride = @sizeOf(VertexType),
                    .input_rate = .vertex,
                    .divisor = 1,
                };
            }

            break :bindings descriptions;
        };

        const attribute_count = count: {
            var count: usize = 0;
            for (streams) |VertexType| count += std.meta.fields(VertexType).len;
            break :count count;
        };

        pub const attributes: [attribute_count]vk.VertexInputAttributeDescription2EXT = attributes: {
            var descriptions: [attribute_count]vk.VertexInputAttributeDescription2EXT = undefined;

            var attribute_index: usize = 0;

            for (streams, 0..) |VertexType, binding| {
                for (std.meta.fields(VertexType)) |field| {
                    descriptions[attribute_index] = .{
                        .location = attribute_index,
                        .binding = binding,
                        .format = formatOf(field.type),
                        .offset = @offsetOf(VertexType, field.name),
                    };

                    attribute_index += 1;
                }
            }
            break :attributes descriptions;
        };

        pub const InitOptions = struct {
            vertices: VertexData,
            indices: []const IndexType = &.{},
        };

        pub fn init(renderer: Renderer, options: InitOptions) !Self {
            var buffers: [streams.len]Buffer = undefined;
            inline for (streams, 0..) |T, i| {
                buffers[i] = try .init(T, renderer.gpa, renderer.physical_device, renderer.device, .vertex, options.vertices[i]);
            }

            const index_buffer = if (has_indices) try Buffer.init(IndexType, renderer.gpa, renderer.physical_device, renderer.device, .index, options.indices) else void{};

            const count: u32 = @truncate(if (has_indices) options.indices.len else options.vertices[0].len);

            return .{ .buffers = buffers, .index_buffer = index_buffer, .count = count };
        }

        pub fn deinit(self: Self, renderer: Renderer) void {
            if (has_indices) self.index_buffer.deinit(renderer.gpa, renderer.device);
            for (self.buffers) |buffer| buffer.deinit(renderer.gpa, renderer.device);
        }

        pub fn bind(self: Self, renderer: Renderer) void {
            const frame = renderer.getFrame();
            renderer.device.proxy.cmdSetVertexInputEXT(
                frame.command_buffer,
                bindings[0..],
                attributes[0..],
            );

            var handles: [streams.len]vk.Buffer = undefined;
            for (&handles, self.buffers) |*handle, buffer| {
                handle.* = buffer.handle;
            }

            const offsets: [streams.len]vk.DeviceSize = @splat(0);

            renderer.device.proxy.cmdBindVertexBuffers(
                frame.command_buffer,
                0,
                &handles,
                &offsets,
            );

            if (has_indices) renderer.device.proxy.cmdBindIndexBuffer(
                frame.command_buffer,
                self.index_buffer.handle,
                0,
                switch (IndexType) {
                    u8 => .uint8,
                    u16 => .uint16,
                    u32 => .uint32,
                    else => unreachable,
                },
            );
        }

        pub fn draw(self: Self, renderer: Renderer) void {
            const frame = renderer.getFrame();
            if (has_indices) {
                renderer.device.proxy.cmdDrawIndexed(frame.command_buffer, self.count, 1, 0, 0, 0);
            } else {
                renderer.device.proxy.cmdDraw(frame.command_buffer, self.count, 1, 0, 0);
            }
        }

        fn formatOf(comptime T: type) vk.Format {
            return switch (@typeInfo(T)) {
                .float => switch (@bitSizeOf(T)) {
                    32 => .r32_sfloat,
                    64 => .r64_sfloat,
                    else => @compileError("unsupported float size"),
                },
                .array => |array| {
                    if (array.child != f32) {
                        @compileError("unly f32 arrays are supported");
                    }

                    return switch (array.len) {
                        2 => .r32g32_sfloat,
                        3 => .r32g32b32_sfloat,
                        4 => .r32g32b32a32_sfloat,
                        else => @compileError("unsupported vector size"),
                    };
                },

                else => @compileError("unsupported vertex attribute type"),
            };
        }
    };
}
