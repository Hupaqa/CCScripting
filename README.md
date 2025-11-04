# CCScripting

Collection of ComputerCraft / Advanced Peripherals helper scripts for MineColonies and monitor displays.

This repo contains small scripts you can run on an in-game ComputerCraft computer (with Advanced Peripherals attached) to display MineColonies data on a CC monitor.

## Available scripts
- `minecolonies_builder_monitor.lua` — Displays materials required for the current/next builder work order. This script uses Advanced Peripherals' `getWorkOrderResources` API (preferred). It prints a short list of item names and counts to a monitor, falling back to terminal output when no monitor is attached.
- `minecolonies_citizen_stats.lua` — Displays all citizens and their happiness/satisfaction on a monitor. The script attempts to detect common citizen-related peripheral methods, scales the display to fit the monitor, and can optionally refresh on an interval.

## Usage
1. Copy the desired script onto an in-game ComputerCraft computer (using pastebin, wget, or by transferring the file into the server's save directory).
2. Attach an Advanced Peripherals colony integrator peripheral (or any peripheral that exposes the required API) to the computer.
3. Attach a `monitor` peripheral and position it where you want the output.
4. Run the script on the computer, for example:

```sh
minecolonies_builder_monitor.lua
```

## Configuration and options
- `minecolonies_citizen_stats.lua` contains a `REFRESH_INTERVAL` variable at the top (seconds). Set it to a positive number (e.g. `5`) to auto-refresh every N seconds.
- Both scripts will fall back to terminal output if no monitor is found or if the monitor does not support text scaling.

## Troubleshooting
- "bad argument #1 (number expected, got table)": Some Advanced Peripherals / MineColonies method signatures expect a numeric index rather than a work order object. The `minecolonies_builder_monitor.lua` script prefers passing a numeric index first, then a string id. If you still get this error, enable debug prints (or paste the exact error and the peripheral name) and I can adapt the calling shape.
- If the script prints "peripheral not found", confirm the colony integrator peripheral is attached and that Advanced Peripherals is installed. Use the in-game command `peripheral.getNames()` in the ComputerCraft REPL to list attached peripherals.
- If names appear but methods are missing, your versions of MineColonies or Advanced Peripherals may differ — share the raw peripheral payload and I'll adapt the script.

## Development notes
- The scripts attempt to be defensive about various MineColonies API shapes. If you have a custom server modpack or a different MineColonies version, send a small snippet of the API output (the raw table) and I will update parser heuristics.

## Contributing
- Open a PR with improvements or tweaks.

## License
- MIT
