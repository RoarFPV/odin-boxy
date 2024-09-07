package boxy

import b2 "vendor:box2d"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "core:fmt"
import "core:math/rand"
import "core:strings"

GameState :: enum {
	Reset,
	MainMenu,
	Load,
	Play,
	GameOver,
}

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
	alpha:       byte,
}

vanilia_milkshake :: [?][4]byte {
	{0x28, 0x28, 0x2e, 255}, // 0
	{0x6c, 0x56, 0x71, 255}, // 1
	{0xd9, 0xc8, 0xbf, 255}, // 2
	{0xf9, 0x82, 0x84, 255}, // 3
	{0xb0, 0xa9, 0xe4, 255}, // 4
	{0xac, 0xcc, 0xe4, 255}, // 5
	{0xb3, 0xe3, 0xda, 255}, // 6
	{0xfe, 0xaa, 0xe4, 255}, // 7
	{0x87, 0xa8, 0x89, 255}, // 8
	{0xb0, 0xeb, 0x93, 255}, // 9
	{0xe9, 0xf5, 0x9d, 255}, // 10
	{0xff, 0xe6, 0xc6, 255}, // 11
	{0xde, 0xa3, 0x8b, 255}, // 12
	{0xff, 0xc3, 0x84, 255}, // 13
	{0xff, 0xf7, 0xa0, 255}, // 14
	{0xff, 0xf7, 0xe4, 255}, // 15
}

Object :: struct {
	id:           u32,
	name:         string,
	texture:      string,
	textureScale: f32,
	radius:       f32,
	score:        u32,
}


objectTable := [?]Object {
	{0, "0", "assets/alienBeige.png", 1.0, 0.2, 10},
	{1, "1", "assets/alienBlue.png", 1.0, 0.4, 20},
	{2, "2", "assets/alienGreen.png", 1.0, 0.6, 40},
	{3, "3", "assets/alienPink.png", 1.0, 0.8, 80},
	{4, "4", "assets/alienYellow.png", 1.0, 1, 160},
}


// Game
score: u64 = 0
game_state: GameState = .MainMenu
top_sensor: ^Entity
over_sensor: ^Entity
over_sensor_enter_sec: f64
over_sensor_wait_sec :: 4

ShapeMap :: map[b2.ShapeId]u32

shapes_on_top := ShapeMap{}
shapes_over_top := ShapeMap{}

palette := vanilia_milkshake
width :: 720
height :: 1024
unit_scale :: 70.0
inv_unit_scale :: 1.0 / unit_scale
play_area :: [2]f32{11, 15}

scaled_width :: width * inv_unit_scale
scaled_height :: height * inv_unit_scale


// Entities
EntityMap :: map[u32]Entity

entities_dynamic := EntityMap{}
entities_static := EntityMap{}

shape_map := map[b2.ShapeId]u32{}
shape_color_map := map[b2.ShapeId]byte{}

textures := map[string]rl.Texture{}

nextEntityId: u32 = 1


// Input
leftDown := false

// Drop
drop_wait :: 0.5
drop_height :: 2.0
drop_max_index :: 2
drop_entity: ^Entity
last_drop_time: f64


// Physics
gravity :: [2]f32{0, 30}
restitution :: 0.1
worldDef: b2.WorldDef
world: b2.WorldId

texture_load :: proc(path: string) -> rl.Texture {
	t, found := textures[path]
	if found {
		return t
	}

	t = rl.LoadTexture(strings.clone_to_cstring(path))
	rl.SetTextureFilter(t, .TRILINEAR)
	textures[path] = t
	return t

}

create_entity :: proc(
	pos: [2]f32,
	rot: f32,
	color: byte,
	isDynamicBody: bool,
	alpha: byte = 255,
) -> ^Entity {

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
	entity.alpha = alpha

	return entity
}

remove_entity_from_map :: proc(entities: ^EntityMap, id: u32) {
	e, found := entities[id]
	if !found {return}

	remove_entity(&e)

	delete_key(entities, id)
}

