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
};
