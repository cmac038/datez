//! TODO: doc-level comments

/// Date union, either LiteDate or BigDate.
///
/// LiteDate is used for years 0 - 65,535.
/// BigDate is used for years 65,536 - 4,294,967,295.
///
/// Can be used directly, or extract the inner object for less memory usage.
///
/// Size: 8 bytes
pub const Date = union(enum) {
    const Self = @This();

    lite_date: LiteDate,
    big_date: BigDate,

    /// Output takes the format mm/dd/yyyy.
    pub fn format(this: Self, writer: *Writer) Writer.Error!void {
        switch (this) {
            .lite_date => |lite_date| try writer.print("{f}", .{lite_date}),
            .big_date => |big_date| try writer.print("{f}", .{big_date}),
        }
    }

    /// Get year without needing to know if Date is Lite or Big.
    pub fn getYear(this: Self) u32 {
        switch (this) {
            .lite_date => |lite_date| return lite_date.year,
            .big_date => |big_date| return big_date.getTrueYear(),
        }
    }

    /// Get month without needing to know if Date is Lite or Big.
    pub fn getMonth(this: Self) u4 {
        month: switch (this) {
            .lite_date => |lite_date| return lite_date.month_day.month.numeric(),
            .big_date => |big_date| continue :month Date{ .lite_date = big_date.lite_date },
        }
    }

    /// Get day without needing to know if Date is Lite or Big.
    pub fn getDay(this: Self) u5 {
        day: switch (this) {
            .lite_date => |lite_date| return lite_date.month_day.day_index,
            .big_date => |big_date| continue :day Date{ .lite_date = big_date.lite_date },
        }
    }

    /// Increment by one day, handling month and year turnovers (handles leap years).
    ///
    /// Converts LiteDate to BigDate if current date is the max LiteDate.
    /// Fails before allowing year to go beyond 4,294,967,295
    pub fn increment(this: *Self) OverflowError!void {
        inc: switch (this.*) {
            .lite_date => |*lite_date| {
                lite_date.increment() catch {
                    this.* = Date{
                        .big_date = .{
                            .year_rollover = 0,
                            .lite_date = lite_date.*,
                        },
                    };
                    continue :inc this.*;
                };
            },
            .big_date => |*big_date| try big_date.increment(),
        }
    }

    /// Util for incrementing more than once.
    /// Fails before allowing year to go beyond 4,294,967,295
    pub fn incrementNTimes(this: *Self, n: usize) OverflowError!void {
        for (0..n) |_| try this.increment();
    }

    /// Decrement by one day, handling month and year turnovers (handles leap years).
    ///
    /// Converts BigDate to LiteDate if current date is the min BigDate.
    /// Fails before allowing year to go negative.
    pub fn decrement(this: *Self) UnderflowError!void {
        switch (this.*) {
            .lite_date => |*lite_date| try lite_date.decrement(),
            .big_date => |*big_date| {
                try big_date.decrement();
                if (big_date.compare(MIN_BIG_DATE) == .equal) {
                    this.* = Date{ .lite_date = big_date.lite_date };
                }
            },
        }
    }

    /// Util for decrementing more than once.
    /// Fails before allowing year to go negative.
    pub fn decrementNTimes(this: *Self, n: usize) UnderflowError!void {
        for (0..n) |_| try this.decrement();
    }

    /// Compare two Date unions, accounting for all possible values.
    ///
    /// Returns DateComparison enum(i2):
    /// * DateComparison.before = -1
    /// * DateComparison.equal = 0
    /// * DateComparison.after = 1
    pub fn compare(this: Self, other: Self) DateComparison {
        switch (this) {
            .lite_date => |lite_date| {
                switch (other) {
                    .lite_date => |other_lite_date| {
                        return lite_date.compare(other_lite_date);
                    },
                    .big_date => |other_big_date| {
                        if (other_big_date.year_rollover != 0) return .before;
                        return lite_date.compare(other_big_date.lite_date);
                    },
                }
            },
            .big_date => |big_date| {
                switch (other) {
                    .lite_date => |other_lite_date| {
                        if (big_date.year_rollover != 0) return .after;
                        return big_date.lite_date.compare(other_lite_date);
                    },
                    .big_date => |other_big_date| {
                        return big_date.compare(other_big_date);
                    },
                }
            },
        }
    }

    /// Create a date from int values.
    /// * Returns LiteDate if year < 65,535
    /// * Returns BigDate if year > 65,535 and year < 4,294,967,295
    /// * Returns errors if month, day, or year is too big
    pub fn fromInts(year: u32, month: u4, day: u5) InputError!Date {
        if (month > 12) {
            return InputError.MonthTooBig;
        }
        const lite_year: u16 =
            if (year < U16_MAX_VALUE)
                @intCast(year)
            else
                @intCast(year % U16_MAX_VALUE);
        if (day > epoch.getDaysInMonth(lite_year, @enumFromInt(month))) {
            return InputError.DayTooBig;
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

    /// Get today's date; will always be a LiteDate.
    /// Will need to be updated to also use BigDate in 65,535 AD.
    pub fn today() Date {
        const now: epoch.EpochSeconds = .{
            .secs = @abs(std.time.timestamp()),
        };
        const today_year_day = now.getEpochDay().calculateYearDay();
        var today_date: Date = .{ .lite_date = .{
            .year = today_year_day.year,
            .month_day = today_year_day.calculateMonthDay(),
        } };
        today_date.increment() catch unreachable; // off by one for some reason???
        return today_date;
    }

    /// Read out contents of Date object for debugging.
    fn dump(this: Self) void {
        switch (this) {
            .lite_date => print("[LiteDate dump]\n", .{}),
            .big_date => |big_date| print("[BigDate dump]\n  rollover: {d}\n", .{big_date.year_rollover}),
        }
        print(
            \\  full: {f}
            \\  year: {d}
            \\  month: {d}
            \\  day: {d}
            \\
            \\
        , .{
            this,
            this.getYear(),
            this.getMonth(),
            this.getDay(),
        });
    }
};

/// Lightweight Date, max year = 66,535. 
/// Use this for most normal date-related logic.
///
/// Size: 4 bytes
pub const LiteDate = struct {
    const Self = @This();

    year: epoch.Year,
    month_day: epoch.MonthAndDay,

    /// Output takes the format mm/dd/yyyy.
    pub fn format(this: Self, writer: *Writer) Writer.Error!void {
        try writer.print("{d:0>2}/{d:0>2}/{d}", .{
            this.month_day.month.numeric(),
            this.month_day.day_index,
            this.year,
        });
    }

    /// Increment by one day, handling month and year turnovers (handles leap years).
    /// Fails before allowing year to go beyond 65,535.
    pub fn increment(this: *Self) OverflowError!void {
        if (this.compare(MAX_LITE_DATE) == .equal) {
            return OverflowError.LiteDateOverflow;
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
            this.month_day.month = @enumFromInt(this.month_day.month.numeric() + 1);
            this.month_day.day_index = 1;
            return;
        }
        this.month_day.day_index += 1;
    }

    /// Util for incrementing more than once.
    /// Fails before allowing year to go beyond 65,535.
    pub fn incrementNTimes(this: *Self, n: usize) OverflowError!void {
        for (0..n) |_| try this.increment();
    }

    /// Decrement by one day, handling month and year turnovers (handles leap years).
    /// Fails before allowing year to go negative.
    pub fn decrement(this: *Self) UnderflowError!void {
        if (this.compare(MIN_LITE_DATE) == .equal) {
            return UnderflowError.DateUnderflow;
        }
        // year turnaround
        if (this.month_day.month == .jan and this.month_day.day_index == 1) {
            this.year -= 1;
            this.month_day.month = .dec;
            this.month_day.day_index = 31;
            return;
        }
        // month turnaround
        if (this.month_day.day_index == 1) {
            const last_month: epoch.Month = @enumFromInt(this.month_day.month.numeric() - 1);
            this.month_day.month = last_month;
            this.month_day.day_index = epoch.getDaysInMonth(this.year, last_month);
            return;
        }
        this.month_day.day_index -= 1;
    }

    /// Util for decrementing more than once.
    /// Fails before allowing year to go negative.
    pub fn decrementNTimes(this: *Self, n: usize) UnderflowError!void {
        for (0..n) |_| try this.decrement();
    }

    /// Compare two LiteDate structs.
    ///
    /// Returns DateComparison enum(i2):
    /// * DateComparison.before = -1
    /// * DateComparison.equal = 0
    /// * DateComparison.after = 1
    pub fn compare(this: Self, other: Self) DateComparison {
        if (this.year < other.year) return .before;
        if (this.year > other.year) return .after;
        // Reach here -> years are equal
        const this_month = this.month_day.month.numeric();
        const other_month = other.month_day.month.numeric();
        if (this_month < other_month) return .before;
        if (this_month > other_month) return .after;
        // Reach here -> months are equal
        if (this.month_day.day_index < other.month_day.day_index) return .before;
        if (this.month_day.day_index > other.month_day.day_index) return .after;
        // Reach here -> days are equal
        return .equal;
    }
};

/// Heavier Date with year rollover, max year = 4,294,967,295.
///
/// Size: 6 bytes
pub const BigDate = struct {
    const Self = @This();

    lite_date: LiteDate,
    year_rollover: u16,

    /// Output takes the format mm/dd/yyyy.
    pub fn format(this: Self, writer: *Writer) Writer.Error!void {
        try writer.print("{d:0>2}/{d:0>2}/{d}", .{
            this.lite_date.month_day.month.numeric(),
            this.lite_date.month_day.day_index,
            this.getTrueYear(),
        });
    }

    /// Increment by one day, handling month and year turnovers (handles leap years).
    /// Fails before allowing year to go beyond 4,294,967,295.
    pub fn increment(this: *Self) OverflowError!void {
        if (this.compare(MAX_BIG_DATE) == .equal) {
            return OverflowError.BigDateOverflow;
        }
        if (this.lite_date.compare(MAX_LITE_DATE) == .equal) {
            this.lite_date = MIN_LITE_DATE;
            this.year_rollover += 1;
            return;
        }
        this.lite_date.increment() catch unreachable;
    }

    /// Util for incrementing more than once.
    /// Fails before allowing year to go beyond 4,294,967,295.
    pub fn incrementNTimes(this: *Self, n: usize) OverflowError!void {
        for (0..n) |_| try this.increment();
    }

    /// Decrement by one day, handling month and year turnovers (handles leap years).
    /// Fails before allowing year to go negative.
    pub fn decrement(this: *Self) UnderflowError!void {
        if (this.year_rollover == 0 and this.lite_date.compare(MIN_LITE_DATE) == .equal) {
            return UnderflowError.DateUnderflow;
        }
        if (this.lite_date.compare(MIN_LITE_DATE) == .equal) {
            this.lite_date = MAX_LITE_DATE;
            this.year_rollover -= 1;
            return;
        }
        try this.lite_date.decrement();
    }

    /// Util for decrementing more than once.
    /// Fails before allowing year to go negative.
    pub fn decrementNTimes(this: *Self, n: usize) UnderflowError!void {
        for (0..n) |_| try this.decrement();
    }

    /// Compare two BigDate structs.
    ///
    /// Returns DateComparison enum(i2):
    /// * DateComparison.before = -1
    /// * DateComparison.equal = 0
    /// * DateComparison.after = 1
    pub fn compare(this: Self, other: Self) DateComparison {
        if (this.year_rollover < other.year_rollover) return .before;
        if (this.year_rollover > other.year_rollover) return .after;
        // Reach here -> year rollovers are equal, just compare lite dates
        return this.lite_date.compare(other.lite_date);
    }

    /// Combine rollover and inner LiteDate year to get the true year value.
    pub fn getTrueYear(this: Self) u32 {
        return this.lite_date.year + (this.year_rollover * U16_MAX_VALUE);
    }
};

/// Takes a date input in the form "mm/dd/yyyy" and returns a Date union.
///
/// If year > 65,535, a BigDate will be used.
/// Otherwise, a LiteDate will be used.
///
/// Fails if format is wrong or day/month/year is out of scope.
///
/// "mm/dd/yyyy" format is not strict i.e.
/// * mm/dd/yy is valid; yy = 96 will be treated as year 96, not 1996
/// * m/d/y is valid
/// * mm/d/yyyy is valid
/// * mmmmm/dddddd/yyyyyy is valid but ontologically incorrect
/// * Any length for any part of the date is valid - it is the order that matters
pub fn parseDate(allocator: Allocator, input: []const u8) !Date {
    var date_breakdown = try ArrayList(u32).initCapacity(allocator, 3);
    defer date_breakdown.deinit();
    var it = std.mem.tokenizeScalar(u8, input, '/');
    while (it.next()) |date_frag| {
        const parsed_date_frag: u32 = try std.fmt.parseUnsigned(u32, date_frag, 10);
        try date_breakdown.append(parsed_date_frag);
    }
    if (date_breakdown.items.len != 3) {
        return InputError.InvalidDateFormat;
    }
    if (date_breakdown.items[0] > 12) {
        return InputError.MonthTooBig;
    }
    if (date_breakdown.items[1] > 31) {
        return InputError.DayTooBig;
    }
    const day: u5 = @intCast(date_breakdown.items[1]);
    const month: u4 = @intCast(date_breakdown.items[0]);
    return try Date.fromInts(date_breakdown.items[2], month, day);
}

/// Date comparison stored as a 2-bit signed int.
/// * before = -1
/// * equal = 0
/// * after = 1
pub const DateComparison = enum(i2) { before = -1, equal = 0, after = 1 };

/// Occurs when a Date is incremented above the max value.
pub const OverflowError = error{
    /// LiteDate max year = 65,535.
    LiteDateOverflow,
    /// BigDate max year = 4,294,967,295.
    BigDateOverflow,
};
/// Occurs when a Date is decremented below the max value.
pub const UnderflowError = error{
    /// Min year = 0
    DateUnderflow,
};
/// Occurs when Date input is invalid.
pub const InputError = error{
    /// Must be in mm/dd/yyyy or similar format.
    InvalidDateFormat,
    /// Max year = 4,294,967,295.
    YearTooBig,
    /// Max month = 12.
    MonthTooBig,
    /// Max day = 31, 30, or 28 (depends on month).
    DayTooBig,
};


// Constraints
const U16_MAX_VALUE: u32 = 65536;
const MAX_YEAR = 4_294_967_295;
const MAX_LITE_DATE: LiteDate = .{
    .year = U16_MAX_VALUE - 1,
    .month_day = .{
        .month = .dec,
        .day_index = 31,
    },
};
const MAX_BIG_DATE: BigDate = .{
    .lite_date = MAX_LITE_DATE,
    .year_rollover = U16_MAX_VALUE - 1,
};
const MIN_LITE_DATE: LiteDate = .{
    .year = 0,
    .month_day = .{
        .month = .jan,
        .day_index = 1,
    },
};
const MIN_BIG_DATE: BigDate = .{
    .lite_date = MAX_LITE_DATE,
    .year_rollover = 0,
};

const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const print = std.debug.print;
const epoch = std.time.epoch;

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// TESTING
const testing = std.testing;
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
    try testing.expect(lite_date.year == 1950 and
        lite_date.month_day.month == .nov and
        lite_date.month_day.day_index == 10);
    var date: Date = .{ .lite_date = lite_date };
    print("[print_test] {f}\n", .{date});
    try date.increment();
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
    try testing.expect(lite_date.year == 1950 and
        lite_date.month_day.month == .dec and
        lite_date.month_day.day_index == 1);
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
    try testing.expect(lite_date.year == 1950 and
        lite_date.month_day.month == .sep and
        lite_date.month_day.day_index == 1);
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
    try testing.expect(lite_date.year == 1950 and
        lite_date.month_day.month == .mar and
        lite_date.month_day.day_index == 1);
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
    try testing.expect(lite_date.year == 2024 and
        lite_date.month_day.month == .feb and
        lite_date.month_day.day_index == 29);
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
    try testing.expect(lite_date.year == 1951 and
        lite_date.month_day.month == .jan and
        lite_date.month_day.day_index == 1);
    const date: Date = .{
        .lite_date = lite_date,
    };
    print("[print_test] {f}\n", .{date});
}
test "Date increment LiteDateOverflow" {
    var lite_date = MAX_LITE_DATE;
    try testing.expectError(OverflowError.LiteDateOverflow, lite_date.increment());
}
test "Date increment BigDateOverflow" {
    var big_date = MAX_BIG_DATE;
    try testing.expectError(OverflowError.BigDateOverflow, big_date.increment());
}
test "Date increment BigDateOverflow 2" {
    var date: Date = .{ .big_date = MAX_BIG_DATE };
    try testing.expectError(OverflowError.BigDateOverflow, date.increment());
}

// Date incrementNTimes
test "Date incrementNTimes normal" {
    var date: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .apr, .day_index = 1 },
    } };
    try date.incrementNTimes(20);
    const date2: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .apr, .day_index = 21 },
    } };
    try testing.expectEqual(.equal, date.compare(date2));
}
test "Date incrementNTimes month rollover" {
    var date: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .apr, .day_index = 1 },
    } };
    try date.incrementNTimes(30);
    const date2: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .may, .day_index = 1 },
    } };
    try testing.expectEqual(.equal, date.compare(date2));
}
test "Date incrementNTimes year rollover" {
    var date: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .dec, .day_index = 2 },
    } };
    try date.incrementNTimes(30);
    const date2: Date = .{ .lite_date = .{
        .year = 2026,
        .month_day = .{ .month = .jan, .day_index = 1 },
    } };
    try testing.expectEqual(.equal, date.compare(date2));
}
test "Date incrementNTimes LiteDate -> BigDate" {
    var date: Date = .{ .lite_date = .{
        .year = U16_MAX_VALUE - 1,
        .month_day = .{ .month = .dec, .day_index = 2 },
    } };
    try date.incrementNTimes(30);
    const date2: Date = .{ .big_date = .{
        .year_rollover = 1,
        .lite_date = .{
            .year = 0,
            .month_day = .{ .month = .jan, .day_index = 1 },
        },
    } };
    try testing.expectEqual(.equal, date.compare(date2));
}

