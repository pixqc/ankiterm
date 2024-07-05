const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const json = std.json;
const fmt = std.fmt;
const hash = std.crypto.hash;
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

const CARD_JSON_TMPL = "{{\"type\":\"card\",\"front\":\"{s}\",\"back\":\"{s}\"}}";
const REVIEW_JSON_TMPL = "{{\"type\":\"review\",\"id\":{d},\"card_hash\":\"{s}\",\"difficulty_rating\":{d},\"timestamp\":{d},\"algo\":\"{s}\"}}";

const Card = struct {
    type: []const u8 = "card",
    front: []const u8,
    back: []const u8,

    // card_hash is card id - slice(sha256(stringify(card)), 0, 8)
    // 8 byte, 16 hex chars
    // card id is stored in deck by review
    // everything deals in hex chars
    fn getHashComptime(comptime self: Card) [16]u8 {
        const card_str = self.toStringComptime();
        var card_hash: [32]u8 = undefined;
        hash.sha2.Sha256.hash(card_str, &card_hash, .{});
        return std.fmt.bytesToHex(card_hash[0..8], .lower);
    }

    fn getHash(self: Card, allocator: std.mem.Allocator) ![16]u8 {
        const card_str = try self.toString(allocator);
        var card_hash: [32]u8 = undefined;
        hash.sha2.Sha256.hash(card_str, &card_hash, .{});
        return std.fmt.bytesToHex(card_hash[0..8], .lower);
    }

    // hash and next review should be lazy
    fn getNextReview(self: Card, reviews: *ArrayList(Review)) i64 {
        _ = self;
        const minEaseFactor = 1.3;
        var frequency: u32 = 0;
        var lastReview: i64 = 0;
        var ease: f32 = 2.5; // initial ease: 2.5
        var nextReview: i64 = 0;

        for (reviews.items) |review| {
            frequency += 1;
            if (review.timestamp > lastReview) {
                lastReview = review.timestamp;
            }

            switch (review.difficulty_rating) {
                0 => ease -= 0.8,
                1 => ease -= 0.5,
                2 => ease -= 0.3,
                3 => ease += 0.1,
                4 => ease += 0.15,
                5 => ease += 0.2,
                else => unreachable,
            }

            if (review.difficulty_rating < 3) {
                frequency = 0;
            }
        }
        ease = @max(minEaseFactor, ease);

        const now = std.time.timestamp();
        if (frequency == 0) {
            return now;
        } else if (frequency == 1) {
            nextReview = 1 * 24 * 60 * 60; // 1 day in seconds
        } else if (frequency == 2) {
            nextReview = 6 * 24 * 60 * 60; // 6 days in seconds
        } else {
            const prevInterval: f32 = @floatFromInt(now - lastReview);
            nextReview = @intFromFloat(prevInterval * ease);
        }

        return lastReview + nextReview;
    }

    fn toStringComptime(comptime self: Card) []const u8 {
        return std.fmt.comptimePrint(CARD_JSON_TMPL, .{ self.front, self.back });
    }

    fn toString(self: Card, allocator: std.mem.Allocator) ![]const u8 {
        var buf = ArrayList(u8).init(allocator);
        defer buf.deinit();
        try std.fmt.format(buf.writer(), CARD_JSON_TMPL, .{ self.front, self.back });
        return buf.toOwnedSlice();
    }
};

const Review = struct {
    type: []const u8 = "review",
    id: u32,
    card_hash: [16]u8,
    difficulty_rating: u8,
    timestamp: i64, // unix second, i64 just to follow zig's default type
    algo: []const u8 = "sm2", // can add more algorithms later

    fn toStringComptime(self: Review) []const u8 {
        return std.fmt.comptimePrint(REVIEW_JSON_TMPL, .{
            self.id,
            self.card_hash,
            self.difficulty_rating,
            self.timestamp,
            self.algo,
        });
    }

    fn toString(self: Review, allocator: std.mem.Allocator) ![]u8 {
        var buf = ArrayList(u8).init(allocator);
        const result = std.fmt.bufPrint(&buf, REVIEW_JSON_TMPL, .{
            self.id,
            self.card_hash,
            self.difficulty_rating,
            self.timestamp,
            self.algo,
        });
        return allocator.dupe(u8, result);
    }
};

const Deck = union(enum) {
    card: Card,
    review: Review,
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

const dummy_reviews = blk: {
    @setEvalBranchQuota(10000); // so the getHashComptime works
    const reviews = [_]Review{
        .{
            .id = 1,
            .card_hash = dummy_cards[0].getHashComptime(),
            .difficulty_rating = 5,
            .timestamp = 1718949322,
        },
        .{
            .id = 2,
            .card_hash = dummy_cards[1].getHashComptime(),
            .difficulty_rating = 0,
            .timestamp = 1718949322,
        },
        .{
            .id = 3,
            .card_hash = dummy_cards[2].getHashComptime(),
            .difficulty_rating = 1,
            .timestamp = 1718949322,
        },
        .{
            .id = 4,
            .card_hash = dummy_cards[0].getHashComptime(),
            .difficulty_rating = 3,
            .timestamp = 1718949322,
        },
        .{
            .id = 5,
            .card_hash = dummy_cards[1].getHashComptime(),
            .difficulty_rating = 2,
            .timestamp = 1718949322,
        },
        .{
            .id = 6,
            .card_hash = dummy_cards[2].getHashComptime(),
            .difficulty_rating = 5,
            .timestamp = 1718949322,
        },
    };
    break :blk reviews;
};

const dummy_deck = blk: {
    var result: []const u8 = "";
    for (dummy_cards) |card| {
        result = result ++ card.toStringComptime() ++ "\n";
    }
    for (dummy_reviews) |review| {
        result = result ++ review.toStringComptime() ++ "\n";
    }
    break :blk result;
};

fn parseDeck(allocator: std.mem.Allocator, raw: []const u8) ![]Deck {
    var deck = std.ArrayList(Deck).init(allocator);

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
            const card = try json.parseFromSlice(Card, allocator, line, .{});
            defer card.deinit();
            try deck.append(Deck{ .card = card.value });
        } else if (std.mem.eql(u8, typ, "review")) {
            const review = try json.parseFromSlice(Review, allocator, line, .{});
            defer review.deinit();
            try deck.append(Deck{ .review = review.value });
        }
    }
    return deck.items;
}

