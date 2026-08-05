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
const ShaderObject = @import("Renderer/ShaderObject.zig");
const Buffer = @import("Renderer/Buffer.zig");

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
                vk.extensions.khr_xlib_surface.name,
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

pub fn submit(self: *Renderer, frame: Frame) !void {
    const device = self.device;
    const swapchain = self.swapchain;
    const frame_data = self.command_handler.frames[self.command_handler.frame_index % CommandHandler.frames_in_flight];

    const wait_semaphores: []const vk.Semaphore = &.{
        frame_data.image_available,
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

    try device.proxy.queueSubmit(device.graphics_queue, &.{submit_info}, frame_data.in_flight_fence);

    const present_info: vk.PresentInfoKHR = .{
        .wait_semaphore_count = @intCast(signal_semaphores.len),
        .p_wait_semaphores = signal_semaphores.ptr,
        .swapchain_count = 1,
        .p_swapchains = &.{swapchain.handle},
        .p_image_indices = &.{swapchain.image_index},
    };

    _ = device.proxy.queuePresentKHR(device.graphics_queue, &present_info) catch |err| switch (err) {
        error.OutOfDateKHR => {},
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

pub const Frame = struct {
    device: Device,
    image: vk.Image,
    command_buffer: vk.CommandBuffer,

    pub const BeginOptions = struct {
        clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    };

    pub fn begin(renderer: *Renderer, size: Window.Size, options: BeginOptions) !Frame {
        const device = renderer.device;
        const swapchain = &renderer.swapchain;

        try renderer.resize(size);

        const frame = renderer.command_handler.frames[renderer.command_handler.frame_index % CommandHandler.frames_in_flight];

        _ = try device.proxy.waitForFences(
            &.{frame.in_flight_fence},
            .true,
            std.math.maxInt(u64),
        );

        try device.proxy.resetFences(&.{frame.in_flight_fence});

        swapchain.drain(
            renderer.gpa,
            device,
            renderer.command_handler.frame_index,
        );

        const result = device.wrapper.dispatch.vkAcquireNextImageKHR.?(
            device.handle,
            swapchain.handle,
            std.math.maxInt(u64),
            frame.image_available,
            .null_handle,
            &swapchain.image_index,
        );

        if (result == .error_out_of_date_khr or result == .suboptimal_khr) {
            try renderer.resize(size);
            return error.SwapchainOutOfDate;
        }

        const image = swapchain.images[swapchain.image_index];

        try device.proxy.resetCommandBuffer(
            frame.command_buffer,
            .{},
        );

        try device.proxy.beginCommandBuffer(
            frame.command_buffer,
            &.{},
        );

        const color_barrier = vk.ImageMemoryBarrier{
            .src_access_mask = .{},
            .dst_access_mask = .{
                .color_attachment_write_bit = true,
            },
            .old_layout = .undefined,
            .new_layout = .color_attachment_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresource_range = .{
                .aspect_mask = .{
                    .color_bit = true,
                },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        device.proxy.cmdPipelineBarrier(
            frame.command_buffer,
            .{ .top_of_pipe_bit = true },
            .{ .color_attachment_output_bit = true },
            .{},
            null,
            null,
            &.{color_barrier},
        );

        device.proxy.cmdSetViewportWithCount(
            frame.command_buffer,
            &.{.{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(swapchain.extent.width),
                .height = @floatFromInt(swapchain.extent.height),
                .min_depth = 0,
                .max_depth = 1,
            }},
        );

        device.proxy.cmdSetScissorWithCount(
            frame.command_buffer,
            &.{.{
                .offset = .{ .x = 0, .y = 0 },
                .extent = swapchain.extent,
            }},
        );

        const clear_color: vk.ClearValue = .{
            .color = .{
                .float_32 = options.clear_color,
            },
        };

        const clear_depth: vk.ClearValue = .{
            .depth_stencil = .{
                .depth = 1.0,
                .stencil = 0,
            },
        };

        const color_attachment: *const vk.RenderingAttachmentInfo = &.{
            .image_view = swapchain.image_views[swapchain.image_index],
            .image_layout = .color_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = clear_color,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
        };

        const depth_attachment: *const vk.RenderingAttachmentInfo = &.{
            .image_view = swapchain.depth.image_view,
            .image_layout = .depth_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = clear_depth,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
        };

        const rendering_info: *const vk.RenderingInfo = &.{
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = swapchain.extent,
            },
            .layer_count = 1,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(color_attachment),
            .p_depth_attachment = depth_attachment,
            .view_mask = 0,
        };

        device.proxy.cmdBeginRendering(
            frame.command_buffer,
            rendering_info,
        );

        device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .vertex_bit = true }}, null);
        device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .tessellation_control_bit = true }}, null);
        device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .tessellation_evaluation_bit = true }}, null);
        device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .geometry_bit = true }}, null);
        device.proxy.cmdBindShadersEXT(frame.command_buffer, &.{.{ .fragment_bit = true }}, null);

        return .{
            .device = device,
            .image = image,
            .command_buffer = frame.command_buffer,
        };
    }

    pub fn end(self: Frame) !void {
        const device = self.device;
        const command_buffer = self.command_buffer;

        device.proxy.cmdEndRendering(command_buffer);

        const color_to_present: vk.ImageMemoryBarrier = .{
            .src_access_mask = .{ .color_attachment_write_bit = true },
            .dst_access_mask = .{},
            .old_layout = .color_attachment_optimal,
            .new_layout = .present_src_khr,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = self.image,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        device.proxy.cmdPipelineBarrier(
            command_buffer,
            .{ .color_attachment_output_bit = true },
            .{},
            .{},
            null,
            null,
            &.{color_to_present},
        );

        try device.proxy.endCommandBuffer(command_buffer);
    }

    pub fn bindDefaultState(self: Frame) void {
        const device = self.device;
        const command_buffer = self.command_buffer;

        // rasterizer
        device.proxy.cmdSetRasterizerDiscardEnable(command_buffer, .false);

        device.proxy.cmdSetPolygonModeEXT(command_buffer, .fill);

        device.proxy.cmdSetCullMode(
            command_buffer,
            .{ .back_bit = true },
        );
        device.proxy.cmdSetFrontFace(command_buffer, .counter_clockwise);

        device.proxy.cmdSetDepthBiasEnable(command_buffer, .false);

        device.proxy.cmdSetDepthClampEnableEXT(command_buffer, .false);

        // multisampling
        device.proxy.cmdSetRasterizationSamplesEXT(
            command_buffer,
            .{ .@"1_bit" = true },
        );

        device.proxy.cmdSetSampleMaskEXT(
            command_buffer,
            .{ .@"1_bit" = true },
            &.{0xffffffff},
        );

        device.proxy.cmdSetAlphaToCoverageEnableEXT(command_buffer, .false);

        device.proxy.cmdSetAlphaToOneEnableEXT(command_buffer, .false);

        // depth/stencil
        device.proxy.cmdSetDepthTestEnable(command_buffer, .true);
        device.proxy.cmdSetDepthWriteEnable(command_buffer, .true);
        device.proxy.cmdSetDepthCompareOp(command_buffer, .less);
        device.proxy.cmdSetDepthBoundsTestEnable(command_buffer, .false);
        device.proxy.cmdSetStencilTestEnable(command_buffer, .false);

        // blending
        device.proxy.cmdSetColorBlendEnableEXT(
            command_buffer,
            0,
            &.{.true},
        );

        device.proxy.cmdSetColorBlendEquationEXT(
            command_buffer,
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
            command_buffer,
            0,
            &.{.{
                .r_bit = true,
                .g_bit = true,
                .b_bit = true,
                .a_bit = true,
            }},
        );

        device.proxy.cmdSetLogicOpEnableEXT(command_buffer, .false);
    }

    pub const PolygonMode = union(vk.PolygonMode) {
        fill,
        line: struct {
            width: f32 = 1.0,
        },
        point,
        fill_rectangle_nv,
    };

    pub fn setPolygonMode(self: Frame, mode: PolygonMode) void {
        const mode_enum = std.meta.activeTag(mode);
        self.device.proxy.cmdSetPolygonModeEXT(self.command_buffer, mode_enum);

        switch (mode) {
            .line => |line| self.device.proxy.cmdSetLineWidth(self.command_buffer, line.width),
            else => {},
        }
    }

    pub const CullMode = enum(vk.Flags) {
        front = 0,
        back = 1,
    };

    pub fn setCullMode(self: Frame, mode: CullMode) void {
        self.device.proxy.cmdSetCullMode(self.command_buffer, @bitCast(@intFromEnum(mode)));
    }
};