// Date decrement
test "Date decrement day" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .nov,
            .day_index = 9,
        },
    };
    try lite_date.decrement();
    try testing.expect(lite_date.year == 1950 and
        lite_date.month_day.month == .nov and
        lite_date.month_day.day_index == 8);
    var date: Date = .{ .lite_date = lite_date };
    print("[print_test] {f}\n", .{date});
    try date.decrement();
    print("[print_test] {f}\n", .{date});
}
test "Date decrement 30 day month" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .dec,
            .day_index = 1,
        },
    };
    try lite_date.decrement();
    try testing.expect(lite_date.year == 1950 and
        lite_date.month_day.month == .nov and
        lite_date.month_day.day_index == 30);
    print("[print_test] {f}\n", .{Date{ .lite_date = lite_date }});
}
test "Date decrement 31 day month" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .sep,
            .day_index = 1,
        },
    };
    try lite_date.decrement();
    try testing.expect(lite_date.year == 1950 and
        lite_date.month_day.month == .aug and
        lite_date.month_day.day_index == 31);
    print("[print_test] {f}\n", .{Date{ .lite_date = lite_date }});
}
test "Date decrement February (not Leap Year)" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .mar,
            .day_index = 1,
        },
    };
    try lite_date.decrement();
    try testing.expect(lite_date.year == 1950 and
        lite_date.month_day.month == .feb and
        lite_date.month_day.day_index == 28);
    print("[print_test] {f}\n", .{Date{ .lite_date = lite_date }});
}
test "Date decrement February (Leap Year)" {
    var lite_date = LiteDate{
        .year = 2024,
        .month_day = .{
            .month = .mar,
            .day_index = 1,
        },
    };
    try lite_date.decrement();
    try testing.expect(lite_date.year == 2024 and
        lite_date.month_day.month == .feb and
        lite_date.month_day.day_index == 29);
    print("[print_test] {f}\n", .{Date{ .lite_date = lite_date }});
}
test "Date decrement year" {
    var lite_date = LiteDate{
        .year = 1950,
        .month_day = .{
            .month = .jan,
            .day_index = 1,
        },
    };
    try lite_date.decrement();
    try testing.expect(lite_date.year == 1949 and
        lite_date.month_day.month == .dec and
        lite_date.month_day.day_index == 31);
    const date: Date = .{ .lite_date = lite_date };
    print("[print_test] {f}\n", .{date});
}
test "Date decrement LiteDate DateUnderflow" {
    var lite_date = MIN_LITE_DATE;
    try testing.expectError(UnderflowError.DateUnderflow, lite_date.decrement());
}
test "Date decrement BigDate DateUnderflow" {
    var big_date: BigDate = .{
        .year_rollover = 0,
        .lite_date = MIN_LITE_DATE,
    };
    try testing.expectError(UnderflowError.DateUnderflow, big_date.decrement());
}
test "Date decrement BigDate DateUnderflow 2" {
    var date: Date = .{ .big_date = .{
        .year_rollover = 0,
        .lite_date = MIN_LITE_DATE,
    } };
    try testing.expectError(UnderflowError.DateUnderflow, date.decrement());
}

