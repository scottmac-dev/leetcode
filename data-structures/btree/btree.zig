const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Order = std.math.Order;

/// Various types of invalid tree state to check
const ValidationError = error{
    EmptyRoot,
    CountMismatch,
    NodeOverfull,
    NodeUnderfull,
    KeysNotSorted,
    KeyOutOfBounds,
};

/// In memory BTree
pub fn BTree(comptime K: type, comptime V: type, comptime B: usize, comptime compareFn: anytype) type {
    comptime assert(B >= 2); // BTree with node < 2 is just BST
    const max_keys = 2 * B - 1; // 2B - 1 , ensures always a median split node
    const max_children = max_keys + 1; // Always extra child pointer, eg. * K * K *
    const median = B - 1;
    const min_keys = median;
    const Len = u16;
    comptime assert(max_children <= std.math.maxInt(Len)); // children index = len + 1 must fit

    return struct {
        const Self = @This();
        pub const empty: Self = .{};

        // Allow for compareFn to be fn (anytype, anytype) anytype
        // which allows the convenient use of std.math.order.
        fn compare(a: K, b: K) Order {
            return compareFn(a, b);
        }

        // --- Properties

        root: ?*Leaf = null,
        len: usize = 0,
        height: u32 = 0, // 0 => root is leaf

        // --- Data shapes

        /// Leaf node holds key value mappings, no pointers as they are true leaf nodes
        const Leaf = struct {
            len: Len = 0,
            keys: [max_keys]K = undefined,
            values: [max_keys]V = undefined,

            pub fn isFull(self: *const Leaf) bool {
                return self.len == max_keys;
            }
        };

        /// Embeds a leaf nodes data and points at children nodes, used for mid tree nodes so not all
        /// leaf nodes require children pointer arrays
        const Internal = struct {
            data: Leaf, // first pos to align *Internal as *Leaf
            // always one more pointer than node
            // * L * L *
            children: [max_keys + 1]*Leaf = undefined,

            /// Casting between Leaf and Internal node so data and additional pointers not always needed
            fn cast(leaf: *Leaf) *Internal {
                return @alignCast(@fieldParentPtr("data", leaf));
            }

            fn castConst(leaf: *const Leaf) *const Internal {
                return @alignCast(@fieldParentPtr("data", leaf));
            }
        };

        /// Result from getOrPut function
        pub const GetOrPutResult = struct {
            key_ptr: *const K,
            val_ptr: *V,
            found_existing: bool,
        };

        /// Result from a searchNode function
        pub const SearchNodeResult = struct {
            idx: usize,
            found: bool,
        };

        /// Pairs key and value as a single return shape
        pub const KV = struct {
            key: K,
            val: V,
        };

        /// Pointers to a key and value stored in the tree, invalidated by the next mutation
        pub const Entry = struct {
            key_ptr: *const K,
            val_ptr: *V,
        };

        // --- Life cycle

        /// Public API for total KV pairs
        pub fn count(self: *const Self) usize {
            return self.len;
        }

        /// Recursively free all nodes
        pub fn deinit(self: *Self, alloc: Allocator) void {
            if (self.root) |r| freeNode(alloc, r, self.height);
            self.* = undefined;
        }

        /// Frees a nodes resources based on its height, used for recursive tree walk in deinit
        fn freeNode(alloc: Allocator, node: *Leaf, h: u32) void {
            if (h == 0) {
                // Is leaf
                alloc.destroy(node);
            } else {
                // Is Internal, walk children and destroy self as Internal after
                const internal: *Internal = Internal.cast(node);

                // node.len is slots used, children.len could be unused capacity
                for (internal.children[0 .. node.len + 1]) |n| {
                    freeNode(alloc, n, h - 1);
                }
                alloc.destroy(internal);
            }
        }

        /// Allocates and returns Leaf pointer
        fn createLeaf(alloc: Allocator) Allocator.Error!*Leaf {
            const n = try alloc.create(Leaf);
            n.* = .{}; // initialize
            return n;
        }

        /// Allocates and returns Internal pointer
        fn createInternal(alloc: Allocator) Allocator.Error!*Internal {
            const n = try alloc.create(Internal);
            n.* = .{ .data = .{} }; // initialize
            return n;
        }

        // --- Search and retrieve

        /// Search a node to identify key position relative to stored keys
        fn searchNode(node: *const Leaf, key: K) SearchNodeResult {
            for (node.keys[0..node.len], 0..) |k, i| {
                switch (compare(key, k)) {
                    .lt => return .{ .idx = i, .found = false }, // less than, search lhs
                    .eq => return .{ .idx = i, .found = true }, // found, return corresponding value to key
                    .gt => {}, // continue
                }
            }
            return .{ .idx = node.len, .found = false }; // exhausted keys, search rhs
        }

        /// Public API for does btree contain a key
        pub fn contains(self: *const Self, key: K) bool {
            return self.getPtr(key) != null;
        }

        /// Return a value as a pointer given key, null if not found
        pub fn getPtr(self: *const Self, key: K) ?*V {
            var node = self.root orelse return null; // empty BTree
            var h = self.height; // start height, decremented as we descend
            while (true) {
                const r = searchNode(node, key);
                if (r.found) return &node.values[r.idx]; // found
                if (h == 0) return null; // exhausted search, not found
                node = Internal.cast(node).children[r.idx]; // descend to search children
                h -= 1; // decrement to track height
            }
        }

        /// Walk Btree and return value if found, else null
        pub fn get(self: *const Self, key: K) ?V {
            return if (self.getPtr(key)) |p| p.* else null;
        }

        /// Entry with the smallest key, null if empty
        pub fn min(self: *const Self) ?Entry {
            var node = self.root orelse return null;
            var h = self.height;
            while (h > 0) : (h -= 1) node = Internal.cast(node).children[0]; // leftmost path
            return .{ .key_ptr = &node.keys[0], .val_ptr = &node.values[0] };
        }

        /// Entry with the largest key, null if empty
        pub fn max(self: *const Self) ?Entry {
            var node = self.root orelse return null;
            var h = self.height;
            while (h > 0) : (h -= 1) node = Internal.cast(node).children[node.len]; // rightmost path
            const i = node.len - 1;
            return .{ .key_ptr = &node.keys[i], .val_ptr = &node.values[i] };
        }

        // --- Iteration

        /// Deepest path the iterator can record. Every level multiplies the node count by at least
        /// B >= 2, so a tree this deep would need over 2^63 nodes, unreachable in practice
        const max_depth = 64;

        /// In order iterator, holds the path from the root to the current position as a stack of
        /// (node, idx) frames, with no allocation:
        ///     - top frame: idx of the next key to yield from that node
        ///     - ancestor frames: idx of the child descended into, which is also the idx of the
        ///       key that follows that child's subtree, * K0 * K1 * ..
        /// Invalidated by any mutation of the tree.
        pub const Iterator = struct {
            const Frame = struct { node: *Leaf, idx: Len };

            stack: [max_depth]Frame = undefined,
            depth: u8 = 0, // frames in use, 0 => exhausted
            height: u32 = 0, // tree height, the frame at level == height is a leaf

            /// Next entry in sorted key order, null when exhausted
            pub fn next(it: *Iterator) ?Entry {
                while (it.depth > 0) {
                    const level = it.depth - 1;
                    const top = &it.stack[level];
                    if (top.idx < top.node.len) {
                        const i = top.idx;
                        top.idx += 1;
                        // Internal: the subtree right of key i comes before key i + 1, queue it up
                        if (level < it.height) it.pushLeftmost(Internal.cast(top.node).children[top.idx]);
                        return .{ .key_ptr = &top.node.keys[i], .val_ptr = &top.node.values[i] };
                    }
                    it.depth -= 1; // node exhausted, resume at the parent's next key
                }
                return null;
            }

            fn push(it: *Iterator, node: *Leaf, idx: usize) void {
                assert(it.depth < max_depth);
                it.stack[it.depth] = .{ .node = node, .idx = @intCast(idx) };
                it.depth += 1;
            }

            /// Push `start` then follow its leftmost children down to a leaf
            fn pushLeftmost(it: *Iterator, start: *Leaf) void {
                var node = start;
                while (true) {
                    it.push(node, 0);
                    if (it.depth - 1 == it.height) return; // leaf level reached
                    node = Internal.cast(node).children[0];
                }
            }
        };

        fn emptyIterator(self: *const Self) Iterator {
            assert(self.height < max_depth);
            return .{ .height = self.height };
        }

        /// Iterator over every entry in sorted key order
        pub fn iterator(self: *const Self) Iterator {
            var it = self.emptyIterator();
            if (self.root) |r| it.pushLeftmost(r);
            return it;
        }

        /// Iterator starting at the first entry with key >= `key`
        pub fn lowerBound(self: *const Self, key: K) Iterator {
            return self.seek(key, .lower);
        }

        /// Iterator starting at the first entry with key > `key`
        pub fn upperBound(self: *const Self, key: K) Iterator {
            return self.seek(key, .upper);
        }

        /// Descend towards `key` recording the path, so the iterator resumes at the first key that is
        /// >= `key` (lower) or > `key` (upper). A leaf frame left with idx == len is popped by next(),
        /// which then resumes at the ancestor key following that subtree.
        fn seek(self: *const Self, key: K, comptime bound: enum { lower, upper }) Iterator {
            var it = self.emptyIterator();
            var node = self.root orelse return it;
            var h = self.height;
            while (true) {
                const r = searchNode(node, key);
                // Exact match: lower starts on it, upper starts just after it
                const idx = if (r.found and bound == .upper) r.idx + 1 else r.idx;
                it.push(node, idx);
                if (h == 0) return it;
                if (r.found) {
                    // upper on an internal node: successor is the leftmost key of the right child
                    if (bound == .upper) it.pushLeftmost(Internal.cast(node).children[idx]);
                    return it;
                }
                node = Internal.cast(node).children[idx]; // descend
                h -= 1;
            }
        }

        // --- Insert

        /// Puts a key and value into a node that is not full at pos idx
        fn insertAt(node: *Leaf, idx: usize, key: K, value: V) void {
            assert(node.len < max_keys);
            assert(idx <= node.len);
            const len = node.len;

            // Shift keys and values to right if required to make room for new KV insert
            @memmove(node.keys[idx + 1 .. len + 1], node.keys[idx..len]);
            @memmove(node.values[idx + 1 .. len + 1], node.values[idx..len]);

            // Insert at idx position which will be clear now
            node.keys[idx] = key;
            node.values[idx] = value;
            node.len += 1;
        }

        /// When parent is a internal node and children is full
        /// A full node holds at most 2B - 1 keys, its middle (median) node is index B - 1
        /// Top down splitting strategy - when a child is full split it before going down to it on insert
        ///     - results in single pass insert, nodes split on way down to find insert pos
        ///     - when reaching a leaf that has room, insert always succeeds no backtracking
        ///     - when splitting child, its parent has room for the median guaranteed
        ///     - full nodes cannot take another key, cut it in half and middle key moves up to parent,
        ///     becoming the separator between the halves, * M *
        fn splitChild(alloc: Allocator, parent: *Internal, idx: usize, child_h: u32) Allocator.Error!void {
            const child_n = parent.children[idx]; // becomes lhs node
            assert(child_n.len == max_keys); // only split full nodes
            assert(parent.data.len < max_keys); // top down split assumes room in parent to push up

            // Allocate rhs node first, if alloc fails tree does not change
            const rhs: *Leaf = if (child_h == 0) blk: {
                // Is leaf
                const leaf = try createLeaf(alloc);
                break :blk leaf;
            } else blk: {
                // Is internal
                const internal = try createInternal(alloc);
                break :blk &internal.data;
            };

            // Top half keys/values moves to rhs node
            @memcpy(rhs.keys[0 .. B - 1], child_n.keys[B..max_keys]);
            @memcpy(rhs.values[0 .. B - 1], child_n.values[B..max_keys]);

            // For internal nodes, top half of children pointers adopted by rhs node
            if (child_h > 0) {
                @memcpy(
                    Internal.cast(rhs).children[0..B],
                    Internal.cast(child_n).children[B..max_children],
                );
            }

            // Save median value to push to parent, shrink split halves
            const mid_key = child_n.keys[median];
            const mid_val = child_n.values[median];
            child_n.len = min_keys;
            rhs.len = min_keys;

            // Make room for new child pointer at idx + 1 in parent
            // Pushing up the median means there is also an additional child
            const p_len = parent.data.len;
            @memmove(
                parent.children[idx + 2 .. p_len + 2],
                parent.children[idx + 1 .. p_len + 1], // shift idx + 1.. right
            );
            parent.children[idx + 1] = rhs; // insert rhs, original child_n is still lhs

            // Push up median value to parent, insertAt handles key/value shift and len bump
            insertAt(&parent.data, idx, mid_key, mid_val);
        }

        /// Finds `key`, inserting it if missing. When `found_existing` is false the
        /// value is undefined and must be written by the caller via `val_ptr`.
        /// Returned pointers are invalidated by the next mutation of the tree.
        pub fn getOrPut(self: *Self, alloc: Allocator, key: K) Allocator.Error!GetOrPutResult {

            // Empty tree: root is a single leaf
            const root = self.root orelse {
                const leaf = try createLeaf(alloc);
                insertAt(leaf, 0, key, undefined);
                self.root = leaf;
                self.len = 1;
                return .{ .key_ptr = &leaf.keys[0], .val_ptr = &leaf.values[0], .found_existing = false };
            };

            // Root is full: grow a new root above it (the only way height increases at this stage)
            if (root.isFull()) {
                const new_root = try createInternal(alloc);
                errdefer alloc.destroy(new_root);
                new_root.children[0] = root;
                try splitChild(alloc, new_root, 0, self.height);
                // Only commit once the split succeeded
                self.root = &new_root.data;
                self.height += 1;
            }

            // Top down descend, splitting full children before entering
            var node = self.root.?; // assumed safe by this point
            var h = self.height;
            while (true) {
                const r = searchNode(node, key);
                if (r.found) {
                    return .{ .key_ptr = &node.keys[r.idx], .val_ptr = &node.values[r.idx], .found_existing = true };
                }
                if (h == 0) {
                    // Leaf, not found: insert key now, value left for the caller
                    insertAt(node, r.idx, key, undefined);
                    self.len += 1;
                    return .{ .key_ptr = &node.keys[r.idx], .val_ptr = &node.values[r.idx], .found_existing = false };
                }

                // Is Internal, assumed by this point
                const parent = Internal.cast(node);
                var idx = r.idx;
                if (parent.children[idx].isFull()) {
                    try splitChild(alloc, parent, idx, h - 1);
                    // Median sits at node.keys[idx], determine side base on comparison
                    switch (compare(key, node.keys[idx])) {
                        .eq => return .{ .key_ptr = &node.keys[r.idx], .val_ptr = &node.values[r.idx], .found_existing = true },
                        .gt => idx += 1, // rhs
                        .lt => {}, // idx already equals lhs
                    }
                }
                node = parent.children[idx]; // descend
                h -= 1;
            }
        }

        /// Insert or overwrite key with value, returning old key value pair if found existing
        pub fn fetchPut(self: *Self, alloc: Allocator, key: K, value: V) Allocator.Error!?KV {
            const res = try self.getOrPut(alloc, key);
            const old: ?KV = if (res.found_existing) .{ .key = res.key_ptr.*, .val = res.val_ptr.* } else null;
            res.val_ptr.* = value;
            return old;
        }

        /// Insert or overwrite `key` with `value`
        pub fn put(self: *Self, alloc: Allocator, key: K, value: V) Allocator.Error!void {
            const res = try self.getOrPut(alloc, key);
            res.val_ptr.* = value;
        }

        // -- Validation and correctness helpers

        /// Validates that:
        /// - Empty tree has len = 0 and height = 0
        /// - Non empty tree has len > 0
        /// - Tree length = sum of all KV pairs
        /// - Root node not empty if initialized
        fn validate(self: *const Self) ValidationError!void {
            const node = self.root orelse {
                if (self.height > 0 or self.len > 0) return error.CountMismatch;
                return;
            };
            if (node.len == 0) return error.EmptyRoot;
            if (self.len != try validateNode(node, self.height, true, null, null)) return error.CountMismatch;
        }

        /// Helper to recursively sum children nodes during validation
        /// Each node is validates such that:
        /// - Has at most max_keys keys
        /// - Non root nodes have atleast min_keys
        /// - Keys are incresing according to compare logic
        /// - Every key lies strictly within (lo, hi) inherited from ancestors, AKA. all nodes sorted
        fn validateNode(node: *const Leaf, h: u32, is_root: bool, lo: ?K, hi: ?K) ValidationError!usize {

            // Length and size checks
            const n_keys: usize = node.len;
            if (n_keys > max_keys) return error.NodeOverfull;
            if (!is_root and n_keys < min_keys) return error.NodeUnderfull;

            // Keys sorted within node, and within bounds from ancestors
            for (node.keys[0..n_keys], 0..) |key, i| {
                if (i > 0 and compare(node.keys[i - 1], key) != .lt) return error.KeysNotSorted;
                if (lo) |l| {
                    if (compare(l, key) != .lt) return error.KeyOutOfBounds;
                }
                if (hi) |u| {
                    if (compare(key, u) != .lt) return error.KeyOutOfBounds;
                }
            }

            var total_kv_pairs: usize = n_keys;
            if (h != 0) {
                // Is Internal, recurse children with tightened bounds and sum their KV pairs
                const internal = Internal.castConst(node);

                // node.len is slots used, children.len could be unused capacity
                for (internal.children[0 .. n_keys + 1], 0..) |child, i| {
                    const c_lo = if (i == 0) lo else node.keys[i - 1];
                    const c_hi = if (i == n_keys) hi else node.keys[i];
                    total_kv_pairs += try validateNode(child, h - 1, false, c_lo, c_hi);
                }
            }
            return total_kv_pairs;
        }
    };
}

