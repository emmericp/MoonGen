\page timestamping Hardware Timestamping
\tableofcontents

Intel commodity NICs like the 82599, X540, and 82580 support time stamping in hardware for both transmitted and received packets.
The NICs implement this to support the IEEE 1588 PTP protocol, but this feature can be used to timestamp almost arbitrary UDP packets.
The NICs achieve sub-microsecond precision and accuracy.

A more detailed evaluation can be found in [our paper](http://arxiv.org/ftp/arxiv/papers/1410/1410.3322.pdf) [1].