pub const ShaderStage = enum(vk.Flags) {
    none = 0x00000000,
    vertex = 0x00000001,
    tessellation_control = 0x00000002,
    tessellation_evaluation = 0x00000004,
    geometry = 0x00000008,
    fragment = 0x00000010,
    compute = 0x00000020,

    pub const Mask = packed struct(vk.Flags) {
        vertex: bool = false,
        tessellation_control: bool = false,
        tessellation_evaluation: bool = false,
        geometry: bool = false,
        fragment: bool = false,
        compute: bool = false,
        _pad: u26 = 0,
    };
};

pub fn Shader(stage: ShaderStage) type {
    const default_next_stage: ShaderStage = switch (stage) {
        .none => .none,
        .vertex => .fragment,
        .tessellation_control => .tessellation_evaluation,
        .tessellation_evaluation => .geometry,
        .geometry => .fragment,
        .fragment => .none,
        .compute => .none,
    };

    return struct {
        const Self = @This();

        object: ShaderObject,

        pub const InitOptions = struct {
            next_stage: ShaderStage = default_next_stage,
            entry_name: [*:0]const u8 = "main",
        };

        pub const InitError = ShaderObject.InitError;

        pub fn initFromSlice(renderer: Renderer, source: []const u8, options: InitOptions) InitError!Self {
            const shader_object: ShaderObject = try .init(renderer.gpa, renderer.device, .{
                .stage = stage,
                .next_stage = options.next_stage,
                .source = source,
                .entry_name = options.entry_name,
            });

            return .{ .object = shader_object };
        }

        pub fn initFromSliceWithPushConstants(renderer: Renderer, source: []const u8, options: InitOptions, push_constant_range: PushConstantRange) InitError!Self {
            const shader_object: ShaderObject = try .init(renderer.gpa, renderer.device, .{
                .stage = @bitCast(@intFromEnum(stage)),
                .next_stage = @bitCast(@intFromEnum(options.next_stage)),
                .source = source,
                .entry_name = options.entry_name,
                .push_constant_ranges = &.{push_constant_range},
            });

            return .{ .object = shader_object };
        }

        pub fn deinit(self: Self, renderer: Renderer) void {
            self.object.deinit(renderer.gpa, renderer.device);
        }

        pub fn bind(self: Self, frame: Frame) void {
            frame.device.proxy.cmdBindShadersEXT(
                frame.command_buffer,
                &.{@bitCast(@intFromEnum(stage))},
                &.{self.object.handle},
            );
        }
    };
}

