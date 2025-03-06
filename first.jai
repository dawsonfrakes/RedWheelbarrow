#run {
	#import "Compiler";
	#import "Basic";

	set_build_options_dc(.{do_output = false});

	options := get_build_options();
	options.output_type = .EXECUTABLE;
	options.output_executable_name = "RedWheelbarrow";

	w := compiler_create_workspace("Red Wheelbarrow");
	set_build_options(options, w);
	add_build_string("DEBUG :: true;", w);
	if options.os_target == {
		case .WINDOWS;
			add_build_file("platform/main_windows.jai", w);
		case;
			print("Target % is not supported\n", options.os_target);
	}
}
