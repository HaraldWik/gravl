const Swapchain = @This();

const std = @import("std");
const vk = @import("vulkan");

const Size = @import("../Window.zig").Size;

const Instance = @import("Instance.zig");
const Surface = @import("Surface.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const Device = @import("Device.zig");

handle: vk.SwapchainKHR = .null_handle,

images: []vk.Image = &.{},
image_views: []vk.ImageView = &.{},
finished: []vk.Semaphore = &.{},

image_count: u32 = 0,
image_index: u32 = 0,

format: vk.Format = undefined,
extent: vk.Extent2D = undefined,

graveyard: [graveyard_size]Zombie = .{
    .{},
    .{},
    .{},
    .{},
},

const frames_in_flight = 3;
const graveyard_size = 4;

pub const Zombie = struct {
    handle: vk.SwapchainKHR = .null_handle,

    image_views: []vk.ImageView = &.{},
    images: []vk.Image = &.{},
    finished: []vk.Semaphore = &.{},

    image_count: u32 = 0,
    frame_retired: u64 = 0,

    valid: bool = false,

    pub fn deinit(self: *Zombie, gpa: std.mem.Allocator, device: Device) void {
        for (self.image_views) |image_view| {
            device.proxy.destroyImageView(image_view, null);
        }

        for (self.finished) |semaphore| {
            device.proxy.destroySemaphore(semaphore, null);
        }

        if (self.handle != .null_handle) {
            device.proxy.destroySwapchainKHR(self.handle, null);
        }

        gpa.free(self.finished);
        gpa.free(self.image_views);
        gpa.free(self.images);

        self.* = .{};
    }
};

fn build(
    swapchain: *Swapchain,
    gpa: std.mem.Allocator,
    instance: Instance,
    surface: Surface,
    physical_device: PhysicalDevice,
    device: Device,
    size: Size,
    old_handle: vk.SwapchainKHR,
) !void {
    const caps = try instance.proxy.getPhysicalDeviceSurfaceCapabilitiesKHR(
        physical_device.handle,
        surface.handle,
    );

    const formats = try instance.proxy.getPhysicalDeviceSurfaceFormatsAllocKHR(
        physical_device.handle,
        surface.handle,
        gpa,
    );
    defer gpa.free(formats);

    // TODO: fix
    const surface_format: vk.SurfaceFormatKHR = formats[0];
    // for (formats) |format| {
    //     if (format.format == .r8g8b8_srgb and
    //         format.color_space == .srgb_nonlinear_khr)
    //     {
    //         break format;
    //     }
    // } else return error.FormatNotFound;

    const present_mode = try getPresentMode(
        gpa,
        instance,
        surface,
        physical_device,
    );

    const extent: vk.Extent2D = .{
        .width = std.math.clamp(
            size.width,
            caps.min_image_extent.width,
            caps.max_image_extent.width,
        ),
        .height = std.math.clamp(
            size.height,
            caps.min_image_extent.height,
            caps.max_image_extent.height,
        ),
    };

    var image_count = caps.min_image_count + 1;

    if (caps.max_image_count > 0 and image_count > caps.max_image_count) {
        image_count = caps.max_image_count;
    }

    const create_info: vk.SwapchainCreateInfoKHR = .{
        .surface = surface.handle,
        .min_image_count = image_count,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{
            .color_attachment_bit = true,
        },
        .image_sharing_mode = .exclusive,
        .pre_transform = .{
            .identity_bit_khr = true,
        },
        .composite_alpha = .{
            .opaque_bit_khr = true,
        },
        .present_mode = present_mode,
        .clipped = .true,
        .old_swapchain = old_handle,
    };

    const handle = try device.proxy.createSwapchainKHR(
        &create_info,
        null,
    );

    errdefer device.proxy.destroySwapchainKHR(handle, null);

    var actual_image_count: u32 = 0;

    _ = try device.proxy.getSwapchainImagesKHR(
        handle,
        &actual_image_count,
        null,
    );

    const images = try gpa.alloc(vk.Image, actual_image_count);
    errdefer gpa.free(images);

    _ = try device.proxy.getSwapchainImagesKHR(
        handle,
        &actual_image_count,
        images.ptr,
    );

    const image_views = try gpa.alloc(vk.ImageView, actual_image_count);

    var created_views: usize = 0;

    errdefer {
        for (image_views[0..created_views]) |view| {
            device.proxy.destroyImageView(view, null);
        }
        gpa.free(image_views);
    }

    for (image_views, images) |*image_view, image| {
        const info: vk.ImageViewCreateInfo = .{
            .image = image,
            .view_type = .@"2d",
            .format = surface_format.format,
            .components = std.mem.zeroes(vk.ComponentMapping),
            .subresource_range = .{
                .aspect_mask = .{
                    .color_bit = true,
                },
                .level_count = 1,
                .layer_count = 1,
                .base_mip_level = 0,
                .base_array_layer = 0,
            },
        };

        image_view.* = try device.proxy.createImageView(
            &info,
            null,
        );

        created_views += 1;
    }

    const finished = try gpa.alloc(vk.Semaphore, actual_image_count);

    var created_semaphores: usize = 0;

    errdefer {
        for (finished[0..created_semaphores]) |semaphore| {
            device.proxy.destroySemaphore(semaphore, null);
        }
        gpa.free(finished);
    }

    const semaphore_info: vk.SemaphoreCreateInfo = .{};

    for (finished) |*semaphore| {
        semaphore.* = try device.proxy.createSemaphore(
            &semaphore_info,
            null,
        );

        created_semaphores += 1;
    }

    swapchain.handle = handle;
    swapchain.images = images;
    swapchain.image_views = image_views;
    swapchain.finished = finished;

    swapchain.image_count = actual_image_count;
    swapchain.image_index = 0;

    swapchain.format = surface_format.format;
    swapchain.extent = extent;
}

pub fn create(
    swapchain: *Swapchain,
    gpa: std.mem.Allocator,
    instance: Instance,
    surface: Surface,
    physical_device: PhysicalDevice,
    device: Device,
    size: Size,
) !void {
    try build(swapchain, gpa, instance, surface, physical_device, device, size, .null_handle);
}

pub fn drain(
    swapchain: *Swapchain,
    gpa: std.mem.Allocator,
    device: Device,
    accumulated_frame_index: u64,
) void {
    for (&swapchain.graveyard) |*zombie| {
        if (!zombie.valid) continue;
        if (accumulated_frame_index - zombie.frame_retired < frames_in_flight) continue;

        zombie.deinit(gpa, device);
    }
}

pub fn recreate(
    swapchain: *Swapchain,
    gpa: std.mem.Allocator,
    instance: Instance,
    surface: Surface,
    physical_device: PhysicalDevice,
    device: Device,
    size: Size,
    accumulated_frame_index: u64,
) !void {
    const zombie = for (&swapchain.graveyard) |*zombie| {
        if (!zombie.valid) {
            break zombie;
        }
    } else {
        // No room in graveyard, wait for everything to finish
        swapchain.deinit(gpa, device);

        return build(
            swapchain,
            gpa,
            instance,
            surface,
            physical_device,
            device,
            size,
            .null_handle,
        );
    };

    zombie.* = .{
        .handle = swapchain.handle,
        .image_views = swapchain.image_views,
        .images = swapchain.images,
        .finished = swapchain.finished,
        .image_count = swapchain.image_count,
        .frame_retired = accumulated_frame_index,
        .valid = true,
    };

    swapchain.handle = .null_handle;
    swapchain.images = &.{};
    swapchain.image_views = &.{};
    swapchain.finished = &.{};

    return build(
        swapchain,
        gpa,
        instance,
        surface,
        physical_device,
        device,
        size,
        zombie.handle,
    );
}

fn getPresentMode(gpa: std.mem.Allocator, instance: Instance, surface: Surface, physical_device: PhysicalDevice) !vk.PresentModeKHR {
    const present_modes = try instance.proxy.getPhysicalDeviceSurfacePresentModesAllocKHR(physical_device.handle, surface.handle, gpa);
    defer gpa.free(present_modes);

    const preferred_present_modes: []const vk.PresentModeKHR = &.{
        .mailbox_khr, // low latency + vsync, usually best for games
        .immediate_khr, // lowest latency, but can tear
        .fifo_latest_ready_khr,
        .fifo_relaxed_khr,
        .shared_continuous_refresh_khr,
        .shared_demand_refresh_khr,
        .fifo_khr, // guaranteed fallback
    };

    var found_present_mode: vk.PresentModeKHR = .fifo_khr;

    for (preferred_present_modes) |preferred| {
        for (present_modes) |available| if (preferred == available) {
            found_present_mode = preferred;
            break;
        };

        if (found_present_mode == preferred) break;
    }

    return found_present_mode;
}

pub fn deinit(
    swapchain: *Swapchain,
    gpa: std.mem.Allocator,
    device: Device,
) void {
    for (&swapchain.graveyard) |*zombie| {
        if (!zombie.valid) continue;

        zombie.deinit(gpa, device);
    }

    for (swapchain.image_views) |image_view| {
        device.proxy.destroyImageView(image_view, null);
    }

    for (swapchain.finished) |semaphore| {
        device.proxy.destroySemaphore(semaphore, null);
    }

    if (swapchain.handle != .null_handle) device.proxy.destroySwapchainKHR(
        swapchain.handle,
        null,
    );

    gpa.free(swapchain.finished);
    gpa.free(swapchain.image_views);
    gpa.free(swapchain.images);

    swapchain.* = .{};
}
