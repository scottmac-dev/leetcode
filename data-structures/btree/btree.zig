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

/// Context that orders keys with std.math.order, for integers, floats, bools and enums
pub fn AutoContext(comptime K: type) type {
    return struct {
        pub fn order(_: @This(), a: K, b: K) Order {
            return std.math.order(a, b);
        }
    };
}

/// Target bytes of keys + values in a full node when B is chosen automatically, the same target
/// Abseil's btree uses. Internal nodes also carry 2B child pointers on top of this.
pub const default_node_bytes = 256;

/// Largest B whose full node (2B - 1 entries) fits its keys and values into default_node_bytes,
/// at least 2. For example u32 -> u32 gives B = 16 (31 entries, 248 bytes).
pub fn defaultB(comptime K: type, comptime V: type) usize {
    const entry_bytes = @max(1, @sizeOf(K) + @sizeOf(V));
    return @max(2, (default_node_bytes / entry_bytes + 1) / 2);
}

/// Ordered map with B picked from the key and value sizes, see `defaultB`.
/// Use `BTreeWithB` to choose B yourself.
pub fn BTree(comptime K: type, comptime V: type, comptime Context: type) type {
    return BTreeWithB(K, V, Context, defaultB(K, V));
}

/// BTree ordered by std.math.order, see AutoContext
pub fn AutoBTree(comptime K: type, comptime V: type) type {
    return BTree(K, V, AutoContext(K));
}

