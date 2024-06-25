const std = @import("std");

const SRSAlgo = enum { SM2 };

const Card = struct {
    front: []const u8,
    back: []const u8,
    id: u32,
};

const Review = struct {
    id: u32,
    card_id: u32,
    difficulty_rating: u8,
    timestamp: u32,
    algo: SRSAlgo,
};

pub const StudyUnit = union(enum) {
    card: Card,
    review: Review,
};

fn init_study_units() [6]StudyUnit {
    const cards = [_]Card{
        .{ .front = "2^8", .back = "256", .id = 1 },
        .{ .front = "bocchi band is called", .back = "kessoku", .id = 2 },
        .{ .front = "what's a symlink (unix)", .back = "pointer to file/dir", .id = 3 },
    };
    const reviews = [_]Review{
        .{ .id = 1, .card_id = 1, .difficulty_rating = 5, .timestamp = 1718949322, .algo = .SM2 },
        .{ .id = 2, .card_id = 2, .difficulty_rating = 0, .timestamp = 1718949322, .algo = .SM2 },
        .{ .id = 3, .card_id = 3, .difficulty_rating = 3, .timestamp = 1718949322, .algo = .SM2 },
    };

    comptime {
        std.debug.assert(cards.len == reviews.len);
    }

    return comptime blk: {
        var units: [cards.len + reviews.len]StudyUnit = undefined;
        for (cards, 0..) |card, i| {
            units[i] = .{ .card = card };
            units[i + cards.len] = .{ .review = reviews[i] };
        }
        break :blk units;
    };
}

fn print_unit(unit: StudyUnit, writer: anytype) !void {
    try std.json.stringify(unit, .{}, writer);
    try writer.writeByte('\n');
}

pub fn main() !void {
    const study_units = init_study_units();
    const stdout = std.io.getStdOut().writer();

    for (study_units) |unit| {
        try print_unit(unit, stdout);
    }
}
