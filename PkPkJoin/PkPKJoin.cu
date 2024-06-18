#include <iostream>
#include <vector>
#include <algorithm>
#include <cuda_runtime.h>
#include <cub/cub.cuh>
#include "/csproject/yike/intern/ronak/HKUST-Server-Use-/PkPkJoin/Ronak/SortDataBlockWise.cu"
#include "/csproject/yike/intern/ronak/HKUST-Server-Use-/PkPkJoin/Ronak/FindSplits.cu"
#include "/csproject/yike/intern/ronak/HKUST-Server-Use-/PkPkJoin/Ronak/DistributionAfterSplits.cu"
// #include "/csproject/yike/intern/ronak/HKUST-Server-Use-/PkPkJoin/Ronak/JoinAfterSort.cu"


int main() {
    std::vector<int> h_data(256);
    for (int i=0;i<h_data.size();i++) {
        h_data[i]= rand() % 123;
    }
    int n = h_data.size();

    // Allocate device memory
    int* d_data;
    cudaMalloc(&d_data, n * sizeof(int));
    int* d_sorted_data;
    cudaMalloc(&d_sorted_data, n * sizeof(int));

    // Copy data to device
    cudaMemcpy(d_data, h_data.data(), n * sizeof(int), cudaMemcpyHostToDevice);

    int numBlocks = (n + (BLOCK_THREADS * ITEMS_PER_THREAD) - 1) / (BLOCK_THREADS * ITEMS_PER_THREAD);

    // Launch kernel to sort blocks
    BlockSortKernel<<<numBlocks, BLOCK_THREADS>>>(d_data, d_sorted_data, n);

    printArray<<<1,1>>>(d_sorted_data,n);

    int p = numBlocks;
    int sample_size = n / p;
    int *d_samples, *d_splitters;
    cudaMalloc(&d_samples, sample_size * sizeof(int));
    cudaMalloc(&d_splitters, (p - 1) * sizeof(int));

    FindSplit(d_sorted_data,d_samples, d_splitters, n, numBlocks, sample_size);

    printArray<<<1,1>>>(d_samples,p-1);

    int blockSize = numBlocks;
    // Device pointers
    int  *d_output, *d_partition_counts, *d_partition_starts, *d_partition_offsets;

    // Allocate device memory
    CUDA_CHECK(cudaMalloc(&d_output, n * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_partition_counts, p * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_partition_starts, p * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_partition_offsets, p * sizeof(int)));

    // Copy data to device
    CUDA_CHECK(cudaMemset(d_partition_counts, 0, p * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_partition_starts, 0, p * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_partition_offsets, 0, p * sizeof(int)));

    // Launch kernels in sequence to ensure synchronization
    countElements<<<numBlocks, blockSize>>>(d_sorted_data, d_samples, d_partition_counts, n, p);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    computeStarts<<<1, p>>>(d_partition_counts, d_partition_starts, p);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    distributeElements<<<numBlocks, blockSize>>>(d_sorted_data, d_output, d_samples, d_partition_starts, d_partition_offsets, n, p);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    // Copy result back to host
    int* h_output = new int[n];
    CUDA_CHECK(cudaMemcpy(h_output, d_output, n * sizeof(int), cudaMemcpyDeviceToHost));

    // Print result
    for (int i = 0; i < n; ++i) {
        std::cout << h_output[i] << " ";
    }
    std::cout << std::endl;

    delete[] h_output;

    // Free device memory
    cudaFree(d_data);
    cudaFree(d_sorted_data);
    cudaFree(d_samples);
    cudaFree(d_splitters);
    CUDA_CHECK(cudaFree(d_output));
    CUDA_CHECK(cudaFree(d_partition_starts));
    CUDA_CHECK(cudaFree(d_partition_offsets));
    CUDA_CHECK(cudaFree(d_partition_counts));

    return 0;
}