const c = @import("../../CLibs.zig").c;

const Panic = @import("Util.zig").Panic;
const VULKAN_ALLOCATOR = @import("Util.zig").VULKAN_ALLOCATOR;
const VULKAN_DEBUG = @import("Util.zig").VULKAN_DEBUG;

const std = @import("std");

const Log = @import("../../Log.zig");
const RenderError = @import("Error.zig").RenderError;

const GetCurrentRenderer = @import("../Vulkan.zig").GetCurrentRenderer;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

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
                    GetCurrentRenderer().Surface,
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

        const result = c.vkCreateDevice(self.Physical, &create_info, VULKAN_ALLOCATOR, &self.Device);
        if (result != c.VK_SUCCESS) {
            Panic("Could not create logical device", result, .{});
        }

        self.QueryQueues();
    }

    pub fn PickPhsyicalDevice(self: *Device) void {
        errdefer @panic("Could not pick physical devices!");

        const renderer = GetCurrentRenderer();

        var device_count: u32 = 0;
        _ = c.vkEnumeratePhysicalDevices(renderer.Instance, &device_count, null);

        if (device_count == 0) {
            Panic("Could not find any physical devices with Vulkan support!", null, .{});
        }

        const physical_devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
        defer allocator.free(physical_devices);

        const result = c.vkEnumeratePhysicalDevices(renderer.Instance, &device_count, physical_devices.ptr);

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

    pub fn GetBestSurfaceFormat(self: Device) c.VkSurfaceFormatKHR {
        errdefer @panic("Could not get surface formats");

        const surface = GetCurrentRenderer().Surface;

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
            c.vkDestroyDevice(self.Device, VULKAN_ALLOCATOR);
        }
    }
};
