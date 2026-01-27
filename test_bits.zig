const std = @import("std");
const mem = std.mem;
const expect = std.testing.expect;

const B = packed struct(u16) {
    b0: u1,
    b1: u1,
    b2: u1,
    b3: u1,
    b4: u1,
    b5: u1,
    b6: u1,
    b7: u1,
    b8: u1,
    b9: u1,
    b10: u1,
    b11: u1,
    b12: u1,
    b13: u1,
    b14: u1,
    b15: u1,
};

test "packed struct" {
    var b: B = @bitCast(@as(u16, 0));
    const b_slice = @as([*]u8, @ptrCast(&b))[0..2];
    const u16_ptr = @as(*u16, @ptrCast(&b)); 

    b.b0 = 1; // this should set 0x0100
    try expect(mem.eql(u8, b_slice, &[_]u8{0x01, 0x00}));

    // setting underlying to 0 resets all the bits
    u16_ptr.* = 0;
    b.b1 = 1; // this should set 0x0200
    std.debug.print("bytes are {x} {x}\n", .{ b_slice[0], b_slice[1] });
    try expect(mem.eql(u8, b_slice, &[_]u8{0x02, 0x00}));

    u16_ptr.* = 0;
    b.b4 = 1; // this should set 0x1000
    try expect(mem.eql(u8, b_slice, &[_]u8{0x10, 0x00}));

    u16_ptr.* = 0;
    b.b7 = 1; // this should set 0x8000
    try expect(mem.eql(u8, b_slice, &[_]u8{0x80, 0x00}));

    // b8 and upwards will update the second byte
    u16_ptr.* = 0;
    b.b8 = 1; // this should set 0x0001
    try expect(mem.eql(u8, b_slice, &[_]u8{0x00, 0x01}));

    u16_ptr.* = 0;
    b.b15 = 1; // this should set 0x0080
    try expect(mem.eql(u8, b_slice, &[_]u8{0x00, 0x80}));
}

const S = extern struct {
    flg1: u8 = 0,
    flg2: u8 = 0,
};

test "extern struct" {
    var s: S align(16) = .{}; // use defaults
    const s_slice = @as([*]u8, @ptrCast(&s))[0..2];
    const u16_ptr = @as(*u16, @ptrCast(&s)); 
    
    s.flg1 |= 0x80;
    try expect(mem.eql(u8, s_slice, &[_]u8{0x80, 0x00}));

    u16_ptr.* = 0;
    s.flg1 |= 0x40;
    try expect(mem.eql(u8, s_slice, &[_]u8{0x40, 0x00}));

    u16_ptr.* = 0;
    s.flg1 |= 0x01;
    try expect(mem.eql(u8, s_slice, &[_]u8{0x01, 0x00}));

    u16_ptr.* = 0;
    s.flg2 |= 0x80;
    try expect(mem.eql(u8, s_slice, &[_]u8{0x00, 0x80}));    
}
