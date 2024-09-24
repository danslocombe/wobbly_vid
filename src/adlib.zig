const std = @import("std");
const rl = @import("raylib");

const consts = @import("consts.zig");
const alloc = @import("alloc.zig");
const utils = @import("utils.zig");

pub const DialogueEngine = struct {
    file: DialogueFile,
    filename: []const u8,

    line_linger_time: f32 = 4.0,
    text_rate: f32 = 0.035,

    cursor: ?DialogueCursor = null,

    // Keep this here for handling special commands, though really we should do away with a
    // layer of abstraction
    last_tick_result: ?TickResult = null,

    t: f32 = 0.0,
    t_since_last_update: f32 = 0,
    line_linger_t: f32 = 0.0,

    waiting_for_input: bool = false,
    waiting_for_input_t: i32 = 0,

    buffered_keypress: bool = false,
    buffered_mousepress: bool = false,

    pub fn from_path(filename: []const u8) DialogueEngine {
        //console.print("Loading DialogueEngine from {s}...\n", .{filename});

        var cwd = std.fs.cwd();
        var data_dir = cwd.openDir("dialogue", .{}) catch @panic("Could not find data directory");
        var file = data_dir.openFile(filename, .{}) catch std.debug.panic("Could not find ./dialogue/{s}", .{filename});
        defer file.close();
        var intro_adlib_content = file.readToEndAlloc(alloc.gpa.allocator(), 1024 * 1024) catch unreachable;
        var intro_adlib_lines = std.mem.split(u8, intro_adlib_content, "\r\n");
        var lines = std.ArrayList([]const u8).init(alloc.gpa.allocator());
        while (intro_adlib_lines.next()) |line| {
            lines.append(line) catch unreachable;
        }

        var parser = Parser{};
        var dialogue = parser.parse(lines.items);

        //console.print("Done!\n", .{});

        var engine = DialogueEngine{
            .file = dialogue,
            .filename = alloc.copy_slice_to_gpa(filename),
        };

        return engine;
    }

    pub fn active(self: *DialogueEngine) bool {
        // Good enough for now?
        // Also do we want to check if last_tick_result == .Done?
        if (self.cursor) |c| {
            return !c.exhausted;
        }

        return false;
    }

    // Tick returns a u8 with the char, can we remove a layer of abstraction somehow?
    pub fn tick(self: *DialogueEngine) ?u8 {
        var dt: f32 = 1.0 / 60.0;
        self.buffered_keypress = self.buffered_keypress or rl.IsKeyPressed(rl.KeyboardKey.KEY_SPACE);
        self.buffered_mousepress = self.buffered_mousepress or rl.IsMouseButtonPressed(rl.MouseButton.MOUSE_BUTTON_LEFT);

        self.t_since_last_update += dt;

        if (self.cursor) |*cursor| {
            if (self.line_linger_t > 0.0) {
                self.line_linger_t -= dt;

                if (self.line_linger_t > self.line_linger_time) {
                    self.clear();
                }

                return null;
            }

            self.t += dt;

            var tick_time = cursor.tick_time(&self.file, self.text_rate);
            if (self.t > tick_time) {
                self.t -= tick_time;

                self.waiting_for_input = false;

                var keypress = self.buffered_keypress;
                self.buffered_keypress = false;
                var mousepress = self.buffered_mousepress;
                self.buffered_mousepress = false;

                var incr_res = cursor.incr(&self.file, keypress, mousepress);
                self.last_tick_result = incr_res;

                var result: ?u8 = null;

                if (incr_res != .Done) {
                    self.t_since_last_update = 0;
                }

                switch (incr_res) {
                    .Char => |c| {
                        result = c;
                    },
                    .Newline => {
                        result = '\n';
                    },
                    .Wait => {
                        self.line_linger_t = self.line_linger_time;
                        //result = '\n';
                    },
                    .WaitingForKeypress => {
                        self.waiting_for_input = true;
                    },
                    .WaitingForClick => {
                        self.waiting_for_input = true;
                    },
                    .Clear => {
                        // @Hack TODO replace return value with union.
                        result = '\r';
                    },
                    .ClearLine => {
                        // Backspace
                        result = 8;
                    },
                    .Noop => {},
                    .Done => {
                        result = 0;
                    },
                    .SetTextRate => |r| {
                        self.text_rate = r;
                    },
                    // Special commands, handle kinda hackily by requiring the caller
                    // to access last_tick_result
                    else => {
                        // Bell
                        result = 7;
                    },
                }

                if (self.waiting_for_input) {
                    self.waiting_for_input_t += 1;
                } else {
                    self.waiting_for_input_t = 0;
                }

                return result;
            }
        }

        return null;
    }

    pub fn clear(self: *DialogueEngine) void {
        self.cursor = null;
        self.t = 0.0;
        self.line_linger_t = 0.0;
    }

    pub fn queue(self: *DialogueEngine, name: []const u8) void {
        for (self.file.sections.items, 0..) |section, i| {
            if (std.mem.eql(u8, section.name, name)) {
                //console.print("Queuing {s}\n", .{name});
                self.clear();
                self.cursor = DialogueCursor{
                    .index = i,
                };

                return;
            }
        }

        //console.err_fmt("[adlib] Could not queue '{s}' as it was not found in {s}", .{ name, self.filename });
    }

    pub fn queue_if_different(self: *DialogueEngine, name: []const u8) bool {
        for (self.file.sections.items, 0..) |section, i| {
            if (std.mem.eql(u8, section.name, name)) {
                if (self.cursor) |cursor| {
                    if (cursor.index == i) {
                        // queuing current
                        return false;
                    }
                }

                //console.print("Queuing {s}\n", .{name});
                self.clear();
                self.cursor = DialogueCursor{
                    .index = i,
                };

                return true;
            }
        }

        return false;
    }
};