remove_entity :: proc(e: ^Entity) {
	texture: rl.Texture
	switch shape in e.shape {
	case BoxShape:
		texture = shape.texture
	case CircleShape:
		texture = shape.texture
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
	alpha: byte = 255,
	texturePath: string = "",
	isSensor: bool = false,
) -> ^Entity {
	entity := create_entity(pos, rot, color, isDynamicBody, alpha = alpha)
	texture := texture_load(texturePath)

	entity.shape = BoxShape{size, texture}

	box := b2.MakeBox(size.x / 2, size.y / 2)

	box_shape_def := b2.DefaultShapeDef()
	box_shape_def.isSensor = isSensor

	// box_shape_def.restitution = restitution
	entity.body_shape = b2.CreatePolygonShape(entity.body, box_shape_def, box)

	if entity.dynamicBody {
		b2.Shape_EnableContactEvents(entity.body_shape, true)
		shape_map[entity.body_shape] = entity.id
		shape_color_map[entity.body_shape] = entity.color
	}

	return entity
}

create_circle :: proc(
	pos: [2]f32,
	rot: f32,
	radius: f32,
	color: byte,
	isDynamicBody: bool,
	alpha: byte = 255,
	texturePath: string = "",
) -> ^Entity {
	entity := create_entity(pos, rot, color, isDynamicBody, alpha)
	texture := texture_load(texturePath)

	entity.shape = CircleShape{radius, texture}

	circle := b2.Circle{{}, radius}
	shape_def := b2.DefaultShapeDef()
	shape_def.restitution = restitution
	shapeId := b2.CreateCircleShape(entity.body, shape_def, circle)
	entity.body_shape = shapeId


	if entity.dynamicBody {
		b2.Shape_EnableContactEvents(shapeId, true)
		shape_map[entity.body_shape] = entity.id
		shape_color_map[entity.body_shape] = entity.color
	}

	return entity
}

draw_entity :: proc(e: ^Entity) {
	c := color(e.color)
	c[3] = e.alpha

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
				rl.WHITE,
			)

			// rlgl.Scalef(inv_unit_scale, inv_unit_scale, inv_unit_scale)
			// rl.DrawText(rl.TextFormat("%02i", e.color), 0,0,20, c)

		} else {
			rl.DrawCircleV(e.pos, shape.radius, c)
		}
	}
}

draw_entities :: proc() {


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

	for id, &e in entities_static {
		draw_entity(&e)
	}
}

physics_init :: proc() {
	worldDef = b2.DefaultWorldDef()
	worldDef.gravity = gravity
	// worldDef.contactPushoutVelocity = 100000.0
	world = b2.CreateWorld(worldDef)

	// b2.SetLengthUnitsPerMeter(unit_scale)

}

physics_shudown :: proc() {
	if !b2.World_IsValid(world) {
		return
	}

	b2.DestroyWorld(world)
	world = {}
}

physics_update :: proc(dt: f32) -> bool {
	b2.World_Step(world, dt, 8)

	{
		sensor_events := b2.World_GetSensorEvents(world)
		// fmt.printfln("sensor events begin: {}, end: {}", sensor_events.beginCount, sensor_events.endCount)
		{
			count := sensor_events.beginCount
			events := sensor_events.beginEvents[:count]
			begin_loop: for event in events {
				if drop_entity != nil {
					(event.visitorShapeId == drop_entity.body_shape) or_continue begin_loop
				}
				switch event.sensorShapeId {
				case top_sensor.body_shape:
					shapes_on_top[event.visitorShapeId] = 1
				case over_sensor.body_shape:
					shapes_over_top[event.visitorShapeId] = 1
				}
			}
		}

		{
			count := sensor_events.endCount
			events := sensor_events.endEvents[:count]
			end_loop: for event in events {
				if drop_entity != nil {
					(event.visitorShapeId == drop_entity.body_shape) or_continue end_loop
				}
				switch event.sensorShapeId {
				case top_sensor.body_shape:
					delete_key(&shapes_on_top, event.visitorShapeId)
				case over_sensor.body_shape:
					delete_key(&shapes_over_top, event.visitorShapeId)
				}
			}
		}
	}

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


		data := objectTable[ea.color]

		score += auto_cast data.score

		// remove both
		remove_entity_from_map(&entities_dynamic, ea.id)
		remove_entity_from_map(&entities_dynamic, eb.id)

		next := data.id + 1

		if next < len(objectTable) {
			data = objectTable[next]
			create_circle(mid, 0, data.radius, auto_cast next, true, 255, data.texture)
		}
	}

	return true
}

color :: proc(index: byte) -> rl.Color {
	return rl.Color(palette[index < len(palette) ? index : len(palette) - 1])
}

radius_from_color :: proc(index: int) -> f32 {
	return auto_cast (index * index) * 0.01
}


