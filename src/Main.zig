const std = @import("std");

const m = @import("Math.zig");

pub const c = @import("CLibs.zig").c;

pub const Shader = @import("Shader.zig").Shader;
var DataHandler = @import("GPUMem.zig").DataHandler;

const Log = @import("Log.zig");

const FRenderer = @import("Renderer.zig");

var Renderer = FRenderer.Renderer;
const Vertex = FRenderer.Vertex;

var test_mesh: Mesh = Mesh{};
var running: bool = true;

const PerspectiveCamera = @import("Camera.zig").PerspectiveCamera;

var Player = struct {
    Camera: PerspectiveCamera(.{ .AspectRatio = 1024 / 720 }) = .{},
    Position: m.TVec3 = m.Vec3(0, 0, -2),
}{};

const Control = struct {
    IsDown: bool,
};

var DeltaTime: f32 = 0.1;

var Controls = struct {
    Gpa: std.heap.GeneralPurposeAllocator(.{}) = .{},
    Allocator: std.mem.Allocator = undefined,
    ControlMap: []Control = undefined,
    MouseLocked: bool = false,

    const MaxKeys = 300;
    const Self = @This();

    fn AllocControlMap(self: *Self) void {
        self.ControlMap = self.Allocator.alloc(Control, MaxKeys) catch {
            FRenderer.Panic("Could not allocate control map!", .{});
        };
    }

    pub fn Init(self: *Self) void {
        self.Gpa = std.heap.GeneralPurposeAllocator(.{}){};
        self.Allocator = self.Gpa.allocator();

        self.AllocControlMap();
    }

    pub fn UpdateControl(self: *Self, event: *c.SDL_KeyboardEvent) void {
        const scancode = event.scancode;

        if (scancode > MaxKeys) {
            Log.Warn("key scancode is higher than the allocated key map, ignoring...", .{});
            return;
        }

        self.ControlMap[scancode].IsDown = event.down;
    }

    pub fn LockMouse(self: *Self, value: bool) void {
        self.MouseLocked = value;
        if (!c.SDL_SetWindowRelativeMouseMode(Renderer.Window, self.MouseLocked)) {
            Log.Error("Could not lock mouse! ({s})", .{c.SDL_GetError()});
        }
    }

    pub inline fn IsControlDown(self: *Self, keycode: u32) bool {
        return self.ControlMap[keycode].IsDown;
    }

    pub fn Destroy(self: Self) void {
        self.Allocator.free(self.ControlMap);
    }
}{};

fn ProcessEvents() void {
    var event: c.SDL_Event = undefined;

    while (c.SDL_PollEvent(&event)) {
        switch (event.type) {
            c.SDL_EVENT_QUIT => {
                std.debug.print("Exitting...\n", .{});
                running = false;
            },
            c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
                if (event.key.repeat) {
                    break;
                }

                Controls.UpdateControl(&event.key);
                // Log.Info("Control: [{d}]: {d}", .{ event.key.scancode, @intFromBool(Controls.IsControlDown(event.key.scancode)) });
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                OnMouseMove(event.motion.xrel, event.motion.yrel);
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                // std.debug.print("Button: {d}\n", .{event.button.button});
                if (event.button.button == 1) {
                    Controls.LockMouse(true);
                }
            },
            else => {},
        }
    }
}

pub fn OnMouseMove(xrel: f32, yrel: f32) void {
    if (!Controls.MouseLocked) {
        return;
    }

    // Player.Camera.RotateAxis(.X, -0.001 * yrel * DeltaTime);
    // Player.Camera.RotateAxis(.Y, -0.001 * xrel * DeltaTime);
    //
    Player.Camera.Rotate(m.Vec3(-0.001 * xrel * DeltaTime, 0.001 * yrel * DeltaTime, 0));

    // var qa = m.TQuat.Identity();
    // var qb = m.TQuat.Identity();

    // qa.Rotate(&.{.Y}, -0.001 * xrel * DeltaTime);
    // qb.Rotate(&.{.X}, -0.001 * yrel * DeltaTime);

    // Player.Camera.Camera.Rotation.Multiply(qa);
    // Player.Camera.Camera.Rotation.Multiply(qb);
    //
    // Player.Camera.Camera.Rotation.Normalize();

    Player.Camera.NeedsUpdate = true;
}

