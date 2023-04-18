## Hnswlib.rb

Hnswlib.rb provides Ruby bindings for the Hnswlib that implements approximate nearest-neghbor search based on hierarchical navigable small world graphs.

## hnswlib

Header-only C++ HNSW implementation with python bindings, insertions and updates.

### Highlights

- Lightweight, header-only, no dependencies other than C++ 11
- Interfaces for C++, Python, external support for Java and R (https://github.com/jlmelville/rcpphnsw).
- Has full support for incremental index construction and updating the elements. Has support for element deletions (by marking them in index). Index is picklable.
- Can work with custom user defined distances (C++).
Significantly less memory footprint and faster build time compared to current nmslib's implementation.

### properties

space - name of the space (can be one of "l2", "ip", or "cosine").
dim - dimensionality of the space.
max_elements - current capacity of the index. Equivalent to p.get_max_elements().

### Other implementations

Non-metric space library (nmslib) - main library(python, C++), supports exotic distances: https://github.com/nmslib/nmslib
Faiss library by facebook, uses own HNSW implementation for coarse quantization (python, C++): https://github.com/facebookresearch/faiss
Code for the paper "Revisiting the Inverted Indices for Billion-Scale Approximate Nearest Neighbors" (current state-of-the-art in compressed indexes, C++): https://github.com/dbaranchuk/ivf-hnsw
Amazon PECOS https://github.com/amzn/pecos
TOROS N2 (python, C++): https://github.com/kakao/n2
Online HNSW (C++): https://github.com/andrusha97/online-hnsw)
Go implementation: https://github.com/Bithack/go-hnsw
Python implementation (as a part of the clustering code by by Matteo Dell'Amico): https://github.com/matteodellamico/flexible-clustering
Julia implmentation https://github.com/JuliaNeighbors/HNSW.jl
Java implementation: https://github.com/jelmerk/hnswlib
Java bindings using Java Native Access: https://github.com/stepstone-tech/hnswlib-jna
.Net implementation: https://github.com/curiosity-ai/hnsw-sharp
CUDA implementation: https://github.com/js1010/cuhnsw
Rust implementation https://github.com/rust-cv/hnsw
Rust implementation for memory and thread safety purposes and There is A Trait to enable the user to implement its own distances. It takes as data slices of types T satisfying T:Serialize+Clone+Send+Sync.: https://github.com/jean-pierreBoth/hnswlib-rs

