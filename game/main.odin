package game

Renderer_Procs :: struct {
	clear_color: proc(color: [4]f32, index := u32(0)),
	clear_depth: proc(depth: f32),
	rect: proc(position, size: [2]f32, color: [4]f32, texcoords: [2][2]f32, rotation: f32, texture_index: u32, z_index: i32),
}

Renderer :: struct {
	using procs: Renderer_Procs,
}

Input :: struct {
	delta: f32,
}

rect :: proc(renderer: ^Renderer, position, size: [2]f32, color: [4]f32, rotation := f32(0.0), z_index := i32(-1)) {
	renderer.rect(position, size, color, {0.0, 1.0}, rotation, 0, z_index)
}

update_and_render :: proc(input: ^Input, renderer: ^Renderer) {
	renderer.clear_color({0.6, 0.2, 0.2, 1.0})
	renderer.clear_depth(0.0)
	rect(renderer, 500.0, 100.0, {1.0, 0.0, 1.0, 1.0})
}
