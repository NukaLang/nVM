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
};

const Instruction = struct {
    instruction: InstructionOption,
    values: [8]this_module.Value,
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
    string: []u8,
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
    program_counter: usize,

    inline fn istr(self: *VM, register: RegisterIdent, value: Value) !void {
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
        self.registers[@intFromEnum(string)].value.string = try self.stdin.readAllAlloc(self.allocator);
    }

    /// instruction: the given instruction to append
    /// this **INLINE** function reallocs the instruction_vector each vm_alloc_size - 1
    pub inline fn appendInstruction(self: *VM, instruction: Instruction) !void {
        if ((self.instruction_vector.len % vm_alloc_size) == (vm_alloc_size - 1)) {
            self.instruction_vector = self.allocator.realloc(self.instruction_vector, self.instruction_vector.len);
        }
        self.instruction_vector[self.instruction_vector.len] = instruction;
    }

    pub inline fn compute(self: *VM) !void {
        for (self.instruction_vector) |instruction| {
            switch (instruction.instruction) {
                .iputs => {
                    self.iputs(instruction.values[0]);
                },
                .eputs => {
                    self.ieputs(instruction.values[0]);
                },
                .igets => {
                    self.igets(instruction.values[0]);
                },
            }
        }
    }

    pub fn destroy(self: *VM) !void {
        self.arena.deinit();
    }
};

pub fn vmCreate() !VM {
    var ret: VM = .{};
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    ret.allocator = arena.allocator();
    ret.arena = arena;
    ret.instructions_vector = ret.allocator.alloc(Instruction, vm_alloc_size);
    ret.instruction_vector[0].instruction = .inoop;
    ret.program_counter = 0x0;

    ret.stdout = std.io.getStdOut().writer().any();
    ret.stderr = std.io.getStdErr().writer().any();
    ret.stdin = std.io.getStdErr().reader().any();

    return ret;
}

test "vm" {
    var v: VM = vmCreate();
    v.appendInstruction(.{});
}
