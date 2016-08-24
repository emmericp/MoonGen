#include "main.hpp"

int main(int argc, char** argv) {
	// TODO: get the install-path via cmake
	phobos::setup_base_dir({"phobos", "../phobos", "/usr/local/lib/moongen"}, true);
	return phobos::main(argc, argv);
}

