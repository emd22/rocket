const std = @import("std");

const Log = @import("../Log.zig");
const c = @import("../CLibs.zig").c;

pub const VULKAN_DEBUG = true;

const VulkanAllocator: [*c]c.VkAllocationCallbacks = null;

/// The currently selected Vulkan Renderer
var CurrentRenderer: *Renderer = undefined;

pub const RenderError = error{
    ExtensionNotAvailable,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

/// Retrieves the currently selected Renderer
pub fn GetCurrentRenderer() *Renderer {
    return CurrentRenderer;
}

pub fn SetCurrentRenderer(renderer: *Renderer) void {
    CurrentRenderer = renderer;
}

pub fn AssertRendererExists(options: struct { CheckInitialized: bool = true }) void {
    if (comptime VULKAN_DEBUG == false) {
        return;
    }

    // if (CurrentRenderer == null) {
    //     Panic("No renderer has been created or selected", null, .{});
    // }
    if (options.CheckInitialized and !CurrentRenderer.Initialized) {
        Panic("A renderer has been created but not initialized!", null, .{});
    }
}

inline fn TryVk(status: c.VkResult, comptime on_error: []const u8) void {
    if (status == c.VK_SUCCESS) {
        return;
    }
    Panic(on_error, status, .{});
}

/// Gets the handle for a function in a Vulkan extension.
///
/// ```
/// // the function prototype
/// const prot: type = *const fn (c.VkInstance, i32) callconv(.c) void;
/// const func = GetExtensionFunc(prot, "vkSomeFuncEXT");
///
/// // call the retrieved handle
/// func(instance, 10);
///
/// ```
pub inline fn GetExtensionFunc(comptime FuncProt: type, name: []const u8) RenderError!FuncProt {
    const raw_ptr = c.vkGetInstanceProcAddr(CurrentRenderer.Instance, name.ptr);

    if (raw_ptr) |funcptr| {
        return @as(FuncProt, @ptrCast(funcptr));
    }

    Log.RenError("Extension '{s}' not present", .{name});
    return RenderError.ExtensionNotAvailable;
}

fn CreateDebugUtilsMessengerEXT(
    instance: c.VkInstance,
    pCreateInfo: [*c]const c.VkDebugUtilsMessengerCreateInfoEXT,
    pAllocator: [*c]const c.VkAllocationCallbacks,
    pDebugMessenger: [*c]c.VkDebugUtilsMessengerEXT,
) callconv(.c) c.VkResult {
    const prot: type = *const fn (c.VkInstance, [*c]const c.VkDebugUtilsMessengerCreateInfoEXT, [*c]const c.VkAllocationCallbacks, [*c]c.VkDebugUtilsMessengerEXT) callconv(.c) c.VkResult;

    const function = GetExtensionFunc(prot, "vkCreateDebugUtilsMessengerEXT") catch {
        return c.VK_ERROR_EXTENSION_NOT_PRESENT;
    };

    return function(instance, pCreateInfo, pAllocator, pDebugMessenger);
}

fn DestroyDebugUtilsMessengerEXT(
    instance: c.VkInstance,
    messenger: c.VkDebugUtilsMessengerEXT,
    pAllocator: [*c]const c.VkAllocationCallbacks,
) callconv(.c) void {
    const prot: type = *const fn (c.VkInstance, messenger: c.VkDebugUtilsMessengerEXT, pAllocator: [*c]const c.VkAllocationCallbacks) callconv(.c) void;

    const function = GetExtensionFunc(prot, "vkDestroyDebugUtilsMessengerEXT") catch {
        Log.Warn("Debug Utils extension not present, ignoring DestroyDebugUtilsMessengerEXT...", .{});
        return;
    };

    return function(instance, messenger, pAllocator);
}

// since this only is used in SetupDebugMessager(which is only compiled if VULKAN_DEBUG is true),
// this function will be skipped in compilation even if the extension types do not exist, as long as
// VULKAN_DEBUG is false.
fn DebugMessageCallback(
    message_severity: c_uint,
    message_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.C) u32 {
    const fmt = "VkValidator: {s}";

    _ = message_type;
    _ = user_data;

    const message = callback_data.*.pMessage;

    if ((message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) == 0) {
        Log.RenInfo(fmt, .{message});
    } else if ((message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) == 0) {
        Log.RenWarn(fmt, .{message});
    } else if ((message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) == 0) {
        Log.RenError(fmt, .{message});
    } else {
        Log.RenDebug(fmt, .{message});
    }

    return 0;
}

pub const CommandPool = struct {
    CommandPool: c.VkCommandPool = null,

    pub fn Create(self: *CommandPool, queue_family: u32) void {
        const pool_info = c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .queueFamilyIndex = queue_family,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        };

        const status = c.vkCreateCommandPool(CurrentRenderer.GetDevice().Device, pool_info, VulkanAllocator, &self.CommandPool);
        if (status != c.VK_SUCCESS) {
            Panic("Could not create command pool!", status);
        }
    }

    pub fn Destroy(self: CommandPool) void {
        c.vkDestroyCommandPool(CurrentRenderer.GetDevice().Device, self.CommandPool, VulkanAllocator);
    }
};

pub const CommandBuffer = struct {
    CommandBuffer: c.VkCommandBuffer = null,
    CommandPool: *CommandPool = undefined,
    Initialized: bool = false,

    pub fn Create(self: *CommandBuffer, command_pool: *CommandPool) void {
        const buffer_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool.CommandPool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };

        self.CommandPool = CommandPool;

        const status = c.vkAllocateCommandBuffers(CurrentRenderer.GetDevice().Device, &buffer_info, &self.CommandBuffer);
        if (status != c.VK_SUCCESS) {
            Panic("Could not allocate command buffer!", status, .{});
        }
    }

    pub fn Record(self: CommandBuffer) void {
        if (!self.Initialized) {
            Panic("Command buffer has not been initialized!", null, .{});
        }
        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = 0,
            .pInheritanceInfo = null,
        };

        const status = c.vkBeginCommandBuffer(self.CommandBuffer, &begin_info);
        if (status != c.VK_SUCCESS) {
            Panic("Could not begin recording command buffer", status, .{});
        }
    }

    pub fn Reset(self: CommandBuffer) void {
        _ = c.vkResetCommandBuffer(self.CommandBuffer, 0);
    }

    pub fn End(self: CommandBuffer) void {
        const status = c.vkEndCommandBuffer(self.CommandBuffer);
        if (status != c.VK_SUCCESS) {
            Panic("Failed to record command buffer", status, .{});
        }
    }

    pub fn Destroy(self: *CommandBuffer) void {
        c.vkFreeCommandBuffers(CurrentRenderer.GetDevice().Device, self.CommandPool.CommandPool, 1, &self.CommandBuffer);
        self.Initialized = false;
    }
};

