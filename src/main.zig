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

fn readFile(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

// SECTION: data structures ===================================================

// LINGO:
// - card: a flashcard item
// - review: a review of a card
// - deck: a collection of cards and reviews

const Card = struct {
    type: []const u8 = "card",
    front: []const u8,
    back: []const u8,
    tmpl: []const u8 = "{{\"type\":\"card\",\"front\":\"{s}\",\"back\":\"{s}\"}}",

    // card_hash is card id - slice(sha256(stringify(card)), 0, 8)
    // 8 byte, 16 hex chars
    // card id is stored in deck by review
    fn getHash(self: Card) [8]u8 {
        const card_str = self.toString();
        var card_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(card_str, &card_hash, .{});
        return card_hash[0..8].*;
    }

    fn getHashAlloc(self: Card, allocator: std.mem.Allocator) ![8]u8 {
        const card_str = try self.toStringAlloc(allocator);
        var card_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(card_str, &card_hash, .{});
        return card_hash[0..8].*;
    }

    // hash and next review should be lazy
    fn getNextReview(self: Card, reviews: *ArrayList(Review)) u32 {
        // TODO: sm2 here
        _ = reviews;
        _ = self;
        return 0;
    }

    fn toString(self: Card) []const u8 {
        return std.fmt.comptimePrint(self.tmpl, .{ self.front, self.back });
    }

    fn toStringAlloc(self: Card, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, self.tmpl, .{ self.front, self.back });
    }
};

const Review = struct {
    type: []const u8 = "review",
    id: u32,
    card: *const Card = undefined,
    difficulty_rating: u8,
    timestamp: u32, // unix second
    algo: []const u8 = "sm2", // can add more algorithms later
    tmpl: []const u8 = "{{\"type\":\"review\",\"id\":{d},\"card_hash\":\"{s}\",\"difficulty_rating\":{d},\"timestamp\":{d},\"algo\":\"{s}\"}}",

    fn toString(self: Review) []const u8 {
        const card_hash = bytesToHex(&self.card.getHash());
        return std.fmt.comptimePrint(self.tmpl, .{ self.id, card_hash, self.difficulty_rating, self.timestamp, self.algo });
    }

    fn toStringAlloc(self: Review, allocator: std.mem.Allocator) ![]u8 {
        const card_hash = bytesToHex(&self.card.getHash());
        return std.fmt.allocPrint(allocator, self.tmpl, .{ self.id, card_hash, self.difficulty_rating, self.timestamp, self.algo });
    }
};

// TODO: should use these to test sm2 too
const dummy_cards = [_]Card{
    .{
        .front = "2^8",
        .back = "256",
    },
    .{
        .front = "what is string in zig",
        .back = "pointer to null-terminated u8 array",
    },
    .{
        .front = "what is a symlink file",
        .back = "pointer to file/dir",
    },
};

const dummy_reviews = [_]Review{
    .{
        .id = 1,
        .card = &dummy_cards[0],
        .difficulty_rating = 5,
        .timestamp = 1718949322,
    },
    .{
        .id = 2,
        .card = &dummy_cards[1],
        .difficulty_rating = 0,
        .timestamp = 1718949322,
    },
    .{
        .id = 3,
        .card = &dummy_cards[2],
        .difficulty_rating = 0,
        .timestamp = 1718949322,
    },
    .{
        .id = 4,
        .card = &dummy_cards[0],
        .difficulty_rating = 0,
        .timestamp = 1718949322,
    },
    .{
        .id = 5,
        .card = &dummy_cards[1],
        .difficulty_rating = 0,
        .timestamp = 1718949322,
    },
    .{
        .id = 6,
        .card = &dummy_cards[2],
        .difficulty_rating = 0,
        .timestamp = 1718949322,
    },
};

const dummy_string = blk: {
    var result: []const u8 = "";
    for (dummy_cards) |card| {
        result = result ++ card.toString() ++ "\n";
    }
    for (dummy_reviews) |review| {
        result = result ++ review.toString() ++ "\n";
    }
    break :blk result;
};

fn parseCards(allocator: std.mem.Allocator, raw: []const u8) ![]Card {
    var cards = std.ArrayList(Card).init(allocator);
    var lines = std.mem.split(u8, raw, "\n");

    while (lines.next()) |line| {
        if (line.len == 0) {
            continue;
        }
        if (line[0] == '/' or line[0] == '#') {
            // skip items that start with // or #
            continue;
        }

        const parsed = json.parseFromSlice(json.Value, allocator, line, .{}) catch |err| {
            std.debug.print("Error parsing JSON: {}\n", .{err});
            continue;
        };
        defer parsed.deinit();
        const root = parsed.value.object;
        const typ = root.get("type").?.string;
        if (std.mem.eql(u8, typ, "card")) {
            const front = root.get("front").?.string;
            const back = root.get("back").?.string;
            const card = Card{ .type = typ, .front = front, .back = back };
            try cards.append(card);
        }
    }
    return cards.items;
}

