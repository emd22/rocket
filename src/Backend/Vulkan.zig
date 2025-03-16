const std = @import("std");

const c = @import("../CLibs.zig").c;

const RenderError = @import("Vulkan/Error.zig").RenderError;
const FUtil = @import("Vulkan/Util.zig");

// Utility imports
const Panic = FUtil.Panic;
const TryVk = FUtil.TryVk;
const VULKAN_ALLOCATOR = FUtil.VULKAN_ALLOCATOR;
const VULKAN_DEBUG = FUtil.VULKAN_DEBUG;

const Log = @import("../Log.zig");
const Device = @import("Vulkan/Device.zig").Device;

//////////////////////////////////////////
// Global Variables
//////////////////////////////////////////

/// The currently selected Vulkan Renderer
var CurrentRenderer: *Renderer = undefined;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

//////////////////////////////////////////
// Public Getter/Utility functions
//////////////////////////////////////////

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

pub const CommandPool = struct {
    CommandPool: c.VkCommandPool = null,

    pub fn Create(self: *CommandPool, queue_family: u32) void {
        const pool_info = c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .queueFamilyIndex = queue_family,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        };

        const status = c.vkCreateCommandPool(CurrentRenderer.GetDevice().Device, &pool_info, VULKAN_ALLOCATOR, &self.CommandPool);
        if (status != c.VK_SUCCESS) {
            Panic("Could not create command pool!", null, .{});
        }
    }

    pub fn Destroy(self: CommandPool) void {
        c.vkDestroyCommandPool(CurrentRenderer.GetDevice().Device, self.CommandPool, VULKAN_ALLOCATOR);
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

        self.CommandPool = command_pool;

        const status = c.vkAllocateCommandBuffers(CurrentRenderer.GetDevice().Device, &buffer_info, &self.CommandBuffer);
        if (status != c.VK_SUCCESS) {
            Panic("Could not allocate command buffer!", status, .{});
        }

        self.Initialized = true;
    }

    inline fn CheckInitialized(self: CommandBuffer) void {
        if (!self.Initialized) {
            Panic("Command buffer has not been initialized!", null, .{});
        }
    }

    pub fn Record(self: *CommandBuffer) void {
        self.CheckInitialized();
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

    pub fn Reset(self: *CommandBuffer) void {
        self.CheckInitialized();
        _ = c.vkResetCommandBuffer(self.CommandBuffer, 0);
    }

    pub fn End(self: *CommandBuffer) void {
        self.CheckInitialized();
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

    Initialized: bool = false,

    Pipeline: ?GraphicsPipeline = null,

    const Self = @This();

    pub fn Create(self: *Self, size: TVec2i) void {
        // swapchains are part of the initialization stage
        AssertRendererExists(.{ .CheckInitialized = false });

        self.CreateSwapchain(size);
        self.CreateSwapchainImages();
        self.CreateImageViews();

        self.Initialized = true;
    }

    fn GetWindowSize() TVec2i {
        var x: i32 = 0;
        var y: i32 = 0;

        if (CurrentRenderer.Window == null or c.SDL_GetWindowSize(CurrentRenderer.Window.?, &x, &y) == false) {
            Log.Error("Could not retreive window size from SDL (err: {s})", .{c.SDL_GetError()});
            return TVec2i{ .v = .{ 0, 0 } };
        }
        return TVec2i{ .v = .{ x, y } };
    }

    pub fn Rebuild(self: *Swapchain, graphics_pipeline: GraphicsPipeline) void {
        // wait until the previous frames have been processed and presented
        CurrentRenderer.WaitForGPUIdle();

        self.Extent = GetWindowSize();

        const device = CurrentRenderer.GetDevice().Device;

        // free our old swapchain and framebuffers
        self.DestroyFramebuffersAndImageViews(device);
        self.DestroyInternalSwapchain(device);

        // recreate swapchain and get the new images
        self.CreateSwapchain(self.Extent);
        self.CreateSwapchainImages();

        // new resized framebuffers and views
        self.CreateImageViews();
        self.CreateSwapchainFramebuffers(graphics_pipeline);
    }

    pub fn GetNextImage(self: *Swapchain, image_available: Semaphore) RenderError!void {
        const result = c.vkAcquireNextImageKHR(CurrentRenderer.GetDevice().Device, self.Swapchain, std.math.maxInt(u64), image_available.Get(), null, &CurrentRenderer.ImageIndex);

        if (result == c.VK_SUCCESS) {} // ignore
        else if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR) {
            self.Rebuild(self.Pipeline.?);
            return RenderError.GraphicsOutOfDate;
        } else {
            Log.Error("Error getting next swapchain image! (err: {s})", .{FUtil.VkResultStr(result)});
        }
    }

    pub fn CreateSwapchainFramebuffers(self: *Swapchain, graphics_pipeline: GraphicsPipeline) void {
        Log.RenDebug("Image view count: {d}", .{self.ImageViews.len});
        self.Framebuffers = allocator.alloc(Framebuffer, self.ImageViews.len) catch {
            Panic("Could not allocate framebuffers", null, .{});
        };

        for (self.ImageViews, 0..) |image_view, index| {
            var views = [_]c.VkImageView{image_view};

            self.Framebuffers[index].Create(&views, graphics_pipeline, self.Extent);
        }

        self.Pipeline = graphics_pipeline;
    }

    fn CreateImageViews(self: *Swapchain) void {
        self.ImageViews = allocator.alloc(c.VkImageView, self.Images.len) catch {
            Panic("Could not allocate image views", null, .{});
        };

        for (self.Images, 0..) |image, index| {
            const create_info = c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.ImageFormat.format,
                .components = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            const result = c.vkCreateImageView(CurrentRenderer.GetDevice().Device, &create_info, null, &self.ImageViews[index]);
            if (result != c.VK_SUCCESS) {
                Panic("Could not create swapchain image view", result, .{});
            }
        }
    }

    inline fn DestroyFramebuffersAndImageViews(self: *Self, device: c.VkDevice) void {
        for (self.ImageViews, 0..) |view, index| {
            self.Framebuffers[index].Destroy();
            c.vkDestroyImageView(device, view, VULKAN_ALLOCATOR);
        }
        allocator.free(self.Framebuffers);
        allocator.free(self.ImageViews);
    }

    inline fn DestroyInternalSwapchain(self: *Self, device: c.VkDevice) void {
        c.vkDestroySwapchainKHR(device, self.Swapchain, VULKAN_ALLOCATOR);
    }

    pub fn Destroy(self: *Self) void {
        const device = CurrentRenderer.GetDevice().Device;

        self.DestroyFramebuffersAndImageViews(device);

        allocator.free(self.Images);

        self.DestroyInternalSwapchain(device);

        self.Initialized = false;
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
        Log.RenInfo("Swapchain - min:{d}, max:{d}", .{ capabilities.minImageCount, capabilities.maxImageCount });

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

        // const indices = [_]u32{ device.QueueFamilies.Graphics.?, device.QueueFamilies.Present.? };

        if (device.QueueFamilies.Graphics == device.QueueFamilies.Present) {
            create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
            create_info.queueFamilyIndexCount = 0;
            create_info.pQueueFamilyIndices = null;
        }
        // else {
        //     create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        //     create_info.queueFamilyIndexCount = 2;
        //     create_info.pQueueFamilyIndices = &indices;
        // }

        result = c.vkCreateSwapchainKHR(device.Device, &create_info, VULKAN_ALLOCATOR, &self.Swapchain);
        if (result != c.VK_SUCCESS) {
            Panic("Could not create swapchain", result, .{});
        }
    }
};

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
            .renderPass = graphics_pipeline.RenderPass.RenderPass,
            .attachmentCount = @intCast(image_views.len),
            .pAttachments = image_views.ptr,
            .width = @intCast(size.Width()),
            .height = @intCast(size.Height()),
            .layers = 1,
        };

        const device = GetCurrentRenderer().GetDevice().Device;

        const result = c.vkCreateFramebuffer(device, &create_info, VULKAN_ALLOCATOR, &self.Framebuffer);
        if (result != c.VK_SUCCESS) {
            Panic("Failed to create framebuffer", result, .{});
        }
    }

    pub fn Destroy(self: *Framebuffer) void {
        const device = CurrentRenderer.GetDevice().Device;

        c.vkDestroyFramebuffer(device, self.Framebuffer, VULKAN_ALLOCATOR);
    }
};

