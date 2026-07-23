const Pipeline = @This();

const std = @import("std");
const vk = @import("vulkan");

const Device = @import("Device.zig");
const Swapchain = @import("Swapchain.zig");

handle: vk.Pipeline,
layout: vk.PipelineLayout,

fragment_shader: vk.ShaderModule,
vertex_shader: vk.ShaderModule,

pub const InitError = vk.DeviceWrapper.CreateShaderModuleError || vk.DeviceWrapper.CreateGraphicsPipelinesError;

pub const InitOptions = struct {
    fragment_source: []align(4) const u8,
    vertex_source: []align(4) const u8,
};

pub fn init(gpa: std.mem.Allocator, device: Device, swapchain: Swapchain, options: InitOptions) InitError!Pipeline {
    const fragment_shader = try createShader(gpa, device, options.fragment_source);
    const vertex_shader = try createShader(gpa, device, options.vertex_source);

    const shader_stages: []const vk.PipelineShaderStageCreateInfo = &.{
        .{
            .stage = .{ .fragment_bit = true },
            .module = fragment_shader,
            .p_name = "main",
        },
        .{
            .stage = .{ .vertex_bit = true },
            .module = vertex_shader,
            .p_name = "main",
        },
    };

    const rendering_info: *const vk.PipelineRenderingCreateInfo = &.{
        .color_attachment_count = 1,
        .p_color_attachment_formats = @ptrCast(&swapchain.format),
        .view_mask = 0,
        .stencil_attachment_format = .undefined,
        .depth_attachment_format = .undefined,
    };

    const vertex_state: *const vk.PipelineVertexInputStateCreateInfo = &.{};

    const assembly_state: *const vk.PipelineInputAssemblyStateCreateInfo = &.{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const viewport_state: *const vk.PipelineViewportStateCreateInfo = &.{
        .viewport_count = 1,
        .scissor_count = 1,
    };

    const rasterization_state: *const vk.PipelineRasterizationStateCreateInfo = &.{
        .line_width = 1.0,
        .depth_clamp_enable = .false,
        .depth_bias_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{},
        .front_face = .counter_clockwise,
        .depth_bias_clamp = 0.0,
        .depth_bias_constant_factor = 0.0,
        .depth_bias_slope_factor = 0.0,
        .rasterizer_discard_enable = .false,
    };

    const multisample_state: *const vk.PipelineMultisampleStateCreateInfo = &.{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 0.0,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const stencil_state: *const vk.PipelineDepthStencilStateCreateInfo = &.{
        .depth_test_enable = .false,
        .depth_write_enable = .false,
        .depth_compare_op = .less,
        .depth_bounds_test_enable = .false,
        .stencil_test_enable = .false,
        .front = std.mem.zeroes(vk.StencilOpState),
        .back = std.mem.zeroes(vk.StencilOpState),
        .min_depth_bounds = 0.0,
        .max_depth_bounds = 1.0,
    };

    const attachments: []const vk.PipelineColorBlendAttachmentState = &.{
        .{
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
            .blend_enable = .true,
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .alpha_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
        },
    };

    const color_blend_state: *const vk.PipelineColorBlendStateCreateInfo = &.{
        .attachment_count = attachments.len,
        .p_attachments = attachments.ptr,
        .logic_op_enable = .false,
        .logic_op = .clear,
        .blend_constants = @splat(0.0),
    };

    const dynamic_states: []const vk.DynamicState = &.{
        .viewport,
        .scissor,
    };

    const dynamic_state: *const vk.PipelineDynamicStateCreateInfo = &.{
        .dynamic_state_count = @intCast(dynamic_states.len),
        .p_dynamic_states = dynamic_states.ptr,
    };

    const layout_create_info: *const vk.PipelineLayoutCreateInfo = &.{};
    const layout = try device.proxy.createPipelineLayout(layout_create_info, @ptrCast(@alignCast(gpa.ptr)));

    const create_info: *const vk.GraphicsPipelineCreateInfo = &.{
        .p_next = @ptrCast(rendering_info),
        .stage_count = @intCast(shader_stages.len),
        .p_stages = shader_stages.ptr,
        .p_vertex_input_state = vertex_state,
        .p_input_assembly_state = assembly_state,
        .p_viewport_state = viewport_state,
        .p_rasterization_state = rasterization_state,
        .p_multisample_state = multisample_state,
        .p_depth_stencil_state = stencil_state,
        .p_color_blend_state = color_blend_state,
        .p_dynamic_state = dynamic_state,
        .layout = layout,
        .subpass = 0,
        .base_pipeline_index = 0,
    };

    var handle: vk.Pipeline = undefined;
    _ = try device.proxy.createGraphicsPipelines(.null_handle, @ptrCast(create_info), @ptrCast(@alignCast(gpa.ptr)), @ptrCast(&handle));

    return .{
        .handle = handle,
        .layout = layout,

        .fragment_shader = fragment_shader,
        .vertex_shader = vertex_shader,
    };
}

pub fn deinit(self: Pipeline, gpa: std.mem.Allocator, device: Device) void {
    device.proxy.destroyShaderModule(self.fragment_shader, @ptrCast(@alignCast(gpa.ptr)));
    device.proxy.destroyShaderModule(self.vertex_shader, @ptrCast(@alignCast(gpa.ptr)));
    device.proxy.destroyPipeline(self.handle, @ptrCast(@alignCast(gpa.ptr)));
}

fn createShader(gpa: std.mem.Allocator, device: Device, source: []align(4) const u8) vk.DeviceWrapper.CreateShaderModuleError!vk.ShaderModule {
    std.debug.assert(source.len % 4 == 0);
    const create_info: *const vk.ShaderModuleCreateInfo = &.{
        .code_size = source.len,
        .p_code = @ptrCast(source.ptr),
    };

    const shader_module = try device.proxy.createShaderModule(create_info, @ptrCast(@alignCast(gpa.ptr)));
    return shader_module;
}