// var CamPos = m.Vec3(0, 0, 4);
var ModelMatrix: m.Mat4 = m.Mat4.Identity();
var ModelRotation: m.TQuat = m.TQuat.Identity();

pub fn ObjectRotate() void {
    // ModelRotation.Rotate(&.{.X}, 0.01);
    ModelMatrix = m.Mat4.FromQuaternion(ModelRotation, m.Vec3(0, 0, -2));
}

var LastTick: u64 = 0;

fn Render() void {
    const CurrentTick = c.SDL_GetTicksNS();

    DeltaTime = @as(f32, @floatFromInt(CurrentTick - LastTick)) / 1_000_000.0;

    // const command_buffer = c.SDL_AcquireGPUCommandBuffer(RenderContext.Device) orelse {
    //     FRenderer.Panic("Could not acquire command buffer", .{});
    // };

    // var swapchain_texture: ?*c.SDL_GPUTexture = null;
    // if (!c.SDL_WaitAndAcquireGPUSwapchainTexture(
    //     command_buffer,
    //     RenderContext.Window,
    //     &swapchain_texture,
    //     null,
    //     null,
    // )) {
    //     FRenderer.Panic("Could not acquire swapchain", .{});
    // }

    // if (swapchain_texture == null) {
    //     FRenderer.Panic("Swapchain texture is null", .{});
    // }

    ObjectRotate();

    const mvp_matrix = ModelMatrix.Multiply(Player.Camera.GetVPMatrix());
    _ = mvp_matrix;

    // const color_target_info: c.SDL_GPUColorTargetInfo = .{
    //     .texture = swapchain_texture,
    //     .clear_color = c.SDL_FColor{ .r = 0, .g = 0, .b = 0, .a = 1.0 },
    //     .load_op = c.SDL_GPU_LOADOP_CLEAR,
    //     .store_op = c.SDL_GPU_STOREOP_STORE,
    // };

    // const depth_target_info = c.SDL_GPUDepthStencilTargetInfo{
    //     .texture = RenderContext.DepthTexture,
    //     .cycle = true,
    //     .clear_depth = 1,
    //     .clear_stencil = 0,
    //     .load_op = c.SDL_GPU_LOADOP_CLEAR,
    //     .store_op = c.SDL_GPU_STOREOP_STORE,
    //     .stencil_load_op = c.SDL_GPU_LOADOP_CLEAR,
    //     .stencil_store_op = c.SDL_GPU_STOREOP_STORE,
    // };

    // const render_pass = c.SDL_BeginGPURenderPass(
    //     command_buffer,
    //     &color_target_info,
    //     1,
    //     &depth_target_info,
    // ) orelse return;

    // c.SDL_BindGPUGraphicsPipeline(render_pass, Renderer.Pipeline);
    // c.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);
    // test_mesh.Render(render_pass, command_buffer, &mvp_matrix, &ModelMatrix);

    // c.SDL_EndGPURenderPass(render_pass);

    // if (!c.SDL_SubmitGPUCommandBuffer(command_buffer)) {
    //     FRenderer.Panic("Error submitting GPU buffer", .{});
    // }

    LastTick = CurrentTick;
}

fn HandleControls() void {
    if (Controls.IsControlDown(c.SDL_SCANCODE_D)) {
        Player.Camera.Move(m.Vec3(-0.01 * DeltaTime, 0, 0));
    }
    if (Controls.IsControlDown(c.SDL_SCANCODE_A)) {
        Player.Camera.Move(m.Vec3(0.01 * DeltaTime, 0, 0));
    }

    if (Controls.IsControlDown(c.SDL_SCANCODE_S)) {
        // Player.Camera.MoveAxis(.Z, -0.1);
        Player.Camera.Move(m.Vec3(0, 0, -0.01 * DeltaTime));
    }
    if (Controls.IsControlDown(c.SDL_SCANCODE_W)) {
        Player.Camera.Move(m.Vec3(0, 0, 0.01 * DeltaTime));
        // Player.Camera.MoveAxis(.Z, 0.1);
    }

    if (Controls.IsControlDown(c.SDL_SCANCODE_ESCAPE)) {
        Controls.LockMouse(false);
    }

    if (Controls.IsControlDown(c.SDL_SCANCODE_F)) {
        Log.Info("Camera Matrix: ", .{});
        Player.Camera.Camera.ViewMatrix.Print();
        Player.Camera.Camera.ProjectionMatrix.Print();
    }
}

