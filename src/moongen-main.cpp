#include "main.hpp"

int main(int argc, char** argv) {
	// TODO: get the install-path via cmake
	phobos::setup_base_dir({"phobos", "../phobos", "/usr/local/lib/moongen"}, true);
	phobos::setup_extra_lua_path({"../lua/?.lua", "../lua/?/init.lua", "../lua/lib/?.lua", "../lua/lib/?/init.lua"});
	return phobos::main(argc, argv);
}