// Date decrementNTimes
test "Date decrementNTimes normal" {
    var date: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .apr, .day_index = 21 },
    } };
    try date.decrementNTimes(20);
    const date2: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .apr, .day_index = 1 },
    } };
    try testing.expectEqual(.equal, date.compare(date2));
}
test "Date decrementNTimes month rollover" {
    var date: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .may, .day_index = 1 },
    } };
    try date.decrementNTimes(30);
    const date2: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .apr, .day_index = 1 },
    } };
    try testing.expectEqual(.equal, date.compare(date2));
}
test "Date decrementNTimes year rollover" {
    var date: Date = .{ .lite_date = .{
        .year = 2025,
        .month_day = .{ .month = .jan, .day_index = 1 },
    } };
    try date.decrementNTimes(30);
    const date2: Date = .{ .lite_date = .{
        .year = 2024,
        .month_day = .{ .month = .dec, .day_index = 2 },
    } };
    try testing.expectEqual(.equal, date.compare(date2));
}
test "Date decrementNTimes BigDate -> LiteDate" {
    var date: Date = .{ .big_date = MIN_BIG_DATE };
    const date2: Date = .{ .lite_date = .{
        .year = U16_MAX_VALUE - 1,
        .month_day = .{ .month = .dec, .day_index = 1 },
    } };
    try date.decrementNTimes(30);
    try testing.expectEqual(.equal, date.compare(date2));
}