const TVec2i = @import("../Math.zig").TVec2i;

pub const Swapchain = struct {
    Swapchain: c.VkSwapchainKHR = null,
    ImageViews: []c.VkImageView = undefined,
    Images: []c.VkImage = undefined,

    Framebuffers: []Framebuffer = undefined,

    ImageFormat: c.VkSurfaceFormatKHR = undefined,

    Extent: TVec2i = TVec2i.Zero,

    const Self = @This();

    pub fn Create(self: *Self, size: TVec2i) void {
        // swapchains are part of the initialization stage
        AssertRendererExists(.{ .CheckInitialized = false });

        self.CreateSwapchain(size);
        self.CreateSwapchainImages();
    }

    pub fn GetNextImage(self: Swapchain, image_available: Semaphore) void {
        TryVk(
            c.vkAcquireNextImageKHR(CurrentRenderer.GetDevice().Device, self.Swapchain, std.math.maxInt(u64), image_available.Get(), null, &CurrentRenderer.FrameNumber),
            "Could not acquire next frame image!",
        );
    }

    fn CreateSwapchainFramebuffers(self: *Swapchain, graphics_pipeline: GraphicsPipeline) void {
        self.Framebuffers = allocator.alloc(Framebuffer, self.ImageViews.len) catch {
            Panic("Could not allocate framebuffers", null, .{});
        };

        for (self.ImageViews, 0..) |image_view, index| {
            const views = [_]c.VkImageView{image_view};

            self.Framebuffers[index].Create(views, graphics_pipeline, self.Extent);
        }
    }

    fn CreateImageViews(self: *Swapchain) void {
        self.ImageViews = allocator.alloc(c.VkImageView, self.Images.len);

        for (self.Images, 0..) |image, index| {
            const create_info = c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.ImageFormat,
                .components = @splat(c.VK_COMPONENT_SWIZZLE_IDENTITY),
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            const result = c.vkCreateImageView(CurrentRenderer.GetDevice(), &create_info, null, &self.ImageViews[index]);
            if (result != c.VK_SUCCESS) {
                Panic("Could not create swapchain image view", result, .{});
            }
        }
    }

    pub fn Destroy(self: *Self) void {
        const device = CurrentRenderer.GetDevice().Device;

        for (self.ImageViews, 0..) |view, index| {
            self.Framebuffers[index].Destroy();
            c.vkDestroyImageView(device, view, VulkanAllocator);
        }

        allocator.free(self.ImageViews);
        allocator.free(self.Images);
        c.vkDestroySwapchainKHR(device, self.Swapchain, VulkanAllocator);
    }

    fn CreateSwapchainImages(self: *Self) void {
        var image_count: u32 = 0;

        const device = CurrentRenderer.GetDevice();

        _ = c.vkGetSwapchainImagesKHR(device.Device, self.Swapchain, &image_count, null);

        self.Images = allocator.alloc(c.VkImage, image_count) catch Panic("Could not create swapchain images", null, .{});

        _ = c.vkGetSwapchainImagesKHR(device.Device, self.Swapchain, &image_count, self.Images.ptr);
    }

    fn CreateSwapchain(self: *Self, size: TVec2i) void {
        self.Extent = size;

        const device = CurrentRenderer.GetDevice();

        var capabilities = c.VkSurfaceCapabilitiesKHR{};
        var result = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device.Physical, CurrentRenderer.Surface, &capabilities);

        if (result != c.VK_SUCCESS) {
            Panic("Could not get device surface capabilities", result, .{});
        }

        const extent = c.VkExtent2D{
            .width = @intCast(size.X()),
            .height = @intCast(size.Y()),
        };

        // TODO: look more into what the best swapchain image count would be
        var image_count = capabilities.minImageCount + 1;

        if (capabilities.maxImageCount > 0 and image_count > capabilities.maxImageCount) {
            image_count = capabilities.maxImageCount;
        }

        self.ImageFormat = device.GetBestSurfaceFormat();

        // TODO: query and select MAILBOX
        const present_mode = c.VK_PRESENT_MODE_FIFO_KHR;

        var create_info = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = CurrentRenderer.Surface,
            .minImageCount = image_count,
            .imageFormat = self.ImageFormat.format,
            .imageColorSpace = self.ImageFormat.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .presentMode = present_mode,
            .preTransform = capabilities.currentTransform,
            // ignore alpha (from blending behind the window)
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .clipped = c.VK_TRUE,
            .oldSwapchain = null,
        };

        const indices = [_]u32{ device.QueueFamilies.Graphics.?, device.QueueFamilies.Present.? };

        if (device.QueueFamilies.Graphics == device.QueueFamilies.Present) {
            create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
            create_info.queueFamilyIndexCount = 0;
            create_info.pQueueFamilyIndices = null;
        } else {
            create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
            create_info.queueFamilyIndexCount = 2;
            create_info.pQueueFamilyIndices = &indices;
        }

        result = c.vkCreateSwapchainKHR(device.Device, &create_info, VulkanAllocator, &self.Swapchain);
        if (result != c.VK_SUCCESS) {
            Panic("Could not create swapchain", result, .{});
        }
    }
};

pub fn SetupDebugMessenger() callconv(.c) void {
    if (comptime VULKAN_DEBUG == false) {
        return;
    }

    const create_info = c.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT,
        .pfnUserCallback = &DebugMessageCallback,
        .pUserData = null,
        .pNext = null,
        .flags = 0,
    };

    const result = CreateDebugUtilsMessengerEXT(
        CurrentRenderer.Instance,
        &create_info,
        VulkanAllocator,
        &CurrentRenderer.DebugMessenger,
    );

    if (result != c.VK_SUCCESS) {
        // TODO: not panic worthy? keep going if we can.
        Panic("Failed to create Vulkan debug messenger!", result, .{});
    }
}

/// Prints the currently available validation layers.
fn PrintValidationLayers() void {
    errdefer @panic("Could not get validation layers (memory error)");
    var layer_count: u32 = 0;
    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, null);
    const layers = try allocator.alloc(c.VkLayerProperties, layer_count);
    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, layers.ptr);

    for (0..layer_count) |i| {
        Log.RenInfo("Layer: {s}", .{layers[i].layerName});
    }
}

