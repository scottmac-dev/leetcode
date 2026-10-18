/// SPSC Ring Buffer = lock-free single producer, single consumer ring buffer 
///
/// Commonly used in systems when moving data between two parties, such as UART, DMA, audio pipelines, io_uring queues, network packet rings
/// Thread safe data structure for high-throughput comms between two threads, one reader and one writer
/// Eliminates need for mutexes or CAS ops as each thread owns its cursor index exclusively
///
/// Characteristics:
///     - atomic cursors: head (read) and tail (write) are atomic idx owned by each thread 
///     - correctness: ensured with release/acquire, producer release stores to pub data, consumer acquire loads ensuring visibility
///     - Pow 2 capacity: capacity generally a power of 2, allowing fast wrapping and bitwise ops instead of modulo index wrapping
///     - empty slot: generally a single slot kept empty to distinguish a full buff from empty buff where head == tail
///     - false sharing: head and tail idx are padded to seperate cache lines to prevent degradtion due to cache coherency traffic
///
/// Advanced:
///     - cached cursor: threads cache opposite threads cursor in local var, refreshes from memory when buffer full or empty, can reduce cross-core traffic ~90%
///     - batch ops: proucer may reserve multiple slots and consumer read multiple itemr per atomic update 
///     - variable sized elements: may allow copying various sidez data into buffer, not explored here
///
const std = @import("std");
const atomic = std.atomic;

pub fn SpscRing(comptime T: type, comptime N: usize) type {
    comptime std.debug.assert(std.math.isPowerOfTwo(N));

    return struct {
        const Self = @This();

        // items in buf = (tail - head) or (pushed - popped)
        // empty if tail == head or pushed == popped 
        // full when (tail - head) == N, or when items in buf equal comptime assigned capacity
        buf: [N]T = undefined,  

        head: atomic.Value(usize) align(atomic.cache_line) = .init(0),  // consumer owns, counts items popped
        tail: atomic.Value(usize) align(atomic.cache_line) = .init(0),  // producer owns, counts items pushed

        // Producer only
        pub fn push(self: *Self, item: T) bool {
            const tail = self.tail.load(.monotonic); // monotonic guarantees no torn reads
            const head = self.head.load(.acquire); // acquire pairs with consumers .release, guaranteeing that consumer is finished reading up to head
            if (tail -% head == N) return false;    // full 

            // array slot = idx & (N - 1), the bitwise equivalent of index % N for wrapping, works wit pow2 capacity 
            // head & tail dont wrap to 0 when exceeding N, they only wrap exceeding usize max 
            self.buf[tail & (N - 1)] = item;    // place in buf, non atomic write
            self.tail.store(tail +% 1, .release);   // publish, consumer sees new tail idx, write is commited
            return true;    // success
        }

        // Consumer only
        pub fn pop(self: *Self) ?T {
            const head = self.head.load(.monotonic); // no torn writes
            const tail = self.tail.load(.acquire); // see the producer's write
            if (head == tail) return null; // empty

            const item = self.buf[head & (N - 1)];
            self.head.store(head +% 1, .release); // free the slot
            return item;
        }

        // Returns number of items remaining in buf (unpopped)
        pub fn len(self: *Self) usize {
            const head = self.head.load(.monotonic);
            const tail = self.tail.load(.monotonic); 
            return tail -% head; 
        }

        // True when head == tail, no items unpopped in buf
        pub fn isEmpty(self: *Self) bool {
            const head = self.head.load(.monotonic);
            const tail = self.tail.load(.monotonic); 
            return head == tail;
        }
        
        // True when amount of items in buf == comptime assigned N capacity
        pub fn isFull(self: *Self) bool {
            const head = self.head.load(.monotonic);
            const tail = self.tail.load(.monotonic); 
            return tail -% head == N;
        }
    };
}


