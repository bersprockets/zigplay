const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;

pub fn BTree(t: u16) type {
    return struct {
        const Self = @This();
        allocator: Allocator,
        t: u16 = t,
        root: *BTreeNode,

        const maxT: u16 = 2 * t - 1;
        
        const BTreeNode = struct {
            const InnerSelf = @This();
            keys: [maxT]?u64 = [_]?u64 {null} ** maxT,
            children: [maxT + 1]?*InnerSelf  = [_]?*InnerSelf {null} ** (maxT + 1),
            n: u16 = 0,
            leaf: bool = true,
        };

        fn split_child(self: Self, parent: *BTreeNode, child_index: usize) !void {
            const new_child = try self.allocator.create(BTreeNode);
            new_child.* = .{}; // init with default settings
            
            const child = parent.children[child_index].?;
            new_child.leaf = child.leaf;
            assert(child.n == (2 * self.t) - 1);
            const new_key = child.keys[self.t - 1].?;
            if (!child.leaf) {
                for (0..self.t) | i | {
                    new_child.children[i] = child.children[i + self.t];
                }
            }

            for (0..self.t - 1) | i | {
                new_child.keys[i] = child.keys[i + self.t];
            }

            new_child.n = self.t - 1;

            // This essentially 'truncates' the key list in the original child
            child.n = self.t - 1;

            // clean up unused child slots. As an optimization we could leave this out
            for (self.t..child.children.len) | i | {
                child.children[i] = null;
            }

            // clean-up unused key slots. As an optimization we could leave this out
            for ((self.t - 1)..child.keys.len) | i | {
                child.keys[i] = null;
            }

            // the number of children is one greater than the number of keys
            var curr_idx: i32 = @as(i32, @intCast(parent.n));
            while (curr_idx + 1 > child_index) {
                parent.children[@intCast(curr_idx + 1)] = parent.children[@intCast(curr_idx)];
                curr_idx -= 1;
            }
            parent.children[child_index + 1] = new_child;
            curr_idx = @as(i32, @intCast(parent.n)) - 1;
            while (curr_idx + 1 > child_index) {
                parent.keys[@intCast(curr_idx + 1)] = parent.keys[@intCast(curr_idx)];
                curr_idx -= 1;
            }
            parent.keys[child_index] = new_key;
            parent.n += 1;

            try self.disk_write(new_child);
            try self.disk_write(child);
            try self.disk_write(parent);
        }
   
        pub fn contains_key(self: Self, key: u64) bool {
            return self.find_key(self.root, key);
        }

        fn find_key(self: Self, node: *BTreeNode, k: u64) bool {
            var index: u64 = 0;
            while (index < node.n and k > node.keys[index].?) : (index += 1) {}

            return if (index < node.n and k == node.keys[index]) true
            else if (node.leaf) false
            else self.find_key(node.children[index].?, k);
        }

        pub fn insert(self: *Self, k: u64) !void {
            if (self.root.n == 0) {
                self.root.keys[0] = k;
                self.root.n = 1;
            } else if (self.root.n == (2 * self.t) - 1) {
                if (self.get_key_index(self.root, k)) |_| {
                    return;
                }
                const new_root = try self.allocator.create(BTreeNode);
                new_root.* = .{}; // set up with default values
                new_root.leaf = false;
                new_root.children[0] = self.root;
                self.root = new_root;

                // Now we have a new root that has the old root as a child.
                // Split the old root, which will pull up a key into the new root
                try self.split_child(new_root, 0);
                try self.insert_nonfull(new_root, k);
            } else {
                try self.insert_nonfull(self.root, k);
            }
        }

        fn insert_nonfull(self: *Self, node: *BTreeNode, k: u64) !void {
            if (self.get_key_index(node, k)) |_| {
                return;
            }

            var index: i32 = node.n - 1;
            
            // If this is a leaf node, we insert into this node
            if (node.leaf) {
                // make space for the new key: find each key that is greater than
                // the new key, and move each key up one slot.
                while (index >= 0 and k < node.keys[@intCast(index)].?) {
                    const us_index = @as(usize, @intCast(index));
                    node.keys[us_index + 1] = node.keys[us_index];
                    index -= 1;
                }
                node.keys[@intCast(index + 1)] = k;
                node.n += 1;

                try self.disk_write(node);
            } else {
                // find the first key that's greater than our new key, if it exists
                while (index >= 0 and k < node.keys[@intCast(index)].?) {
                    index -= 1;
                }
                
                index = index + 1;
                var us_index = @as(usize, @intCast(index));
                try self.disk_read(node.children[us_index].?);
                if (node.children[us_index].?.n == (2 * self.t) - 1) {
                    if (self.get_key_index(node.children[us_index].?, k)) |_| {
                        return;
                    }
                    try self.split_child(node, us_index);
                    if (k > node.keys[us_index].?) {
                        us_index += 1;
                    }
                }
                try self.insert_nonfull(node.children[us_index].?, k);
            }
        }

        pub fn delete(self: *Self, k: u64) void {
            const r = self.root;
            const index_opt = self.get_key_index(r, k);
            if (index_opt != null and r.leaf) {
                self.delete_from_leaf(r, index_opt.?);
            } else {
                self.delete2(self.root, k);
            }
            
            if (r.n == 0) {
                const old_root = self.root;
                self.root = r.children[0].?;
                self.allocator.destroy(old_root);
            }
        }
        
        fn delete_from_leaf(self: Self, node: *BTreeNode, index: u64) void {
            _ = self;
            node.keys[index] = null;
            for (index + 1..node.n) | i | {
                node.keys[i - 1] = node.keys[i];
            }
            node.n -= 1;
            for (node.n..node.keys.len) | i | {
                node.keys[i] = null;
            }
        }
        
        fn delete2(self: *Self, node: *BTreeNode, k: u64) void {
            const index_opt = self.get_key_index(node, k);
            if (index_opt) | index | {
                // CLR case #1
                if (node.leaf) {
                    self.delete_from_leaf(node, index);
                    return;
                }
                
                // CLR case 2a
                if (node.children[index].?.n >= self.t) {
                    const predecessor = self.find_max_key(node.children[index].?);
                    self.delete2(node.children[index].?, predecessor);
                    node.keys[index] = predecessor;
                    return;
                }
                
                // CLR case 2b
                if (node.children[index + 1].?.n >= self.t) {
                    const successor = self.find_min_key(node.children[index + 1].?);
                    self.delete2(node.children[index + 1].?, successor);
                    node.keys[index] = successor;
                    return;
                }

                // CLR case 2c
                // Merge the predecessor child and the successor child, making k the median key. Then remove k from node
                const child1 = node.children[index].?;
                const child2 = node.children[index + 1].?;
                child1.keys[child1.n] = k; // note that there is already an appropriate child at child1.children[child1.n],
                                           // at least in the case where child1 is not a leaf node
                child1.n += 1;
                for (0..child2.n) | i | {
                    child1.keys[child1.n + i] = child2.keys[i];
                    child1.children[child1.n + i] = child2.children[i];
                }
                child1.n += child2.n;
                // There's one more child than there are keys
                child1.children[child1.n] = child2.children[child2.n];

                // remove child2 reference from node
                for (index + 1..node.n) | i | {
                    node.children[i] = node.children[i + 1];
                }

                self.allocator.destroy(child2);
                
                // remove k from node (because we moved it to child1)
                for (index..node.n - 1) | i | {
                    node.keys[i] = node.keys[i + 1];
                }
                node.n -= 1;

                for (node.n..(2 * self.t - 1)) | i | {
                    node.keys[i] = null;
                }
                for (node.n + 1..(2 * self.t)) | i | {
                    node.children[i] = null;
                }

                assert(self.get_key_index(node.children[index].?, k) != null);
                self.delete2(node.children[index].?, k);
            } else {
                if (node.leaf) {
                    return;
                }
                var index: u64 = 0;
                while (index < node.n and k > node.keys[index].?) {
                    index += 1;
                }
                const child = node.children[index].?;
                if (child.n == self.t - 1) {
                    // check for siblings
                    var sibling_array: [2]*BTreeNode = undefined;
                    var sibling_i: u64 = 0;
                    if (index != 0) {
                        sibling_array[sibling_i] = node.children[index - 1].?;
                        sibling_i += 1;
                    }
                    if (index < node.n) {
                        sibling_array[sibling_i] = node.children[index + 1].?;
                        sibling_i += 1;
                    }
                    const siblings = sibling_array[0..sibling_i];
                    
                    var max_n: u16 = 0;
                    for (siblings) | sibling | {
                        if (sibling.n > max_n) max_n = sibling.n;
                    }
                    if (max_n == self.t - 1) {
                        // CLR case 3b
                        var sibling_index: u64 = 0;
                        var key_index: u64 = 0;
                        // if this is the last child, choose previous sibling
                        if (index == node.n) {
                            sibling_index = index; // this is a bit of a kludge
                            key_index = index - 1;
                        } else {
                            sibling_index = index + 1;
                            key_index = index;
                        }
                        const target_child = node.children[key_index].?;
                        const source_child = node.children[sibling_index].?;
                        target_child.keys[target_child.n] = node.keys[key_index];
                        target_child.n += 1;
                        for (0..source_child.n) | i | {
                            target_child.keys[target_child.n + i] = source_child.keys[i];
                        }
                        for (0..source_child.n + 1) | i | {
                            target_child.children[target_child.n + i] = source_child.children[i];
                        }
                        target_child.n += source_child.n;

                        for (key_index..node.n - 1) | i | {
                            node.keys[i] = node.keys[i + 1];
                        }
                        // in the case where index is the last child, this loop will not run,
                        // which is appropriate
                        for (key_index + 1..node.n) | i | {
                            node.children[i] = node.children[i + 1];
                        }
                        node.n -= 1;
                        for (node.n..node.keys.len) | i | {
                            node.keys[i] = null;
                        }
                        for (node.n + 1..node.children.len) | i | {
                            node.children[i] = null;
                        }

                        self.allocator.destroy(source_child);
                    
                        self.delete2(target_child, k);                         
                    } else {
                        // CLR case 3a
                        // We need to rotate left or right depending on which sibling has at least t keys
                        // If index is 0, then rotate left
                        // Else, if index is node.n, then rotate right
                        // Else, if sibling with at least t keys is on the right, then rotate left
                        // Else, rotate right
                        var rotate_left = false;
                        if (index == 0) {
                            rotate_left = true;
                        } else if (index == node.n) {
                            rotate_left = false;
                        } else if (node.children[index + 1].?.n >= self.t) {
                            rotate_left = true;
                        } else rotate_left = false;
                        if (rotate_left) {
                            const sibling = node.children[index + 1].?;
                            child.keys[child.n] = node.keys[index];
                            child.n += 1;
                            child.children[child.n] = sibling.children[0];
                            node.keys[index] = sibling.keys[0];
                            for (0..sibling.n - 1) | i | {
                                sibling.keys[i] = sibling.keys[i + 1];
                            }
                            for (0..sibling.n) | i | {
                                sibling.children[i] = sibling.children[i + 1];
                            }
                            sibling.n -= 1;
                            for (sibling.n..sibling.keys.len) | i | {
                                sibling.keys[i] = null;
                            }
                            for (sibling.n + 1..sibling.children.len) | i | {
                                sibling.children[i] = null;
                            }
                        } else {
                            // rotate right
                            const sibling = node.children[index - 1].?;
                            // make room in the child for the new key and child
                            var curr_idx: i32 = child.n;
                            while (curr_idx > 0) {
                                child.keys[@intCast(curr_idx)] = child.keys[@intCast(curr_idx - 1)];
                                curr_idx -= 1;
                            }
                            curr_idx = child.n + 1;
                            while (curr_idx > 0) {
                                child.children[@intCast(curr_idx)] = child.children[@intCast(curr_idx - 1)];
                                curr_idx -= 1;
                            }
                            child.keys[0] = node.keys[index - 1];
                            node.keys[index - 1] = sibling.keys[sibling.n - 1];
                            child.children[0] = sibling.children[sibling.n];
                            child.n += 1;
                            sibling.n -= 1;
                            for (sibling.n..sibling.keys.len) | i | {
                                sibling.keys[i] = null;
                            }
                            for (sibling.n + 1..sibling.children.len) | i | {
                                sibling.children[i] = null;
                            }    
                        }
                        self.delete2(child, k);
                    }

                } else {
                    self.delete2(child, k);
                }
            }
        }
        
        fn get_key_index(self: Self, node: *BTreeNode, k: u64) ?u64 {
            _ = self;
            for (0..node.n) | i | {
                if (node.keys[i].? == k) {
                    return i;
                }
            }
            return null;
        }

        fn find_max_key(self: Self, node: *BTreeNode) u64 {
            if (node.leaf) {
                return node.keys[node.n - 1].?;
            }
            return self.find_max_key(node.children[node.n].?);
        }

        fn find_min_key(self: Self, node: *BTreeNode) u64 {
            if (node.leaf) {
                return node.keys[0].?;
            }
            return self.find_min_key(node.children[0].?);
        }
        
        fn disk_read(self: Self, node: *BTreeNode) !void {
            _ = self;
            _ = node;
        }

        fn disk_write(self: Self, node: *BTreeNode) !void {
            _ = self;
            _ = node;
        }

        pub fn init(allocator: Allocator) !Self {
            const root = try allocator.create(BTreeNode);
            root.* = .{}; // init with default values

            return .{ .allocator = allocator, .root = root};
        }

        pub fn deinit(self: Self) void {
            // traverse the tree, releasing BTreeNode instances
            deinit2(self.root, self.allocator);
            self.allocator.destroy(self.root);
        }

        fn deinit2(node: *BTreeNode, allocator: Allocator) void {
            if (node.leaf) {
                return;
            }
            for (0..node.children.len) | i | {
                const child_maybe = node.children[i];
                if (child_maybe) | child | {
                    deinit2(child, allocator);
                    node.children[i] = null;
                    allocator.destroy(child);
                }
            }
        }

        pub fn traverse(self: Self, ally: Allocator) []usize {
            var elements = std.ArrayList(usize).empty;
            defer elements.deinit(ally);
            self.traverse_node(self.root, ally, &elements);
            const items = elements.items;
            const ptr = ally.allocate(usize, items.len);
            // can I just do ptr.* = items.*?
            for (0..items.len) | i | {
                ptr[i] = items[i];
            }
            return ptr[0..items.len];
        }

        pub fn traverse_node(self: Self, node: *BTreeNode, ally: Allocator, elements: *std.ArrayList) void {
            for (0..node.n) | i | {
                if (!node.leaf) {
                    self.traverse_node(node.children[i].?, ally, elements);
                }
                try elements.append(ally, node.keys[i].?);
            }

            if (!node.leaf) {
                self.traverse_node(node.children(node.n).?, ally, elements);
            }
        }

        pub fn tree_ok(self: Self) bool {
            return self.node_ok(self.root, true);
        }
        
        fn node_ok(self: Self, node: *BTreeNode, is_root: bool) bool {
            // 1) All nodes (except root) must have at least t-1 keys and, if not leaf node, t children.
            // 2) All nodes must have no more than 2t-1 keys and, if not leaf node, 2t children.
            // 3) Each key should be greater than the previous key
            // 4) All keys in child associated with keys[x] should be less than keys[x].
            // 5) The smallest key in child associated with keys[x] should be greater than
            //    keys[x-1] (for x = 1 to node.n)
            if (node.n == 0) {
                print("Node has n == 0\n", .{});
                return false;
            }
            if (node.n > self.t * 2 - 1) {
                print("Node has more than {d} keys\n", .{ self.t * 2 - 1 });
                return false;
            }
            if (!is_root) {
                if (node.n < self.t - 1) {
                    print("Node has less than {d} keys\n", .{ self.t - 1 });
                    return false;
                }
            }
            for (0..node.n) | i | {
                if (node.keys[i]) |_| {
                    // this is good
                } else {
                    print("Unexpected null key: {any}\n", .{ node });
                    return false;
                }
            }
            for (node.n..node.keys.len) | i | {
                if (node.keys[i]) |_| {
                    print("Unexpected non-null key in node {any}\n", .{ node });
                    return false;
                }
            }
            for (1..node.n) | i | {
                if (node.keys[i - 1].? > node.keys[i].?) {
                    print("Key {d} is greater than key {d}\n", .{ node.keys[i - 1].?, node.keys[i].? } );
                    return false;
                }
            }
            if (node.leaf) {
                for (0..node.children.len) | i | {
                    if (node.children[i]) |_| {
                        print("Unexpected non-null child in leaf node\n", .{});
                        return false;
                    }
                }
                return true;
            }
            for (0..(node.n + 1)) | i | {
                if (node.children[i]) |_| {
                    // happy path
                } else {
                    print("Unexpected null child\n", .{});
                    return false;
                }
            }
            for ((node.n + 1)..node.children.len) | i | {
                if (node.children[i]) |_| {
                    print("Unexpected non-null child\n", .{});
                    return false;
                }
            }

            var prev_child_opt: ?*BTreeNode = null;
            for (0..node.n) | i | {
                const k = node.keys[i].?;
                const c = node.children[i].?;
                var max_prev_child_k_opt: ?u64 = null;
                if (prev_child_opt) | prev_child | {
                    max_prev_child_k_opt = prev_child.keys[prev_child.n - 1];
                    if (max_prev_child_k_opt.? > k) {
                        print("Previous child's max key {d} is greater than key {d}\n", .{ max_prev_child_k_opt.?, k });
                        return false;
                    }
                }
                for (0..c.n) | j | {
                    const child_k = c.keys[j].?;
                    if (child_k >= k) {
                        print("Child's key {d} is greater than key {d}\n", .{ child_k, k });
                        return false;
                    }
                    if (max_prev_child_k_opt) | max_prev_child_k | {
                        if (max_prev_child_k >= child_k) {
                            print("Previous child's max key {d} is greater than child key {d}\n", .{ max_prev_child_k, child_k });
                            return false;
                        }
                    }
                }
                prev_child_opt = c;
            }

            const last_child = node.children[node.n].?;
            const last_key = node.keys[node.n - 1].?;
            for (0..last_child.n) | i | {
                if (last_key > last_child.keys[i].?) {
                    print("Final child's key {d} is less than key {d}\n", .{ last_child.keys[i].?, last_key });
                    return false;
                }
            }
            
            for (0..(node.n + 1)) | i | {
                if (!self.node_ok(node.children[i].?, false)) {
                    return false;
                }
            }
            
            return true;
        }

        pub fn print_btree(btree: *Self) !void {
            const path = ([_]u8 {'0'})[0..]; 
            try print_btree_level(btree.root, path);
        }

        fn print_btree_level(node: *BTreeNode, path: []const u8) !void {
            print("{s} n:{d}, leaf:{any} {any}\n", .{ path, node.n, node.leaf, node.keys });
            if (node.leaf) return;
            for (0..node.n + 1) | i | {
                var buf: [20]u8 = undefined;
                const next_path = try std.fmt.bufPrint(&buf, "{s}-{d}", .{ path, i });
                try print_btree_level(node.children[i].?, next_path);
            }
        }
    };
}

