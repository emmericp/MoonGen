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

	void update(int64_t new_val) {
		++count;
		double delta = new_val - mean;
		mean = mean + delta / count;
		double delta2 = new_val - mean;
		m2 = m2 + delta * delta2;

		// if not already in map, it should be inserted and zero initialized
		++storage[new_val];
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

	Histogram() = default;

	virtual ~Histogram() = default;
};

Histogram *hist;

extern "C" {
void hs_initialize() {
	hist = new Histogram();
}

void hs_destroy() {
	delete (hist);
}

void hs_update(int64_t new_val) {
	hist->update(new_val);
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