pub const FrameData = struct {
    CommandPool: CommandPool,
    CommandBuffer: CommandBuffer,

    ImageAvailable: Semaphore,
    RenderFinished: Semaphore,
    InFlight: Fence,

    pub fn CreateSynchro(self: *FrameData) void {
        self.ImageAvailable.Create();
        self.RenderFinished.Create();

        self.InFlight.Create();
    }

    pub fn Destroy(self: *FrameData) void {
        self.ImageAvailable.Destroy();
        self.RenderFinished.Destroy();

        self.InFlight.Destroy();
    }
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
            c.vkCreateSemaphore(renderer.GetDevice().Device, &create_info, VULKAN_ALLOCATOR, &self.Semaphore),
            "Could not create semaphore!",
        );
    }

    pub inline fn Get(self: Semaphore) c.VkSemaphore {
        return self.Semaphore;
    }

    pub fn Destroy(self: *Semaphore) void {
        c.vkDestroySemaphore(GetCurrentRenderer().GetDevice().Get(), self.Semaphore, VULKAN_ALLOCATOR);
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
            c.vkCreateFence(renderer.GetDevice().Get(), &create_info, VULKAN_ALLOCATOR, &self.Fence),
            "Could not create fence!",
        );
    }

    const WaitOptions = struct { Timeout: u64 = std.math.maxInt(u64) };

    pub inline fn ResetMany(fences: []c.VkFence) void {
        TryVk(c.vkResetFences(CurrentRenderer.GetDevice().Device, fences.len, &fences.ptr), "Could not reset fences!");
    }

    pub inline fn Reset(self: Fence) void {
        TryVk(c.vkResetFences(CurrentRenderer.GetDevice().Device, 1, &self.Fence), "Error resetting fence");
    }

    pub inline fn WaitForMany(fences: []c.VkFence, options: WaitOptions) void {
        TryVk(
            c.vkWaitForFences(CurrentRenderer.GetDevice().Device, fences.len, &fences.ptr, c.VK_TRUE, options.Timeout),
            "Could not wait for fences!",
        );
    }

    pub inline fn WaitFor(self: Fence, options: WaitOptions) void {
        TryVk(
            c.vkWaitForFences(CurrentRenderer.GetDevice().Device, 1, &self.Fence, c.VK_TRUE, options.Timeout),
            "Could not wait for fences",
        );
    }

    pub inline fn Get(self: Fence) c.VkFence {
        return self.Fence;
    }

    pub fn Destroy(self: Fence) void {
        c.vkDestroyFence(GetCurrentRenderer().GetDevice().Get(), self.Fence, VULKAN_ALLOCATOR);
    }
};

