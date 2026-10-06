//! ============================================================================
//!  Problem: Bubble Sort
//! ============================================================================
//!
//!  Given a slice of integers `nums`, sort it **in place** in ascending order
//!  using the bubble sort algorithm.
//!
//!  Bubble sort works by repeatedly stepping through the slice, comparing each
//!  pair of adjacent elements, and swapping them if they are in the wrong
//!  order. After each full pass, the largest unsorted element has "bubbled"
//!  to its final position at the end of the unsorted region.
//!
//!  You must NOT use `std.mem.sort` or any other library sorting routine.
//!  Do not allocate — the sort must happen inside the slice you are given.
//!
//!  ---------------------------------------------------------------------------
//!  Example 1:
//!      Input:  nums = [5, 1, 4, 2, 8]
//!      Output: nums = [1, 2, 4, 5, 8]
//!
//!  Example 2:
//!      Input:  nums = [3, -1, 3, 0]
//!      Output: nums = [-1, 0, 3, 3]
//!
//!  Example 3:
//!      Input:  nums = []
//!      Output: nums = []
//!
//!  ---------------------------------------------------------------------------
//!  Constraints:
//!      0 <= nums.len <= 1000
//!      -10^4 <= nums[i] <= 10^4
//!
//!  ---------------------------------------------------------------------------
//!  Run the tests with:
//!      zig test bubble_sort.zig
//! ============================================================================

const std = @import("std");
const testing = std.testing;

pub fn bubbleSort(nums: []i32) void {
    if (nums.len < 2) {
        return;
    }
    var passes: usize = 0;
    while (true) {
        var changed: bool = false;
        for (1..nums.len) |i| {
            const prev: i32 = nums[i - 1];
            const curr: i32 = nums[i];
            if (prev > curr) {
                std.mem.swap(i32, &nums[i - 1], &nums[i]);
                //nums[i - 1] = curr;
                //nums[i] = prev;
                changed = true;
            }
        }
        passes += 1;

        if (!changed) {
            std.debug.print("Sorted in {d} passes \n" , .{passes});
            return;
        }
    }
}

// ============================================================================

//  Test cases 
// ============================================================================

test "example 1: basic unsorted" {
    var nums = [_]i32{ 5, 1, 4, 2, 8 };
    const expected = [_]i32{ 1, 2, 4, 5, 8 };
    bubbleSort(&nums);
    try testing.expectEqualSlices(i32, &expected, &nums);
}

test "example 2: negatives and duplicates" {
    var nums = [_]i32{ 3, -1, 3, 0 };
    const expected = [_]i32{ -1, 0, 3, 3 };
    bubbleSort(&nums);
    try testing.expectEqualSlices(i32, &expected, &nums);
}

test "example 3: empty slice" {
    var nums = [_]i32{};

    const expected = [_]i32{};
    bubbleSort(&nums);
    try testing.expectEqualSlices(i32, &expected, &nums);
}


test "single element" {

    var nums = [_]i32{42};

    const expected = [_]i32{42};
    bubbleSort(&nums);
    try testing.expectEqualSlices(i32, &expected, &nums);
}

test "two elements, swapped" {
    var nums = [_]i32{ 2, 1 };
    const expected = [_]i32{ 1, 2 };
    bubbleSort(&nums);
    try testing.expectEqualSlices(i32, &expected, &nums);
}

test "already sorted" {
    var nums = [_]i32{ 1, 2, 3, 4, 5, 6, 7 };
    const expected = [_]i32{ 1, 2, 3, 4, 5, 6, 7 };
    bubbleSort(&nums);
    try testing.expectEqualSlices(i32, &expected, &nums);
}

test "reverse sorted (worst case)" {
    var nums = [_]i32{ 9, 8, 7, 6, 5, 4, 3, 2, 1 };
    const expected = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    bubbleSort(&nums);
    try testing.expectEqualSlices(i32, &expected, &nums);
}

test "all identical" {
    var nums = [_]i32{ 7, 7, 7, 7, 7 };
    const expected = [_]i32{ 7, 7, 7, 7, 7 };
    bubbleSort(&nums);
    try testing.expectEqualSlices(i32, &expected, &nums);
}

test "constraint boundaries" {
    var nums = [_]i32{ 10_000, -10_000, 0, 10_000, -10_000 };
    const expected = [_]i32{ -10_000, -10_000, 0, 10_000, 10_000 };
    bubbleSort(&nums);
    try testing.expectEqualSlices(i32, &expected, &nums);
}


test "random 1000 elements vs std.mem.sort" {
    var prng = std.Random.DefaultPrng.init(0xB0BB1E);
    const rand = prng.random();

    var nums: [1000]i32 = undefined;
    for (&nums) |*n| n.* = rand.intRangeAtMost(i32, -10_000, 10_000);

    var expected: [1000]i32 = nums;
    std.mem.sort(i32, &expected, {}, std.sort.asc(i32));


    bubbleSort(&nums);

    try testing.expectEqualSlices(i32, &expected, &nums);
}