// fn parseDeck(allocator: std.mem.Allocator, cards: *ArrayList(Card), reviews: *ArrayList(Review), raw: []u8) !void {
//     var it = std.mem.tokenizeAny(u8, raw, "\n");
//     while (it.next()) |line| {
//         if (line.len == 0) {
//             continue;
//         }
//         const parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
//         const root = parsed.value.object;
//         const typ = root.get("type").?.string;
//         if (std.mem.eql(u8, typ, "card")) {
//             var card = try std.json.parseFromSlice(Card, allocator, line, .{});
//             card.value.card_hash = try getCardHash(allocator, card.value);
//             try cards.append(card.value);
//         } else if (std.mem.eql(u8, typ, "review")) {
//             const review = try std.json.parseFromSlice(Review, allocator, line, .{});
//             try reviews.append(review.value);
//         }
//     }
// }

// fn reviewCard(allocator: std.mem.Allocator, card: Card, review_id: u32, stdout: @TypeOf(std.io.getStdOut().writer())) !void {
//     const MAX_WIDTH = 60;
//     const wrapped_front = try wrapText(allocator, card.front, MAX_WIDTH);
//     const wrapped_back = try wrapText(allocator, card.back, MAX_WIDTH);
//
//     try stdout.writeAll("\n\n");
//     try stdout.writeByteNTimes('=', MAX_WIDTH);
//     try stdout.writeAll("\n");
//     try stdout.print("Q: {s}\n", .{wrapped_front});
//     try stdout.writeByteNTimes('-', MAX_WIDTH);
//
//     var buffer: [1]u8 = undefined;
//     _ = try std.io.getStdIn().read(&buffer);
//
//     try stdout.print("A: {s}\n", .{wrapped_back});
//     try stdout.writeByteNTimes('=', MAX_WIDTH);
//
//     while (true) {
//         try stdout.writeAll("\n");
//         try stdout.writeAll(
//             \\(0) Blackout
//             \\(1) Wrong, hard
//             \\(2) Wrong, need hint
//             \\(3) Correct, hard recall
//             \\(4) Correct, easy recall
//             \\(5) Correct, instant recall
//             \\Your rating:
//         );
//
//         var input_buffer = std.ArrayList(u8).init(allocator);
//         var input_reader = std.io.getStdIn().reader();
//         try input_reader.streamUntilDelimiter(input_buffer.writer(), '\n', 2);
//         const input = input_buffer.items;
//         const difficulty_rating = std.fmt.parseInt(u8, input, 10) catch continue;
//
//         if (difficulty_rating > 5) continue;
//         const review = Review{
//             .id = review_id,
//             .type = "review",
//             .card = @constCast(&card),
//             .difficulty_rating = difficulty_rating,
//             .timestamp = @intCast(std.time.timestamp()),
//             .algo = SRSAlgo.sm2,
//         };
//         print("review: {any}\n", .{review});
//         break;
//     }
// }

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout = std.io.getStdOut().writer();

    var env_map = try std.process.getEnvMap(allocator);

    const sandbox_mode = env_map.get("SANDBOX") != null and std.mem.eql(u8, env_map.get("SANDBOX").?, "1");

    // SECTION: sandbox, for testing small code snippets ======================

    if (sandbox_mode) {
        print("{s}", .{dummy_string});
        const cards = try parseCards(allocator, dummy_string);
        print("{any}\n", .{cards});
        std.posix.exit(0);
    }

    // SECTION: main ==========================================================

    var arg_iterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();
    const cmd = try cli.parse(&arg_iterator);

    switch (cmd) {
        .init => |init_cmd| {
            const cwd = std.fs.cwd();
            const file = cwd.openFile(init_cmd.filename, .{}) catch |err| switch (err) {
                // only write if file doesn't exist
                error.FileNotFound => {
                    var buf = std.ArrayList(u8).init(allocator);
                    try buf.appendSlice(dummy_string);
                    const bytesWritten = try writeFile(init_cmd.filename, buf.items);
                    try stdout.print("Successfully wrote {d} bytes to {s}.\n", .{ bytesWritten, init_cmd.filename });
                    std.posix.exit(0);
                },
                else => |e| return e,
            };
            defer file.close();
            cli.fatal("file already exists, choose a different filename or delete the existing file", .{});
        },
        .review => |review_cmd| {
            // const deck = try readFile(allocator, review_cmd.filename);
            // var cards = ArrayList(Card).init(allocator);
            // var reviews = ArrayList(Review).init(allocator);
            // try parseDeck(allocator, &cards, &reviews, deck);
            // // assumes review is not altered by user, autoinc u32
            // var review_id: u32 = @intCast(reviews.items.len + 1);
            // for (cards.items) |card| {
            //     try reviewCard(allocator, card, review_id, stdout);
            //     review_id += 1;
            // }
            _ = review_cmd;
            try stdout.print("\nyou have finished reviewing all the flashcards.\n", .{});
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

// test "inits properly" {
//     var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     defer arena.deinit();
//     const allocator = arena.allocator();
//
//     const filename = "test.ndjson";
//     const deck = try getDefaultDeck(allocator);
//     _ = try writeFile(filename, deck);
//
//     // read
//     const file_content = try readDeck(allocator, filename);
//     try expect(std.mem.eql(u8, file_content, deck));
//
//     // cleanup
//     const cwd = std.fs.cwd();
//     try cwd.deleteFile(filename);
// }
