// Adapted from aleozlx/2in1screen
const std = @import("std");
const io = std.io;
const Allocator = std.mem.Allocator;

// OPTIONS
const opts = @import("build_options");

// Add script length so we can automatically deal with that being really long
const DATA_SIZE = opts.buffer_size + opts.script.len;
const N_STATE: bool = opts.n_state;
const OUTPUT: []const u8 = opts.output;
const SCRIPT_NAME = opts.script;

const NUM_OF_VARIABLES = if (N_STATE) 2 else 1;

// Updated from original (index 3 swapped with index 2)
const ROT = [_][]const u8{ "normal", "inverted", "right", "left" };

const ACCEL_G: f64 = 7.0;

const Device = struct {
    // Rought length of: /sys/bus/iio/devices/iio:device999/in_accel_x_raw
    const BUF_SIZE = opts.device_location.len + 32;

    buf: [BUF_SIZE]u8,
    name_len: usize,

    fn new(allocator: Allocator) !Device {
        var buf: [BUF_SIZE]u8 = undefined;
        // ls /sys/bus/iio/devices/iio:device*/in_accel*
        const device = try findDevice(allocator, &buf, opts.device_location);
        std.log.info("Accelerometer {s}", .{device});
        return Device{
            .buf = buf, // Buffer moved so device is now void
            .name_len = device.len,
        };
    }

    fn openProp(self: *Device, fname: []const u8) !PropertyInfo {
        const end = self.name_len;
        self.buf[end] = '/';
        std.mem.copy(u8, self.buf[end + 1 ..], fname);
        const file_name = self.buf[0 .. end + fname.len + 1];

        std.log.debug("Opening file {s}", .{file_name});
        var file = try std.fs.cwd().openFile(file_name, .{});

        return PropertyInfo{ .file = file };
    }
};

const Property = enum { X, Y };

fn getPropertyName(comptime v: Property) []const u8 {
    switch (v) {
        .Y => return "in_accel_y_raw",
        .X => return "in_accel_x_raw",
    }
}

const PropertyInfo = struct {
    file: std.fs.File,

    fn deinit(self: PropertyInfo) void {
        self.file.close();
    }

    fn read(self: PropertyInfo, buf: []u8) !f64 {
        try self.file.seekTo(0);
        var buf_reader = io.bufferedReader(self.file.reader());
        var in_stream = buf_reader.reader();

        if (try in_stream.readUntilDelimiterOrEof(buf, '\n')) |content| {
            return try std.fmt.parseFloat(f64, content);
        } else {
            const stderr = io.getStdErr().writer();
            try stderr.print("Could not find anything in file\n", .{});
        }
        return 0.0;
    }
};

const State = struct {
    current_state: u2,
    scale: f64,
    variables: [NUM_OF_VARIABLES]PropertyInfo,

    fn new(dev: *Device, buf: []u8) !State {
        var scale_prop = try dev.openProp("in_accel_scale");

        std.log.debug("Reading property", .{});
        const scale = try scale_prop.read(buf);
        scale_prop.deinit();

        std.log.debug("Reading property", .{});
        var variables: [2]PropertyInfo = undefined;

        inline for ([_]Property{ Property.Y, Property.X }, 0..) |v, i| {
            if (!N_STATE and v == Property.X) continue;
            variables[i] = try dev.openProp(getPropertyName(v));
        }

        var state = State{ .current_state = 0, .scale = scale, .variables = variables };
        try state.updateState(buf);
        return state;
    }

    fn current(allocator: Allocator, buf: []u8) !State {
        var dev = try Device.new(allocator);
        return try State.new(&dev, buf);
    }

    fn checkForChange(self: *State, buf: []u8) !bool {
        const state = self.current_state;
        try self.updateState(buf);
        return self.current_state != state;
    }

    fn deinit(self: State) void {
        for (self.variables) |v| {
            v.deinit();
        }
    }

    fn updateState(self: *State, buf: []u8) !void {
        for (self.variables, 0..) |v, i| {
            if (try self.getStateOf(v, buf)) |s| {
                const si: u2 = @intCast(i);
                self.current_state = si * 2 + s;
                return;
            }
        }
    }

    fn getStateOf(self: State, prop: PropertyInfo, buf: []u8) !?u2 {
        const accel = try prop.read(buf) * self.scale;
        if (accel < -ACCEL_G) {
            return 0;
        } else if (accel > ACCEL_G) {
            return 1;
        }
        return null;
    }
};