// --- TESTING
const testing = std.testing;
const Tree = BTree(u32, u32, 2, std.math.order);

/// Insert keys in the given order, validating after every put, then check every value.
fn fillAndCheck(keys: []const u32) !void {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    for (keys) |k| {
        try t.put(testing.allocator, k, k * 10);
        try t.validate();
    }
    try testing.expectEqual(keys.len, t.count());
    for (keys) |k| try testing.expectEqual(@as(?u32, k * 10), t.get(k));
}

test "empty tree" {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    try testing.expectEqual(@as(?u32, null), t.get(1));
    try testing.expect(!t.contains(1));
    try testing.expectEqual(@as(usize, 0), t.count());
    try t.validate();
}

test "ascending inserts" {
    var keys: [500]u32 = undefined;
    for (&keys, 0..) |*k, i| k.* = @intCast(i);
    try fillAndCheck(&keys);
}

test "descending inserts" {
    var keys: [500]u32 = undefined;
    for (&keys, 0..) |*k, i| k.* = @intCast(keys.len - i);
    try fillAndCheck(&keys);
}

test "shuffled inserts" {
    var keys: [500]u32 = undefined;
    for (&keys, 0..) |*k, i| k.* = @intCast(i);
    var prng = std.Random.DefaultPrng.init(0xb7ee);
    prng.random().shuffle(u32, &keys);
    try fillAndCheck(&keys);
}

