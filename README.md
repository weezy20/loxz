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
- Implemented `OP_CONSTANT_LONG` to enable 16_777_216 constants. This is flexible and 24 bits are only used after 8 bits for constant
pool have been exhausted.
- 65536 Global variables with Global cache to reduce hashtable lookups.
- Expanded Local variables limit to 65536 (u16), no 256 local variable limit, this means we use (u16::max + 1024)*sizeof(Value) [16 bytes] for stack
- Compiler stage string interning for strings so zero cost runtime ObjString comparisons. It's as fast as it gets.