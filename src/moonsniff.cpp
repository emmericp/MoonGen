#include <stdint.h>
#include <deque>
#include <iostream>
#include <fstream>
#include <mutex>
#include <thread>

#define UINT24_MAX 16777215

namespace moonsniff {

	struct ms_timestamps {
		uint64_t pre;
		uint64_t post;
	};

	class Writer {
		protected:
			std::ofstream file;
		public:
			virtual void write_to_file(uint64_t old_ts, uint64_t new_ts) = 0;
			void finish(){
				file.close();
			}
	};

	class Text_Writer: public Writer {
		public:
			void write_to_file(uint64_t old_ts, uint64_t new_ts){
				file << old_ts << " " << new_ts << "\n";
			}
			
			Text_Writer(const char* fileName){
				file.open(fileName);
			}
	};

	class Binary_Writer: public Writer {
		public:
			void write_to_file(uint64_t old_ts, uint64_t new_ts){
				file.write(reinterpret_cast<const char*>(&old_ts), sizeof(uint64_t));
				file.seekp( 8, std::ios::cur );
				file.write(reinterpret_cast<const char*>(&new_ts), sizeof(uint64_t));
				file.seekp( 8, std::ios::cur );
			}

			Binary_Writer(const char* fileName){
				file.open(fileName, std::ios::binary);
			}
	};

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
			}
	};

	class Binary_Reader: public Reader {
		private:
			std::streampos end;
		public:
			bool has_next(){
				return file.tellg() >= end ? false : true;
			}

			ms_timestamps read_from_file(){
				file.read(reinterpret_cast<char*>(&ts.pre), sizeof(uint64_t));
				file.seekg( 8, std::ios::cur );
				file.read(reinterpret_cast<char*>(&ts.post), sizeof(uint64_t));
				file.seekg( 8, std::ios::cur );

				return ts;
			}

			Binary_Reader(const char* fileName){
				file.open(fileName, std::ios::binary | std::ios::ate);
				end = file.tellg();
				file.seekg(0, std::ios::beg);
			}
	};
				
		
	struct ms_stats {
		uint64_t average_latency = 0;
		uint32_t hits = 0;
		uint32_t misses = 0;
		uint32_t inval_ts = 0;
	};

	ms_stats stats;

	std::ofstream file;
	
	uint64_t hit_list[UINT24_MAX + 1] = { 0 };

	Writer* writer;

//	void write_textfile(uint64_t old_ts, uint64_t new_ts){
//		file << old_ts << " " << new_ts << "\n";
//	}
//
//	void write_binaryfile(uint64_t old_ts, uint64_t new_ts){
//		file.write(reinterpret_cast<const char*>(&old_ts), sizeof(uint64_t));
//		file.write(reinterpret_cast<const char*>(&new_ts), sizeof(uint64_t));
//	}
//
//	void (*write_to_file)(uint64_t, uint64_t);

	static void init(const char* fileName){
//		file.open(fileName);
//		write_to_file = &write_textfile;
		writer = new Text_Writer(fileName);
	}

	static void finish(){
		writer -> finish();
	}

	static void add_entry(uint32_t identification, uint64_t timestamp){
		//std::cout << "timestamp: " << timestamp << " for identification: " << identification << "\n";
		hit_list[identification & 0x00ffffff] = timestamp;
		//std::cout << "finished adding" << "\n";
	}

	static void test_for(uint32_t identification, uint64_t timestamp){
		uint64_t old_ts = hit_list[identification & 0x00ffffff];
		hit_list[identification & 0x00ffffff] = 0;
		if( old_ts != 0 ){
			++stats.hits;
//			write_to_file(old_ts, timestamp);
			writer -> write_to_file(old_ts, timestamp);
			//std::cout << "new: " << timestamp << "\n";
			//std::cout << "old: " << hit_list[identification].timestamp << "\n";
			//std::cout << "difference: " << (timestamp - hit_list[identification].timestamp)/1e6 << " ms\n";
		} else {
			++stats.misses;
		}
	}

	static ms_stats post_process(const char* fileName){
//		std::ifstream ifile;
//		ifile.open(fileName);
		uint64_t pre, post;
		Reader* reader = new Text_Reader(fileName);
		uint64_t size = 0, sum = 0;

//		while( ifile >> pre >> post ){
		while( reader -> has_next() ){
			ms_timestamps ts = reader -> read_from_file();
			pre = ts.pre;
			post = ts.post;
			if( pre < post && post - pre < 1e9 ){
				sum += post - pre;
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

	moonsniff::ms_stats ms_post_process(const char* fileName){
		return moonsniff::post_process(fileName);
	}
	
	void ms_init(const char* fileName){ moonsniff::init(fileName); }
	void ms_finish(){ moonsniff::finish(); }

}