const Mesh = struct {
    VertexBuffer: ?*c.SDL_GPUBuffer = null,
    VertexCount: u32 = 0,
    IndexBuffer: ?*c.SDL_GPUBuffer = null,
    IndexCount: u32 = 0,

    // fn TransferBufferToGPU(comptime T: type, buffer: []T, output_buffer: ?*c.SDL_GPUBuffer, cmd_buffer: *c.SDL_GPUCommandBuffer) *c.SDL_GPUTransferBuffer {
    // const buffer_size: u32 = @intCast(buffer.len * @sizeOf(T));

    // const transfer_buffer = c.SDL_CreateGPUTransferBuffer(RenderContext.Device, &c.SDL_GPUTransferBufferCreateInfo{
    //     .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
    //     .size = buffer_size,
    // }) orelse {
    //     FRenderer.Panic("Could not upload data to GPU buffer", .{});
    // };

    // const transfer_data_c = c.SDL_MapGPUTransferBuffer(RenderContext.Device, transfer_buffer, false) orelse {
    //     FRenderer.Panic("Error getting mapped transfer buffer!", .{});
    // };

    // const transfer_data: [*]T = @ptrCast(@alignCast(transfer_data_c));

    // copy all data to our transfer buffer
    // std.mem.copyForwards(T, transfer_data[0..buffer.len], buffer);

    // c.SDL_UnmapGPUTransferBuffer(RenderContext.Device, transfer_buffer);

    // const upload_copy_pass = c.SDL_BeginGPUCopyPass(cmd_buffer);

    // c.SDL_UploadToGPUBuffer(
    //     upload_copy_pass,
    //     &c.SDL_GPUTransferBufferLocation{ .transfer_buffer = transfer_buffer, .offset = 0 },
    //     &c.SDL_GPUBufferRegion{ .buffer = output_buffer, .offset = 0, .size = buffer_size },
    //     false,
    // );

    // c.SDL_EndGPUCopyPass(upload_copy_pass);

    // return transfer_buffer;
    // }

    pub fn UploadToGPU(self: *Mesh, vertices: []Vertex, indices: ?[]u32) void {
        _ = self;
        _ = vertices;
        _ = indices;
        // self.VertexCount = @intCast(vertices.len);

        // Log.Info("Mesh vertex count: {d}", .{self.VertexCount});

        // const vbo_size: u32 = @intCast(@sizeOf(Vertex) * vertices.len);

        // const vbo_create_info = c.SDL_GPUBufferCreateInfo{
        //     .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX,
        //     .size = vbo_size,
        // };

        // self.VertexBuffer = c.SDL_CreateGPUBuffer(RenderContext.Device, &vbo_create_info);

        // const upload_cmd_buffer = c.SDL_AcquireGPUCommandBuffer(RenderContext.Device);

        // var index_tbuffer: ?*c.SDL_GPUTransferBuffer = null;

        // if (indices) |t_indices| {
        //     self.IndexCount = @intCast(t_indices.len);

        //     Log.Info("Mesh index count: {d}", .{self.IndexCount});

        //     const ibo_size: u32 = @intCast(@sizeOf(u32) * t_indices.len);
        //     const ibo_create_info = c.SDL_GPUBufferCreateInfo{
        //         .usage = c.SDL_GPU_BUFFERUSAGE_INDEX,
        //         .size = ibo_size,
        //     };
        //     self.IndexBuffer = c.SDL_CreateGPUBuffer(RenderContext.Device, &ibo_create_info);
        //     index_tbuffer = TransferBufferToGPU(u32, indices.?, self.IndexBuffer, upload_cmd_buffer.?);
        // }

        // // submit data to the GPU
        // const vertex_tbuffer = TransferBufferToGPU(Vertex, vertices, self.VertexBuffer, upload_cmd_buffer.?);

        // // submit the command buffer for both transfers
        // if (!c.SDL_SubmitGPUCommandBuffer(upload_cmd_buffer)) {
        //     FRenderer.Panic("Could not submit command buffer", .{});
        // }
        // // release the transfer buffers
        // c.SDL_ReleaseGPUTransferBuffer(RenderContext.Device, vertex_tbuffer);

        // if (index_tbuffer != null) {
        //     c.SDL_ReleaseGPUTransferBuffer(RenderContext.Device, index_tbuffer);
        // }
    }

    pub fn Render(self: Mesh, render_pass: *c.SDL_GPURenderPass, command_buffer: *c.SDL_GPUCommandBuffer, mvp_matrix: *m.Mat4, model_matrix: *m.Mat4) void {
        _ = self;
        _ = render_pass;
        _ = command_buffer;
        _ = mvp_matrix;
        _ = model_matrix;
        // c.SDL_PushGPUVertexUniformData(command_buffer, 0, &mvp_matrix.v, @sizeOf(m.Mat4));
        // c.SDL_PushGPUVertexUniformData(command_buffer, 1, &model_matrix.v, @sizeOf(m.Mat4));

        // c.SDL_BindGPUVertexBuffers(render_pass, 0, &c.SDL_GPUBufferBinding{ .buffer = self.VertexBuffer, .offset = 0 }, 1);

        // if (self.IndexCount != 0) {
        //     c.SDL_BindGPUIndexBuffer(render_pass, &c.SDL_GPUBufferBinding{ .buffer = self.IndexBuffer, .offset = 0 }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
        //     c.SDL_DrawGPUIndexedPrimitives(render_pass, self.IndexCount, 1, 0, 0, 0);
        // } else {
        //     c.SDL_DrawGPUPrimitives(render_pass, self.VertexCount, 1, 0, 0);
        // }
    }
};

