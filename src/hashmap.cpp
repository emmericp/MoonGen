/*
 * This file is mostly based on pudelkoMs FlowScope project, specifically of this file:
 * https://github.com/pudelkoM/FlowScope/blob/7beb980e2cb64284666ba2d62dda5727c7bfd499/src/var_hashmap.cpp
 *
 * Most important distinction is the use of a different hash function which is more relaxed about
 * different digest sizes.
 */

#include <array>
#include <cstring>
#include <tbb/concurrent_hash_map.h>
#include <cstdint>
#include <iostream>
#include <c_bindings.h>
#include <deque>

namespace hash_map {
	/* Secret hash cookie */
	constexpr uint32_t secret = 0xF00BA;
	constexpr uint64_t sip_secret[2] = {1, 2}; // 128 bit secret

	template<typename K, typename std::enable_if<std::is_pod<K>::value>::type * = nullptr>
	struct var_sip_hash {
		var_sip_hash() = default;

		var_sip_hash(const var_sip_hash &h) = default;

		inline bool equal(const K &j, const K &k) const noexcept {
			return j == k;
		}

		// Safety check
		static_assert(sizeof(K) == K::size, "sizeof(K) != K::size");

		/* Hash function to be used by TBB */
		inline size_t hash(const K &k) const noexcept {
			return SipHashC(sip_secret, reinterpret_cast<const char *>(k.data + 0), k.size);
		}

	};

	template<size_t key_size>
	struct key_buf {
		static constexpr size_t size = key_size;
		uint8_t data[key_size];
	} __attribute__((__packed__));

	template<size_t key_size>
	inline bool operator==(const key_buf<key_size> &lhs, const key_buf<key_size> &rhs) noexcept {
		return std::memcmp(lhs.data, rhs.data, key_size) == 0;
	}

	template<size_t key_size> using K = key_buf<key_size>;
	template<size_t value_size> using V = std::array<std::uint8_t, value_size>;
}

extern "C" {
using namespace hash_map;

#define MAP_IMPL(key_size, value_size) \
    template class tbb::concurrent_hash_map<K<key_size>, V<value_size>, var_sip_hash<K<key_size>>>; \
    using hmapk##key_size##v##value_size = tbb::concurrent_hash_map<K<key_size>, V<value_size>, var_sip_hash<K<key_size>>>; \
    hmapk##key_size##v##value_size* hmapk##key_size##v##value_size##_create() { \
        return new hmapk##key_size##v##value_size; \
    } \
    void hmapk##key_size##v##value_size##_delete(hmapk##key_size##v##value_size* map) { \
        delete map; \
    } \
    void hmapk##key_size##v##value_size##_clear(hmapk##key_size##v##value_size* map) { \
        map->clear(); \
    } \
    hmapk##key_size##v##value_size::accessor* hmapk##key_size##v##value_size##_new_accessor() { \
        return new hmapk##key_size##v##value_size::accessor; \
    } \
    void hmapk##key_size##v##value_size##_accessor_free(hmapk##key_size##v##value_size::accessor* a) { \
        a->release(); \
        delete a; \
    } \
    void hmapk##key_size##v##value_size##_accessor_release(hmapk##key_size##v##value_size::accessor* a) { \
        a->release(); \
    } \
    bool hmapk##key_size##v##value_size##_access(hmapk##key_size##v##value_size* map, hmapk##key_size##v##value_size::accessor* a, const void* key) { \
        return map->insert(*a, *static_cast<const K<key_size>*>(key)); \
    } \
    std::uint8_t* hmapk##key_size##v##value_size##_accessor_get_value(hmapk##key_size##v##value_size::accessor* a) { \
        return (*a)->second.data(); \
    } \
    bool hmapk##key_size##v##value_size##_erase(hmapk##key_size##v##value_size* map, hmapk##key_size##v##value_size::accessor* a) { \
        if (a->empty()) std::terminate();\
        return map->erase(*a); \
    } \
    bool hmapk##key_size##v##value_size##_find(hmapk##key_size##v##value_size* map, hmapk##key_size##v##value_size::accessor* a, const void* key) { \
        return map->find(*a, *static_cast<const K<key_size>*>(key)); \
    } \
    uint32_t hmapk##key_size##v##value_size##_clean(hmapk##key_size##v##value_size* map, uint64_t thresh) { \
    int ctr = 0; \
        std::deque<hash_map::key_buf<key_size>> deque; \
        for (hmapk##key_size##v##value_size::iterator it = map->begin(); it != map->end();) { \
            uint64_t ts = *reinterpret_cast<uint64_t *>( &(*it).second); \
            if(ts  < thresh) { \
                deque.push_front(it->first); \
            } \
            it++; \
            for(auto it = deque.begin(); it != deque.end(); it++) { \
                map->erase(*it); \
        ++ctr; \
            } \
        } \
        deque.clear(); \
    return ctr; \
    }

#define MAP_VALUES(value_size) \
    MAP_IMPL(8, value_size) \
    MAP_IMPL(16, value_size) \
    MAP_IMPL(32, value_size) \
    MAP_IMPL(64, value_size)

// Values are the 64 bit timestamps
MAP_VALUES(8)
MAP_VALUES(16)
MAP_VALUES(32)
MAP_VALUES(64)
MAP_VALUES(128)
}