pub const Framebuffer = struct {
    Framebuffer: c.VkFramebuffer = null,
    pub fn Create(self: *Framebuffer, image_views: []c.VkImageView, graphics_pipeline: GraphicsPipeline, size: TVec2i) void {
        AssertRendererExists(.{ .CheckInitialized = true });

        const create_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = graphics_pipeline.RenderPass,
            .attachmentCount = image_views.len,
            .pAttachments = image_views.ptr,
            .width = @intCast(size.Width()),
            .height = @intCast(size.Height()),
            .layers = 1,
        };

        const device = GetCurrentRenderer().GetDevice().Device;

        const result = c.vkCreateFramebuffer(device, create_info, VulkanAllocator, &self.Framebuffer);
        if (result != c.VK_SUCCESS) {
            Panic("Failed to create framebuffer", result, .{});
        }
    }

    pub fn Destroy(self: *Framebuffer) void {
        const device = CurrentRenderer.GetDevice().Device;

        c.vkDestroyFramebuffer(device, self.Framebuffer, VulkanAllocator);
    }
};

pub const FrameData = struct {
    CommandPool: CommandPool,
    CommandBuffer: CommandBuffer,
};

pub const Semaphore = struct {
    Semaphore: c.VkSemaphore = null,

    pub fn Create(self: *Semaphore) void {
        const create_info = c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .flags = 0,
            .pNext = null,
        };

        const renderer = GetCurrentRenderer();

        TryVk(
            c.vkCreateSemaphore(renderer.GetDevice().Device, &create_info, VulkanAllocator, &self.Semaphore),
            "Could not create semaphore!",
        );
    }

    pub inline fn Get(self: Semaphore) c.VkSemaphone {
        return self.Semaphore;
    }

    pub fn Destroy(self: *Semaphore) void {
        c.vkDestroySemaphore(GetCurrentRenderer().GetDevice().Get(), self.Semaphore, VulkanAllocator);
    }
};

pub const Fence = struct {
    Fence: c.VkFence = null,

    pub fn Create(self: *Fence) void {
        const create_info = c.VkFenceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
            .pNext = null,
        };

        const renderer = GetCurrentRenderer();

        TryVk(
            c.vkCreateFence(renderer.GetDevice().Get(), &create_info, VulkanAllocator, &self.Fence),
            "Could not create fence!",
        );
    }

    const WaitOptions = struct { Timeout: u64 = std.math.maxInt(u64) };

    pub inline fn ResetMany(fences: []Fence) void {
        TryVk(
            c.vkResetFences(CurrentRenderer.GetDevice().Device, fences.len, &fences.ptr),
            "Could not reset fences!",
        );
    }

    pub inline fn Reset(self: Fence) void {
        Fence.ResetMany([_]Fence{self});
    }

    pub inline fn WaitForMany(fences: []Fence, options: WaitOptions) void {
        TryVk(
            c.vkWaitForFences(CurrentRenderer.GetDevice().Device, fences.len, &fences.ptr, c.VK_TRUE, options.Timeout),
            "Could not wait for fences!",
        );
    }

    pub inline fn WaitFor(self: Fence, options: WaitOptions) void {
        Fence.WaitForMany([_]Fence{self}, options);
    }

    pub inline fn Get(self: Fence) c.VkFence {
        return self.Fence;
    }

    pub fn Destroy(self: Fence) void {
        c.vkDestroyFence(GetCurrentRenderer().GetDevice().Get(), self.Fence, VulkanAllocator);
    }
};

