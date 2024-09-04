package boxy

import b2 "vendor:box2d"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "core:fmt"
import "core:math/rand"

Shape :: union {
	CircleShape,
	BoxShape,
}

CircleShape :: struct {
	radius:  f32,
	texture: rl.Texture,
}

BoxShape :: struct {
	size:    [2]f32,
	texture: rl.Texture,
}

Entity :: struct {
	id:          u32,
	body:        b2.BodyId,
	body_shape:  b2.ShapeId,
	radius:      f32,
	color:       byte,
	shape:       Shape,
	pos:         [2]f32,
	rot:         f32,
	dynamicBody: bool,
}

vanilia_milkshake :: [?][4]byte {
	{0x28, 0x28, 0x2e, 255},
	{0x6c, 0x56, 0x71, 255},
	{0xd9, 0xc8, 0xbf, 255},
	{0xf9, 0x82, 0x84, 255},
	{0xb0, 0xa9, 0xe4, 255},
	{0xac, 0xcc, 0xe4, 255},
	{0xb3, 0xe3, 0xda, 255},
	{0xfe, 0xaa, 0xe4, 255},
	{0x87, 0xa8, 0x89, 255},
	{0xb0, 0xeb, 0x93, 255},
	{0xe9, 0xf5, 0x9d, 255},
	{0xff, 0xe6, 0xc6, 255},
	{0xde, 0xa3, 0x8b, 255},
	{0xff, 0xc3, 0x84, 255},
	{0xff, 0xf7, 0xa0, 255},
	{0xff, 0xf7, 0xe4, 255},
}

palette := vanilia_milkshake
width :: 720
height :: 1024
unit_scale :: 70.0
inv_unit_scale :: 1.0 / unit_scale

scaled_width :: width* inv_unit_scale
scaled_height :: height * inv_unit_scale

entities_dynamic := map[u32]Entity{}
entities_static := map[u32]Entity{}

shape_map := map[b2.ShapeId]u32{}
shape_color_map := map[b2.ShapeId]byte{}

worldDef: b2.WorldDef
world: b2.WorldId
nextEntityId: u32 = 1

score: u64 = 0

create_entity :: proc(pos: [2]f32, rot: f32, color: byte, isDynamicBody: bool) -> ^Entity {

	id := nextEntityId

	// fmt.printfln("+entity: {}", id)
	nextEntityId += 1

	entity: ^Entity = nil
	if isDynamicBody {
		entities_dynamic[id] = Entity{}
		entity = &entities_dynamic[id]
	} else {
		entities_static[id] = Entity{}
		entity = &entities_static[id]
	}

	entity.id = id
	body_def := b2.DefaultBodyDef()
	body_def.position = pos
	body_def.type = isDynamicBody ? .dynamicBody : .staticBody
	body_def.automaticMass = true
	// body_def.enableSleep = true
	entity.body = b2.CreateBody(world, body_def)
	entity.pos = pos
	entity.rot = rot
	entity.dynamicBody = isDynamicBody
	entity.color = color

	return entity
}

remove_dynamic_entity :: proc(id: u32) {
	e, ok := entities_dynamic[id]
	if !ok {
		return
	}

	delete_key(&entities_dynamic, id)
	texture: rl.Texture
	switch shape in e.shape {
	case BoxShape:
		texture = shape.texture
	case CircleShape:
		texture = shape.texture
	}

	if texture.id != 0 {
		rl.UnloadTexture(texture)
	}

	delete_key(&shape_map, e.body_shape)
	delete_key(&shape_color_map, e.body_shape)

	b2.DestroyShape(e.body_shape)
	b2.DestroyBody(e.body)

	


}