/// In memory ordered map from K to V, with nodes holding between B - 1 and 2B - 1 keys.
/// `BTree` picks B for you. Larger B means fewer, wider nodes: shallower trees and better cache
/// use, but more entries moved on each insert or remove.
///
/// Ordering: `Context` provides `fn order(ctx: Context, a: K, b: K) std.math.Order`, the same
/// shape as std.HashMap contexts. The tree stores one Context value and passes it to every
/// comparison, so it can carry outside state such as a lookup table or a collation setting.
/// Zero-sized contexts can start from `.empty`; contexts with state use `init(ctx)`.
///
/// Memory ownership: the tree allocates and frees its own nodes, nothing else. Keys and values
/// are copied in by value and are never freed or deep copied by the tree. If K or V owns memory
/// (for example a heap allocated []const u8), the caller frees it, typically by walking
/// `iterator()` before `deinit`. This is the same convention as std.HashMap.
///
/// Pointer and iterator stability: any mutating call (`getOrPut`, `put`, `fetchPut`, `remove`,
/// `fetchRemove`, `popFirst`, `popLast`, `clearAndFree`) invalidates every key/value pointer and
/// every iterator previously obtained from the tree, whether or not the call changed anything.
/// Splits and merges move entries between nodes, so old pointers can silently point at the
/// wrong entry. With runtime safety on (Debug, ReleaseSafe), an iterator used after a mutation
/// panics. Pointers returned by `getPtr`, `min`, `max` and `getOrPut` are not checked.
pub fn BTreeWithB(comptime K: type, comptime V: type, comptime Context: type, comptime B: usize) type {
    comptime assert(B >= 2); // BTree with node < 2 is just BST
    const max_keys = 2 * B - 1; // 2B - 1 , ensures always a median split node
    const max_children = max_keys + 1; // Always extra child pointer, eg. * K * K *
    const median = B - 1;
    const min_keys = median;
    const Len = u16;
    comptime assert(max_children <= std.math.maxInt(Len)); // children index = len + 1 must fit

    switch (@typeInfo(Context)) {
        .@"struct", .@"union", .@"enum" => if (!@hasDecl(Context, "order")) @compileError(
            "BTree context " ++ @typeName(Context) ++ " must declare `fn order(ctx, a: K, b: K) std.math.Order`",
        ),
        else => {}, // e.g. a pointer to a context, checked at the call site
    }

    // Iterator misuse detection, compiled out when runtime safety is off (ReleaseFast/Small)
    const safety = std.debug.runtime_safety;
    const Version = if (safety) u64 else void;

    return struct {
        const Self = @This();

        /// Empty tree, only for zero-sized contexts. Use `init` for a context with state.
        /// Does not allocate.
        pub const empty: Self = if (@sizeOf(Context) == 0)
            .{ .ctx = undefined }
        else
            @compileError("BTree.empty needs a zero-sized Context, use BTree.init(ctx) for " ++ @typeName(Context));

        /// Empty tree that orders keys with `ctx`. Does not allocate.
        pub fn init(ctx: Context) Self {
            return .{ .ctx = ctx };
        }

        fn compare(ctx: Context, a: K, b: K) Order {
            return ctx.order(a, b);
        }

        // --- Properties

        root: ?*Leaf = null,
        len: usize = 0,
        height: u32 = 0, // 0 => root is leaf
        ctx: Context,
        version: Version = if (safety) 0 else {}, // bumped on every mutation, checked by iterators

        /// Called at the start of every mutating function
        fn bumpVersion(self: *Self) void {
            if (safety) self.version +%= 1;
        }

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

        /// Pointers to a key and value stored in the tree. Valid until the next mutating call.
        /// Write through `val_ptr` freely. Never change the key's ordering through `key_ptr`.
        pub const Entry = struct {
            key_ptr: *const K,
            val_ptr: *V,
        };

        // --- Life cycle

        /// Number of key/value pairs. Does not allocate, cannot fail.
        pub fn count(self: *const Self) usize {
            return self.len;
        }

        /// Free every node, leaving `self` undefined. Does not allocate, cannot fail.
        /// Keys and values are not freed. If they own memory, free them first by walking
        /// `iterator()`. `alloc` must be the allocator used for every insert.
        pub fn deinit(self: *Self, alloc: Allocator) void {
            if (self.root) |r| freeNode(alloc, r, self.height);
            self.* = undefined;
        }

        /// Free every node and reset to an empty tree, keeping the context. Does not allocate,
        /// cannot fail. Keys and values are not freed, as with `deinit`. Mutating call:
        /// invalidates all earlier pointers and iterators.
        pub fn clearAndFree(self: *Self, alloc: Allocator) void {
            self.bumpVersion(); // keep counting rather than reset, so stale iterators still trip
            if (self.root) |r| freeNode(alloc, r, self.height);
            self.root = null;
            self.len = 0;
            self.height = 0;
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

        /// Search a node to identify key position relative to stored keys.
        /// Binary search, since default B gives nodes of up to a few hundred keys.
        /// Returns the matching idx if found, else the idx of the first key > `key`
        /// (equivalently, the child to descend into).
        fn searchNode(ctx: Context, node: *const Leaf, key: K) SearchNodeResult {
            var lo: usize = 0;
            var hi: usize = node.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                switch (compare(ctx, key, node.keys[mid])) {
                    .lt => hi = mid, // search lhs
                    .gt => lo = mid + 1, // search rhs
                    .eq => return .{ .idx = mid, .found = true },
                }
            }
            return .{ .idx = lo, .found = false };
        }

        /// Whether `key` is present. Does not allocate, cannot fail.
        pub fn contains(self: *const Self, key: K) bool {
            return self.getPtr(key) != null;
        }

        /// Pointer to the value stored under `key`, null if absent. Does not allocate, cannot fail.
        /// The pointer is valid until the next mutating call.
        pub fn getPtr(self: *const Self, key: K) ?*V {
            var node = self.root orelse return null; // empty BTree
            var h = self.height; // start height, decremented as we descend
            while (true) {
                const r = searchNode(self.ctx, node, key);
                if (r.found) return &node.values[r.idx]; // found
                if (h == 0) return null; // exhausted search, not found
                node = Internal.cast(node).children[r.idx]; // descend to search children
                h -= 1; // decrement to track height
            }
        }

        /// Copy of the value stored under `key`, null if absent. Does not allocate, cannot fail.
        pub fn get(self: *const Self, key: K) ?V {
            return if (self.getPtr(key)) |p| p.* else null;
        }

        /// Entry with the smallest key, null if empty. Does not allocate, cannot fail.
        /// The pointers are valid until the next mutating call.
        pub fn min(self: *const Self) ?Entry {
            var node = self.root orelse return null;
            var h = self.height;
            while (h > 0) : (h -= 1) node = Internal.cast(node).children[0]; // leftmost path
            return .{ .key_ptr = &node.keys[0], .val_ptr = &node.values[0] };
        }

        /// Entry with the largest key, null if empty. Does not allocate, cannot fail.
        /// The pointers are valid until the next mutating call.
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
        /// Any mutating call on the tree invalidates the iterator. With runtime safety on, `next`
        /// panics if that happened. The iterator also points back at the tree, so don't move or
        /// copy the tree value while iterating.
        pub const Iterator = struct {
            const Frame = struct { node: *Leaf, idx: Len };

            stack: [max_depth]Frame = undefined,
            depth: u8 = 0, // frames in use, 0 => exhausted
            height: u32 = 0, // tree height, the frame at level == height is a leaf
            tree: if (safety) *const Self else void,
            version: Version, // tree.version when this iterator was created

            /// Next entry in sorted key order, null when exhausted. Does not allocate, cannot fail.
            /// The entry's pointers are valid until the next mutating call on the tree.
            pub fn next(it: *Iterator) ?Entry {
                if (safety and it.tree.version != it.version) {
                    @panic("BTree iterator used after the tree was modified");
                }
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
            return .{
                .height = self.height,
                .tree = if (safety) self else {},
                .version = self.version,
            };
        }

        /// Iterator over every entry in ascending key order. Does not allocate, cannot fail.
        /// Invalidated by the next mutating call on the tree.
        pub fn iterator(self: *const Self) Iterator {
            var it = self.emptyIterator();
            if (self.root) |r| it.pushLeftmost(r);
            return it;
        }

        /// Iterator starting at the first entry with key >= `key`, running to the end.
        /// Does not allocate, cannot fail. Invalidated by the next mutating call on the tree.
        /// For a range [lo, hi), call `lowerBound(lo)` and stop at the first key >= hi.
        pub fn lowerBound(self: *const Self, key: K) Iterator {
            return self.seek(key, .lower);
        }

        /// Iterator starting at the first entry with key > `key`, running to the end.
        /// Does not allocate, cannot fail. Invalidated by the next mutating call on the tree.
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
                const r = searchNode(self.ctx, node, key);
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

        /// Find `key`, inserting it if missing.
        /// - found_existing = false: `key` is now stored, and the value is undefined until the
        ///   caller writes it through `val_ptr`.
        /// - found_existing = true: the stored key is kept and `key` is not stored. If `key` owns
        ///   memory, the caller still owns it and must free it.
        ///
        /// Allocates: up to one node per level when full nodes split on the way down, plus one
        /// for a new root. The first insert into an empty tree allocates a leaf.
        /// Errors: error.OutOfMemory. The key is then not inserted and the tree's contents are
        /// unchanged. Nodes may already have been split, so the tree stays valid but its shape
        /// may differ.
        /// Mutating call: invalidates all earlier pointers and iterators, even when the key was
        /// already present. The returned pointers are valid until the next mutating call.
        pub fn getOrPut(self: *Self, alloc: Allocator, key: K) Allocator.Error!GetOrPutResult {
            self.bumpVersion();

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
                const r = searchNode(self.ctx, node, key);
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
                    switch (compare(self.ctx, key, node.keys[idx])) {
                        .eq => return .{ .key_ptr = &node.keys[r.idx], .val_ptr = &node.values[r.idx], .found_existing = true },
                        .gt => idx += 1, // rhs
                        .lt => {}, // idx already equals lhs
                    }
                }
                node = parent.children[idx]; // descend
                h -= 1;
            }
        }

        /// Insert `key` -> `value`, or overwrite the value if `key` is present and return the old
        /// pair. When a pair is returned, `.key` is the stored key, which stays in the tree and is
        /// still owned by it. The passed `key` is not stored, so free that one if it owns memory.
        /// `.val` was removed from the tree and now belongs to the caller.
        ///
        /// Allocates and fails like `getOrPut`: error.OutOfMemory leaves the contents unchanged.
        /// Mutating call: invalidates all earlier pointers and iterators.
        pub fn fetchPut(self: *Self, alloc: Allocator, key: K, value: V) Allocator.Error!?KV {
            const res = try self.getOrPut(alloc, key);
            const old: ?KV = if (res.found_existing) .{ .key = res.key_ptr.*, .val = res.val_ptr.* } else null;
            res.val_ptr.* = value;
            return old;
        }

        /// Insert `key` -> `value`, or overwrite the value if `key` is present. When overwriting, the
        /// old value is dropped without being freed and the passed `key` is not stored. Use
        /// `fetchPut` or `getOrPut` if either one owns memory.
        ///
        /// Allocates and fails like `getOrPut`: error.OutOfMemory leaves the contents unchanged.
        /// Mutating call: invalidates all earlier pointers and iterators.
        pub fn put(self: *Self, alloc: Allocator, key: K, value: V) Allocator.Error!void {
            const res = try self.getOrPut(alloc, key);
            res.val_ptr.* = value;
        }

        // --- Remove

        /// Remove and return the entry at idx, shifting later entries left
        fn removeAt(node: *Leaf, idx: usize) KV {
            assert(idx < node.len);
            const len = node.len;
            const kv: KV = .{ .key = node.keys[idx], .val = node.values[idx] };
            @memmove(node.keys[idx .. len - 1], node.keys[idx + 1 .. len]);
            @memmove(node.values[idx .. len - 1], node.values[idx + 1 .. len]);
            node.len -= 1;
            return kv;
        }

        /// Free a single node, as the type it was created with
        fn destroyNode(alloc: Allocator, node: *Leaf, h: u32) void {
            if (h == 0) alloc.destroy(node) else alloc.destroy(Internal.cast(node));
        }

        /// Inverse of splitChild: children[i], separator keys[i] and children[i + 1] become one
        /// node at children[i]. The parent loses a key and a child, children[i + 1] is freed.
        ///     * L * K * R *   =>   * [L K R] *
        fn mergeChildren(alloc: Allocator, parent: *Internal, i: usize, child_h: u32) void {
            const left = parent.children[i];
            const right = parent.children[i + 1];
            const l_len: usize = left.len;
            const r_len: usize = right.len;
            assert(l_len + 1 + r_len <= max_keys);

            // Separator drops down to the end of left, right's entries follow it
            left.keys[l_len] = parent.data.keys[i];
            left.values[l_len] = parent.data.values[i];
            @memcpy(left.keys[l_len + 1 .. l_len + 1 + r_len], right.keys[0..r_len]);
            @memcpy(left.values[l_len + 1 .. l_len + 1 + r_len], right.values[0..r_len]);
            if (child_h > 0) {
                @memcpy(
                    Internal.cast(left).children[l_len + 1 .. l_len + 2 + r_len],
                    Internal.cast(right).children[0 .. r_len + 1],
                );
            }
            left.len = @intCast(l_len + 1 + r_len);

            // Close the gap in the parent: child i + 1, then key i
            const p_len = parent.data.len;
            @memmove(parent.children[i + 1 .. p_len], parent.children[i + 2 .. p_len + 1]);
            _ = removeAt(&parent.data, i);
            destroyNode(alloc, right, child_h);
        }

        /// Rotate right: children[i] gains separator keys[i - 1] at its front, and the left
        /// sibling's last entry (and last child) moves up / across to replace it
        fn borrowFromLeft(parent: *Internal, i: usize, child_h: u32) void {
            const child = parent.children[i];
            const left = parent.children[i - 1];
            const l_last: usize = left.len - 1;

            insertAt(child, 0, parent.data.keys[i - 1], parent.data.values[i - 1]);
            if (child_h > 0) {
                const cc = &Internal.cast(child).children;
                const c_len = child.len; // already includes the new key
                @memmove(cc[1 .. c_len + 1], cc[0..c_len]);
                cc[0] = Internal.cast(left).children[l_last + 1];
            }
            parent.data.keys[i - 1] = left.keys[l_last];
            parent.data.values[i - 1] = left.values[l_last];
            left.len -= 1;
        }

        /// Rotate left: children[i] gains separator keys[i] at its end, and the right sibling's
        /// first entry (and first child) moves up / across to replace it
        fn borrowFromRight(parent: *Internal, i: usize, child_h: u32) void {
            const child = parent.children[i];
            const right = parent.children[i + 1];
            const c_len: usize = child.len;

            insertAt(child, c_len, parent.data.keys[i], parent.data.values[i]);
            if (child_h > 0) {
                const rc = &Internal.cast(right).children;
                Internal.cast(child).children[c_len + 1] = rc[0];
                const r_len: usize = right.len;
                @memmove(rc[0..r_len], rc[1 .. r_len + 1]);
            }
            const first = removeAt(right, 0);
            parent.data.keys[i] = first.key;
            parent.data.values[i] = first.val;
        }

        /// Top up children[i] to more than min_keys before descending into it, so removing one
        /// entry below can never underflow. Borrows from a sibling that can spare an entry, else
        /// merges with one. Returns the index to descend into, which moves left by one when
        /// merging into the left sibling.
        fn ensureChildCanLose(alloc: Allocator, parent: *Internal, i: usize, child_h: u32) usize {
            if (parent.children[i].len > min_keys) return i;
            const p_len = parent.data.len;
            assert(p_len > 0); // an internal node always has a sibling to work with
            if (i > 0 and parent.children[i - 1].len > min_keys) {
                borrowFromLeft(parent, i, child_h);
                return i;
            }
            if (i < p_len and parent.children[i + 1].len > min_keys) {
                borrowFromRight(parent, i, child_h);
                return i;
            }
            if (i < p_len) {
                mergeChildren(alloc, parent, i, child_h);
                return i;
            }
            mergeChildren(alloc, parent, i - 1, child_h);
            return i - 1;
        }

        const RemoveTarget = union(enum) { key: K, first, last };

        /// Top down removal, mirroring getOrPut's top down splits. Each child is topped up to
        /// more than min_keys before descending, so the final leaf removal never underflows and
        /// nothing is revisited on the way back up.
        /// - key in a leaf: remove it directly
        /// - key in an internal node: swap in its predecessor (or successor) taken from a child
        ///   that can spare one, or merge the two children around it and keep descending
        /// - first / last: follow the leftmost / rightmost path to a leaf
        fn removeImpl(self: *Self, alloc: Allocator, target_in: RemoveTarget) ?KV {
            self.bumpVersion();
            var node = self.root orelse return null;
            var h = self.height;
            var target = target_in;
            // Internal slot holding the matched key, refilled by its predecessor/successor
            var slot: ?struct { node: *Leaf, idx: usize } = null;

            const removed: ?KV = while (true) {
                if (h == 0) {
                    const idx: usize = switch (target) {
                        .key => |k| blk: {
                            const r = searchNode(self.ctx, node, k);
                            if (!r.found) break null; // absent, nothing removed
                            break :blk r.idx;
                        },
                        .first => 0,
                        .last => node.len - 1,
                    };
                    const kv = removeAt(node, idx);
                    const s = slot orelse break kv;
                    // kv is the neighbour, move it into the matched key's slot and return that
                    const out: KV = .{ .key = s.node.keys[s.idx], .val = s.node.values[s.idx] };
                    s.node.keys[s.idx] = kv.key;
                    s.node.values[s.idx] = kv.val;
                    break out;
                }

                const parent = Internal.cast(node);
                const i: usize = switch (target) {
                    .first => 0,
                    .last => node.len,
                    .key => |k| blk: {
                        const r = searchNode(self.ctx, node, k);
                        if (!r.found) break :blk r.idx;
                        // Key sits in this internal node
                        if (parent.children[r.idx].len > min_keys) {
                            slot = .{ .node = node, .idx = r.idx };
                            target = .last; // predecessor: rightmost entry of the left subtree
                            node = parent.children[r.idx];
                        } else if (parent.children[r.idx + 1].len > min_keys) {
                            slot = .{ .node = node, .idx = r.idx };
                            target = .first; // successor: leftmost entry of the right subtree
                            node = parent.children[r.idx + 1];
                        } else {
                            // Neither side can spare one: merge, the key drops into the merged child
                            mergeChildren(alloc, parent, r.idx, h - 1);
                            node = parent.children[r.idx];
                        }
                        h -= 1;
                        continue;
                    },
                };
                node = parent.children[ensureChildCanLose(alloc, parent, i, h - 1)];
                h -= 1;
            };

            // A merge under a one key root, or removing the last entry, empties the root
            const root = self.root.?;
            if (root.len == 0) {
                if (self.height == 0) {
                    alloc.destroy(root);
                    self.root = null;
                } else {
                    self.root = Internal.cast(root).children[0];
                    alloc.destroy(Internal.cast(root));
                    self.height -= 1;
                }
            }
            if (removed != null) self.len -= 1;
            return removed;
        }

        /// Remove `key` and return its entry, or null if absent. The returned key and value now
        /// belong to the caller, so free them here if they own memory.
        /// Does not allocate, cannot fail. Frees nodes emptied by merges with `alloc`.
        /// Mutating call: invalidates all earlier pointers and iterators, even if `key` was absent.
        pub fn fetchRemove(self: *Self, alloc: Allocator, key: K) ?KV {
            return self.removeImpl(alloc, .{ .key = key });
        }

        /// Remove `key`, returning whether it was present. Drops the stored key and value without
        /// freeing them; use `fetchRemove` if they own memory.
        /// Does not allocate, cannot fail. Frees nodes emptied by merges with `alloc`.
        /// Mutating call: invalidates all earlier pointers and iterators, even if `key` was absent.
        pub fn remove(self: *Self, alloc: Allocator, key: K) bool {
            return self.fetchRemove(alloc, key) != null;
        }

        /// Remove and return the entry with the smallest key, null if empty. The entry now belongs
        /// to the caller. Does not allocate, cannot fail. Frees nodes emptied by merges with `alloc`.
        /// Mutating call: invalidates all earlier pointers and iterators.
        pub fn popFirst(self: *Self, alloc: Allocator) ?KV {
            return self.removeImpl(alloc, .first);
        }

        /// Remove and return the entry with the largest key, null if empty. The entry now belongs
        /// to the caller. Does not allocate, cannot fail. Frees nodes emptied by merges with `alloc`.
        /// Mutating call: invalidates all earlier pointers and iterators.
        pub fn popLast(self: *Self, alloc: Allocator) ?KV {
            return self.removeImpl(alloc, .last);
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
            if (self.len != try validateNode(self.ctx, node, self.height, true, null, null)) return error.CountMismatch;
        }

        /// Helper to recursively sum children nodes during validation
        /// Each node is validates such that:
        /// - Has at most max_keys keys
        /// - Non root nodes have atleast min_keys
        /// - Keys are incresing according to compare logic
        /// - Every key lies strictly within (lo, hi) inherited from ancestors, AKA. all nodes sorted
        fn validateNode(ctx: Context, node: *const Leaf, h: u32, is_root: bool, lo: ?K, hi: ?K) ValidationError!usize {

            // Length and size checks
            const n_keys: usize = node.len;
            if (n_keys > max_keys) return error.NodeOverfull;
            if (!is_root and n_keys < min_keys) return error.NodeUnderfull;

            // Keys sorted within node, and within bounds from ancestors
            for (node.keys[0..n_keys], 0..) |key, i| {
                if (i > 0 and compare(ctx, node.keys[i - 1], key) != .lt) return error.KeysNotSorted;
                if (lo) |l| {
                    if (compare(ctx, l, key) != .lt) return error.KeyOutOfBounds;
                }
                if (hi) |u| {
                    if (compare(ctx, key, u) != .lt) return error.KeyOutOfBounds;
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
                    total_kv_pairs += try validateNode(ctx, child, h - 1, false, c_lo, c_hi);
                }
            }
            return total_kv_pairs;
        }
    };
}