pub const Renderer = struct {
    Initialized: bool = false,

    Instance: c.VkInstance = undefined,
    AvailableExtensions: ?[]c.VkExtensionProperties = null,

    DebugMessenger: c.VkDebugUtilsMessengerEXT = undefined,

    Surface: c.VkSurfaceKHR = null,
    Swapchain: Swapchain = Swapchain{},

    Device: ?Device = null,

    ImageAvailable: Semaphore = Semaphore{},
    RenderFinished: Semaphore = Semaphore{},

    InFlight: Fence = Fence{},

    Frames: []FrameData = undefined,
    FrameNumber: u32 = 0,
    const FRAME_OVERLAP = 2;

    const Self = @This();

    pub inline fn GetDevice(self: Self) Device {
        if (self.Device == null) {
            Panic("No device selected!\n", null, .{});
        }
        return self.Device.?;
    }

    /// Create a new `Renderer` in memory and initialize it.
    ///
    /// Make sure to call `.Free()` after the `Renderer` is no longer used.
    pub fn New(window: *c.SDL_Window, window_size: TVec2i) RenderError!*Self {
        var renderer = allocator.create(Renderer) catch {
            Panic("Could not allocate Renderer instance", null, .{});
        };
        renderer.* = std.mem.zeroes(Renderer);

        try renderer.Init(window, window_size);

        return renderer;
    }

    pub fn Free(self: *Self) void {
        self.Destroy();

        allocator.destroy(self);
    }

    pub inline fn GetFrame(self: Renderer) *FrameData {
        return &self.Frames[self.GetFrameIndex()];
    }

    pub fn InitFrames(self: *Self) void {
        const graphics_family = self.GetDevice().QueueFamilies.Graphics;

        for (self.Frames) |*frame| {
            frame.*.CommandPool.Create(graphics_family);
            frame.*.CommandBuffer.Create(frame.*.CommandPool);
        }
    }

    pub inline fn GetFrameIndex(self: Self) u32 {
        return (self.FrameNumber & 0x01);
    }

    pub fn DestroyFrames(self: *Self) void {
        for (self.Frames) |*frame| {
            frame.*.CommandBuffer.Destroy();
            frame.*.CommandPool.Destroy();
        }
    }

    pub fn Init(self: *Self, window: *c.SDL_Window, window_size: TVec2i) RenderError!void {
        if (self.Initialized) {
            Log.Warn("Renderer has already been initialized", .{});
            return;
        }

        SetCurrentRenderer(self);

        try self.InitVulkan();

        // retrieve our rendering surface from SDL
        self.AttachToWindow(window);

        {
            var device = Device{};
            device.PickPhsyicalDevice();
            device.CreateLogicalDevice();

            self.SelectDevice(device);
        }

        self.Swapchain.Create(window_size);

        self.Frames = allocator.alloc(FrameData, FRAME_OVERLAP) catch {
            Panic("Could not allocate frame data", null, .{});
        };

        // render semaphores
        self.ImageAvailable.Create();
        self.RenderFinished.Create();
        // render fences
        self.InFlight.Create();

        self.Initialized = true;
    }

    fn QueryInstanceExtensions(self: *Self) void {
        errdefer @panic("Could not query instance extensions!");

        std.debug.print("Query extensions\n", .{});

        if (self.AvailableExtensions != null) {
            Log.Warn("Extensions were previously queried", .{});
            return;
        }

        // get the count of the current extensions
        var extension_count: u32 = 0;
        _ = c.vkEnumerateInstanceExtensionProperties(null, &extension_count, null);

        std.debug.print("Ext count: {d}\n", .{extension_count});

        // get the available instance extensions
        self.AvailableExtensions = try allocator.alloc(c.VkExtensionProperties, extension_count);

        _ = c.vkEnumerateInstanceExtensionProperties(null, &extension_count, self.AvailableExtensions.?.ptr);

        Log.Info("=== Available Instance Extensions ({d}) ===", .{extension_count});

        for (0..extension_count) |i| {
            const extension = self.AvailableExtensions.?[i];

            Log.Info("{s} : {d}", .{ extension.extensionName, extension.specVersion });
        }
    }

    pub fn BeginFrame(self: Renderer, pipeline: GraphicsPipeline) void {
        self.Swapchain.GetNextImage(self.ImageAvailable);

        const command_buffer = self.GetFrame().CommandBuffer;

        command_buffer.Reset();
        command_buffer.Record();

        pipeline.RenderPass.Begin();
        pipeline.Bind(command_buffer);

        const width, const height = self.Swapchain.Extent.v;

        const viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = width, .height = height },
        };
        c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);
    }

    fn PresentFrame(self: Renderer) void {
        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.RenderFinished,

            .pSwapchains = &self.Swapchain.Swapchain,
            .pImageIndices = &self.FrameNumber,

            .pResults = null,
        };
        TryVk(c.vkQueuePresentKHR(self.GetDevice().PresentQueue, &present_info), "Could not present graphics queue");
    }

    fn SubmitFrame(self: Renderer) void {
        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.ImageAvailable.Semaphore,
            .pWaitDstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            // command buffers
            .commandBufferCount = 1,
            .pCommandBuffers = &self.GetFrame().CommandBuffer,
            // signal semaphores
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &self.RenderFinished.Semaphore,
        };
        TryVk(c.vkQueueSubmit(self.GetDevice().GraphicsQueue, 1, &submit_info, self.InFlight.Fence), "Error submitting draw buffer");
    }

    pub inline fn FinishFrame(self: *Renderer, pipeline: GraphicsPipeline) void {
        const command_buffer = self.GetFrame().CommandBuffer;

        pipeline.RenderPass.End();

        command_buffer.End();

        self.SubmitFrame();
        self.PresentFrame();
    }

    fn MakeInstanceExtensionList(self: *Self, requested_extensions: [][:0]const u8) std.ArrayList([*:0]const u8) {
        errdefer @panic("could not build extension list");

        var needed_extenion_count: u32 = 0;
        const vk_needed_extensions = c.SDL_Vulkan_GetInstanceExtensions(&needed_extenion_count);

        self.QueryInstanceExtensions();

        var total_extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, requested_extensions.len + needed_extenion_count);

        for (requested_extensions) |ext| {
            try total_extensions.append(ext.ptr);
        }

        for (0..needed_extenion_count) |i| {
            try total_extensions.append(vk_needed_extensions[i]);
        }

        return total_extensions;
    }

    fn CheckExtensionsAvailable(self: *Self, requested: [][*:0]const u8) ?std.ArrayList([*:0]const u8) {
        errdefer @panic("error checking extensions available");

        if (self.AvailableExtensions == null) {
            self.QueryInstanceExtensions();
        }

        // we have to use dynamic here as the length is not comptime known
        var extensions_found = try std.DynamicBitSet.initEmpty(allocator, requested.len);

        for (self.AvailableExtensions.?) |raw_extension| {
            // loop through all of our required extensions to see if the extension matches one
            for (requested, 0..) |raw_request, index| {
                // convert the [256]u8 to a []u8. Convert to sentinel terminated pointer, get length, and reslice
                const extension_length = std.mem.len(@as([*:0]u8, @ptrCast(@constCast(&raw_extension.extensionName))));
                const extension = raw_extension.extensionName[0..extension_length];

                const request = std.mem.span(raw_request);

                // the extension names do not match, skip
                if (!std.mem.eql(u8, extension, request)) {
                    continue;
                }

                extensions_found.setValue(index, true);
                break;
            }
        }

        Log.Info("Found {d} extensions, requested {d}", .{ extensions_found.count(), requested.len });

        // all extensions have been found
        if (extensions_found.count() == requested.len) {
            return null;
        }

        // there are extensions missing, make a list of them
        var extensions_not_available = std.ArrayList([*:0]const u8).init(allocator);

        for (0..requested.len) |index| {
            if (!extensions_found.isSet(index)) {
                try extensions_not_available.append(requested[index]);
            }
        }

        // check if all extensions have been found
        return extensions_not_available;
    }

    fn InitVulkan(self: *Self) RenderError!void {
        const app_name: [:0]const u8 = "Rocket";
        const app_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = app_name.ptr,
            .pEngineName = app_name.ptr,
            .apiVersion = c.VK_MAKE_VERSION(1, 3, 261),
        };

        var requested_extensions = [_][:0]const u8{
            c.VK_EXT_LAYER_SETTINGS_EXTENSION_NAME,
        };

        var all_extensions = MakeInstanceExtensionList(self, &requested_extensions);
        defer all_extensions.deinit();

        if (comptime VULKAN_DEBUG) {
            errdefer @panic("cannot add debug extensions");
            try all_extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
            try all_extensions.append(c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME);
        }
        Log.Info("Requested to load {d} extensions...", .{all_extensions.items.len});

        for (all_extensions.items) |extension| {
            Log.Info("Ext: {s}", .{extension});
        }

        const extensions_missing = self.CheckExtensionsAvailable(all_extensions.items);

        if (extensions_missing) |missing| {
            Log.SetColor(Log.TextColor.Error);

            Log.WriteRaw("MISSING: ", .{});

            for (missing.items, 0..) |ext, index| {
                Log.WriteRaw("{s}", .{ext});

                if (index < missing.items.len - 1) {
                    Log.WriteRaw(", ", .{});
                }
            }
            Log.WriteChar('\n');

            Log.SetColor(Log.TextColor.Reset);
            // free the missing extensions arraylist
            missing.deinit();

            Panic("Missing required instance extensions", null, .{});
        }

        PrintValidationLayers();

        const requested_validation_layers = [_][*:0]const u8{
            "VK_LAYER_KHRONOS_validation",
        };

        const instance_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &app_info,
            .ppEnabledExtensionNames = all_extensions.items.ptr,
            .enabledExtensionCount = @intCast(all_extensions.items.len),
            .ppEnabledLayerNames = &requested_validation_layers,
            .enabledLayerCount = @intCast(requested_validation_layers.len),
            .flags = c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
        };

        const result = c.vkCreateInstance(&instance_info, VulkanAllocator, &self.Instance);

        if (result != c.VK_SUCCESS) {
            Panic("Error creating Vulkan instance", result, .{});
        }

        Log.RenInfo("Successfully created instance!", .{});

        SetupDebugMessenger();
    }

    pub fn SelectDevice(self: *Self, device: Device) void {
        self.Device = device;
    }

    pub fn AttachToWindow(self: *Self, window: *c.SDL_Window) void {
        const success = c.SDL_Vulkan_CreateSurface(window, self.Instance, VulkanAllocator, &self.Surface);

        if (!success) {
            Log.RenFatal("Could not attach Vulkan instance to window! [SDLError: {s}]\n", .{c.SDL_GetError()});
            @panic("Renderer error");
        }
    }

    pub inline fn WaitForGPUIdle(self: Renderer) void {
        TryVk(c.vkDeviceWaitIdle(self.GetDevice().Device), "Error when waiting for GPU idle");
    }

    pub fn Destroy(self: *Self) void {
        if (!self.Initialized) {
            Log.Warn("Renderer has already been destroyed", .{});
            return;
        }

        self.WaitForGPUIdle();

        self.Swapchain.Destroy();

        if (self.Surface) |surface| {
            c.vkDestroySurfaceKHR(self.Instance, surface, VulkanAllocator);
        }
        self.GetDevice().Destroy();

        if (self.DebugMessenger != null) {
            DestroyDebugUtilsMessengerEXT(self.Instance, self.DebugMessenger, VulkanAllocator);
        }

        c.vkDestroyInstance(self.Instance, VulkanAllocator);
        if (self.AvailableExtensions) |extensions| {
            allocator.free(extensions);
        }

        self.DestroyFrames();
        allocator.free(self.Frames);

        // destroy synchro
        {
            self.ImageAvailable.Destroy();
            self.RenderFinished.Destroy();

            self.InFlight.Destroy();
        }

        self.Initialized = false;
    }
};