// Date equals
test "equals true" {
    const date = Date{ .lite_date = .{
        .year = 2023,
        .month_day = .{ .month = .jan, .day_index = 7 },
    } };
    const date2 = Date{ .lite_date = .{
        .year = 2023,
        .month_day = .{ .month = .jan, .day_index = 7 },
    } };
    try testing.expectEqual(.equal, date.compare(date2));
}
test "equals false (year)" {
    const date = Date{ .lite_date = .{
        .year = 2023,
        .month_day = .{ .month = .jan, .day_index = 7 },
    } };
    const date2 = Date{ .lite_date = .{
        .year = 2024,
        .month_day = .{ .month = .jan, .day_index = 7 },
    } };
    try testing.expectEqual(.before, date.compare(date2));
}
test "equals false (month)" {
    const date = Date{ .lite_date = .{
        .year = 2023,
        .month_day = .{ .month = .jan, .day_index = 7 },
    } };
    const date2 = Date{ .lite_date = .{
        .year = 2023,
        .month_day = .{ .month = .aug, .day_index = 7 },
    } };
    try testing.expectEqual(.after, date2.compare(date));
}
test "equals false (day)" {
    const date = Date{
        .lite_date = .{
            .year = 2023,
            .month_day = .{ .month = .jan, .day_index = 7 },
        },
    };
    const date2 = Date{
        .lite_date = .{
            .year = 2023,
            .month_day = .{ .month = .jan, .day_index = 31 },
        },
    };
    try testing.expectEqual(.before, date.compare(date2));
}

