const c = @import("CLibs.zig").c;

const Renderer = @import("Renderer.zig");

const v = @import("Backend/Vulkan.zig");

const std = @import("std");

const ShaderLoadOptions = struct {
    Samplers: u32 = 0,
    UniformBuffers: u32 = 0,
    StorageBuffers: u32 = 0,
    StorageTextures: u32 = 0,
};

// fn ShaderTypeToSDL(shader_type: Shader.Type) c.SDL_GPUShaderStage {
//     switch (shader_type) {
//         Shader.Type.Vertex => {
//             return c.SDL_GPU_SHADERSTAGE_VERTEX;
//         },
//         Shader.Type.Fragment => {
//             return c.SDL_GPU_SHADERSTAGE_FRAGMENT;
//         },
//     }
// }
//
// fn ShaderGetEntrypoint(fmt: c.SDL_GPUShaderFormat) ?[]const u8 {
//     // std.debug.print("shader format: {d}\n", .{fmt});
//     if ((fmt & c.SDL_GPU_SHADERFORMAT_MSL) != 0) {
//         return "main0";
//     }

//     if ((fmt & c.SDL_GPU_SHADERFORMAT_DXIL) != 0 or (fmt & c.SDL_GPU_SHADERFORMAT_SPIRV) != 0) {
//         return "main";
//     }

//     @panic("No GPU shadertype found");
// }

inline fn GetFileExtension(filename: []const u8) []u8 {
    return std.mem.splitBackwardsSequence(u8, filename, ".").next();
}

fn getSupportedShaderFormats() c.SDL_GPUShaderFormat {}

const MAXIMUM_FILE_LENGTH = 1 * 1024 * 1024 * 1024;

const Log = @import("Log.zig");

pub const Shader = struct {
    // Shader: *c.SDL_GPUShader = undefined,
    Shader: c.VkShaderModule = null,
    Initialized: bool = false,

    pub const Type = enum {
        Vertex,
        Fragment,
    };

    pub fn FromFile(renderer: *Renderer, shader_type: Type, filename: []const u8, options: ShaderLoadOptions) !Shader {
        var shader: Shader = Shader{};
        try shader.Load(renderer, shader_type, filename, options);

        return shader;
    }

    pub fn Load(self: *Shader, shader_type: Type, filename: []const u8, options: ShaderLoadOptions) !void {
        errdefer Log.Error("Error loading shader '{s}'", .{filename});

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer if (gpa.deinit() != .ok) @panic("Could not deinit allocator!");

        const allocator = gpa.allocator();

        _ = shader_type;
        _ = options;

        // convert the shader stage (vertex, fragment, etc.) to SDL's values
        // const stage: c.SDL_GPUShaderStage = ShaderTypeToSDL(shader_type);

        // const shader_format: c.SDL_GPUShaderFormat = c.SDL_GetGPUShaderFormats(context.device);
        // const shader_format = c.SDL_GPU_SHADERFORMAT_MSL;
        // const backend_formats = c.SDL_GetGPUShaderFormats(context.Device);

        const file = try std.fs.cwd().openFile(filename, .{});

        // load the full file in
        const buffer = try file.readToEndAlloc(allocator, MAXIMUM_FILE_LENGTH);

        file.close();

        self.Shader = v.CreateShaderModule(buffer);

        // const shader_info: c.SDL_GPUShaderCreateInfo = .{
        //     .code = buffer.ptr,
        //     .code_size = buffer.len,
        //     .entrypoint = ShaderGetEntrypoint(backend_formats).?.ptr,
        //     .format = shader_format,
        //     .stage = stage,

        //     .num_samplers = options.Samplers,
        //     .num_uniform_buffers = options.UniformBuffers,
        //     .num_storage_buffers = options.StorageBuffers,
        //     .num_storage_textures = options.StorageTextures,
        // };

        // self.Shader = c.SDL_CreateGPUShader(context.Device, &shader_info) orelse {
        //     @panic("Failed to create GPU shader");
        // };

        // after the GPU buffer is created, we can free the file contents
        allocator.free(buffer);

        self.Initialized = true;
    }

    pub fn Destroy(self: *Shader) void {
        if (!self.Initialized) {
            Log.Warn("cannot destroy shader: shader has already been released", .{});
            return;
        }

        v.DestroyShaderModule(self.Shader);

        // c.SDL_ReleaseGPUShader(context.Device, self.Shader);
        self.Initialized = false;
    }
};