test parseDeck {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const deck = try parseDeck(allocator, dummy_deck);
    var card_idx: u8 = 0;
    var review_idx: u8 = 0;
    for (deck) |item| {
        switch (item) {
            .card => |card| {
                try expect(std.mem.eql(u8, card.front, dummy_cards[card_idx].front));
                try expect(std.mem.eql(u8, card.back, dummy_cards[card_idx].back));
                card_idx += 1;
            },
            .review => |review| {
                try expect(review.id == dummy_reviews[review_idx].id);
                try expect(std.mem.eql(u8, &review.card_hash, &dummy_reviews[review_idx].card_hash));
                try expect(review.difficulty_rating == dummy_reviews[review_idx].difficulty_rating);
                try expect(review.timestamp == dummy_reviews[review_idx].timestamp);
                review_idx += 1;
            },
        }
    }
    try expect(deck.len == dummy_cards.len + dummy_reviews.len);
}

fn reviewCard(allocator: std.mem.Allocator, card: Card) !u8 {
    const MAX_WIDTH = 60;
    const wrapped_front = try wrapText(allocator, card.front, MAX_WIDTH);
    const wrapped_back = try wrapText(allocator, card.back, MAX_WIDTH);

    const stdout = std.io.getStdOut().writer();
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
        return difficulty_rating;
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
                    try buf.appendSlice(dummy_deck);
                    const bytesWritten = try writeFile(init_cmd.filename, buf.items);
                    const stdout = std.io.getStdOut().writer();
                    try stdout.print("Successfully wrote {d} bytes to {s}.\n", .{ bytesWritten, init_cmd.filename });
                    std.posix.exit(0);
                },
                else => |e| return e,
            };
            defer file.close();
            cli.fatal("file already exists, choose a different filename or delete the existing file", .{});
        },
        .review => |review_cmd| {
            const deck_raw = try readFile(allocator, review_cmd.filename);
            const deck = try parseDeck(allocator, deck_raw);
            var cardMap = std.AutoHashMap([16]u8, Card).init(allocator);
            var reviewMap = std.AutoHashMap([16]u8, ArrayList(Review)).init(allocator);
            var max_review_id: u32 = 0;

            // first pass: fill the cards in reviewMap with new arraylist
            // second pass: append reviews to the corresponding card
            // "why not only do second pass" bc card without review is valid card
            for (deck) |item| {
                if (item == .card) {
                    const card = item.card;
                    const card_hash = try card.getHash(allocator);
                    print("{s}\n", .{card_hash});
                    try cardMap.put(card_hash, card);
                    try reviewMap.put(card_hash, ArrayList(Review).init(allocator));
                }
            }
            for (deck) |item| {
                if (item == .review) {
                    const review = item.review;
                    if (review.id > max_review_id) {
                        max_review_id = review.id;
                    }
                    if (reviewMap.getPtr(review.card_hash)) |reviews_ptr| {
                        try reviews_ptr.append(review);
                    } else {
                        // Handle error: review for non-existent card
                        std.debug.print("Error: Review for non-existent card\n", .{});
                        continue;
                    }
                }
            }

            var it = cardMap.iterator();
            while (it.next()) |kv| {
                const card_hash = kv.key_ptr.*;
                const card = kv.value_ptr.*;
                const reviews = reviewMap.getPtr(card_hash).?;
                if (card.getNextReview(reviews) <= std.time.timestamp()) {
                    const difficulty_rating = try reviewCard(allocator, card);

                    const review = Review{
                        .id = max_review_id + 1,
                        .type = "review",
                        .card_hash = card_hash,
                        .difficulty_rating = difficulty_rating,
                        .timestamp = @intCast(std.time.timestamp()),
                        .algo = "sm2",
                    };
                    print("review: {any}\n", .{review});
                }
            }

            const stdout = std.io.getStdOut().writer();
            try stdout.print("\nyou have finished reviewing all the flashcards\n", .{});
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
//

// for testing small code snippets
test "sandbox" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    print("{s}\n", .{dummy_deck});
    const deck = try parseDeck(allocator, dummy_deck);
    var my_map = std.hash_map.StringHashMap(i32).init(allocator);
    print("{any}\n", .{my_map});

    var idx: i32 = 0;
    for (deck) |item| {
        switch (item) {
            .card => |card| {
                _ = card;
                continue;
            },
            .review => |review| {
                try my_map.put(&review.card_hash, idx);
                idx += 1;
            },
        }
    }
    print("{any}\n", .{my_map});
    print("{d}\n", .{my_map.count()});
    print("{any}\n", .{my_map.get("f293baf387c5c190")});

    std.posix.exit(0);
}
