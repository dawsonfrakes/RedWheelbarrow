package platform

import w "core:sys/windows"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"

D3D11_Rect_Index :: u16
D3D11_Rect_Vertex :: struct {
	position: [2]f32,
}
D3D11_Rect_Instance :: struct {
	offset: [3]f32,
	scale: [2]f32,
	color: [4]f32,
	texcoords: [2][2]f32,
	rotation: f32,
	texture_index: u32,
}

d3d11_rect_indices := []D3D11_Rect_Index{0, 1, 2, 2, 3, 0}
d3d11_rect_vertices := []D3D11_Rect_Vertex{
	{{-0.5, -0.5}},
	{{-0.5, +0.5}},
	{{+0.5, +0.5}},
	{{+0.5, -0.5}},
}
d3d11_rect_instances: [dynamic]D3D11_Rect_Instance

d3dobj: struct {
	swapchain: ^dxgi.ISwapChain,
	device: ^d3d11.IDevice,
	ctx: ^d3d11.IDeviceContext,
	depth_state: ^d3d11.IDepthStencilState,
	using sized: struct {
		backbuffer_texture: ^d3d11.ITexture2D,
		backbuffer_view: ^d3d11.IRenderTargetView,
		depthbuffer_texture: ^d3d11.ITexture2D,
		depthbuffer_view: ^d3d11.IDepthStencilView,
	},
	rect_vertex_shader: ^d3d11.IVertexShader,
	rect_pixel_shader: ^d3d11.IPixelShader,
	rect_input_layout: ^d3d11.IInputLayout,
	rect_vertices_buffer: ^d3d11.IBuffer,
	rect_indices_buffer: ^d3d11.IBuffer,
	rect_instances_buffer: ^d3d11.IBuffer,
}

