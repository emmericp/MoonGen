#include <cstdint>
#include <string>
#include <deque>
#include <iostream>
#include <fstream>
#include <mutex>
#include <cstring>
#include <thread>
#include <unordered_map>
#include <rte_mbuf.h>
#include <rte_mempool.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_byteorder.h>

#define UINT24_MAX 16777215
#define INDEX_MASK (uint32_t) 0x00FFFFFF

/*
 * This namespace holds functions which are used by MoonSniff's Live Mode
 *
 * Other modes are implemented in examples/moonsniff/
 */
namespace moonsniff {

	struct ms_timestamps {
		uint64_t pre; // timestamp of packet before entering DUT
		uint64_t post; // timestamp of packet after leaving DUT
	};

	/**
	 * Base class for all file-writers
	 *
	 * The writers are responsible to write pre/post timestamp pairs
	 */
	class Writer {
		protected:
			std::ofstream file;
		public:
			virtual void write_to_file(uint64_t old_ts, uint64_t new_ts) = 0;
			void finish(){
				file.close();
			}
			void check_stream(const char* fileName){
				if( file.fail() ){
					std::cerr << "Failed to open file < " << fileName << " >\nMake sure this file exists.\n\n";
					exit(EXIT_FAILURE);
				}
			}

	};

	class Text_Writer: public Writer {
		public:
			void write_to_file(uint64_t old_ts, uint64_t new_ts){
				file << old_ts << " " << new_ts << "\n";
			}

			Text_Writer(const char* fileName){
				file.open(fileName);
				check_stream(fileName);
			}
	};

	class Binary_Writer: public Writer {
		public:
			void write_to_file(uint64_t old_ts, uint64_t new_ts){
				file.write(reinterpret_cast<const char*>(&old_ts), sizeof(uint64_t));
				file.write(reinterpret_cast<const char*>(&new_ts), sizeof(uint64_t));
			}

			Binary_Writer(const char* fileName){
				file.open(fileName, std::ios::binary);
				check_stream(fileName);
			}
	};

	/**
	 * Base class for all file-readers
	 *
	 * Reads pre/post timestamp pairs from a file
	 */
	class Reader {
		protected:
			std::ifstream file;
			ms_timestamps ts;
		public:
			virtual ms_timestamps read_from_file() = 0;
			virtual bool has_next() = 0;
			void finish(){
				file.close();
			}
			void check_stream(const char* fileName){
				if( file.fail() ){
					std::cerr << "Failed to open file < " << fileName << " >\nMake sure this file exists.\n\n";
					exit(EXIT_FAILURE);
				}
			}
	};

	class Text_Reader: public Reader {
		public:
			bool has_next(){
				return file >> ts.pre >> ts.post ? true : false;
			}

			ms_timestamps read_from_file(){
				return ts;
			}

			Text_Reader(const char* fileName){
				file.open(fileName);
				check_stream(fileName);
			}
	};

	class Binary_Reader: public Reader {
		private:
			std::streampos end;
		public:
			bool has_next(){
				return end > file.tellg();
			}

			ms_timestamps read_from_file(){
				file.read(reinterpret_cast<char*>(&ts.pre), sizeof(uint64_t));
				file.read(reinterpret_cast<char*>(&ts.post), sizeof(uint64_t));

				return ts;
			}

			Binary_Reader(const char* fileName){
				file.open(fileName, std::ios::binary | std::ios::ate);
				check_stream(fileName);
				end = file.tellg();
				file.seekg(0, std::ios::beg);

				if ( (end - file.tellg()) % 16 != 0 ){
					std::cerr << "Invalid binary file detected. Are you sure it was created in ms_binary mode?" << "\n";
					exit(EXIT_FAILURE);
				}
			}
	};


	struct ms_stats {
		uint64_t average_latency = 0;
		uint32_t hits = 0;
		uint32_t misses = 0;
		uint32_t inval_ts = 0;
	} stats;

	/**
	 * Enum to change the reading/writing mode
	 */
	enum ms_mode { ms_text, ms_binary };

	std::ofstream file;

	// initialize array and as many mutexes to ensure memory order
	uint64_t hit_list[UINT24_MAX + 1] = { 0 };
	std::mutex mtx[UINT24_MAX + 1];

	Writer* writer;

	/**
	 * Initializes the writers for the output file. Should be called before calling other functions.
	 *
	 * @param fileName Name of the output file
	 * @param mode The type of the Writer which shall be created
	 */
	static void init(const char* fileName, ms_mode mode){
		if( mode == ms_binary ){
			writer = new Binary_Writer(fileName);
		} else {
			writer = new Text_Writer(fileName);
		}
	}

	/**
	 * Call when finished writing operations. Closes underlying writers.
	 */
	static void finish(){
		writer -> finish();
	}

	/**
	 * Add a pre DUT timestamp to the array.
	 *
	 * @param identification The identifier associated with this timestamp
	 * @param timestamp The timestamp
	 */
	static void add_entry(uint32_t identification, uint64_t timestamp){
		uint32_t index = identification & INDEX_MASK;
		while(!mtx[index].try_lock());
		hit_list[index] = timestamp;
		mtx[index].unlock();
	}

	/**
	 * Check if there exists an entry in the array for the given identifier.
	 * Retrieves the pre DUT timestamp (if existing) and writes timestamp pair into a file.
	 *
	 * @param identification Identifier for which an entry is searched
	 * @param timestamp The post timestamp
	 */
	static void test_for(uint32_t identification, uint64_t timestamp){
		uint32_t index = identification & INDEX_MASK;
		while(!mtx[index].try_lock());
		uint64_t old_ts = hit_list[index];
		hit_list[index] = 0;
		mtx[index].unlock();
		if( old_ts != 0 ){
			++stats.hits;
			writer -> write_to_file(old_ts, timestamp);
		} else {
			++stats.misses;
		}
	}

	/**
	 * Reads the output file which contains timestamp pairs.
	 * Computes the average latency from all pairs.
	 *
	 * @param fileName The name of the file generated during the sniffing phase
	 * @param mode The mode in which the file was written (ms_text, ms_binary)
	 */
	static ms_stats post_process(const char* fileName, ms_mode mode){
		Reader* reader;
		if( mode == ms_binary ){
			reader = new Binary_Reader(fileName);
		} else {
			reader = new Text_Reader(fileName);
		}
		uint64_t size = 0, sum = 0;

		while( reader -> has_next() ){
			ms_timestamps ts = reader -> read_from_file();
			if( ts.pre < ts.post && ts.post - ts.pre < 1e9 ){
				sum += ts.post - ts.pre;
				++size;
			} else {
				++stats.inval_ts;
			}
		}
		std::cout << size << ", " << sum << "\n";
		stats.average_latency = size != 0 ? sum/size : 0;
		reader -> finish();
		return stats;
	}
}

extern "C" {
	void ms_add_entry(uint32_t identification, uint64_t timestamp){
		moonsniff::add_entry(identification, timestamp);
	}

	void ms_test_for(uint32_t identification, uint64_t timestamp){
		moonsniff::test_for(identification, timestamp);
	}

	moonsniff::ms_stats ms_post_process(const char* fileName, moonsniff::ms_mode mode){
		return moonsniff::post_process(fileName, mode);
	}

	void ms_init(const char* fileName, moonsniff::ms_mode mode){ moonsniff::init(fileName, mode); }
	void ms_finish(){ moonsniff::finish(); }
}
