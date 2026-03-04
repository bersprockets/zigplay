const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;
const btree1 = @import("btree1.zig");
const BTree = btree1.BTree;

fn test_tree_deg_3(allocator: Allocator, keys: []u64, biggest_value: u64, delete_keys: []u64) !void {
    try test_tree(3, allocator, keys, biggest_value, delete_keys);
}

fn test_tree_deg_30(allocator: Allocator, keys: []u64, biggest_value: u64, delete_keys: []u64) !void {
    try test_tree(30, allocator, keys, biggest_value, delete_keys);
}

fn test_tree_deg_300(allocator: Allocator, keys: []u64, biggest_value: u64, delete_keys: []u64) !void {
    try test_tree(300, allocator, keys, biggest_value, delete_keys);
}

fn test_tree(comptime degree: u16, allocator: Allocator, keys: []u64, biggest_value: u64, delete_keys: []u64) !void {
    const BTreeType = BTree(degree);
    var btree = try BTreeType.init(allocator);
    defer btree.deinit();

    const remaining_keys_array = try allocator.alloc(u64, keys.len);
    defer allocator.free(remaining_keys_array);

    var delete_key_map = std.AutoHashMap(u64, bool).init(allocator);
    defer delete_key_map.deinit();

    for (delete_keys) | delete_key | {
        try delete_key_map.put(delete_key, true);
    }

    var remaining_key_count: u64 = 0;
    for (keys) | key | {
        if (!delete_key_map.contains(key)) {
            remaining_keys_array[remaining_key_count] = key;
            remaining_key_count += 1;
        }
    }
    const remaining_keys = remaining_keys_array[0..remaining_key_count];
    
    for (keys) | key | {
        try btree.insert(key);
    }
    
    for (keys) | key | {
        assert(btree.contains_key(key));
    }

    assert(!btree.contains_key(biggest_value + 2000));
    
    if (!btree.tree_ok()) {
        print("Bad tree\n", .{});
        print("Degree is {d}\n", .{ degree });
        print("Keys are {any}\n", .{ keys });
        assert(btree.tree_ok());
    }

    // delete the keys that are listed in delete_keys
    for (delete_keys) | delete_key | {
        btree.delete(delete_key);
    }

    // check that deleted keys are gone
    for (delete_keys) | delete_key | {
        if (btree.contains_key(delete_key)) {
            print("Deleted key {d} still in tree\n", .{ delete_key });
            print("Degree is {d}\n", .{ degree });
            print("Keys are {any}\n", .{ keys });
            print("Delete keys are {any}\n", .{ delete_keys });
            assert(1 == 2);
        }
    }

    // check that we didn't unexpectedly lose keys
    for (remaining_keys) | key | {
        if (!btree.contains_key(key)) {
            print("Remaining key {d} no longer in tree\n", .{ key });
            print("Degree is {d}\n", .{ degree });
            print("Keys are {any}\n", .{ keys });
            print("Delete keys are {any}\n", .{ delete_keys });
            assert(1 == 2);
        }
    }       
    
    if (!btree.tree_ok()) {
        print("Bad tree\n", .{});
        print("Degree is {d}\n", .{ degree });
        print("Keys are {any}\n", .{ keys });
        print("Delete keys are {any}\n", .{ delete_keys });
        assert(btree.tree_ok());
    }
}

pub fn main() !void {
    const keys_buffer_size = 3000;
    // for testing: const keys_buffer_size = 45;
    var keys_buffer = [_]u64{0} ** keys_buffer_size;
    var delete_keys_buffer = [_]u64{0} ** keys_buffer_size;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var t: std.Io.Threaded = .init_single_threaded;
    const io = t.io();
    const timestamp = std.Io.Clock.real.now(io);
    const seed: u64 = @intCast(timestamp.toMilliseconds());
    print("Seed is {d}\n", .{ seed });
    
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const smallest_size = 1;
    const biggest_size = keys_buffer_size;

    const funcs = [_] *const fn (allocator: Allocator, keys: []u64, biggest_value: u64, delete_keys: []u64) anyerror!void { test_tree_deg_3, test_tree_deg_30, test_tree_deg_300 };
    
    for (0..20000) | i | {
        if (i % 1000 == 0) {
            print("{d} iterations\n", .{ i });
        }
        const size = random.intRangeAtMost(u64, smallest_size, biggest_size);
        const smallest_value = 0;
        const biggest_value = size * 10000;

        for (0..size) | j | {
            const candidate = random.intRangeAtMost(u64, smallest_value, biggest_value);
            keys_buffer[j] = candidate;
        }
        const keys = keys_buffer[0..size];

        const percent_to_delete = @as(f32, @floatFromInt(random.intRangeAtMost(u64, 3, 5)))/10.0;
        const delete_count: u64 = @intFromFloat(@as(f32, @floatFromInt(keys.len)) * percent_to_delete);

        for (0..delete_count) | j | {
            const key_index = random.intRangeAtMost(u64, 0, keys.len - 1);
            delete_keys_buffer[j] = keys[key_index];
        }
        const delete_keys = delete_keys_buffer[0..delete_count];

        const func_idx = random.intRangeAtMost(u64, 0, funcs.len - 1);
        try funcs[func_idx](allocator,  keys, biggest_value, delete_keys);
    }
}
