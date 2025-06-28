const lib = @import("root.zig");
const build_options = @import("build_options");
/// Default hasher for keys in the table
pub const hasher = lib.loxHash;
/// Use lib.hasClhash to determine if CLHash is available
pub const clhasher = lib.ClHash.hash;

pub const InterpreterOpts = struct {
    stack_tracing: bool = false,
    repl_mode: bool = false,
    debug_level: u8,

    pub fn intoCompilerOpts(opts: InterpreterOpts) CompilerOpts {
        return CompilerOpts{
            .debug = true, // We need line info so we hardcode debug == true
            .debug_level = opts.debug_level,
            .repl_mode = opts.repl_mode,
        };
    }
};
pub const CompilerOpts = struct {
    debug: bool = false,
    debug_level: u8,
    repl_mode: bool = false,
};
