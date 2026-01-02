const std = @import("std");
const Layout = @import("layout").Layout;
const layout_sdl = @import("layout_sdl");
const SDLContents = layout_sdl.SDLContents;
const c = layout_sdl.c;
const assertSdl = layout_sdl.assertSdl;

const cantarell_bold = @embedFile("assets/Cantarell-Bold.ttf");
const cantarell_regular = @embedFile("assets/Cantarell-Regular.ttf");

const lore_ipsum = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";

const Vec2 = @Vector(2, f64);

const GuiAssets = struct {
    default_cursor: *c.SDL_Cursor,
    ew_cursor: *c.SDL_Cursor,
};

const GuiState = struct {
    action: union(enum) {
        none,
        resize_left_panel,
    },

    width: f32,
    height: f32,

    left_panel_width: f32,
    left_panel_width_min: f32,
    left_panel_width_max: f32,

    left_panel: Layout.Rect,
    vertical_resize_bar: Layout.Rect,
    main_panel: Layout.Rect,
    bottom_panel: Layout.Rect,

    assets: GuiAssets,

    fn updateWindowSize(self: *GuiState, width: f32, height: f32) void {
        self.width = width;
        self.height = height;
        self.left_panel_width_max = width / 2;
        self.left_panel_width = std.math.clamp(
            self.left_panel_width,
            self.left_panel_width_min,
            self.left_panel_width_max,
        );
    }
};

const State = struct {
    gui_state: GuiState,

    fn init(width: f32, height: f32) State {
        return .{
            .gui_state = .{
                .action = .none,
                .width = width,
                .height = height,
                .left_panel_width = 200,
                .left_panel_width_min = 100,
                .left_panel_width_max = width / 2,
                .left_panel = .zero,
                .vertical_resize_bar = .zero,
                .main_panel = .zero,
                .bottom_panel = .zero,

                .assets = .{
                    .default_cursor = assertSdl(c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_DEFAULT)),
                    .ew_cursor = assertSdl(c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_EW_RESIZE)),
                },
            },
        };
    }
};

fn refresh(allocator: std.mem.Allocator) !void {
    var rebuild_process = std.process.Child.init(&.{ "zig", "build" }, allocator);
    const term = try rebuild_process.spawnAndWait();
    switch (term) {
        .Exited => |v| {
            if (v == 0) {
                const argv = [3:null]?[*:0]const u8{ "zig", "build", "run" };
                std.posix.execvpeZ("zig", &argv, std.c.environ) catch unreachable;
            }
        },
        else => {},
    }
}

fn handleGuiEvent(event: c.SDL_Event, state: *GuiState) bool {
    switch (state.action) {
        .none => {
            switch (event.type) {
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    const x: u16 = @intFromFloat(event.button.x);
                    const y: u16 = @intFromFloat(event.button.y);
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        if (state.vertical_resize_bar.contains(x, y)) {
                            state.action = .resize_left_panel;
                            assertSdl(c.SDL_SetCursor(state.assets.ew_cursor));
                        }
                    }
                    return true;
                },
                c.SDL_EVENT_WINDOW_RESIZED => {
                    state.updateWindowSize(
                        @floatFromInt(event.window.data1),
                        @floatFromInt(event.window.data2),
                    );
                    return true;
                },
                c.SDL_EVENT_MOUSE_MOTION => {
                    const x: u16 = @intFromFloat(event.motion.x);
                    const y: u16 = @intFromFloat(event.motion.y);
                    if (state.vertical_resize_bar.contains(x, y)) {
                        assertSdl(c.SDL_SetCursor(state.assets.ew_cursor));
                    } else {
                        assertSdl(c.SDL_SetCursor(state.assets.default_cursor));
                    }
                    return true;
                },

                else => return false,
            }
        },
        .resize_left_panel => switch (event.type) {
            c.SDL_EVENT_MOUSE_MOTION => {
                state.left_panel_width = std.math.clamp(
                    event.motion.x,
                    state.left_panel_width_min,
                    state.left_panel_width_max,
                );
                return true;
            },
            c.SDL_EVENT_MOUSE_BUTTON_UP => {
                state.action = .none;
                assertSdl(c.SDL_SetCursor(state.assets.default_cursor));
                return true;
            },

            else => return false,
        },
    }
}

fn handleEvent(
    event: c.SDL_Event,
    state: *State,
    allocator: std.mem.Allocator,
) enum { none, redraw, quit } {
    if (handleGuiEvent(event, &state.gui_state)) return .redraw;
    switch (event.type) {
        c.SDL_EVENT_QUIT => return .quit,
        c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_SHOWN => {
            return .redraw;
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            return .redraw;
        },
        c.SDL_EVENT_MOUSE_BUTTON_UP => return .redraw,
        c.SDL_EVENT_KEY_DOWN => {
            if (event.key.key == c.SDLK_R) {
                refresh(allocator) catch {
                    std.log.info("Failed to reload application", .{});
                };
            }
            if (event.key.key == c.SDLK_Q) {
                return .quit;
            }
            return .none;
        },
        c.SDL_EVENT_MOUSE_WHEEL => return .redraw,
        c.SDL_EVENT_MOUSE_MOTION => {
            return .redraw;
        },
        else => return .none,
    }
}