fn keys_expected(actual: []?u64, expected: []const u64) bool {
    if (actual.len != expected.len) return false;

    for (0..actual.len) | i | {
        if (actual[i]) | key | {
            if (key != expected[i]) return false;
        } else {
            return false;
        }
    }
    return true;
}

test "btree 1" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const BTreeType = BTree(4);
    var btree = try BTreeType.init(allocator);
    try btree.insert(13);
    try btree.insert(5);
    try btree.insert(9);
    try btree.insert(11);
    try btree.insert(3);
    try btree.insert(0);
    try btree.insert(15);

    // this insert should cause a split
    try btree.insert(6);

    // Now it should be
    //              9
    //  0, 3, 5, 6    11, 13, 15
    var runtime_known_end: u64 = 1;
    _ = &runtime_known_end;
    assert(keys_expected(btree.root.keys[0..1], &[_]u64{9}));
    var child = btree.root.children[0].?;
    assert(keys_expected(child.keys[0..4], &[_]u64{0, 3, 5, 6}));
    child = btree.root.children[1].?;
    assert(keys_expected(child.keys[0..3], &[_]u64{11, 13, 15}));
    assert(btree.tree_ok());
    try BTreeType.print_btree(&btree);
    
    btree.deinit();
    _ = gpa.deinit();
}