/// Ordered set with B picked from the key size, see `defaultB`. Use `BTreeSetWithB` to choose B.
pub fn BTreeSet(comptime K: type, comptime Context: type) type {
    return BTreeSetWithB(K, Context, defaultB(K, void));
}

/// BTreeSet ordered by std.math.order, see AutoContext
pub fn AutoBTreeSet(comptime K: type) type {
    return BTreeSet(K, AutoContext(K));
}

/// Ordered set of K, a thin wrapper over a BTreeWithB(K, void, ..) map. Ownership, context and
/// invalidation rules are the map's: the set frees nodes only, and any mutating call
/// (`insert`, `remove`, `fetchRemove`, `popFirst`, `popLast`, `clearAndFree`) invalidates
/// iterators. Use `fetchRemove`, `popFirst`, `popLast` or `iterator` to get at keys that own
/// memory so you can free them.
pub fn BTreeSetWithB(comptime K: type, comptime Context: type, comptime B: usize) type {
    return struct {
        const Self = @This();
        pub const Map = BTreeWithB(K, void, Context, B);

        /// Underlying map, for anything the set doesn't wrap
        map: Map,

        /// Empty set, only for zero-sized contexts. Does not allocate.
        pub const empty: Self = .{ .map = .empty };

        /// Empty set that orders keys with `ctx`. Does not allocate.
        pub fn init(ctx: Context) Self {
            return .{ .map = .init(ctx) };
        }

        /// Free every node, leaving `self` undefined. Keys are not freed. Does not allocate.
        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.map.deinit(alloc);
        }

        /// Free every node and reset to empty, keeping the context. Keys are not freed.
        /// Does not allocate. Mutating call.
        pub fn clearAndFree(self: *Self, alloc: Allocator) void {
            self.map.clearAndFree(alloc);
        }

        /// Number of keys. Does not allocate, cannot fail.
        pub fn count(self: *const Self) usize {
            return self.map.count();
        }

        /// Add `key`, returning true if it was newly added. If an equal key is already stored it
        /// is kept and `key` is not stored, so the caller still owns `key`.
        /// Allocates like BTree.getOrPut. Errors: error.OutOfMemory, the set is then unchanged.
        /// Mutating call: invalidates all earlier iterators, even when `key` was present.
        pub fn insert(self: *Self, alloc: Allocator, key: K) Allocator.Error!bool {
            const res = try self.map.getOrPut(alloc, key);
            return !res.found_existing;
        }

        /// Whether `key` is present. Does not allocate, cannot fail.
        pub fn contains(self: *const Self, key: K) bool {
            return self.map.contains(key);
        }

        /// Remove `key`, returning whether it was present. Does not allocate, cannot fail.
        /// Mutating call: invalidates all earlier iterators.
        pub fn remove(self: *Self, alloc: Allocator, key: K) bool {
            return self.map.remove(alloc, key);
        }

        /// Remove `key` and return the stored key (which now belongs to the caller), or null.
        /// Does not allocate, cannot fail. Mutating call: invalidates all earlier iterators.
        pub fn fetchRemove(self: *Self, alloc: Allocator, key: K) ?K {
            return if (self.map.fetchRemove(alloc, key)) |kv| kv.key else null;
        }

        /// Smallest key, null if empty. Does not allocate, cannot fail.
        pub fn min(self: *const Self) ?K {
            return if (self.map.min()) |e| e.key_ptr.* else null;
        }

        /// Largest key, null if empty. Does not allocate, cannot fail.
        pub fn max(self: *const Self) ?K {
            return if (self.map.max()) |e| e.key_ptr.* else null;
        }

        /// Remove and return the smallest key, null if empty. Does not allocate, cannot fail.
        /// Mutating call: invalidates all earlier iterators.
        pub fn popFirst(self: *Self, alloc: Allocator) ?K {
            return if (self.map.popFirst(alloc)) |kv| kv.key else null;
        }

        /// Remove and return the largest key, null if empty. Does not allocate, cannot fail.
        /// Mutating call: invalidates all earlier iterators.
        pub fn popLast(self: *Self, alloc: Allocator) ?K {
            return if (self.map.popLast(alloc)) |kv| kv.key else null;
        }

        /// Ascending iterator yielding keys only. Same rules as BTree.Iterator: invalidated by
        /// any mutating call, checked when runtime safety is on.
        pub const Iterator = struct {
            inner: Map.Iterator,

            /// Next key in ascending order, null when exhausted. Does not allocate, cannot fail.
            pub fn next(it: *Iterator) ?K {
                return if (it.inner.next()) |e| e.key_ptr.* else null;
            }
        };

        /// Iterator over every key in ascending order. Does not allocate, cannot fail.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.map.iterator() };
        }

        /// Iterator starting at the first key >= `key`. Does not allocate, cannot fail.
        pub fn lowerBound(self: *const Self, key: K) Iterator {
            return .{ .inner = self.map.lowerBound(key) };
        }

        /// Iterator starting at the first key > `key`. Does not allocate, cannot fail.
        pub fn upperBound(self: *const Self, key: K) Iterator {
            return .{ .inner = self.map.upperBound(key) };
        }
    };
}

