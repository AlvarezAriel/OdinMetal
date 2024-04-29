package lib

import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA  "vendor:darwin/QuartzCore"

import SDL "vendor:sdl2"
import MU "vendor:microui"

import "core:fmt"
import "core:os"
import "core:math"
import "core:mem"
import glm "core:math/linalg/glsl"

import pipeline "pipeline"

W_WIDTH :: 1024.0;
W_HEIGHT :: 1024.0;
BRUSH_SIZE :: 32.0;

Camera_Data :: struct #align(16) {
	translation:  glm.vec2,
}

FragmentUniform :: struct #align(16) {
	cursor: [4]f32,
	toggle_layer:[4]f32,
	screen_size: [2]f32,
}

ComputeUniform :: struct #align(16) {
	line: [4]f32,
	flags: [4]f32,
}

AppState :: struct {
    command_queue: ^MTL.CommandQueue,
    compute_uniform: ^MTL.Buffer, 
}

appState := AppState {
   
}

metal_main :: proc() -> (err: ^NS.Error) {
	SDL.SetHint(SDL.HINT_RENDER_DRIVER, "metal")
	SDL.setenv("METAL_DEVICE_WRAPPER_TYPE", "1", 0)
	SDL.Init({.VIDEO})
	defer SDL.Quit()

	window := SDL.CreateWindow("Metal in Odin",
		SDL.WINDOWPOS_CENTERED_DISPLAY(1), SDL.WINDOWPOS_CENTERED_DISPLAY(1),
		W_WIDTH, W_HEIGHT,
		{.ALLOW_HIGHDPI, .HIDDEN, .RESIZABLE},
	)
	defer SDL.DestroyWindow(window)

	window_system_info: SDL.SysWMinfo
	SDL.GetVersion(&window_system_info.version)
	SDL.GetWindowWMInfo(window, &window_system_info)
	assert(window_system_info.subsystem == .COCOA)

	native_window := (^NS.Window)(window_system_info.info.cocoa.window)

	device := MTL.CreateSystemDefaultDevice()

	fmt.println(device->name()->odinString())

	swapchain := CA.MetalLayer.layer()
	swapchain->setDevice(device)
	swapchain->setPixelFormat(.BGRA8Unorm_sRGB)
	swapchain->setFramebufferOnly(true)
	swapchain->setFrame(native_window->frame())

	native_window->contentView()->setLayer(swapchain)
	native_window->setOpaque(true)
	native_window->setBackgroundColor(nil)

  camera_buffer := device->newBuffer(size_of(Camera_Data), {.StorageModeManaged})
	defer camera_buffer->release()

  uniform_buffer := device->newBuffer(size_of(FragmentUniform), {.StorageModeManaged})
	defer uniform_buffer->release()

	appState.compute_uniform = device->newBuffer(size_of(ComputeUniform), {.StorageModeManaged})
  defer appState.compute_uniform->release()

	compute_pso := pipeline.build_compute_pipeline(
		device,
		filename="./assets/shaders/compute.metal",
		entrypoint="line_rasterizer"
	) or_return
	defer compute_pso->release()

	appState.command_queue = device->newCommandQueue()
	defer appState.command_queue->release()

	render_pso := pipeline.build_render_pipeline(
		device,
		filename="./assets/shaders/display.metal",
		vertex_entrypoint="vertex_main",
		fragment_entrypoint="fragment_main",
	) or_return
	defer render_pso->release()

	positions := [?][4]f32{
		{ -1,  1, 0, 1},
		{-1, -1, 0, 1},
		{ 1, -1, 0, 1},

		{ -1,  1, 0, 1},
		{ 1,  1, 0, 1},
		{ 1, -1, 0, 1},
	}

	uniform_data := uniform_buffer->contentsAsType(FragmentUniform)
	uniform_data.screen_size = { W_WIDTH, W_HEIGHT }
	uniform_data.toggle_layer = { 1.0, 1.0, 1.0, 1.0 }

	compute_uniform_data := appState->compute_uniform->contentsAsType(ComputeUniform)
	compute_uniform_data.flags = { 1.0, 0.0, 0.0, 0.0 }

	position_buffer := device->newBufferWithSlice(positions[:], {})
	defer position_buffer->release()

	texture := pipeline.build_managed_texture(device, W_WIDTH, W_HEIGHT)
	defer texture->release()

	shadow_texture := pipeline.build_managed_texture(device, W_WIDTH, W_HEIGHT)
	defer shadow_texture->release()

	SDL.ShowWindow(window)
	counter := 0
	requires_computation := true
	is_first_point := true
	for quit := false; !quit;  {


		{
			w, h: i32
			SDL.GetWindowSize(window, &w, &h)
			consumed := false
			for e: SDL.Event; SDL.PollEvent(&e); {
				#partial switch e.type {
				case .FINGERMOTION:
					fmt.println("FINGER!!!")	
				case .MOUSEMOTION:
					if(consumed || e.motion.state == 0) {
						is_first_point = true
						continue
					}
					consumed = true

					new_pos : [2]f32 = {f32(e.motion.x), f32(e.motion.y)}

					compute_uniform_data.line = { 
						uniform_data.cursor.z,
						uniform_data.cursor.w,
						new_pos.x,
						new_pos.y
					}

					uniform_data.cursor.x = new_pos.x / f32(w);
					uniform_data.cursor.y = new_pos.y / f32(h);
					uniform_data.cursor.zw = new_pos

					if(!is_first_point) {
						requires_computation = true
					}
					is_first_point = false
					
				case .QUIT: 
					quit = true
				case .KEYDOWN:
					#partial switch e.key.keysym.sym {
						case .ESCAPE: 
							quit = true
						case .R:
							uniform_data.toggle_layer.r = 1.0 - uniform_data.toggle_layer.r
						case .G:
							uniform_data.toggle_layer.g = 1.0 - uniform_data.toggle_layer.g
						case .B:
							uniform_data.toggle_layer.b = 1.0 - uniform_data.toggle_layer.b
						case .D:
							uniform_data.toggle_layer.a = 1.0 - uniform_data.toggle_layer.a
						case .SPACE:
							requires_computation := true
							compute_uniform_data.flags.x = 1.0;	
					}
				}
				fmt.printfln("TYPE: ", e.type)
			}
		}

		NS.scoped_autoreleasepool()

		drawable := swapchain->nextDrawable()
		assert(drawable != nil)

		pass := MTL.RenderPassDescriptor.renderPassDescriptor()
		color_attachment := pass->colorAttachments()->object(0)
		assert(color_attachment != nil)
		color_attachment->setClearColor(MTL.ClearColor{0.25, 0.5, 1.0, 1.0})
		color_attachment->setLoadAction(.Clear)
		color_attachment->setStoreAction(.Store)
		color_attachment->setTexture(drawable->texture())
		
		command_buffer := appState.command_queue->commandBuffer()


		// -------------------------------------------------------------------------------------------
		if(requires_computation) {
			requires_computation = false
			compute_encoder := command_buffer->computeCommandEncoder()

			compute_encoder->setComputePipelineState(compute_pso)
			compute_encoder->setTexture(texture, 0)
			compute_encoder->setTexture(shadow_texture, 1)
			compute_encoder->setBuffer(appState->compute_uniform, offset=0, index=0)
			compute_encoder->setBuffer(camera_buffer, offset=0, index=1)
		
			grid_size := MTL.Size{W_WIDTH, W_HEIGHT, 1}
			thread_group_size := MTL.Size{NS.Integer(compute_pso->maxTotalThreadsPerThreadgroup()), 1, 1}
		
			compute_encoder->dispatchThreads(grid_size, thread_group_size)
			compute_encoder->endEncoding()
		}
		// -------------------------------------------------------------------------------------------
		
		render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)

		render_encoder->setRenderPipelineState(render_pso)
		render_encoder->setVertexBuffer(position_buffer, offset=0, index=0)
		render_encoder->setVertexBuffer(camera_buffer,   offset=0, index=1)

		render_encoder->setFragmentBuffer(uniform_buffer, offset=0, index=0);
		render_encoder->setFragmentTexture(texture, 1)
		render_encoder->setFragmentTexture(shadow_texture, 2)
		render_encoder->drawPrimitivesWithInstanceCount(.Triangle, 0, 6, 2);

		render_encoder->endEncoding()

		command_buffer->presentDrawable(drawable)
		command_buffer->commit()
		command_buffer->waitUntilCompleted()

		compute_uniform_data.flags.x = 0.0;
		requires_computation = false;
	}

	return nil
}