// Date today
test "Date today" {
    print("[today_test] {f}\n", .{Date.today()});
}

// parseDate
test "parseDate 1" {
    const allocator = testing.allocator;
    const date = LiteDate{
        .year = 2023,
        .month_day = .{ .month = .oct, .day_index = 7 },
    };
    const parsed_date = try parseDate(allocator, "10/7/2023");
    try testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 2" {
    const allocator = testing.allocator;
    const date = LiteDate{
        .year = 2023,
        .month_day = .{ .month = .oct, .day_index = 7 },
    };
    const parsed_date = try parseDate(allocator, "10/07/2023");
    try testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 3" {
    const allocator = testing.allocator;
    const date = LiteDate{
        .year = 2023,
        .month_day = .{ .month = .jan, .day_index = 7 },
    };
    const parsed_date = try parseDate(allocator, "1/7/2023");
    try testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 4" {
    const allocator = testing.allocator;
    const date = LiteDate{
        .year = 2023,
        .month_day = .{ .month = .jan, .day_index = 7 },
    };
    const parsed_date = try parseDate(allocator, "1/07/2023");
    try testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 5" {
    const allocator = testing.allocator;
    const date = LiteDate{
        .year = 2023,
        .month_day = .{ .month = .jan, .day_index = 7 },
    };
    const parsed_date = try parseDate(allocator, "01/07/2023");
    try testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 6 (Leap Year)" {
    const allocator = testing.allocator;
    const date = LiteDate{
        .year = 2020,
        .month_day = .{ .month = .feb, .day_index = 29 },
    };
    const parsed_date = try parseDate(allocator, "02/29/2020");
    try testing.expectEqualDeep(date, parsed_date.lite_date);
}
test "parseDate 7 (InvalidDateFormat error)" {
    const allocator = testing.allocator;
    try testing.expectError(InputError.InvalidDateFormat, parseDate(allocator, "01/17"));
}
test "parseDate 8 (InvalidDateFormat error)" {
    const allocator = testing.allocator;
    try testing.expectError(InputError.InvalidDateFormat, parseDate(allocator, "01/17"));
}
test "parseDate 9 (MonthTooBig error)" {
    const allocator = testing.allocator;
    try testing.expectError(InputError.MonthTooBig, parseDate(allocator, "13/12/2025"));
}
test "parseDate 10 (DayTooBig error)" {
    const allocator = testing.allocator;
    try testing.expectError(InputError.DayTooBig, parseDate(allocator, "04/31/2025"));
}
test "parseDate 11 (DayTooBig error)" {
    const allocator = testing.allocator;
    try testing.expectError(InputError.DayTooBig, parseDate(allocator, "09/32/2025"));
}
test "parseDate 12 (Leap Year DayTooBig error)" {
    const allocator = testing.allocator;
    try testing.expectError(InputError.DayTooBig, parseDate(allocator, "02/29/2025"));
}
test "parseDate 13 (Overflow error)" {
    const allocator = testing.allocator;
    try testing.expectError(error.Overflow, parseDate(allocator, "2/2/4294967296"));
}