// --- TESTING
const testing = std.testing;
/// Small B keeps nodes tiny so trees get deep and every split, borrow and merge path runs
fn TestTree(comptime b: usize) type {
    return BTreeWithB(u32, u32, AutoContext(u32), b);
}
const Tree = TestTree(2);

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
fn checkOrdered(comptime T: type) !void {
    var t: T = .empty;
    defer t.deinit(testing.allocator);

    const lo = 10;
    const hi = 1008;
    var keys: [500]u32 = undefined;
    for (&keys, 0..) |*k, i| k.* = @intCast(lo + i * 2);
    var prng = std.Random.DefaultPrng.init(0x5eed);
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
    try checkOrdered(TestTree(2));
    try checkOrdered(TestTree(3));
    try checkOrdered(TestTree(16));
    try checkOrdered(AutoBTree(u32, u32));
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

const StrContext = struct {
    pub fn order(_: StrContext, a: []const u8, b: []const u8) Order {
        return std.mem.order(u8, a, b);
    }
};

test "iterator frees owned keys" {
    const StrTree = BTreeWithB([]const u8, u32, StrContext, 2);
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

/// Keys are IDs into a table, ordered by the names they point at
const NameIdContext = struct {
    names: []const []const u8,
    pub fn order(ctx: NameIdContext, a: u32, b: u32) Order {
        return std.mem.order(u8, ctx.names[a], ctx.names[b]);
    }
};

test "stateful context orders IDs through a table" {
    const names = [_][]const u8{ "delta", "alpha", "charlie", "bravo", "echo" };
    const IdTree = BTreeWithB(u32, void, NameIdContext, 2);
    var t = IdTree.init(.{ .names = &names });
    defer t.deinit(testing.allocator);
    for (0..names.len) |i| try t.put(testing.allocator, @intCast(i), {});
    try t.validate();

    // Ascending by name: alpha(1) bravo(3) charlie(2) delta(0) echo(4)
    const want = [_]u32{ 1, 3, 2, 0, 4 };
    var it = t.iterator();
    for (want) |id| try testing.expectEqual(id, it.next().?.key_ptr.*);
    try testing.expect(it.next() == null);

    var ub = t.upperBound(2); // after charlie
    try testing.expectEqual(@as(u32, 0), ub.next().?.key_ptr.*);
    try testing.expectEqual(@as(u32, 1), t.min().?.key_ptr.*);
    try testing.expectEqual(@as(u32, 4), t.max().?.key_ptr.*);
}

test "case insensitive context" {
    const Ctx = struct {
        pub fn order(_: @This(), a: []const u8, b: []const u8) Order {
            return std.ascii.orderIgnoreCase(a, b);
        }
    };
    var t: BTreeWithB([]const u8, u32, Ctx, 2) = .empty;
    defer t.deinit(testing.allocator);
    try t.put(testing.allocator, "Hello", 1);
    try t.put(testing.allocator, "HELLO", 2);
    try testing.expectEqual(@as(usize, 1), t.count());
    try testing.expectEqual(@as(?u32, 2), t.get("hello"));
    try testing.expectEqualStrings("Hello", t.min().?.key_ptr.*); // first key stored is kept
}

test "every mutating call bumps the version" {
    if (!std.debug.runtime_safety) return error.SkipZigTest;
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    try t.put(testing.allocator, 1, 1);

    const it = t.iterator();
    try testing.expectEqual(t.version, it.version);
    try t.put(testing.allocator, 1, 2); // existing key, still a mutation
    try testing.expect(t.version != it.version); // it.next() would now panic
    _ = try t.getOrPut(testing.allocator, 1);
    _ = try t.fetchPut(testing.allocator, 2, 2);
    try testing.expectEqual(it.version + 3, t.version);
}

/// Random inserts and removes checked against a reference, validating structure after every op
fn checkRandomOps(comptime T: type, seed: u64) !void {
    const n = 600;
    var t: T = .empty;
    defer t.deinit(testing.allocator);
    var present: [n]bool = @splat(false);
    var live: usize = 0;
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    for (0..6000) |step| {
        const k = rand.uintLessThan(u32, n);
        // Insert-heavy first half, remove-heavy second half, so the tree grows then shrinks
        const insert_bias: u32 = if (step < 3000) 70 else 30;
        if (rand.uintLessThan(u32, 100) < insert_bias) {
            try t.put(testing.allocator, k, k * 10);
            if (!present[k]) live += 1;
            present[k] = true;
        } else {
            const got = t.fetchRemove(testing.allocator, k);
            if (present[k]) {
                try testing.expectEqual(k, got.?.key);
                try testing.expectEqual(k * 10, got.?.val);
                live -= 1;
            } else try testing.expect(got == null);
            present[k] = false;
        }
        try t.validate();
        try testing.expectEqual(live, t.count());
    }
    for (present, 0..) |p, k| try testing.expectEqual(p, t.contains(@intCast(k)));
}

test "random inserts and removes keep the tree valid" {
    try checkRandomOps(TestTree(2), 1);
    try checkRandomOps(TestTree(3), 2);
    try checkRandomOps(TestTree(4), 3);
    try checkRandomOps(AutoBTree(u32, u32), 4);
}

test "remove everything, in several orders, then reuse" {
    const orders = [_]enum { ascending, descending, shuffled }{ .ascending, .descending, .shuffled };
    for (orders) |order| {
        var t: Tree = .empty;
        defer t.deinit(testing.allocator);
        var keys: [500]u32 = undefined;
        for (&keys, 0..) |*k, i| k.* = @intCast(i);
        for (keys) |k| try t.put(testing.allocator, k, k);

        switch (order) {
            .ascending => {},
            .descending => std.mem.reverse(u32, &keys),
            .shuffled => {
                var prng = std.Random.DefaultPrng.init(0xdead);
                prng.random().shuffle(u32, &keys);
            },
        }
        for (keys) |k| {
            try testing.expect(t.remove(testing.allocator, k));
            try testing.expect(!t.remove(testing.allocator, k)); // already gone
            try t.validate();
        }
        try testing.expectEqual(@as(usize, 0), t.count());
        try testing.expect(t.root == null);
        try testing.expectEqual(@as(u32, 0), t.height);

        try t.put(testing.allocator, 42, 1); // usable again
        try testing.expectEqual(@as(?u32, 1), t.get(42));
    }
}

test "remove on empty tree" {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    try testing.expect(!t.remove(testing.allocator, 1));
    try testing.expect(t.popFirst(testing.allocator) == null);
    try testing.expect(t.popLast(testing.allocator) == null);
}

test "popFirst and popLast drain in order" {
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    var keys: [300]u32 = undefined;
    for (&keys, 0..) |*k, i| k.* = @intCast(i);
    var prng = std.Random.DefaultPrng.init(7);
    prng.random().shuffle(u32, &keys);
    for (keys) |k| try t.put(testing.allocator, k, k * 10);

    // Take from both ends alternately, like a double ended priority queue
    var lo: u32 = 0;
    var hi: u32 = 299;
    while (t.count() > 0) {
        const first = t.popFirst(testing.allocator).?;
        try testing.expectEqual(lo, first.key);
        try testing.expectEqual(lo * 10, first.val);
        lo += 1;
        try t.validate();
        if (t.count() == 0) break;
        const last = t.popLast(testing.allocator).?;
        try testing.expectEqual(hi, last.key);
        hi -= 1;
        try t.validate();
    }
    try testing.expectEqual(hi + 1, lo); // met in the middle, nothing skipped
    try testing.expect(t.popFirst(testing.allocator) == null);
}

test "clearAndFree resets and keeps the context" {
    const names = [_][]const u8{ "b", "a", "c" };
    var t = BTreeWithB(u32, void, NameIdContext, 2).init(.{ .names = &names });
    defer t.deinit(testing.allocator);
    for (0..3) |i| try t.put(testing.allocator, @intCast(i), {});
    t.clearAndFree(testing.allocator); // testing.allocator catches leaked nodes
    try testing.expectEqual(@as(usize, 0), t.count());
    try testing.expect(t.min() == null);
    try t.validate();

    for (0..3) |i| try t.put(testing.allocator, @intCast(i), {});
    try testing.expectEqual(@as(u32, 1), t.min().?.key_ptr.*); // still ordered by name
}

test "set API" {
    var s: AutoBTreeSet(u32) = .empty;
    defer s.deinit(testing.allocator);

    try testing.expect(try s.insert(testing.allocator, 5));
    try testing.expect(!try s.insert(testing.allocator, 5)); // duplicate
    for ([_]u32{ 9, 1, 7, 3 }) |k| _ = try s.insert(testing.allocator, k);
    try testing.expectEqual(@as(usize, 5), s.count());
    try testing.expect(s.contains(7));
    try testing.expect(!s.contains(4));
    try testing.expectEqual(@as(?u32, 1), s.min());
    try testing.expectEqual(@as(?u32, 9), s.max());

    var it = s.iterator();
    for ([_]u32{ 1, 3, 5, 7, 9 }) |k| try testing.expectEqual(@as(?u32, k), it.next());
    try testing.expectEqual(@as(?u32, null), it.next());

    var lb = s.lowerBound(4);
    try testing.expectEqual(@as(?u32, 5), lb.next());
    var ub = s.upperBound(5);
    try testing.expectEqual(@as(?u32, 7), ub.next());

    try testing.expect(s.remove(testing.allocator, 5));
    try testing.expect(!s.remove(testing.allocator, 5));
    try testing.expectEqual(@as(?u32, 7), s.fetchRemove(testing.allocator, 7));
    try testing.expectEqual(@as(?u32, 1), s.popFirst(testing.allocator));
    try testing.expectEqual(@as(?u32, 9), s.popLast(testing.allocator));
    try testing.expectEqual(@as(usize, 1), s.count());

    s.clearAndFree(testing.allocator);
    try testing.expectEqual(@as(usize, 0), s.count());
}

test "set with owned keys freed by popping" {
    const alloc = testing.allocator;
    var s = BTreeSetWithB([]const u8, StrContext, 2).empty;
    defer s.deinit(alloc);
    for (0..100) |i| {
        const key = try std.fmt.allocPrint(alloc, "k{d:0>3}", .{i});
        if (!try s.insert(alloc, key)) alloc.free(key);
    }
    // A duplicate insert hands ownership back to the caller
    const dup = try alloc.dupe(u8, "k050");
    try testing.expect(!try s.insert(alloc, dup));
    alloc.free(dup);

    const removed = s.fetchRemove(alloc, "k050").?;
    try testing.expectEqualStrings("k050", removed);
    alloc.free(removed);

    var prev: []const u8 = "";
    while (s.popFirst(alloc)) |key| {
        try testing.expect(std.mem.order(u8, prev, key) == .lt);
        if (prev.len > 0) alloc.free(prev);
        prev = key;
    }
    alloc.free(prev);
}

test "defaultB sizes nodes to about 256 bytes" {
    try testing.expectEqual(@as(usize, 16), defaultB(u32, u32)); // 31 * 8 = 248 bytes
    try testing.expectEqual(@as(usize, 8), defaultB(u64, u64)); // 15 * 16 = 240 bytes
    try testing.expectEqual(@as(usize, 16), defaultB(u64, void)); // sets carry keys only
    try testing.expectEqual(@as(usize, 6), defaultB([]const u8, u32)); // 11 * 20 = 220 bytes
    try testing.expectEqual(@as(usize, 2), defaultB([512]u8, u8)); // huge entries floor at 2
    inline for (.{ u8, u32, u64, [3]u64 }) |K| {
        const b = defaultB(K, u32);
        try testing.expect((2 * b - 1) * (@sizeOf(K) + @sizeOf(u32)) <= default_node_bytes);
    }
}

test "removes and clears bump the version" {
    if (!std.debug.runtime_safety) return error.SkipZigTest;
    var t: Tree = .empty;
    defer t.deinit(testing.allocator);
    for (0..10) |i| try t.put(testing.allocator, @intCast(i), 0);
    const v = t.version;
    _ = t.remove(testing.allocator, 3);
    _ = t.remove(testing.allocator, 99); // absent still counts
    _ = t.popFirst(testing.allocator);
    _ = t.popLast(testing.allocator);
    t.clearAndFree(testing.allocator);
    try testing.expectEqual(v + 5, t.version);
}
