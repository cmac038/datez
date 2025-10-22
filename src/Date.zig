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

/// Date comparison stored as a 2-bit signed int.
/// -1 = before, 0 = equal, 1 = after
pub const DateComparison = enum(i2) { before = -1, equal = 0, after = 1 };

/// Date union, either LiteDate (year < 65536) or BigDate for bigger years.
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

    /// Compare two Date unions, accounting for all possible values.
    /// Returns DateComparison enum(i2):
    ///   DateComparison.before = -1
    ///   DateComparison.equal = 0
    ///   DateComparison.after = 1
    pub fn compare(this: Self, other: Self) DateComparison {
        switch (this) {
            .lite_date => |this_lite_date| {
                switch (other) {
                    .lite_date => |other_lite_date| {
                        return this_lite_date.compare(other_lite_date);
                    },
                    .big_date => |other_big_date| {
                        if (other_big_date.year_rollover != 0) return .before;
                        return this_lite_date.compare(other_big_date.lite_date);
                    },
                }
            },
            .big_date => |this_big_date| {
                switch (other) {
                    .lite_date => |other_lite_date| {
                        if (this_big_date.year_rollover != 0) return .after;
                        return this_big_date.lite_date.compare(other_lite_date);
                    },
                    .big_date => |other_big_date| {
                        return this_big_date.compare(other_big_date);
                    },
                }
            },
        }
    }

    /// Create a date from int values
    /// Returns LiteDate if year < 65535, BigDate otherwise
    /// Returns errors if month or day is too big
    pub fn fromInts(year: u128, month: u4, day: u5) !Date {
        if (month > 12) {
            return error.MonthTooBig;
        }
        const lite_year: u16 =
            if (year < U16_MAX_VALUE)
                @intCast(year)
            else
                @intCast(year % U16_MAX_VALUE);
        if (day > epoch.getDaysInMonth(lite_year, @enumFromInt(month))) {
            return error.DayTooBig;
        }
        const lite_date: LiteDate = .{
            .year = lite_year,
            .month_day = .{ .month = @enumFromInt(month), .day_index = @intCast(day) },
        };
        if (year < U16_MAX_VALUE) {
            return .{ .lite_date = lite_date };
        }
        return .{ .big_date = .{
            .year_rollover = @intCast(year / U16_MAX_VALUE),
            .lite_date = lite_date,
        } };
    }

    /// Get today's date; will always be a LiteDate
    /// Will need to be updated to also use BigDate in 65535 AD
    pub fn today() Date {
        const epoch_seconds: epoch.EpochSeconds = .{
            .secs = @abs(std.time.timestamp()),
        };
        const year_day = epoch_seconds.getEpochDay().calculateYearDay();
        var today_date: Date = .{ .lite_date = .{
            .year = year_day.year,
            .month_day = year_day.calculateMonthDay(),
        } };
        today_date.increment(); // off by one for some reason???
        return today_date;
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

    /// Compare two LiteDate structs
    /// Returns DateComparison enum(i2):
    ///   DateComparison.before = -1
    ///   DateComparison.equal = 0
    ///   DateComparison.after = 1
    pub fn compare(this: Self, other: Self) DateComparison {
        if (this.year < other.year) return .before;
        if (this.year > other.year) return .after;
        // Reach here -> years are equal
        const this_month = @intFromEnum(this.month_day.month);
        const other_month = @intFromEnum(other.month_day.month);
        if (this_month < other_month) return .before;
        if (this_month > other_month) return .after;
        // Reach here -> months are equal
        if (this.month_day.day_index < other.month_day.day_index) return .before;
        if (this.month_day.day_index > other.month_day.day_index) return .after;
        // Reach here -> days are equal
        return .equal;
    }
};

