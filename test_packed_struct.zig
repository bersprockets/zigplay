const std = @import("std");
const mem = std.mem;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const native_endian = @import("builtin").target.cpu.arch.endian();

const S = packed struct(u16) {
    a: u3,
    b: u3,
    c: u10,
};

test "packed struct" {
    var s: S = @bitCast(@as(u16, 0));
    const int_ptr: *u16 = @ptrCast(&s);
    
    std.debug.print("BE: 0x{X:0>4}\n", .{ int_ptr.* });
    // after setting the following, the big endian bit pattern is
    // 0000 0000 0000 0101 or 0x0005
    s.a = 5;
    std.debug.print("BE: 0x{X:0>4}\n", .{ int_ptr.* });
    try expectEqual(0x0005, int_ptr.*);
    
    // after setting the following, the big endian bit pattern is
    // 0000 0000 0000 1101 or 0x000d
    s.b = 1;
    std.debug.print("BE: 0x{X:0>4}\n", .{ int_ptr.* });
    try expectEqual(0x000d, int_ptr.*);

    // after setting the following, the big endian bit pattern is
    // 0000 0000 0001 0101 or 0x0015
    s.b = 2;
    std.debug.print("BE: 0x{X:0>4}\n", .{ int_ptr.* });
    try expectEqual(0x0015, int_ptr.*);

    // after setting the following, the big endian bit pattern is
    // 0000 0000 0101 0101 or 0x0055
    s.c = 1;
    std.debug.print("BE: 0x{X:0>4}\n", .{ int_ptr.* });
    try expectEqual(0x0055, int_ptr.*);

    // after setting the following, the big endian bit pattern is
    // 0000 0000 0100 0101 or 0x0045
    s.b = 0;
    std.debug.print("BE: 0x{X:0>4}\n", .{ int_ptr.* });
    try expectEqual(0x0045, int_ptr.*);

    // note, however, on little endian systems, the actual memory layout will be different
    if (native_endian == .little) {
        const s_slice = @as([*]u8, @ptrCast(&s))[0..2];
        std.debug.print("LE: 0x{x:0>2}{x:0>2}\n", .{ s_slice[0], s_slice[1] });
        // in little endian, the bytes will be reversed
        try expect(mem.eql(u8, s_slice, &[_]u8{0x45, 0x00}));
    }
}