pub fn Assert(cond: bool) void {
    if (!cond) {
        @panic("Renderer assertion failure");
    }
}

pub const Renderer = struct {
    Initialized: bool = false,

    Instance: c.VkInstance = undefined,
    AvailableExtensions: ?[]c.VkExtensionProperties = null,

    DebugMessenger: c.VkDebugUtilsMessengerEXT = null,

    Surface: c.VkSurfaceKHR = null,
    Swapchain: Swapchain = Swapchain{},

    Device: ?Device = null,

    Frames: []FrameData = undefined,
    FrameNumber: u32 = 0,

    Window: ?*c.SDL_Window = null,

    ImageIndex: u32 = 0,

    GPUAllocator: c.VmaAllocator = null,

    const Self = @This();

    const FRAMES_IN_FLIGHT = 2;

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
        Assert(self.GetDevice().QueueFamilies.Graphics != null);

        self.Frames = allocator.alloc(FrameData, FRAMES_IN_FLIGHT) catch {
            Panic("Could not allocate frame data", null, .{});
        };

        const graphics_family = self.GetDevice().QueueFamilies.Graphics.?;

        for (0..self.Frames.len) |index| {
            self.Frames[index].CommandPool.Create(graphics_family);
            self.Frames[index].CommandBuffer.Create(&self.Frames[index].CommandPool);

            self.Frames[index].CreateSynchro();
        }
    }

    pub inline fn GetFrameIndex(self: Self) u32 {
        return (self.FrameNumber);
    }

    pub fn DestroyFrames(self: *Self) void {
        for (self.Frames) |*frame| {
            frame.*.CommandBuffer.Destroy();
            frame.*.CommandPool.Destroy();
            frame.*.Destroy();
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

        self.InitGPUAllocator();

        self.Swapchain.Create(window_size);
        self.InitFrames();

        self.Initialized = true;
    }

    inline fn InitGPUAllocator(self: *Renderer) void {
        const device = self.GetDevice();

        const allocator_info = c.VmaAllocatorCreateInfo{
            .physicalDevice = device.Physical,
            .device = device.Device,
            .instance = self.Instance,
        };

        TryVk(c.vmaCreateAllocator(&allocator_info, &self.GPUAllocator), "Could not initialize VMA allocator");
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

    /// Begins building the next frame and starts recording to the frame's command buffer.
    ///
    /// Returns `RenderError.GraphicsOutOfDate` when the current swapchain or present queue
    /// is out of date from window events or driver notices. This should be handled by the
    /// caller by skipping the current frame. The swapchain is rebuilt internally.
    pub fn BeginFrame(self: *Renderer, pipeline: *GraphicsPipeline) RenderError!void {
        var current_frame = self.GetFrame();

        current_frame.InFlight.WaitFor(.{});

        // if we cannot get the next frame(normally frame out of date), return early with
        // a GraphicsOutOfDate error. This should be handled by the Renderer's Render function
        // to skip the current frame.
        try self.Swapchain.GetNextImage(current_frame.ImageAvailable);

        current_frame.InFlight.Reset();

        var command_buffer = current_frame.CommandBuffer;

        command_buffer.Reset();
        command_buffer.Record();

        pipeline.RenderPass.Begin();
        pipeline.Bind(command_buffer);

        const width, const height = self.Swapchain.Extent.v;

        const viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        c.vkCmdSetViewport(command_buffer.CommandBuffer, 0, 1, &viewport);

        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = @intCast(width), .height = @intCast(height) },
        };
        c.vkCmdSetScissor(command_buffer.CommandBuffer, 0, 1, &scissor);
    }

    /// Submits the GraphicsQueue to the in-progress frame to be presented.
    fn SubmitFrame(self: Renderer) void {
        var frame = self.GetFrame();

        const wait_stages = [_]c.VkPipelineStageFlags{
            @intCast(c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        };
        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &frame.ImageAvailable.Semaphore,
            .pWaitDstStageMask = &wait_stages,
            // command buffers
            .commandBufferCount = 1,
            .pCommandBuffers = &frame.CommandBuffer.CommandBuffer,
            // signal semaphores
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &frame.RenderFinished.Semaphore,
        };
        // const fence = self.InFlight.Fence;
        TryVk(c.vkQueueSubmit(self.GetDevice().GraphicsQueue, 1, &submit_info, self.GetFrame().InFlight.Fence), "Error submitting draw buffer");
    }

    /// Presents the submitted graphics queue.
    fn PresentFrame(self: *Renderer) void {
        Assert(self.Swapchain.Initialized == true);

        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.GetFrame().RenderFinished.Semaphore,

            .swapchainCount = 1,
            .pSwapchains = &self.Swapchain.Swapchain,
            .pImageIndices = &self.ImageIndex,

            .pResults = null,
        };

        const status = c.vkQueuePresentKHR(self.GetDevice().PresentQueue, &present_info);

        if (status == c.VK_SUCCESS) {} // ignore
        else if (status == c.VK_ERROR_OUT_OF_DATE_KHR or status == c.VK_SUBOPTIMAL_KHR) {
            self.Swapchain.Rebuild(self.Swapchain.Pipeline.?);
        } else {
            Log.Error("Error submitting present queue (err: {s})", .{FUtil.VkResultStr(status)});
        }
    }

    pub inline fn FinishFrame(self: *Renderer, pipeline: GraphicsPipeline) void {
        var command_buffer = self.GetFrame().CommandBuffer;

        pipeline.RenderPass.End();

        command_buffer.End();

        self.SubmitFrame();
        self.PresentFrame();

        self.FrameNumber = (self.FrameNumber + 1) % FRAMES_IN_FLIGHT;
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
            // "VK_LAYER_KHRONOS_validation",
            // "VK_LAYER_KHRONOS_shader_object",
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

        const result = c.vkCreateInstance(&instance_info, VULKAN_ALLOCATOR, &self.Instance);

        if (result != c.VK_SUCCESS) {
            Panic("Error creating Vulkan instance", result, .{});
        }

        Log.RenInfo("Successfully created instance!", .{});

        self.DebugMessenger = FUtil.CreateDebugMessenger(self.Instance) catch blk: {
            Log.RenError("Error creating debug messenger", .{});
            break :blk null;
        };
    }

    pub fn SelectDevice(self: *Self, device: Device) void {
        self.Device = device;
    }

    pub fn AttachToWindow(self: *Self, window: *c.SDL_Window) void {
        const success = c.SDL_Vulkan_CreateSurface(window, self.Instance, VULKAN_ALLOCATOR, &self.Surface);

        if (!success) {
            Log.RenFatal("Could not attach Vulkan instance to window! [SDLError: {s}]\n", .{c.SDL_GetError()});
            @panic("Renderer error");
        }

        self.Window = window;
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
        self.DestroyFrames();

        if (self.Surface) |surface| {
            c.vkDestroySurfaceKHR(self.Instance, surface, VULKAN_ALLOCATOR);
        }
        self.GetDevice().Destroy();

        if (self.DebugMessenger != null) {
            FUtil.DestroyDebugMessenger(self.Instance, self.DebugMessenger);
        }

        c.vkDestroyInstance(self.Instance, VULKAN_ALLOCATOR);
        if (self.AvailableExtensions) |extensions| {
            allocator.free(extensions);
        }

        allocator.free(self.Frames);

        if (self.GPUAllocator != null) {
            c.vmaDestroyAllocator(self.GPUAllocator);
        }

        self.Initialized = false;
    }
};

