# sine-clap

CLAP plugin written in zig, based on https://nakst.gitlab.io/tutorial/clap-part-1.html

It makes sine waves.

## Build

Build for current host:
```
zig build
```

Build for windows:
```
zig build -Dtarget=x86_64-windows
```

## Validate

This runs the clap validator:

```
zig build validate
```