d3d11_init :: proc() {
	error: {
		hr: w.HRESULT = ---

		{ // create device, swapchain, device context
			desc: dxgi.SWAP_CHAIN_DESC
			desc.BufferDesc.Format = .R16G16B16A16_FLOAT
			desc.SampleDesc.Count = 1
			desc.BufferCount = 2
			desc.BufferUsage = {.RENDER_TARGET_OUTPUT}
			desc.OutputWindow = platform_hwnd
			desc.Windowed = true
			desc.SwapEffect = .FLIP_DISCARD
			desc.Flags = {.ALLOW_MODE_SWITCH}
			hr = d3d11.CreateDeviceAndSwapChain(nil, .HARDWARE, nil, {.DEBUG} when ODIN_DEBUG else {}, nil, 0,
				d3d11.SDK_VERSION, &desc, &d3dobj.swapchain, &d3dobj.device, nil, &d3dobj.ctx)
			if w.FAILED(hr) do break error
		}

		{ // disable alt-enter
			dxgi_device: ^dxgi.IDevice
			if w.SUCCEEDED(d3dobj.swapchain->GetDevice(dxgi.IDevice_UUID, cast(^rawptr) &dxgi_device)) {
				dxgi_adapter: ^dxgi.IAdapter
				if w.SUCCEEDED(dxgi_device->GetAdapter(&dxgi_adapter)) {
					dxgi_factory: ^dxgi.IFactory
					if w.SUCCEEDED(dxgi_adapter->GetParent(dxgi.IFactory_UUID, cast(^rawptr) &dxgi_factory)) {
						dxgi_factory->MakeWindowAssociation(platform_hwnd, {.NO_ALT_ENTER})
						dxgi_factory->Release()
					}
					dxgi_adapter->Release()
				}
				dxgi_device->Release()
			}
		}

		{ // create rect vertex shader and input layout
			src := `
			struct VSIn {
				float2 position : POSITION;
				float3 offset : OFFSET;
				float2 scale : SCALE;
				float4 color : COLOR;
				float4 texcoords : TEXCOORDS;
				float rotation : ROTATION;
				uint texture_index : TEXTURE_INDEX;
			};
			struct VSOut {
				float4 color : COLOR;
				float4 position : SV_Position;
			};
			VSOut main(VSIn input) {
				VSOut output;
				output.color = input.color;
				output.position = float4(input.position * input.scale + input.offset.xy, input.offset.z, 1.0);
				return output;
			}
			`
			blob: ^d3d11.IBlob
			hr = d3d_compiler.Compile(raw_data(src), len(src), nil, nil, nil, "main", "vs_5_0", 0, 0, &blob, nil)
			if w.FAILED(hr) do break error
			defer blob->Release()

			hr = d3dobj.device->CreateVertexShader(blob->GetBufferPointer(), blob->GetBufferSize(), nil, &d3dobj.rect_vertex_shader)
			if w.FAILED(hr) do break error

			descs := []d3d11.INPUT_ELEMENT_DESC{
				{"POSITION", 0, .R32G32_FLOAT, 0, u32(offset_of(D3D11_Rect_Vertex, position)), .VERTEX_DATA, 0},
				{"SCALE", 0, .R32G32_FLOAT, 1, u32(offset_of(D3D11_Rect_Instance, offset)), .INSTANCE_DATA, 1},
				{"OFFSET", 0, .R32G32B32_FLOAT, 1, u32(offset_of(D3D11_Rect_Instance, offset)), .INSTANCE_DATA, 1},
				{"COLOR", 0, .R32G32B32A32_FLOAT, 1, u32(offset_of(D3D11_Rect_Instance, color)), .INSTANCE_DATA, 1},
				{"TEXCOORDS", 0, .R32G32B32A32_FLOAT, 1, u32(offset_of(D3D11_Rect_Instance, texcoords)), .INSTANCE_DATA, 1},
				{"ROTATION", 0, .R32_FLOAT, 1, u32(offset_of(D3D11_Rect_Instance, rotation)), .INSTANCE_DATA, 1},
				{"TEXTURE_INDEX", 0, .R32_UINT, 1, u32(offset_of(D3D11_Rect_Instance, texture_index)), .INSTANCE_DATA, 1},
			}
			hr = d3dobj.device->CreateInputLayout(raw_data(descs), u32(len(descs)), blob->GetBufferPointer(), blob->GetBufferSize(), &d3dobj.rect_input_layout)
			if w.FAILED(hr) do break error
		}

		{ // create rect pixel shader
			src := `
			struct PSIn {
				float4 color : COLOR;
			};
			float4 main(PSIn input) : SV_Target {
				return input.color;
			}
			`
			blob: ^d3d11.IBlob
			hr = d3d_compiler.Compile(raw_data(src), len(src), nil, nil, nil, "main", "ps_5_0", 0, 0, &blob, nil)
			if w.FAILED(hr) do break error
			defer blob->Release()

			hr = d3dobj.device->CreatePixelShader(blob->GetBufferPointer(), blob->GetBufferSize(), nil, &d3dobj.rect_pixel_shader)
			if w.FAILED(hr) do break error
		}

		{ // create rect vertex buffer
			desc: d3d11.BUFFER_DESC
			desc.ByteWidth = u32(len(d3d11_rect_vertices) * size_of(D3D11_Rect_Vertex))
			desc.Usage = .DEFAULT
			desc.BindFlags = {.VERTEX_BUFFER}
			desc.StructureByteStride = size_of(D3D11_Rect_Vertex)
			sr: d3d11.SUBRESOURCE_DATA
			sr.pSysMem = raw_data(d3d11_rect_vertices)
			hr = d3dobj.device->CreateBuffer(&desc, &sr, &d3dobj.rect_vertices_buffer)
			if w.FAILED(hr) do break error
		}

		{ // create rect instance buffer
			desc: d3d11.BUFFER_DESC
			desc.ByteWidth = u32(1024 * size_of(D3D11_Rect_Instance))
			desc.Usage = .DYNAMIC
			desc.BindFlags = {.VERTEX_BUFFER}
			desc.CPUAccessFlags = {.WRITE}
			desc.StructureByteStride = size_of(D3D11_Rect_Instance)
			hr = d3dobj.device->CreateBuffer(&desc, nil, &d3dobj.rect_instances_buffer)
			if w.FAILED(hr) do break error
		}

		{ // create rect index buffer
			desc: d3d11.BUFFER_DESC
			desc.ByteWidth = u32(len(d3d11_rect_indices) * size_of(D3D11_Rect_Index))
			desc.Usage = .DEFAULT
			desc.BindFlags = {.INDEX_BUFFER}
			desc.StructureByteStride = size_of(D3D11_Rect_Index)
			sr: d3d11.SUBRESOURCE_DATA
			sr.pSysMem = raw_data(d3d11_rect_indices)
			hr = d3dobj.device->CreateBuffer(&desc, &sr, &d3dobj.rect_indices_buffer)
			if w.FAILED(hr) do break error
		}

		return
	}
	renderer_switch_api(.NONE)
}

