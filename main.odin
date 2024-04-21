package objc_test

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
	
import SDL "vendor:sdl2"

import "core:fmt"
import "core:os"
import "core:mem"


W_WIDTH :: 854.0;
W_HEIGHT :: 480.0;

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

	command_queue := device->newCommandQueue()

	compile_options := NS.new(MTL.CompileOptions)
	defer compile_options->release()

	program_source :: `
	using namespace metal;
	struct Uniforms {
		float2 cursor;
		float2 screen_size;
	};
	struct ColoredVertex {
		float4 position [[position]];
		float4 color;
	};

	vertex ColoredVertex vertex_main(constant float4 *position [[buffer(0)]],
	                                 constant float4 *color    [[buffer(1)]],
	                                 uint vid                  [[vertex_id]]) {
		ColoredVertex vert;
		vert.position = position[vid];
		vert.color    = color[vid];
		
		return vert;
	}

	float circle(float2 _st, float _radius){
		float2 dist = _st;
		return 1.-smoothstep(_radius-(_radius*0.01),
							 _radius+(_radius*0.01),
							 dot(dist,dist)*4.0);
	}

	fragment float4 fragment_main(
		ColoredVertex vert [[stage_in]], 
		constant Uniforms *uni [[ buffer(0) ]]
	) {
		float2 st = vert.position.xy / uni->screen_size.xx;
		float2 cur = uni->cursor / uni->screen_size.xx;

		return float4(float3(circle(st - cur, 0.01)) ,1.0);
	}
	`

	program_library := device->newLibraryWithSource(NS.AT(program_source), compile_options) or_return
	
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

	colors := [?][4]f32{
		{1, 1, 1, 1},
		{0, 0, 0, 1},
		{0, 0, 0, 1},
		{0, 0, 0, 1},
		{0, 0, 0, 1},
	}
	cursors := [2]f32{ 0, 0 }

	FragmentUniform :: struct {
		cursor: [2]f32,
		screen_size: [2]f32,
	}
	cursor: FragmentUniform = FragmentUniform {
		screen_size = { W_WIDTH, W_HEIGHT }
	}


	position_buffer := device->newBufferWithSlice(positions[:], {})
	color_buffer    := device->newBufferWithSlice(colors[:],    {})
	//cursor_buffer   := device->newBufferWithBytes(mem.byte_slice(&cursor, size_of(cursor)), MTL.ResourceOptions { .StorageModeManaged })

	SDL.ShowWindow(window)

	for quit := false; !quit;  {
		for e: SDL.Event; SDL.PollEvent(&e); {
			#partial switch e.type {
            case .MOUSEMOTION:
				
				positions[0][0] = f32(e.motion.x);
				positions[0][1] = f32(e.motion.y);
				cursor.cursor.x = f32(e.motion.x);
				cursor.cursor.y = f32(e.motion.y);
				fmt.println("motion ", positions[0][1]);
				//somebytes := position_buffer->contents();
				//copy_slice(somebytes, transmute([]byte)positions[:]); 
				//position_buffer->didModifyRange( NS.Range { 0, len(positions) })

			case .QUIT: 
				quit = true
			case .KEYDOWN:
				if e.key.keysym.sym == .ESCAPE {
					quit = true
				}
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

		
		command_buffer := command_queue->commandBuffer()
		render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)

		render_encoder->setRenderPipelineState(pipeline_state)
		render_encoder->setVertexBuffer(position_buffer, 0, 0)
		render_encoder->setVertexBuffer(color_buffer,    0, 1)
		render_encoder->setFragmentBytes(mem.byte_slice(&cursor, size_of(cursor)), 0);
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