pub fn CreateShaderModule(buffer: []u8) c.VkShaderModule {
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = buffer.len,
        .pCode = @alignCast(@ptrCast(buffer.ptr)),
    };

    var shader: c.VkShaderModule = null;

    const result = c.vkCreateShaderModule(CurrentRenderer.GetDevice().Device, &create_info, VULKAN_ALLOCATOR, &shader);
    if (result != c.VK_SUCCESS) {
        Panic("Could not create shader module", result, .{});
    }
    return shader;
}

pub fn DestroyShaderModule(shader: c.VkShaderModule) void {
    c.vkDestroyShaderModule(CurrentRenderer.GetDevice().Device, shader, VULKAN_ALLOCATOR);
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
            Log.RenInfo("Added vertex shader", .{});
        }
        if (self.Fragment != null) {
            try shader_stages.append(.{ .Shader = self.Fragment, .ShaderType = .Fragment });
            Log.RenInfo("Added fragment shader", .{});
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

        const result = c.vkCreateRenderPass(CurrentRenderer.GetDevice().Device, &render_pass_info, VULKAN_ALLOCATOR, &self.RenderPass);
        if (result != c.VK_SUCCESS) {
            Panic("Could not create renderpass!", result, .{});
        }
    }

    pub fn Begin(self: *RenderPass) void {
        if (self.RenderPass == null) {
            Panic("Renderpass not previously created", null, .{});
        }

        const extent = CurrentRenderer.Swapchain.Extent;

        const renderer = CurrentRenderer;

        const clear_color = c.VkClearValue{ .color = .{ .float32 = @splat(1.0) } };
        const begin_info = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = self.RenderPass,
            .framebuffer = renderer.Swapchain.Framebuffers[renderer.ImageIndex].Framebuffer,
            .renderArea = .{
                .extent = .{ .width = @intCast(extent.Width()), .height = @intCast(extent.Height()) },
                .offset = .{ .x = 0, .y = 0 },
            },
            .pClearValues = &clear_color,
            .clearValueCount = 1,
            .pNext = null,
        };

        const frame = renderer.GetFrame();

        self.CommandBuffer = &frame.CommandBuffer;
        Assert(self.CommandBuffer != null);

        c.vkCmdBeginRenderPass(self.CommandBuffer.?.CommandBuffer, &begin_info, c.VK_SUBPASS_CONTENTS_INLINE);
    }

    pub fn End(self: RenderPass) void {
        if (self.CommandBuffer == null) {
            Panic("Command buffer is null when starting renderpass!", null, .{});
        }
        c.vkCmdEndRenderPass(self.CommandBuffer.?.CommandBuffer);
    }

    pub fn Destroy(self: RenderPass) void {
        const device = CurrentRenderer.GetDevice().Device;

        c.vkDestroyRenderPass(device, self.RenderPass, VULKAN_ALLOCATOR);
    }
};

