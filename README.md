## A bytecode VM interpreter for Lox

### Usage

Interpret a lox file. A lox file must have `.lox` extension.
Some sample programs are provided in the `programs` folder.
```sh
loxz <OPTIONS> <file.lox>
```

Run in REPL mode

```sh
loxz <OPTIONS>
```

Flags:

| Flag         | Description                |
|--------------|----------------------------|
| `-h`, `--help` | Show help message          |
| `-t`, `--stack-tracing` | Enable VM stack tracing   |
| `-d`, `--debug`   | Enable debug output, set debug level  |

### Build

Easiest way to build this is using the bash script `build.sh`, unless you already have zig installed.
Add execute permissions to the script and run it to obtain the `loxz` binary in your current working directory.
```sh
./build.sh
# Follow prompts
# Run loxz
./loxz <OPTIONS> <file.lox>
```
 Inspect the script before running, but in a nutshell it downloads the `.zigversion` zig binary for your platform/OS and builds `loxz` using all optimizations.

## Additional features in loxz over the standard implementation: 

- Flexible constant pool upto 16_777_216 (u24) constants enabled by `OP_CONSTANT_LONG`. This instruction is emitted only after 8-bit space for constants have been exhausted.
pool have been exhausted.
- 65536 Global variables supported over 256 in clox, with a global cache to speed up lookups.
- Expanded Local variables limit to 65536 (u16), no 256 local variable limit, this means we use (u16::max + 1024)*sizeof(Value) [16 bytes] for stack
- String interning for strings are performed at comptime so zero cost runtime ObjString comparisons. They are only a pointer comparison. It's as fast as it gets.
- Supports `%` modulo operation.
- Add support for `switch/case`. Check out [switch-case.lox](programs/switch-case.lox) example. Supports upto 64 nested switch blocks. No `break` keyword required, only one switch case executes.

## Native Functions

The interpreter includes several built-in native functions with runtime error reporting:

- **`clock()`** - Returns the current timestamp in seconds since epoch
- **`sqrt(number)`** - Returns the square root of a number (requires non-negative input)
- **`abs(number)`** - Returns the absolute value of a number
- **`pow(base, exponent)`** - Returns base raised to the power of exponent

All native functions perform argument validation and provide descriptive error messages for invalid inputs. See [test_native.lox](programs/test_native.lox) for usage examples.