d3d11_deinit_sized :: proc() {
	if d3dobj.backbuffer_texture != nil do d3dobj.backbuffer_texture->Release()
	if d3dobj.backbuffer_view != nil do d3dobj.backbuffer_view->Release()
	if d3dobj.depthbuffer_texture != nil do d3dobj.depthbuffer_texture->Release()
	if d3dobj.depthbuffer_view != nil do d3dobj.depthbuffer_view->Release()
	d3dobj.sized = {}
}

d3d11_deinit :: proc() {
	d3d11_deinit_sized()
	if d3dobj.swapchain != nil do d3dobj.swapchain->Release()
	if d3dobj.device != nil do d3dobj.device->Release()
	if d3dobj.ctx != nil do d3dobj.ctx->Release()
	if d3dobj.depth_state != nil do d3dobj.depth_state->Release()
	if d3dobj.rect_vertex_shader != nil do d3dobj.rect_vertex_shader->Release()
	if d3dobj.rect_pixel_shader != nil do d3dobj.rect_pixel_shader->Release()
	if d3dobj.rect_input_layout != nil do d3dobj.rect_input_layout->Release()
	if d3dobj.rect_vertices_buffer != nil do d3dobj.rect_vertices_buffer->Release()
	if d3dobj.rect_indices_buffer != nil do d3dobj.rect_indices_buffer->Release()
	if d3dobj.rect_instances_buffer != nil do d3dobj.rect_instances_buffer->Release()
	d3dobj = {}
}

d3d11_resize :: proc() {
	error: {
		hr: w.HRESULT = ---

		d3d11_deinit_sized()

		{ // create backbuffer texture
			desc: d3d11.TEXTURE2D_DESC
			desc.Width = u32(platform_size.x)
			desc.Height = u32(platform_size.y)
			desc.MipLevels = 1
			desc.ArraySize = 1
			desc.Format = .R16G16B16A16_FLOAT
			desc.SampleDesc.Count = 4
			desc.Usage = .DEFAULT
			desc.BindFlags = {.RENDER_TARGET}
			hr = d3dobj.device->CreateTexture2D(&desc, nil, &d3dobj.backbuffer_texture)
			if w.FAILED(hr) do break error
		}

		{ // create backbuffer view
			hr = d3dobj.device->CreateRenderTargetView(d3dobj.backbuffer_texture, nil, &d3dobj.backbuffer_view)
			if w.FAILED(hr) do break error
		}

		{ // create depth state
			desc: d3d11.DEPTH_STENCIL_DESC
			desc.DepthEnable = true
			desc.DepthWriteMask = .ALL
			desc.DepthFunc = .GREATER_EQUAL
			hr = d3dobj.device->CreateDepthStencilState(&desc, &d3dobj.depth_state)
			if w.FAILED(hr) do break error
		}

		{ // create depthbuffer texture
			desc: d3d11.TEXTURE2D_DESC
			desc.Width = u32(platform_size.x)
			desc.Height = u32(platform_size.y)
			desc.MipLevels = 1
			desc.ArraySize = 1
			desc.Format = .D32_FLOAT
			desc.SampleDesc.Count = 4
			desc.Usage = .DEFAULT
			desc.BindFlags = {.DEPTH_STENCIL}
			hr = d3dobj.device->CreateTexture2D(&desc, nil, &d3dobj.depthbuffer_texture)
			if w.FAILED(hr) do break error
		}

		{ // create depthbuffer view
			hr = d3dobj.device->CreateDepthStencilView(d3dobj.depthbuffer_texture, nil, &d3dobj.depthbuffer_view)
			if w.FAILED(hr) do break error
		}

		return
	}
	renderer_switch_api(.NONE)
}

