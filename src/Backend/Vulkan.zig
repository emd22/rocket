const std = @import("std");

const Log = @import("../Log.zig");
const c = @import("../CLibs.zig").c;

pub const VULKAN_DEBUG = true;

const VulkanAllocator: [*c]c.VkAllocationCallbacks = null;

/// A set of variables and states for Vulkan.
pub const Context = struct {
    Instance: c.VkInstance = undefined,
    AvailableExtensions: ?[]c.VkExtensionProperties = null,

    DebugMessenger: c.VkDebugUtilsMessengerEXT = undefined,

    Surface: c.VkSurfaceKHR = null,
    Swapchain: c.VkSwapchainKHR = null,

    Device: ?Device = null,

    pub fn Destroy(self: *Context) void {
        if (self.AvailableExtensions) |extensions| {
            allocator.free(extensions);
        }
    }
};

/// The currently selected Vulkan Renderer
var CurrentRenderer: *Renderer = undefined;
/// The current `Renderer`'s `Context`
var CurrentContext: *Context = undefined;

pub const RenderError = error{
    ExtensionNotAvailable,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

/// Retrieves the currently selected Renderer
pub fn GetCurrentRenderer() *Renderer {
    return CurrentRenderer;
}

/// Gets the handle for a function in a Vulkan extension.
///
/// ```
/// // the function prototype
/// const prot: type = *const fn (c.VkInstance, i32) void;
/// const func = GetExtensionFunc(prot, "vkSomeFuncEXT");
///
/// // call the retrieved handle
/// func(instance, 10);
///
/// ```
pub fn GetExtensionFunc(comptime FuncProt: type, name: []const u8) RenderError!FuncProt {
    const raw_ptr = c.vkGetInstanceProcAddr(CurrentContext.Instance, name.ptr);

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
) c.VkResult {
    const prot: type = *const fn (c.VkInstance, [*c]const c.VkDebugUtilsMessengerCreateInfoEXT, [*c]const c.VkAllocationCallbacks, [*c]c.VkDebugUtilsMessengerEXT) c.VkResult;

    const function = GetExtensionFunc(prot, "vkCreateDebugUtilsMessengerEXT") catch {
        return c.VK_ERROR_EXTENSION_NOT_PRESENT;
    };

    return function(instance, pCreateInfo, pAllocator, pDebugMessenger);
}

fn DestroyDebugUtilsMessengerEXT(
    instance: c.VkInstance,
    messenger: c.VkDebugUtilsMessengerEXT,
    pAllocator: [*c]const c.VkAllocationCallbacks,
) void {
    const prot: type = *const fn (c.VkInstance, messenger: c.VkDebugUtilsMessengerEXT, pAllocator: [*c]const c.VkAllocationCallbacks) void;

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

pub fn SetupDebugMessenger() void {
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
        CurrentContext.Instance,
        &create_info,
        VulkanAllocator,
        &CurrentContext.DebugMessenger,
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

pub fn SetCurrentRenderer(renderer: *Renderer) void {
    CurrentRenderer = renderer;
    CurrentContext = &renderer.Context;
}

pub const Renderer = struct {
    Initialized: bool = false,
    // NOTE: do not define Context here. Define it in an Init function;
    // If you define it here, for some reason any of the null or undefined values
    // do NOT get set to null, and instead take on a garbage value.
    Context: Context = undefined,

    const Self = @This();

    /// Create a new `Renderer` in memory and initialize it.
    ///
    /// Make sure to call `.Free()` after the `Renderer` is no longer used.
    pub fn New(window: *c.SDL_Window) RenderError!*Self {
        var renderer = allocator.create(Renderer) catch {
            Panic("Could not allocate Renderer instance", null, .{});
        };

        try renderer.Init(window);

        return renderer;
    }

    pub fn Free(self: *Self) void {
        self.Destroy();

        allocator.destroy(self);
    }

    pub fn Init(self: *Self, window: *c.SDL_Window) RenderError!void {
        if (self.Initialized) {
            Log.Warn("Renderer has already been initialized", .{});
            return;
        }

        self.Context = Context{};

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

        self.Initialized = true;
    }

    fn QueryInstanceExtensions(self: *Self) void {
        errdefer @panic("could not query instance extensions!");

        std.debug.print("Query extensions\n", .{});

        if (self.Context.AvailableExtensions != null) {
            Log.Warn("Extensions were previously queried", .{});
            return;
        }

        // get the count of the current extensions
        var extension_count: u32 = 0;
        _ = c.vkEnumerateInstanceExtensionProperties(null, &extension_count, null);

        std.debug.print("Ext count: {d}\n", .{extension_count});

        // get the available instance extensions
        self.Context.AvailableExtensions = try allocator.alloc(c.VkExtensionProperties, extension_count);

        _ = c.vkEnumerateInstanceExtensionProperties(null, &extension_count, self.Context.AvailableExtensions.?.ptr);

        Log.Info("=== Available Instance Extensions ({d}) ===", .{extension_count});

        for (0..extension_count) |i| {
            const extension = self.Context.AvailableExtensions.?[i];

            Log.Info("{s} : {d}", .{ extension.extensionName, extension.specVersion });
        }
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

        if (self.Context.AvailableExtensions == null) {
            self.QueryInstanceExtensions();
        }

        // we have to use dynamic here as the length is not comptime known
        var extensions_found = try std.DynamicBitSet.initEmpty(allocator, requested.len);

        for (self.Context.AvailableExtensions.?) |raw_extension| {
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

        Log.Info("found {d} extensions, requested {d}", .{ extensions_found.count(), requested.len });

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

        const result = c.vkCreateInstance(&instance_info, VulkanAllocator, &self.Context.Instance);

        if (result != c.VK_SUCCESS) {
            Panic("Error creating Vulkan instance", result, .{});
        }

        SetupDebugMessenger();
    }

    pub fn SelectDevice(self: *Self, device: Device) void {
        self.Context.Device = device;
    }

    pub fn GetDevice(self: Self) Device {
        if (self.Context.Device == null) {
            Panic("No device selected!\n", null, .{});
        }
        return self.Context.Device.?;
    }

    pub fn AttachToWindow(self: *Self, window: *c.SDL_Window) void {
        const success = c.SDL_Vulkan_CreateSurface(window, self.Context.Instance, VulkanAllocator, &self.Context.Surface);

        if (!success) {
            Log.RenFatal("Could not attach Vulkan instance to window! [SDLError: {s}]\n", .{c.SDL_GetError()});
            @panic("Renderer error");
        }
    }

    const TVec2i = @import("../Math.zig").TVec2i;

    pub fn CreateSwapchain(self: Self, size: TVec2i) void {
        const device = self.GetDevice();

        var capabilities = c.VkSurfaceCapabilitiesKHR{};
        var result = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device.Physical, self.Context.Surface, &capabilities);

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

        const surface_format = device.GetBestSurfaceFormat();
        // TODO: query and select MAILBOX
        const present_mode = c.VK_PRESENT_MODE_FIFO_KHR;

        var create_info = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = CurrentContext.Surface,
            .minImageCount = image_count,
            .imageFormat = surface_format.format,
            .imageColorSpace = surface_format.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .presentMode = present_mode,
            .preTransform = capabilities.currentTransform,
            // ignore alpha (from blending behind the window)
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .clipped = 1,
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

        result = c.vkCreateSwapchainKHR(device.Device, &create_info, VulkanAllocator, &CurrentContext.Swapchain);
        if (result != c.VK_SUCCESS) {
            Panic("Could not create swapchain", result, .{});
        }
    }

    pub fn Destroy(self: *Self) void {
        if (!self.Initialized) {
            Log.Warn("Renderer has already been destroyed", .{});
            return;
        }

        if (self.Context.Swapchain) |swapchain| {
            c.vkDestroySwapchainKHR(self.GetDevice().Device, swapchain, VulkanAllocator);
        }

        if (self.Context.Surface) |surface| {
            c.vkDestroySurfaceKHR(self.Context.Instance, surface, VulkanAllocator);
        }

        self.GetDevice().Destroy();

        DestroyDebugUtilsMessengerEXT(self.Context.Instance, self.Context.DebugMessenger, VulkanAllocator);
        c.vkDestroyInstance(self.Context.Instance, VulkanAllocator);
        self.Context.Destroy();

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

        for (self.RawFamilies.?, 0..) |family, index| {
            // check for a graphics family
            if ((family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) == 1) {
                self.Graphics = @intCast(index);
            }

            // check for a presentation family
            var present_support: u32 = 0;
            const result = c.vkGetPhysicalDeviceSurfaceSupportKHR(
                device.Physical,
                @as(u32, @intCast(index)),
                CurrentContext.Surface,
                &present_support,
            );
            if (result != c.VK_SUCCESS) {
                Panic("Could not get physical device surface support(presentation queue family)", result, .{});
            }
            Log.Info("Present support: {d}", .{present_support});
            if (present_support > 0) {
                self.Present = @as(u32, @intCast(index));
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

    fn QueryQueues(self: *Device) void {
        c.vkGetDeviceQueue(self.Device, self.QueueFamilies.Graphics.?, 0, &self.GraphicsQueue);
        c.vkGetDeviceQueue(self.Device, self.QueueFamilies.Present.?, 0, &self.PresentQueue);
    }

    pub fn CreateLogicalDevice(self: *Device) void {
        if (self.Physical == null) {
            self.PickPhsyicalDevice();
        }
        if (self.QueueFamilies.Graphics == null) {
            self.QueueFamilies.FindQueueFamilies(self);
        }

        const queue_priority: f32 = 1.0;

        const queue_create_info = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = self.QueueFamilies.Graphics.?,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };

        const device_features = c.VkPhysicalDeviceFeatures{};

        // TODO: search for this prior to make sure its available
        const device_extensions = [_][*:0]const u8{
            "VK_KHR_portability_subset",
            c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        };

        const create_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pQueueCreateInfos = &queue_create_info,
            .queueCreateInfoCount = 1,
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
        _ = c.vkEnumeratePhysicalDevices(CurrentContext.Instance, &device_count, null);

        if (device_count == 0) {
            Panic("Could not find any physical devices with Vulkan support!", null, .{});
        }

        const physical_devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
        defer allocator.free(physical_devices);

        const result = c.vkEnumeratePhysicalDevices(CurrentContext.Instance, &device_count, physical_devices.ptr);

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

        const surface = CurrentContext.Surface;

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