game_update_input :: proc() {
	if !rl.IsCursorHidden() {
		rl.HideCursor()
		// rl.DisableCursor()
	}

	mousePos := rl.GetMousePosition()
	worldMouse := rl.GetScreenToWorld2D(mousePos, camera)
	x := clamp(worldMouse.x, -play_area.x / 2 + 0.7, play_area.x / 2 - 0.7)
	drop_pos := [2]f32{x, drop_height}
	t := rl.GetTime()

	if drop_entity != nil {
		drop_entity.pos = drop_pos
		b2.Body_SetTransform(drop_entity.body, drop_pos, b2.Rot_identity)

	} else if (last_drop_time + drop_wait) < t {
		assert( drop_max_index < len(objectTable))
		c := rand.int_max(drop_max_index+1)

		data := objectTable[c]

		drop_entity = create_circle(
			drop_pos,
			0,
			data.radius,
			u8(data.id),
			true,
			255,
			data.texture,
		)

		b2.Body_Disable(drop_entity.body)
		b2.Shape_EnableContactEvents(drop_entity.body_shape, false)

	}

	if rl.IsMouseButtonDown(.LEFT) {
		if !leftDown {

			if drop_entity != nil {
				b2.Body_SetTransform(drop_entity.body, drop_entity.pos, b2.Rot_identity)
				b2.Body_Enable(drop_entity.body)
				b2.Shape_EnableContactEvents(drop_entity.body_shape, true)
				last_drop_time = t
				drop_entity = nil
			}
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

		camera.offset = mousePos
		camera.target = worldMouse
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

game_update_state :: proc(dt: f32) {
	switch game_state {
	case .MainMenu:
		game_render()
		menu_update()

	case .Reset:
		for id, &entity in entities_dynamic {
			remove_entity(&entity)
		}

		for id, &entity in entities_static {
			remove_entity(&entity)
		}

		drop_entity = nil

		clear_map(&entities_dynamic)
		clear_map(&entities_static)

		clear_map(&shapes_on_top)
		clear_map(&shapes_over_top)

		// for id, &texture in textures {
		// 	rl.UnloadTexture(texture)
		// }

		physics_shudown()

		game_state = .Load

	case .Load:
		physics_init()
		game_init()
		game_state = .Play

	case .Play:
		physics_update(dt)
		game_update_input()
		game_check_end()
		game_render()
		game_render_score()

		if rl.IsKeyDown(rl.KeyboardKey.ENTER) {
			game_state = .GameOver
		}

	case .GameOver:
		if rl.IsCursorHidden() {
			rl.ShowCursor()
			rl.EnableCursor()
		}

		game_render()
		game_render_score()
		{
			size := rl.MeasureText("GAME OVER", 40)
			// rl.GuiButton({rl.GetScreenWidth() / 2, rl.GetScreenWidth() / 2, 100, 100}, "GAME OVER")
			rl.DrawText(
				"GAME OVER",
				rl.GetScreenWidth() / 2 - size / 2,
				rl.GetScreenHeight() / 2 - 20,
				40,
				color(3),
			)

			if rl.GuiButton({width / 2 - 50, height / 2, 100, 50}, "Restart") ||
			   rl.IsKeyDown(rl.KeyboardKey.SPACE) {
				game_state = .MainMenu
			}
		}

	}
}

menu_update :: proc() {
	// rl.DrawText("Play", rl.GetScreenWidth() / 2, rl.GetScreenHeight() / 2, 30, color(12))

	if rl.GuiButton({width / 2 - 50, height / 2 - 25, 100, 50}, "PLAY") ||
	   rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		game_state = .Reset
	}
}

game_render :: proc() {
	rl.BeginMode2D(camera)
	defer rl.EndMode2D()

	if drop_entity != nil {
		rl.DrawLineEx(drop_entity.pos, drop_entity.pos + {0, 40}, 0.1, color(15))
	}
	draw_entities()

}

game_render_score :: proc() {
	rl.DrawText(rl.TextFormat("Score: {}", score), 100, 10, 30, color(0))
	rl.DrawLineEx({-play_area.x, 1}, {play_area.x, 1}, 0.2, color(0))
}

game_init :: proc() {
	// floor
	create_box({0, play_area.y}, 0, {50, 1}, 11, false) //, "assets/grass.png")

	// walls
	create_box({play_area.x / 2, 4}, 0, {1, 50}, 11, false) //, "assets/grass.png")
	create_box({-play_area.x / 2, 4}, 0, {1, 50}, 11, false) //, "assets/grass.png")

	over_sensor = create_box({0, 1}, 0, {play_area.x, 3}, 5, false, isSensor = true, alpha = 127)
	top_sensor = create_box(
		{0, 2.5},
		0,
		{play_area.x, 1.0},
		4,
		false,
		isSensor = true,
		alpha = 127,
	)
}


game_check_end :: proc() {
	if len(shapes_over_top) < 1 {
		return
	}

	for shape, i in shapes_over_top {
		if !(shape in shapes_on_top) {
			game_state = .GameOver
			return
		}
	}
}
main :: proc() {

	rl.InitWindow(width, height, "boxy")
	defer rl.CloseWindow()

	rl.SetTargetFPS(165)

	pause := false
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(color(6))

		game_update_state(dt)

		rl.DrawFPS(rl.GetScreenWidth() - 100, 10)


	}
}
