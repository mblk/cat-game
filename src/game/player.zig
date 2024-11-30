const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;

const zbox = @import("zbox");
const b2 = zbox.API;

pub const Player = struct {
    world_id: b2.b2WorldId,

    body_id: b2.b2BodyId,

    pub fn create(world_id: b2.b2WorldId) Player {
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position = b2.b2Vec2{
            .x = 0,
            .y = 0,
        };
        body_def.fixedRotation = true;

        const body_id = b2.b2CreateBody(world_id, &body_def);

        // head
        {
            var circle = b2.b2Circle{
                .center = b2.b2Vec2{ .x = 0, .y = 0.5 },
                .radius = 0.4,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 1.0;
            shape_def.friction = 0.1;

            _ = b2.b2CreateCircleShape(body_id, &shape_def, &circle);
        }

        // body front
        {
            var circle = b2.b2Circle{
                .center = b2.b2Vec2{ .x = 0, .y = 0.0 },
                .radius = 0.5,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 1.0;
            shape_def.friction = 0.1;

            _ = b2.b2CreateCircleShape(body_id, &shape_def, &circle);
        }

        // leg1
        {
            var circle = b2.b2Circle{
                .center = b2.b2Vec2{ .x = -0.1, .y = -0.5 },
                .radius = 0.1,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 1.0;
            shape_def.friction = 0.1;

            _ = b2.b2CreateCircleShape(body_id, &shape_def, &circle);
        }

        // leg2
        {
            var circle = b2.b2Circle{
                .center = b2.b2Vec2{ .x = 0.1, .y = -0.5 },
                .radius = 0.1,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 1.0;
            shape_def.friction = 0.1;

            _ = b2.b2CreateCircleShape(body_id, &shape_def, &circle);
        }

        return Player{
            .world_id = world_id,
            .body_id = body_id,
        };
    }

    pub fn update(self: *Player, dt: f32, input: *engine.InputState) void {

        //
        _ = dt;

        //const player_position = b2.b2Body_GetPosition(self.body_id);
        const player_velocity = b2.b2Body_GetLinearVelocity(self.body_id);

        const player_mass = b2.b2Body_GetMass(self.body_id);
        //const world_gravity = b2.b2World_GetGravity(self.world_id);

        // move?
        var target_vx: f32 = 0;
        if (input.getKeyState(.a)) {
            target_vx -= 10;
        }
        if (input.getKeyState(.d)) {
            target_vx += 10;
        }

        const curr_vx = player_velocity.x;
        const err_vx = target_vx - curr_vx;
        const f_x = err_vx * 2.5;

        if (@abs(f_x) > 0.1) {
            b2.b2Body_ApplyForceToCenter(self.body_id, b2.b2Vec2{ .x = f_x, .y = 0 }, true);
        }

        // jump?
        if (input.consumeKeyDownEvent(.space)) {
            const curr_vy = player_velocity.y;
            const target_vy = 10.0;
            const err_vy = target_vy - curr_vy;
            const i_y = player_mass * err_vy;

            b2.b2Body_ApplyLinearImpulseToCenter(self.body_id, b2.b2Vec2{ .x = 0, .y = i_y }, true);
        }
    }

    pub fn render(self: *Player, dt: f32, renderer: *engine.Renderer2D) void {
        _ = self;
        _ = dt;
        _ = renderer;
    }
};