test "overwrite keeps count" {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    for (0..100) |i| try t.put(testing.allocator, @intCast(i), 1);
    for (0..100) |i| try t.put(testing.allocator, @intCast(i), 2);
    try t.validate();
    try testing.expectEqual(@as(usize, 100), t.count());
    for (0..100) |i| try testing.expectEqual(@as(?u32, 2), t.get(@intCast(i)));
}

test "missing keys return null" {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    for (0..100) |i| try t.put(testing.allocator, @intCast(i * 2), 0); // evens only
    for (0..100) |i| try testing.expect(!t.contains(@intCast(i * 2 + 1))); // odds absent
}

/// Drain `it`, expecting even keys first, first + 2, .., last (value = key * 10), or nothing if `first` is null
fn expectRun(it: anytype, first: ?u32, last: u32) !void {
    var want = first;
    while (it.next()) |e| {
        try testing.expect(want != null);
        try testing.expectEqual(want.?, e.key_ptr.*);
        try testing.expectEqual(want.? * 10, e.val_ptr.*);
        want = if (want.? == last) null else want.? + 2;
    }
    try testing.expectEqual(@as(?u32, null), want);
}

/// Even keys 10..1008 inserted shuffled, then check full iteration, min/max and every bound query
fn checkOrdered(comptime b: usize) !void {
    const T = BTree(u32, u32, b, std.math.order);
    var t: T = .empty;
    defer t.deinit(testing.allocator);

    const lo = 10;
    const hi = 1008;
    var keys: [500]u32 = undefined;
    for (&keys, 0..) |*k, i| k.* = @intCast(lo + i * 2);
    var prng = std.Random.DefaultPrng.init(b);
    prng.random().shuffle(u32, &keys);
    for (keys) |k| try t.put(testing.allocator, k, k * 10);
    try t.validate();

    var all = t.iterator();
    try expectRun(&all, lo, hi);

    try testing.expectEqual(@as(u32, lo), t.min().?.key_ptr.*);
    try testing.expectEqual(@as(u32, hi), t.max().?.key_ptr.*);

    // Queries below, between, on and above the stored keys
    var q: u32 = 0;
    while (q <= hi + 5) : (q += 1) {
        const ge: u32 = if (q < lo) lo else if (q % 2 == 0) q else q + 1;
        const gt: u32 = if (q < lo) lo else if (q % 2 == 0) q + 2 else q + 1;
        var lb = t.lowerBound(q);
        try expectRun(&lb, if (ge <= hi) ge else null, hi);
        var ub = t.upperBound(q);
        try expectRun(&ub, if (gt <= hi) gt else null, hi);
    }
}

