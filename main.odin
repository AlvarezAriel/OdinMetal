package objc_test

import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA  "vendor:darwin/QuartzCore"

import SDL "vendor:sdl2"

import "core:fmt"
import "core:os"
import "core:math"
import "core:mem"
import glm "core:math/linalg/glsl"


W_WIDTH :: 512.0;
W_HEIGHT :: 512.0;

Camera_Data :: struct #align(16) {
	translation:  glm.vec2,
}

FragmentUniform :: struct #align(16) {
	cursor: [4]f32,
	screen_size: [2]f32,
}

build_texture :: proc(device: ^MTL.Device) -> ^MTL.Texture {
	desc := MTL.TextureDescriptor.alloc()->init()
	defer desc->release()

	desc->setWidth(W_WIDTH)
	desc->setHeight(W_HEIGHT)
	desc->setPixelFormat(.RGBA8Unorm)
	desc->setStorageMode(.Managed)
	desc->setUsage({.ShaderRead, .ShaderWrite})

	return device->newTextureWithDescriptor(desc)
}

build_compute_pipeline :: proc(device: ^MTL.Device) -> (pso: ^MTL.ComputePipelineState, err: ^NS.Error) {
	kernel_src, ok := os.read_entire_file_from_filename("./compute.metal")

	kernel_src_str := NS.String.alloc()->initWithOdinString(string(kernel_src))
	defer kernel_src_str->release()

	compute_library := device->newLibraryWithSource(kernel_src_str, nil) or_return
	defer compute_library->release()

	line_rasterizer := compute_library->newFunctionWithName(NS.AT("line_rasterizer"))
	defer line_rasterizer->release()

	return device->newComputePipelineStateWithFunction(line_rasterizer)
}

