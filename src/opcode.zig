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

    NIL,
    TRUE,
    FALSE,
};
