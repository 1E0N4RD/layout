const std = @import("std");

const Layout = @This();

allocator: std.mem.Allocator,
elements: std.ArrayList(Element),
stack: std.ArrayList(u32),
instructions: std.ArrayList(Instruction),
text_measure: TextMeasure,
string_arena: std.heap.ArenaAllocator,

width: u16,
height: u16,

pub fn init(allocator: std.mem.Allocator, text_measure: TextMeasure) Layout {
    return .{
        .allocator = allocator,
        .elements = .empty,
        .stack = .empty,
        .instructions = .empty,
        .text_measure = text_measure,
        .string_arena = .init(allocator),

        .width = 0,
        .height = 0,
    };
}

pub fn deinit(l: *Layout) void {
    l.string_arena.deinit();
    l.instructions.deinit(l.allocator);
    l.elements.deinit(l.allocator);
    l.stack.deinit(l.allocator);
}

pub const Rect = struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,

    pub const zero = Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };

    pub fn contains(self: Rect, x: u16, y: u16) bool {
        return self.x <= x and self.y <= y and x <= self.x + self.w and y <= self.y + self.h;
    }
};

pub const Result = struct {
    rect: Rect,
    instruction: usize,
    rendered: bool,

    pub const init = Result{ .rect = .zero, .instruction = 0, .rendered = false };
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const grey = Color{ .r = 100, .g = 100, .b = 100, .a = 255 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
};

// const Text = struct {
//     buffer: []const u8,
//     lines: std.ArrayList([2]usize),
//     fn init(str: []const u8, allocator: std.mem.Allocator) !Text {
//         var res: Text = .{ .buffer = str, .lines = .empty };
//         const view = try std.unicode.Utf8View.init(str);
//         var iterator = view.iterator();
//
//         var lo: ?usize = null;
//         var i: usize = 0;
//         while (iterator.nextCodepoint()) |c| {
//             switch (c) {
//                 '\n' => {
//                     if (lo) |l| {
//                         try res.lines.append(allocator, .{ l, i });
//                         lo = null;
//                     }
//                 },
//
//                 else => if (lo == null) {
//                     lo = i;
//                 },
//             }
//
//             i = iterator.i;
//         }
//
//         if (lo) |l| {
//             try res.lines.append(allocator, .{ l, i });
//         }
//
//         return res;
//     }
//     fn deinit(self: *Text, allocator: std.mem.Allocator) void {
//         self.lines.deinit(allocator);
//     }
//
//     fn getLine(self: Text, i: usize) []const u8 {
//         const lo, const hi = self.lines.items[i];
//         return self.buffer[lo..hi];
//     }
// };
//
// test "Text" {
//     const testing = std.testing;
//     const string = "€§\nHallo wie gehts?\nh";
//     var txt = try Text.init(string, testing.allocator);
//     defer txt.deinit(testing.allocator);
//
//     try testing.expectEqualStrings(txt.getLine(0), "€§");
//     try testing.expectEqualStrings(txt.getLine(1), "");
//     try testing.expectEqualStrings(txt.getLine(2), "Hallo wie gehts?");
// }

pub const RectInstruction = struct {
    fg: Color,
    bg: Color,
    frame_width: u16,
    x: u16,
    y: u16,
    w: u16,
    h: u16,
};

pub const TextInstruction = struct {
    fg: Color,
    x: u16,
    y: u16,
    w: u16,
    font_id: u16,
    string: []const u8,
};

pub const Instruction = union(enum) {
    rect: RectInstruction,
    text: TextInstruction,
};

pub const TextMeasure = struct {
    context: *anyopaque,
    measure_codepoint: *const fn (context: *anyopaque, font_id: u16, char: u21) u16,
    measure_wrapped_height: *const fn (context: *anyopaque, font_id: u16, string: []const u8, width: u16) u16,

    fn measure(self: TextMeasure, font_id: u16, char: u8) u16 {
        return self.measure_codepoint(self.context, font_id, char);
    }

    fn getTextWidthRange(self: TextMeasure, font_id: u16, string: []const u8) Range {
        var word_len: u16 = 0;
        var max_word_len = word_len;
        var line_len: u16 = 0;
        var max_line_len: u16 = line_len;
        for (string) |c| {
            if (std.ascii.isWhitespace(c)) {
                if (word_len > max_word_len) {
                    max_word_len = word_len;
                }
                word_len = 0;

                if (c == '\n' or c == '\r') {
                    if (line_len > max_line_len) {
                        max_line_len = line_len;
                    }
                    line_len = 0;
                } else {
                    const char_len = self.measure(font_id, c);
                    line_len += char_len;
                }
            } else {
                const char_len = self.measure(font_id, c);
                word_len += char_len;
                line_len += char_len;
            }
        }
        if (word_len > max_word_len) {
            max_word_len = word_len;
        }
        if (line_len > max_line_len) {
            max_line_len = line_len;
        }
        return .{ .lo = max_word_len, .hi = max_line_len };
    }

    fn getWrappedHeight(self: TextMeasure, font_id: u16, string: []const u8, width: u16) u16 {
        return self.measure_wrapped_height(self.context, font_id, string, width);
    }
};

pub fn printElementLayout() void {
    const info = @typeInfo(Element);
    const structure = info.@"struct";
    const Field = struct { []const u8, usize };
    var fields: [structure.fields.len]Field = undefined;
    std.debug.print("Element: {}\n", .{@sizeOf(Element)});
    inline for (structure.fields, &fields) |field, *f| {
        f.* = .{ field.name, @offsetOf(Element, field.name) };
    }
    const Context = struct {
        fn lessThan(_: void, a: Field, b: Field) bool {
            return a[1] < b[1];
        }
    };
    std.sort.heap(Field, &fields, {}, Context.lessThan);
    for (&fields) |field| {
        std.debug.print("{s}: {}\n", field);
    }
}

const Element = struct {
    next: u32 = 1,
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,
    w_range: Range = .any,
    h_range: Range = .any,
    render: bool = true,
    result: ?*Result,

    spec: struct {
        w: Spec,
        h: Spec,
        fg: Color,
        bg: Color,
        padding: Padding,
        frame_width: u16 = 0,
        spill: bool,
    },

    as: union(enum) {
        hbox: struct {
            rendered_children: u16,
            render_empty: bool,
            gap: u16,
        },
        vbox: struct {
            rendered_children: u16,
            render_empty: bool,
            gap: u16,
        },
        box,
        text: struct {
            string: []const u8, // TODO: Move this somewhere else.
            font_id: u16,
            gap: u16,
        },
    },

    fn canWidthGrow(self: Element) bool {
        return self.w < self.w_range.hi;
    }
    fn canWidthShrink(self: Element) bool {
        return self.w_range.lo < self.w;
    }
    fn canHeightGrow(self: Element) bool {
        return self.h < self.h_range.hi;
    }
    fn canHeightShrink(self: Element) bool {
        return self.h_range.lo < self.h;
    }
};

const ChildIterator = struct {
    elements: []Element,
    current: usize,
    fn next(self: *ChildIterator) ?*Element {
        if (self.current < self.elements.len) {
            defer self.current += self.elements[self.current].next;
            return &self.elements[self.current];
        } else {
            return null;
        }
    }
    fn nextPair(self: *ChildIterator) ?struct { *Element, u32 } {
        if (self.current < self.elements.len) {
            defer self.current += self.elements[self.current].next;
            return .{ &self.elements[self.current], @intCast(self.current) };
        } else {
            return null;
        }
    }
    fn nextId(self: *ChildIterator) ?u32 {
        if (self.current < self.elements.len) {
            defer self.current += self.elements[self.current].next;
            return @intCast(self.current);
        } else {
            return null;
        }
    }
};

fn childIterator(self: *Layout, id: usize) ChildIterator {
    return .{
        .elements = self.elements.items[0 .. id + self.elements.items[id].next],
        .current = id + 1,
    };
}

fn childIteratorTo(self: *Layout, id: usize, last_child_id: usize) ChildIterator {
    return .{
        .elements = self.elements.items[0 .. last_child_id + 1],
        .current = id + 1,
    };
}

pub fn begin(l: *Layout, width: u16, height: u16) void {
    l.elements.clearRetainingCapacity();
    l.stack.clearRetainingCapacity();
    _ = l.string_arena.reset(.{ .retain_with_limit = 4096 });
    l.width = width;
    l.height = height;
}

fn endElement(l: *Layout, e: *Element) !void {
    e.w_range.add(e.spec.padding.width());
    e.w_range = e.spec.w.intersect(e.w_range);

    const lo = l.stack.pop().?;
    const hi: u32 = @intCast(l.elements.items.len);

    try l.accumulateParentWidth(e.w_range);
    l.incrementParent(hi - lo);
}

fn resolvePositions(l: *Layout, id: usize, x: u16, y: u16) void {
    const e = &l.elements.items[id];

    e.x = x;
    e.y = y;

    switch (e.as) {
        .hbox => |b| {
            var child_x = x + e.spec.padding.left;
            const child_y = y + e.spec.padding.top;

            var iterator = l.childIterator(id);
            while (iterator.nextPair()) |pair| {
                const child, const child_id = pair;

                l.resolvePositions(child_id, child_x, child_y);
                child_x += child.w;
                child_x += b.gap;
            }
        },
        .vbox => |b| {
            const child_x = x + e.spec.padding.left;
            var child_y = y + e.spec.padding.top;

            var iterator = l.childIterator(id);
            while (iterator.nextPair()) |pair| {
                const child, const child_id = pair;

                l.resolvePositions(child_id, child_x, child_y);
                child_y += child.h;
                child_y += b.gap;
            }
        },
        .box => {},
        .text => {},
    }
}

fn resizeWidthsHBox(
    self: *Layout,
    element: *Element,
    hbox: @TypeOf(&element.as.hbox),
    id: usize,
    width: u16,
) void {
    hbox.rendered_children = 0;

    var iterator = self.childIterator(id);

    var required = element.spec.padding.width();
    var last_child_id = id;

    // First is handled separatly because it does not get a gap.
    if (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        child.w = child.w_range.lo;
        if (required + child.w_range.lo <= width) {
            child.w = child.w;
            required += child.w;
            last_child_id = child_id;
            hbox.rendered_children += 1;
        } else {
            child.render = false;
        }
    }
    while (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        child.w = child.w_range.lo;
        if (required + hbox.gap + child.w <= width) {
            required += hbox.gap + child.w;
            last_child_id = child_id;
            hbox.rendered_children += 1;
        } else {
            child.render = false;
        }
    }

    if (width > required) {
        var remaining = width - required;

        while (remaining > 0) {
            var smallest: u16 = 0xffff;
            var second_smallest: u16 = 0xffff;
            var smallest_count: usize = 0;

            iterator = self.childIteratorTo(id, last_child_id);
            while (iterator.next()) |child| {
                if (!child.canWidthGrow()) continue;

                if (child.w < smallest) {
                    smallest_count = 1;
                    second_smallest = smallest;
                    smallest = child.w;
                } else if (child.w == smallest) {
                    smallest_count += 1;
                } else if (child.w < second_smallest) {
                    second_smallest = child.w;
                }
            }

            if (smallest_count == 0) break;
            const extra_width = @min(
                second_smallest - smallest,
                (remaining + smallest_count - 1) / smallest_count,
            );

            iterator = self.childIteratorTo(id, last_child_id);
            while (iterator.next()) |child| {
                if (!child.canWidthGrow()) continue;

                if (child.w == smallest) {
                    const additional = @min(
                        remaining,
                        extra_width,
                        child.w_range.hi - child.w,
                    );
                    child.w += additional;
                    remaining -= additional;
                }
            }
        }
    } else {
        var remaining = required - width;

        while (remaining > 0) {
            var largest: u16 = 0;
            var second_largest: u16 = 0;
            var largest_count: usize = 0;

            iterator = self.childIteratorTo(id, last_child_id);
            while (iterator.next()) |child| {
                if (!child.canWidthShrink()) continue;

                if (child.w > largest) {
                    largest_count = 1;
                    second_largest = largest;
                    largest = child.w;
                } else if (child.w == largest) {
                    largest_count += 1;
                } else if (child.w > second_largest) {
                    second_largest = child.w;
                }
            }

            if (largest_count == 0) break;
            const extra_width = @min(
                largest - second_largest,
                (remaining + largest_count - 1) / largest_count,
            );

            iterator = self.childIteratorTo(id, last_child_id);
            while (iterator.next()) |child| {
                if (!child.canWidthShrink()) continue;

                if (child.w == largest) {
                    const additional = @min(
                        @min(remaining, extra_width),
                        child.w - child.w_range.lo,
                    );
                    child.w -= additional;
                    remaining -= additional;
                }
            }
        }
    }

    iterator = self.childIteratorTo(id, last_child_id);
    while (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        self.resizeWidths(child_id, child.w);
    }
    element.w = width;
}

fn resizeWidths(l: *Layout, id: usize, width: u16) void {
    const element = &l.elements.items[id];
    switch (element.as) {
        .hbox => |*hbox| l.resizeWidthsHBox(element, hbox, id, width),
        .vbox => {
            var iterator = l.childIterator(id);
            const child_width = width - element.spec.padding.width();
            while (iterator.nextId()) |child_id| {
                l.resizeWidths(child_id, child_width);
            }
        },
        .box => {},
        .text => {},
    }
    element.w = width;
}

fn resizeHeightsVBox(
    l: *Layout,
    e: *Element,
    vbox: @TypeOf(&e.as.vbox),
    id: usize,
    height: u16,
) void {
    vbox.rendered_children = 0;

    var iterator = l.childIterator(id);

    var required = e.spec.padding.height();
    var last_child_id = id;

    if (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        child.h = child.h_range.lo;
        if (required + child.h_range.lo <= height) {
            required += child.h;
            last_child_id = child_id;
            vbox.rendered_children += 1;
        } else {
            child.render = false;
        }
    }
    while (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        child.h = child.h_range.lo;
        if (required + vbox.gap + child.h_range.lo <= height) {
            required += vbox.gap + child.h;
            last_child_id = child_id;
            vbox.rendered_children += 1;
        } else {
            child.render = false;
        }
    }

    if (height > required) {
        var remaining = height - required;

        while (remaining > 0) {
            var smallest: u16 = 0xffff;
            var second_smallest: u16 = 0xffff;
            var smallest_count: usize = 0;

            iterator = l.childIteratorTo(id, last_child_id);
            while (iterator.next()) |child| {
                if (!child.canHeightGrow()) continue;

                if (child.h < smallest) {
                    smallest_count = 1;
                    second_smallest = smallest;
                    smallest = child.h;
                } else if (child.h == smallest) {
                    smallest_count += 1;
                } else if (child.h < second_smallest) {
                    second_smallest = child.h;
                }
            }

            if (smallest_count == 0) break;
            const extra = @min(
                second_smallest - smallest,
                (remaining + smallest_count - 1) / smallest_count,
            );

            iterator = l.childIteratorTo(id, last_child_id);
            while (iterator.next()) |child| {
                if (!child.canHeightGrow()) continue;

                if (child.h == smallest) {
                    const additional = @min(
                        remaining,
                        extra,
                        child.h_range.hi - child.h,
                    );
                    child.h += additional;
                    remaining -= additional;
                }
            }
        }
    } else {
        var remaining = required - height;

        while (remaining > 0) {
            var largest: u16 = 0;
            var second_largest: u16 = 0;
            var largest_count: usize = 0;

            iterator = l.childIteratorTo(id, last_child_id);
            while (iterator.next()) |child| {
                if (!child.canHeightShrink()) continue;

                if (child.h > largest) {
                    largest_count = 1;
                    second_largest = largest;
                    largest = child.h;
                } else if (child.h == largest) {
                    largest_count += 1;
                } else if (child.h > second_largest) {
                    second_largest = child.h;
                }
            }

            if (largest_count == 0) break;
            const extra_height = @min(
                largest - second_largest,
                (remaining + largest_count - 1) / largest_count,
            );

            iterator = l.childIteratorTo(id, last_child_id);
            while (iterator.next()) |child| {
                if (!child.canHeightShrink()) continue;

                if (child.h == largest) {
                    const additional = @min(
                        @max(remaining, extra_height),
                        child.h - child.h_range.lo,
                    );
                    child.h -= additional;
                    remaining -= additional;
                }
            }
        }
    }

    iterator = l.childIteratorTo(id, last_child_id);
    while (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        l.resizeHeights(child_id, child.h);
    }
    e.h = height;
}

fn resizeHeights(self: *Layout, id: u32, height: u16) void {
    const e = &self.elements.items[id];
    switch (e.as) {
        .hbox => {
            var iterator = self.childIterator(id);
            while (iterator.nextId()) |child_id| {
                self.resizeHeights(child_id, height - e.spec.padding.height());
            }
            e.h = height;
        },
        .vbox => |*vbox| self.resizeHeightsVBox(e, vbox, id, height),
        .box => e.h = height,
        .text => e.h = height,
    }
}

fn wrap(l: *Layout, id: u32) !void {
    const e = &l.elements.items[id];
    switch (e.as) {
        .vbox => |*vbox| {
            var iterator = l.childIterator(id);
            var first = true;
            while (iterator.nextPair()) |pair| : (first = false) {
                const child, const child_id = pair;
                if (!child.render) continue;

                try l.wrap(child_id);
                e.h_range.accumulateSerial(
                    e.spec.spill,
                    if (first) 0 else vbox.gap,
                    child.h_range,
                );
            }
        },
        .hbox => {
            var iterator = l.childIterator(id);
            var first = true;
            while (iterator.nextPair()) |pair| : (first = false) {
                const child, const child_id = pair;
                if (!child.render) continue;

                try l.wrap(child_id);

                try e.h_range.accumulateParallel(child.h_range);
            }
        },
        .box => {},
        .text => |t| {
            const height = l.text_measure.getWrappedHeight(
                t.font_id,
                t.string,
                e.w - e.spec.padding.width(),
            );
            e.h_range = if (e.spec.spill)
                .initMax(height)
            else
                .initExact(height);
        },
    }
    e.h_range.add(e.spec.padding.height());
    e.h_range = e.spec.h.intersect(e.h_range);
}

fn createInstructions(l: *Layout) ![]const Instruction {
    l.instructions.clearRetainingCapacity();
    var i: usize = 0;
    while (i < l.elements.items.len) {
        const e = l.elements.items[i];
        if (e.render) {
            i += 1;
            const instruction = switch (e.as) {
                .vbox, .hbox, .box => Instruction{
                    .rect = .{
                        .x = e.x,
                        .y = e.y,
                        .fg = e.spec.fg,
                        .bg = e.spec.bg,
                        .w = e.w,
                        .h = e.h,
                        .frame_width = e.spec.frame_width,
                    },
                },
                .text => |t| Instruction{
                    .text = .{
                        .fg = e.spec.fg,
                        .x = e.x + e.spec.padding.top,
                        .y = e.y + e.spec.padding.left,
                        .w = e.w - e.spec.padding.width(),
                        .string = t.string,
                        .font_id = t.font_id,
                    },
                },
            };

            if (e.result) |result| {
                result.* = .{
                    .rendered = true,
                    .instruction = l.instructions.items.len,
                    .rect = .{ .x = e.x, .y = e.y, .w = e.w, .h = e.h },
                };
            }

            try l.instructions.append(l.allocator, instruction);
        } else {
            i += e.next;
        }
    }
    return l.instructions.items;
}

pub fn end(self: *Layout) ![]const Instruction {
    self.resizeWidths(0, self.width);
    try self.wrap(0);
    self.resizeHeights(0, self.height);
    self.resolvePositions(0, 0, 0);
    return self.createInstructions();
}

pub const Spec = struct {
    r: Range,
    grow: bool,

    pub fn fixed(value: u16) Spec {
        return .{ .r = .{ .lo = value, .hi = value }, .grow = false };
    }

    pub fn min(value: u16) Spec {
        return .{ .r = .{ .lo = value, .hi = 0xffff }, .grow = false };
    }

    pub fn minGrow(value: u16) Spec {
        return .{ .r = .{ .lo = value, .hi = 0xffff }, .grow = true };
    }

    pub fn max(value: u16) Spec {
        return .{ .r = .{ .lo = 0, .hi = value }, .grow = false };
    }

    pub fn maxGrow(value: u16) Spec {
        return .{ .r = .{ .lo = 0, .hi = value }, .grow = true };
    }

    pub fn range(lo: u16, hi: u16) Spec {
        return .{ .r = .{ .lo = lo, .hi = hi }, .grow = true };
    }

    pub fn rangeGrow(lo: u16, hi: u16) Spec {
        return .{ .r = .{ .lo = lo, .hi = hi }, .grow = true };
    }

    pub const any = Spec{ .r = .{ .lo = 0, .hi = 0xffff }, .grow = true };
    pub const fit = Spec{ .r = .{ .lo = 0, .hi = 0xffff }, .grow = false };

    fn intersect(a: Spec, b: Range) Range {
        if (a.grow) {
            var res = Range{ .lo = @max(a.r.lo, b.lo), .hi = a.r.hi };
            if (res.hi < res.lo) {
                std.log.warn("Element got squashed", .{});
                res.lo = res.hi;
            }
            return res;
        } else {
            return a.r.intersect(b) orelse .{ .lo = a.r.hi, .hi = a.r.hi };
        }
    }
};

const Range = struct {
    lo: u16,
    hi: u16,

    const any = Range{ .lo = 0, .hi = 0xffff };
    const zero = Range{ .lo = 0, .hi = 0 };
    const initParallel = any;
    const initSerial = zero;

    fn initExact(value: u16) Range {
        return .{ .lo = value, .hi = value };
    }
    fn initMax(value: u16) Range {
        return .{ .lo = 0, .hi = value };
    }
    fn initMin(value: u16) Range {
        return .{ .lo = value, .hi = 0xffff };
    }

    fn clamp(self: Range, value: u16) u16 {
        return std.math.clamp(value, self.lo, self.hi);
    }

    fn add(self: *Range, value: u16) void {
        self.lo +|= value;
        self.hi +|= value;
    }

    fn intersect(a: Range, b: Range) ?Range {
        const lo = @max(a.lo, b.lo);
        const hi = @min(a.hi, b.hi);
        return if (lo <= hi) .{ .lo = lo, .hi = hi } else null;
    }

    fn accumulateParallel(a: *Range, b: Range) !void {
        a.* = a.intersect(b) orelse return error.RangesDisjoint;
    }

    fn accumulateSerial(a: *Range, spill: bool, gap: u16, b: Range) void {
        if (!spill) a.lo += b.lo + gap;
        a.hi +|= b.hi +| gap;
    }
};

pub const Padding = struct {
    top: u16,
    left: u16,
    bottom: u16,
    right: u16,
    pub fn uniform(value: u16) Padding {
        return .{ .top = value, .left = value, .bottom = value, .right = value };
    }
    pub fn horizontal(value: u16) Padding {
        return .{ .top = 0, .left = value, .bottom = 0, .right = value };
    }
    pub fn vertical(value: u16) Padding {
        return .{ .top = value, .left = 0, .bottom = value, .right = 0 };
    }
    pub fn symmetrical(h: u16, v: u16) Padding {
        return .{ .top = v, .left = h, .bottom = v, .right = h };
    }
    pub const none = Padding{ .top = 0, .left = 0, .bottom = 0, .right = 0 };
    fn width(self: Padding) u16 {
        return self.left + self.right;
    }
    fn height(self: Padding) u16 {
        return self.top + self.bottom;
    }
};

const BoxOptions = struct {
    width: Spec = .any,
    height: Spec = .any,
    padding: Padding = .none,
    gap: u16 = 0,
    spill: bool = false,
    fg: Color = .black,
    bg: Color = .white,
    result: ?*Result = null,
};

fn getParent(l: *Layout) ?*Element {
    const parent_id = l.stack.getLastOrNull() orelse return null;
    return &l.elements.items[parent_id];
}

fn accumulateParentWidth(l: *Layout, width: Range) !void {
    const parent = l.getParent() orelse return;
    const first_child = parent.next == 1;

    switch (parent.as) {
        .vbox => {
            try parent.w_range.accumulateParallel(width);
        },
        .hbox => |*b| {
            const gap = if (first_child) 0 else b.gap;
            parent.w_range.accumulateSerial(parent.spec.spill, gap, width);
        },
        else => unreachable,
    }
}

fn accumulateParentHeight(l: *Layout, height: Range) !void {
    const parent = l.getParent() orelse return;
    const first_child = parent.next == 1;

    switch (parent.as) {
        .vbox => |*b| {
            const gap = if (first_child) 0 else b.gap;
            b.height_accumulator.accumulate(b.spill, gap, height);
        },
        .hbox => |*b| {
            try b.height_accumulator.accumulate(height);
        },
        else => unreachable,
    }
}

fn incrementParent(self: *Layout, n: u32) void {
    if (self.getParent()) |parent| parent.next += n;
}

pub fn box(self: *Layout, options: BoxOptions) !void {
    if (options.result) |result| result.* = .init;

    const element = Element{
        .w = options.width.r.lo,
        .w_range = options.width.r,
        .result = options.result,
        .spec = .{
            .frame_width = 1,
            .fg = options.fg,
            .bg = options.bg,
            .w = options.width,
            .h = options.height,
            .padding = options.padding,
            .spill = options.spill,
        },
        .as = .box,
    };
    try self.elements.append(self.allocator, element);

    try self.accumulateParentWidth(element.spec.w.r);
    self.incrementParent(1);
}
pub fn beginHBox(self: *Layout, options: BoxOptions) !void {
    if (options.result) |result| result.* = .init;
    const id = self.elements.items.len;
    try self.elements.append(
        self.allocator,
        .{
            .w_range = .initSerial,
            .h_range = .initParallel,
            .result = options.result,
            .spec = .{
                .frame_width = 1,
                .fg = options.fg,
                .bg = options.bg,
                .w = options.width,
                .h = options.height,
                .padding = options.padding,
                .spill = options.spill,
            },
            .as = .{ .hbox = .{
                .rendered_children = 0,
                .render_empty = false,
                .gap = options.gap,
            } },
        },
    );
    try self.stack.append(self.allocator, @intCast(id));
}

pub fn endHBox(l: *Layout) !void {
    const e = &l.elements.items[l.stack.getLast()];
    std.debug.assert(e.as == .hbox);
    try l.endElement(e);
}

pub fn beginVBox(self: *Layout, options: BoxOptions) !void {
    if (options.result) |result| result.* = .init;
    const id = self.elements.items.len;
    try self.elements.append(
        self.allocator,
        .{
            .w_range = .initParallel,
            .h_range = .initSerial,
            .result = options.result,
            .spec = .{
                .frame_width = 1,
                .fg = options.fg,
                .bg = options.bg,
                .w = options.width,
                .h = options.height,
                .padding = options.padding,
                .spill = options.spill,
            },
            .as = .{ .vbox = .{
                .rendered_children = 0,
                .render_empty = false,
                .gap = options.gap,
            } },
        },
    );
    try self.stack.append(self.allocator, @intCast(id));
}

fn getSmallestChildWidth(self: *Layout, id: usize) u16 {
    var res: u16 = 0;
    var iterator = self.childIterator(id);
    if (iterator.next()) |child| {
        res = child.width_spec.lo;
    }
    while (iterator.next()) |child| {
        res = @min(res, child.width_spec.lo);
    }
    return res;
}

fn getSmallestChildHeight(self: *Layout, id: usize) u16 {
    var res = 0;
    var iterator = self.childIterator(id);
    if (iterator.next()) |child| {
        res = child.height_spec.lo;
    }
    while (iterator.next()) |child| {
        res = @min(res, child.height_spec.lo);
    }
    return res;
}

pub fn endVBox(self: *Layout) !void {
    const e = &self.elements.items[self.stack.getLast()];
    std.debug.assert(e.as == .vbox);
    try self.endElement(e);
}

const TextOptions = struct {
    width: Spec = .fit,
    height: Spec = .fit,
    padding: Padding = .none,
    gap: u16 = 5,
    fg: Color = .black,
    bg: Color = .transparent,
    spill: bool = false,
    result: ?*Result = null,
};

/// Draw text.
/// @param self
/// @param font Id of font
/// @param string String to be drawn. Function makes copy.
/// @param options
pub fn text(self: *Layout, font: u16, string: []const u8, options: TextOptions) !void {
    if (options.result) |result| result.* = .init;

    var text_width_range = self.text_measure.getTextWidthRange(font, string);
    text_width_range.add(options.padding.width());
    const width_range = options.width.intersect(text_width_range);

    const string_copy = try self.string_arena.allocator().dupe(u8, string);
    try self.elements.append(self.allocator, .{
        .w_range = width_range,
        .spec = .{
            .fg = options.fg,
            .bg = options.bg,
            .w = options.width,
            .h = options.height,
            .padding = options.padding,
            .spill = options.spill,
        },
        .result = options.result,
        .as = .{ .text = .{
            .string = string_copy,
            .gap = options.gap,
            .font_id = font,
        } },
    });
    try self.accumulateParentWidth(width_range);
    self.incrementParent(1);
}

pub fn textBox(
    self: *Layout,
    font: u16,
    string: []const u8,
    text_options: TextOptions,
    box_options: BoxOptions,
) !void {
    try self.beginVBox(box_options);
    try self.text(font, string, text_options);
    try self.endVBox();
}

pub fn body(self: *Layout, string: []const u8) void {
    _ = self;
    _ = string;
}

fn doPrint(self: *Layout, writer: *std.Io.Writer, id: usize, depth: usize) !void {
    const e = self.elements.items[id];
    for (0..depth) |_| try writer.print("  ", .{});
    switch (e.as) {
        .box => {
            try writer.print(
                "Box x={} y={} w={} h={}\n",
                .{ e.x, e.y, e.w, e.h },
            );
        },
        .hbox => {
            try writer.print(
                "HBox x={} y={} w={} h={} next={}\n",
                .{ e.x, e.y, e.w, e.h, e.next },
            );
            var iterator = self.childIterator(id);
            while (iterator.nextId()) |child_id| {
                try self.doPrint(writer, child_id, depth + 1);
            }
        },
        .vbox => {
            try writer.print(
                "VBox x={} y={} w={} h={} next={}\n",
                .{ e.x, e.y, e.w, e.h, e.next },
            );
            var iterator = self.childIterator(id);
            while (iterator.nextId()) |child_id| {
                try self.doPrint(writer, child_id, depth + 1);
            }
        },
        .text => |t| {
            try writer.print(
                "Text x={} y={} w={} h={} \"{s}\"\n",
                .{ e.x, e.y, e.w, e.h, t.string },
            );
        },
    }
}

pub fn print(self: *Layout, writer: *std.Io.Writer) !void {
    if (self.elements.items.len > 0) {
        try self.doPrint(writer, 0, 0);
    }
}
