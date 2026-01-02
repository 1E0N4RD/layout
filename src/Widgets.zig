const std = @import("std");
const Allocator = std.mem.Allocator;
const Layout = @import("layout").Layout;
const SDLContents = @import("SDLContents.zig");
const IdList = @import("idlist").IdList;

allocator: Allocator,
layout: *Layout,
widgets: std.ArrayList(Widget),
contents: *SDLContents,
buttons: IdList(Button, "buttons"),

const Content = Layout.Content;

pub fn init(allocator: Allocator, layout: *Layout, contents: *SDLContents) Widgets {
    return .{
        .allocator = allocator,
        .layout = layout,
        .contents = contents,
        .widgets = .empty,
        .buttons = .empty(allocator),
    };
}

pub fn deinit(self: *Widgets) void {
    self.buttons.deinit();
    self.widgets.deinit(self.allocator);
}

const Button = struct {
    content: Content,
    rect: Layout.Rect = .zero,
    hovered: bool = false,
    pressed: bool = false,
};

const Pane = struct {
    offset: u16,
};

const Widget = union(enum) {
    button: Button,
    horizontal_pane: Pane,
    vertical_pane: Pane,
};

const Widgets = @This();

pub const ButtonStyle = struct {
    padding: u16 = 0,
};

pub fn button(self: *Widgets, content: Content, style: ButtonStyle) !void {
    _ = try self.buttons.add(.{
        .content = try self.contents.clone(content),
    });
    _ = style;
}

pub const PaneStyle = struct {
    background: Content,
    split: f32 = 0.5,
};

pub fn beginHorizontalPane(
    self: *Widgets,
) !void {
    _ = self;
}

pub fn pane() void {}

pub fn endHorzontalPane(self: *Widgets) !void {
    _ = self;
}