d3d11_present :: proc() {
	error: {
		hr: w.HRESULT = ---

		swapchain_backbuffer_texture: ^d3d11.ITexture2D
		hr = d3dobj.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, cast(^rawptr) &swapchain_backbuffer_texture)
		if w.FAILED(hr) do break error
		defer swapchain_backbuffer_texture->Release()

		d3dobj.ctx->OMSetRenderTargets(1, &d3dobj.backbuffer_view, d3dobj.depthbuffer_view)
		d3dobj.ctx->OMSetDepthStencilState(d3dobj.depth_state, 0)

		viewport: d3d11.VIEWPORT
		viewport.Width = f32(platform_size.x)
		viewport.Height = f32(platform_size.y)
		viewport.MaxDepth = 1.0
		d3dobj.ctx->RSSetViewports(1, &viewport)

		d3dobj.ctx->IASetPrimitiveTopology(.TRIANGLELIST)
		d3dobj.ctx->IASetInputLayout(d3dobj.rect_input_layout)
		vertex_buffers := []^d3d11.IBuffer{d3dobj.rect_vertices_buffer, d3dobj.rect_instances_buffer}
		vertex_strides := []u32{size_of(D3D11_Rect_Vertex), size_of(D3D11_Rect_Instance)}
		vertex_offsets := []u32{0, 0}
		d3dobj.ctx->IASetVertexBuffers(0, u32(len(vertex_buffers)), raw_data(vertex_buffers), raw_data(vertex_strides), raw_data(vertex_offsets))
		d3dobj.ctx->IASetIndexBuffer(d3dobj.rect_indices_buffer, .R16_UINT, 0)

		d3dobj.ctx->VSSetShader(d3dobj.rect_vertex_shader, nil, 0)
		d3dobj.ctx->PSSetShader(d3dobj.rect_pixel_shader, nil, 0)

		mapped: d3d11.MAPPED_SUBRESOURCE = ---
		hr = d3dobj.ctx->Map(d3dobj.rect_instances_buffer, 0, .WRITE_DISCARD, {}, &mapped)
		if w.FAILED(hr) do break error
		count := min(len(d3d11_rect_instances), 1024)
		copy((cast([^]D3D11_Rect_Instance) mapped.pData)[:count], d3d11_rect_instances[:count])
		d3dobj.ctx->Unmap(d3dobj.rect_instances_buffer, 0)
		defer clear(&d3d11_rect_instances)

		d3dobj.ctx->DrawIndexedInstanced(u32(len(d3d11_rect_indices)), u32(len(d3d11_rect_instances)), 0, 0, 0)

		d3dobj.ctx->ResolveSubresource(swapchain_backbuffer_texture, 0, d3dobj.backbuffer_texture, 0, .R16G16B16A16_FLOAT)

		hr = d3dobj.swapchain->Present(1, {})
		if w.FAILED(hr) do break error

		return
	}
	renderer_switch_api(.NONE)
}

d3d11_clear_color :: proc(color: [4]f32, index: u32) {
	color := color
	d3dobj.ctx->ClearRenderTargetView(d3dobj.backbuffer_view, &color)
}

d3d11_clear_depth :: proc(depth: f32) {
	d3dobj.ctx->ClearDepthStencilView(d3dobj.depthbuffer_view, {.DEPTH}, depth, 0)
}

d3d11_rect :: proc(position, size: [2]f32, color: [4]f32, texcoords: [2][2]f32, rotation: f32, texture_index: u32, z_index: i32) {
	w, h := f32(platform_size.x - 1), f32(platform_size.y - 1)
	append(&d3d11_rect_instances, D3D11_Rect_Instance{
		offset = {position.x / w * 2.0 - 1.0, position.y / h * 2.0 - 1.0, f32(z_index) / 1000.0 + 0.5},
		scale = {size.x / w * 2.0, size.y / h * 2.0},
		color = color,
		texcoords = texcoords,
		rotation = rotation,
		texture_index = texture_index,
	})
}

renderer_d3d11 := Renderer{
	init = d3d11_init,
	deinit = d3d11_deinit,
	resize = d3d11_resize,
	present = d3d11_present,
	procs = {
		clear_color = d3d11_clear_color,
		clear_depth = d3d11_clear_depth,
		rect = d3d11_rect,
	},
}