pub const PushConstantRange = vk.PushConstantRange;
pub fn PushConstant(comptime Value: type, shader_stages: ShaderStage.Mask) type {
    switch (@typeInfo(Value)) {
        .@"struct" => |s| {
            if (s.layout != .@"extern") @compileError("expected extern struct layout for push constants, found '" ++ @tagName(s.layout) ++ "' in '" ++ @typeName(Value) ++ "'");
        },
        else => |info| {
            @compileError("expected extern struct for push constants, found '" ++ @tagName(info) ++ " in '" ++ @typeName(Value) ++ "'");
        },
    }

    const range: vk.PushConstantRange = .{
        .stage_flags = @bitCast(shader_stages),
        .offset = 0,
        .size = @sizeOf(Value),
    };

    return struct {
        const Self = @This();

        layout: vk.PipelineLayout,

        comptime stages: ShaderStage.Mask = shader_stages,
        comptime range: vk.PushConstantRange = range,

        pub fn init(renderer: Renderer) !Self {
            const layout_create_info = vk.PipelineLayoutCreateInfo{
                .push_constant_range_count = 1,
                .p_push_constant_ranges = @ptrCast(&range),
            };

            const layout = try renderer.device.proxy.createPipelineLayout(&layout_create_info, @ptrCast(@alignCast(renderer.gpa.ptr)));

            return .{ .layout = layout };
        }

        pub fn deinit(self: Self, renderer: Renderer) void {
            renderer.device.proxy.destroyPipelineLayout(self.layout, @ptrCast(@alignCast(renderer.gpa.ptr)));
        }

        pub fn push(self: Self, frame: Frame, value: Value) void {
            frame.device.proxy.cmdPushConstants(
                frame.command_buffer,
                self.layout,
                range.stage_flags,
                range.offset,
                range.size,
                &value,
            );
        }
    };
}

