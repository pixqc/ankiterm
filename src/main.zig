const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

const cli = @import("cli.zig");

// SECTION: utils =============================================================

fn wrapText(allocator: std.mem.Allocator, text: []const u8, line_length: usize) ![]u8 {
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

fn bytesToHex(bytes: *const [8]u8) [16]u8 {
    var hex: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{s}", .{std.fmt.fmtSliceHexLower(bytes)}) catch unreachable;
    return hex;
}

fn hexToBytes(hex: *[]const u8) ![8]u8 {
    var bytes: [8]u8 = undefined;
    _ = try std.fmt.hexToBytes(&bytes, hex);
    return bytes;
}

// SECTION: data structures ===================================================

// LINGO:
// - card: a flashcard item
// - review: a review of a card
// - deck: a collection of cards and reviews

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
    // card_hash is card id
    // slice(sha256(concat(front,back)), 0, 8);
    // 8 bytes, store as hex string (16 chars)
    // card hash should not be saved to deck
    // having to worry about card id when adding new cards is annoying
    card_hash: [8]u8 = undefined,
    type: []const u8 = "card",
    front: []const u8,
    back: []const u8,
    nextReview: ?u32 = null, // unix second

    fn toString(self: Card, allocator: std.mem.Allocator) ![]u8 {
        const tmp = .{
            .type = self.type,
            .front = self.front,
            .back = self.back,
        };

        var string = std.ArrayList(u8).init(allocator);
        errdefer string.deinit();
        try std.json.stringify(tmp, .{}, string.writer());
        return string.toOwnedSlice();
    }
};

const Review = struct {
    type: []const u8 = "review",
    id: u32,
    card_hash: [8]u8,
    difficulty_rating: u8,
    timestamp: u32, // unix second
    algo: SRSAlgo,

    fn toString(self: Review, allocator: std.mem.Allocator) ![]u8 {
        const tmp = .{
            .type = self.type,
            .id = self.id,
            .card_hash = bytesToHex(&self.card_hash),
            .difficulty_rating = self.difficulty_rating,
            .timestamp = self.timestamp,
            .algo = self.algo.toString(),
        };

        var string = std.ArrayList(u8).init(allocator);
        errdefer string.deinit();
        try std.json.stringify(tmp, .{}, string.writer());
        return string.toOwnedSlice();
    }
};

fn getDefaultDeck(allocator: std.mem.Allocator) ![]u8 {
    const cards = [_]Card{
        .{ .front = "2^8", .back = "256" },
        .{ .front = "what is string in zig", .back = "pointer to null-terminated u8 array" },
        .{ .front = "what is a symlink file", .back = "pointer to file/dir" },
    };
    const reviews = [_]Review{
        .{ .id = 1, .card_hash = .{ 191, 58, 6, 27, 32, 236, 22, 253 }, .difficulty_rating = 5, .timestamp = 1718949322, .algo = SRSAlgo.sm2 },
        .{ .id = 2, .card_hash = .{ 230, 203, 160, 172, 115, 67, 97, 68 }, .difficulty_rating = 0, .timestamp = 1718949322, .algo = SRSAlgo.sm2 },
        .{ .id = 3, .card_hash = .{ 167, 78, 138, 228, 253, 116, 83, 95 }, .difficulty_rating = 0, .timestamp = 1718949322, .algo = SRSAlgo.sm2 },
    };
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    for (cards) |card| {
        const raw = try card.toString(allocator);
        try writer.writeAll(raw);
        try writer.writeByte('\n');
    }
    for (reviews) |review| {
        const raw = try review.toString(allocator);
        try writer.writeAll(raw);
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

fn getCardHash(allocator: std.mem.Allocator, card: Card) ![8]u8 {
    const content_slices = [_][]const u8{ card.front, card.back };
    const card_content = try std.mem.concat(allocator, u8, &content_slices);
    defer allocator.free(card_content);
    var card_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(card_content, &card_hash, .{});
    return card_hash[0..8].*;
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
            var card = try std.json.parseFromSlice(Card, allocator, line, .{});
            card.value.card_hash = try getCardHash(allocator, card.value);
            try cards.append(card.value);
        } else if (std.mem.eql(u8, typ, "review")) {
            const review = try std.json.parseFromSlice(Review, allocator, line, .{});
            try reviews.append(review.value);
        }
    }
}