pub const QueueFamilies = struct {
    RawFamilies: ?[]c.VkQueueFamilyProperties = null,

    Graphics: ?u32 = null,
    Present: ?u32 = null,

    pub fn GetQueueFamilies(self: *QueueFamilies, device: *Device) []c.VkQueueFamilyProperties {
        if (self.QueueFamilies == null) {
            self.FindQueueFamilies(device);
        }

        return self.QueueFamilies.?;
    }

    pub fn FindQueueFamilies(self: *QueueFamilies, device: *Device) void {
        errdefer @panic("Cannot get queue families");

        var family_count: u32 = 0;

        c.vkGetPhysicalDeviceQueueFamilyProperties(device.Physical, &family_count, null);

        if (self.RawFamilies == null) {
            self.RawFamilies = try allocator.alloc(c.VkQueueFamilyProperties, family_count);
        }

        c.vkGetPhysicalDeviceQueueFamilyProperties(device.Physical.?, &family_count, self.RawFamilies.?.ptr);

        Log.RenInfo("Amount of queue families: {d}", .{self.RawFamilies.?.len});

        for (self.RawFamilies.?, 0..) |family, index| {
            if (self.Present != null and self.Graphics != null) {
                break;
            }

            if (family.queueCount == 0) {
                continue;
            }

            {
                // check for a graphics family
                if ((family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) == 1) {
                    self.Graphics = @intCast(index);
                }
            }
            {
                // check for a presentation family
                var present_support: u32 = 0;

                const result = c.vkGetPhysicalDeviceSurfaceSupportKHR(
                    device.Physical,
                    @as(u32, @intCast(index)),
                    CurrentRenderer.Surface,
                    &present_support,
                );

                if (result != c.VK_SUCCESS) {
                    Panic("Could not get physical device surface support(presentation queue family)", result, .{});
                }

                Log.Info("Present support: {d}", .{present_support});

                if (present_support > 0) {
                    self.Present = @intCast(index);
                }
            }
        }
    }

    pub fn Destroy(self: QueueFamilies) void {
        if (self.RawFamilies != null) {
            allocator.free(self.RawFamilies.?);
        }
    }
};