const TickResult = union(enum) {
    Char: u8,
    Newline: void,
    Wait: void,
    WaitingForKeypress: void,
    WaitingForClick: void,
    Clear: void,
    ClearLine: void,
    Done: void,
    SetTextRate: f32,
    DumpNoise: f32,
    DumpShaderAmp: f32,
    PlaySound: f32,
    SetStyling: Styling,
    Noop: void,
};

const DialogueCursor = struct {
    index: usize,

    i: usize = 0,
    line: usize = 0,
    exhausted: bool = false,

    pub fn tick_time(self: *DialogueCursor, file: *DialogueFile, base_text_rate: f32) f32 {
        var peeked = self.peek_chunk(file);
        if (peeked.chunk) |chunk| {
            switch (chunk.*) {
                .Command => |cc| {
                    switch (cc) {
                        .Wait => |wait_s| {
                            return wait_s;
                        },
                        else => {},
                    }
                },
                else => {
                    return base_text_rate;
                },
            }
        }

        return 0;
    }

    pub fn peek_chunk(self: *DialogueCursor, file: *DialogueFile) struct { section: ?*Dialogue = null, chunk: ?*Chunk = null, set_exhausted: bool = false } {
        if (self.exhausted) {
            return .{};
        }

        if (self.index >= file.sections.items.len) {
            return .{ .set_exhausted = true };
        }

        var section = &file.sections.items[self.index];

        if (self.line >= section.chunks.items.len) {
            return .{ .set_exhausted = true };
        }

        var chunk = &section.chunks.items[self.line];

        return .{
            .section = section,
            .chunk = chunk,
        };
    }

    pub fn incr(self: *DialogueCursor, file: *DialogueFile, keypress: bool, click: bool) TickResult {
        var peeked = self.peek_chunk(file);
        if (peeked.chunk == null) {
            if (peeked.set_exhausted) {
                self.exhausted = true;
            }

            return .{ .Done = void{} };
        }

        var chunk = peeked.chunk.?.*;

        switch (chunk) {
            .Text => |tc| {
                std.debug.assert(self.i < tc.text.len);

                var c = chunk.Text.text[self.i];

                self.i += 1;
                if (self.i == tc.text.len) {
                    self.line += 1;
                    self.i = 0;
                }

                return .{ .Char = c };
            },
            .Newline => {
                self.line += 1;
                return .Newline;
            },
            .Command => |cc| {
                switch (cc) {
                    .WaitPress => {
                        if (keypress) {
                            self.line += 1;
                        } else {
                            return .{ .WaitingForKeypress = void{} };
                        }
                    },
                    .WaitClick => {
                        if (click) {
                            self.line += 1;
                        } else {
                            return .{ .WaitingForClick = void{} };
                        }
                    },
                    .Wait => {
                        self.line += 1;
                    },
                    .Clear => {
                        self.line += 1;
                        return .{ .Clear = void{} };
                    },
                    .ClearLine => {
                        self.line += 1;
                        return .{ .ClearLine = void{} };
                    },
                    .SetTextRate => |r| {
                        self.line += 1;
                        return .{ .SetTextRate = r };
                    },
                    .DumpNoise => |r| {
                        self.line += 1;
                        return .{ .DumpNoise = r };
                    },
                    .DumpShaderAmp => |r| {
                        self.line += 1;
                        return .{ .DumpShaderAmp = r };
                    },
                    .SetStyling => |r| {
                        self.line += 1;
                        return .{ .SetStyling = r };
                    },
                    else => unreachable,
                }
            },
        }

        return .Noop;
    }
};

