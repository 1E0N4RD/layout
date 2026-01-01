const Layout = @import("layout").Layout;
const ContentId = Layout.ContentId;

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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

pub const FontId = enum(u16) {
    body,
    h1,
    h2,
    h3,
    user_begin,
    user_end = 0xffff,
};

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
            @panic("");
        }
    } else {
        if (value) |v| {
            return v;
        } else {
            std.log.err("SDL Error: {s}", .{c.SDL_GetError()});
            @panic("");
        }
    }
}

pub const TextureMode = enum {
    strict,
    crop,
    scale,
    stretch,
};

pub const Content = union(enum) {
    rect: struct {
        bg: ?Color,
        fg: Color,
        frame_width: u16,
    },
    text: *c.TTF_Text,
    texture: struct {
        bg: *c.SDL_Texture,
        fg: Color,
        frame_width: u16,
        mode: TextureMode,
    },

    pub fn deinit(self: Content) void {
        switch (self) {
            .rect => {},
            .text => |t| c.TTF_DestroyText(t),
            .texture => {},
        }
    }
};

const SDLContent = @This();

allocator: Allocator,
contents: ArrayList(Content),
fonts: ArrayList(?*c.TTF_Font),
text_engine: *c.TTF_TextEngine,
renderer: *c.SDL_Renderer,

pub fn init(allocator: Allocator, renderer: *c.SDL_Renderer) !SDLContent {
    const text_engine = c.TTF_CreateRendererTextEngine(renderer) orelse {
        std.log.err("Failed to create text engine: {s}", .{c.SDL_GetError()});
        return error.SDLError;
    };
    errdefer c.TTF_DestroyRendererTextEngine(text_engine);

    var fonts = ArrayList(?*c.TTF_Font).empty;
    errdefer fonts.deinit(allocator);

    try fonts.resize(allocator, @intFromEnum(FontId.user_begin));
    for (fonts.items) |*f| f.* = null;

    return .{
        .renderer = renderer,
        .text_engine = text_engine,
        .fonts = fonts,
        .contents = .empty,
        .allocator = allocator,
    };
}

pub fn deinit(self: *SDLContent) void {
    self.fonts.deinit(self.allocator);
    self.clear();
    self.contents.deinit(self.allocator);
    c.TTF_DestroyRendererTextEngine(self.text_engine);
}

pub fn setFont(self: *SDLContent, id: FontId, font: *c.TTF_Font) !void {
    const i: usize = @intFromEnum(id);
    const old_len = self.fonts.items.len;
    if (i >= old_len) {
        try self.fonts.resize(self.allocator, i + 1);
        for (self.fonts.items[old_len..i]) |*f| f.* = null;
    }
    self.fonts.items[i] = font;
}

pub fn getFont(self: *SDLContent, id: FontId) ?*c.TTF_Font {
    const i: usize = @intFromEnum(id);
    if (i >= self.fonts.items.len) return null;
    return self.fonts.items[i];
}

/// Does not take ownership!
pub fn addFont(self: *SDLContent, font: *c.TTF_Font) !FontId {
    const i = self.fonts.items.len;
    try self.fonts.append(self.allocator, font);
    return @enumFromInt(i);
}

pub fn clear(self: *SDLContent) void {
    for (self.contents.items) |content| content.deinit();
    self.contents.clearRetainingCapacity();
}

pub const RectangleOptions = struct {
    background: Color = .transparent,
    frame_color: Color = .black,
    frame_width: u16 = 0,
};

pub fn rectangle(self: *SDLContent, options: RectangleOptions) !Layout.Content {
    const index = self.contents.items.len;

    try self.contents.append(self.allocator, .{ .rect = .{
        .fg = options.frame_color,
        .bg = if (options.background.a != 0) options.background else null,
        .frame_width = options.frame_width,
    } });

    return .{ .index = @intCast(index) };
}

pub const TextOptions = struct {
    font: FontId = .body,
    color: Color = .black,
    wrap: bool = true,
};

pub fn text(self: *SDLContent, str: []const u8, options: TextOptions) !Layout.Content {
    const index = self.contents.items.len;

    const ptr = if (str.len > 0) str.ptr else null;
    const font = self.getFont(options.font) orelse return error.InvalidFont;

    const t = c.TTF_CreateText(self.text_engine, font, ptr, str.len) orelse {
        std.log.err("Failed to create TTF_Text: {s}", .{c.SDL_GetError()});
        return error.SDLError;
    };

    assertSdl(c.TTF_SetTextColor(
        t,
        options.color.r,
        options.color.g,
        options.color.b,
        options.color.a,
    ));

    var w: c_int = undefined;
    var h: c_int = undefined;
    assertSdl(c.TTF_GetTextSize(t, &w, &h));

    try self.contents.append(self.allocator, .{ .text = t });

    return .{
        .index = @intCast(index),

        .w_range = if (options.wrap)
            .initMax(@intCast(w))
        else
            .initExact(@intCast(w)),

        .h_range = if (options.wrap)
            .initMin(@intCast(h))
        else
            .initExact(@intCast(h)),

        .wrap = options.wrap,
    };
}

const TextureOptions = struct {
    frame_color: Color = .black,
    frame_width: u16 = 0,
    mode: TextureMode = .strict,
};

