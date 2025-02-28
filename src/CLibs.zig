pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");

    @cDefine("SDL_MAIN_HANDLES", {});
    @cInclude("SDL3/SDL_main.h");

    @cInclude("cgltf.h");
});
