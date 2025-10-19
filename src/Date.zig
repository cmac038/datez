const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const print = std.debug.print;
const epoch = std.time.epoch;

const U16_MAX_VALUE: u128 = 65536;
const MAX_LITE_DATE: LiteDate = .{
    .year = U16_MAX_VALUE - 1,
    .month_day = .{
        .month = .dec,
        .day_index = 31,
    },
};

/// Lightweight Date, max year = 66535
pub const LiteDate = struct {
    const Self = @This();

    year: epoch.Year,
    month_day: epoch.MonthAndDay,

    /// Output takes the format mm/dd/yyyy
    pub fn format(this: Self, writer: *Writer) Writer.Error!void {
        try writer.print("{d:0>2}/{d:0>2}/{d}", .{
            this.month_day.month.numeric(),
            this.month_day.day_index,
            this.year,
        });
    }

    /// Increment by one day, handling month and year turnovers
    /// Also handles leap years
    pub fn increment(this: *Self) !void {
        if (std.meta.eql(this.*, MAX_LITE_DATE)) {
            return error.LiteDateOverflow;
        }
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

/// Heavier Date with year rollover, max year = ???
pub const BigDate = struct {
    const Self = @This();

    lite_date: LiteDate,
    year_rollover: u64,

    /// Output takes the format mm/dd/yyyy
    pub fn format(this: Self, writer: *Writer) Writer.Error!void {
        try writer.print("{d:0>2}/{d:0>2}/{d}", .{
            this.lite_date.month_day.month.numeric(),
            this.lite_date.month_day.day_index,
            this.lite_date.year + (this.year_rollover * U16_MAX_VALUE),
        });
    }

    /// Increment by one day, handling month and year turnovers
    /// Also handles leap years
    /// Should never fail
    pub fn increment(this: *Self) void {
        if (std.meta.eql(this.lite_date, MAX_LITE_DATE)) {
            this.lite_date.year = 0;
            this.lite_date.month_day.month = .jan;
            this.lite_date.month_day.day_index = 1;
            this.year_rollover += 1;
            return;
        }
        this.lite_date.increment() catch unreachable;
    }
};

/// Date union to allow agnostic operations
/// Can be used directly, or extract the inner object for less memory usage.
pub const Date = union(enum) {
    const Self = @This();

    lite_date: LiteDate,
    big_date: BigDate,

    /// Output takes the format mm/dd/yyyy
    pub fn format(this: Self, writer: *Writer) Writer.Error!void {
        switch (this) {
            .lite_date => |date| try writer.print("{f}", .{date}),
            .big_date => |date| try writer.print("{f}", .{date}),
        }
    }

    /// Increment by one day, handling month and year turnovers
    /// Also handles leap years
    pub fn increment(this: *Self) void {
        ds: switch (this.*) {
            .lite_date => |*date| {
                date.increment() catch {
                    this.* = Date{
                        .big_date = .{
                            .year_rollover = 0,
                            .lite_date = date.*,
                        },
                    };
                    continue :ds this.*;
                };
            },
            .big_date => |*date| date.increment(),
        }
    }

    /// Read out contents of Date object for debugging
    fn dump(this: Self) void {
        switch (this) {
            .lite_date => |date| {
                print(
                    \\[LiteDate dump]
                    \\  full: {f}
                    \\  year: {d}
                    \\  month: {d}
                    \\  day: {d}
                    \\
                , .{
                    this,
                    date.year,
                    date.month_day.month,
                    date.month_day.day_index,
                });
            },
            .big_date => |date| {
                print(
                    \\[BigDate dump]
                    \\  full: {f}
                    \\  rollover: {d}
                    \\  year: {d}
                    \\  month: {d}
                    \\  day: {d}
                    \\
                , .{
                    this,
                    date.year_rollover,
                    date.lite_date.year,
                    date.lite_date.month_day.month,
                    date.lite_date.month_day.day_index,
                });
            },
        }
    }
};

/// Takes a date input in the form "mm/dd/yyyy" and returns a Date union.
/// If year > 65535, a BigDate will be used.
/// Otherwise, a LiteDate will be used.
/// "mm/dd/yyyy" format is not strict i.e.
///     mm/dd/yy is valid; yy = 96 will be treated as year 96, not 1996
///     m/d/y is valid
///     mm/d/yyyy is valid
///     mmmmm/dddddd/yyyyyy is valid but ontologically incorrect
///     Any length for any part of the date is valid - it is the order that matters
pub fn parseDate(allocator: Allocator, input: []const u8) !Date {
    var date_breakdown = try ArrayList(u64).initCapacity(allocator, 3);
    defer date_breakdown.deinit();
    var it = std.mem.tokenizeScalar(u8, input, '/');
    while (it.next()) |date_frag| {
        const parsed_date_frag: u64 = try std.fmt.parseUnsigned(u64, date_frag, 10);
        try date_breakdown.append(parsed_date_frag);
    }
    if (date_breakdown.items.len != 3) {
        return error.InvalidDateFormat;
    }
    if (date_breakdown.items[0] > 12) {
        return error.MonthTooBig;
    }
    const true_year = date_breakdown.items[2];
    const month: epoch.Month = @enumFromInt(date_breakdown.items[0]);
    const lite_year: u16 =
        if (true_year < U16_MAX_VALUE)
            @intCast(true_year)
        else
            @intCast(true_year % U16_MAX_VALUE);

    if (date_breakdown.items[1] > epoch.getDaysInMonth(lite_year, month)) {
        return error.DayTooBig;
    }
    const lite_date: LiteDate = .{
        .year = lite_year,
        .month_day = .{ .month = month, .day_index = @intCast(date_breakdown.items[1]) },
    };
    const rollover = true_year / U16_MAX_VALUE;
    if (true_year >= U16_MAX_VALUE) {
        return Date{ .big_date = .{
            .year_rollover = @intCast(rollover),
            .lite_date = lite_date,
        } };
    }
    return Date{ .lite_date = lite_date };
}

//---------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------

// TESTING
// Date increment
test "Date increment day" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .nov,
            .day_index = 9,
        },
    };
    try lite_date.increment();
    try std.testing.expect(lite_date.year == 1950 and lite_date.month_day.month == .nov and lite_date.month_day.day_index == 10);
    var date: Date = .{ .lite_date = lite_date };
    print("[print_test] {f}\n", .{date});
    date.increment();
    print("[print_test] {f}\n", .{date});
}
test "Date increment 30 day month" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .nov,
            .day_index = 30,
        },
    };
    try lite_date.increment();
    try std.testing.expect(lite_date.year == 1950 and lite_date.month_day.month == .dec and lite_date.month_day.day_index == 1);
    print("[print_test] {f}\n", .{Date{ .lite_date = lite_date }});
}
test "Date increment 31 day month" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .aug,
            .day_index = 31,
        },
    };
    try lite_date.increment();
    try std.testing.expect(lite_date.year == 1950 and lite_date.month_day.month == .sep and lite_date.month_day.day_index == 1);
    print("[print_test] {f}\n", .{Date{ .lite_date = lite_date }});
}
test "Date increment February (not Leap Year)" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .feb,
            .day_index = 28,
        },
    };
    try lite_date.increment();
    try std.testing.expect(lite_date.year == 1950 and lite_date.month_day.month == .mar and lite_date.month_day.day_index == 1);
    print("[print_test] {f}\n", .{Date{ .lite_date = lite_date }});
}
test "Date increment February (Leap Year)" {
    var lite_date = LiteDate{
        .year = 2024,
        .month_day = .{
            .month = .feb,
            .day_index = 28,
        },
    };
    try lite_date.increment();
    try std.testing.expect(lite_date.year == 2024 and lite_date.month_day.month == .feb and lite_date.month_day.day_index == 29);
    print("[print_test] {f}\n", .{Date{ .lite_date = lite_date }});
}
test "Date increment year" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .dec,
            .day_index = 31,
        },
    };
    try lite_date.increment();
    try std.testing.expect(lite_date.year == 1951 and lite_date.month_day.month == .jan and lite_date.month_day.day_index == 1);
    const date: Date = .{
        .lite_date = lite_date,
    };
    print("[print_test] {f}\n", .{date});
    date.dump();
}

