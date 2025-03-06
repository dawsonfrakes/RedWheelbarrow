Render_API :: enum {
	NONE :: 0;
	D3D11 :: 1;
}

Platform_Renderer :: struct {
	init: ();
	deinit: ();
	resize: ();
	present: ();
}

none_renderer :: Platform_Renderer.{
	init = () {},
	deinit = () {},
	resize = () {},
	present = () {},
};

#load "renderer_d3d11.jai";

renderer_switch_api :: (new_api: Render_API) {
	set_before := platform_renderer != null;
	if set_before platform_renderer.deinit();
	if #complete new_api == {
		case .NONE;
			platform_renderer = *none_renderer;
		case .D3D11;
			platform_renderer = *d3d11_renderer;
	}
	platform_renderer.init();
	if set_before platform_renderer.resize();
}