/// Heavier Date with year rollover, max year = ???
pub const BigDate = struct {
    const Self = @This();

    lite_date: LiteDate,
    year_rollover: u32,

    /// Output takes the format mm/dd/yyyy
    pub fn format(this: Self, writer: *Writer) Writer.Error!void {
        try writer.print("{d:0>2}/{d:0>2}/{d}", .{
            this.lite_date.month_day.month.numeric(),
            this.lite_date.month_day.day_index,
            this.getTrueYear(),
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

    /// Compare two BigDate structs
    /// Returns DateComparison enum(i2):
    ///   DateComparison.before = -1
    ///   DateComparison.equal = 0
    ///   DateComparison.after = 1
    pub fn compare(this: Self, other: Self) DateComparison {
        if (this.year_rollover < other.year_rollover) return .before;
        if (this.year_rollover > other.year_rollover) return .after;
        // Reach here -> year rollovers are equal, just compare lite dates
        return this.lite_date.compare(other.lite_date);
    }

    /// Combine rollover and inner LiteDate year to get the true year value
    pub fn getTrueYear(this: Self) u128 {
        return this.lite_date.year + (this.year_rollover * U16_MAX_VALUE);
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
    var date_breakdown = try ArrayList(u128).initCapacity(allocator, 3);
    defer date_breakdown.deinit();
    var it = std.mem.tokenizeScalar(u8, input, '/');
    while (it.next()) |date_frag| {
        const parsed_date_frag: u128 = try std.fmt.parseUnsigned(u128, date_frag, 10);
        try date_breakdown.append(parsed_date_frag);
    }
    if (date_breakdown.items.len != 3) {
        return error.InvalidDateFormat;
    }
    if (date_breakdown.items[0] > 12) {
        return error.MonthTooBig;
    }
    if (date_breakdown.items[1] > 31) {
        return error.DayTooBig;
    }
    const day: u5 = @intCast(date_breakdown.items[1]);
    const month: u4 = @intCast(date_breakdown.items[0]);
    return try Date.fromInts(date_breakdown.items[2], month, day);
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

// Date today
test "Date today" {
    print("[today_test] {f}\n",.{Date.today()});
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

// BigDate getTrueYear
test "BigDate getTrueYear 1" {
    const allocator = std.testing.allocator;
    const parsed_date = try parseDate(allocator, "10/7/9294967296");
    try std.testing.expectEqual(9294967296, parsed_date.big_date.getTrueYear());
}
test "BigDate getTrueYear 2" {
    const allocator = std.testing.allocator;
    var parsed_date = try parseDate(allocator, "12/31/131071");
    try std.testing.expectEqual(131071, parsed_date.big_date.getTrueYear());
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
    print("\nDate rollover 1\n", .{});
    parsed_date.dump();
}
test "Date rollover 2" {
    const allocator = std.testing.allocator;
    var parsed_date = try parseDate(allocator, "12/31/131071");
    print("Date rollover 2: pre-increment\n", .{});
    parsed_date.dump();
    parsed_date.increment();
    print("Date rollover 2: post-increment\n", .{});
    parsed_date.dump();
}
test "Date rollover 3" {
    const allocator = std.testing.allocator;
    var parsed_date = try parseDate(allocator, "12/31/65535");
    print("Date rollover 3: pre-increment\n", .{});
    parsed_date.dump();
    parsed_date.increment();
    print("Date rollover 3: post-increment\n", .{});
    parsed_date.dump();
}

// Date fromInts
test "Date fromInts: LiteDate" {
    const a = try Date.fromInts(2024, 5, 21);
    try std.testing.expect(a.lite_date.year == 2024 and
        a.lite_date.month_day.month == epoch.Month.may and
        a.lite_date.month_day.day_index == 21);
}
test "Date fromInts: BigDate" {
    const a = try Date.fromInts(65536, 5, 21);
    try std.testing.expect(a.big_date.year_rollover == 1 and
        a.big_date.lite_date.year == 0 and
        a.big_date.lite_date.month_day.month == epoch.Month.may and
        a.big_date.lite_date.month_day.day_index == 21);
}

// Date compare
test "LiteDate compare: before 1" {
    const a = try Date.fromInts(2024, 5, 21);
    const b = try Date.fromInts(2025, 7, 12);
    try std.testing.expect(a.compare(b) == .before);
}
test "LiteDate compare: before 2" {
    const a = try Date.fromInts(2025, 5, 21);
    const b = try Date.fromInts(2025, 7, 12);
    try std.testing.expect(a.compare(b) == .before);
}
test "LiteDate compare: before 3" {
    const a = try Date.fromInts(2025, 5, 12);
    const b = try Date.fromInts(2025, 5, 21);
    try std.testing.expect(a.compare(b) == .before);
}
test "LiteDate compare: after 1" {
    const a = try Date.fromInts(1961, 2, 14);
    const b = try Date.fromInts(1960, 11, 25);
    try std.testing.expect(a.compare(b) == .after);
}
test "LiteDate compare: after 2" {
    const a = try Date.fromInts(1961, 11, 25);
    const b = try Date.fromInts(1961, 2, 14);
    try std.testing.expect(a.compare(b) == .after);
}
test "LiteDate compare: after 3" {
    const a = try Date.fromInts(1961, 11, 16);
    const b = try Date.fromInts(1961, 11, 14);
    try std.testing.expect(a.compare(b) == .after);
}
test "LiteDate compare: equal" {
    const a = try Date.fromInts(1961, 11, 14);
    const b = try Date.fromInts(1961, 11, 14);
    try std.testing.expect(a.compare(b) == .equal);
}
test "BigDate compare: before 1" {
    const a = try Date.fromInts(65536, 5, 21);
    const b = try Date.fromInts(65537, 7, 12);
    try std.testing.expect(a.compare(b) == .before);
}
test "BigDate compare: before 2" {
    const a = try Date.fromInts(65536, 5, 21);
    const b = try Date.fromInts(65536, 7, 12);
    try std.testing.expect(a.compare(b) == .before);
}
test "BigDate compare: before 3" {
    const a = try Date.fromInts(65536, 5, 12);
    const b = try Date.fromInts(65536, 5, 21);
    try std.testing.expect(a.compare(b) == .before);
}
test "BigDate compare: after 1" {
    const a = try Date.fromInts(123456792, 2, 14);
    const b = try Date.fromInts(123456789, 11, 25);
    try std.testing.expect(a.compare(b) == .after);
}
test "BigDate compare: after 2" {
    const a = try Date.fromInts(123456789, 11, 25);
    const b = try Date.fromInts(123456789, 2, 14);
    try std.testing.expect(a.compare(b) == .after);
}
test "BigDate compare: after 3" {
    const a = try Date.fromInts(123456789, 11, 16);
    const b = try Date.fromInts(123456789, 11, 14);
    try std.testing.expect(a.compare(b) == .after);
}
test "BigDate compare: equal" {
    const a = try Date.fromInts(1235813213456, 11, 14);
    const b = try Date.fromInts(1235813213456, 11, 14);
    try std.testing.expect(a.compare(b) == .equal);
}
test "LiteDate/BigDate compare: before" {
    const a = try Date.fromInts(2025, 5, 21);
    const b = try Date.fromInts(65537, 7, 12);
    try std.testing.expect(a.compare(b) == .before);
}
test "LiteDate/BigDate compare: after" {
    const a = try Date.fromInts(123456792, 2, 14);
    const b = try Date.fromInts(2025, 11, 25);
    try std.testing.expect(a.compare(b) == .after);
}
test "LiteDate/BigDate compare: equal" {
    const a = try Date.fromInts(65535, 11, 14);
    var b = try Date.fromInts(65536, 11, 14);
    b.big_date.year_rollover = 0;
    b.big_date.lite_date.year = 65535;
    a.dump();
    b.dump();
    try std.testing.expect(a.compare(b) == .equal);
}

test "sizeof" {
    print("size of Date: {d} bytes == {d} bits\n", .{@sizeOf(Date), @bitSizeOf(Date)});
    print("size of LiteDate: {d} bytes == {d} bits\n", .{@sizeOf(LiteDate), @bitSizeOf(LiteDate)});
    print("size of BigDate: {d} bytes == {d} bits\n", .{@sizeOf(BigDate), @bitSizeOf(BigDate)});
}