const sinfunc = @import("Math/SIMD.zig").fast_sincos_ps;

const FType = @Vector(4, f32);
const UType = @Vector(4, u32);

const gltf = @import("Loader/Gltf.zig");

pub fn main() !void {
    errdefer FRenderer.Panic("Error in main (init)!", .{});

    Renderer.Init();
    defer Renderer.Destroy();

    Controls.Init();
    defer Controls.Destroy();

    var model = gltf.GLTFModel{};
    model.Load("./models/DamagedHelmet.glb");

    if (model.data == null) {
        Log.Error("Could not load model!\n", .{});
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var raw_positions: []f32 = undefined;

    var indices: []u32 = undefined;
    var raw_normals: []f32 = undefined;

    for (0..model.data.?.meshes_count) |mesh_index| {
        const mesh = model.data.?.meshes[mesh_index];
        Log.Info("Mesh: {s}", .{mesh.name});

        for (0..mesh.primitives_count) |prim_index| {
            const primitive = &mesh.primitives[prim_index];

            if (primitive.indices != null) {
                indices = try allocator.alloc(u32, primitive.indices.*.count);

                _ = c.cgltf_accessor_unpack_indices(primitive.indices, indices.ptr, @sizeOf(u32), primitive.indices.*.count);

                // const index_accessor = primitive.indices.*;

                // const buffer_view = index_accessor.buffer_view;
                // const buffer = buffer_view.*.buffer;
                // const stride = index_accessor.stride;
                // const component_type = index_accessor.component_type;

                // for (indices, 0..) |*index, i| {
                //     const offset = buffer_view.*.offset + index_accessor.offset + i * stride;
                //     switch (component_type) {
                //         c.cgltf_component_type_r_16u => {
                //             const ptrv = @as(usize, @intFromPtr(buffer.*.data.?)) + offset;
                //             const idx: *u16 = @ptrCast(@alignCast(@as(*u16, @ptrFromInt(ptrv))));
                //             index.* = idx.*;
                //         },
                //         c.cgltf_component_type_r_32u => {
                //             const ptrv = @as(usize, @intFromPtr(buffer.*.data.?)) + offset;

                //             const idx: *u32 = @ptrCast(@alignCast(@as(*u16, @ptrFromInt(ptrv))));
                //             index.* = idx.*;
                //         },
                //         else => {
                //             std.debug.print("Unsupported index type!\n", .{});
                //             return error.UnsupportedIndexType;
                //         },
                //     }
                // }
            }

            for (0..primitive.attributes_count) |attrib_index| {
                const attribute = &primitive.attributes[attrib_index];

                const data_size = c.cgltf_accessor_unpack_floats(attribute.data, null, 0);
                std.debug.print("data size: {d}\n", .{data_size});

                if (attribute.type == c.cgltf_attribute_type_position) {
                    raw_positions = try allocator.alloc(f32, data_size);
                    _ = c.cgltf_accessor_unpack_floats(attribute.data, raw_positions.ptr, data_size);
                    // _ = c.cgltf_accessor_unpack_floats(attribute.data, &data, 3);
                    // const vertex = Vertex{ .Pos = .{ data[0], data[1], data[2], 1 } };
                    // std.debug.print("Size: {}\n", .{vertex.Pos});
                    // try vertex_buffer.append(vertex);
                } else if (attribute.type == c.cgltf_attribute_type_normal) {
                    raw_normals = try allocator.alloc(f32, data_size);
                    _ = c.cgltf_accessor_unpack_floats(attribute.data, raw_normals.ptr, data_size);
                }

                // if (attribute.type == )
            }
        }
    }

    var vertices: []Vertex = try allocator.alloc(Vertex, raw_positions.len / 3);
    defer allocator.free(vertices);

    var v_index: u32 = 0;
    while (v_index < raw_positions.len) {
        // std.debug.print("x: [{d}, {d}, {d}]\n", .{ raw_positions[v_index], raw_positions[v_index + 1], raw_positions[v_index + 2] });
        vertices[v_index / 3] = Vertex{
            .Position = .{
                raw_positions[v_index],
                raw_positions[v_index + 1],
                raw_positions[v_index + 2],
            },
            .Normal = .{
                raw_normals[v_index],
                raw_normals[v_index + 1],
                raw_normals[v_index + 2],
            },
        };
        // Log.Info("V[{d}]: {}", .{ v_index / 3, vertices[v_index / 3].Pos });
        v_index += 3;
    }
    allocator.free(raw_positions);
    defer allocator.free(indices);

    defer model.Destroy();

    const window_size = Renderer.WindowSize;
    const aspect_ratio: f32 = @as(f32, @floatFromInt(window_size.X())) / @as(f32, @floatFromInt(window_size.Y()));

    Player.Camera.UpdateProjectionMatrix(.{ .AspectRatio = aspect_ratio });

    // var test_mesh_verts = [_]Vertex{
    //     .{ .Pos = .{ -1, -1, 0 } },
    //     .{ .Pos = .{ 1, -1, 0 } },
    //     .{ .Pos = .{ 0, 1, 0 } },
    // };
    //
    // var test_mesh_verts = [_]Vertex{
    //     .{ .Position = .{ -0.5, -0.5, 0.5 } }, // 0: Bottom-left
    //     .{ .Position = .{ 0.5, -0.5, 0.5 } }, // 1: Bottom-right
    //     .{ .Position = .{ 0.5, 0.5, 0.5 } }, // 2: Top-right
    //     .{ .Position = .{ -0.5, 0.5, 0.5 } }, // 3: Top-left

    //     // Back face
    //     .{ .Position = .{ -0.5, -0.5, -0.5 } }, // 4: Bottom-left
    //     .{ .Position = .{ 0.5, -0.5, -0.5 } }, // 5: Bottom-right
    //     .{ .Position = .{ 0.5, 0.5, -0.5 } }, // 6: Top-right
    //     .{ .Position = .{ -0.5, 0.5, -0.5 } }, // 7: Top-left
    // };

    // var test_mesh_indices = [_]u32{
    //     // Front face
    //     0, 1, 2, 0, 2, 3,
    //     // Back face
    //     4, 5, 6, 4, 6, 7,
    //     // Left face
    //     0, 3, 7, 0, 7, 4,
    //     // Right face
    //     1, 2, 6, 1, 6, 5,
    //     // Top face
    //     2, 3, 7, 2, 7, 6,
    //     // Bottom face
    //     0, 1, 5, 0, 5, 4,
    // };

    // test_mesh.UploadToGPU(vertices, indices);
    test_mesh.UploadToGPU(vertices, indices);

    while (running) {
        ProcessEvents();
        HandleControls();

        Player.Camera.Update();

        Render();
    }
}
