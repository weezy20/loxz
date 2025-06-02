//! Error types used in loxz

pub const InterpretResult = union(enum) {
    ok,
    compile_error,
    runtime_error: RuntimeError,
};

pub const CompilerError = error{
    /// Not enough memory
    OutOfMemory,
    /// Not a number
    NaN,
    /// Unreachable compiler state
    Unreachable,
    /// Local variable not found
    LocalNotFound,
    /// Cannot declare a variable with its own initializer
    SameInitializer,
};

pub const RuntimeError = error{
    StackOverflow,
    NaN,
    DivisionByZero,
    ValueIndexOutOfBounds,
    OutOfMemory,
    StackUnderflow,
    InvalidNot,
    InvalidEquality,
    InvalidComparison,
    CannotAddDifferentTypes,
    GlobalNotFound,
};
pub fn formatRuntimeError(err: RuntimeError) []const u8 {
    return switch (err) {
        RuntimeError.StackOverflow => "Stack overflow",
        RuntimeError.NaN => "Not a number",
        RuntimeError.DivisionByZero => "Division by zero",
        RuntimeError.ValueIndexOutOfBounds => "Value index out of bounds",
        RuntimeError.OutOfMemory => "Out of memory",
        RuntimeError.StackUnderflow => "Stack underflow",
        RuntimeError.InvalidNot => "Invalid operand for 'not'",
        RuntimeError.InvalidEquality => "Invalid operands for equality",
        RuntimeError.InvalidComparison => "Invalid operands for comparison",
        RuntimeError.CannotAddDifferentTypes => "Operands of different types cannot be added",
        RuntimeError.GlobalNotFound => "Undefined global variable",
    };
}