test "iterator, bounds and min/max across node sizes" {
    try checkOrdered(2);
    try checkOrdered(3);
    try checkOrdered(16);
}

test "iteration on empty tree" {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    var it = t.iterator();
    try testing.expect(it.next() == null);
    var lb = t.lowerBound(5);
    try testing.expect(lb.next() == null);
    var ub = t.upperBound(5);
    try testing.expect(ub.next() == null);
    try testing.expect(t.min() == null);
    try testing.expect(t.max() == null);
}

test "range query [lo, hi)" {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    for (0..1000) |i| try t.put(testing.allocator, @intCast(i), 1);

    var sum: u32 = 0;
    var n: u32 = 0;
    var it = t.lowerBound(250);
    while (it.next()) |e| {
        if (e.key_ptr.* >= 750) break;
        sum += e.key_ptr.*;
        n += 1;
    }
    try testing.expectEqual(@as(u32, 500), n);
    try testing.expectEqual(@as(u32, (250 + 749) * 500 / 2), sum);
}

test "iterator values are mutable in place" {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    for (0..100) |i| try t.put(testing.allocator, @intCast(i), 0);
    var it = t.iterator();
    while (it.next()) |e| e.val_ptr.* = e.key_ptr.* + 1;
    for (0..100) |i| try testing.expectEqual(@as(?u32, @intCast(i + 1)), t.get(@intCast(i)));
}

