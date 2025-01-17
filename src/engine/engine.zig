pub const Window = @import("window.zig");
pub const InputState = @import("input_state.zig");

pub const SceneManager = @import("scene_manager.zig").SceneManager;
pub const SceneDescriptor = @import("scene_manager.zig").SceneDescriptor;
pub const Scene = @import("scene_manager.zig").Scene;
pub const SceneId = @import("scene_manager.zig").SceneId;
pub const SceneArgs = @import("scene_manager.zig").SceneArgs;

pub const LoadContext = @import("scene_manager.zig").LoadContext;
pub const UnloadContext = @import("scene_manager.zig").UnloadContext;
pub const UpdateContext = @import("scene_manager.zig").UpdateContext;
pub const RenderContext = @import("scene_manager.zig").RenderContext;
pub const DrawUiContext = @import("scene_manager.zig").DrawUiContext;

pub const ContentManager = @import("content_manager.zig").ContentManager;
pub const SaveManager = @import("save_manager.zig").SaveManager;

pub const Shader = @import("shader.zig").Shader;
pub const ShaderError = @import("shader.zig").ShaderError;

pub const Texture = @import("texture.zig").Texture;
pub const TextureError = @import("texture.zig").TextureError;

pub const MaterialDefs = @import("material.zig").MaterialDefs;
pub const MaterialDef = @import("material.zig").MaterialDef;
pub const Materials = @import("material.zig").Materials;
pub const Material = @import("material.zig").Material;
pub const MaterialRef = @import("material.zig").MaterialRef;

pub const Renderer2D = @import("renderer_2d.zig").Renderer2D;
pub const ZBoxRenderer = @import("zbox_renderer.zig").ZBoxRenderer;

pub const Camera = @import("camera.zig").Camera;

const math = @import("math.zig");
pub const vec2 = math.vec2;
pub const rot2 = math.rot2;
pub const Transform2 = math.Transform2;
pub const Color = math.Color;
