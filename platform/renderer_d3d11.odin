#+build windows
package platform

import w "core:sys/windows"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"

Vertex :: struct {
	position: [2]f32,
}
vertices := []Vertex{
	{position = {-0.5, -0.5}},
	{position = {+0.0, +0.5}},
	{position = {+0.5, -0.5}},
}

d3dobj : struct {
	swapchain: ^dxgi.ISwapChain,
	device: ^d3d11.IDevice,
	ctx: ^d3d11.IDeviceContext,
	render_target_view: ^d3d11.IRenderTargetView,
}

d3d11_init :: proc() {
	hr: d3d11.HRESULT = ---

	scd: dxgi.SWAP_CHAIN_DESC
	scd.BufferDesc.Format = .R16G16B16A16_FLOAT
	scd.BufferUsage = {.RENDER_TARGET_OUTPUT}
	scd.BufferCount = 2
	scd.OutputWindow = platform_hwnd
	scd.SampleDesc.Count = 1
	scd.SwapEffect = .FLIP_DISCARD
	scd.Windowed = true
	hr = d3d11.CreateDeviceAndSwapChain(nil, .HARDWARE, nil, {.DEBUG} when ODIN_DEBUG else {}, nil, 0, d3d11.SDK_VERSION, &scd, &d3dobj.swapchain, &d3dobj.device, nil, &d3dobj.ctx)
	if w.FAILED(hr) { d3d11_deinit(); return }
}

d3d11_deinit :: proc() {
	if d3dobj.ctx != nil do d3dobj.ctx->Release()
	if d3dobj.device != nil do d3dobj.device->Release()
	if d3dobj.swapchain != nil do d3dobj.swapchain->Release()
	if d3dobj.render_target_view != nil do d3dobj.render_target_view->Release()
	d3dobj = {}
}

d3d11_resize :: proc() {
	if d3dobj.swapchain == nil do return

	hr: d3d11.HRESULT = ---

	texture: ^d3d11.ITexture2D
	hr = d3dobj.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, cast(^rawptr) &texture)
	if w.FAILED(hr) { d3d11_deinit(); return }
	d3dobj.device->CreateRenderTargetView(texture, nil, &d3dobj.render_target_view)
	texture->Release()
}

d3d11_present :: proc() {
	if d3dobj.swapchain == nil do return

	hr: d3d11.HRESULT = ---

	d3dobj.ctx->ClearRenderTargetView(d3dobj.render_target_view, &{0.6, 0.2, 0.2, 1.0})
	d3dobj.ctx->OMSetRenderTargets(1, &d3dobj.render_target_view, nil)
	d3dobj.ctx->RSSetViewports(1, &d3d11.VIEWPORT{Width = f32(platform_size.x), Height = f32(platform_size.y), MaxDepth = 1.0})

	vertex_buffer: ^d3d11.IBuffer
	vbd: d3d11.BUFFER_DESC
	vbd.ByteWidth = u32(len(vertices) * size_of(Vertex))
	vbd.Usage = .DEFAULT
	vbd.BindFlags = {.VERTEX_BUFFER}
	vbd.StructureByteStride = size_of(Vertex)
	vsr: d3d11.SUBRESOURCE_DATA
	vsr.pSysMem = raw_data(vertices)
	hr = d3dobj.device->CreateBuffer(&vbd, &vsr, &vertex_buffer)
	if w.FAILED(hr) { d3d11_deinit(); return }
	defer vertex_buffer->Release()

	vsrc := `
	struct VSOut {
		float3 color : Color;
		float4 pos : SV_Position;
	};

	VSOut main(float2 pos : Position, float3 color : Color) {
		VSOut vso;
		vso.pos = float4(pos, 0.0, 1.0);
		vso.color = color;
		return vso;
	}
	`
	vertex_shader_blob: ^d3d11.IBlob
	hr = d3d_compiler.Compile(raw_data(vsrc), len(vsrc), nil, nil, nil, "main", "vs_5_0", 0, 0, &vertex_shader_blob, nil)
	if w.FAILED(hr) { d3d11_deinit(); return }

	vertices_stride: u32 = size_of(Vertex)
	vertices_offset: u32 = 0
	d3dobj.ctx->IASetVertexBuffers(0, 1, &vertex_buffer, &vertices_stride, &vertices_offset)
	d3dobj.ctx->IASetPrimitiveTopology(.TRIANGLELIST)
	d3dobj.ctx->Draw(u32(len(vertices)), 0)

	d3dobj.swapchain->Present(1, {})
}