pub const Device = struct {
    Physical: c.VkPhysicalDevice = null,
    Device: c.VkDevice = null,
    QueueFamilies: QueueFamilies = QueueFamilies{},

    GraphicsQueue: c.VkQueue = null,
    PresentQueue: c.VkQueue = null,

    fn IsPhysicalDeviceSuitable(device: c.VkPhysicalDevice) bool {
        var props = c.VkPhysicalDeviceProperties{};
        var features = c.VkPhysicalDeviceFeatures{};

        c.vkGetPhysicalDeviceFeatures(device, &features);
        c.vkGetPhysicalDeviceProperties(device, &props);

        var rdev = Device{ .Physical = device };
        if (rdev.QueueFamilies.RawFamilies == null) {
            rdev.QueueFamilies.FindQueueFamilies(&rdev);
        }
        defer rdev.Destroy();

        const has_families = (rdev.QueueFamilies.Graphics != null and rdev.QueueFamilies.Present != null);

        // NOTE: MoltenVK only supports up to version 1.2, but most of these features can be
        // used through extensions.
        const version = props.apiVersion;
        if (version >= c.VK_MAKE_VERSION(1, 2, 0) and has_families) {
            Log.Info("Suitable Physical Device: {s}", .{props.deviceName});
            return true;
        }

        Log.Warn("Failed Device: {d}.{d}.{d}, Graphics Family?: {s}, Present Family?: {s}", .{
            c.VK_VERSION_MAJOR(version),
            c.VK_VERSION_MINOR(version),
            c.VK_VERSION_PATCH(version),
            Log.YesNo(rdev.QueueFamilies.Graphics != null),
            Log.YesNo(rdev.QueueFamilies.Present != null),
        });

        return false;
    }

    pub inline fn Get(self: Device) c.VkDevice {
        return self.Device;
    }

    pub inline fn GetPhysical(self: Device) c.VkPhysicalDevice {
        return self.Physical;
    }

    fn QueryQueues(self: *Device) void {
        c.vkGetDeviceQueue(self.Device, self.QueueFamilies.Graphics.?, 0, &self.GraphicsQueue);
        c.vkGetDeviceQueue(self.Device, self.QueueFamilies.Present.?, 0, &self.PresentQueue);
    }

    pub fn CreateLogicalDevice(self: *Device) void {
        if (self.Physical == null) {
            self.PickPhsyicalDevice();
        }
        if (self.QueueFamilies.Graphics == null or self.QueueFamilies.Present == null) {
            self.QueueFamilies.FindQueueFamilies(self);
        }

        const queue_priority: f32 = 1.0;

        errdefer Panic("Could not create logical device", null, .{});

        const queue_families = [_]?u32{ self.QueueFamilies.Graphics, self.QueueFamilies.Present };

        var queue_create_infos = try std.ArrayList(c.VkDeviceQueueCreateInfo).initCapacity(allocator, queue_families.len);
        defer queue_create_infos.deinit();

        for (queue_families) |family| {
            if (family == null) {
                continue;
            }

            try queue_create_infos.append(c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = family.?,
                .queueCount = 1,
                .pQueuePriorities = &queue_priority,
            });

            // TODO: add smarter method (add more families if one does not support graphics, present, etc.)
            if (self.QueueFamilies.Graphics == self.QueueFamilies.Present) {
                break;
            }
        }

        const device_features = c.VkPhysicalDeviceFeatures{};

        // TODO: search for this prior to make sure its available
        const device_extensions = [_][*:0]const u8{
            "VK_KHR_portability_subset",
            c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        };

        const create_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pQueueCreateInfos = queue_create_infos.items.ptr,
            .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
            .pEnabledFeatures = &device_features,
            // device specific extensions
            .enabledExtensionCount = device_extensions.len,
            .ppEnabledExtensionNames = &device_extensions,
            // these are no longer used
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
        };

        const result = c.vkCreateDevice(self.Physical, &create_info, VulkanAllocator, &self.Device);
        if (result != c.VK_SUCCESS) {
            Panic("Could not create logical device", result, .{});
        }

        self.QueryQueues();
    }

    pub fn PickPhsyicalDevice(self: *Device) void {
        errdefer @panic("Could not pick physical devices!");

        var device_count: u32 = 0;
        _ = c.vkEnumeratePhysicalDevices(CurrentRenderer.Instance, &device_count, null);

        if (device_count == 0) {
            Panic("Could not find any physical devices with Vulkan support!", null, .{});
        }

        const physical_devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
        defer allocator.free(physical_devices);

        const result = c.vkEnumeratePhysicalDevices(CurrentRenderer.Instance, &device_count, physical_devices.ptr);

        if (result != c.VK_SUCCESS) {
            Panic("Could not enumerate physical devices", result, .{});
        }

        // find the best device from our list
        const physical_device: c.VkPhysicalDevice = blk: {
            for (physical_devices) |device| {
                if (IsPhysicalDeviceSuitable(device)) {
                    break :blk device;
                }
            }
            Panic("Cannot find a suitable device!", null, .{});
        };

        self.Physical = physical_device;
    }

    fn GetBestSurfaceFormat(self: Device) c.VkSurfaceFormatKHR {
        errdefer @panic("Could not get surface formats");

        const surface = CurrentRenderer.Surface;

        var format_count: u32 = 0;
        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(self.Physical, surface, &format_count, null);

        const formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
        defer allocator.free(formats);

        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(self.Physical, surface, &format_count, formats.ptr);

        for (formats) |format| {
            if (format.format == c.VK_FORMAT_B8G8R8_SRGB) {
                return format;
            }
        }

        return formats[0];
    }

    pub fn Destroy(self: Device) void {
        self.QueueFamilies.Destroy();

        if (self.Device != null) {
            c.vkDestroyDevice(self.Device, VulkanAllocator);
        }
    }
};

pub fn CreateShaderModule(buffer: []u8) c.VkShaderModule {
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = buffer.len,
        .pCode = @alignCast(@ptrCast(buffer.ptr)),
    };

    var shader: c.VkShaderModule = null;

    const result = c.vkCreateShaderModule(CurrentRenderer.GetDevice().Device, &create_info, VulkanAllocator, &shader);
    if (result != c.VK_SUCCESS) {
        Panic("Could not create shader module", result, .{});
    }
    return shader;
}

pub fn DestroyShaderModule(shader: c.VkShaderModule) void {
    c.vkDestroyShaderModule(CurrentRenderer.GetDevice().Device, shader, VulkanAllocator);
}

pub const ShaderList = struct {
    Fragment: c.VkShaderModule,
    Vertex: c.VkShaderModule,

    pub const ShaderType = enum {
        Vertex,
        Fragment,
    };

    pub const ShaderInfo = struct {
        Shader: c.VkShaderModule,
        ShaderType: ShaderType,

        pub fn GetStageBit(self: ShaderInfo) u32 {
            return switch (self.ShaderType) {
                .Vertex => c.VK_SHADER_STAGE_VERTEX_BIT,
                .Fragment => c.VK_SHADER_STAGE_FRAGMENT_BIT,
            };
        }
    };

    pub fn GetShaderStages(self: ShaderList) []ShaderInfo {
        errdefer Panic("Could not allocate shader stages", null, .{});
        var shader_stages = try std.ArrayList(ShaderInfo).initCapacity(allocator, 2);

        if (self.Vertex != null) {
            try shader_stages.append(.{ .Shader = self.Vertex, .ShaderType = .Vertex });
        }
        if (self.Fragment != null) {
            try shader_stages.append(.{ .Shader = self.Fragment, .ShaderType = .Fragment });
        }

        return shader_stages.items;
    }
};

