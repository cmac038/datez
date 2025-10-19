const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const print = std.debug.print;
const epoch = std.time.epoch;

pub const Date = struct {
    const Self = @This();

    year: epoch.Year,
    month_day: epoch.MonthAndDay,

    /// Output takes the format mm/dd/yyyy
    /// Custom format is used for print formatting
    pub fn format(this: Self, writer: *Writer) Writer.Error!void {
        try writer.print("{d:0>2}/{d:0>2}/{d}", .{
            this.month_day.month.numeric(),
            this.month_day.day_index,
            this.year,
        });
    }

    /// Recursively check Date fields for equality
    /// Currently just a wrapper for `std.meta.eql()`
    pub fn equals(this: Self, other: Date) bool {
        return std.meta.eql(this, other);
    }

    /// Increment by one day, handling month and year turnovers
    /// Also handles leap years
    /// Return true if incrementing results in a year turnover
    pub fn increment(this: *Self) void {
        // year turnaround
        if (this.month_day.month == .dec and this.month_day.day_index == 31) {
            this.year += 1;
            this.month_day.month = .jan;
            this.month_day.day_index = 1;
            return;
        }

        // month turnaround
        const days_in_month = epoch.getDaysInMonth(this.year, this.month_day.month);
        if (this.month_day.day_index == days_in_month) {
            const next_month: u4 = this.month_day.month.numeric() + 1;
            this.month_day.month = @enumFromInt(next_month);
            this.month_day.day_index = 1;
            return;
        }
        this.month_day.day_index += 1;
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
    var date_breakdown = try ArrayList(u16).initCapacity(allocator, 3);
    defer date_breakdown.deinit();
    var it = std.mem.tokenizeScalar(u8, input, '/');
    while (it.next()) |date_frag| {
        const parsed_date_frag: u16 = std.fmt.parseUnsigned(u16, date_frag, 10) catch |err| {
            return err;
        };
        try date_breakdown.append(parsed_date_frag);
    }
    if (date_breakdown.items.len != 3) {
        return error.InvalidDateFormat;
    }
    if (date_breakdown.items[0] > 12) {
        return error.MonthTooBig;
    }
    const year = date_breakdown.items[2];
    const month: epoch.Month = @enumFromInt(date_breakdown.items[0]);
    if (date_breakdown.items[1] > epoch.getDaysInMonth(year, month)) {
        return error.DayTooBig;
    }
    return .{
        .year = year,
        .month_day = .{
            .month = month,
            .day_index = @intCast(date_breakdown.items[1]),
        },
    };
}

//---------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------

// TESTING
// Date increment
test "Date increment day" {
    var date = Date{
        .year = 1950,
        .month_day = .{
            .month = .nov,
            .day_index = 9,
        },
    };
    date.increment();
    try std.testing.expect(date.year == 1950 and date.month_day.month == .nov and date.month_day.day_index == 10);
    print("[print_test] {f}\n", .{date});
}
test "Date increment 30 day month" {
    var date = Date{
        .year = 1950,
        .month_day = .{
            .month = .nov,
            .day_index = 30,
        },
    };
    date.increment();
    try std.testing.expect(date.year == 1950 and date.month_day.month == .dec and date.month_day.day_index == 1);
    print("[print_test] {f}\n", .{date});
}
test "Date increment 31 day month" {
    var date = Date{
        .year = 1950,
        .month_day = .{
            .month = .aug,
            .day_index = 31,
        },
    };
    date.increment();
    try std.testing.expect(date.year == 1950 and date.month_day.month == .sep and date.month_day.day_index == 1);
    print("[print_test] {f}\n", .{date});
}
test "Date increment February (not Leap Year)" {
    var date = Date{
        .year = 1950,
        .month_day = .{
            .month = .feb,
            .day_index = 28,
        },
    };
    date.increment();
    try std.testing.expect(date.year == 1950 and date.month_day.month == .mar and date.month_day.day_index == 1);
    print("[print_test] {f}\n", .{date});
}
test "Date increment February (Leap Year)" {
    var date = Date{
        .year = 2024,
        .month_day = .{
            .month = .feb,
            .day_index = 28,
        },
    };
    date.increment();
    try std.testing.expect(date.year == 2024 and date.month_day.month == .feb and date.month_day.day_index == 29);
    print("[print_test] {f}\n", .{date});
}
test "Date increment year" {
    var date = Date{
        .year = 1950,
        .month_day = .{
            .month = .dec,
            .day_index = 31,
        },
    };
    date.increment();
    try std.testing.expect(date.year == 1951 and date.month_day.month == .jan and date.month_day.day_index == 1);
    print("[print_test] {f}\n", .{date});
}

// Date equals
test "equals true" {
    const date = Date{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const date2 = Date{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    try std.testing.expect(date.equals(date2));
}
test "equals false (year)" {
    const date = Date{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const date2 = Date{ .year = 2024, .month_day = .{ .month = .jan, .day_index = 7 } };
    try std.testing.expect(!date.equals(date2));
}
test "equals false (month)" {
    const date = Date{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const date2 = Date{ .year = 2023, .month_day = .{ .month = .aug, .day_index = 7 } };
    try std.testing.expect(!date.equals(date2));
}
test "equals false (day)" {
    const date = Date{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const date2 = Date{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 31 } };
    try std.testing.expect(!date.equals(date2));
}

// parseDate
test "parseDate 1" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month_day = .{ .month = .oct, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "10/7/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 2" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month_day = .{ .month = .oct, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "10/07/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 3" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "1/7/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 4" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "1/07/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 5" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "01/07/2023");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 6 (Leap Year)" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2020, .month_day = .{ .month = .feb, .day_index = 29 } };
    const parsed_date = try parseDate(allocator, "02/29/2020");
    try std.testing.expectEqualDeep(date, parsed_date);
}
test "parseDate 7 (InvalidDateFormat error)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidDateFormat, parseDate(allocator, "01/17"));
}
test "parseDate 8 (InvalidDateFormat error)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidDateFormat, parseDate(allocator, "01/17"));
}
test "parseDate 9 (MonthTooBig error)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MonthTooBig, parseDate(allocator, "13/12/2025"));
}
test "parseDate 10 (DayTooBig error)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DayTooBig, parseDate(allocator, "04/31/2025"));
}
test "parseDate 11 (DayTooBig error)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DayTooBig, parseDate(allocator, "09/32/2025"));
}
test "parseDate 12 (Leap Year DayTooBig error)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DayTooBig, parseDate(allocator, "02/29/2025"));
}