// BigDate getTrueYear
test "BigDate getTrueYear 1" {
    const allocator = testing.allocator;
    const parsed_date = try parseDate(allocator, "10/7/4294967295");
    try testing.expectEqual(4294967295, parsed_date.big_date.getTrueYear());
}
test "BigDate getTrueYear 2" {
    const allocator = testing.allocator;
    var parsed_date = try parseDate(allocator, "12/31/131071");
    try testing.expectEqual(131071, parsed_date.big_date.getTrueYear());
}

// Date rollover
test "Date rollover 1" {
    const allocator = testing.allocator;
    const parsed_date = try parseDate(allocator, "10/7/4294967295");
    const lite_date: LiteDate = .{
        .year = 65535,
        .month_day = .{
            .month = .oct,
            .day_index = 7,
        },
    };
    const big_date: BigDate = .{
        .year_rollover = 65535,
        .lite_date = lite_date,
    };
    try testing.expectEqualDeep(lite_date, parsed_date.big_date.lite_date);
    try testing.expectEqualDeep(big_date, parsed_date.big_date);
    print("\nDate rollover 1\n", .{});
    parsed_date.dump();
}
test "Date rollover 2" {
    const allocator = testing.allocator;
    var parsed_date = try parseDate(allocator, "12/31/131071");
    print("Date rollover 2: pre-increment\n", .{});
    parsed_date.dump();
    try parsed_date.increment();
    print("Date rollover 2: post-increment\n", .{});
    parsed_date.dump();
}
test "Date rollover 3" {
    const allocator = testing.allocator;
    var parsed_date = try parseDate(allocator, "12/31/65535");
    print("Date rollover 3: pre-increment\n", .{});
    parsed_date.dump();
    try parsed_date.increment();
    print("Date rollover 3: post-increment\n", .{});
    parsed_date.dump();
}