pub const RenderPass = struct {
    RenderPass: c.VkRenderPass = null,
    CommandBuffer: ?*CommandBuffer = null,

    pub fn Create(self: *RenderPass, swapchain: Swapchain) void {
        AssertRendererExists(.{});

        const color_attachment = c.VkAttachmentDescription{
            .format = swapchain.ImageFormat.format,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,

            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,

            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const color_attachment_ref = c.VkAttachmentReference{
            .attachment = 0,
            .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const subpass = c.VkSubpassDescription{
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_attachment_ref,
        };

        const subpass_dependency = c.VkSubpassDependency{
            .srcSubpass = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = 0,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        };

        const render_pass_info = c.VkRenderPassCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = 1,
            .pAttachments = &color_attachment,
            .subpassCount = 1,
            .pSubpasses = &subpass,

            .dependencyCount = 1,
            .pDependencies = &subpass_dependency,
        };

        const result = c.vkCreateRenderPass(CurrentRenderer.GetDevice().Device, &render_pass_info, VulkanAllocator, &self.RenderPass);
        if (result != c.VK_SUCCESS) {
            Panic("Could not create renderpass!", result, .{});
        }
    }

    pub fn Begin(self: RenderPass) void {
        if (self.RenderPass == null) {
            Panic("Renderpass not previously created", null, .{});
        }

        const extent = CurrentRenderer.Swapchain.Extent;

        const renderer = CurrentRenderer;
        const clear_color = c.VkClearValue{ .color = .{ .float32 = 1.0 } };
        const begin_info = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = self.RenderPass,
            .framebuffer = renderer.Swapchain.Framebuffers[renderer.GetFrameIndex()],
            .renderArea = .{
                .extent = .{ .width = extent.Width(), .height = extent.Height() },
                .offset = .{ .x = 0, .y = 0 },
            },
            .pClearValues = &clear_color,
            .clearValueCount = 1,
            .pNext = null,
        };

        const frame = renderer.GetFrame();

        self.CommandBuffer = frame.CommandBuffer;

        const status = c.vkCmdBeginRenderPass(self.CommandBuffer.?.CommandBuffer, &begin_info, c.VK_SUBPASS_CONTENTS_INLINE);
        if (status != c.VK_SUCCESS) {
            Panic("Could not begin render pass", status, .{});
        }
    }

    pub fn End(self: RenderPass) void {
        if (self.CommandBuffer == null) {
            Panic("Command buffer is null when starting renderpass!", null, .{});
        }
        c.vkCmdEndRenderPass(self.CommandBuffer.?.CommandBuffer);
    }

    pub fn Destroy(self: RenderPass) void {
        const device = CurrentRenderer.GetDevice().Device;

        c.vkDestroyRenderPass(device, self.RenderPass, VulkanAllocator);
    }
};

pub const GraphicsPipeline = struct {
    Shaders: ShaderList = .{ .Fragment = null, .Vertex = null },
    Layout: c.VkPipelineLayout = null,

    Pipeline: c.VkPipeline = null,

    RenderPass: RenderPass = RenderPass{},

    pub fn Create(self: *GraphicsPipeline, shader_list: ShaderList) void {
        AssertRendererExists(.{});

        self.Shaders = shader_list;

        const specialization_info = c.VkSpecializationInfo{ .mapEntryCount = 0, .pMapEntries = null, .dataSize = 0, .pData = null };

        const shader_stages = self.Shaders.GetShaderStages();
        defer allocator.free(shader_stages);

        errdefer Panic("Could not allocate memory for Graphics Pipeline!", null, .{});

        var shader_create_info = try std.ArrayList(c.VkPipelineShaderStageCreateInfo).initCapacity(allocator, 2);
        defer shader_create_info.deinit();

        for (shader_stages) |stage| {
            const info = c.VkPipelineShaderStageCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = stage.GetStageBit(),
                .module = stage.Shader,
                .pName = "main",
                .pSpecializationInfo = &specialization_info,
            };
            try shader_create_info.append(info);
        }

        const dynamic_states = [_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state_info = c.VkPipelineDynamicStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamic_states.len,
            .pDynamicStates = &dynamic_states,
        };

        const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = 0,
            .pVertexBindingDescriptions = null,
            .vertexAttributeDescriptionCount = 0,
            .pVertexAttributeDescriptions = null,
        };

        const input_assembly_info = c.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = 0,
        };

        const extent = CurrentRenderer.Swapchain.Extent;

        const viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(extent.X()),
            .height = @floatFromInt(extent.Y()),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };

        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = @intCast(extent.X()), .height = @intCast(extent.Y()) },
        };

        const viewport_state = c.VkPipelineViewportStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount = 1,
            .pViewports = &viewport,
            .pScissors = &scissor,
        };

        const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = 0, // TODO: come back to this at shadowmap time
            .rasterizerDiscardEnable = 0,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .lineWidth = 1.0,
            .cullMode = c.VK_CULL_MODE_NONE,
            .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
            // depth bias
            .depthBiasEnable = 0,
            .depthBiasConstantFactor = 0.0,
            .depthBiasClamp = 0.0,
            .depthBiasSlopeFactor = 0.0,
        };

        const multisampling = c.VkPipelineMultisampleStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable = 0,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            .minSampleShading = 1.0,
            .pSampleMask = null,
            .alphaToCoverageEnable = 0,
            .alphaToOneEnable = 0,
        };

        const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
            .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
            .blendEnable = c.VK_FALSE,
            // color blending
            .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .colorBlendOp = c.VK_BLEND_OP_ADD,
            // alpha blending
            .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp = c.VK_BLEND_OP_ADD,
        };

        const color_blend_state_info = c.VkPipelineColorBlendStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments = &color_blend_attachment,
            .blendConstants = @splat(0),
        };

        self.CreateLayout();

        self.RenderPass.Create(CurrentRenderer.Swapchain);

        const pipeline_info = c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            // shader info
            .stageCount = @intCast(shader_create_info.items.len),
            .pStages = shader_create_info.items.ptr,
            // vertex/rasterization
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &input_assembly_info,
            .pViewportState = &viewport_state,
            .pRasterizationState = &rasterizer,
            .pMultisampleState = &multisampling,
            .pDepthStencilState = null,
            .pColorBlendState = &color_blend_state_info,
            .pDynamicState = &dynamic_state_info,
            /////////////////////////////////////////////
            .layout = self.Layout,
            // render pass
            .renderPass = self.RenderPass.RenderPass,
            .subpass = 0,
            ///////////////////////////////////
            .basePipelineIndex = -1,
            .basePipelineHandle = @ptrCast(c.VK_NULL_HANDLE),
        };

        const result = c.vkCreateGraphicsPipelines(CurrentRenderer.GetDevice().Device, null, 1, &pipeline_info, VulkanAllocator, &self.Pipeline);
        if (result != c.VK_SUCCESS) {
            Panic("Failed to create graphics pipeline", result, .{});
        }
    }

    pub fn Bind(self: GraphicsPipeline, cmd: CommandBuffer) void {
        c.vkCmdBindPipeline(cmd.CommandBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.Pipeline);
    }

    fn CreateLayout(self: *GraphicsPipeline) void {
        const pipeline_layout_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 0,
            .pSetLayouts = null,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
        };

        const result = c.vkCreatePipelineLayout(CurrentRenderer.GetDevice().Device, &pipeline_layout_info, VulkanAllocator, &self.Layout);

        if (result != c.VK_SUCCESS) {
            Panic("Could not create graphics pipeline layout", result, .{});
        }
    }

    pub fn Destroy(self: *GraphicsPipeline) void {
        const device = CurrentRenderer.GetDevice().Device;

        self.RenderPass.Destroy();

        if (self.Layout) |layout| {
            c.vkDestroyPipelineLayout(device, layout, null);
        }

        if (self.Pipeline) |pipeline| {
            c.vkDestroyPipeline(device, pipeline, VulkanAllocator);
        }
    }
};

