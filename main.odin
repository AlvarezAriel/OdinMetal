package inkless

import "core:fmt"
import "core:os"

import lib "lib"

main :: proc() {
	err := lib.metal_main()
	if err != nil {
		fmt.eprintln(err->localizedDescription()->odinString())
		os.exit(1)
	}
}