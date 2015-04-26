#include <iostream>
#include <cuda.h>
#include <chrono>
#include <math.h>
// Matrices are stored in row-major order:
// M(row, col) = *(M.elements + row * M.stride + col)
typedef struct {
  int width;
  int height;
  int stride;
  double* elements;
} Matrix;

// Thread block size
#define BLOCK_SIZE 32

// Get a matrix element
__device__ double GetElement(const Matrix A, int row, int col)
{
  return A.elements[row * A.stride + col];
}

// Set a matrix element
__device__ void SetElement(Matrix A, int row, int col,
    double value)
{
  A.elements[row * A.stride + col] = value;
}

// Get the BLOCK_SIZExBLOCK_SIZE sub-matrix Asub of A that is
// located col sub-matrices to the right and row sub-matrices down
// from the upper-left corner of A
__device__ Matrix GetSubMatrix(Matrix A, int row, int col)
{
  Matrix Asub;
  Asub.width    = BLOCK_SIZE;
  Asub.height   = BLOCK_SIZE;
  Asub.stride   = A.stride;
  Asub.elements = &A.elements[A.stride * BLOCK_SIZE * row
    + BLOCK_SIZE * col];
  return Asub;
}

// Matrix multiplication kernel called by MatMul()
__global__ void MatMulKernel(Matrix A, Matrix B, Matrix C)
{
  // Block row and column
  int blockRow = blockIdx.y;
  int blockCol = blockIdx.x;

  // Each thread block computes one sub-matrix Csub of C
  Matrix Csub = GetSubMatrix(C, blockRow, blockCol);

  // Each thread computes one element of Csub
  // by accumulating results into Cvalue
  double Cvalue = 0;

  // Thread row and column within Csub
  int row = threadIdx.y;
  int col = threadIdx.x;

  // Loop over all the sub-matrices of A and B that are
  // required to compute Csub
  // Multiply each pair of sub-matrices together
  // and accumulate the results
  for (int m = 0; m < (A.width / BLOCK_SIZE); ++m) {

    // Get sub-matrix Asub of A
    Matrix Asub = GetSubMatrix(A, blockRow, m);

    // Get sub-matrix Bsub of B
    Matrix Bsub = GetSubMatrix(B, m, blockCol);

    // Shared memory used to store Asub and Bsub respectively
    __shared__ double As[BLOCK_SIZE][BLOCK_SIZE];
    __shared__ double Bs[BLOCK_SIZE][BLOCK_SIZE];

    // Load Asub and Bsub from device memory to shared memory
    // Each thread loads one element of each sub-matrix
    As[row][col] = GetElement(Asub, row, col);
    Bs[row][col] = GetElement(Bsub, row, col);

    // Synchronize to make sure the sub-matrices are loaded
    // before starting the computation
    __syncthreads();

    // Multiply Asub and Bsub together
    for (int e = 0; e < BLOCK_SIZE; ++e)
      Cvalue += As[row][e] * Bs[e][col];

    // Synchronize to make sure that the preceding
    // computation is done before loading two new
    // sub-matrices of A and B in the next iteration
    __syncthreads();
  }

  // Write Csub to device memory
  // Each thread writes one element
  SetElement(Csub, row, col, Cvalue);
}
// Matrix multiplication - Host code
// Matrix dimensions are assumed to be multiples of BLOCK_SIZE
void MatMul(const Matrix A, const Matrix B, Matrix C)
{
  cudaEvent_t start, stop, startT, stopT;
  float time,full;
  cudaEventCreate(&start);
  cudaEventCreate(&startT);
  cudaEventCreate(&stop);
  cudaEventCreate(&stopT);

  // Load A and B to device memory
  cudaEventRecord(startT,0);
  Matrix d_A;
  d_A.width = d_A.stride = A.width; d_A.height = A.height;
  size_t size = A.width * A.height * sizeof(double);
  cudaMalloc(&d_A.elements, size);
  cudaMemcpy(d_A.elements, A.elements, size,
      cudaMemcpyHostToDevice);
  Matrix d_B;
  d_B.width = d_B.stride = B.width; d_B.height = B.height;
  size = B.width * B.height * sizeof(double);

  cudaMalloc(&d_B.elements, size);
  cudaMemcpy(d_B.elements, B.elements, size,
      cudaMemcpyHostToDevice);

  // Allocate C in device memory
  Matrix d_C;
  d_C.width = d_C.stride = C.width; d_C.height = C.height;
  size = C.width * C.height * sizeof(double);
  cudaMalloc(&d_C.elements, size);

  // Invoke kernel
  dim3 dimBlock(BLOCK_SIZE, BLOCK_SIZE);
  dim3 dimGrid(B.width / dimBlock.x, A.height / dimBlock.y);

  cudaEventRecord(start,0);
  MatMulKernel<<<dimGrid, dimBlock>>>(d_A, d_B, d_C);
  cudaDeviceSynchronize();
  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);

  // Read C from device memory
  cudaMemcpy(C.elements, d_C.elements, size, cudaMemcpyDeviceToHost);
  cudaEventRecord(stopT,0);
  cudaEventSynchronize(stopT);

  cudaEventElapsedTime(&time, start, stop);
  cudaEventElapsedTime(&full, startT, stopT);
  printf ("Time for the kernel: %f ms\n", time);
  printf ("Time Full: %f ms\n", full);

  // Free device memory
  cudaFree(d_A.elements);
  cudaFree(d_B.elements);
  cudaFree(d_C.elements);
}

void runs(int side) {

  double *ma,*mb,*mc;
  int size = side * side;
  ma = new double[size];
  mb = new double[size];
  mc = new double[size];
  for (int i = 0; i < size; i++) {
    ma[i] = 2; mb[i] = 2; mc[i] = 0;
  }

  Matrix matA,matB,matC;
  matA.width = side;
  matA.height = side;
  matA.elements = ma;
  matB.width = side;
  matB.height = side;
  matB.elements = mb;
  matC.width = side;
  matC.height = side;
  matC.elements = mc;

  MatMul(matA,matB,matC);
}

// run the benchmarks
int main () {
  for (int j = 1; j <= 5; j++) {
    printf("===== Iter = %d ===== \n",j);
    for (int i = 6; i <= 13; i++) {
      int side = pow(2,i);
      printf("Size %d x %d\n", side,side);
      runs(side);
      printf("==========");
    }
  }
  return 0;
}
