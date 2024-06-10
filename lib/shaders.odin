package lib


FragmentUniform :: struct #align(16) {
	  cursor: [4]f32,
	  toggle_layer:[4]f32,
	  screen_size: [2]f32,
}

ComputeUniform :: struct #align(16) {
	  line: [4]f32,
	  flags: [4]f32,
}

