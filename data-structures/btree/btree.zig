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
        fn searchNode(node: *const Leaf, key: K) struct { idx: usize, found: bool } {
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

        /// Put used to insert new KV into BTree, split nodes when full
        pub fn put(self: *Self, alloc: Allocator, key: K, value: V) Allocator.Error!void {
            // Empty tree: root is a single leaf
            const root = self.root orelse {
                const leaf = try createLeaf(alloc);
                insertAt(leaf, 0, key, value);
                self.root = leaf;
                self.len = 1;
                return;
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
                    node.values[r.idx] = value; // unique keys, reassign value only
                    return;
                }
                if (h == 0) {
                    // Is leaf
                    insertAt(node, r.idx, key, value); // room guaranteed, split on descend
                    self.len += 1;
                    return;
                }

                const parent = Internal.cast(node);
                var idx = r.idx;
                if (parent.children[idx].isFull()) {
                    try splitChild(alloc, parent, idx, h - 1);
                    // Median sits at node.keys[idx], determine side base on comparison
                    switch (compare(key, node.keys[idx])) {
                        .eq => {
                            node.values[idx] = value; // match on promoted key, reassign val
                            return;
                        },
                        .gt => idx += 1, // rhs
                        .lt => {}, // idx already equals lhs
                    }
                }
                node = parent.children[idx]; // descend
                h -= 1;
            }
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
