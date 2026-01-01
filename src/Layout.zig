const std = @import("std");

pub const ContentId = u16;

pub const Content = struct {
    index: ContentId,
    w_range: Range = .any,
    h_range: Range = .any,
    wrap: bool = false,
};

const Layout = @This();

allocator: std.mem.Allocator,
elements: std.ArrayList(Element),
stack: std.ArrayList(u16),
instructions: std.ArrayList(Instruction),

width: u16,
height: u16,

pub fn init(allocator: std.mem.Allocator) Layout {
    return .{
        .allocator = allocator,
        .elements = .empty,
        .stack = .empty,
        .instructions = .empty,

        .width = 0,
        .height = 0,
    };
}

pub fn deinit(l: *Layout) void {
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

pub const Instruction = struct {
    content: ContentId,
    x: u16,
    y: u16,
    w: u16,
    h: u16,
};

pub fn printElementLayout() void {
    const info = @typeInfo(Element);
    const structure = info.@"struct";

    for (0..@sizeOf(Element)) |i| {
        inline for (structure.fields) |field| {
            if (@offsetOf(Element, field.name) == i) {
                std.debug.print("{:3} {s} {s}\n", .{
                    i,
                    if (i % 4 == 0) "+" else "|",
                    field.name,
                });
                break;
            }
        } else {
            std.debug.print("{:3} {s}\n", .{ i, if (i % 4 == 0) "+" else "|" });
        }
    }
}

const Element = struct {
    next: u16 = 1,
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,
    w_range: Range = .any,
    h_range: Range = .any,
    show: bool = true,
    wrap: bool = false,
    content: ContentId,

    spec: struct {
        w: Spec,
        h: Spec,
        padding: Padding,
        spill: bool,
        gap: u16,
    },
    shown_children: u16 = 0,

    direction: enum {
        terminal,
        horizontal,
        vertical,
    },

    fn canWidthGrow(self: Element) bool {
        return self.w < self.w_range.hi;
    }
    fn canHeightGrow(self: Element) bool {
        return self.h < self.h_range.hi;
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
    l.width = width;
    l.height = height;
}

fn endElement(l: *Layout, e: *Element) !void {
    e.w_range.add(e.spec.padding.width());
    e.w_range = e.spec.w.intersect(e.w_range).r;

    const id = l.stack.pop().?;
    const front: u16 = @intCast(l.elements.items.len);

    try l.accumulateWidth(e.w_range);
    l.incrementTop(front - id);
}

fn resolvePositions(l: *Layout, id: usize, x: u16, y: u16) void {
    const e = &l.elements.items[id];

    e.x = x;
    e.y = y;

    switch (e.direction) {
        .horizontal => {
            var child_x = x + e.spec.padding.left;
            const child_y = y + e.spec.padding.top;

            var iterator = l.childIterator(id);
            while (iterator.nextPair()) |pair| {
                const child, const child_id = pair;

                l.resolvePositions(child_id, child_x, child_y);
                child_x += child.w;
                child_x += e.spec.gap;
            }
        },
        .vertical => {
            const child_x = x + e.spec.padding.left;
            var child_y = y + e.spec.padding.top;

            var iterator = l.childIterator(id);
            while (iterator.nextPair()) |pair| {
                const child, const child_id = pair;

                l.resolvePositions(child_id, child_x, child_y);
                child_y += child.h;
                child_y += e.spec.gap;
            }
        },
        .terminal => {},
    }
}

fn resizeWidthsHorizontal(
    self: *Layout,
    element: *Element,
    id: usize,
    width: u16,
) void {
    element.shown_children = 0;

    var iterator = self.childIterator(id);

    var required = element.spec.padding.width();
    var last_child_id = id;

    var gap: u16 = 0;
    while (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        child.w = child.w_range.lo;
        if (required + gap + child.w <= width) {
            required += gap + child.w;
            last_child_id = child_id;
            element.shown_children += 1;
        } else {
            child.show = false;
        }
        gap = element.spec.gap;
    }

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

    iterator = self.childIteratorTo(id, last_child_id);
    while (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        self.resizeWidths(child_id, child.w);
    }
    element.w = width;
}

fn resizeWidths(l: *Layout, id: usize, width: u16) void {
    const element = &l.elements.items[id];
    switch (element.direction) {
        .horizontal => l.resizeWidthsHorizontal(element, id, width),
        .vertical => {
            var iterator = l.childIterator(id);
            const child_width = width - element.spec.padding.width();
            while (iterator.nextId()) |child_id| {
                l.resizeWidths(child_id, child_width);
            }
        },
        .terminal => {},
    }
    element.w = width;
}

fn resizeHeightsVertical(
    l: *Layout,
    e: *Element,
    id: usize,
    height: u16,
) void {
    e.shown_children = 0;

    var iterator = l.childIterator(id);

    var required = e.spec.padding.height();
    var last_child_id = id;

    var gap: u16 = 0;
    while (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        child.h = child.h_range.lo;
        if (required + gap + child.h_range.lo <= height) {
            required += gap + child.h;
            last_child_id = child_id;
            e.shown_children += 1;
        } else {
            child.show = false;
        }

        gap = e.spec.gap;
    }

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

    iterator = l.childIteratorTo(id, last_child_id);
    while (iterator.nextPair()) |pair| {
        const child, const child_id = pair;
        l.resizeHeights(child_id, child.h);
    }
    e.h = height;
}

fn resizeHeights(self: *Layout, id: u32, height: u16) void {
    const e = &self.elements.items[id];
    switch (e.direction) {
        .horizontal => {
            var iterator = self.childIterator(id);
            while (iterator.nextId()) |child_id| {
                self.resizeHeights(child_id, height - e.spec.padding.height());
            }
            e.h = height;
        },
        .vertical => self.resizeHeightsVertical(e, id, height),
        .terminal => e.h = height,
    }
}

fn WrapFn(comptime Ctx: type) type {
    return fn (ctx: Ctx, id: ContentId, w: u16) u16;
}

fn wrap(
    l: *Layout,
    ctx: anytype,
    comptime wrapFn: WrapFn(@TypeOf(ctx)),
    id: u32,
) !void {
    const e = &l.elements.items[id];

    // Wrap self
    switch (e.direction) {
        .vertical, .horizontal => if (e.wrap) {
            _ = wrapFn(ctx, e.content, e.w);
        },
        .terminal => if (e.wrap) {
            const height = wrapFn(ctx, e.content, e.w);

            e.h_range = if (e.spec.spill)
                .initMax(height)
            else
                .initExact(height);
        },
    }

    // Wrap children
    switch (e.direction) {
        .vertical => {
            var iterator = l.childIterator(id);
            var gap: u16 = 0;
            while (iterator.nextPair()) |pair| : (gap = e.spec.gap) {
                const child, const child_id = pair;
                if (!child.show) continue;

                try l.wrap(ctx, wrapFn, child_id);
                e.h_range.accumulateSerial(e.spec.spill, gap, child.h_range);
            }
        },
        .horizontal => {
            var iterator = l.childIterator(id);
            while (iterator.nextPair()) |pair| {
                const child, const child_id = pair;
                if (!child.show) continue;

                try l.wrap(ctx, wrapFn, child_id);
                try e.h_range.accumulateParallel(child.h_range);
            }
        },
        .terminal => {},
    }

    // Add padding
    switch (e.direction) {
        .vertical, .horizontal => e.h_range.add(e.spec.padding.height()),
        .terminal => {},
    }

    e.h_range = e.spec.h.intersect(e.h_range).r;
}

fn createInstructions(l: *Layout) ![]const Instruction {
    l.instructions.clearRetainingCapacity();
    var i: usize = 0;
    while (i < l.elements.items.len) {
        const e = l.elements.items[i];
        if (e.show) {
            i += 1;

            try l.instructions.append(l.allocator, .{
                .x = e.x,
                .y = e.y,
                .w = e.w,
                .h = e.h,
                .content = e.content,
            });
        } else {
            i += e.next;
        }
    }
    return l.instructions.items;
}

pub fn end(
    self: *Layout,
    wrap_context: anytype,
    comptime wrapFn: WrapFn(@TypeOf(wrap_context)),
) ![]const Instruction {
    self.resizeWidths(0, self.width);
    try self.wrap(wrap_context, wrapFn, 0);
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

    fn intersect(a: Spec, b: Range) Spec {
        if (a.grow) {
            var res = Range{ .lo = @max(a.r.lo, b.lo), .hi = a.r.hi };
            if (res.hi < res.lo) {
                std.log.warn("Element got squashed", .{});
                res.lo = res.hi;
            }
            return .{ .r = res, .grow = a.grow };
        } else {
            return .{
                .r = a.r.intersect(b) orelse .{ .lo = a.r.hi, .hi = a.r.hi },
                .grow = false,
            };
        }
    }
};

pub const Range = struct {
    lo: u16,
    hi: u16,

    const any = Range{ .lo = 0, .hi = 0xffff };
    const zero = Range{ .lo = 0, .hi = 0 };
    const initParallel = any;
    const initSerial = zero;

    pub fn initExact(value: u16) Range {
        return .{ .lo = value, .hi = value };
    }
    pub fn initMax(value: u16) Range {
        return .{ .lo = 0, .hi = value };
    }
    pub fn initMin(value: u16) Range {
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
        a.* = a.intersect(b) orelse {
            @breakpoint();
            return error.RangesDisjoint;
        };
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
};

fn getTop(l: *Layout) ?*Element {
    const parent_id = l.stack.getLastOrNull() orelse return null;
    return &l.elements.items[parent_id];
}

fn accumulateWidth(l: *Layout, width: Range) !void {
    const top = l.getTop() orelse return;
    const first_child = top.next == 1;

    switch (top.direction) {
        .vertical => {
            try top.w_range.accumulateParallel(width);
        },
        .horizontal => {
            const gap = if (first_child) 0 else top.spec.gap;
            top.w_range.accumulateSerial(top.spec.spill, gap, width);
        },
        .terminal => unreachable,
    }
}

fn incrementTop(self: *Layout, n: u16) void {
    if (self.getTop()) |top| top.next += n;
}

pub fn box(self: *Layout, content: Content, options: BoxOptions) !void {
    const element = Element{
        .w = options.width.r.lo,
        .w_range = options.width.r,
        .content = content.index,
        .spec = .{
            .gap = options.gap,
            .w = options.width.intersect(content.w_range),
            .h = options.height.intersect(content.h_range),
            .padding = options.padding,
            .spill = options.spill,
        },
        .wrap = content.wrap,
        .direction = .vertical,
    };
    try self.elements.append(self.allocator, element);

    try self.accumulateWidth(element.spec.w.r);
    self.incrementTop(1);
}

pub fn beginHBox(self: *Layout, content: Content, options: BoxOptions) !void {
    const id = self.elements.items.len;
    try self.elements.append(
        self.allocator,
        .{
            .w_range = .initSerial,
            .h_range = .initParallel,
            .content = content.index,
            .spec = .{
                .w = options.width,
                .h = options.height,
                .padding = options.padding,
                .spill = options.spill,
                .gap = options.gap,
            },
            .wrap = content.wrap,
            .direction = .horizontal,
        },
    );
    try self.stack.append(self.allocator, @intCast(id));
}

pub fn endHBox(l: *Layout) !void {
    const e = &l.elements.items[l.stack.getLast()];
    std.debug.assert(e.direction == .horizontal);
    try l.endElement(e);
}

pub fn beginVBox(self: *Layout, content: Content, options: BoxOptions) !void {
    const id = self.elements.items.len;
    try self.elements.append(
        self.allocator,
        .{
            .w_range = .initParallel,
            .h_range = .initSerial,
            .content = content.index,
            .spec = .{
                .gap = options.gap,
                .w = options.width,
                .h = options.height,
                .padding = options.padding,
                .spill = options.spill,
            },
            .wrap = content.wrap,
            .direction = .vertical,
        },
    );
    try self.stack.append(self.allocator, @intCast(id));
}

pub fn endVBox(self: *Layout) !void {
    const e = &self.elements.items[self.stack.getLast()];
    std.debug.assert(e.direction == .vertical);
    try self.endElement(e);
}