fn strOrder(a: []const u8, b: []const u8) Order {
    return std.mem.order(u8, a, b);
}

test "iterator frees owned keys" {
    const StrTree = BTree([]const u8, u32, 2, strOrder);
    const alloc = testing.allocator;
    var t: StrTree = .empty;
    defer t.deinit(alloc);

    for (0..200) |i| {
        const key = try std.fmt.allocPrint(alloc, "key-{d:0>4}", .{i});
        try t.put(alloc, key, @intCast(i));
    }
    try testing.expectEqualStrings("key-0000", t.min().?.key_ptr.*);
    try testing.expectEqualStrings("key-0199", t.max().?.key_ptr.*);

    // testing.allocator fails the test if any key leaks
    var it = t.iterator();
    while (it.next()) |e| alloc.free(e.key_ptr.*);
}

test "fetchPut returns previous pair" {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    try testing.expectEqual(@as(?Tree.KV, null), try t.fetchPut(testing.allocator, 7, 70));
    const old = (try t.fetchPut(testing.allocator, 7, 71)).?;
    try testing.expectEqual(@as(u32, 7), old.key);
    try testing.expectEqual(@as(u32, 70), old.val);
    try testing.expectEqual(@as(?u32, 71), t.get(7));
    try testing.expectEqual(@as(usize, 1), t.count());
}
