const std = @import("std");
const this_module = @This();

const InstructionOption = enum {
    inoop,
    izero,
    ipush,
    ipop,
    istr,
    iget,
    iallocptr,
    idestroyptr,
    iand,
    ior,
    inot,
    ixor,
    iputc,
    ieputc,
    iputs,
    ieputs,
    igetc,
    igets,
    ijmp,
    ijc,
    ijeq,
    ijne,
    ijle,
    ijnle,
    ijls,
    ijnls,
    ijge,
    ijnge,
    ijgr,
    ijngr,
    ijproc,
    iproc,
    istruct,
    ifork,
    isys,
};

const Instruction = struct {
    instruction: InstructionOption,
    values: [3]this_module.Value,
};

const ValueOption = enum {
    size,
    float,
    string,
    registerident,
};

const Value = union(ValueOption) {
    size: usize,
    float: f128,
    string: []const u8,
    registerident: RegisterIdent,
};

pub const RegisterIdent = enum(u4) {
    r1 = 0x0,
    r2 = 0x1,
    r3 = 0x2,
    r4 = 0x3,
    r5 = 0x4,
    r6 = 0x5,
    r7 = 0x6,
    r8 = 0x7,
    r9 = 0x8,
    r10 = 0x9,
    r11 = 0xa,
    r12 = 0xb,
    r13 = 0xc,
    r14 = 0xd,
    r15 = 0xe,
    r16 = 0xf,
};

const Register = struct {
    value: Value,
};

pub const VMError = error{
    invalid_register,
    segmentation_fault,
    illegal_instruction,
    stack_overflow,
    register_collision,
};

const vm_stdin_max_alloc_size: usize = 1_024_000;
const vm_alloc_size: usize = 64;
pub const VM = struct {
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
    stdin: std.io.AnyReader,

    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    registers: [16]Register,
    stack: std.AutoHashMap(RegisterIdent, Register),
    instruction_vector: []Instruction,
    instruction_vector_size: usize,
    program_counter: usize,

    // testing function here.
    fn getValueFromRegister(self: *VM, register: RegisterIdent) Value {
        return self.registers[@intFromEnum(register)].value;
    }

    inline fn izero(self: *VM, register: RegisterIdent) void {
        self.registers[@intFromEnum(register)].value.size = 0;
    }

    inline fn istr(self: *VM, register: RegisterIdent, value: Value) void {
        self.registers[@intFromEnum(register)].value = value;
    }

    inline fn ipush(self: *VM, register: RegisterIdent) !void {
        self.stack.put(register, self.registers[@intFromEnum(register)]);
    }

    inline fn ipop(self: *VM, register: RegisterIdent) !void {
        self.stack.remove(register);
    }

    inline fn iputc(self: *VM, character: RegisterIdent) !void {
        try self.stdout.writeByte(self.registers[@intFromEnum(character)].value.size);
    }

    inline fn ieputc(self: *VM, character: RegisterIdent) !void {
        try self.stderr.writeByte(self.registers[@intFromEnum(character)].value.size);
    }

    inline fn igetc(self: *VM, character: RegisterIdent) !void {
        self.registers[@intFromEnum(character)].value.size = try self.stdin.readByte();
    }

    inline fn iputs(self: *VM, string: RegisterIdent) !void {
        try self.stdout.writeAll(self.registers[@intFromEnum(string)].value.string);
    }

    inline fn ieputs(self: *VM, string: RegisterIdent) !void {
        try self.stderr.writeAll(self.registers[@intFromEnum(string)].value.string);
    }

    inline fn igets(self: *VM, string: RegisterIdent) !void {
        self.registers[@intFromEnum(string)].value.string = try self.stdin.readAllAlloc(self.allocator, vm_stdin_max_alloc_size);
    }

    inline fn ifork(self: *VM, pid_register: RegisterIdent) !void {
        self.registers[@intFromEnum(pid_register)] = try std.os.fork();
    }

    /// instruction: the given instruction to append
    /// this **INLINE** function reallocs the instruction_vector each vm_alloc_size - 1
    pub inline fn appendInstruction(self: *VM, instruction: Instruction) !void {
        if ((self.instruction_vector_size % vm_alloc_size) == (vm_alloc_size - 1)) {
            self.instruction_vector = try self.allocator.realloc(self.instruction_vector, vm_alloc_size * @divTrunc(self.instruction_vector_size, vm_alloc_size));
        }
        self.instruction_vector_size += 1;
        self.instruction_vector[self.instruction_vector_size] = instruction;
    }

    pub inline fn compute(self: *VM) !void {
        for (0..self.instruction_vector_size) |is| {
            switch (self.instruction_vector[is].instruction) {
                .iputs => {
                    try self.iputs(self.instruction_vector[is].values[0].registerident);
                },
                .ieputs => {
                    try self.ieputs(self.instruction_vector[is].values[0].registerident);
                },
                .igets => {
                    try self.igets(self.instruction_vector[is].values[0].registerident);
                },
                .istr => {
                    self.istr(self.instruction_vector[is].values[0].registerident, self.instruction_vector[is].values[1]);
                },
                .izero => {
                    self.izero(self.instruction_vector[is].values[0].registerident);
                },
                else => {
                    std.debug.print("Unimplemented", .{});
                },
            }
        }
    }

    pub fn destroy(self: *VM) void {
        self.arena.deinit();
    }
};

pub fn vmCreate(comptime allocator: std.mem.Allocator) !VM {
    var ret: VM = undefined;
    var arena = std.heap.ArenaAllocator.init(allocator);
    ret.allocator = arena.allocator();
    ret.arena = arena;
    ret.instruction_vector = try ret.allocator.alloc(Instruction, vm_alloc_size);
    ret.instruction_vector[0].instruction = .inoop;
    ret.program_counter = 0x0;
    ret.instruction_vector_size = 0;

    ret.stdout = std.io.getStdOut().writer().any();
    ret.stderr = std.io.getStdErr().writer().any();
    ret.stdin = std.io.getStdErr().reader().any();

    return ret;
}

test "vm_strget" {
    var v: VM = try vmCreate(std.heap.page_allocator);
    defer v.destroy();
    try v.appendInstruction(.{ .instruction = .istr, .values = [_]Value{ .{ .registerident = .r1 }, .{ .string = "Hello World" }, undefined } });
    switch (v.getValueFromRegister(.r1)) {
        .string => {
            try std.testing.expectEqualStrings("Hello World", v.getValueFromRegister(.r1).string);
        },
        else => {
            std.debug.print("unsupported", .{});
        },
    }
    try v.compute();
}

test "vm_strzero" {
    var v: VM = try vmCreate(std.heap.page_allocator);
    defer v.destroy();
    try v.appendInstruction(.{ .instruction = .istr, .values = [_]Value{ .{ .registerident = .r1 }, .{ .size = 0xaaaa }, undefined } });
    try v.appendInstruction(.{ .instruction = .izero, .values = [_]Value{ .{ .registerident = .r1 }, undefined, undefined } });
    try v.compute();
    switch (v.getValueFromRegister(.r1)) {
        .size => {
            try std.testing.expectEqual(0, v.getValueFromRegister(.r1).size);
        },
        else => {},
    }
}