create_box :: proc(
	pos: [2]f32,
	rot: f32,
	size: [2]f32,
	color: byte,
	isDynamicBody: bool,
	texturePath: cstring = nil,
) {
	entity := create_entity(pos, rot, color, isDynamicBody)
	texture := rl.LoadTexture(texturePath)

	entity.shape = BoxShape{size, texture}

	box := b2.MakeBox(size.x / 2, size.y / 2)

	box_shape_def := b2.DefaultShapeDef()
	box_shape_def.restitution = 1
	entity.body_shape = b2.CreatePolygonShape(entity.body, box_shape_def, box)
	
	if entity.dynamicBody {
		b2.Shape_SetUserData(entity.body_shape, &entity)
		b2.Shape_EnableContactEvents(entity.body_shape, true)
		shape_map[entity.body_shape] = entity.id
		shape_color_map[entity.body_shape] = entity.color
	}
}

create_circle :: proc(
	pos: [2]f32,
	rot: f32,
	radius: f32,
	color: byte,
	isDynamicBody: bool,
	texturePath: cstring = nil,
) {
	entity := create_entity(pos, rot, color, isDynamicBody)
	texture := rl.LoadTexture(texturePath)

	entity.shape = CircleShape{radius, texture}

	circle := b2.Circle{{}, radius}
	shape_def := b2.DefaultShapeDef()
	shape_def.restitution = 0.1
	shapeId := b2.CreateCircleShape(entity.body, shape_def, circle)
	entity.body_shape = shapeId


	if entity.dynamicBody {
		b2.Shape_SetUserData(shapeId, entity)
		b2.Shape_EnableContactEvents(shapeId, true)
		shape_map[entity.body_shape] = entity.id
		shape_color_map[entity.body_shape] = entity.color
	}
}

draw_entity :: proc(e: ^Entity) {
	c := color(e.color)


	switch shape in e.shape {
	case BoxShape:
		p := e.pos + shape.size * -0.5
		if shape.texture.id != 0 {
			rl.DrawTextureEx(shape.texture, e.pos, rl.RAD2DEG * e.rot, inv_unit_scale, c)
		} else {
			rl.DrawRectangleV(p, shape.size, c)
		}
	case CircleShape:
		p := e.pos + shape.radius * -0.5
		if shape.texture.id != 0 {
			rlgl.PushMatrix()
			defer rlgl.PopMatrix()

			rlgl.Translatef(e.pos.x, e.pos.y, 0)
			rlgl.Rotatef(rl.RAD2DEG * e.rot, 0, 0, 1)

			rl.DrawTextureEx(
				shape.texture,
				{-shape.radius, -shape.radius},
				0,
				inv_unit_scale * (shape.radius / 0.5),
				c,
			)

			// rlgl.Scalef(inv_unit_scale, inv_unit_scale, inv_unit_scale)
			// rl.DrawText(rl.TextFormat("%02i", e.color), 0,0,20, c)

		} else {
			rl.DrawCircleV(e.pos, shape.radius, c)
		}
	}
}

draw_entities :: proc() {
	for id, &e in entities_static {
		draw_entity(&e)
	}

	for id, &e in entities_dynamic {
		t := b2.Body_GetTransform(e.body)
		w: [2]f32 = {}
		r: f32 = 0.5
		switch shape in e.shape {
		case BoxShape:
			w = b2.Body_GetWorldPoint(e.body, shape.size * -0.5)
			r = shape.size.x * 0.5
		case CircleShape:
			w = t.p //b2.Body_GetWorldPoint(e.body, shape.radius)
			r = shape.radius
			c := color(7)
			c[3] = 127

			rl.DrawCircleV(t.p, r, c)
		}

		// fmt.printfln("pos: {}", bodyPos)
		e.pos = w
		e.rot = b2.Rot_GetAngle(t.q)
		draw_entity(&e)
	}
}

physics_init :: proc() {
	worldDef = b2.DefaultWorldDef()
	worldDef.gravity = b2.Vec2{0, 10}
	worldDef.contactPushoutVelocity = 100000.0
	world = b2.CreateWorld(worldDef)

	// b2.SetLengthUnitsPerMeter(unit_scale)

}

