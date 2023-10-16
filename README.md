# 2in1screen - Zig Style

Basically this is a conversion of the already perfectly fine
[`2in1screen` command](https://github.com/aleozlx/2in1screen) into zig (It
seems there are so many different repos for this I'm hoping that this is the
original one...) because I wanted to do something in zig and this seemed fun.

## Differences with original

Other then being written in zig there are a few differences with the original
version:

- Can deal with multihead as this will only rotate the output display
  configured in the build options (with the disadvantage that there is no
  option to rotate all screens)
- Will run a custom script (configured in build options) when the rotation
  changes, defaults to `.xrandr-changed`.

  If the script does not exist it will just print an error but recover.

  Example of my `.xrandr-changed` which deals with rotating touch devices
  ```sh
  #!/usr/bin/env sh

  display="eDP-1"
  xinput --map-to-output "Wacom HID 48EE Finger touch" $display
  xinput --map-to-output "Wacom HID 48EE Pen stylus"   $display
  xinput --map-to-output "Wacom HID 48EE Pen eraser"   $display
  ```

- You can now run the script as a one off to rotate your screen, which also
  includes running the script above. See Usage for more info. Which is useful
  to make sure if you only want it rotating in tablet mode, it will always
  rotate back to being upright when going back into desktop mode.

## Build Requirements

- Zig >= 0.11 to be installed
- `xrandr` to rotate the screen (have not made it handle wayland soz)
- `find` command for running glob pattern matching

## Install

```sh
git clone https://github.com/WilfSilver/2in1screen
cd 2in1screen
```

Before we build there are some options you may want to change:

(These options with their defaults can be seen by going `zig build --help`)

- `display` - The display name of your touchscreen (e.g. `eDP-1`)
- `script` - The script to run

Other compile options you may want to experiment with

- `n-state` - Should we rotate in all directions or just upside down and
  upright
- `buffer-size` - The size of the buffer we use on the stack, careful not to go
  too low, should only be changed if the script is erroring out
- `device-location` - The directory to search to try and find the `iio:device*`
  symlinks

You can then install with these options by going:

```sh
zig build install -Doptimize=ReleaseFast -D<option>=<value> -p ~/.local
```

Which will install it to your `~/.local/bin` folder.

NOTE: Sadly this cannot currently compile with `ReleaseSmall` because issue
with running child process.

## Usage

Default: Start daemon to listen to accelerator for change and rotate as
necessary.

```sh
2in1screen &
```

Stop the daemon

```sh
pkill 2in1screen
```

Rotate the screen back to upright

```sh
2in1screen 0
```

The argument should be an index of `ROT`: `{ "normal", "inverted", "right", "left" }`
for the direction to rotate in.