pub const Vertex = struct {
    Position: @Vector(3, f32),
    Normal: @Vector(3, f32) = @splat(0),
};

pub const GPUBuffer = struct {
    Buffer: c.VkBuffer,

    pub const Usage = enum(i32) {
        Vertices = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
    };

    pub fn Create(self: *GPUBuffer, usage: Usage, size: u64) void() {
        const create_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = @intFromEnum(usage),
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .flags = 0,
        };

        const device = CurrentRenderer.GetDevice();
        const status = c.vkCreateBuffer(device.Device, &create_info, FUtil.VULKAN_ALLOCATOR, &self.Buffer);
        if (status != c.VK_SUCCESS) {
            Panic("Could not create GPU buffer! (usage: {s})", status, .{std.enums.tagName(Usage, usage)});
        }
    }

    pub fn Destroy(self: *GPUBuffer) void {
        const device = CurrentRenderer.GetDevice();

        c.vkDestroyBuffer(device.Device, self.Buffer, FUtil.VULKAN_ALLOCATOR);
    }
};

pub const GraphicsPipeline = struct {
    Shaders: ShaderList = .{ .Fragment = null, .Vertex = null },
    Layout: c.VkPipelineLayout = null,

    Pipeline: c.VkPipeline = null,

    RenderPass: RenderPass = RenderPass{},

    fn MakeVertexInfo() struct { binding: c.VkVertexInputBindingDescription, attributes: []c.VkVertexInputAttributeDescription } {
        const binding_desc = c.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        const attribs = [_]c.VkVertexInputAttributeDescription{
            .{ .binding = 0, .location = 0, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = 0 },
            .{ .binding = 0, .location = 1, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = @offsetOf(Vertex, "Normal") },
        };

        const attributes: []c.VkVertexInputAttributeDescription = allocator.alloc(c.VkVertexInputAttributeDescription, attribs.len) catch {
            Panic("Error making vertex attribute list", null, .{});
        };

        std.mem.copyForwards(c.VkVertexInputAttributeDescription, attributes, &attribs);

        return .{ .binding = binding_desc, .attributes = attributes };
    }

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
            Log.RenDebug("Added shader (Vertex: {s}) (VertexBit: {s})", .{ Log.YesNo(stage.ShaderType == .Vertex), Log.YesNo(info.stage == c.VK_SHADER_STAGE_VERTEX_BIT) });
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

        const vertex_info = MakeVertexInfo();
        defer allocator.free(vertex_info.attributes);

        const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = 1,
            .pVertexBindingDescriptions = &vertex_info.binding,
            .vertexAttributeDescriptionCount = @intCast(vertex_info.attributes.len),
            .pVertexAttributeDescriptions = vertex_info.attributes.ptr,
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
            .width = @floatFromInt(extent.Width()),
            .height = @floatFromInt(extent.Height()),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };

        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = @intCast(extent.Width()), .height = @intCast(extent.Height()) },
        };

        const viewport_state = c.VkPipelineViewportStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .pViewports = &viewport,
            .scissorCount = 1,
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
            .pNext = null,
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
            .pNext = null,
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
            .basePipelineHandle = null,

            .pTessellationState = null,
            .pNext = null,
        };

        const result = c.vkCreateGraphicsPipelines(CurrentRenderer.GetDevice().Device, null, 1, &pipeline_info, VULKAN_ALLOCATOR, &self.Pipeline);
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

        const result = c.vkCreatePipelineLayout(CurrentRenderer.GetDevice().Device, &pipeline_layout_info, VULKAN_ALLOCATOR, &self.Layout);

        if (result != c.VK_SUCCESS) {
            Panic("Could not create graphics pipeline layout", result, .{});
        }
    }

    pub fn Destroy(self: *GraphicsPipeline) void {
        const device = CurrentRenderer.GetDevice().Device;

        CurrentRenderer.WaitForGPUIdle();

        self.RenderPass.Destroy();

        if (self.Layout) |layout| {
            c.vkDestroyPipelineLayout(device, layout, null);
        }

        if (self.Pipeline) |pipeline| {
            c.vkDestroyPipeline(device, pipeline, VULKAN_ALLOCATOR);
        }
    }
};
