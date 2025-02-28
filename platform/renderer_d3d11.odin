#+build windows
package platform

import "core:math/linalg"
import w "core:sys/windows"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"

Vertex :: struct {
	position: [3]f32,
	color: [3]f32,
}
indices := []u16{
	0,2,1, 2,3,1,
	1,3,5, 3,7,5,
	2,6,3, 3,6,7,
	4,5,7, 4,7,6,
	0,4,2, 2,4,6,
	0,1,4, 1,5,4,
}
vertices := []Vertex{
	{position = {-1.0, -1.0, -1.0}, color = {1.0, 0.0, 0.0}},
	{position = {+1.0, -1.0, -1.0}, color = {0.0, 1.0, 0.0}},
	{position = {-1.0, +1.0, -1.0}, color = {0.0, 0.0, 1.0}},
	{position = {+1.0, +1.0, -1.0}, color = {1.0, 1.0, 0.0}},
	{position = {-1.0, -1.0, +1.0}, color = {1.0, 0.0, 1.0}},
	{position = {+1.0, -1.0, +1.0}, color = {0.0, 1.0, 1.0}},
	{position = {-1.0, +1.0, +1.0}, color = {0.0, 0.0, 0.0}},
	{position = {+1.0, +1.0, +1.0}, color = {1.0, 1.0, 1.0}},
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

	if d3dobj.render_target_view != nil do d3dobj.render_target_view->Release()
	d3dobj.render_target_view = nil

	hr = d3dobj.swapchain->ResizeBuffers(0, 0, 0, {}, {})
	if w.FAILED(hr) { d3d11_deinit(); return }

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
	{
		vbd: d3d11.BUFFER_DESC
		vbd.ByteWidth = u32(len(vertices) * size_of(Vertex))
		vbd.Usage = .DEFAULT
		vbd.BindFlags = {.VERTEX_BUFFER}
		vbd.StructureByteStride = size_of(Vertex)
		vsr: d3d11.SUBRESOURCE_DATA
		vsr.pSysMem = raw_data(vertices)
		hr = d3dobj.device->CreateBuffer(&vbd, &vsr, &vertex_buffer)
		if w.FAILED(hr) { d3d11_deinit(); return }
	}
	defer vertex_buffer->Release()

	index_buffer: ^d3d11.IBuffer
	{
		vbd: d3d11.BUFFER_DESC
		vbd.ByteWidth = u32(len(indices) * size_of(u16))
		vbd.Usage = .DEFAULT
		vbd.BindFlags = {.INDEX_BUFFER}
		vbd.StructureByteStride = size_of(u16)
		vsr: d3d11.SUBRESOURCE_DATA
		vsr.pSysMem = raw_data(indices)
		hr = d3dobj.device->CreateBuffer(&vbd, &vsr, &index_buffer)
		if w.FAILED(hr) { d3d11_deinit(); return }
	}
	defer index_buffer->Release()

	constant_buffer: ^d3d11.IBuffer
	{
		ConstantBuffer :: struct {
			transform: matrix[4, 4]f32,
		}

		cb := ConstantBuffer{
			transform = linalg.transpose(
				linalg.matrix4_infinite_perspective_f32(linalg.to_radians(f32(90.0)), f32(platform_size.x) / f32(platform_size.y), 0.1, flip_z_axis = false) *
				linalg.matrix4_translate_f32({linalg.sin(platform_clock) * 2, linalg.cos(platform_clock) * 2, 3.0})
			),
		}

		vbd: d3d11.BUFFER_DESC
		vbd.ByteWidth = size_of(ConstantBuffer)
		vbd.Usage = .DYNAMIC
		vbd.BindFlags = {.CONSTANT_BUFFER}
		vbd.CPUAccessFlags = {.WRITE}
		vsr: d3d11.SUBRESOURCE_DATA
		vsr.pSysMem = &cb
		hr = d3dobj.device->CreateBuffer(&vbd, &vsr, &constant_buffer)
		if w.FAILED(hr) { d3d11_deinit(); return }
	}
	defer constant_buffer->Release()

	vsrc := `
	struct VSOut {
		float3 color : Color;
		float4 pos : SV_Position;
	};

	cbuffer CBuf {
		matrix transform;
	};

	VSOut main(float3 pos : Position, float3 color : Color) {
		VSOut vso;
		vso.pos = mul(float4(pos, 1.0), transform);
		vso.color = color;
		return vso;
	}
	`
	vertex_shader_blob: ^d3d11.IBlob
	hr = d3d_compiler.Compile(raw_data(vsrc), len(vsrc), nil, nil, nil, "main", "vs_5_0", 0, 0, &vertex_shader_blob, nil)
	if w.FAILED(hr) { d3d11_deinit(); return }
	defer vertex_shader_blob->Release()

	vertex_shader: ^d3d11.IVertexShader
	hr = d3dobj.device->CreateVertexShader(vertex_shader_blob->GetBufferPointer(), vertex_shader_blob->GetBufferSize(), nil, &vertex_shader)
	if w.FAILED(hr) { d3d11_deinit(); return }
	defer vertex_shader->Release()

	psrc := `
	float4 main(float3 color : Color) : SV_Target {
		return float4(color, 1.0);
	}
	`
	pixel_shader_blob: ^d3d11.IBlob
	hr = d3d_compiler.Compile(raw_data(psrc), len(psrc), nil, nil, nil, "main", "ps_5_0", 0, 0, &pixel_shader_blob, nil)
	if w.FAILED(hr) { d3d11_deinit(); return }
	defer pixel_shader_blob->Release()

	pixel_shader: ^d3d11.IPixelShader
	hr = d3dobj.device->CreatePixelShader(pixel_shader_blob->GetBufferPointer(), pixel_shader_blob->GetBufferSize(), nil, &pixel_shader)
	if w.FAILED(hr) { d3d11_deinit(); return }
	defer pixel_shader->Release()

	ild := []d3d11.INPUT_ELEMENT_DESC{
		{"Position", 0, .R32G32B32_FLOAT, 0, u32(offset_of(Vertex, position)), .VERTEX_DATA, 0},
		{"Color", 0, .R32G32B32_FLOAT, 0, u32(offset_of(Vertex, color)), .VERTEX_DATA, 0},
	}
	il: ^d3d11.IInputLayout
	hr = d3dobj.device->CreateInputLayout(raw_data(ild), u32(len(ild)), vertex_shader_blob->GetBufferPointer(), vertex_shader_blob->GetBufferSize(), &il)
	if w.FAILED(hr) { d3d11_deinit(); return }
	defer il->Release()

	d3dobj.ctx->VSSetShader(vertex_shader, nil, 0)
	d3dobj.ctx->PSSetShader(pixel_shader, nil, 0)
	vertices_stride: u32 = size_of(Vertex)
	vertices_offset: u32 = 0
	d3dobj.ctx->VSSetConstantBuffers(0, 1, &constant_buffer)
	d3dobj.ctx->IASetInputLayout(il)
	d3dobj.ctx->IASetVertexBuffers(0, 1, &vertex_buffer, &vertices_stride, &vertices_offset)
	d3dobj.ctx->IASetIndexBuffer(index_buffer, .R16_UINT, 0)
	d3dobj.ctx->IASetPrimitiveTopology(.TRIANGLELIST)
	d3dobj.ctx->DrawIndexed(u32(len(indices)), 0, 0)

	d3dobj.swapchain->Present(1, {})
}
