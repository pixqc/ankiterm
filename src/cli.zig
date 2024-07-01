const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const assert = std.debug.assert;

// format and print an error message to stderr, then exit with an exit code of 1.
// https://github.com/tigerbeetle/tigerbeetle/blob/31130f3b924cad6787270e0fa0b5dcbea09baf66/src/flags.zig#L45
pub fn fatal(comptime fmt_string: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print("error: " ++ fmt_string ++ "\n", args) catch {};
    std.posix.exit(1);
}

pub const Command = union(enum) {
    pub const Init = struct {
        filename: []const u8,
    };
    pub const Review = struct {
        filename: []const u8,
    };
    init: Init,
    review: Review,
    version: void,
    help: void,

    pub const help =
        \\Usage: ankiterm <command> <filename>
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
};

/// https://github.com/tigerbeetle/tigerbeetle/blob/31130f3b924cad6787270e0fa0b5dcbea09baf66/src/flags.zig#L51
///
/// const CliArgs = union(enum) {
///    start: struct { addresses: []const u8, replica: u32 },
///    format: struct {
///        verbose: bool = false,
///        positional: struct {
///            path: []const u8,
///        }
///    },
///
///    pub const help =
///        \\ tigerbeetle start --addresses=<addresses> --replica=<replica>
///        \\ tigerbeetle format [--verbose] <path>
/// }
///
/// const cli_args = parse_commands(&args, CliArgs);

// parse cli arguments passed to ankiterm binary as structs or `union(enum)`
pub fn parse(args: *std.process.ArgIterator) !Command {
    assert(args.skip()); // skip the program name
    const subcmd = args.next() orelse fatal("subcommand required, expected init or review", .{});

    if (std.mem.eql(u8, subcmd, "-h") or std.mem.eql(u8, subcmd, "--help")) {
        std.io.getStdOut().writeAll(Command.help) catch std.posix.exit(1);
        std.posix.exit(0);
    }

    const filename = args.next() orelse fatal("filename required", .{});

    if (std.mem.eql(u8, subcmd, "init")) {
        return Command{ .init = .{ .filename = filename } };
    } else if (std.mem.eql(u8, subcmd, "review")) {
        return Command{ .review = .{ .filename = filename } };
    } else {
        fatal("unknown command: {s}", .{subcmd});
    }
}