fn strToState(str: []u8) ?u2 {
    for (ROT, 0..) |elem, i| {
        if (std.mem.eql(u8, elem, str))
            return @intCast(i);
    }
    return null;
}

fn checkArgs(allocator: Allocator, update_script: ?[]const u8) !bool {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const length = args.len;
    if (length == 2) {
        const state = if (strToState(args[1])) |s| s else try std.fmt.parseInt(u2, args[1], 10);
        try rotateScreen(state, allocator, update_script);
        return true;
    } else if (length > 2) {
        std.log.err("Too many arguments given\n", .{});
        return true;
    }
    return false;
}

pub fn get_update_script(allocator: Allocator, buf: []u8) !?[]const u8 {
    const env_map = try allocator.create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(allocator);
    defer env_map.deinit(); // technically unnecessary when using ArenaAllocator

    if (env_map.get("HOME")) |home| {
        return try std.fmt.bufPrint(buf, "{s}/" ++ SCRIPT_NAME, .{home});
    }

    return null;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var buf: [DATA_SIZE]u8 = undefined;
    const update_script = try get_update_script(allocator, &buf);
    if (try checkArgs(allocator, update_script))
        return;

    var rbuf: []u8 = &buf;
    if (update_script) |script| {
        rbuf = buf[script.len..];
    }

    var state = State.current(allocator, rbuf) catch |err| {
        std.log.err("Unable to find or open accelerometer: {}.\n", .{err});
        return;
    };
    defer state.deinit();

    while (true) {
        if (try state.checkForChange(rbuf))
            try rotateScreen(state.current_state, allocator, update_script);

        std.time.sleep(2 * std.time.ns_per_s);
    }
}

// Runs commands to rotate the screen + ~/.xrandr-changed and cleans up
// the resources
fn rotateScreen(current_state: u2, allocator: Allocator, update_script: ?[]const u8) !void {
    const side = ROT[current_state];
    std.log.debug("Rotating the screen {s}", .{side});

    var xrandr = std.ChildProcess.init(
        &[_][]const u8{ "xrandr", "--output", OUTPUT, "--rotate", side },
        allocator,
    );
    _ = xrandr.spawnAndWait() catch |err| {
        std.log.err("Failed to rotate screen with xrandr: {}", .{err});
    };

    if (update_script) |script_name| {
        var update_proc = std.ChildProcess.init(
            &[_][]const u8{ script_name, side },
            allocator,
        );
        _ = update_proc.spawnAndWait() catch |err| {
            std.log.err("Failed to run .xrandr-changed: {}", .{err});
        };
    }
}

fn findDevice(allocator: Allocator, buffer: []u8, dir_path: []const u8) ![]u8 {
    const pattern_match = try std.fmt.bufPrint(buffer, "{s}/{s}", .{ dir_path, "iio:device*/in_accel*" });

    const res = try std.ChildProcess.exec(.{
        .argv = &[_][]const u8{
            "find",
            "-L",
            dir_path,
            "-mindepth",
            "2",
            "-maxdepth",
            "2",
            "-iwholename",
            pattern_match,
        },
        .allocator = allocator,
    });
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);

    var line_it = std.mem.splitScalar(u8, res.stdout, '\n');
    const first_line = line_it.next();
    if (first_line) |path| {
        if (std.fs.path.dirname(path)) |device_path| {
            std.mem.copy(u8, buffer, device_path);
            return buffer[0..device_path.len];
        }
    }

    return std.fs.File.OpenError.FileNotFound;
}
