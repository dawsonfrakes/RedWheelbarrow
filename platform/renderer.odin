package platform

import "../game"

Render_API :: enum {
	NONE = 1 << 0,
	D3D11 = 1 << 1,
}

Render_APIs :: bit_set[Render_API; u32];

Renderer :: struct {
	init: proc(),
	deinit: proc(),
	resize: proc(),
	present: proc(),
	procs: game.Renderer_Procs,
}

renderer_none := Renderer{
	init = proc() {},
	deinit = proc() {},
	resize = proc() {},
	present = proc() {},
	procs = {
		clear_color = proc(color: [4]f32, index: u32) {},
		clear_depth = proc(depth: f32) {},
		rect = proc(position, size: [2]f32, color: [4]f32, texcoords: [2][2]f32, rotation: f32, texture_index: u32, z_index: i32) {}
	},
}

platform_render_apis := Render_APIs({.NONE} | {.D3D11}) when ODIN_OS == .Windows else Render_APIs({.NONE})
platform_renderer: ^Renderer
platform_renderers := [Render_API]^Renderer{
	.NONE = &renderer_none,
	.D3D11 = &renderer_d3d11 when ODIN_OS == .Windows else &renderer_none,
}

renderer_switch_api :: proc(new_api: Render_API) {
	assert(new_api in platform_render_apis)
	previous_exists := platform_renderer != nil
	if previous_exists do platform_renderer.deinit()
	platform_renderer = platform_renderers[new_api]
	platform_renderer.init()
	if previous_exists do platform_renderer.resize()
}
