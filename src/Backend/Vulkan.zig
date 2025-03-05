const std = @import("std");

const Log = @import("../Log.zig");
const c = @import("../CLibs.zig").c;

pub const VULKAN_DEBUG = true;

pub const VkContext = struct {
    Instance: c.VkInstance = undefined,
    AvailableExtensions: ?[]c.VkExtensionProperties = null,
    DebugMessenger: c.VkDebugUtilsMessengerEXT = undefined,

    pub fn Destroy(self: *VkContext) void {
        if (self.AvailableExtensions) |extensions| {
            allocator.free(extensions);
        }
    }
};

pub var Context = VkContext{};

pub const RenderError = error{
    ExtensionNotAvailable,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

fn QueryInstanceExtensions() void {
    errdefer @panic("could not query instance extensions!");

    if (Context.AvailableExtensions != null) {
        return;
    }

    // get the count of the current extensions
    var extension_count: u32 = 0;
    _ = c.vkEnumerateInstanceExtensionProperties(null, &extension_count, null);

    // get the available instance extensions
    Context.AvailableExtensions = try allocator.alloc(c.VkExtensionProperties, extension_count);

    _ = c.vkEnumerateInstanceExtensionProperties(null, &extension_count, Context.AvailableExtensions.?.ptr);

    Log.Info("=== Available Instance Extensions ({d}) ===", .{extension_count});

    for (0..extension_count) |i| {
        const extension = Context.AvailableExtensions.?[i];

        Log.Info("{s} : {d}", .{ extension.extensionName, extension.specVersion });
    }
}

fn CheckExtensionsAvailable(requested: [][*:0]const u8) ?std.ArrayList([*:0]const u8) {
    errdefer @panic("error checking extensions available");

    if (Context.AvailableExtensions == null) {
        QueryInstanceExtensions();
    }

    // we have to use dynamic here as the length is not comptime known
    var extensions_found = try std.DynamicBitSet.initEmpty(allocator, requested.len);

    for (Context.AvailableExtensions.?) |raw_extension| {
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

fn MakeInstanceExtensionList(requested_extensions: [][:0]const u8) std.ArrayList([*:0]const u8) {
    errdefer @panic("could not build extension list");

    var needed_extenion_count: u32 = 0;
    const vk_needed_extensions = c.SDL_Vulkan_GetInstanceExtensions(&needed_extenion_count);

    QueryInstanceExtensions();

    var total_extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, requested_extensions.len + needed_extenion_count);

    for (requested_extensions) |ext| {
        try total_extensions.append(ext.ptr);
    }

    for (0..needed_extenion_count) |i| {
        // const c_str = vk_needed_extensions[i];
        // const len: usize = std.mem.len(c_str);
        // const str = c_str[0..len];

        try total_extensions.append(vk_needed_extensions[i]);
    }

    return total_extensions;
}

pub fn GetExtensionFunc(comptime FuncProt: type, name: []const u8) RenderError!FuncProt {
    const raw_ptr = c.vkGetInstanceProcAddr(Context.Instance, name.ptr);

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
        Context.Instance,
        &create_info,
        null,
        &Context.DebugMessenger,
    );

    if (result != c.VK_SUCCESS) {
        // TODO: not panic worthy? keep going if we can.
        Panic("Failed to create Vulkan debug messenger!", result, .{});
    }
}

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

pub fn Init() RenderError!VkContext {
    const app_name: [:0]const u8 = "Rocket";
    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = app_name.ptr,
        .pEngineName = app_name.ptr,
        .apiVersion = c.VK_MAKE_VERSION(1, 3, 261),
    };

    var requested_extensions = [_][:0]const u8{
        // "VK_EXT_validation_features",
        c.VK_EXT_LAYER_SETTINGS_EXTENSION_NAME,
    };

    var all_extensions = MakeInstanceExtensionList(&requested_extensions);
    defer all_extensions.deinit();

    if (comptime VULKAN_DEBUG) {
        errdefer @panic("cannot add debug extensions");
        try all_extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        try all_extensions.append(c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME);
    }
    Log.Info("Requested to load {d} extensions...", .{all_extensions.items.len});

    const extensions_missing = CheckExtensionsAvailable(all_extensions.items);

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

    const result = c.vkCreateInstance(&instance_info, null, &Context.Instance);

    if (result != c.VK_SUCCESS) {
        Panic("Error creating Vulkan instance", result, .{});
    }

    SetupDebugMessenger();

    return Context;
}

pub fn Destroy() void {
    c.vkDestroyInstance(Context.Instance, null);
}

pub fn Panic(comptime msg: []const u8, result: ?c.VkResult, args: anytype) noreturn {
    Log.ThreadSafe = false;

    Log.Custom(Log.TextColor.Error, "PANIC: ", msg, args);
    Log.Custom(Log.TextColor.Error, " => Msg: ", "{s} ({d})", .{
        if (result) |r| VkResultStr(r) else "[None]",
        result orelse 0,
    });

    Log.WriteChar('\n');

    @panic("Renderer panic occurred");
}

//////////////////////////////////
// Utility Functions
//////////////////////////////////

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