fn doLayout(
    layout: *Layout,
    content: *SDLContents,
    gui_state: *GuiState,
    width: u16,
    height: u16,
    texture: *c.SDL_Texture,
) ![]const Layout.Instruction {
    layout.begin(@intCast(width), @intCast(height));
    content.clear();

    const green = try content.rectangle(.{
        .frame_width = 4,
        .background = .green,
    });
    const white = try content.rectangle(.{
        .background = .white,
        .frame_width = 4,
    });
    const vertical_bar = try content.clone(white);
    const transparent = try content.rectangle(.{
        .frame_width = 4,
    });
    const grey = try content.rectangle(.{
        .frame_color = .black,
        .frame_width = 4,
        .background = .grey,
    });
    const blue = try content.rectangle(.{
        .frame_width = 4,
        .background = .blue,
    });

    const invisible = try content.rectangle(.{});

    const image = try content.texture(texture, .{ .frame_width = 1, .mode = .strict });

    {
        try layout.beginVertical(white, .{ .gap = 5 });

        {
            try layout.beginHorizontal(transparent, .{});

            {
                try layout.beginVertical(grey, .{
                    .width = .fixed(@intFromFloat(gui_state.left_panel_width)),
                    .spill = true,
                });

                try layout.beginVertical(white, .{ .padding = .uniform(10), .height = .fixed(100) });
                try layout.box(try content.text("Start", .{ .font = .h1 }), .{});
                try layout.endVertical();

                try layout.box(white, .{ .height = .fixed(100) });
                try layout.box(white, .{ .height = .fixed(100) });
                try layout.box(white, .{ .height = .fixed(100) });
                try layout.box(white, .{ .height = .fixed(100) });

                try layout.endVertical();
            }
            try layout.box(vertical_bar, .{ .width = .fixed(10) });

            try layout.beginVertical(white, .{ .padding = .uniform(10), .gap = 10, .spill = true });
            try layout.box(try content.text(lore_ipsum, .{}), .{});
            try layout.box(try content.text(lore_ipsum, .{}), .{ .spill = true });
            try layout.box(image, .{ .width = .fit, .height = .fit });
            try layout.endVertical();

            try layout.beginVertical(green, .{ .width = .max(600), .padding = .uniform(10), .spill = true });
            try layout.box(try content.text(lore_ipsum, .{}), .{ .spill = true });
            try layout.box(image, .{});
            try layout.endVertical();

            try layout.endHorizontal();
        }

        {
            try layout.beginHorizontal(blue, .{
                .height = .fit,
                .padding = .uniform(5),
                .gap = 2,
                .spill = true,
            });

            for (0..20) |i| {
                var buf: [4]u8 = undefined;
                const label = try std.fmt.bufPrint(&buf, "{:0>4}", .{i});

                try layout.beginHorizontal(grey, .{
                    .height = .fit,
                    .padding = .uniform(10),
                });
                try layout.box(try content.text(label, .{ .wrap = false, .font = .h1 }), .{});
                try layout.endHorizontal();
                try layout.box(invisible, .{});
            }

            try layout.endHorizontal();
        }

        try layout.endVertical();
    }

    const res = try layout.end(content, SDLContents.wrap);
    for (res) |r| {
        if (r.content == vertical_bar.index) {
            gui_state.vertical_resize_bar = .{
                .x = r.x,
                .y = r.y,
                .w = r.w,
                .h = r.h,
            };
        }
    }
    return res;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    assertSdl(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO));
    assertSdl(c.TTF_Init());

    const window = c.SDL_CreateWindow(
        "Layout Example",
        1500,
        1000,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_MAXIMIZED,
    ) orelse unreachable;
    defer c.SDL_DestroyWindow(window);

    assertSdl(c.SDL_SetWindowMinimumSize(window, 200, 200));

    const renderer = assertSdl(c.SDL_CreateRenderer(window, null));
    defer c.SDL_DestroyRenderer(renderer);

    const text_engine = assertSdl(c.TTF_CreateRendererTextEngine(renderer));
    defer c.TTF_DestroyRendererTextEngine(text_engine);

    const body_font = assertSdl(c.TTF_OpenFontIO(
        assertSdl(c.SDL_IOFromConstMem(cantarell_regular.ptr, cantarell_regular.len)),
        true,
        18,
    ));
    defer c.TTF_CloseFont(body_font);
    const h1_font = assertSdl(c.TTF_OpenFontIO(
        assertSdl(c.SDL_IOFromConstMem(cantarell_bold.ptr, cantarell_bold.len)),
        true,
        24,
    ));
    defer c.TTF_CloseFont(h1_font);

    var content = try SDLContents.init(allocator, renderer);
    defer content.deinit();

    try content.setFont(.body, body_font);
    try content.setFont(.h1, h1_font);

    var layout = Layout.init(allocator);
    defer layout.deinit();

    var state = State.init(1500, 1000);

    const texture = try layout_sdl.createBMPTexture(renderer, @embedFile("./assets/example-image.bmp"));
    defer c.SDL_DestroyTexture(texture);

    var event: c.SDL_Event = undefined;
    while (c.SDL_WaitEvent(&event)) {
        const action = handleEvent(event, &state, allocator);

        if (action == .quit) break;
        if (action == .redraw) {
            var width: c_int = undefined;
            var height: c_int = undefined;
            assertSdl(c.SDL_GetWindowSize(window, &width, &height));

            var mouse_x: f32 = undefined;
            var mouse_y: f32 = undefined;
            _ = c.SDL_GetMouseState(&mouse_x, &mouse_y);

            const instructions = try doLayout(
                &layout,
                &content,
                &state.gui_state,
                @intCast(width),
                @intCast(height),
                texture,
            );

            try content.drawInstructions(instructions);

            assertSdl(c.SDL_RenderPresent(renderer));
        }
    }
}