metal_main :: proc() -> (err: ^NS.Error) {
	SDL.SetHint(SDL.HINT_RENDER_DRIVER, "metal")
	SDL.setenv("METAL_DEVICE_WRAPPER_TYPE", "1", 0)
	SDL.Init({.VIDEO})
	defer SDL.Quit()

	window := SDL.CreateWindow("Metal in Odin", 
		SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED, 
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

	compute_pso := build_compute_pipeline(device) or_return
	defer compute_pso->release()

	command_queue := device->newCommandQueue()
	defer command_queue->release()

	compile_options := NS.new(MTL.CompileOptions)
	defer compile_options->release()

	program_src, ok := os.read_entire_file_from_filename("./display.metal")

	program_src_str := NS.String.alloc()->initWithOdinString(string(program_src))
	defer program_src_str->release()

	program_library := device->newLibraryWithSource(program_src_str, compile_options) or_return
	
	vertex_program := program_library->newFunctionWithName(NS.AT("vertex_main"))
	fragment_program := program_library->newFunctionWithName(NS.AT("fragment_main"))
	assert(vertex_program != nil)
	assert(fragment_program != nil)

	pipeline_state_descriptor := NS.new(MTL.RenderPipelineDescriptor)
	pipeline_state_descriptor->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)
	pipeline_state_descriptor->setVertexFunction(vertex_program)
	pipeline_state_descriptor->setFragmentFunction(fragment_program)

	pipeline_state := device->newRenderPipelineState(pipeline_state_descriptor) or_return

	positions := [?][4]f32{
		{ -1,  1, 0, 1},
		{-1, -1, 0, 1},
		{ 1, -1, 0, 1},

		{ -1,  1, 0, 1},
		{ 1,  1, 0, 1},
		{ 1, -1, 0, 1},
	}

	// positions := [?][4]f32{
	// 	{ 0,  W_HEIGHT, 0, 1},
	// 	{0, 0, 0, 1},
	// 	{ W_WIDTH, 0, 0, 1},

	// 	{ 0,  W_HEIGHT, 0, 1},
	// 	{ W_WIDTH,  W_HEIGHT, 0, 1},
	// 	{ W_WIDTH, 0, 0, 1},
	// }

	colors := [?][4]f32{
		{1, 1, 1, 1},
		{0, 0, 0, 1},
		{0, 0, 0, 1},
		{0, 0, 0, 1},
		{0, 0, 0, 1},
	}

	interpolator_stack : [100][2]f32 = {}
	interpolator_stack_index : uint = 0

	uniform_data := uniform_buffer->contentsAsType(FragmentUniform)
	uniform_data.screen_size = { W_WIDTH, W_HEIGHT }

	position_buffer := device->newBufferWithSlice(positions[:], {})
	color_buffer    := device->newBufferWithSlice(colors[:],    {})

	texture := build_texture(device)
	defer texture->release()

	SDL.ShowWindow(window)

	for quit := false; !quit;  {
		{
			w, h: i32
			SDL.GetWindowSize(window, &w, &h)
			//cursor.screen_size.x = f32(w);
			//cursor.screen_size.y = f32(h);
			
			//camera_data := camera_buffer->contentsAsType(Camera_Data)

			for e: SDL.Event; SDL.PollEvent(&e); {
				#partial switch e.type {
				case .MOUSEMOTION:
					new_pos : [2]f32 = {f32(e.motion.x), f32(e.motion.y)}
					uniform_data.cursor.x = new_pos.x / f32(w);
					uniform_data.cursor.y = new_pos.y / f32(h);

					if(uniform_data.cursor.zw != new_pos) {
						dist := glm.distance_vec2(uniform_data.cursor.zw, new_pos.xy)
						brush_width :f32 = 4
						n_points := dist / brush_width
						
						uniform_data.cursor.zw = new_pos
					}
					
					//cursor.cursor = camera_data.perspective_transform * cursor.cursor;
					
					fmt.println("motion X ", uniform_data.cursor.x, " Y: ", uniform_data.cursor.y);
				case .QUIT: 
					quit = true
				case .KEYDOWN:
					if e.key.keysym.sym == .ESCAPE {
						quit = true
					} 
					// else if e.key.keysym.sym == .LEFT {
					// 	camera_data.translation.x -= 1
					// } else if e.key.keysym.sym == .RIGHT {
					// 	camera_data.translation.x += 1
					// } else if e.key.keysym.sym == .UP {
					// 	camera_data.translation.y -= 1
					// } else if e.key.keysym.sym == .DOWN {
					// 	camera_data.translation.y += 1
					// }
				}
			}
			
			//camera_data.perspective_transform = glm.mat4Ortho3d(0.0, f32(w), f32(h), 0.0,-5.0, 5.0)

			//camera_buffer->didModifyRange(NS.Range_Make(0, size_of(Camera_Data)))
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
		
		command_buffer := command_queue->commandBuffer()


		// -------------------------------------------------------------------------------------------

		compute_encoder := command_buffer->computeCommandEncoder()

		compute_encoder->setComputePipelineState(compute_pso)
		compute_encoder->setTexture(texture, 0)
		compute_encoder->setBuffer(uniform_buffer, offset=0, index=0)
		compute_encoder->setBuffer(camera_buffer, offset=0, index=1)
	
		grid_size := MTL.Size{W_WIDTH, W_HEIGHT, 1}
		thread_group_size := MTL.Size{NS.Integer(compute_pso->maxTotalThreadsPerThreadgroup()), 1, 1}
	
		compute_encoder->dispatchThreads(grid_size, thread_group_size)
		compute_encoder->endEncoding()
		// -------------------------------------------------------------------------------------------
		
		render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)

		render_encoder->setRenderPipelineState(pipeline_state)
		render_encoder->setVertexBuffer(position_buffer, offset=0, index=0)
		render_encoder->setVertexBuffer(color_buffer,    offset=0, index=1)
		render_encoder->setVertexBuffer(camera_buffer,   offset=0, index=2)

		render_encoder->setFragmentBuffer(uniform_buffer, offset=0, index=0);
		render_encoder->setFragmentTexture(texture, 1)
		render_encoder->drawPrimitivesWithInstanceCount(.Triangle, 0, 6, 2);

		render_encoder->endEncoding()

		command_buffer->presentDrawable(drawable)
		command_buffer->commit()
	}

	return nil
}

main :: proc() {
	err := metal_main()
	if err != nil {
		fmt.eprintln(err->localizedDescription()->odinString())
		os.exit(1)
	}
}