physics_update :: proc(dt: f32) -> bool {
	b2.World_Step(world, dt, 16)

	events := b2.World_GetContactEvents(world)
	c := events.beginCount
	(c > 0) or_return
	begins := events.beginEvents[:c]

	Matching :: struct {
		a: b2.ShapeId,
		b: b2.ShapeId,
	}

	matches := [dynamic]Matching{}

	begins_loop: for event in begins {
		a_color, afound := shape_color_map[event.shapeIdA]
		b_color, bfound := shape_color_map[event.shapeIdB]

		(afound && bfound) or_continue begins_loop
		(a_color == b_color) or_continue begins_loop


		append(&matches, Matching{event.shapeIdA, event.shapeIdB})

	}

	matches_loop: for m in matches {
		a, afound := shape_map[m.a]
		b, bfound := shape_map[m.b]

		(afound && bfound) or_continue matches_loop

		ea, ea_found := entities_dynamic[a]
		eb, eb_found := entities_dynamic[b]

		(ea_found && eb_found) or_continue matches_loop


		mid := ea.pos + (eb.pos - ea.pos) / 2
		color := ea.color

		ds := u64(ea.color)
		score += ds * ds

		// remove both
		remove_dynamic_entity(ea.id)
		remove_dynamic_entity(eb.id)

		create_circle(
			mid,
			0,
			radius_from_color(auto_cast (color + 1)),
			color + 1,
			true,
			"assets/alienBlue.png",
		)
	}

	return true
}

color :: proc(index: byte) -> rl.Color {
	return rl.Color(palette[index < len(palette) ? index : len(palette) - 1])
}

radius_from_color :: proc(index: int) -> f32 {
	return auto_cast (index * index) * 0.01
}

leftDown := false
update_input :: proc() {

	if rl.IsMouseButtonDown(.LEFT) {
		if !leftDown {
			mousePos := rl.GetMousePosition()
			worldMouse := rl.GetScreenToWorld2D(mousePos, camera)
			c := 1 + rand.int_max(len(palette) - 2)
			create_circle(
				worldMouse,
				0,
				auto_cast (c * c) * 0.01,
				auto_cast c,
				true,
				"assets/alienYellow.png",
			)
			leftDown = true
		}
	} else {
		leftDown = false
	}

	if rl.IsMouseButtonDown(.RIGHT) {
		// rl.GetScreenToWorld2D(rl.GetMou)
		delta := rl.GetMouseDelta() * -1.0 / camera.zoom
		camera.target += delta
	}

	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		zoomIncrement :: 1
		mousePos := rl.GetMousePosition()
		camera.offset = mousePos
		camera.target = rl.GetScreenToWorld2D(mousePos, camera)
		camera.zoom += rl.GetMouseWheelMove() * zoomIncrement
		if camera.zoom < zoomIncrement {
			camera.zoom = zoomIncrement
		}
	}
}

camera := rl.Camera2D {
	target = {scaled_width / -2, 0},
	zoom   = unit_scale,
}

main :: proc() {

	rl.InitWindow(width, height, "boxy")
	defer rl.CloseWindow()


	physics_init()

	// floor
	create_box({0, 15}, 0, {50, 1}, 9, false) //, "assets/grass.png")

	// walls
	create_box({5.5, 4}, 0, {1, 50}, 10, false) //, "assets/grass.png")
	create_box({-5.5, 4}, 0, {1, 50}, 11, false) //, "assets/grass.png")

	create_circle({0, 0}, 0, 0.5, 3, true, "assets/alienBeige.png")
	create_box({0, 0}, 0, {1.0, 1.0}, 4, true, "assets/grass.png")


	rl.SetTargetFPS(165)

	pause := false
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		if !pause {
			physics_update(dt)
		}

		update_input()

		{
			rl.BeginDrawing()
			defer rl.EndDrawing()

			rl.ClearBackground(color(0))

			{
				rl.BeginMode2D(camera)
				defer rl.EndMode2D()


				// rlgl.PushMatrix()
				// rlgl.Translatef(0, 25 * 1, 0)
				// rlgl.Rotatef(90, 1, 0, 0)
				// rl.DrawGrid(100, 1)
				// rlgl.PopMatrix()

				draw_entities()
			}

			rl.DrawFPS(rl.GetScreenWidth() - 100, 10)
			rl.DrawText(rl.TextFormat("Score: {}", score), 100, 10, 30, color(6))
		}
	}
}