const Command = union(enum) {
    //Speaker: []const u8,
    Wait: f32,
    WaitPress: void,
    WaitClick: void,
    Clear: void,
    ClearLine: void,
    SetTextRate: f32,

    DumpNoise: f32,
    DumpShaderAmp: f32,
    PlaySound: []const u8,

    SetStyling: Styling,
};

pub const Styling = struct {
    color: rl.Color = consts.pico_white,
    wavy: bool = false,
    jitter: bool = false,
    rainbow: bool = false,
    font_type: FontType = .Dialogue,
};

pub const FontType = enum {
    Dialogue,
    DialogueItalic,
    DialogueSmall,
    Monospace,
};

const TextChunk = struct { text: []const u8 };

const Chunk = union(enum) {
    Text: TextChunk,
    Command: Command,
    Newline: void,
};

const Dialogue = struct {
    name: []const u8,
    chunks: std.ArrayList(Chunk),
};

const DialogueFile = struct {
    //talkers: []Chunk,
    sections: std.ArrayList(Dialogue),
};

pub const Parser = struct {
    normalize_whitespace: bool = true,

    pub fn parse(self: Parser, lines: [][]const u8) DialogueFile {
        var sections = std.ArrayList(Dialogue).init(alloc.gpa.allocator());

        var i: usize = 0;

        while (i < lines.len) {
            var line = lines[i];
            i += 1;

            if (line.len == 0 or line[0] == '#') {
                continue;
            }

            if (line[0] == '[') {
                var section_name = line[1 .. line.len - 1];

                var section = self.parse_section(lines, &i, section_name);

                sections.append(section) catch unreachable;
            }
        }

        return DialogueFile{
            .sections = sections,
        };
    }

    pub fn parse_section(self: Parser, lines: []const []const u8, i: *usize, section_name: []const u8) Dialogue {
        var chunks = std.ArrayList(Chunk).init(alloc.gpa.allocator());

        while (i.* < lines.len) {
            var line = lines[i.*];

            if (line.len == 0 or line[0] == '#') {
                i.* += 1;
                continue;
            }

            if (line[0] == '[') {
                // Next section
                break;
            }

            i.* += 1;

            var added_text = false;

            var l_i: usize = 0;
            while (std.mem.indexOf(u8, line[l_i..], "(")) |open_pos_local| {
                var open_pos = open_pos_local + l_i;
                var end_pos = line.len;
                if (std.mem.indexOf(u8, line[open_pos..], ")")) |close_pos_local| {
                    end_pos = close_pos_local + open_pos;
                }

                if (end_pos - open_pos > 0) {
                    var command_str = line[open_pos + 1 .. (end_pos)];

                    if (self.try_parse_command(command_str, line, section_name)) |command| {
                        var ret = self.make_add_text_chunk(line[l_i..open_pos], &chunks);
                        added_text = added_text or ret;
                        chunks.append(Chunk{
                            .Command = command,
                        }) catch unreachable;
                    }
                }

                l_i = end_pos + 1;
            }

            var ret = self.make_add_text_chunk(line[l_i..], &chunks);
            added_text = added_text or ret;

            if (added_text) {
                // Only add a newline if one of the above actually added text to be displayed.
                // This handles the case where we have a line that is entirely a command.
                chunks.append(Chunk{
                    .Newline = void{},
                }) catch unreachable;
            }
        }

        return Dialogue{
            .name = section_name,
            .chunks = chunks,
        };
    }

    fn tokenize_command(self: Parser, command: []const u8) [][]const u8 {
        _ = self;
        var buf = alloc.temp_alloc.allocator().alloc([]const u8, 8) catch unreachable;
        var iter = std.mem.split(u8, command, " ");

        var i: usize = 0;
        while (iter.next()) |c| {
            if (c.len == 0) {
                continue;
            }

            if (i == 8) {
                std.debug.panic("Error parsing adlib command, too many args in '{s}'", .{command});
            }

            buf[i] = c;
            i += 1;
        }

        return buf[0..i];
    }

    fn try_parse_command(self: Parser, command: []const u8, line: []const u8, section_name: []const u8) ?Command {
        var tokens = self.tokenize_command(command);

        if (tokens.len == 0) {
            return null;
        }

        if (std.mem.eql(u8, tokens[0], "wait")) {
            if (tokens.len == 1) {
                //console.err_fmt("Adlib: Wait command has no argument, line: '{s}', section: {s}", .{ line, section_name });
                return null;
            }

            if (std.mem.eql(u8, tokens[1], "press")) {
                return .WaitPress;
            }

            if (std.mem.eql(u8, tokens[1], "click")) {
                return .WaitClick;
            }

            if (std.mem.eql(u8, tokens[1], "click")) {
                return .WaitClick;
            }

            var time_str = tokens[1];
            var time_in_s: f32 = -1;
            if (time_str.len > 0) {
                if (std.mem.endsWith(u8, time_str, "s")) {
                    if (std.fmt.parseFloat(f32, time_str[0 .. time_str.len - 1])) |f| {
                        time_in_s = f;
                    } else |_| {}
                }
            }

            if (time_in_s < 0) {
                //console.err_fmt("Adlib: Failed to parse wait time '{s}' line: '{s}', section: {s}", .{ time_str, line, section_name });
                time_in_s = 1;
            }

            return .{
                .Wait = time_in_s,
            };
        }

        if (std.mem.eql(u8, tokens[0], "text_rate")) {
            var text_rate_str = if (tokens.len > 0) tokens[1] else "";
            var text_rate: f32 = -1;
            if (text_rate_str.len > 0) {
                if (std.fmt.parseFloat(f32, text_rate_str)) |f| {
                    text_rate = f;
                } else |_| {}
            }

            if (text_rate < 0) {
                //console.err_fmt("Adlib: Failed to parse text rate '{s}' line: '{s}', section: {s}", .{ text_rate_str, line, section_name });
                text_rate = 0.035;
            }

            return .{
                .SetTextRate = text_rate,
            };
        }

        if (self.try_parse_command_float(tokens, "dump_noise", 1, line, section_name)) |rate| {
            return .{
                .DumpNoise = rate,
            };
        }

        if (self.try_parse_command_float(tokens, "dump_shader_amp", 1, line, section_name)) |rate| {
            return .{
                .DumpShaderAmp = rate,
            };
        }

        if (std.mem.eql(u8, "clear", tokens[0])) {
            return .Clear;
        }

        if (std.mem.eql(u8, "clear_line", tokens[0])) {
            return .ClearLine;
        }

        if (std.mem.eql(u8, "style", tokens[0]) or std.mem.eql(u8, "s", tokens[0])) {
            var style = Styling{};
            for (tokens[1..]) |t| {
                if (std.mem.eql(u8, "wavy", t)) {
                    style.wavy = true;
                } else if (std.mem.eql(u8, "jitter", t)) {
                    style.jitter = true;
                } else if (std.mem.eql(u8, "rainbow", t)) {
                    style.rainbow = true;
                } else if (std.mem.eql(u8, "col_sea", t)) {
                    style.color = consts.pico_sea;
                } else if (std.mem.eql(u8, "col_purple", t)) {
                    style.color = consts.pico_purple;
                } else if (std.mem.eql(u8, "col_white", t)) {
                    style.color = consts.pico_white;
                } else if (std.mem.eql(u8, "col_beige", t)) {
                    style.color = consts.pico_beige;
                } else if (std.mem.eql(u8, "col_red", t)) {
                    style.color = consts.pico_red;
                } else if (std.mem.eql(u8, "col_lilac", t)) {
                    style.color = consts.pico_lilac;
                } else if (std.mem.eql(u8, "italic", t)) {
                    style.font_type = .DialogueItalic;
                } else if (std.mem.eql(u8, "monospace", t)) {
                    style.font_type = .Monospace;
                } else if (std.mem.eql(u8, "small", t)) {
                    style.font_type = .DialogueSmall;
                }
            }

            return .{
                .SetStyling = style,
            };
        }

        return null;
    }

    fn try_parse_command_float(self: Parser, tokens: [][]const u8, command_name: []const u8, default_value: ?f32, line: []const u8, section: []const u8) ?f32 {
        _ = section;
        _ = line;
        _ = self;
        std.debug.assert(tokens.len != 0);

        if (std.mem.eql(u8, tokens[0], command_name)) {
            var arg = if (tokens.len > 1) tokens[1] else "";
            if (std.fmt.parseFloat(f32, arg)) |f| {
                return f;
            } else |_| {
                //console.err_fmt("Adlib: Failed not parse '{s}' as a float in line '{s}', section '{s}'", .{ arg, line, section });
                return default_value;
            }
        }

        return null;
    }

    fn make_add_text_chunk(self: Parser, text: []const u8, chunks: *std.ArrayList(Chunk)) bool {
        var s = if (self.normalize_whitespace) std.mem.trim(u8, text, " ") else text;

        if (s.len == 0) {
            return false;
        }

        if (self.normalize_whitespace) {
            var has_a_previous_text_chunk_since_linebreak = false;
            for (chunks.items) |c| {
                if (c == .Text) {
                    has_a_previous_text_chunk_since_linebreak = true;
                }

                if (c == .Newline) {
                    has_a_previous_text_chunk_since_linebreak = false;
                }
            }

            if (has_a_previous_text_chunk_since_linebreak) {
                chunks.append(Chunk{
                    .Text = TextChunk{
                        .text = " ",
                    },
                }) catch unreachable;
            }
        }

        chunks.append(Chunk{
            .Text = TextChunk{
                .text = s,
            },
        }) catch unreachable;

        return true;
    }
};

test "parse_section inline command" {
    const section: []const []const u8 = &[_][]const u8{
        "hello (style wavy)val(style) nonwavy",
    };

    var i: usize = 0;
    var parser = Parser{};
    var parsed = parser.parse_section(section, &i, "test");
    try std.testing.expectEqual(@as(usize, 6), parsed.chunks.items.len);
    try std.testing.expectEqualStrings("hello", parsed.chunks.items[0].Text.text);
    try std.testing.expect(parsed.chunks.items[1].Command.SetStyling.wavy);
    try std.testing.expectEqualStrings("val", parsed.chunks.items[2].Text.text);
    try std.testing.expect(parsed.chunks.items[3].Command.SetStyling.wavy == false);
    try std.testing.expectEqualStrings("nonwavy", parsed.chunks.items[4].Text.text);
    try std.testing.expect(parsed.chunks.items[5] == .Newline);
}
