const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const json = std.json;
const ArrayList = std.ArrayList;

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

fn getDefaultDeck(allocator: std.mem.Allocator) ![]u8 {
    const cards = [_]Card{
        .{ .id = 1, .front = "2^8", .back = "256" },
        .{ .id = 2, .front = "what is string in zig", .back = "pointer to null-terminated u8 array" },
        .{ .id = 3, .front = "what is a symlink file", .back = "pointer to file/dir" },
    };
    const reviews = [_]Review{
        .{ .id = 1, .card_id = 1, .difficulty_rating = 5, .timestamp = 1718949322, .algo = SRSAlgo.sm2 },
        .{ .id = 2, .card_id = 2, .difficulty_rating = 0, .timestamp = 1718949322, .algo = SRSAlgo.sm2 },
        .{ .id = 3, .card_id = 3, .difficulty_rating = 3, .timestamp = 1718949322, .algo = SRSAlgo.sm2 },
    };

    // create a buffer to write to
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    const writer = buf.writer();
    for (cards) |card| {
        try json.stringify(card, .{}, writer);
        try writer.writeByte('\n');
    }
    for (reviews) |review| {
        try json.stringify(review, .{}, writer);
        try writer.writeByte('\n');
    }
    return buf.toOwnedSlice();
}

fn writeDeck(filename: []const u8, deck: []u8) !usize {
    const cwd: std.fs.Dir = std.fs.cwd();
    const file: std.fs.File = try cwd.createFile(filename, .{});
    defer file.close();

    // flush to file
    var buffered_writer = std.io.bufferedWriter(file.writer());
    var writer = buffered_writer.writer();
    const file_size = try writer.write(deck);
    try buffered_writer.flush();
    return file_size;
}

fn readDeck(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

pub fn main() !void {

    // SECTION: playground, for testing small code snippets ===================

    if (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        print("{s}\n", .{"hi playground"});

        const raw = try getDefaultDeck(allocator);
        var it = std.mem.tokenizeAny(u8, raw, "\n");
        while (it.next()) |line| {
            if (line.len == 0) {
                continue;
            }
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
            const root = parsed.value.object;
            const typ = root.get("type").?.string;
            print("{s}\n", .{typ});

            if (std.mem.eql(u8, typ, "card")) {
                const card = try std.json.parseFromSlice(Card, allocator, line, .{});
                print("{any}\n", .{card.value});
            } else if (std.mem.eql(u8, typ, "review")) {
                const review = try std.json.parseFromSlice(Review, allocator, line, .{});
                print("{any}\n", .{review.value});
            }
        }
        return;
    }

    // SECTION: main ==========================================================

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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const arg: []const u8 = std.mem.span(std.os.argv[1]);
    if (std.mem.eql(u8, arg, "init")) {
        if (std.os.argv.len < 3) {
            try stdout.print("Error: 'init' command requires a filename.\n", .{});
            try stdout.print("Usage: {s} init <filename>\n", .{std.os.argv[0]});
            return;
        }

        const filename = std.mem.span(std.os.argv[2]);
        const file = std.fs.cwd().openFile(filename, .{}) catch |err| switch (err) {
            // only write if file doens't exist
            error.FileNotFound => {
                const deck = try getDefaultDeck(allocator);
                const bytesWritten = try writeDeck(filename, deck);
                try stdout.print("Successfully wrote {d} bytes to {s}.\n", .{ bytesWritten, filename });
                return;
            },
            else => |e| return e,
        };
        defer file.close();
        try stdout.print("Error: File '{s}' already exists. Choose a different filename or delete the existing file.\n", .{filename});
    } else if (std.mem.eql(u8, arg, "review")) {
        if (std.os.argv.len < 3) {
            try stdout.print("Error: 'review' command requires a filename.\n", .{});
            try stdout.print("Usage: {s} review <filename>\n", .{std.os.argv[0]});
            return;
        }
        try stdout.print("TODO: impl this", .{});
    } else if (std.mem.eql(u8, arg, "--version")) {
        try stdout.print("0.0.0\n", .{});
    } else if (std.mem.eql(u8, arg, "--help")) {
        try stdout.print(help, .{std.os.argv[0]});
    } else {
        try stdout.print("Unknown command: {s}\n", .{arg});
        try stdout.print("Use '{s} --help' for usage information.\n", .{std.os.argv[0]});
    }
}

// use `zig test src/main.zig` to run small code in isolation

test "inits properly" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const filename = "test.ndjson";
    const deck = try getDefaultDeck(allocator);
    _ = try writeDeck(filename, deck);

    // read
    const file_content = try readDeck(allocator, filename);
    try expect(std.mem.eql(u8, file_content, deck));

    // cleanup
    const cwd = std.fs.cwd();
    try cwd.deleteFile(filename);
}
