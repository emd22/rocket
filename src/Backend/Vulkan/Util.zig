const c = @import("../../CLibs.zig").c;

pub const VULKAN_ALLOCATOR: [*c]c.VkAllocationCallbacks = null;
pub const VULKAN_DEBUG = true;

const RenderError = @import("Error.zig").RenderError;

pub const Log = @import("../../Log.zig");

//////////////////////////////////
// Utility Functions
//////////////////////////////////

pub inline fn TryVk(status: c.VkResult, comptime on_error: []const u8) void {
    if (status == c.VK_SUCCESS) {
        return;
    }
    Panic(on_error, status, .{});
}

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

/// Gets the handle for a function in a Vulkan extension.
///
/// **NOTE**: ensure that the function prototype is using the C calling convention(`callconv(.c)`)!
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
pub inline fn GetExtensionFuncVk(instance: c.VkInstance, comptime FuncProt: type, name: []const u8) RenderError!FuncProt {
    const raw_ptr = c.vkGetInstanceProcAddr(instance, name.ptr);

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

    const function = GetExtensionFuncVk(instance, prot, "vkCreateDebugUtilsMessengerEXT") catch {
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

    const function = GetExtensionFuncVk(instance, prot, "vkDestroyDebugUtilsMessengerEXT") catch {
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

const Renderer = @import("../Vulkan.zig").Renderer;

/// Enables the use of logging debug information from Vulkan's validation layers.
pub fn CreateDebugMessenger(instance: c.VkInstance) RenderError!c.VkDebugUtilsMessengerEXT {
    if (comptime VULKAN_DEBUG == false) {
        return;
    }

    const create_info = c.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,
        .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_DEVICE_ADDRESS_BINDING_BIT_EXT,
        .pfnUserCallback = &DebugMessageCallback,
        .pUserData = null,
        .pNext = null,
        .flags = 0,
    };

    var messenger: c.VkDebugUtilsMessengerEXT = null;

    const result = CreateDebugUtilsMessengerEXT(
        instance,
        &create_info,
        VULKAN_ALLOCATOR,
        &messenger,
    );

    if (result != c.VK_SUCCESS) {
        // TODO: not panic worthy? keep going if we can.
        // Panic("Failed to create Vulkan debug messenger!", result, .{});
        Log.RenError("Could not create debug messenger! (err: {s})", .{VkResultStr(result)});
        return RenderError.CouldNotInitialize;
    }

    return messenger;
}

pub fn DestroyDebugMessenger(instance: c.VkInstance, messenger: c.VkDebugUtilsMessengerEXT) void {
    DestroyDebugUtilsMessengerEXT(instance, messenger, VULKAN_ALLOCATOR);
}
