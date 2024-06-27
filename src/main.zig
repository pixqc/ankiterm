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

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    for (default_units) |unit| {
        switch (unit) {
            .card => try std.json.stringify(unit.card, .{}, stdout),
            .review => try std.json.stringify(unit.review, .{}, stdout),
        }
        try stdout.writeByte('\n');
    }
}
