#include <cstdint>
#include <string>
#include <cstring>
#include <unordered_map>
#include <tuple>
#include <mutex>
#include <iostream>
#include <atomic>

// this file is C++ instead of C as doing this in C would be annoying...

static std::unordered_map<uint64_t, std::tuple<std::string, std::string>> results;
static std::mutex results_mutex;
static std::atomic<uint64_t> task_id_ctr(1);

// TODO: two char*s is obviously not the best API

extern "C" {

uint64_t generate_task_id() {
	return task_id_ctr.fetch_add(1);
}

void store_result(uint64_t task_id, char* result1, char* result2) {
	std::lock_guard<std::mutex> lock(results_mutex);
	results.emplace(task_id, std::forward_as_tuple(result1, result2));
}

// TODO: extremely ugly, but this is the simplest way to get two strings back to luajit
// (the other way would be using ugly classic lua APIs and pushing the strings on the lua stack)

bool get_result_size(uint64_t task_id, uint64_t* result1, uint64_t* result2) {
	std::lock_guard<std::mutex> lock(results_mutex);
	auto result = results.find(task_id);
	if (result != results.end()) {
		auto strings = result->second;
		*result1 = std::get<0>(strings).length() + 1;
		*result2 = std::get<1>(strings).length() + 1;
		return true;
	}
	return false;
}

bool get_result(uint64_t task_id, char* result1, char* result2, size_t buf_size1, size_t buf_size2) {
	std::lock_guard<std::mutex> lock(results_mutex);
	auto result = results.find(task_id);
	if (result != results.end()) {
		auto strings = result->second;
		auto str1 = std::get<0>(strings);
		auto str2 = std::get<1>(strings);
		if (str1.length() + 1 > buf_size1 || str2.length() + 1 > buf_size2) {
			std::cerr << "Result string buffer size too small" << std::endl;
			return false;
		}
		std::strcpy(result1, str1.c_str());
		std::strcpy(result2, str2.c_str());
		results.erase(task_id);
		return true;
	}
	return false;
}

}
