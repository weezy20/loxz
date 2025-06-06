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

## Additional features in loxz over the standard implementation: 

- Flexible constant pool upto 16_777_216 (u24) constants enabled by `OP_CONSTANT_LONG`. This instruction is emitted only after 8-bit space for constants have been exhausted.
pool have been exhausted.
- 65536 Global variables supported over 256 in clox, with a global cache to speed up lookups.
- Expanded Local variables limit to 65536 (u16), no 256 local variable limit, this means we use (u16::max + 1024)*sizeof(Value) [16 bytes] for stack
- String interning for strings are performed at comptime so zero cost runtime ObjString comparisons. They are only a pointer comparison. It's as fast as it gets.
- Supports `%` modulo operation.