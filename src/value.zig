pub const Value = union(enum) {
    Number: f64,
    String: []const u8,
    Bool: bool,
    Nil,
};
