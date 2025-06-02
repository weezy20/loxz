## A bytecode VM interpreter for Lox

### Usage

Interpret a lox file
```sh
loxz <file.lox> 
```

Run in REPL mode

```sh
loxz
```

Flags:

| Flag         | Description                |
|--------------|----------------------------|
| `-h`, `--help` | Show help message          |
| `-t`, `--stack-tracing` | Enable VM stack tracing   |
| `-d`, `--debug`   | Enable debug output, set debug level  |

## Additional features in loxz: 
- Implemented `OP_CONSTANT_LONG` to enable 16_777_216 constants. This is flexible and 24 bits are only used after 8 bits for constant
pool have been exhausted.
- Larger 16 bit indexes for Global variables with Global cache to reduce hashtable lookups.
- Using 16 bit indexes for Local variables, no 256 local variable limit, this means we use (u16::max + 1024)*sizeof(Value) [16 bytes] for stack
- Compiler string interning for strings so zero cost runtime ObjString comparisons. It's as fast as it gets.