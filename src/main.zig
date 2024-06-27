const std = @import("std");
const print = std.debug.print;

const SRSAlgo = enum {
    sm2,
    // fsrs tonite king?
    // https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm

    pub fn toString(self: SRSAlgo) []const u8 {
        return switch (self) {
            .sm2 => "sm2",
        };
    }
};

const Card = struct {
    type: []const u8 = "card",
    id: u32,
    front: []const u8,
    back: []const u8,
};

const Review = struct {
    type: []const u8 = "review",
    id: u32,
    card_id: u32,
    difficulty_rating: u8,
    timestamp: u64,
    algo: SRSAlgo,
};

pub const StudyUnit = union(enum) {
    card: Card,
    review: Review,
};

const default_cards = [_]Card{
    .{ .id = 1, .front = "2^8", .back = "256" },
    .{ .id = 2, .front = "what is string in zig", .back = "pointer to null-terminated u8 array" },
    .{ .id = 3, .front = "what is a symlink file", .back = "pointer to file/dir" },
};

const default_reviews = [_]Review{
    .{ .id = 1, .card_id = 1, .difficulty_rating = 5, .timestamp = 1718949322, .algo = SRSAlgo.sm2 },
    .{ .id = 2, .card_id = 2, .difficulty_rating = 0, .timestamp = 1718949322, .algo = SRSAlgo.sm2 },
    .{ .id = 3, .card_id = 3, .difficulty_rating = 3, .timestamp = 1718949322, .algo = SRSAlgo.sm2 },
};

const default_units = blk: {
    var units: [default_cards.len + default_reviews.len]StudyUnit = undefined;
    for (default_cards, 0..) |card, i| {
        units[i] = .{ .card = card };
    }
    for (default_reviews, 0..) |review, i| {
        units[default_cards.len + i] = .{ .review = review };
    }
    break :blk units;
};

fn init(stdout: @TypeOf(std.io.getStdOut().writer())) !void {
    for (default_units) |unit| {
        switch (unit) {
            .card => try std.json.stringify(unit.card, .{}, stdout),
            .review => try std.json.stringify(unit.review, .{}, stdout),
        }
        try stdout.writeByte('\n');
    }
}

fn init_deck(filename: []const u8) !void {
    const cwd: std.fs.Dir = std.fs.cwd();
    const file: std.fs.File = try cwd.createFile(filename, .{});
    defer file.close();
    var buffered_writer = std.io.bufferedWriter(file.writer());
    var writer = buffered_writer.writer();
    for (default_units) |unit| {
        switch (unit) {
            .card => try std.json.stringify(unit.card, .{}, writer),
            .review => try std.json.stringify(unit.review, .{}, writer),
        }
        try writer.writeByte('\n');
    }
    try buffered_writer.flush();
    const file_size = try file.getEndPos();
    std.debug.print("Successfully wrote {d} bytes to {s}.\n", .{ file_size, filename });
}

pub fn review_deck(filename: []const u8) !void {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{});
    defer file.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    var lines = std.mem.split(u8, file_contents, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue; // Skip empty lines

        std.debug.print("line: {s}\n", .{line});
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
        defer parsed.deinit();

        const root = parsed.value.object;
        const type_str = root.get("type").?.string;
        std.debug.print("type_str: {s}\n", .{type_str});
        // TODO: parse to struct
    }
}

pub fn main() !void {
    // playground
    if (true) {
        try review_deck("hi.ndjson");
        return;
    }
    const stdout = std.io.getStdOut().writer();
    const help =
        \\Usage: {s} <command> <filename> [options] [arguments]
        \\Commands:
        \\  init <filename>         Initialize a new deck
        \\  review <filename>       Review due cards
        \\  stats <filename>        Show statistics
        \\  tidy <filename>         Tidy up the deck
        \\
        \\Global Options:
        \\  --help                  Show help message and exit
        \\  --version               Show version information and exit
    ;

    if (std.os.argv.len < 2) {
        try stdout.print("{s}", .{help});
        return;
    }

    const arg: []const u8 = std.mem.span(std.os.argv[1]);
    if (std.mem.eql(u8, arg, "init")) {
        if (std.os.argv.len < 3) {
            try stdout.print("Error: 'init' command requires a filename.\n", .{});
            try stdout.print("Usage: {s} init <filename>\n", .{std.os.argv[0]});
            return;
        }
        const filename = std.mem.span(std.os.argv[2]);
        try init_deck(filename);
    } else if (std.mem.eql(u8, arg, "review")) {
        if (std.os.argv.len < 3) {
            try stdout.print("Error: 'review' command requires a filename.\n", .{});
            try stdout.print("Usage: {s} review <filename>\n", .{std.os.argv[0]});
            return;
        }
        const filename = std.mem.span(std.os.argv[2]);
        try review_deck(filename);
    }
    // else if (std.mem.eql(u8, arg, "stats")) {
    //     if (std.os.argv.len < 3) {
    //         try stdout.print("Error: 'stats' command requires a filename.\n", .{});
    //         try stdout.print("Usage: {s} stats <filename>\n", .{std.os.argv[0]});
    //         return;
    //     }
    //     const filename = std.mem.span(std.os.argv[2]);
    //     try init(stdout);
    // } else if (std.mem.eql(u8, arg, "tidy")) {
    //     if (std.os.argv.len < 3) {
    //         try stdout.print("Error: 'tidy' command requires a filename.\n", .{});
    //         try stdout.print("Usage: {s} tidy <filename>\n", .{std.os.argv[0]});
    //         return;
    //     }
    //     const filename = std.mem.span(std.os.argv[2]);
    //     try init(stdout);
    // }
    else if (std.mem.eql(u8, arg, "--version")) {
        try stdout.print("0.0.0\n", .{});
    } else if (std.mem.eql(u8, arg, "--help")) {
        try stdout.print(help, .{std.os.argv[0]});
    } else {
        try stdout.print("Unknown command: {s}\n", .{arg});
        try stdout.print("Use '{s} --help' for usage information.\n", .{std.os.argv[0]});
    }
}
