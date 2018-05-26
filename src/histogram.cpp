#include <cstdint>
#include <map>
#include <iostream>
#include <fstream>

// Algorithm based on: https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Online_algorithm

class Histogram {
private:
	uint64_t count = 0;
	double m2 = 0;
	double mean = 0;
	double variance = 0;
	int64_t bucket_size;
	int64_t bucket_half;
	std::map<int64_t, uint32_t> storage;

public:
	uint64_t getCount() const {
		return count;
	}

	double getMean() const {
		return mean;
	}

	double getVariance() const {
		return variance;
	}

	bool update(int64_t new_val) {
		bool ret = true;
		if (new_val < 0){
			ret = false;
		}
		++count;
		double delta = new_val - mean;
		mean = mean + delta / count;
		double delta2 = new_val - mean;
		m2 = m2 + delta * delta2;

		// compute the bucket to put this value in
		if(new_val > 0){
			new_val += bucket_half;
		}
		else if(new_val < 0){
			new_val -= bucket_half;
		}

		new_val = (new_val / bucket_size) * bucket_size;
		// if not already in map, it should be inserted and zero initialized
		++storage[new_val];

		return ret;
	}

	void finalize() {
		if (count < 2) {
			std::cerr << "Not enough members to calculate mean and variance\n";
		} else {
			variance = m2 / (count - 1);
		}
	}

	void write_to_file(const char *filename) {
		std::ofstream file;
		file.open(filename);
		if (file.fail()) {
			std::cerr << "Failed to open file < " << filename << " >\n";
			exit(EXIT_FAILURE);
		}

		auto it = storage.begin();
		while (it != storage.end()) {
			file << it->first << "," << it->second << "\n";
			++it;
		}
		file.close();
	}

	// If bucket_size is even the bucket for 0 will be slightly smaller then the rest,
	// also the bucket value will not represent exactly the median of the bucket
	Histogram(uint32_t bucket_size){
		if (bucket_size <= 0){
			std::cerr << "Invalid bucket size\n";
			exit(EXIT_FAILURE);
		}

		// to avoid casting all the time during the bucket computation
		// we directly store values as signed
		this->bucket_size = (int64_t) bucket_size;
		bucket_half = this->bucket_size/2;
	}

	virtual ~Histogram() = default;
};

Histogram *hist;

extern "C" {
void hs_initialize(uint32_t bucket_size) {
	hist = new Histogram(bucket_size);
}

void hs_destroy() {
	delete (hist);
}

bool hs_update(int64_t new_val) {
	return hist->update(new_val);
}

void hs_finalize(){
	hist->finalize();
}

void hs_write(const char* filename){
	hist->write_to_file(filename);
}

uint64_t hs_getCount() {
	return hist->getCount();
}

double hs_getMean() {
	return hist->getMean();
}

double hs_getVariance() {
	return hist->getVariance();
}

}

