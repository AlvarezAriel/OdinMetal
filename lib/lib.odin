package lib

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"

import MU "vendor:microui"
import SDL "vendor:sdl2"

import "core:fmt"
import "core:math"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:time"

import engine "engine"
import pipeline "pipeline"

W_WIDTH :: 1024.0
W_HEIGHT :: 1024.0
BRUSH_SIZE :: 32.0

AppState :: struct {
	command_queue:    ^MTL.CommandQueue,
	compute_uniform:  ^MTL.Buffer,
	fragment_uniform: ^MTL.Buffer,
	shader_data:      engine.Shader_Data,
}

appState := AppState{}

metal_main :: proc() -> (err: ^NS.Error) {
	SDL.SetHint(SDL.HINT_RENDER_DRIVER, "metal")
	SDL.setenv("METAL_DEVICE_WRAPPER_TYPE", "1", 0)
	SDL.Init({.VIDEO})
	defer SDL.Quit()

	window := SDL.CreateWindow(
		"Metal in Odin",
		SDL.WINDOWPOS_CENTERED_DISPLAY(1),
		SDL.WINDOWPOS_CENTERED_DISPLAY(1),
		W_WIDTH,
		W_HEIGHT,
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

	camera_buffer := device->newBuffer(size_of(engine.Camera_Data), {.StorageModeManaged})
	defer camera_buffer->release()

	voxel_buffer := device->newBuffer(size_of(engine.Voxel_Data), {.StorageModeManaged})
	defer voxel_buffer->release()

	appState.fragment_uniform =
	device->newBuffer(size_of(engine.FragmentUniform), {.StorageModeManaged})
	defer appState.fragment_uniform->release()

	appState.compute_uniform =
	device->newBuffer(size_of(engine.ComputeUniform), {.StorageModeManaged})
	defer appState.compute_uniform->release()

	compute_pso := pipeline.build_compute_pipeline(
		device,
		filename = "./assets/shaders/compute.metal",
		entrypoint = "line_rasterizer",
	) or_return
	defer compute_pso->release()

	appState.command_queue = device->newCommandQueue()
	defer appState.command_queue->release()

	render_pso := pipeline.build_render_pipeline(
		device,
		filename = "./assets/shaders/display.metal",
		vertex_entrypoint = "vertex_main",
		fragment_entrypoint = "fragment_main",
	) or_return
	defer render_pso->release()

	positions := [?][4]f32 {
		{-1, 1, 0, 1},
		{-1, -1, 0, 1},
		{1, -1, 0, 1},
		{-1, 1, 0, 1},
		{1, 1, 0, 1},
		{1, -1, 0, 1},
	}

	appState.shader_data.fragment_uniform =
	appState.fragment_uniform->contentsAsType(engine.FragmentUniform)

	appState.shader_data.camera = camera_buffer->contentsAsType(engine.Camera_Data);
	appState.shader_data.voxel_data = camera_buffer->contentsAsType(engine.Voxel_Data);

	appState.shader_data.compute_uniform =
	appState->compute_uniform->contentsAsType(engine.ComputeUniform)
	appState.shader_data.compute_uniform.flags = {0.0, 0.0, 0.0, 0.0}

	position_buffer := device->newBufferWithSlice(positions[:], {})
	defer position_buffer->release()

	texture := pipeline.build_managed_texture(device, W_WIDTH, W_HEIGHT)
	defer texture->release()

	shadow_texture := pipeline.build_managed_texture(device, W_WIDTH, W_HEIGHT)
	defer shadow_texture->release()

	SDL.ShowWindow(window)
	counter := 0
	is_first_point := true

	engine.init(&appState.shader_data, {W_WIDTH, W_HEIGHT})

	start_tick := time.tick_now()
	next_time := SDL.GetTicks() + 30

	for quit := false; !quit; {

		SDL.Delay(time_left(next_time))
		next_time += 30

		duration := time.tick_since(start_tick)
		elapsed_time := f32(time.duration_seconds(duration))

		{
			w, h: i32
			SDL.GetWindowSize(window, &w, &h)
			consumed := false
			for e: SDL.Event; SDL.PollEvent(&e); {
				engine.input(e, &appState.shader_data)

				#partial switch e.type {
				case .QUIT:
					quit = true
				case .KEYDOWN:
					#partial switch e.key.keysym.sym {
					case .ESCAPE:
						quit = true
					case .SPACE:
						appState.shader_data.requires_computation = !appState.shader_data.requires_computation	
					}
				}
			}
		}

		engine.update(elapsed_time, &appState.shader_data)

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
		if (appState.shader_data.requires_computation) {
			compute_encoder := command_buffer->computeCommandEncoder()

			compute_encoder->setComputePipelineState(compute_pso)
			compute_encoder->setTexture(texture, 0)
			compute_encoder->setTexture(shadow_texture, 1)
			compute_encoder->setBuffer(appState->compute_uniform, offset = 0, index = 0)
			compute_encoder->setBuffer(camera_buffer, offset = 0, index = 1)
			compute_encoder->setBuffer(voxel_buffer, offset = 0, index = 2)

			grid_size := MTL.Size{W_WIDTH, W_HEIGHT, 1}
			thread_group_size := MTL.Size {
				NS.Integer(compute_pso->maxTotalThreadsPerThreadgroup()),
				1,
				1,
			}

			compute_encoder->dispatchThreads(grid_size, thread_group_size)
			compute_encoder->endEncoding()
		}
		// -------------------------------------------------------------------------------------------

		render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)

		render_encoder->setRenderPipelineState(render_pso)
		render_encoder->setVertexBuffer(position_buffer, offset = 0, index = 0)
		render_encoder->setVertexBuffer(camera_buffer, offset = 0, index = 1)

		render_encoder->setFragmentBuffer(appState.fragment_uniform, offset = 0, index = 0)
		render_encoder->setFragmentTexture(texture, 1)
		render_encoder->setFragmentTexture(shadow_texture, 2)
		render_encoder->drawPrimitivesWithInstanceCount(.Triangle, 0, 6, 2)

		render_encoder->endEncoding()

		command_buffer->presentDrawable(drawable)
		command_buffer->commit()
		command_buffer->waitUntilCompleted()

	}

	return nil
}

time_left :: proc(next_time: u32) -> u32 {
	now := SDL.GetTicks()
	if (next_time <= now) {
		return 0
	} else {
		return next_time - now
	}
}