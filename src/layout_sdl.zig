pub const SDLContents = @import("SDLContents.zig");

pub const c = @import("sdl_import.zig").c;

const utils = @import("sdl_utils.zig");
pub const assertSdl = utils.assertSdl;
pub const checkSdl = utils.checkSdl;
pub const createBMPTexture = utils.createBMPTexture;
