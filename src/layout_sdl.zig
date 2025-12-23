const Layout = @import("layout").Layout;

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

const std = @import("std");

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
pub const TTFTextMeasure = struct {
    /// Not owning
    fonts: []const *c.TTF_Font,

    pub fn init(fonts: []const *c.TTF_Font) TTFTextMeasure {
        return .{ .fonts = fonts };
    }
    pub fn textMeasure(self: *TTFTextMeasure) Layout.TextMeasure {
        return .{
            .context = @ptrCast(self),
            .measure_codepoint = &measureCodepoint,
            .measure_wrapped_height = &measureWrappedHeight,
        };
    }
};

fn measureCodepoint(context: *anyopaque, font_id: u16, char: u21) u16 {
    const measure: *TTFTextMeasure = @ptrCast(@alignCast(context));
    var advance: c_int = undefined;
    _ = c.TTF_GetGlyphMetrics(measure.fonts[font_id], char, null, null, null, null, &advance);
    return @intCast(advance);
}

fn measureWrappedHeight(context: *anyopaque, font_id: u16, string: []const u8, width: u16) u16 {
    const measure: *TTFTextMeasure = @ptrCast(@alignCast(context));
    var height: c_int = undefined;
    _ = c.TTF_GetStringSizeWrapped(measure.fonts[font_id], string.ptr, string.len, width, null, &height);
    return @intCast(height);
}

fn drawRect(instr: Layout.RectInstruction, renderer: *c.SDL_Renderer) void {
    var rect = c.SDL_FRect{
        .x = @floatFromInt(instr.x),
        .y = @floatFromInt(instr.y),
        .w = @floatFromInt(instr.w),
        .h = @floatFromInt(instr.h),
    };

    if (instr.bg.a != 0) {
        assertSdl(c.SDL_SetRenderDrawColor(renderer, instr.bg.r, instr.bg.g, instr.bg.b, instr.bg.a));
        assertSdl(c.SDL_RenderFillRect(renderer, &rect));
    }
    if (instr.frame_width != 0) {
        assertSdl(c.SDL_SetRenderDrawColor(renderer, instr.fg.r, instr.fg.g, instr.fg.b, instr.fg.a));
        assertSdl(c.SDL_RenderRect(renderer, &rect));
    }
}

fn drawText(
    t: Layout.TextInstruction,
    text_engine: *c.TTF_TextEngine,
    fonts: []const *c.TTF_Font,
) void {
    if (t.fg.a == 0) return;

    const text = assertSdl(
        c.TTF_CreateText(text_engine, fonts[t.font_id], t.string.ptr, t.string.len),
    );
    defer c.TTF_DestroyText(text);
    assertSdl(c.TTF_SetTextWrapWidth(text, t.w));
    assertSdl(c.TTF_SetTextColor(text, t.fg.r, t.fg.g, t.fg.b, t.fg.a));
    assertSdl(c.TTF_DrawRendererText(text, @floatFromInt(t.x), @floatFromInt(t.y)));
}

pub fn drawInstructions(
    renderer: *c.SDL_Renderer,
    text_engine: *c.TTF_TextEngine,
    fonts: []const *c.TTF_Font,
    instructions: []const Layout.Instruction,
) void {
    for (instructions) |instruction| {
        switch (instruction) {
            .rect => |rect| drawRect(rect, renderer),
            .text => |text| drawText(text, text_engine, fonts),
        }
    }
}
