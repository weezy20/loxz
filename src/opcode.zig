pub const OpCode = enum(u8) {
    RETURN = 0x00,
    CONSTANT = 0x01,
    CONSTANT_LONG = 0x02,
    NEGATE,
    // Arithmetic OPs
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    // Nil
    NIL,
    // Boolean values
    TRUE,
    FALSE,
    // Logical ops
    NOT,
    // AND,
    // OR,
    EQUAL, // a != b is !(a == b)
    LESS, // a >= b is !(a < b)
    GREATER, // a <= b is !(a > b)
    PRINT,
    POP,
    DEFINE_GLOBAL,
    GET_GLOBAL,
    SET_GLOBAL,
};