// Date equals
test "equals true" {
    const date = Date{ .lite_date = .{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } } };
    const date2 = Date{ .lite_date = .{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } } };
    try std.testing.expect(std.meta.eql(date, date2));
}
test "equals false (year)" {
    const date = Date{ .lite_date = .{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } } };
    const date2 = Date{ .lite_date = .{ .year = 2024, .month_day = .{ .month = .jan, .day_index = 7 } } };
    try std.testing.expect(!std.meta.eql(date, date2));
}
test "equals false (month)" {
    const date = Date{ .lite_date = .{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } } };
    const date2 = Date{ .lite_date = .{ .year = 2023, .month_day = .{ .month = .aug, .day_index = 7 } } };
    try std.testing.expect(!std.meta.eql(date, date2));
}
test "equals false (day)" {
    const date = Date{ .lite_date = .{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } } };
    const date2 = Date{ .lite_date = .{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 31 } } };
    try std.testing.expect(!std.meta.eql(date, date2));
}

// parseDate
test "parseDate 1" {
    const allocator = std.testing.allocator;
    const date = LiteDate{ .year = 2023, .month_day = .{ .month = .oct, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "10/7/2023");
    try std.testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 2" {
    const allocator = std.testing.allocator;
    const date = LiteDate{ .year = 2023, .month_day = .{ .month = .oct, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "10/07/2023");
    try std.testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 3" {
    const allocator = std.testing.allocator;
    const date = LiteDate{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "1/7/2023");
    try std.testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 4" {
    const allocator = std.testing.allocator;
    const date = LiteDate{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "1/07/2023");
    try std.testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 5" {
    const allocator = std.testing.allocator;
    const date = LiteDate{ .year = 2023, .month_day = .{ .month = .jan, .day_index = 7 } };
    const parsed_date = try parseDate(allocator, "01/07/2023");
    try std.testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 6 (Leap Year)" {
    const allocator = std.testing.allocator;
    const date = LiteDate{ .year = 2020, .month_day = .{ .month = .feb, .day_index = 29 } };
    const parsed_date = try parseDate(allocator, "02/29/2020");
    try std.testing.expectEqualDeep(date, parsed_date.lite_date);
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

// Date rollover
test "Date rollover 1" {
    const allocator = std.testing.allocator;
    const parsed_date = try parseDate(allocator, "10/7/9294967296");
    const normal_date: LiteDate = .{
        .year = 61952,
        .month_day = .{
            .month = .oct,
            .day_index = 7,
        },
    };
    const date_with_rollover: BigDate = .{
        .year_rollover = 141829,
        .lite_date = normal_date,
    };
    try std.testing.expectEqualDeep(normal_date, parsed_date.big_date.lite_date);
    try std.testing.expectEqualDeep(date_with_rollover, parsed_date.big_date);
    parsed_date.dump();
}
test "Date rollover 2" {
    const allocator = std.testing.allocator;
    var parsed_date = try parseDate(allocator, "12/31/131071");
    parsed_date.dump();
    parsed_date.increment();
    parsed_date.dump();
}
test "Date rollover 3" {
    const allocator = std.testing.allocator;
    var parsed_date = try parseDate(allocator, "12/31/65535");
    parsed_date.dump();
    parsed_date.increment();
    parsed_date.dump();
}