pub fn texture(self: *SDLContent, t: *c.SDL_Texture, options: TextureOptions) !Layout.Content {
    std.log.info("texture size: {} {}", .{ t.w, t.h });
    const index = self.contents.items.len;
    try self.contents.append(self.allocator, .{ .texture = .{
        .bg = t,
        .fg = options.frame_color,
        .frame_width = options.frame_width,
        .mode = options.mode,
    } });
    return .{
        .index = @intCast(index),
        .w_range = switch (options.mode) {
            .strict => .initExact(@intCast(t.w)),
            .crop => .initMax(@intCast(t.w)),
            else => .any,
        },
        .h_range = switch (options.mode) {
            .strict => .initExact(@intCast(t.h)),
            .crop => .initMax(@intCast(t.h)),
            else => .any,
        },
    };
}

pub fn clone(self: *SDLContent, content: Layout.Content) !Layout.Content {
    const original = self.contents.items[content.index];
    const new_index = self.contents.items.len;

    switch (original) {
        .text => |t| {
            const new_text = c.TTF_CreateText(self.text_engine, c.TTF_GetTextFont(t), t.text, 0) orelse {
                std.log.err("Failed to create TTF_Text: {s}", .{c.SDL_GetError()});
                return error.SDLError;
            };
            errdefer c.TTF_DestroyText(new_text);

            var color: Color = undefined;
            assertSdl(c.TTF_GetTextColor(t, &color.r, &color.g, &color.b, &color.a));
            assertSdl(c.TTF_SetTextColor(t, color.r, color.g, color.b, color.a));

            try self.contents.append(self.allocator, .{ .text = new_text });
        },
        .rect, .texture => {
            try self.contents.append(self.allocator, original);
        },
    }

    var res = content;
    res.index = @intCast(new_index);
    return res;
}

pub fn wrap(self: *SDLContent, id: ContentId, width: u16) u16 {
    const content = self.contents.items[id];
    switch (content) {
        .text => |t| {
            assertSdl(c.TTF_SetTextWrapWidth(t, width));
            var h: c_int = undefined;
            assertSdl(c.TTF_GetTextSize(t, null, &h));
            return @intCast(h);
        },
        .texture => unreachable,
        .rect => unreachable,
    }
}

pub fn drawInstruction(self: *SDLContent, instr: Layout.Instruction) !void {
    const content = self.contents.items[instr.content];
    switch (content) {
        .rect => |r| {
            var rect = c.SDL_FRect{
                .x = @floatFromInt(instr.x),
                .y = @floatFromInt(instr.y),
                .w = @floatFromInt(instr.w),
                .h = @floatFromInt(instr.h),
            };

            if (r.bg) |bg| {
                assertSdl(c.SDL_SetRenderDrawColor(
                    self.renderer,
                    bg.r,
                    bg.g,
                    bg.b,
                    bg.a,
                ));
                assertSdl(c.SDL_RenderFillRect(self.renderer, &rect));
            }
            if (r.frame_width != 0) {
                assertSdl(c.SDL_SetRenderDrawColor(
                    self.renderer,
                    r.fg.r,
                    r.fg.g,
                    r.fg.b,
                    r.fg.a,
                ));
                assertSdl(c.SDL_RenderRect(self.renderer, &rect));
            }
        },
        .text => |t| {
            const font = c.TTF_GetTextFont(t);
            const line_skip: u16 = @intCast(c.TTF_GetFontLineSkip(font));
            const max_lines = @divTrunc(instr.h, line_skip);
            var substring: c.TTF_SubString = undefined;
            if (c.TTF_GetTextSubStringForLine(t, max_lines, &substring)) {
                assertSdl(c.TTF_DeleteTextString(t, substring.offset, -1));
            }

            if (!c.TTF_DrawRendererText(
                t,
                @floatFromInt(instr.x),
                @floatFromInt(instr.y),
            )) {
                std.log.err("Failed to draw text: {s}", .{c.SDL_GetError()});
            }
        },
        .texture => |t| {
            const src = switch (t.mode) {
                .stretch => c.SDL_FRect{
                    .w = @floatFromInt(t.bg.w),
                    .h = @floatFromInt(t.bg.h),
                },
                .strict, .crop => c.SDL_FRect{
                    .w = @floatFromInt(instr.w),
                    .h = @floatFromInt(instr.h),
                },
                .scale => unreachable,
            };

            const dest = switch (t.mode) {
                .stretch, .crop, .strict => c.SDL_FRect{
                    .x = @floatFromInt(instr.x),
                    .y = @floatFromInt(instr.y),
                    .w = @floatFromInt(instr.w),
                    .h = @floatFromInt(instr.h),
                },
                .scale => unreachable,
            };
            assertSdl(c.SDL_RenderTexture(self.renderer, t.bg, &src, &dest));

            if (t.frame_width != 0) {
                const rect = c.SDL_FRect{
                    .x = @floatFromInt(instr.x),
                    .y = @floatFromInt(instr.y),
                    .w = @floatFromInt(instr.w),
                    .h = @floatFromInt(instr.h),
                };
                assertSdl(c.SDL_SetRenderDrawColor(
                    self.renderer,
                    t.fg.r,
                    t.fg.g,
                    t.fg.b,
                    t.fg.a,
                ));
                assertSdl(c.SDL_RenderRect(self.renderer, &rect));
            }
        },
    }
}

pub fn drawInstructions(
    self: *SDLContent,
    instructions: []const Layout.Instruction,
) !void {
    for (instructions) |instruction| try self.drawInstruction(instruction);
}