//////////////////////////////////
// Utility Functions
//////////////////////////////////

pub fn Panic(comptime msg: []const u8, result: ?c.VkResult, args: anytype) noreturn {
    Log.ThreadSafe = false;

    Log.Custom(Log.TextColor.Error, "VKPANIC: ", msg, args);

    if (result) |res| {
        Log.Custom(Log.TextColor.Error, " => Msg: ", "{s} ({d})", .{ VkResultStr(res), res });
    }

    Log.WriteChar('\n');

    @panic("Renderer panic occurred");
}

pub fn VkResultStr(result: c.VkResult) []const u8 {
    return switch (result) {
        c.VK_SUCCESS => "VK_SUCCESS",
        c.VK_NOT_READY => "VK_NOT_READY",
        c.VK_TIMEOUT => "VK_TIMEOUT",
        c.VK_EVENT_SET => "VK_EVENT_SET",
        c.VK_EVENT_RESET => "VK_EVENT_RESET",
        c.VK_INCOMPLETE => "VK_INCOMPLETE",
        c.VK_ERROR_OUT_OF_HOST_MEMORY => "VK_ERROR_OUT_OF_HOST_MEMORY",
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => "VK_ERROR_OUT_OF_DEVICE_MEMORY",
        c.VK_ERROR_INITIALIZATION_FAILED => "VK_ERROR_INITIALIZATION_FAILED",
        c.VK_ERROR_DEVICE_LOST => "VK_ERROR_DEVICE_LOST",
        c.VK_ERROR_MEMORY_MAP_FAILED => "VK_ERROR_MEMORY_MAP_FAILED",
        c.VK_ERROR_LAYER_NOT_PRESENT => "VK_ERROR_LAYER_NOT_PRESENT",
        c.VK_ERROR_EXTENSION_NOT_PRESENT => "VK_ERROR_EXTENSION_NOT_PRESENT",
        c.VK_ERROR_FEATURE_NOT_PRESENT => "VK_ERROR_FEATURE_NOT_PRESENT",
        c.VK_ERROR_INCOMPATIBLE_DRIVER => "VK_ERROR_INCOMPATIBLE_DRIVER",
        c.VK_ERROR_TOO_MANY_OBJECTS => "VK_ERROR_TOO_MANY_OBJECTS",
        c.VK_ERROR_FORMAT_NOT_SUPPORTED => "VK_ERROR_FORMAT_NOT_SUPPORTED",
        c.VK_ERROR_FRAGMENTED_POOL => "VK_ERROR_FRAGMENTED_POOL",
        c.VK_ERROR_UNKNOWN => "VK_ERROR_UNKNOWN",
        c.VK_ERROR_OUT_OF_POOL_MEMORY => "VK_ERROR_OUT_OF_POOL_MEMORY",
        c.VK_ERROR_INVALID_EXTERNAL_HANDLE => "VK_ERROR_INVALID_EXTERNAL_HANDLE",
        c.VK_ERROR_FRAGMENTATION => "VK_ERROR_FRAGMENTATION",
        c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => "VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS",
        c.VK_PIPELINE_COMPILE_REQUIRED => "VK_PIPELINE_COMPILE_REQUIRED",
        c.VK_ERROR_NOT_PERMITTED => "VK_ERROR_NOT_PERMITTED",
        c.VK_ERROR_SURFACE_LOST_KHR => "VK_ERROR_SURFACE_LOST_KHR",
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR",
        c.VK_SUBOPTIMAL_KHR => "VK_SUBOPTIMAL_KHR",
        c.VK_ERROR_OUT_OF_DATE_KHR => "VK_ERROR_OUT_OF_DATE_KHR",
        c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => "VK_ERROR_INCOMPATIBLE_DISPLAY_KHR",
        c.VK_ERROR_VALIDATION_FAILED_EXT => "VK_ERROR_VALIDATION_FAILED_EXT",
        c.VK_ERROR_INVALID_SHADER_NV => "VK_ERROR_INVALID_SHADER_NV",
        c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => "VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR",
        c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => "VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR",
        c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => "VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT",
        c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => "VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT",
        c.VK_THREAD_IDLE_KHR => "VK_THREAD_IDLE_KHR",
        c.VK_THREAD_DONE_KHR => "VK_THREAD_DONE_KHR",
        c.VK_OPERATION_DEFERRED_KHR => "VK_OPERATION_DEFERRED_KHR",
        c.VK_OPERATION_NOT_DEFERRED_KHR => "VK_OPERATION_NOT_DEFERRED_KHR",
        c.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => "VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR",
        c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => "VK_ERROR_COMPRESSION_EXHAUSTED_EXT",
        c.VK_INCOMPATIBLE_SHADER_BINARY_EXT => "VK_INCOMPATIBLE_SHADER_BINARY_EXT",
        c.VK_PIPELINE_BINARY_MISSING_KHR => "VK_PIPELINE_BINARY_MISSING_KHR",
        c.VK_ERROR_NOT_ENOUGH_SPACE_KHR => "VK_ERROR_NOT_ENOUGH_SPACE_KHR",
        else => "Unhandled VkResult",
    };
}
