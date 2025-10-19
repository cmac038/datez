# Datez

Simple Date utils for zig.

# Usage

Run the following command from your project root to add `datez`:
```sh
$ zig fetch --save git+https://github.com/cmac038/datez.git
```

Then, add the following to your `build.zig`:
```zig
const datez = b.dependency("datez", .{});
exe.root_module.addImport("datez", datez.module("datez"));
```

Run `zig build`, then you can use `datez` in your code via:
```zig
const datez = @import("datez");
```

