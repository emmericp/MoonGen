#include <cstdint>
#include <unordered_map>
#include <mutex>

// note: namespaces aka 'global maps' are not meant to be fast

template<typename K, typename V>
struct lockable_map {
	std::unordered_map<K, V> map;
	std::recursive_timed_mutex lock;

	lockable_map() : map(), lock() {
	}
};

using ns = lockable_map<std::string, std::string>;

static lockable_map<std::string, ns*> namespaces;

extern "C" {

	ns* create_or_get_namespace(const char* name) {
		std::lock_guard<std::recursive_timed_mutex> lock(namespaces.lock);
		auto result = namespaces.map.find(name);
		if (result != namespaces.map.end()) {
			return result->second;
		}
		auto new_ns = new ns();
		namespaces.map[name] = new_ns;
		return new_ns;
	}
	
	// key and value are copied and must be freed by the caller
	void namespace_store(ns* ns, const char* key, const char* value) {
		std::lock_guard<std::recursive_timed_mutex> lock(ns->lock);
		ns->map[key] = value;
	}

	void namespace_delete(ns* ns, const char* key) {
		std::lock_guard<std::recursive_timed_mutex> lock(ns->lock);
		ns->map.erase(key);
	}

	const char* namespace_retrieve(ns* ns, const char* key) {
		std::lock_guard<std::recursive_timed_mutex> lock(ns->lock);
		auto value = ns->map.find(key);
		if (value != ns->map.end()) {
			return value->second.c_str();
		} else {
			return nullptr;
		}
	}

	void namespace_iterate(ns* ns, void (*cb)(const char*, const char*)) {
		std::lock_guard<std::recursive_timed_mutex> lock(ns->lock);
		for (auto e : ns->map) {
			cb(e.first.c_str(), e.second.c_str());
		}
	}

	std::recursive_timed_mutex* namespace_get_lock(ns* ns) {
		return &ns->lock;
	}

}

