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

// LINGO:
// - card: a flashcard item
// - review: a review of a card
// - deck: a collection of cards and reviews

const Card = struct {
    type: []const u8 = "card",
    id: u32,
    front: []const u8,
    back: []const u8,
    nextReview: ?u32 = null, // unix second
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

fn writeFile(filename: []const u8, raw: []u8) !usize {
    const cwd: std.fs.Dir = std.fs.cwd();
    const file: std.fs.File = try cwd.createFile(filename, .{});
    defer file.close();

    // flush to file
    var buffered_writer = std.io.bufferedWriter(file.writer());
    var writer = buffered_writer.writer();
    const file_size = try writer.write(raw);
    try buffered_writer.flush();
    return file_size;
}

fn readDeck(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

fn parseDeck(allocator: std.mem.Allocator, cards: *ArrayList(Card), reviews: *ArrayList(Review), raw: []u8) !void {
    var it = std.mem.tokenizeAny(u8, raw, "\n");
    while (it.next()) |line| {
        if (line.len == 0) {
            continue;
        }
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
        const root = parsed.value.object;
        const typ = root.get("type").?.string;
        if (std.mem.eql(u8, typ, "card")) {
            const card = try std.json.parseFromSlice(Card, allocator, line, .{});
            try cards.append(card.value);
        } else if (std.mem.eql(u8, typ, "review")) {
            const review = try std.json.parseFromSlice(Review, allocator, line, .{});
            try reviews.append(review.value);
        }
    }
}

pub fn wrapText(allocator: std.mem.Allocator, text: []const u8, line_length: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var line_start: usize = 0;
    var last_space: ?usize = null;
    var current_line_length: usize = 0;
    for (text, 0..) |char, i| {
        if (char == ' ') {
            last_space = i;
        }
        current_line_length += 1;
        if (current_line_length > line_length) {
            if (last_space) |space| {
                try result.appendSlice(text[line_start..space]);
                try result.append('\n');
                line_start = space + 1;
                current_line_length = i - space;
                last_space = null;
            } else {
                // if no space found, force wrap at current position
                try result.appendSlice(text[line_start..i]);
                try result.append('\n');
                line_start = i;
                current_line_length = 0;
            }
        }
    }
    if (line_start < text.len) {
        try result.appendSlice(text[line_start..]);
    }
    return result.toOwnedSlice();
}

pub fn reviewCard(allocator: std.mem.Allocator, card: Card, stdout: @TypeOf(std.io.getStdOut().writer())) !void {
    const MAX_WIDTH = 60;
    const wrapped_front = try wrapText(allocator, card.front, MAX_WIDTH);
    const wrapped_back = try wrapText(allocator, card.back, MAX_WIDTH);

    try stdout.writeAll("\n\n");
    try stdout.writeByteNTimes('=', MAX_WIDTH);
    try stdout.writeAll("\n");
    try stdout.print("Q: {s}\n", .{wrapped_front});
    try stdout.writeByteNTimes('-', MAX_WIDTH);

    var buffer: [1]u8 = undefined;
    _ = try std.io.getStdIn().read(&buffer);

    try stdout.print("A: {s}\n", .{wrapped_back});
    try stdout.writeByteNTimes('=', MAX_WIDTH);

    while (true) {
        try stdout.writeAll("\n(0) Blackout\n(1) Wrong, hard\n(2) Wrong, need hint\n(3) Correct, hard recall\n(4) Correct, easy recall\n(5) Correct, instant recall\nYour rating: ");

        var input_buffer = std.ArrayList(u8).init(allocator);
        var input_reader = std.io.getStdIn().reader();
        try input_reader.streamUntilDelimiter(input_buffer.writer(), '\n', 2);
        const input = input_buffer.items;
        const difficulty_rating = std.fmt.parseInt(u8, input, 10) catch continue;

        if (difficulty_rating > 5) continue;
        const review = Review{
            .id = 0,
            .type = "review",
            .card_id = card.id,
            .difficulty_rating = difficulty_rating,
            .timestamp = @intCast(std.time.timestamp()),
            .algo = SRSAlgo.sm2,
        };
        print("review: {any}\n", .{review});
        break;
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var env_map = try std.process.getEnvMap(allocator);

    // SECTION: playground, for testing small code snippets ===================
    // set PLAYGROUND=1 to run this code

    const playground_mode = env_map.get("PLAYGROUND") != null and std.mem.eql(u8, env_map.get("PLAYGROUND").?, "1");
    if (playground_mode) {
        print("{s}\n", .{"hi playground"});
        const deck = try getDefaultDeck(allocator);
        var cards = ArrayList(Card).init(allocator);
        var reviews = ArrayList(Review).init(allocator);
        try parseDeck(allocator, &cards, &reviews, deck);
        try reviewCard(allocator, cards.items[2], std.io.getStdOut().writer());
        return;
    }

    // SECTION: main ==========================================================

    const stdout = std.io.getStdOut().writer();
    const help =
        \\Usage: {s} <command> <filename>
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

    const argv = std.os.argv;
    if (argv.len < 2) {
        try stdout.print("{s}", .{help});
        return;
    }

    const arg: []const u8 = std.mem.span(argv[1]);
    if (std.mem.eql(u8, arg, "init")) {
        if (argv.len < 3) {
            try stdout.print("Error: 'init' command requires a filename.\n", .{});
            try stdout.print("Usage: {s} init <filename>\n", .{argv[0]});
            return;
        }

        const filename = std.mem.span(argv[2]);
        const file = std.fs.cwd().openFile(filename, .{}) catch |err| switch (err) {
            // only write if file doens't exist
            error.FileNotFound => {
                const deck = try getDefaultDeck(allocator);
                const bytesWritten = try writeFile(filename, deck);
                try stdout.print("Successfully wrote {d} bytes to {s}.\n", .{ bytesWritten, filename });
                return;
            },
            else => |e| return e,
        };
        defer file.close();
        try stdout.print("Error: File '{s}' already exists. Choose a different filename or delete the existing file.\n", .{filename});
    } else if (std.mem.eql(u8, arg, "review")) {
        if (argv.len < 3) {
            try stdout.print("Error: 'review' command requires a filename.\n", .{});
            try stdout.print("Usage: {s} review <filename>\n", .{argv[0]});
            return;
        }
        const filename = std.mem.span(argv[2]);
        const deck = try readDeck(allocator, filename);
        var cards = ArrayList(Card).init(allocator);
        var reviews = ArrayList(Review).init(allocator);
        try parseDeck(allocator, &cards, &reviews, deck);
        for (cards.items) |card| {
            try reviewCard(allocator, card, stdout);
        }
    } else if (std.mem.eql(u8, arg, "--version")) {
        try stdout.print("0.0.0\n", .{});
    } else if (std.mem.eql(u8, arg, "--help")) {
        try stdout.print(help, .{argv[0]});
    } else {
        try stdout.print("Unknown command: {s}\n", .{arg});
        try stdout.print("Use '{s} --help' for usage information.\n", .{argv[0]});
    }
}

// use `zig test src/main.zig` to run small code in isolation

test "inits properly" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const filename = "test.ndjson";
    const deck = try getDefaultDeck(allocator);
    _ = try writeFile(filename, deck);

    // read
    const file_content = try readDeck(allocator, filename);
    try expect(std.mem.eql(u8, file_content, deck));

    // cleanup
    const cwd = std.fs.cwd();
    try cwd.deleteFile(filename);
}
