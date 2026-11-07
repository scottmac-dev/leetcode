const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Order = std.math.Order;

/// In memory BTree
pub fn BTree(comptime K: type, comptime V: type, comptime B: usize, comptime compareFn: anytype) type {
    comptime assert(B >= 2); // BTree with node < 2 is just BST
    const max_keys = 2 * B - 1;

    return struct {
        const Self = @This();
        const Len = std.math.IntFittingRange(0, max_keys);

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
        };

        /// Embeds a leaf nodes data and points at children nodes, used for mid tree nodes so not all
        /// leaf nodes require children pointer arrays
        const Internal = struct {
            data: Leaf, // first pos to align *Internal as *Leaf
            // always one more pointer than node
            // * L * L *
            children: [max_keys + 1]*Leaf = undefined,

            fn cast(leaf: *Leaf) *Internal {
                return @fieldParentPtr("data", leaf);
            }
        };

        // --- Life cycle

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
            n.* = .{}; // initialize
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
        pub fn get(self: *Self, key: K) ?V {
            return if (self.getPtr(key)) |p| p.* else null;
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
        fn splitChild(alloc: Allocator, parent: *Internal, idx: usize, child_h: u32) Allocator.Error!void {}

        /// Put used to insert new KV into BTree, split nodes when full
        pub fn put(self: *Self, alloc: Allocator, key: K, value: V) Allocator.Error!void {}
    };
}

/// TESTING
const testing = std.testing;

// test "put/get ascending, B=2" {
//     var t: BTree(u32, u32, 2, std.math.order) = .{};
//     defer t.deinit(std.testing.allocator);
//     for (0..1000) |i| try t.put(std.testing.allocator, @intCast(i), @intCast(i * 10));
//     for (0..1000) |i| try std.testing.expectEqual(@as(?u32, @intCast(i * 10)), t.get(@intCast(i)));
//     try std.testing.expectEqual(@as(?u32, null), t.get(5000));
// }
