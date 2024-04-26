const std = @import("std");
const this_module = @This();

const InstructionOption = enum {
    inoop,
    iadd,
    isub,
    imul,
    idiv,
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
    ijlbl,
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
    ilbl,
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
    labels: std.StringHashMap(usize),
    stack: std.AutoHashMap(RegisterIdent, Register),

    instruction_vector: []Instruction,
    instruction_vector_size: usize,
    program_counter: usize,

    // testing function here.
    inline fn getValueFromRegister(self: *VM, register: RegisterIdent) Value {
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

    inline fn ilbl(self: *VM, name: Value) !void {
        var lbl: []const u8 = undefined;
        switch (name) {
            .string => {
                lbl = name.string;
            },
            .registerident => {
                lbl = self.registers[@intFromEnum(name.registerident)].value.string;
            },
            else => {},
        }
        try self.labels.put(lbl, self.program_counter + 1);
    }

    inline fn ijlbl(self: *VM, name: Value) !void {
        var lbl: []const u8 = undefined;
        switch (name) {
            .string => {
                lbl = name.string;
            },
            .registerident => {
                lbl = self.registers[@intFromEnum(name.registerident)].value.string;
            },
            else => {},
        }

        const jpos = self.labels.get(lbl) orelse return VMError.illegal_instruction;
        self.program_counter = jpos;
    }

    inline fn ijmp(self: *VM, value: usize) void {
        self.program_counter = value;
    }

    inline fn ijeq(self: *VM, to: usize, eq1: Value, eq2: Value) void {
        var eq1_val: usize = undefined;
        var eq2_val: usize = undefined;
        switch (eq1) {
            .size => {
                eq1_val = eq1.size;
            },
            .registerident => {
                eq1_val = self.registers[@intFromEnum(eq1.registerident)].value.size;
            },
            else => {},
        }

        switch (eq2) {
            .size => {
                eq2_val = eq2.size;
            },
            .registerident => {
                eq2_val = self.registers[@intFromEnum(eq2.registerident)].value.size;
            },
            else => {},
        }

        if (eq1_val == eq2_val) {
            self.program_counter = to;
        }
    }

    inline fn ijne(self: *VM, to: usize, eq1: Value, eq2: Value) void {
        var eq1_val: usize = undefined;
        var eq2_val: usize = undefined;
        switch (eq1) {
            .size => {
                eq1_val = eq1.size;
            },
            .registerident => {
                eq1_val = self.registers[@intFromEnum(eq1.registerident)].value.size;
            },
            else => {},
        }

        switch (eq2) {
            .size => {
                eq2_val = eq2.size;
            },
            .registerident => {
                eq2_val = self.registers[@intFromEnum(eq2.registerident)].value.size;
            },
            else => {},
        }

        if (eq1_val != eq2_val) {
            self.program_counter = to;
        }
    }

    inline fn iadd(self: *VM, add1: Value, add2: Value, target: RegisterIdent) void {
        var add1_val: usize = undefined;
        var add2_val: usize = undefined;
        switch (add1) {
            .size => {
                add1_val = add1.size;
            },
            .registerident => {
                add1_val = self.registers[@intFromEnum(add1.registerident)].value.size;
            },
            else => {},
        }

        switch (add2) {
            .size => {
                add2_val = add2.size;
            },
            .registerident => {
                add2_val = self.registers[@intFromEnum(add2.registerident)].value.size;
            },
            else => {},
        }

        self.istr(target, .{ .size = add1_val + add2_val });
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
        while (self.program_counter != self.instruction_vector_size) {
            switch (self.instruction_vector[self.program_counter].instruction) {
                .iputs => {
                    try self.iputs(self.instruction_vector[self.program_counter].values[0].registerident);
                },
                .ieputs => {
                    try self.ieputs(self.instruction_vector[self.program_counter].values[0].registerident);
                },
                .igets => {
                    try self.igets(self.instruction_vector[self.program_counter].values[0].registerident);
                },
                .istr => {
                    self.istr(self.instruction_vector[self.program_counter].values[0].registerident, self.instruction_vector[self.program_counter].values[1]);
                },
                .izero => {
                    self.izero(self.instruction_vector[self.program_counter].values[0].registerident);
                },
                .ilbl => {
                    try self.ilbl(self.instruction_vector[self.program_counter].values[0]);
                },
                .ijlbl => {
                    try self.ijlbl(self.instruction_vector[self.program_counter].values[0]);
                },
                .ijmp => {
                    self.ijmp(self.instruction_vector[self.program_counter].values[0].size);
                },
                .ijeq => {
                    self.ijeq(self.instruction_vector[self.program_counter].values[0].size, self.instruction_vector[self.program_counter].values[1], self.instruction_vector[self.program_counter].values[2]);
                },
                .ijne => {
                    self.ijne(self.instruction_vector[self.program_counter].values[0].size, self.instruction_vector[self.program_counter].values[1], self.instruction_vector[self.program_counter].values[2]);
                },
                .iadd => {
                    self.iadd(self.instruction_vector[self.program_counter].values[0], self.instruction_vector[self.program_counter].values[1], self.instruction_vector[self.program_counter].values[2].registerident);
                },
                else => {
                    std.debug.print("Unimplemented", .{});
                },
            }
            self.program_counter += 1;
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

test "vm_loop" {
    var v: VM = try vmCreate(std.heap.page_allocator);
    defer v.destroy();
    try v.appendInstruction(.{ .instruction = .istr, .values = [_]Value{ .{ .registerident = .r1 }, .{ .size = 0 }, undefined } });
    try v.appendInstruction(.{ .instruction = .iadd, .values = [_]Value{ .{ .size = 1 }, .{ .registerident = .r1 }, .{ .registerident = .r1 } } });
    try v.appendInstruction(.{ .instruction = .ijne, .values = [_]Value{ .{ .size = 0x2 }, .{ .registerident = .r1 }, .{ .size = 10 } } });
    try v.compute();
}
