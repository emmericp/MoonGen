#include "main.hpp"

int main(int argc, char** argv) {
	// TODO: get the install-path via cmake
	libmoon::setup_base_dir({"libmoon", "../libmoon", "/usr/local/lib/moongen"}, true);
	libmoon::setup_extra_lua_path({"../lua/?.lua", "../lua/?/init.lua", "../lua/lib/?.lua", "../lua/lib/?/init.lua"});
	return libmoon::main(argc, argv);
}

