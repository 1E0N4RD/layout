const std = @import("std");
const c = @import("sdl_import.zig").c;

fn Assert(comptime Type: type) type {
    const info = @typeInfo(Type);
    switch (info) {
        .optional => |optional| {
            const child_info = @typeInfo(optional.child);
            switch (child_info) {
                .pointer => {
                    return optional.child;
                },
                else => @compileError("Only optional errors allowed"),
            }
        },
        .pointer => |pointer| {
            if (pointer.size == .c) {
                return *pointer.child;
            } else {
                @compileError("Invalid Type");
            }
        },
        .bool => return void,
        else => @compileError("Invalid Type"),
    }
}

pub fn assertSdl(value: anytype) Assert(@TypeOf(value)) {
    const Type = Assert(@TypeOf(value));
    if (Type == void) {
        if (!value) {
            std.log.err("SDL Error: {s}", .{c.SDL_GetError()});
            @panic("SDLError");
        }
    } else {
        if (value) |v| {
            return v;
        } else {
            std.log.err("SDL Error: {s}", .{c.SDL_GetError()});
            @panic("SDLError");
        }
    }
}

pub fn checkSdl(value: anytype) error{SDLError}!Assert(@TypeOf(value)) {
    const Type = Assert(@TypeOf(value));
    if (Type == void) {
        if (!value) {
            std.log.err("SDL Error: {s}", .{c.SDL_GetError()});
            return error.SDLError;
        }
    } else {
        if (value) |v| {
            return v;
        } else {
            std.log.err("SDL Error: {s}", .{c.SDL_GetError()});
            return error.SDLError;
        }
    }
}

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255 };
    pub const grey = Color{ .r = 100, .g = 100, .b = 100 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    pub fn toSdl(self: Color) c.SDL_Color {
        return .{
            .r = self.r,
            .g = self.g,
            .b = self.b,
            .a = self.a,
        };
    }
};

pub fn createBMPTexture(
    renderer: *c.SDL_Renderer,
    data: []const u8,
) !*c.SDL_Texture {
    const surface = try checkSdl(
        c.SDL_LoadBMP_IO(c.SDL_IOFromConstMem(data.ptr, data.len), true),
    );
    defer c.SDL_DestroySurface(surface);
    return checkSdl(c.SDL_CreateTextureFromSurface(renderer, surface));
}