/// Creates a mesh type with compile-time generated vertex input layout.
///
/// `streams` defines the vertex buffer streams used by the mesh.
/// Each stream becomes a Vulkan vertex binding and its fields become attributes.
///
/// `IndexType` defines the index buffer type (`u8`, `u16`, or `u32`).
/// Use `null` for a non-indexed mesh.
pub fn Mesh(streams: []const type, opt_index_type: ?type) type {
    const VertexData = init: {
        var field_types: [streams.len]type = undefined;
        for (&field_types, streams) |*t, VertexType| {
            t.* = []const VertexType;
        }
        break :init @Tuple(&field_types);
    };

    const has_indices = if (opt_index_type) |IndexType| switch (IndexType) {
        u8, u16, u32 => true,
        else => @compileError("expected index type u8, u16, u32, or null, found " ++ @typeName(IndexType)),
    } else false;

    const IndexType = opt_index_type orelse u0;

    return struct {
        const Self = @This();

        buffers: [streams.len]Buffer,
        index_buffer: if (has_indices) Buffer else void,

        count: u32, // vertex or index count
        topology: Topology,
        primitive_restart: bool,

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

        pub const Topology = vk.PrimitiveTopology;

        pub const Description = struct {
            vertices: VertexData,
            indices: []const IndexType = &.{},
            topology: Topology = .triangle_list,
            primitive_restart: bool = false,
        };

        pub fn init(renderer: Renderer, desc: Description) !Self {
            var buffers: [streams.len]Buffer = undefined;
            inline for (streams, 0..) |T, i| {
                buffers[i] = try .init(T, renderer.gpa, renderer.physical_device, renderer.device, .vertex, desc.vertices[i]);
            }

            const index_buffer = if (has_indices) try Buffer.init(IndexType, renderer.gpa, renderer.physical_device, renderer.device, .index, desc.indices) else void{};

            const count: u32 = @truncate(if (has_indices) desc.indices.len else desc.vertices[0].len);

            return .{
                .buffers = buffers,
                .index_buffer = index_buffer,
                .count = count,
                .topology = desc.topology,
                .primitive_restart = desc.primitive_restart,
            };
        }

        pub fn deinit(self: Self, renderer: Renderer) void {
            renderer.device.proxy.deviceWaitIdle() catch {};
            if (has_indices) self.index_buffer.deinit(renderer.gpa, renderer.device);
            for (self.buffers) |buffer| buffer.deinit(renderer.gpa, renderer.device);
        }

        pub fn bind(self: Self, frame: Frame) void {
            frame.device.proxy.cmdSetVertexInputEXT(
                frame.command_buffer,
                bindings[0..],
                attributes[0..],
            );

            var handles: [streams.len]vk.Buffer = undefined;
            for (&handles, self.buffers) |*handle, buffer| {
                handle.* = buffer.handle;
            }

            const offsets: [streams.len]vk.DeviceSize = @splat(0);

            frame.device.proxy.cmdBindVertexBuffers(
                frame.command_buffer,
                0,
                &handles,
                &offsets,
            );

            if (has_indices) frame.device.proxy.cmdBindIndexBuffer(
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

        pub fn draw(self: Self, frame: Frame) void {
            frame.device.proxy.cmdSetPrimitiveTopology(
                frame.command_buffer,
                self.topology,
            );

            frame.device.proxy.cmdSetPrimitiveRestartEnable(
                frame.command_buffer,
                @enumFromInt(@intFromBool(self.primitive_restart)),
            );

            if (has_indices) {
                frame.device.proxy.cmdDrawIndexed(frame.command_buffer, self.count, 1, 0, 0, 0);
            } else {
                frame.device.proxy.cmdDraw(frame.command_buffer, self.count, 1, 0, 0);
            }
        }

        fn formatOf(comptime T: type) vk.Format {
            switch (@typeInfo(T)) {
                .float => return switch (@bitSizeOf(T)) {
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
            }
        }
    };
}
