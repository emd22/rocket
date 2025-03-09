const std = @import("std");

const c = @import("CLibs.zig").c;
const Log = @import("Log.zig");
const Shader = @import("Shader.zig").Shader;

const v = @import("Backend/Vulkan.zig");
const VkRenderer = v.Renderer;

const TVec2i = @import("Math/Vector.zig").TVec2i;

// var RenderPipeline: *c.SDL_GPUGraphicsPipeline = undefined;

pub const Vertex = struct {
    Position: @Vector(3, f32),
    Normal: @Vector(3, f32) = @splat(0),
};

pub const Renderer = struct {
    Window: *c.SDL_Window = undefined,
    Device: ?*c.SDL_GPUDevice = null,

    WindowSize: TVec2i = TVec2i{ .v = .{ 1024, 720 } },

    DebugMode: bool = true,
    VSync: bool = true,

    DepthTexture: ?*c.SDL_GPUTexture = null,

    Renderer: *VkRenderer = undefined,

    GraphicsPipeline: v.GraphicsPipeline = v.GraphicsPipeline{},

    const Self = @This();

    pub fn Init(self: *Self) void {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS | c.SDL_INIT_AUDIO)) {
            Panic("Could not initialize SDL", .{});
        }

        // RenderContext.Device = c.SDL_CreateGPUDevice(
        //     c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_MSL | c.SDL_GPU_SHADERFORMAT_DXIL,
        //     RenderContext.DebugMode,
        //     "vulkan", // choose the optimal driver
        // ) orelse {
        //     Panic("Could not create GPU device", .{});
        // };

        // std.debug.print("driver: {s}\n", .{c.SDL_GetGPUDriver(0)});

        self.CreateWindow();

        self.Renderer = VkRenderer.New(self.Window, self.WindowSize) catch {
            Panic("Could not initialize Vulkan renderer", .{});
        };

        var shaders = struct {
            Vertex: Shader = Shader{},
            Fragment: Shader = Shader{},
        }{};

        {
            errdefer Panic("Could not load shaders!", .{});

            try shaders.Vertex.Load(Shader.Type.Vertex, "./shaders/triangle.vert.spv", .{ .UniformBuffers = 1 });
            try shaders.Fragment.Load(Shader.Type.Fragment, "./shaders/main.frag.spv", .{});
        }

        self.GraphicsPipeline.Create(.{
            .Vertex = shaders.Vertex.Shader,
            .Fragment = shaders.Fragment.Shader,
        });

        // const swapchain_success = c.SDL_SetGPUSwapchainParameters(
        //     RenderContext.Device,
        //     RenderContext.Window,
        //     c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,

        //     if (RenderContext.VSync) c.SDL_GPU_PRESENTMODE_VSYNC else c.SDL_GPU_PRESENTMODE_IMMEDIATE,
        // );
        // if (!swapchain_success) {
        //     Log.Error("Could not set renderer swapchain parameters : {s}", .{c.SDL_GetError()});
        // }

        // self.Pipeline = CreateMainPipeline(
        //     &self.Shaders.Vertex,
        //     &self.Shaders.Fragment,
        // );

        // our shaders are now loaded into the graphics pipeline, release them from main memory.

        {
            shaders.Vertex.Destroy();
            shaders.Fragment.Destroy();
        }

        // RenderContext.DepthTexture = c.SDL_CreateGPUTexture(
        //     RenderContext.Device,
        //     &c.SDL_GPUTextureCreateInfo{
        //         .type = c.SDL_GPU_TEXTURETYPE_2D,
        //         .width = @intCast(RenderContext.WindowSize.X()),
        //         .height = @intCast(RenderContext.WindowSize.Y()),
        //         .layer_count_or_depth = 1,
        //         .num_levels = 1,
        //         .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
        //         .format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
        //         .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        //     },
        // );
    }

    fn CreateWindow(self: *Self) void {
        const window_flags: c.SDL_WindowFlags = c.SDL_WINDOW_VULKAN;

        // const driver_str_c = c.SDL_GetGPUDriver(1);
        // const driver_str = std.mem.span(driver_str_c);

        // if (std.mem.eql(u8, driver_str, "vulkan")) {
        //     window_flags |= c.SDL_WINDOW_VULKAN;
        // } else if (std.mem.eql(u8, driver_str, "metal")) {
        //     window_flags |= c.SDL_WINDOW_METAL;
        // } else if (std.mem.eql(u8, driver_str, "direct3d12")) {
        //     // no window flag for dx12?
        // } else {
        //     Panic("No supported rendering backend available", .{});
        // }

        self.Window = c.SDL_CreateWindow(
            "Rocket",
            1024,
            720,
            window_flags,
        ) orelse {
            Panic("Could not create window", .{});
        };

        // c.vkEnumerateDeviceExtensionProperties(physicalDevice: VkPhysicalDevice, pLayerName: [*c]const u8, pPropertyCount: [*c]u32, pProperties: [*c]VkExtensionProperties)
    }

    pub fn Destroy(self: *Self) void {
        self.GraphicsPipeline.Destroy();

        self.Renderer.Free();

        // c.SDL_ReleaseGPUTexture(RenderContext.Device, RenderContext.DepthTexture);

        // c.SDL_ReleaseWindowFromGPUDevice(RenderContext.Device, RenderContext.Window);

        c.SDL_DestroyWindow(self.Window);
        // c.SDL_DestroyGPUDevice(RenderContext.Device);

        c.SDL_Quit();
    }

    // fn CreateMainPipeline(vertex_shader: *Shader, fragment_shader: *Shader) *c.SDL_GPUGraphicsPipeline {
    //     const vertex_input_state = c.SDL_GPUVertexInputState{
    //         .vertex_buffer_descriptions = &[_]c.SDL_GPUVertexBufferDescription{
    //             .{
    //                 .slot = 0,
    //                 .pitch = @sizeOf(Vertex),
    //                 .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
    //                 .instance_step_rate = 0,
    //             },
    //         },
    //         .num_vertex_buffers = 1,
    //         .vertex_attributes = &[_]c.SDL_GPUVertexAttribute{
    //             // Positions
    //             .{
    //                 .location = 0,
    //                 .buffer_slot = 0,
    //                 .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
    //                 .offset = 0,
    //             },
    //             // Normals
    //             .{
    //                 .location = 1,
    //                 .buffer_slot = 0,
    //                 .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
    //                 .offset = @sizeOf(f32) * 3,
    //             },
    //         },
    //         .num_vertex_attributes = 2,
    //     };

    //     const target_info = c.SDL_GPUGraphicsPipelineTargetInfo{
    //         .num_color_targets = 1,
    //         .color_target_descriptions = &[_]c.SDL_GPUColorTargetDescription{
    //             .{
    //                 .format = c.SDL_GetGPUSwapchainTextureFormat(
    //                     RenderContext.Device,
    //                     RenderContext.Window,
    //                 ),
    //             },
    //         },
    //         .has_depth_stencil_target = true,
    //         .depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
    //     };

    //     const pipeline_create_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
    //         .target_info = target_info,
    //         .vertex_input_state = vertex_input_state,
    //         .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
    //         .vertex_shader = vertex_shader.Shader,
    //         .fragment_shader = fragment_shader.Shader,
    //         .rasterizer_state = c.SDL_GPURasterizerState{
    //             .front_face = c.SDL_GPU_FRONTFACE_CLOCKWISE,
    //             .fill_mode = c.SDL_GPU_FILLMODE_FILL,
    //             .cull_mode = c.SDL_GPU_CULLMODE_NONE,
    //         },
    //         .depth_stencil_state = .{
    //             .enable_depth_write = true,
    //             .enable_depth_test = true,
    //             .enable_stencil_test = false,
    //             .compare_op = c.SDL_GPU_COMPAREOP_LESS,
    //         },
    //     };

    //     return c.SDL_CreateGPUGraphicsPipeline(
    //         RenderContext.Device,
    //         &pipeline_create_info,
    //     ) orelse {
    //         Panic("Failed to create render pipeline!", .{});
    //     };
    // }
}{};

pub fn Panic(comptime msg: []const u8, args: anytype) noreturn {
    Log.ThreadSafe = false;

    Log.Custom(Log.TextColor.Error, "PANIC: ", msg, args);
    const err = @as(?[*:0]const u8, c.SDL_GetError()) orelse "[null error]";
    Log.Custom(Log.TextColor.Error, " => Msg: ", "{s}", .{err});

    @panic("Renderer panic occurred");
}
