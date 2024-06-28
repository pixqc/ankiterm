const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const json = std.json;

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

fn get_default_deck() ![]u8 {
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

    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
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

fn write_deck(filename: []const u8, deck: []u8) !usize {
    const cwd: std.fs.Dir = std.fs.cwd();
    const file: std.fs.File = try cwd.createFile(filename, .{});
    defer file.close();
    var buffered_writer = std.io.bufferedWriter(file.writer());
    var writer = buffered_writer.writer();
    const file_size = try writer.write(deck);
    try buffered_writer.flush();
    print("Successfully wrote {d} bytes to {s}.\n", .{ file_size, filename });
    return file_size;
}

// pub fn read_deck(filename: []const u8) ![]u8 {
//     const cwd = std.fs.cwd();
//     const file = try cwd.openFile(filename, .{});
//     defer file.close();
//     const buf = try file.readAllAlloc(std.heap.page_allocator);
//     const bytes_read = try file.readAll(&buf);
//     // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     // defer arena.deinit();
//     // const allocator = arena.allocator();
//     // const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
//     // defer allocator.free(file_contents);
//     // var lines = std.ArrayList([]const u8).init(allocator);
//     // var iter = std.mem.split(u8, file_contents, "\n");
//     // while (iter.next()) |line| {
//     //     if (line.len > 0) {
//     //         try lines.append(try allocator.dupe(u8, line));
//     //     }
//     // }
//     // return lines;
// }
//
// pub fn review_deck(filename: []const u8) !void {
//     // const cwd = std.fs.cwd();
//     // const file = try cwd.openFile(filename, .{});
//     // defer file.close();
//     //
//     // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     // defer arena.deinit();
//     // const allocator = arena.allocator();
//     // const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
//     // defer allocator.free(file_contents);
//     //
//     // var lines = std.mem.split(u8, file_contents, "\n");
//     var lines = read_deck(filename);
//     while (lines.next()) |line| {
//         if (line.len == 0) continue; // Skip empty lines
//
//         print("line: {s}\n", .{line});
//         // try std.json.parseFromSlice(Card, allocator, line, .{}) catch |err| {
//         //     try std.json.parseFromSlice(Review, allocator, line, .{}) catch |err2| {
//         //         print("Error: {s}\n", .{err2});
//         //         return err2;
//         //     };
//         //     return err;
//         // };
//     }
// }

pub fn main() !void {
    // playground
    if (true) {
        const deck = try get_default_deck();
        try write_deck("test.ndjson", deck);
        print("{s}\n", .{deck});
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
        const deck = try get_default_deck();
        try write_deck(filename, deck);
    } else if (std.mem.eql(u8, arg, "review")) {
        if (std.os.argv.len < 3) {
            try stdout.print("Error: 'review' command requires a filename.\n", .{});
            try stdout.print("Usage: {s} review <filename>\n", .{std.os.argv[0]});
            return;
        }
        // const filename = std.mem.span(std.os.argv[2]);
        // try review_deck(filename);
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

// SECTION: playground ========================================================

fn mayError() !u8 {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();
    const isErr = rand.boolean();
    if (isErr) {
        return error.UnexpectedEof;
    }
    return rand.int(u8);
}

// use `zig test src/main.zig` to run small code in isolation

test "inits properly" {
    const filename = "test.ndjson";
    const deck = try get_default_deck();
    const bytes_written = try write_deck(filename, deck);

    // read
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{});
    defer file.close();
    var buf: [1024]u8 = undefined;
    const bytes_read = try file.readAll(&buf);
    try expect(bytes_written == bytes_read);
}
