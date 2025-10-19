const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const print = std.debug.print;

pub const Date = struct {
    const Self = @This();

    year: u32,
    month: u8,
    day: u8,

    /// Output takes the format mm/dd/yyyy
    /// Custom format is used for print formatting
    pub fn format(this: @This(), writer: *Writer) Writer.Error!void {
        try writer.print("{[month]:0>2}/{[day]:0>2}/{[year]}", this);
    }

    /// Increment by one day, handling month and year turnovers
    /// Also handles leap years
    /// Return true if incrementing results in a year turnover
    pub fn increment(this: *Self) void {
        this.day += 1;
        // check for turnover
        switch (this.month) {
            // 31 day months
            1, 3, 5, 7, 8, 10 => {
                if (this.day > 31) {
                    this.month += 1;
                    this.day = 1;
                }
            },
            // 30 day months
            4, 6, 9, 11 => {
                if (this.day > 30) {
                    this.month += 1;
                    this.day = 1;
                }
            },
            // February
            2 => {
                if (this.day == 29 and this.isLeapYear()) return;
                if (this.day > 28) {
                    this.month += 1;
                    this.day = 1;
                }
            },
            // December (year turnover)
            12 => {
                if (this.day > 31) {
                    this.year += 1;
                    this.month = 1;
                    this.day = 1;
                }
            },
            else => unreachable,
        }
    }

    /// Leap year rules:
    ///     divisible by 4 == true
    ///     divisible by 100 == false EXCEPT when divisible by 400
    pub fn isLeapYear(self: Self) bool {
        return self.year % 4 == 0 and (self.year % 100 != 0 or self.year % 400 == 0);
    }
};

/// Takes a date input in the form "mm/dd/yyyy" and returns a Date object
/// "mm/dd/yyyy" format is not strict i.e.
///     mm/dd/yy is valid; yy = 96 will be treated as year 96, not 1996
///     m/d/y is valid
///     mm/d/yyyy is valid
///     mmmmm/dddddd/yyyyyy is valid but ontologically incorrect
///     Any length for any part of the date is valid - it is the order that matters
pub fn parseDate(allocator: Allocator, input: []const u8) !Date {
    var date_breakdown = try ArrayList(u32).initCapacity(allocator, 3);
    defer date_breakdown.deinit();
    var it = std.mem.tokenizeScalar(u8, input, '/');
    while (it.next()) |date_frag| {
        const parsed_date_frag: u32 = std.fmt.parseUnsigned(u32, date_frag, 10) catch |err| {
            return err;
        };
        try date_breakdown.append(parsed_date_frag);
    }
    if (date_breakdown.items.len != 3) {
        return error.InvalidDateFormat;
    }
    return .{
        .month = @as(u8, @intCast(date_breakdown.items[0])),
        .day = @as(u8, @intCast(date_breakdown.items[1])),
        .year = date_breakdown.items[2],
    };
}

//---------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------

// TESTING
// Date isLeapYear
test "Date isLeapYear divisible by 4 (true)" {
    const date = Date{ .year = 2024, .month = 8, .day = 5 };
    try std.testing.expect(date.isLeapYear());
}
test "Date isLeapYear divisible by 400 (true)" {
    const date = Date{ .year = 2000, .month = 8, .day = 5 };
    try std.testing.expect(date.isLeapYear());
}
test "Date isLeapYear divisible by 100 (false)" {
    const date = Date{ .year = 2100, .month = 8, .day = 5 };
    try std.testing.expect(!date.isLeapYear());
}
test "Date isLeapYear (false)" {
    const date = Date{ .year = 2022, .month = 8, .day = 5 };
    try std.testing.expect(!date.isLeapYear());
}
test "Date isLeapYear (true)" {
    const date = Date{ .year = 1996, .month = 8, .day = 5 };
    try std.testing.expect(date.isLeapYear());
}

// Date increment
test "Date increment day" {
    var date = Date{
        .year = 1950,
        .month = 11,
        .day = 9,
    };
    date.increment();
    try std.testing.expect(date.year == 1950 and date.month == 11 and date.day == 10);
}
test "Date increment 30 day month" {
    var date = Date{
        .year = 1950,
        .month = 11,
        .day = 30,
    };
    date.increment();
    try std.testing.expect(date.year == 1950 and date.month == 12 and date.day == 1);
}
test "Date increment 31 day month" {
    var date = Date{
        .year = 1950,
        .month = 8,
        .day = 31,
    };
    date.increment();
    try std.testing.expect(date.year == 1950 and date.month == 9 and date.day == 1);
}
test "Date increment February (not Leap Year)" {
    var date = Date{
        .year = 1950,
        .month = 2,
        .day = 28,
    };
    date.increment();
    try std.testing.expect(date.year == 1950 and date.month == 3 and date.day == 1);
}
test "Date increment February (Leap Year)" {
    var date = Date{
        .year = 2024,
        .month = 2,
        .day = 28,
    };
    date.increment();
    try std.testing.expect(date.year == 2024 and date.month == 2 and date.day == 29);
}
test "Date increment year" {
    var date = Date{
        .year = 1950,
        .month = 12,
        .day = 31,
    };
    date.increment();
    try std.testing.expect(date.year == 1951 and date.month == 1 and date.day == 1);
}

// parseDate
test "parseDate 1" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month = 10, .day = 7 };
    const parsed_date = try parseDate(allocator, "10/7/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 2" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month = 10, .day = 7 };
    const parsed_date = try parseDate(allocator, "10/07/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 3" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month = 1, .day = 7 };
    const parsed_date = try parseDate(allocator, "1/7/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 4" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month = 1, .day = 7 };
    const parsed_date = try parseDate(allocator, "1/07/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 5" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month = 1, .day = 7 };
    const parsed_date = try parseDate(allocator, "01/07/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 6" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidDateFormat, parseDate(allocator, "01/17"));
}