test "delete" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    const BTreeType = BTree(3);

    var btree = try BTreeType.init(allocator);
    defer btree.deinit();
    
    const keys = [_]u64 {80, 90, 77, 82, 65, 75, 89, 67, 71, 86, 68, 69, 76, 88, 66, 83, 85, 84, 79, 70, 78, 81, 74};
    
    for (keys) | key | {
        try btree.insert(key);
    }
    assert(btree.tree_ok());
    try BTreeType.print_btree(&btree);

    btree.delete(70);
    btree.delete(77);
    btree.delete(71);
    btree.delete(68);
    btree.delete(66);

    try BTreeType.print_btree(&btree);
    
    var parent = btree.root;
    assert(parent.n == 5);
    assert(keys_expected(btree.root.keys[0..5], &[_]u64{69, 76, 80, 84, 88}));
    assert(parent.children[0] != null);
    var child = parent.children[0].?;
    assert(child.n == 2);
    assert(keys_expected(child.keys[0..2], &[_]u64{65, 67}));
    child = parent.children[1].?;
    assert(child.n == 2);
    assert(keys_expected(child.keys[0..2], &[_]u64{74, 75}));
    child = parent.children[2].?;
    assert(child.n == 2);
    assert(keys_expected(child.keys[0..2], &[_]u64{78, 79}));
    child = parent.children[3].?;
    assert(child.n == 3);
    assert(keys_expected(child.keys[0..3], &[_]u64{81, 82, 83}));
    child = parent.children[4].?;
    assert(child.n == 2);
    assert(keys_expected(child.keys[0..2], &[_]u64{85, 86}));
    child = parent.children[5].?;
    assert(child.n == 2);
    assert(keys_expected(child.keys[0..2], &[_]u64{89, 90}));    
}

test "More delete" {
    print("More delete case\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    const BTreeType = BTree(3);

    var btree = try BTreeType.init(allocator);
    defer btree.deinit();
    
    const keys = [_]u64 { 127813, 194537, 41710, 36590, 28374, 149671, 79193, 54765, 175974, 73929, 322957, 38824, 83366, 199560, 330520, 226251, 305371, 117077, 194882, 182888, 217687, 70111, 156688, 140782, 315630, 303887, 97012, 193387, 308613, 278670, 124227, 21754, 282972, 72629, 20267 };
    
    for (keys) | key | {
        try btree.insert(key);
    }
    assert(btree.tree_ok());
    try BTreeType.print_btree(&btree);

    btree.delete(127813);
    assert(btree.tree_ok());
    print("------------------------------------------\n", .{});
    try BTreeType.print_btree(&btree);
    print("About to issue troublesome delete\n", .{});
    btree.delete(21754);
    print("------------------------------------------\n", .{});
    try BTreeType.print_btree(&btree);
    assert(btree.tree_ok());
}
    