fn reviewCard(allocator: std.mem.Allocator, card: Card, review_id: u32, stdout: @TypeOf(std.io.getStdOut().writer())) !void {
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
        try stdout.writeAll("\n");
        try stdout.writeAll(
            \\(0) Blackout
            \\(1) Wrong, hard
            \\(2) Wrong, need hint
            \\(3) Correct, hard recall
            \\(4) Correct, easy recall
            \\(5) Correct, instant recall
            \\Your rating: 
        );

        var input_buffer = std.ArrayList(u8).init(allocator);
        var input_reader = std.io.getStdIn().reader();
        try input_reader.streamUntilDelimiter(input_buffer.writer(), '\n', 2);
        const input = input_buffer.items;
        const difficulty_rating = std.fmt.parseInt(u8, input, 10) catch continue;

        if (difficulty_rating > 5) continue;
        const review = Review{
            .id = review_id,
            .type = "review",
            .card_hash = card.card_hash,
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

    // SECTION: sandbox, for testing small code snippets ======================

    const sandbox_mode = env_map.get("SANDBOX") != null and std.mem.eql(u8, env_map.get("SANDBOX").?, "1");
    if (sandbox_mode) {
        try sandbox(allocator);
        std.posix.exit(0);
    }

    // SECTION: main ==========================================================

    const stdout = std.io.getStdOut().writer();

    var arg_iterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();
    const cmd = try cli.parse(&arg_iterator);

    switch (cmd) {
        .init => |init_cmd| {
            const file = std.fs.cwd().openFile(init_cmd.filename, .{}) catch |err| switch (err) {
                // only write if file doesn't exist
                error.FileNotFound => {
                    const deck = try getDefaultDeck(allocator);
                    const bytesWritten = try writeFile(init_cmd.filename, deck);
                    try stdout.print("Successfully wrote {d} bytes to {s}.\n", .{ bytesWritten, init_cmd.filename });
                    std.posix.exit(0);
                },
                else => |e| return e,
            };
            defer file.close();
            cli.fatal("file already exists, choose a different filename or delete the existing file", .{});
        },
        .review => |review_cmd| {
            const deck = try readDeck(allocator, review_cmd.filename);
            var cards = ArrayList(Card).init(allocator);
            var reviews = ArrayList(Review).init(allocator);
            try parseDeck(allocator, &cards, &reviews, deck);
            // assumes review is not altered by user, autoinc u32
            var review_id: u32 = @intCast(reviews.items.len + 1);
            for (cards.items) |card| {
                try reviewCard(allocator, card, review_id, stdout);
                review_id += 1;
            }
            try stdout.print("\nYou have finished reviewing all the flashcards.\n", .{});
        },
        .version => {
            try std.io.getStdOut().writeAll("ankiterm 0.0.0\n");
            std.posix.exit(0);
        },
        .help => {
            try std.io.getStdOut().writeAll(cli.Command.help);
            std.posix.exit(0);
        },
    }
}

fn sandbox(allocator: std.mem.Allocator) !void {
    const defaultDeck = try getDefaultDeck(allocator);
    print("defaultDeck: {s}\n", .{defaultDeck});
    // var cards = ArrayList(Card).init(allocator);
    // var reviews = ArrayList(Review).init(allocator);
    // try parseDeck(allocator, &cards, &reviews, defaultDeck);
    // print("defaultDeck: {any}\n", .{defaultDeck});
    // print("cards: {any}\n", .{cards.items});
    // // for each card print the front and the card_hash
    // for (cards.items) |card| {
    //     print("card: {s}; ", .{card.front});
    //     print("card_hash: {any}\n", .{card.card_hash});
    // }
}

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