// Date fromInts
test "Date fromInts: LiteDate" {
    const a = try Date.fromInts(2024, 5, 21);
    try testing.expect(a.lite_date.year == 2024 and
        a.lite_date.month_day.month == epoch.Month.may and
        a.lite_date.month_day.day_index == 21);
}
test "Date fromInts: BigDate" {
    const a = try Date.fromInts(U16_MAX_VALUE, 5, 21);
    try testing.expect(a.big_date.year_rollover == 1 and
        a.big_date.lite_date.year == 0 and
        a.big_date.lite_date.month_day.month == epoch.Month.may and
        a.big_date.lite_date.month_day.day_index == 21);
}
test "Date fromInts: InputError.MonthTooBig" {
    try testing.expectError(InputError.MonthTooBig, Date.fromInts(2025, 13, 21));
}
test "Date fromInts: DateError.DayTooBig" {
    try testing.expectError(InputError.DayTooBig, Date.fromInts(2025, 2, 31));
}

// Date compare
test "LiteDate compare: before 1" {
    const a = try Date.fromInts(2024, 5, 21);
    const b = try Date.fromInts(2025, 7, 12);
    try testing.expect(a.compare(b) == .before);
}
test "LiteDate compare: before 2" {
    const a = try Date.fromInts(2025, 5, 21);
    const b = try Date.fromInts(2025, 7, 12);
    try testing.expect(a.compare(b) == .before);
}
test "LiteDate compare: before 3" {
    const a = try Date.fromInts(2025, 5, 12);
    const b = try Date.fromInts(2025, 5, 21);
    try testing.expect(a.compare(b) == .before);
}
test "LiteDate compare: after 1" {
    const a = try Date.fromInts(1961, 2, 14);
    const b = try Date.fromInts(1960, 11, 25);
    try testing.expect(a.compare(b) == .after);
}
test "LiteDate compare: after 2" {
    const a = try Date.fromInts(1961, 11, 25);
    const b = try Date.fromInts(1961, 2, 14);
    try testing.expect(a.compare(b) == .after);
}
test "LiteDate compare: after 3" {
    const a = try Date.fromInts(1961, 11, 16);
    const b = try Date.fromInts(1961, 11, 14);
    try testing.expect(a.compare(b) == .after);
}
test "LiteDate compare: equal" {
    const a = try Date.fromInts(1961, 11, 14);
    const b = try Date.fromInts(1961, 11, 14);
    try testing.expect(a.compare(b) == .equal);
}
test "BigDate compare: before 1" {
    const a = try Date.fromInts(65536, 5, 21);
    const b = try Date.fromInts(65537, 7, 12);
    try testing.expect(a.compare(b) == .before);
}
test "BigDate compare: before 2" {
    const a = try Date.fromInts(65536, 5, 21);
    const b = try Date.fromInts(65536, 7, 12);
    try testing.expect(a.compare(b) == .before);
}
test "BigDate compare: before 3" {
    const a = try Date.fromInts(65536, 5, 12);
    const b = try Date.fromInts(65536, 5, 21);
    try testing.expect(a.compare(b) == .before);
}
test "BigDate compare: after 1" {
    const a = try Date.fromInts(123456792, 2, 14);
    const b = try Date.fromInts(123456789, 11, 25);
    try testing.expect(a.compare(b) == .after);
}
test "BigDate compare: after 2" {
    const a = try Date.fromInts(123456789, 11, 25);
    const b = try Date.fromInts(123456789, 2, 14);
    try testing.expect(a.compare(b) == .after);
}
test "BigDate compare: after 3" {
    const a = try Date.fromInts(123456789, 11, 16);
    const b = try Date.fromInts(123456789, 11, 14);
    try testing.expect(a.compare(b) == .after);
}
test "BigDate compare: equal" {
    const a = try Date.fromInts(4294967295, 11, 14);
    const b = try Date.fromInts(4294967295, 11, 14);
    try testing.expect(a.compare(b) == .equal);
}
test "LiteDate/BigDate compare: before" {
    const a = try Date.fromInts(2025, 5, 21);
    const b = try Date.fromInts(65537, 7, 12);
    try testing.expect(a.compare(b) == .before);
}
test "LiteDate/BigDate compare: after" {
    const a = try Date.fromInts(123456792, 2, 14);
    const b = try Date.fromInts(2025, 11, 25);
    try testing.expect(a.compare(b) == .after);
}
test "LiteDate/BigDate compare: equal" {
    const a = try Date.fromInts(65535, 11, 14);
    var b = try Date.fromInts(65536, 11, 14);
    b.big_date.year_rollover = 0;
    b.big_date.lite_date.year = 65535;
    a.dump();
    b.dump();
    try testing.expect(a.compare(b) == .equal);
}

// Show sizes of Date structs
test "sizeOf" {
    print("sizeOf Date: {d} bytes == {d} bits\n", .{ @sizeOf(Date), @bitSizeOf(Date) });
    print("sizeOf LiteDate: {d} bytes == {d} bits\n", .{ @sizeOf(LiteDate), @bitSizeOf(LiteDate) });
    print("sizeOf BigDate: {d} bytes == {d} bits\n", .{ @sizeOf(BigDate), @bitSizeOf(BigDate) });
}
