#include <assert.h>
#include <immintrin.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include "fastmemcpy.h"

void fastMemcpy(void *pvDest, void *pvSrc, size_t nBytes) {
  assert(nBytes % 32 == 0);
  assert((intptr_t(pvDest) & 31) == 0);
  assert((intptr_t(pvSrc) & 31) == 0);
  const __m256i *pSrc = reinterpret_cast<const __m256i*>(pvSrc);
  __m256i *pDest = reinterpret_cast<__m256i*>(pvDest);
  int64_t nVects = nBytes / sizeof(*pSrc);
  for (; nVects > 0; nVects--, pSrc++, pDest++) {
    const __m256i loaded = _mm256_stream_load_si256(pSrc);
    _mm256_stream_si256(pDest, loaded);
  }
  _mm_sfence();
}