test "spsc basic" {
    var q: SpscRing(u32, 4) = .{};
    try std.testing.expect(q.push(1));
    try std.testing.expect(q.push(2));
    try std.testing.expectEqual(@as(?u32, 1), q.pop());
    try std.testing.expectEqual(@as(?u32, 2), q.pop());
    try std.testing.expectEqual(@as(?u32, null), q.pop()); // null empty
    try std.testing.expect(q.isEmpty());
}

test "spsc full" {
    var q: SpscRing(u32, 4) = .{};
    try std.testing.expect(q.push(1));
    try std.testing.expect(q.push(2));
    try std.testing.expect(q.push(3));
    try std.testing.expect(q.push(4));
    try std.testing.expect(!q.push(5)); // false, full
    try std.testing.expect(q.isFull());
}

test "spsc wrapping" {
    var q: SpscRing(u32, 4) = .{};
    try std.testing.expect(q.push(1));
    try std.testing.expect(q.push(2));
    try std.testing.expectEqual(@as(?u32, 1), q.pop());
    try std.testing.expectEqual(@as(?u32, 2), q.pop());
    try std.testing.expect(q.push(3));
    try std.testing.expect(q.push(4));
    try std.testing.expect(q.push(5));
    try std.testing.expect(q.push(6));
    try std.testing.expectEqual(@as(?u32, 3), q.pop());
    try std.testing.expectEqual(@as(?u32, 4), q.pop());
    try std.testing.expectEqual(@as(?u32, 5), q.pop());
    try std.testing.expectEqual(1, q.len());
    try std.testing.expectEqual(@as(?u32, 6), q.pop());
}

// Try with 
// zig test spsc.zig -O ReleaseSafe
// zig test spsc.zig -fsanitize-thread
test "spsc thread stress: ordering and integrity across threads" {
    const Payload = struct { seq: u64, check: u64 };
    const Q = SpscRing(Payload, 8); // small N = maximum contention

    const Ctx = struct {
        const Self = @This();
        const count: u64 = 1_000_000;
        const magic: u64 = 0x9E37_79B9_7F4A_7C15;

        fn producer(q: *Q) void {
            var i: u64 = 0;
            while (i < count) {
                if (q.push(.{ .seq = i, .check = i *% magic })) {
                    i += 1;
                } else {
                    atomic.spinLoopHint(); // full, let the consumer catch up
                }
            }
        }

        fn consumer(q: *Q, errors: *u64) void {
            var expected: u64 = 0;
            while (expected < count) {
                if (q.pop()) |p| {
                    // Wrong seq = lost/duplicated/reordered item.
                    // Bad check = torn or not-yet-visible write.
                    if (p.seq != expected or p.check != p.seq *% Self.magic) errors.* += 1;
                    expected += 1;
                } else {
                    std.atomic.spinLoopHint(); // empty, wait for pushed values
                }
            }
        }
    };

    var q: Q = .{};
    var errors: u64 = 0; // only the consumer writes this, join() makes it visible

    const p = try std.Thread.spawn(.{}, Ctx.producer, .{&q});
    const c = try std.Thread.spawn(.{}, Ctx.consumer, .{ &q, &errors });
    p.join();
    c.join();

    try std.testing.expectEqual(@as(u64, 0), errors);
    try std.testing.expect(q.isEmpty());
}

test "spsc counters wrap past usize max" {
    const start = std.math.maxInt(usize) - 2;
    var q: SpscRing(u32, 4) = .{ .head = .init(start), .tail = .init(start) };

    for (0..10) |i| {
        try std.testing.expect(q.push(@intCast(i)));
        try std.testing.expect(q.push(@intCast(i + 100)));
        try std.testing.expectEqual(@as(usize, 2), q.len());
        try std.testing.expectEqual(@as(?u32, @intCast(i)), q.pop());
        try std.testing.expectEqual(@as(?u32, @intCast(i + 100)), q.pop());
    }
    try std.testing.expect(q.isEmpty());
}
