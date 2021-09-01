/*
 * (C) 2003-2018 - ntop 
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#define _GNU_SOURCE
#include <cuda.h>
#include <signal.h>
#include <sched.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <errno.h>
#include <sys/time.h>
#include <time.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdint.h>

#include "pfring.h"
#include "pfring_zc.h"

#include "zutils.c"

#define ALARM_SLEEP 1
#define MAX_CARD_SLOTS      32768

//c++ include
#include <iostream>
#include <cstdlib>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <bitset>
#include <cmath>
#include <iomanip>
#include <condition_variable>
#include <mutex>
#include <assert.h>
#include <immintrin.h>

using namespace std;

const uint64_t m1  = 0x5555555555555555; //binary: 0101...
const uint64_t m2  = 0x3333333333333333; //binary: 00110011..
const uint64_t m4  = 0x0f0f0f0f0f0f0f0f; //binary:  4 zeros,  4 ones ...
const uint64_t m8  = 0x00ff00ff00ff00ff; //binary:  8 zeros,  8 ones ...
const uint64_t m16 = 0x0000ffff0000ffff; //binary: 16 zeros, 16 ones ...
const uint64_t m32 = 0x00000000ffffffff; //binary: 32 zeros, 32 ones
const uint64_t hff = 0xffffffffffffffff; //binary: all ones
const uint64_t h01 = 0x0101010101010101; //the sum of 256 to the power of 0,1,2,3...

struct timeval startCPU7;
struct timeval endCPU7;
unsigned long diffCPU7=0;

struct timeval startGPU;
struct timeval endGPU;
unsigned long diffGPU=0;

struct timeval startCPU;
struct timeval endCPU;
unsigned long diffCPU=0;

struct timeval startCUDA;
struct timeval endCUDA;
unsigned long diffCUDA=0;

struct timeval startREAL;
struct timeval endREAL;
unsigned long diffREAL = 0;

struct timeval startREALGPU;
struct timeval endREALGPU;
unsigned long diffREALGPU = 0;
unsigned long long int REALtotaltime = 0;
unsigned long long int printtime = 0;
unsigned long long int REALCPU = 0;
unsigned long long int REALGPU = 0;
unsigned long long int REALcountpak[7] = {0};
float totalspeed = 0.0;
int CPUbyte[7] = {0};
int countpak[7] = {0};
int count_intermittent[7] = {0};
int totalpacket[7]={0};
int counterT2[7]={0};
int justanumber[7] = {0};
int modechoose = -1;
int totallock[7] = {0};
int totalcantlock[7] = {0};
//int numofpakcal = 100;

///////////////////////////////////////////////////////
double countrate = 1;
float AdaptiveThreashold = 0.4; //0.8
int timesthreashold = 1;
#if defined(_hpma)
bool CPUPrefilter[7]={1,1,1,1,1,1,1}; //ccc
#elif defined(_GPU)
bool CPUPrefilter[7]={0,0,0,0,0,0,0}; //ccc
#endif

//int hpmamode[21] = {3,2,2,2,2,2,2,2,2,2,2,1,1,1,1,1,1,0,0,0,0};
int hpmamode[11] = {2,1,1,1,1,1,1,1,1,0,0};
///////////////////////////////////////////////////////

bool timesupCPU = false;
bool timesupGPU = false;
int timesupcount = 0;
bool timesup = false;
bool samepak = true;
inline int popcount_3(uint64_t x)
{
    x -= (x >> 1) & m1;             //put count of each 2 bits into those 2 bits
    x = (x & m2) + ((x >> 2) & m2); //put count of each 4 bits into those 4 bits 
    x = (x + (x >> 4)) & m4;        //put count of each 8 bits into those 8 bits 
    return (x * h01)>>56;  //returns left 8 bits of x + (x<<8) + (x<<16) + (x<<24) + ... 
}

inline unsigned long long int BitArrayToInt(bool arr[], int count1, int count2)
{
    unsigned long long int ret = 0;
    unsigned long long int tmp;
    for (int i = count1; i < count2; i++) {
        tmp = arr[i];
        ret |= tmp << (count2 - i - 1);
    }
    return ret;
}

inline int BitCount ( unsigned char arr[], int count1, int count2)
{
	int ret = 0;
	for(int i=count1/8;i<count2/8;i++)
	{
		bitset<8> a(arr[i]);
		ret += a.count();
	}
	bitset<8> b(arr[count2/8] & ( 0xff << (8-(count2 & 0x07))));
	ret += b.count();

	return ret;
}

/*unsigned long long int BitArrayToInt(bool arr[], int count1, int count2)
{
	unsigned long long int ret = 0;
	int tmp;
	for(int i = count1; i < count2; i++)
	{
		if(arr[i]==true)
		{
			ret += pow(2, count2-i);
			//cout << ret << endl;
		}
	}
	return ret;
}*/

//cuda
cudaError_t r;

//include mwm
#define DEBUG_AC
#include "mwm.c"
#include "acsmx.c"
#define err printf("file:%s->line(%d):%d\n", __FILE__, __LINE__, cudaGetErrorString(r));

//defined load file
#define T1c_FILE_PATH "DB/T1_char"
//#define T1b_FILE_PATH "DB/T1_table_s"
#define T1b_FILE_PATH "DB/T1_check"
#define T1_FILE_PATH "DB/T1_table_sc"
#define BT_FILE_PATH "DB/BT_table_s"
#define T2_FILE_PATH "DB/T2_s"
#define T2b_FILE_PATH "DB/T2_bit"
#define T2c_FILE_PATH "DB/T2_char"

#define PAT_FILE_PATH "DB/patNumdata"
#define PATTERN_FILE_PATH "DB/patdata"
#define IF_DROP_FILE_PATH "if_drop"
//thread and semaphore
#include <csignal>
#include <semaphore.h>
sem_t os_sem;
sem_t *sem_shm;

int num_threads = 1;
int cluster_id = -1;

//correctness

//defined about GPU
unsigned char *T1, *BT, *T2;
unsigned char *T2b;
unsigned char *T1b;
unsigned char *T1c;
unsigned char *T2c;
u_char* T2ptr[256*256];
static unsigned short *H1;
unsigned int t1size=0, btsize=0, t2size=0, win_size=0, ingpubuf_pktnum=1000, Output_table_size=0, pcapfile_pktnum=0,HMA_mode=false, t2bsize=0, t1bsize=0, t1csize=0, t2csize=0;
unsigned short *gFST1D, *gfailure_table, *gCST1D,*gCST_CDF_size;
short *gfinal_state_table;
bool test_state=false, justgpu = false, justprecpu=false;

unsigned int cap_pkt=0, precount_total=0, pat1or2count_total=0;
fstream outThroughput, fcap, all_test;
fstream outputyo;
fstream outputyoGPU;
//global
int two_NIC = 0;
int match_mode = 0;
unsigned int payloadlen = 1458;
int buffershift = 1472;
unsigned int rec_pkt_size = 1500;
unsigned long long int CountNumofPacketToGpuFun1 = 0;
unsigned long long int CountNumofPacketToGpuFun2 = 0;
int *counterGpuSnort;
int *d_counterGpuSnort;
int counterGPUHit = 0;
int countGPUthreadtimes = 0;
int totalcountpak[7] = {0};
int totalbushibaRR = 0;
int a = 0;

//global memory to gpu
int buffer_size ;//=blocksNumper*threadsperBlock;
int blocksNumper;// =32;//16
int threadsperBlock ;//= 256;//512
int bytes;// = sizeof(u_char)*buffer_size*1458;
double buffer_times ;
unsigned long long int handlepak[7] = {0};
unsigned long long int temp_test[4] = {0,0,0,0};
unsigned long long int temp_whoami[7] = {0,0,0,0,0,0,0};
unsigned long long int kernel_sum = 0; //nfound_GPU[]
unsigned long long int kernel_tablehits = 0; //Tablehits[]
unsigned long long int kernel_launch = 0;
bool GPUPrefilter = false;
int *d_nfound_GPU1,*d_nfound_GPU2;
int *d_whoami_GPU;
bool *d_Tablehits1,*d_Tablehits2;
bool *Tablehits1,*Tablehits2;
int *nfound_GPU1,*nfound_GPU2;
int *whoami_GPU;
bool CPUrecord = true;
int intoGPUtime=0;
u_char* d_fullTable;
u_char* fullTable;
texture <u_char,1,cudaReadModeElementType> texFulltable;
texture <u_char,1,cudaReadModeElementType> texacsm;

u_char* first_buffer;
u_char* second_buffer;
u_char* __restrict__ Central_memory;
u_char* __restrict__ Central_memory_tail; // = Central_memory;
u_char* __restrict__ CPU_Central_memory;
bool DB_Check = 0;
int DB_Count = 0;
int *CPU_Count;
u_char** Buffer_location;
bool isReady[2]={true,true};
mutex lockurmother;
condition_variable cv_buffer;
condition_variable cv_buffer1;
condition_variable cv_buffer2;
int alldead = 0;
bool firsttimerecord = true;

unsigned lastdrops=0,rec_drop_total=0; //2019/1/9 drop

u_char* d_Central_memory;

static u_char bitmasks[8];

//ac
ACSM_STRUCT * acsm;

//mwm
MWM_STRUCT *ps;
vector <bool> T1_1bit;
bitset <256*256> T1_bitset;
static bool *  T1_bool;
unsigned char T1_char[256*256/8];
unsigned char *d_T1_char;
unsigned char T2_char[256*256/8];
unsigned char *d_T2_char;
unsigned char *d_BT_char;
bool T1b_bool[256*256];
bool T2_bool[256*256];
bool * T1_char1;
bool * T1_char2;

#ifdef _test
char* patArray[2000];
#endif
int stat_mwm;

void fastMemcpy(unsigned char *pvDest, unsigned char *pvSrc, size_t nBytes) {
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

//string to int, three char to one int
int StrToInt(string str)
{
	unsigned int num=0;
	stringstream tmpstrtonum;
	tmpstrtonum << str[0] << str[1] << str[2];
	tmpstrtonum >> num;
	tmpstrtonum.clear();
	return num;
}

//rule of stable_sort, large to small
bool sortRule(const string& s1, const string& s2)
{
	return s1.size() > s2.size();
}

int MatchFound (void* id, int index, void *data)
{
	//printf("%s\n",id);
	return 0;
}
__device__ void MatchFound_AC (void* id)
{
	//printf("1");
	printf ("%s\n",(char *)id);
	//return 0;
}


unsigned long GetFileLength (FILE *filename)
{
	unsigned long pos = ftell(filename);
	unsigned long len = 0;
	fseek (filename, 0 ,SEEK_END);
	len = ftell (filename);
	fseek (filename,pos,SEEK_SET);
	return len;

}

/////////////////////////pop
//#include "popcnt.cpp"
inline int popcnt_naive(unsigned *buf , int n){
	int cnt =0 ;
	unsigned v;
	do {
		v=*buf;
		while(v){
			cnt += v&1;
			v>>=1;
		}
		buf++;
	}while(--n);
	return cnt;
}

/////////20190606 for check T1_char
inline bool CheckT1(int pos){
	unsigned char idx = T1_char[pos >> 3]; // pos/8
	//string str = bitset<8>(T1_char[ pos >> 3 ]).to_string();
	int check = pos & 0x07;
	if( idx & ( 0x01 << (7-check) ) )
	{
		return true;
	}else
	{
		return false;
	}
}
////////20200623 for check gpu T1_char
__device__ bool d_CheckT1(int pos, unsigned char *T1_char){
	unsigned char idx = T1_char[pos >> 3];
	int check = pos & 0x07;
	if( idx & ( 0x01 << (7-check) ) )
	{
		return true;
	}else
	{
		return false;
	}
}

////////20190718 for check T2_char
inline bool CheckT2(int pos){
	unsigned char idx = T2_char[pos >> 3]; // pos/8
	int check = pos & 0x07;
	if( idx & (0x01 << (7-check) ) )
	{
		return true;
	}else
	{
		return false;
	}


}
////////20200623 for check gpu T2_char
__device__ bool d_CheckT2(int pos, unsigned char *T2_char){
	unsigned char idx = T2_char[pos >> 3];
	int check = pos & 0x07;
	if( idx & (0x01 << (7-check) ) )
	{
		return true;
	}else
	{
		return false;
	}
}

////////20200623 for BitCount
__device__ int d_BitCount(unsigned char *arr, int count1, int count2){
	int ret = 0;
	/*for(int i=count1/8;i<count2/8;i++)
	{
		bitset<8> a(arr[i]);
		ret += a.count();
	}
	bitset<8> b(arr[count2/8] & (0xff << (8-(count2 & 0x07))));
	ret += b.count();*/
	
	for(int i=count1/8;i<count2/8;i++)
	{
		ret += __popcll((int)arr[i]);
	}
	ret += __popcll((int)arr[count2/8] & (0xff << (8-(count2 & 0x07))));


	return ret;
}

inline static size_t popcnt(uint8_t v){
	size_t rt;
#if INTRIN_WORDSIZE>=64
	printf("if \n\n");
	rt = popcnt((uint64_t)v);
#else
	printf("else \n\n");
	rt = popcnt((uint32_t)v);
#endif
	return rt;
}


static struct timeval startTime;
u_int8_t bidirectional = 0, wait_for_packet = 1, flush_packet = 0, do_shutdown = 0, verbose = 0;

pfring_zc_cluster *zc;

struct dir_info {
  u_int64_t __padding 
  __attribute__((__aligned__(64)));

  pfring_zc_queue *inzq, *outzq;
  pfring_zc_pkt_buff *tmpbuff;

  u_int64_t numPkts;
  u_int64_t numBytes;
  
  char *in_dev;
  char *out_dev;

  int bind_core;
  pthread_t thread
  __attribute__((__aligned__(64)));
};
struct dir_info dir[32]; //dir[2]

/* ******************************** */
void print_stats() {
	int totalCPUstate = 0;
	int totalintermittent = 0;
	int totaljustanumber = 0;
	
	struct timeval endTime;
	double deltaMillisec[num_threads];
	static u_int8_t print_all;
	/*static u_int64_t lastPkts = 0;
	static u_int64_t lastBytes = 0;
	static u_int64_t lastDrops = 0;*/
	unsigned long long int lastPkts[num_threads];
	unsigned long long int lastBytes[num_threads];
	unsigned long long int lastDrops[num_threads];

	double diff[num_threads], dropsDiff[num_threads], bytesDiff[num_threads];
	static struct timeval lastTime;
	//char buf1[64], buf2[64], buf3[64];
	char buf1[num_threads][64]={0}, buf2[num_threads][64]={0}, buf3[num_threads][64]={0};
	unsigned long long nBytes = 0, nPkts = 0/*, nDrops = 0*/;
	unsigned int drop_sep[num_threads]={0};
	unsigned int nowdrops= 0; //2019/1/9 drop
	pfring_zc_stat stats;
	int i;
	
	if(startTime.tv_sec == 0) {
		gettimeofday(&startTime, NULL);
		print_all = 0;
	} else
	{
		print_all = 1;
	}
	
	gettimeofday(&endTime, NULL);
	for(i=0;i<num_threads;i++)
	{
		deltaMillisec[i] = delta_time(&endTime, &startTime);
	}

  /*for (i = 0; i < 1 + bidirectional; i++) {
    nBytes += dir[i].numBytes;
    nPkts += dir[i].numPkts;
    if (pfring_zc_stats(dir[i].inzq, &stats) == 0)
      nDrops += stats.drop;
  }*/
	/*for (i = 0; i<num_threads;i++)
	{
		nBytes += dir[i].numBytes;
		nPkts += dir[i].numPkts;
		if (pfring_zc_stats(dir[i].inzq, &stats) == 0)
		{
			nDrops += stats.drop;
		}
	}*/

  /*fprintf(stderr, "=========================\n"
	  "Absolute Stats: %s pkts (%s drops) - %s bytes\n", 
	  pfring_format_numbers((double)nPkts, buf1, sizeof(buf1), 0),
	  pfring_format_numbers((double)nDrops, buf3, sizeof(buf3), 0),
	  pfring_format_numbers((double)nBytes, buf2, sizeof(buf2), 0));

  if(print_all && (lastTime.tv_sec > 0)) {
    char buf[256];

    deltaMillisec = delta_time(&endTime, &lastTime);
    diff = nPkts-lastPkts;
    dropsDiff = nDrops-lastDrops;
    bytesDiff = nBytes - lastBytes;
    bytesDiff /= (1000*1000*1000)/8;

    snprintf(buf, sizeof(buf),
	     "Actual Stats: %s pps (%s drops) - %s Gbps",
	     pfring_format_numbers(((double)diff/(double)(deltaMillisec/1000)),  buf2, sizeof(buf2), 1),
	     pfring_format_numbers(((double)dropsDiff/(double)(deltaMillisec/1000)),  buf1, sizeof(buf1), 1),
	     pfring_format_numbers(((double)bytesDiff/(double)(deltaMillisec/1000)),  buf3, sizeof(buf3), 1));
    fprintf(stderr, "%s\n", buf);
  }
    
  fprintf(stderr, "=========================\n\n");*/
  	cout<<"=========="<<endl;
	double totalbytes = 0.0;
	double totaldiff = 0;
	double totaldropsDiff = 0;
	for(i=0;i<num_threads;i++)
	{
		if (pfring_zc_stats(dir[i].inzq, &stats) == 0)
		{
			//cout<<"recv: "<<stats.recv<<" sent: "<<stats.sent<<" drop: "<<stats.drop<<endl;
			drop_sep[i] = (unsigned int)stats.drop;
			fprintf(stderr, "Thread: %d Now: %s pkts (%s drops)  ", //- %s bytes\n
				i,
				pfring_format_numbers((double)dir[i].numPkts, buf1[i], sizeof(buf1[i]), 0),
				pfring_format_numbers((double)drop_sep[i], buf3[i], sizeof(buf3[i]), 0)
				/*pfring_format_numbers((double)dir[i].numBytes, buf2, sizeof(buf2), 0)*/);

			if(print_all && (lastTime.tv_sec > 0)) 
			{
				char buf[256];

				deltaMillisec[i] = delta_time(&endTime, &lastTime);
				diff[i] = dir[i].numPkts-lastPkts[i];
				dropsDiff[i] = drop_sep[i]-lastDrops[i];
				bytesDiff[i] = dir[i].numBytes - lastBytes[i];
			totaldiff+=diff[i];
			totaldropsDiff+=dropsDiff[i];
			totalbytes+=(double)bytesDiff[i];
				//bytesDiff[i] /= (1000*1000*1000)/8;
				bytesDiff[i] /= (1000*1000*1000)/8;
				cout<<" lastBytes: "<<lastBytes[i]<<" dir[i].numBytes: "<<dir[i].numBytes<<" ";

				snprintf(buf, sizeof(buf),
					"Throughput: %s Gbps", //ALL: %s pps (%s drops) - %s Gbps
					/*pfring_format_numbers(((double)diff[i]/(double)(deltaMillisec/1000)),  buf2[i], sizeof(buf2[i]), 1),
					pfring_format_numbers(((double)dropsDiff[i]/(double)(deltaMillisec/1000)),  buf1[i], sizeof(buf1[i]), 1),*/
					pfring_format_numbers(((double)bytesDiff[i]/countrate),  buf3[i], sizeof(buf3[i]), 1));
				fprintf(stderr, "%s", buf);
			}
			
			//fprintf(stderr, "=========================\n\n");
			cout<<endl;
			
			lastPkts[i] = dir[i].numPkts;
			lastDrops[i] = drop_sep[i];
			lastBytes[i] = dir[i].numBytes;

			lastTime.tv_sec = endTime.tv_sec, lastTime.tv_usec = endTime.tv_usec;
		}
	}
	double throughput=0;
	for(int i=0;i<num_threads;i++)
	{
			throughput += bytesDiff[i];
			nowdrops += drop_sep[i]; //20191/9 drop
	}
	rec_drop_total = nowdrops - lastdrops; //20191/9 drop
	lastdrops = nowdrops; //20191/9 drop
	cout << "if_drop  = " << rec_drop_total << ", droprate:" << totaldropsDiff << "/" << totaldiff+totaldropsDiff << " (" << totaldropsDiff/(totaldiff+totaldropsDiff) << ") " <<endl;
	cout<<"ALL Throughput = "<<(double)throughput/(double)countrate<<endl;
	totalbytes=0;

	//2019/1/14 if_drop from sigproc to printstate
	outThroughput.open( IF_DROP_FILE_PATH ,ios::out | ios::ate);
	outThroughput << rec_drop_total;
	outThroughput.close();


	cout << "rec_drop_total: " << rec_drop_total << endl;
	if(intoGPUtime!=0)
	{
		cout << "wow:" << totalbushibaRR << "/" << intoGPUtime << "= " << totalbushibaRR/intoGPUtime << endl;
	}
	//outputyoGPU << endl;
	for(int i=0;i<num_threads;i++)
	{
		totalintermittent += count_intermittent[i];
		totaljustanumber += justanumber[i];
		cout << justanumber[i] << " ";
	}
	cout << endl;
	cout << totaljustanumber << endl;
	for(int i=0;i<num_threads;i++)
	{
		if(CPUPrefilter[i]==true)
		{
			//if(countpak[i]!=0)
			//{
				//cout << "CPUPrefilter["<<i<<"]: on  speed: " << countpak[i]/countrate*1516*8/1000000000 << endl;
				cout << "CPUPrefilter["<<i<<"]: on  speed: " << totalpacket[i]/countrate*1514*8/1000000000 << endl;
				//outputyoGPU << totalpacket[i]/countrate*1514*8/1000000000 << " ";
				totalspeed += totalpacket[i]/countrate*1514*8/1000000000;
				//outputyoGPU << (counterT2[i]+count_intermittent[i])/countrate*1530*8/1000000000 << " ";
			//}else if(countpak[i]==0)
			//{
				//cout << "CPUPrefilter["<<i<<"]: on  speed: not yet!" << endl;
			//}
		}else if(CPUPrefilter[i]==false)
		{
			//if(countpak[i]!=0)
			//{
				//cout << "CPUPrefilter["<<i<<"]: off speed: " << countpak[i]/countrate*1516*8/1000000000 << endl;
				cout << "CPUPrefilter["<<i<<"]: off  speed: " << (intoGPUtime*buffer_size*(justanumber[i]/(double)totaljustanumber))/countrate*1514*8/1000000000 << endl;
				//outputyoGPU << (intoGPUtime*buffer_size*(justanumber[i]/(double)totaljustanumber))/countrate*1514*8/1000000000 << " ";
				totalspeed += (intoGPUtime*buffer_size*(justanumber[i]/(double)totaljustanumber))/countrate*1514*8/1000000000;
				//outputyoGPU << (counterT2[i]+count_intermittent[i])/countrate*1530*8/1000000000 << " ";
			//}else if(countpak[i]==0)
			//{
				//cout << "CPUPrefilter["<<i<<"]: off speed: not yet!" << endl;
			//}
		}
		//totalspeed = totalspeed + countpak[i]/countrate*1516*8/1000000000;
		countpak[i] = 0;
	}
	totalCPUstate = 0;
	for(int i=0;i<num_threads;i++)
	{
		if(CPUPrefilter[i] == true)
		{
			//outputyoGPU << " 1";
		}else if (CPUPrefilter[i] == false)
		{
			//outputyoGPU << " 0";
		}
	}
	cout << "total speed: " << totalspeed << endl;
	if(totalspeed>=5)
	{

		if(firsttimerecord == false)
		{
			outputyo << totalspeed << " ";
			/*if(CPUPrefilter[0]==0)
			{
				outputyo << totalspeed << endl;
			}else if(CPUPrefilter[0]==1)
			{
				outputyo << totalspeed << endl;
			}*/
		}
		firsttimerecord = false;
		for(int i=0;i<num_threads;i++)
		{
			outputyo << CPUPrefilter[i] << " ";
		}
		outputyo << endl;	
	}
	
	totalspeed = 0;

	/*if(DB_Check==0)
	{
		for(int i=0;i<num_threads;i++)
		{
			cout << setw(3) << CPU_Count[i] << " | ";
		}
		cout << isReady[0] << endl;
		for(int i=0;i<num_threads;i++)
		{
			cout << "  0 | ";
		}
		cout << isReady[1] << endl;
	}else if(DB_Check==1)
	{
	
		for(int i=0;i<num_threads;i++)
		{
			cout << "  0 | ";
		}
		cout << isReady[0] << endl;
		for(int i=0;i<num_threads;i++)
		{
			cout << setw(3) << CPU_Count[i+num_threads] << " | ";
		}
		cout << isReady[1] << endl;
	}*/

	cout << "AllDead: " << alldead << endl;
	alldead = 0;
	cout << "countGPUthreadtimes: " << countGPUthreadtimes << endl;
	countGPUthreadtimes = 0;

	/*cout << "Totalcantlock: ";
	for(int i=0;i<num_threads;i++)
	{
		cout << totalcantlock[i] << ":" << justanumber[i] << " _" << totalcantlock[i]+justanumber[i] << "_ " << "(" << ((double)totalcantlock[i]/(totalcantlock[i]+justanumber[i])) << ")" << " ";
	}
	cout <<endl;*/

	timesupcount++; //RRR
	double totalsps[7] = {0.0};
	double totalpak[7] = {0.0};
	double totalpercent[7] = {0.0};
	if(timesupcount >= timesthreashold)
	{
		timesup = true;
		timesupcount = 0;
		//int threadpak = intoGPUtime*buffer_size/num_threads;
		for(int i=0;i<num_threads;i++)
		{

			//CPUPrefilter[i] = !CPUPrefilter[i];

			totalsps[i] = counterT2[i] + count_intermittent[i];
			totalpak[i] = intoGPUtime*buffer_size/num_threads + totalpacket[i];

			//totalpercent[i] = (double)totalsps[i]/(double)totalpak[i];
			//cout << i << ": (" << counterT2[i] << "+" << count_intermittent[i] << ")/(" << intoGPUtime*buffer_size/num_threads << "+" << totalpacket[i] << ")= " << totalpercent[i];
			if(CPUPrefilter[i]==true)
			{
				totalpercent[i] = counterT2[i]/(double)totalpacket[i];
				cout << i << ": (" << counterT2[i] << "+" << count_intermittent[i] << ")/(" << (intoGPUtime*buffer_size*(justanumber[i]/(double)totaljustanumber)) << "+" << totalpacket[i] << ")=" << totalpercent[i] << endl;
			}else if(CPUPrefilter[i] == false)
			{
				//totalpercent[i] = count_intermittent[i]/(double)(intoGPUtime*buffer_size/num_threads);
				totalpercent[i] = count_intermittent[i]/(double)(intoGPUtime*buffer_size*(justanumber[i]/(double)totaljustanumber));
				cout << i << ": (" << counterT2[i] << "+" << count_intermittent[i] << ")/(" << (intoGPUtime*buffer_size*(justanumber[i]/(double)totaljustanumber)) << "+" << totalpacket[i] << ")=" << totalpercent[i] << endl;
			}
			if(totalpercent[i] > (AdaptiveThreashold-0.002))
			{
				if(CPUPrefilter[i] == false)
				{
					//CPUPrefilter[i] = true;
				}
			}else if(totalpercent[i] < (AdaptiveThreashold-0.002))
			{
				if(CPUPrefilter[i] == true)
				{
					//CPUPrefilter[i] = false;
				}
			}
			if(i==0 && totalpercent[0]>=0)
			{
				//modechoose = ((int)(totalpercent[0]*100)/5);
				modechoose = ((int)(totalpercent[0]*100)/10);
				int temppercent = ((int)(totalpercent[0]*100))%10;
				//if(temppercent>=4||temppercent>=9)
				if(temppercent>=9)
				{
					modechoose+=1;
				}
				//cout << "modechoose: " << modechoose << endl;
			}
			unique_lock<mutex> lk(lockurmother);
			counterT2[i] = 0;
			count_intermittent[i] = 0;
			totalpacket[i] = 0;
			totalpercent[i] = 0;
			justanumber[i] = 0;
			totallock[i] = 0;
			totalcantlock[i] = 0;
			lk.unlock();
		}
		//cout << hpmamode[modechoose] << endl;
		for(int i=0;i<num_threads;i++) //CGCLB
		{
			if(modechoose != -1)
			{
				if(i<hpmamode[modechoose])
				{
					//CPUPrefilter[i] = false;
				}else if(i>=hpmamode[modechoose])
				{
					//CPUPrefilter[i] = true;
				}
			}
		}
		intoGPUtime = 0;
		timesup = false;
		timesupGPU = true;
		totalCPUstate = 0;
		totalintermittent = 0;
		totaljustanumber = 0;
		modechoose = -1;
	}

}

/* ******************************** */

void sigproc(int sig) {
  static int called = 0;
  fprintf(stderr, "Leaving...\n");
  if(called) return; else called = 1;

  do_shutdown = 1;

  //print_stats();
  
  /*pfring_zc_queue_breakloop(dir[0].inzq);
  if (bidirectional) pfring_zc_queue_breakloop(dir[1].inzq);*/
	for(int i=0;i<num_threads;i++)
	{
		pfring_zc_queue_breakloop(dir[i].inzq);
	}
	
	/*outThroughput.open( IF_DROP_FILE_PATH ,ios::out | ios::ate);
	outThroughput << rec_drop_total;
	outThroughput.close();

	cout << "rec_drop_total: " << rec_drop_total << endl;*/
}

/* *************************************** */

void printHelp(void) {
	printf("compile success!!!\n");
  printf("zbounce - (C) 2014-2018 ntop.org\n");
  printf("Using PFRING_ZC v.%s\n", pfring_zc_version());
  printf("A packet forwarder application between interfaces.\n\n");
  printf("Usage:  zbounce -i <device> -o <device> -c <cluster id> [-b]\n"
	 "                [-h] [-g <core id>] [-f] [-v] [-a]\n\n");
  printf("-h              Print this help\n");
  printf("-i <device>     Ingress device name\n");
  printf("-o <device>     Egress device name\n");
  printf("-c <cluster id> cluster id\n");
  printf("-b              Bridge mode (forward in both directions)\n");
  printf("-g <core id>    Bind this app to a core (with -b use <core id>:<core id>)\n");
  printf("-a              Active packet wait\n");
  printf("-f              Flush packets immediately\n");
  printf("-v              Verbose\n");
  printf("-e              match mode\n");
  printf("-n              num of threads\n");
  printf("-N              Two NIC control\n");
  printf("-s              BlocksNumper\n");
  printf("-t              threadsperBlock\n");
  printf("-r		  buffer_times\n");
  exit(-1);
}

/* *************************************** */
//CUDA kernel function
__global__ void snort_stream_prefilter(u_char * Tx,int len,int GPUtimes,bool *Tablehits, int *whoami_GPU, u_char * fullTable, unsigned char *T1_char, unsigned char *T2_char, unsigned char *BT)
{
	int gid= blockIdx.x*blockDim.x+threadIdx.x; // 0~20,128,0~128
	int tid= threadIdx.x;
	unsigned char pak_pick1, pak_pick2, pak_pick3;
	int state=0;
	int mlist_counter=0;
	unsigned char *Tend;
	unsigned char *T;
	T=Tx+gid*len+2;
	Tend = T + len -2;
	unsigned char *whoami;
	//whoami = T - 1;
	unsigned char *CPUState;
	CPUState = T - 2;
	//printf("%d,%d,%d\n",blockIdx.x,blockDim.x,threadIdx.x);
	//printf("%d\n",blockDim.x*gridDim.x);

	int vt1_pos = 0;
	int checkBT = 0;
	int PidforT2 = 0;
	int tmp = 0;
	unsigned char *Tpre;
#if defined(_GPU_shared)	
	__shared__ unsigned char sh_T1_char[8192];
	__shared__ unsigned char sh_T2_char[6720];
	__shared__ unsigned char sh_BT[1024];
	
	if(threadIdx.x==0)
	{
		//printf("%d\n",*CPUState);
		for(int i=0;i<8192;i++)
		{
			sh_T1_char[i] = T1_char[i];
		}
		for(int i=0;i<6720;i++)
		{
			sh_T2_char[i] = T2_char[i];
		}
		for(int i=0;i<1024;i++)
		{
			sh_BT[i] = BT[i];
		}
	}

	__syncthreads();
#endif	

	if(*CPUState == 0)
	{
		for(int d_GPUtimes = 0; d_GPUtimes < GPUtimes; d_GPUtimes++)
		{
			Tpre = T + (blockDim.x*gridDim.x)*d_GPUtimes*len;
	//printf("%d, %d, %d\n",(int)*(Tpre),(int)*(Tpre+1),(int)*(Tpre+2));
		whoami = Tpre - 1;
			for (int i=0; i<1458-2; i++)
			{
#if defined(_GPU_texture)
			if( tex1Dfetch( texFulltable,(( *(Tpre+i) *256 +  *(Tpre+i+1) )*32 ) + *(Tpre+i+2) /8) & (128 >> (*(Tpre+i+2)%8 )) )
			{
				//Tablehits[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = 1;
				whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] + ((int)*whoami+1);
				break;
			}
#elif defined(_GPU_shared)
				pak_pick1 = (int)*(Tpre+i);
				pak_pick2 = (int)*(Tpre+i+1);
				vt1_pos = ( pak_pick1 *256 ) + pak_pick2 ;
				if( d_CheckT1((int)vt1_pos,sh_T1_char))
				{
					pak_pick3 = (int)*(Tpre+i+2);
					checkBT = (int)sh_BT[vt1_pos/64];
					PidforT2 = checkBT + d_BitCount(sh_T1_char, (vt1_pos/64)*64 ,vt1_pos);
					if( d_CheckT2(PidforT2*256+(int)pak_pick3,sh_T2_char) )
					{
						//Tablehits[gid] = 1;
						//atomicAdd(&whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes],(int)*whoami+1);
						whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] + ((int)*whoami+1);
						//printf("%d = %d\n",gid+(blockDim.x*gridDim.x)*d_GPUtimes,(int)*whoami+1);
						break;
					}
				}
#endif				
			}
		}
	}else if(*CPUState == 1)
	{
		for(int d_GPUtimes = 0; d_GPUtimes < GPUtimes; d_GPUtimes++)
		{
			//whoami = T + (blockDim.x*gridDim.x)*d_GPUtimes*len -1;
			//whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] + ((int)*whoami+1);
			//atomicAdd(&whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes],(int)*whoami+1);
		}
	}
}
__global__ void snort_stream_snort(u_char * Tx, ACSM_STRUCT * acsm,int len,int GPUtimes,int *whoami_GPU, int *nfound_GPU, u_char * fullTable)
{
	int gid= blockIdx.x*blockDim.x+threadIdx.x; // 20,128,0~128
	//printf("%d, %d\n",blockIdx.x,threadIdx.x);
	int tid= threadIdx.x;
	unsigned char pak_pick1, pak_pick2, pak_pick3;
	int state=0;
	int mlist_counter=0;
	__shared__	ACSM_PATTERN * mlist;
	unsigned char *Tend;
	__shared__	ACSM_STATETABLE * StateTable;
	StateTable= acsm->acsmStateTable;
	unsigned char *T;
	T=Tx+gid*len+2;
	Tend = T + len -2;
	unsigned char *Tsnort;
	unsigned char *whoami;
	
	
	bool SkipPre = false;
	for(int d_GPUtimes = 0;d_GPUtimes<GPUtimes;d_GPUtimes++)
	{
		Tsnort = T + (blockDim.x*gridDim.x)*d_GPUtimes*len;
		whoami = Tsnort -1;
	//printf("%d, %d\n",(int)*Tsnort, (int)*(Tsnort+1));
	//printf("%d\n",(int)*(Tsnort-1));
		for (int i=0;i<1458;i++)
		{	
			// into T2 times counting
			state = StateTable[state].NextState[*(Tsnort+i)];

			if( StateTable[state].MatchList != NULL )
			{
				//printf("%d,%d\n",i,StateTable[state].MatchList->n);
				//whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] + ((int)*whoami+1);
				for( mlist=StateTable[state].MatchList; mlist!=NULL;mlist=mlist->next )
				{
					//nfound_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes]=nfound_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes]+1;
					whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] + ((int)*whoami+1);
					//atomicAdd(&nfound_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes],1);
				}
			}
		}
	}
	//atomicAdd(&whoami_GPU[gid],(int)*whoami+1);

}
//GGG
__global__ void snort_ac_prefilter(u_char * Tx, ACSM_STRUCT * acsm,int len, int GPUtimes, int *nfound_GPU,bool *Tablehits, int *whoami_GPU, u_char * fullTable, unsigned char *T1_char, unsigned char *T2_char, unsigned char *BT)
{
	int gid= blockIdx.x*blockDim.x+threadIdx.x; // 20,128,0~128
	int tid= threadIdx.x;
	unsigned char pak_pick1, pak_pick2, pak_pick3;
	int state=0;
	int mlist_counter=0;
	__shared__	ACSM_PATTERN * mlist;
	unsigned char *Tend;
	__shared__	ACSM_STATETABLE * StateTable;
	StateTable= acsm->acsmStateTable;
	unsigned char *T;
	T=Tx+gid*len+2;
	Tend = T + len -2;
	unsigned char *whoami;
	whoami = T - 1;
	unsigned char *CPUState;
	CPUState = T - 2;
	//printf("%d, %d, %d\n",blockIdx.x,blockDim.x,threadIdx.x); 20,128,0~128
	//printf("%d\n",gid);
	//printf("%d: %d, %d, %d\n", gid,*T,*(T+1),*(T+2));  //work
	//printf("%d\n",(int)Tend-(int)T);

	int vt1_pos = 0;
	int checkBT = 0;
	int PidforT2 = 0;
	int tmp = 0;
	unsigned char *Tpre;
	unsigned char *Tsnort;
	Tpre = T;
#if defined(_GPU_shared)
	__shared__ unsigned char sh_T1_char[8192];
	__shared__ unsigned char sh_T2_char[6720];
	__shared__ unsigned char sh_BT[1024];
	
	if(threadIdx.x==0)
	{
		//printf("%d\n",*CPUState);
		for(int i=0;i<8192;i++)
		{
			sh_T1_char[i] = T1_char[i];
		}
		for(int i=0;i<6720;i++)
		{
			sh_T2_char[i] = T2_char[i];
		}
		for(int i=0;i<1024;i++)
		{
			sh_BT[i] = BT[i];
		}
	}

	__syncthreads();
#endif	
	
	bool SkipPre = false;
	//for (state = 0; T < Tend ; T++)
	for(int d_GPUtimes = 0;d_GPUtimes<GPUtimes;d_GPUtimes++)
	{
		Tsnort = T + (blockDim.x*gridDim.x)*d_GPUtimes*len;
		for (int i=0;i<1458;i++)
		{	
			// into T2 times counting
			//state = StateTable[state].NextState[*T];
			state = StateTable[state].NextState[*(Tsnort+i)];
			
			if( StateTable[state].MatchList != NULL )
			{
				for( mlist=StateTable[state].MatchList; mlist!=NULL;mlist=mlist->next )
				{
					//nfound_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes]=nfound_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes]+1;
					whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] + ((int)*whoami+1);
					//nfound_GPU[gid]=nfound_GPU[gid]+1;
					//nfound_GPU[gid] = mlist->iid;
					////char		nfound_GPU[id*4+mlist_counter]= mlist->iid;
				}
			}
	
		}
	}
	
	if(*CPUState == 0)
	{
		for(int d_GPUtimes = 0; d_GPUtimes < GPUtimes; d_GPUtimes++)
		{
			Tpre = T + (blockDim.x*gridDim.x)*d_GPUtimes*len;
			whoami = Tpre -1;
			for (int i=0; i<1458-2; i++)
			{
#if defined(_GPU_shared)				
				pak_pick1 = (int)*(Tpre+i);
				pak_pick2 = (int)*(Tpre+i+1);
				//vt1_pos = ( *(Tpre+i) << 8 ) | *(Tpre+i+1) ;
				vt1_pos = ( pak_pick1 *256 ) + pak_pick2 ;
				if( d_CheckT1((int)vt1_pos,sh_T1_char))
				{
					//printf("%d, %d, %d\n",(int)*whoami,(int)pak_pick1,(int)pak_pick2);
					pak_pick3 = (int)*(Tpre+i+2);
					//Tablehits[gid]=1;
					//nfound_GPU[gid] = nfound_GPU[gid]+1;
					checkBT = (int)sh_BT[vt1_pos/64];
					PidforT2 = checkBT + d_BitCount(sh_T1_char, (vt1_pos/64)*64 ,vt1_pos);
					if( d_CheckT2(PidforT2*256+(int)pak_pick3,sh_T2_char) )
					{
						//printf("%d, %d, %d\n",(int)pak_pick1,(int)pak_pick2,(int)pak_pick3);
						//printf("whoami: %d\n",(int)*whoami);
		
						//Tablehits[gid] = 1;
						//nfound_GPU[gid] = nfound_GPU[gid]+1;
						//whoami_GPU[gid]=(int)*whoami+1;
					
						//atomicAdd(&whoami_GPU[gid],(int)*whoami+1);
						whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] + ((int)*whoami+1);
		
						//__syncthreads();
						break;
					}
				}
#elif defined(_GPU_texture)
				if( tex1Dfetch( texFulltable,(( *(Tpre+i) *256 +  *(Tpre+i+1) )*32 ) + *(Tpre+i+2) /8) & (128 >> (*(Tpre+i+2)%8 )) )
				{
					//Tablehits[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = 1;
					whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] + ((int)*whoami+1);
					break;
				}
#endif				
			}
		}
	}else if(*CPUState == 1)
	{
		for(int d_GPUtimes = 0; d_GPUtimes < GPUtimes; d_GPUtimes++)
		{
			whoami = T + (blockDim.x*gridDim.x)*d_GPUtimes*len -1;
			//atomicAdd(&whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes],(int)*whoami+1);
			whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] = whoami_GPU[gid+(blockDim.x*gridDim.x)*d_GPUtimes] + ((int)*whoami+1);
		}
	}





}

//CPU presistent PPP
void *persistentkernel(void *unused)
{
	cudaStream_t stream1, stream2, stream3, stream4;
	cudaEvent_t event,start1,start2,stop1,stop2;

	/*cudaEventCreate(&event);
	cudaEventCreate(&start1);
	cudaEventCreate(&stop1);
	cudaEventCreate(&start2);
	cudaEventCreate(&stop2);
	float time1=0, time2=0;*/

	int GPUtimes = buffer_size/(blocksNumper*threadsperBlock);
	cout << "GPUtimes: " << GPUtimes << endl;
	
	bind2core(7);
	long long int totalcount = 0;
	while(!do_shutdown){
		usleep(1);
		if(!isReady[0])
		{
			/*cudaStreamCreate(&stream1);
			cudaStreamCreate(&stream2);
			cudaStreamCreate(&stream3);
			cudaStreamCreate(&stream4);*/

			totalcount=0;
			gettimeofday(&startCPU,NULL);
			for(int i=0;i<num_threads;i++)
			{
				//memcpy(Central_memory+totalcount,CPU_Central_memory+(i*bytes),CPU_Count[i]*buffershift);
				fastMemcpy(Central_memory+totalcount,CPU_Central_memory+(i*bytes),CPU_Count[i]*buffershift);
				totalcount+=CPU_Count[i]*buffershift;
			}
			totalcount = 0;
			
			for(int i=0;i<num_threads;i++)
			{
				CPU_Count[i] = 0;
			}
			isReady[0] = true;
			cv_buffer1.notify_all();
			
			gettimeofday(&endCPU,NULL);
			diffCPU += 1000000*(endCPU.tv_sec-startCPU.tv_sec)+endCPU.tv_usec-startCPU.tv_usec;
			//cout << "                                 time1: " << diffCPU << endl;
			diffCPU = 0;

			

			cudaMemcpy(d_Central_memory,Central_memory,bytes,cudaMemcpyHostToDevice);
			//cv_buffer1.notify_all();
			
			/*cudaMemcpy(d_T1_char,&T1_char,65536/8,cudaMemcpyHostToDevice);
			cudaMemcpy(d_T2_char,&T2_char,53760/8,cudaMemcpyHostToDevice);
			cudaMemcpy(d_BT_char,BT,1024,cudaMemcpyHostToDevice);
			snort_ac_prefilter<<<blocksNumper,threadsperBlock>>>(d_Central_memory,acsm,(payloadlen+3),d_nfound_GPU1,d_Tablehits1,d_whoami_GPU,d_fullTable,d_T1_char,d_T2_char,d_BT_char);
			cudaMemcpy(Tablehits1, d_Tablehits1,sizeof(bool)*(blocksNumper*threadsperBlock), cudaMemcpyDeviceToHost);
			cudaMemcpy(whoami_GPU, d_whoami_GPU,sizeof(int)*(blocksNumper*threadsperBlock), cudaMemcpyDeviceToHost);
			*/
	#if defined(_GPU_shared)		
			/*cudaMemcpyAsync(d_T1_char,&T1_char,65536/8,cudaMemcpyHostToDevice);
			cudaMemcpyAsync(d_T2_char,&T2_char,53760/8,cudaMemcpyHostToDevice);
			cudaMemcpyAsync(d_BT_char,BT,1024,cudaMemcpyHostToDevice);*/
	#endif			
			//snort_stream_prefilter<<<blocksNumper,threadsperBlock,0>>>(d_Central_memory,buffershift,GPUtimes,d_Tablehits1,d_whoami_GPU,d_fullTable,d_T1_char,d_T2_char,d_BT_char);
			snort_stream_snort<<<blocksNumper,threadsperBlock,0>>>(d_Central_memory,acsm,buffershift,GPUtimes,d_whoami_GPU,d_nfound_GPU1,d_fullTable);
			//snort_ac_prefilter<<<blocksNumper,threadsperBlock,0>>>(d_Central_memory,acsm,buffershift,GPUtimes,d_nfound_GPU1,d_Tablehits1,d_whoami_GPU,d_fullTable,d_T1_char,d_T2_char,d_BT_char);
			
			//snort_stream_prefilter<<<blocksNumper,threadsperBlock,0,stream1>>>(d_Central_memory,buffershift,GPUtimes,d_Tablehits1,d_whoami_GPU,d_fullTable,d_T1_char,d_T2_char,d_BT_char);
			//cudaEventRecord(event,stream1);
			//snort_stream_snort<<<blocksNumper,threadsperBlock,0,stream2>>>(d_Central_memory,acsm,buffershift,GPUtimes,d_nfound_GPU1,d_fullTable);
			
			//cudaStreamWaitEvent(stream3,event,0);
			//cudaMemcpyAsync(whoami_GPU, d_whoami_GPU,sizeof(int)*(blocksNumper*threadsperBlock*buffer_times), cudaMemcpyDeviceToHost,stream3);

			//cudaMemcpy(Tablehits1, d_Tablehits1,sizeof(bool)*(blocksNumper*threadsperBlock*buffer_times), cudaMemcpyDeviceToHost);
			
			cudaMemcpy(whoami_GPU, d_whoami_GPU,sizeof(int)*(blocksNumper*threadsperBlock*buffer_times), cudaMemcpyDeviceToHost);
			//cudaMemcpy(nfound_GPU1, d_nfound_GPU1,sizeof(int)*(blocksNumper*threadsperBlock*buffer_times), cudaMemcpyDeviceToHost);

			cudaDeviceSynchronize();
			/*cudaEventSynchronize(stop1);
			cudaEventElapsedTime(&time1, start1, stop1);
			outputyoGPU << time1 << endl;*/

			/*cudaStreamDestroy(stream1);
			cudaStreamDestroy(stream2);
			cudaStreamDestroy(stream3);
			cudaStreamDestroy(stream4);*/

			intoGPUtime++;
			countGPUthreadtimes++;
			
			for(int i=0;i<blocksNumper*threadsperBlock*buffer_times;i++)
			{
				countpak[i%num_threads]++;
				switch (whoami_GPU[i])
				{
					case 0:
						break;
					case 1:
						count_intermittent[0]++;
						temp_test[0]++;
						break;
					case 2:
						count_intermittent[1]++;
						temp_test[0]++;
					        break;
					case 3:
						count_intermittent[2]++;
						temp_test[0]++;
					        break;
					case 4:
						count_intermittent[3]++;
						temp_test[0]++;
					        break;
					case 5:
						count_intermittent[4]++;
						temp_test[0]++;
					        break;
					case 6:
						count_intermittent[5]++;
						temp_test[0]++;
					        break;
					case 7:
						count_intermittent[6]++;
						temp_test[0]++;
						break;
				}
			}
			// count percentage to call CPU

			/*for(int i=0;i<blocksNumper*threadsperBlock*buffer_times;i++)
			{
				//cout << nfound_GPU1[i] << endl;
				//temp_test[0]=temp_test[0]+(nfound_GPU1[i]);
				//temp_test[2]=temp_test[2]+(Tablehits1[i]);
			}*/
			kernel_sum+=temp_test[0];
			//kernel_tablehits+=temp_test[2];
			//cout << "kernel_sum1: " << temp_test[0] << endl;
			CountNumofPacketToGpuFun1++;
			temp_test[0]=0;
			temp_test[2]=0;

			//cudaMemset(d_nfound_GPU1,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
			//cudaMemset(d_Tablehits1,0,sizeof(bool)*blocksNumper*threadsperBlock*buffer_times);
			cudaMemset(d_whoami_GPU,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
			memset(nfound_GPU1,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);

		}else if(!isReady[1])
		{
			/*cudaStreamCreate(&stream1);
			cudaStreamCreate(&stream2);
			cudaStreamCreate(&stream3);
			cudaStreamCreate(&stream4);*/

			totalcount=0;
			gettimeofday(&startCPU,NULL);
			for(int i=0;i<num_threads;i++)
			{
				//memcpy(Central_memory+bytes+totalcount,CPU_Central_memory+((i+num_threads)*bytes),CPU_Count[i+num_threads]*buffershift);
				fastMemcpy(Central_memory+bytes+totalcount,CPU_Central_memory+((i+num_threads)*bytes),CPU_Count[i+num_threads]*buffershift);
				totalcount+=CPU_Count[i+num_threads]*buffershift;
				//cout << CPU_Count[i+num_threads] << " ";
			}
			totalcount = 0;

			for(int i=0;i<num_threads;i++)
			{
				CPU_Count[i+num_threads] = 0;
			}
			isReady[1] = true;
			cv_buffer2.notify_all();
			
			//cout << endl;
			gettimeofday(&endCPU,NULL);
			diffCPU += 1000000*(endCPU.tv_sec-startCPU.tv_sec)+endCPU.tv_usec-startCPU.tv_usec;
			//cout << "                                 time2: " << diffCPU << endl;
			diffCPU = 0;

			

			cudaMemcpy(d_Central_memory+bytes,Central_memory+bytes,bytes,cudaMemcpyHostToDevice);
			//cv_buffer2.notify_all();

			/*cudaMemcpy(d_T1_char,&T1_char,65536/8,cudaMemcpyHostToDevice);
			cudaMemcpy(d_T2_char,&T2_char,53760/8,cudaMemcpyHostToDevice);
			cudaMemcpy(d_BT_char,BT,1024,cudaMemcpyHostToDevice);
			snort_ac_prefilter<<<blocksNumper,threadsperBlock>>>(d_Central_memory+bytes,acsm,(payloadlen+3),d_nfound_GPU2,d_Tablehits2,d_whoami_GPU,d_fullTable,d_T1_char,d_T2_char,d_BT_char);
			cudaMemcpy(Tablehits2, d_Tablehits2,sizeof(bool)*(blocksNumper*threadsperBlock), cudaMemcpyDeviceToHost);
			cudaMemcpy(whoami_GPU, d_whoami_GPU,sizeof(int)*(blocksNumper*threadsperBlock), cudaMemcpyDeviceToHost);
			*/
	#if defined(_GPU_shared)
			/*cudaMemcpyAsync(d_T1_char,&T1_char,65536/8,cudaMemcpyHostToDevice);
			cudaMemcpyAsync(d_T2_char,&T2_char,53760/8,cudaMemcpyHostToDevice);
			cudaMemcpyAsync(d_BT_char,BT,1024,cudaMemcpyHostToDevice);*/
	#endif

			//snort_stream_prefilter<<<blocksNumper,threadsperBlock,0>>>(d_Central_memory+bytes,buffershift,GPUtimes,d_Tablehits2,d_whoami_GPU,d_fullTable,d_T1_char,d_T2_char,d_BT_char);
			snort_stream_snort<<<blocksNumper,threadsperBlock,0>>>(d_Central_memory+bytes,acsm,buffershift,GPUtimes,d_whoami_GPU,d_nfound_GPU2,d_fullTable);	
			//snort_ac_prefilter<<<blocksNumper,threadsperBlock,0>>>(d_Central_memory,acsm,buffershift,GPUtimes,d_nfound_GPU2,d_Tablehits2,d_whoami_GPU,d_fullTable,d_T1_char,d_T2_char,d_BT_char);
				
			//snort_stream_prefilter<<<blocksNumper,threadsperBlock,0,stream1>>>(d_Central_memory+bytes,buffershift,GPUtimes,d_Tablehits2,d_whoami_GPU,d_fullTable,d_T1_char,d_T2_char,d_BT_char);
			//cudaEventRecord(event,stream1);
			//snort_stream_snort<<<blocksNumper,threadsperBlock,0,stream2>>>(d_Central_memory+bytes,acsm,buffershift,GPUtimes,d_nfound_GPU2,d_fullTable);
			//cudaStreamWaitEvent(stream3,event,0);
			//cudaMemcpyAsync(whoami_GPU, d_whoami_GPU,sizeof(int)*(blocksNumper*threadsperBlock*buffer_times), cudaMemcpyDeviceToHost,stream3);
				
			//cudaMemcpy(Tablehits2, d_Tablehits2,sizeof(bool)*(blocksNumper*threadsperBlock*buffer_times), cudaMemcpyDeviceToHost);

			cudaMemcpy(whoami_GPU, d_whoami_GPU,sizeof(int)*(blocksNumper*threadsperBlock*buffer_times), cudaMemcpyDeviceToHost);
			//cudaMemcpy(nfound_GPU2,d_nfound_GPU2,sizeof(int)*(blocksNumper*threadsperBlock*buffer_times), cudaMemcpyDeviceToHost);

			cudaDeviceSynchronize();
			/*cudaEventSynchronize(stop2);
			cudaEventElapsedTime(&time2, start2, stop2);
			outputyoGPU << time2 << endl;*/

			/*cudaStreamDestroy(stream1);
			cudaStreamDestroy(stream2);
			cudaStreamDestroy(stream3);
			cudaStreamDestroy(stream4);*/

			intoGPUtime++;
			countGPUthreadtimes++;
			
			for(int i=0;i<blocksNumper*threadsperBlock*buffer_times;i++)
			{
				countpak[i%num_threads]++;
			        switch (whoami_GPU[i])
			        {
					case 0: 
						break;
			                case 1:
						count_intermittent[0]++;
						temp_test[1]++;
			                        break;
			                case 2:
						count_intermittent[1]++;
						temp_test[1]++;
			                        break;
			                case 3:
						count_intermittent[2]++;
						temp_test[1]++;
			                        break;
			                case 4:
						count_intermittent[3]++;
						temp_test[1]++;
			                        break;
			                case 5:
						count_intermittent[4]++;
						temp_test[1]++;
			                        break;
			                case 6:
						count_intermittent[5]++;
						temp_test[1]++;
			                        break;
					case 7:
						count_intermittent[6]++;
						temp_test[1]++;
						break;
			        }
			}
			
			// count percentage to call CPU
			//int threadpak = intoGPUtime*blocksNumper*threadsperBlock/num_threads;
			/*if(intoGPUtime>=numofpakcal)
			{
				cout < "fu3k you" << endl;
				for(int i=0;i<num_threads;i++)
				{
					/*if( ((double)temp_whoami[i] / threadpak) > AdaptiveThreashold )  //AdaptiveThreashold = 0.8;
					{
						//cout << "1CPU" << i << "  is time to close prefilter! cuz now percent is:" << (double)temp_whoami[i] / threadpak << endl;
						if(CPUPrefilter[i] == false)
						{
							//CPUPrefilter[i]=false; // pre -> nonpre
							//cout << "GPU: 1close!"<< (double)temp_whoami[i] << "/" << threadpak << "= " << (double)temp_whoami[i] / threadpak << endl;
						}
					}else if( ((double)temp_whoami[i] / threadpak) < AdaptiveThreashold )  //AdaptiveThreashold = .8;
					{
						if(CPUPrefilter[i] == false)
						{
							//CPUPrefilter[i]=true;
							//cout << "GPU: 1open!"<< (double)temp_whoami[i] << "/" << threadpak << "= " << (double)temp_whoami[i] / threadpak << endl;
						}
					}
					temp_whoami[i] = 0;*/
					/*if(CPUPrefilter[i] == false)
					{
						CPUPrefilter[i] = true;
					}
				}
				intoGPUtime=0;
			}*/

			/*for(int i=0;i<blocksNumper*threadsperBlock*buffer_times;i++)
			{
				//temp_test[1]=temp_test[1]+(nfound_GPU2[i]);
				//temp_test[3]=temp_test[3]+(Tablehits2[i]);
			}*/
			kernel_sum += temp_test[1];
			//kernel_tablehits += temp_test[3];
			//cout << "kernel_sum2: " << temp_test[1] << endl;
			CountNumofPacketToGpuFun2++;
			temp_test[1]=0;
			temp_test[3]=0;

			//cudaMemset(d_nfound_GPU2,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
			//cudaMemset(d_Tablehits2,0,sizeof(bool)*blocksNumper*threadsperBlock*buffer_times);
			cudaMemset(d_whoami_GPU,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
			memset(nfound_GPU2,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
			
		}
	
	}


	pthread_exit(NULL);
}

//CPU function
void *packet_consumer_thread(void *_i) {
	struct dir_info *i = (struct dir_info *) _i;
	int tx_queue_not_empty = 0;
	u_char* buffer;
	//gpu
	pthread_t thread4gpu[8];
	//time
	struct timeval start;
	struct timeval end;
	unsigned long diff = 0;
	//acsm
	int nfound=0;

	int check = 0;
	int pos;
	unsigned char idx;
	unsigned char each_T1_char[sizeof(T1_char)];
	unsigned char each_T2_char[sizeof(T2_char)];
	unsigned char each_BT[btsize*sizeof(char)];
	
	memcpy(each_T1_char,T1_char,sizeof(T1_char));
	memcpy(each_T2_char,T2_char,sizeof(T2_char));
	memcpy(each_BT,BT,btsize*sizeof(char));

	if (i->bind_core >= 0)
	{
		bind2core(i->bind_core);
	}
  ////////////////////////////////////////
#if defined(_hpma)
	cout << "In _hpma" << endl;
#elif defined(_GPU)
	cout << "In _GPU" << endl;
//#elif defined(_CPU)
	//cout << "In _CPU" << endl;	
#endif
		int whoami = i->bind_core;
		//cout << "whoami: " << whoami << endl;
		int counta=0, countf=0, counts=0;
		int counterbuffer=0;
		int checkbyT1 = 0;
		u_char* temp;
		u_char* __restrict__ CPU_Central_memory_tail; 
		CPU_Central_memory_tail = CPU_Central_memory + (whoami*bytes);
		int countpat1=0,counterT1=0,counter3=0;
		unsigned char pak_pick1, pak_pick2,pak_pick3;
		int vt1_pos=0,count_t1_locat=0, win_no=0;
		int temp_test=0;
		int PidforT2=0;
		int checkBT=0;
		double AP = 0.0;
		bool CPUState = 1;
		while(!do_shutdown) 
		{
			if(pfring_zc_recv_pkt(i->inzq, &i->tmpbuff, wait_for_packet) > 0) 
			{

				if (unlikely(verbose)) 
				{
					char strbuf[4096];
					int strlen = sizeof(strbuf);
					int strused = snprintf(strbuf, strlen, "[%s -> %s]", i->in_dev, i->out_dev);
					pfring_print_pkt(&strbuf[strused], strlen - strused, pfring_zc_pkt_buff_data(i->tmpbuff, i->inzq), i->tmpbuff->len, i->tmpbuff->len);
					fputs(strbuf, stdout);
				}
				buffer = pfring_zc_pkt_buff_data(i->tmpbuff, i->inzq)+42;
				i->numPkts++;
				i->numBytes += i->tmpbuff->len + 24; /* 8 Preamble + 4 CRC + 12 IFG */
				  
				errno = 0;
				while (unlikely(pfring_zc_send_pkt(i->outzq, &i->tmpbuff, flush_packet) < 0 && errno != EMSGSIZE && !do_shutdown)) //send packet
				if (wait_for_packet)
				{					
					usleep(1);
				}
				
				tx_queue_not_empty = 1;
			}else {
				if (tx_queue_not_empty) 
				{
					pfring_zc_sync_queue(i->outzq, tx_only);
					tx_queue_not_empty = 0;
				}
				if (wait_for_packet) 
				{
					usleep(1);
				}
			}
			gettimeofday(&start,NULL); //666
//#if defined(_CPU) // pure CPU acsm
			//nfound+=acsmSearch(acsm, buffer, payloadlen, MatchFound, 0); //pure CPU

			// hpma prefilter start 
			//unique_lock<mutex> lk(lockurmother,defer_lock);
			bool checkifT1 = false;
			bool inT2 = false;
			if( CPUPrefilter[whoami] == true )
			{
				CPUState = 1;
				//unique_lock<mutex> lk(lockurmother);
				totalpacket[whoami]++;
				//lk.unlock();
				for(int i = 0 ; i < payloadlen-2 ; i=i+1 )
				{
					pak_pick1 = *(buffer+i);
					pak_pick2 = *(buffer+i+1);
					vt1_pos = (pak_pick1<<8) |pak_pick2;  //pak_pick1*256+pak_pick2
					if( CheckT1((int)vt1_pos) ) // Prefilter T1
					/*pos = (int)vt1_pos;
					idx = each_T1_char[pos >> 3]; // pos/8
					check = pos & 0x07;
					if( idx & ( 0x01 << (7-check) ) )*/
					{
						checkifT1 = true;
						counterT1++;
						pak_pick3 = *(buffer+i+2);
						
						checkBT = (int)each_BT[vt1_pos/64];
						//checkBT = (int)BT[vt1_pos/64];
						PidforT2 = checkBT + BitCount(each_T1_char, (vt1_pos & 0xfffffc0) ,vt1_pos);
						//PidforT2 = checkBT + BitCount(T1_char, (vt1_pos & 0xfffffc0) ,vt1_pos);
						
						if( CheckT2(PidforT2*256+(int)pak_pick3) )  // Prefilter T2
						/*pos = (PidforT2*256+(int)pak_pick3);
						idx = each_T2_char[pos >> 3]; // pos/8
						check = pos & 0x07;
						if( idx & (0x01 << (7-check) ) )*/
						{
							//CPUbyte[whoami]+=i;
							inT2 = true;
							counterT2[whoami]++;
					
							//no each buffer
							/*if(DB_Check == 1)
							{
								if(!isReady[1])
								{
									unique_lock<mutex> lk(lockurmother);
									while(!isReady[1])
									{
										cv_buffer2.wait(lk);
									}
									lk.unlock();
								}
									
								sem_wait(&os_sem);

								temp = Central_memory_tail;
								
								memcpy(temp,&CPUState,1);
								memcpy(temp+1,&whoami,1);
								memcpy(temp+2,buffer,payloadlen);

								Central_memory_tail = Central_memory_tail + buffershift;
								
								if(Central_memory_tail == second_buffer)
								{
									isReady[1] == false;
									Central_memory_tail = Central_memory;
									DB_Check = !DB_Check;
								}
								sem_post(&os_sem);

							}else if(DB_Check == 0)
							{
								if(!isReady[0])
								{
									unique_lock<mutex> lk(lockurmother);
									while(!isReady[0])
									{
										cv_buffer1.wait(lk);
									}
									lk.unlock();
								}

								sem_wait(&os_sem);

								temp = Central_memory_tail;
								
								memcpy(temp,&CPUState,1);
								memcpy(temp+1,&whoami,1);
								memcpy(temp+2,buffer,payloadlen);

								Central_memory_tail = Central_memory_tail + buffershift;
								
								if(Central_memory_tail == first_buffer)
								{
									isReady[0] == false;
									DB_Check = !DB_Check;
								}
								sem_post(&os_sem);

							}*/
															//


							if(isReady[0] == isReady[1] && isReady[1] == 0)
							{
								alldead++;
							}

							if(DB_Check == 1)
							{
								if(!isReady[1])
								{
									unique_lock<mutex> lk(lockurmother);
									while(!isReady[1])
									{
										cv_buffer2.wait(lk);
									}
									lk.unlock();
								}
								
								//temp = CPU_Central_memory_tail + (num_threads*bytes) + (CPU_Count[whoami+num_threads]*1472);
								temp = Buffer_location[CPU_Count[whoami+num_threads]];
								temp = temp + (whoami*bytes) + (num_threads*bytes);

								memcpy(temp,&CPUState,1);
								memcpy(temp+1,&whoami,1);
								memcpy(temp+2,buffer,payloadlen);

								CPU_Count[whoami+num_threads]++;

							}else if(DB_Check == 0)
							{
								if(!isReady[0])
								{
									unique_lock<mutex> lk(lockurmother);
									while(!isReady[0])
									{
										cv_buffer1.wait(lk);
									}
									lk.unlock();
									
								}
				
								//temp = CPU_Central_memory_tail + (CPU_Count[whoami]*1472);
								temp = Buffer_location[CPU_Count[whoami]];
								temp = temp + whoami*bytes;
			
								memcpy(temp,&CPUState,1);
								memcpy(temp+1,&whoami,1);
								memcpy(temp+2,buffer,payloadlen);
									
								CPU_Count[whoami]++;

							}
							
							unique_lock<mutex> lk(lockurmother);
							//unique_lock<mutex> lk(lockurmother,defer_lock);
						//if(lk.try_lock())
						//{
							DB_Count++;
							if(DB_Count >= buffer_size)
							{
								if(DB_Check==1)
								{
									isReady[1] = false;
									for(int i=0;i<num_threads;i++)
									{
										//CPU_Count[i] = 0;
									}
									
								}else if(DB_Check==0)
								{
									isReady[0] = false;
									for(int i=0;i<num_threads;i++)
									{
										//CPU_Count[i+num_threads] = 0;
									}
								}
								DB_Check = !DB_Check;
								DB_Count = 0;
							}
							justanumber[whoami]++;
							//totallock[whoami]++;
						/*}else{
							totalcantlock[whoami]++;
							lk.lock();
							DB_Count++;
							if(DB_Count >= buffer_size)
							{
								if(DB_Check==1)
								{
									isReady[1] = false;
									for(int i=0;i<num_threads;i++)
									{
										//CPU_Count[i] = 0;
									}
									
								}else if(DB_Check==0)
								{
									isReady[0] = false;
									for(int i=0;i<num_threads;i++)
									{
										//CPU_Count[i+num_threads] = 0;
									}
								}
								DB_Check = !DB_Check;
								DB_Count = 0;
							}
						}*/
							lk.unlock();
							
							break;
						}
					}
				}
				if(inT2 == false)
				{
					countpak[whoami]++;
					//CPUbyte[whoami]+=1458;
				}else if (inT2 == true)
				{
				
				}
			}
			else if ( CPUPrefilter[whoami] == false )
			{
				if(isReady[0] == isReady[1] && isReady[1] == 0)
				{
					alldead++;
				}
				CPUState = 0;
				if(DB_Check == 1)
				{
					if(!isReady[1])
					{
						unique_lock<mutex> lk(lockurmother);
						while(!isReady[1])
						{
							cv_buffer2.wait(lk);
						}
						lk.unlock();
					}

					//temp = CPU_Central_memory_tail + (num_threads*bytes) + (CPU_Count[whoami+num_threads]*1461);
					temp = Buffer_location[CPU_Count[whoami+num_threads]];
					temp = temp + (whoami*bytes) + (num_threads*bytes);

					memcpy(temp,&CPUState,1);
					memcpy(temp+1,&whoami,1);
					memcpy(temp+2,buffer,payloadlen);
						
					CPU_Count[whoami+num_threads]++;
					
				}else if(DB_Check == 0)
				{
					if(!isReady[0])
					{
						unique_lock<mutex> lk(lockurmother);
						while(!isReady[0])
						{
							cv_buffer1.wait(lk);
						}
						lk.unlock();
					}
					
					//temp = CPU_Central_memory_tail + (CPU_Count[whoami]*1461);
					temp = Buffer_location[CPU_Count[whoami]];
					temp = temp + whoami*bytes;

					memcpy(temp,&CPUState,1);
					memcpy(temp+1,&whoami,1);
					memcpy(temp+2,buffer,payloadlen);
						
					CPU_Count[whoami]++;
				}
				
				///
				unique_lock<mutex> lk(lockurmother);
				//unique_lock<mutex> lk(lockurmother,defer_lock);
			//if(lk.try_lock())
			//{
				DB_Count++;
				if(DB_Count >= buffer_size)
				{
					if(DB_Check==1)
					{
						isReady[1] = false;
						for(int i=0;i<num_threads;i++)
						{
							//CPU_Count[i] = 0;
						}
					}else if(DB_Check==0)
					{
						isReady[0] = false;
						for(int i=0;i<num_threads;i++)
						{
							//CPU_Count[i+num_threads] = 0;
						}
					}
					DB_Check = !DB_Check;
					DB_Count = 0;
				}
				justanumber[whoami]++;
				//totallock[whoami]++;
			/*}else{
				
				totalcantlock[whoami]++;
				lk.lock();
				DB_Count++;
				if(DB_Count >= buffer_size)
				{
					if(DB_Check==1)
					{
						isReady[1] = false;
						for(int i=0;i<num_threads;i++)
						{
							//CPU_Count[i] = 0;
						}
					}else if(DB_Check==0)
					{
						isReady[0] = false;
						for(int i=0;i<num_threads;i++)
						{
							//CPU_Count[i+num_threads] = 0;
						}
					}
					DB_Check = !DB_Check;
					DB_Count = 0;
				}
			}*/
				lk.unlock();
				
				//justanumber[whoami]++; //debug
			}

			if(checkifT1 == true)
			{
				checkbyT1++;
			}
			/*sem_wait(&os_sem);
			pthread_join(thread4gpu[0], NULL);
			pthread_join(thread4gpu[1], NULL);
			sem_post(&os_sem);*/
			
			gettimeofday(&end,NULL);
			diff += 1000000*(end.tv_sec-start.tv_sec)+end.tv_usec-start.tv_usec;
		}
		
		if (!flush_packet) //after exit
		{
			pfring_zc_sync_queue(i->outzq, tx_only);
		}
		pfring_zc_sync_queue(i->inzq, rx_only);


		int CNOPTG = CountNumofPacketToGpuFun1+CountNumofPacketToGpuFun2 ;
		//sem_wait(&os_sem);
		printf("totalpacket= %d, countT1= %d, checkbyT1= %d, countT2= %d, countGPU= %d, GPUtablehits= %d, Pak2GPU= %d+%d=%d, pre_time= %d, GPUpre_time= %d, cudathread_time= %d\n",totalpacket, counterT1,checkbyT1,counterT2,kernel_sum, kernel_tablehits, CountNumofPacketToGpuFun1, CountNumofPacketToGpuFun2,intoGPUtime, diff, diffGPU, diffCUDA);
		//sem_post(&os_sem);
  
  return NULL;
}

/* *************************************** */

int init_direction(struct dir_info *i, char *in_dev, char *out_dev) {
  
  cout<<" in: "<<in_dev<<" out: "<<out_dev<<endl;

  i->in_dev = in_dev;
  i->out_dev = out_dev;

  i->tmpbuff = pfring_zc_get_packet_handle(zc);

  if (i->tmpbuff == NULL) {
    fprintf(stderr, "pfring_zc_get_packet_handle error\n");
    return -1;
  }

  i->inzq = pfring_zc_open_device(zc, in_dev, rx_only, 0);

  if(i->inzq == NULL) {
    fprintf(stderr, "pfring_zc_open_device error [%s] Please check that %s is up and not already used\n",
     	    strerror(errno), in_dev);
    return -1;
  }

  i->outzq = pfring_zc_open_device(zc, out_dev, tx_only, 0);

  if(i->outzq == NULL) {
    fprintf(stderr, "pfring_zc_open_device error [%s] Please check that %s is up and not already used\n",
	    strerror(errno), out_dev);
    return -1;
  }

  return 0;
}

/* *************************************** */

int main(int argc, char* argv[]) {
	pthread_t persistentyo;
  char *device1 = NULL, *device2 = NULL;
  char *device1_rss[num_threads], *device2_rss[num_threads];
  char *device1_rss_NIC[num_threads], *device2_rss_NIC[num_threads];
  char *bind_mask = NULL, c;
  long i, j, k, m, n;
  stringstream ss;
  string idder;
  char *device_at     = "@";
  char *device_10_in  = "zc:ens10f1";
  char *device_10_out = "zc:ens10f0";

  
  //outputyo.open("outputyo",ios::out|ios::trunc);
  outputyo.open("outputyo",ios::out);
  outputyoGPU.open("outputyoGPU",ios::out);
  //int cluster_id = DEFAULT_CLUSTER_ID+9; 
  u_int numCPU = sysconf( _SC_NPROCESSORS_ONLN );
  //pattern
  ifstream inFile;
  string line;
  //mwm
  int nocase=1, npats=0;

  cout << "numCPU: " << numCPU << endl;

  //dir[0].bind_core = dir[1].bind_core = -1;
    for(int i=0;i<32;i++)
    {
    	dir[i].bind_core = -1;
    }

  startTime.tv_sec = 0;

	while((c = getopt(argc,argv,"abc:e:g:hi:j:n:N:o:s:t:r:fv")) != '?') {
		if((c == 255) || (c == -1)) break;

		switch(c) {
			case 'h':
			printHelp();
			break;
		case 'a':
			wait_for_packet = 0;
			break;
		case 'f':
			flush_packet = 1;
			break;
		case 'v':
			verbose = 1;
			break;
		case 'b':
			bidirectional = 1;
			break;
		case 'c':
			cluster_id = atoi(optarg);
			break;
		case 'i':
			device1 = strdup(optarg);
			break;
		case 'o':
			device2 = strdup(optarg);
			break;
		case 'g':
			bind_mask = strdup(optarg);
			break;
		case 'e':
			match_mode = atoi(optarg);
			break;
		case 'n':
			num_threads = atoi(optarg);
			break;
		case 'N':
			two_NIC = atoi(optarg);
			break;
		case 's':
			blocksNumper = atoi(optarg);
			printf("\n blocksNumper =%d  ",blocksNumper);
			break;
		case 't':
			threadsperBlock = atoi(optarg);
			printf("\n threadsperBlock = %d\n",threadsperBlock);
			break;
		case 'j':
			rec_pkt_size = atoi(optarg);
			break;
		case 'r':
			buffer_times = atof(optarg);
			break;
    }
  }
  
  if (device1 == NULL) printHelp();
  if (device2 == NULL) printHelp();
  if (cluster_id < 0)  printHelp();

  /*if(bind_mask != NULL) {
    char *id;
    if ((id = strtok(bind_mask, ":")) != NULL)
      dir[0].bind_core = atoi(id) % numCPU;
    if ((id = strtok(NULL, ":")) != NULL)
      dir[1].bind_core = atoi(id) % numCPU;
  }*/
  if(bind_mask != NULL)
  {
    char *id = strtok(bind_mask, ":");
    int idx = 0;
	cout<<"id: ";
    while(id != NULL)
    {
      dir[idx++].bind_core = atoi(id) % numCPU;
	  cout << atoi(id) <<" ";
      if(idx >= num_threads) break;
      id = strtok(NULL, ":");
    }
	cout<<endl;
  }
  	CPU_Count = new int[num_threads*2];
	if(CPU_Count == NULL)
	{
		cout << "Error memory set for CPU_Count" << endl;
	}
	for(int i=0;i<(num_threads*2);i++)
	{
		CPU_Count[i] = 0;
	}
	///// 12/06 for match_mode 4 GPU-AC //1227 test time of bytes //20200820 for corexbuffer bbb
	buffer_size = blocksNumper*threadsperBlock*buffer_times;
		cout<<"buffer_size = " << buffer_size << endl;
	//bytes = sizeof(u_char)*buffer_size*(payloadlen+3);
	bytes = sizeof(u_char)*buffer_size*buffershift;
		cout<<"bytes = "<<bytes<<endl;
	
	nfound_GPU1=(int*)malloc(sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
	nfound_GPU2=(int*)malloc(sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
	//whoami_GPU malloc
	whoami_GPU =(int*)malloc(sizeof(int)*blocksNumper*threadsperBlock*buffer_times); //

	Tablehits1=(bool*)malloc(sizeof(bool)*blocksNumper*threadsperBlock*buffer_times);
	Tablehits2=(bool*)malloc(sizeof(bool)*blocksNumper*threadsperBlock*buffer_times);
	cudaMalloc((void**)&d_nfound_GPU1,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
	cudaMalloc((void**)&d_nfound_GPU2,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
	//d_whoami_GPU malloc
	cudaMalloc((void**)&d_whoami_GPU ,sizeof(int)*blocksNumper*threadsperBlock*buffer_times); //

	cudaMalloc((void**)&d_Tablehits1,sizeof(bool)*blocksNumper*threadsperBlock*buffer_times);
	cudaMalloc((void**)&d_Tablehits2,sizeof(bool)*blocksNumper*threadsperBlock*buffer_times);
	cudaMalloc((void**)&d_T1_char,65536/8);
	cudaMalloc((void**)&d_T2_char,53760/8);
	cudaMalloc((void**)&d_BT_char,1024);
	memset(nfound_GPU1,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
	memset(nfound_GPU2,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
	//whoami_GPU memset
	memset(whoami_GPU ,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times); //
	memset(Tablehits1,0,sizeof(bool)*blocksNumper*threadsperBlock*buffer_times);

	memset(Tablehits2,0,sizeof(bool)*blocksNumper*threadsperBlock*buffer_times);
	cudaMemset(d_nfound_GPU1,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
	cudaMemset(d_nfound_GPU2,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times);
	//d_whoami_GPU memset
	cudaMemset(d_whoami_GPU ,0,sizeof(int)*blocksNumper*threadsperBlock*buffer_times); //

	for(int i=0;i<8;i++) //bitmasks 128, 64, 32, 16, 8, 4, 2, 1
	{
		bitmasks[i] = pow(2,7-i);
		//		printf("%d :: bitmask = %u \n", i ,bitmasks[i]);
	}
	
	//*nfound_GPU=0;
	sem_init(&os_sem,0,1);
	int* partcial_sum;
	//比對所需之宣告
	cudaMallocHost((void**)&Central_memory,bytes*3);//3

	cudaMallocHost((void**)&CPU_Central_memory,num_threads*bytes*2+31);
	//printf("Before CPU_Central_memory: %p, %d\n", CPU_Central_memory,intptr_t(CPU_Central_memory));
	CPU_Central_memory = CPU_Central_memory + (32-(intptr_t(CPU_Central_memory)%32));
	//printf("After CPU_Central_memory: %p, %d\n", CPU_Central_memory,intptr_t(CPU_Central_memory));

	//CPU_Central_memory = (u_char*)malloc(num_threads*bytes*2);

	cudaMalloc((void**)&d_Central_memory,2*bytes); //1119 
	memset(Central_memory,0,bytes*3);
	memset(CPU_Central_memory,0,num_threads*bytes*2);
	
	cudaMemset(d_Central_memory,0,2*bytes);
	
	Buffer_location = new u_char*[buffer_size]; // recording each startIdx in buffer
	for(int i=0;i<buffer_size;i++)
	{
		Buffer_location[i] = &*(CPU_Central_memory+(i*buffershift));
	}

	Central_memory_tail = Central_memory;
	first_buffer = Central_memory + bytes;
	second_buffer = Central_memory + 2*bytes;
	
	///////////////////////////////////  T1
	FILE *fptr;
	fptr = fopen( T1_FILE_PATH ,"r");	
	t1size = GetFileLength(fptr);
  

	printf("T1 size:%d \n", t1size);
	T1 = (unsigned char*)malloc(t1size*sizeof(char));
	if( T1 == NULL )
	{
		fprintf(stderr, "記憶體不足\n");
		exit(1);
	}//fgets( T1 , t1size , fptr );
	//write into mem
	for( i = 0 ; i < t1size ; i++ )
	{
		T1[i] = fgetc(fptr);
		
	}

	///////////////////////////////////// BT
	fptr = fopen( BT_FILE_PATH ,"r");
  
	btsize = GetFileLength(fptr);
	BT = (unsigned char*)malloc(btsize*sizeof(char));
	if( BT == NULL )
	{
		fprintf(stderr, "記憶體不足\n");
		exit(1);
	}
	for( i = 0 ; i < btsize ; i++ )
	{
		BT[i] = fgetc(fptr);
	}
	cout << "btsize: " << btsize << endl;

	fptr = fopen( T2_FILE_PATH ,"r");
	t2size = GetFileLength(fptr);
	T2 = (unsigned char*)malloc(t2size*sizeof(char));
	if( T2 == NULL )
	{
		fprintf(stderr, "記憶體不足\n");
		exit(1);
	}
	for( i = 0 ; i < t2size ; i++ )
	{
		T2[i] = fgetc(fptr);
	}
  
  
	fclose(fptr);
	win_size = 65536/btsize;
	printf("win_size = %d   btsize = %d  t2size = %d t1size = %d \n",win_size, btsize,t2size,t1size);
	
	///////////////////////////////////  T1_bool
	T1_bool =(bool*)malloc(256*256*sizeof(bool));
	for(int c_1 = 0; c_1< 255; c_1++)
	{
		for( int c_2 = 0 ; c_2 < 255;  c_2++)
		{
			int charIndex = c_1*255+c_2;
			T1_bool[charIndex]= T1[ charIndex*4/8] & (bitmasks[(charIndex*4)%8+3]);
		}
	}
	
	/////////////////////////////////// T1b_bool
	
	fptr = fopen( T1b_FILE_PATH ,"r");
	t1bsize = GetFileLength(fptr);
	
	cout << "t1bsize: " << t1bsize << endl;
	
	T1b = (unsigned char*)malloc(t1bsize*sizeof(u_char));
	if( T1b == NULL )
	{
		fprintf(stderr, "記憶體不足\n");
		exit(1);
	}
	for (int i=0;i<t1bsize;i++) //655360 = 256*256
	{
		T1b[i] = fgetc(fptr);
		//ss << T2b[i];
		//ss >> boolalpha  >> T2_bool[i];
		T1b_bool[i] = T1b[i]&1;
	}
	
	fclose(fptr);

	/////////20190605 for T1_char

	fptr = fopen( T1c_FILE_PATH , "r");
	t1csize = GetFileLength(fptr);

	cout << "t1csize: " << t1csize << endl;
	T1c = (unsigned char*)malloc(t1csize*sizeof(u_char));
	if( T1c == NULL )
	{
		fprintf(stderr, "記憶體不足\n");
		exit(1);
	}
	for(int i=0;i<t1csize;i++) //8192
	{
		T1_char[i] = fgetc(fptr); // T1T1

	}
	
	for(int i=0;i<255;i++)
	{
		if( *(T1b_bool+i) != CheckT1(i) )
		{
			cout << "Different!!! at: " << i  << endl;
		}
		if( ((T1[i]>>4)&1) != CheckT1(i*2))
		{
			cout << "T1 is Different at: " << i*2 << endl;
		}
		if(((T1[ i*4/8])&(bitmasks[(i*4)%8+3])) != CheckT1(i) && ((T1[ i*4/8])&(bitmasks[(i*4)%8+3])) != 16 )
		{
			cout << "T1 is Different at: " << i << endl;
		}
	}
	cout << "T1_table_sc: " << endl;
	for(int i=0;i<10;i++)
	{
		cout << ((T1[i]>>4)&1) << ", " << (T1[i]&1) << ", " ;
	}
	cout << endl;

	fclose(fptr);

	/////////20190718 for T2_char

	fptr = fopen( T2c_FILE_PATH , "r");
	t2csize = GetFileLength(fptr);

	cout << "t2csize: " << t2csize << endl;
	T2c = (unsigned char*) malloc(t2csize*sizeof(u_char));
	if( T2c == NULL )
	{
		fprintf(stderr, "記憶體不足\n");
		exit(1);
	}
	for(int i=0;i<t2csize;i++) //6720
	{
		T2_char[i] = fgetc(fptr); // T2T2
	}
	cout << "Test T2_char: " << endl;
	for(int j=0;j<10;j++)
	{
		for(int i=0;i<8;i++)
		{
			cout <<  ((T2_char[j]>>(7-i))&1);
		}
	}
	cout << endl;

	fclose(fptr);


	
	/////////20190315 for popcount
	unsigned long long int numof64;
	numof64 = BitArrayToInt(T1_bool,11840,11891);
	cout << "numof64: " << numof64 << endl;
	cout << "popcount_3: " << popcount_3(numof64) << endl;
	
	fptr = fopen( T2b_FILE_PATH ,"r");
	t2bsize = GetFileLength(fptr);

	cout << "t2bsize: " << t2bsize << endl;
	
	//stringstream T2ss;
	T2b = (unsigned char*)malloc(t2bsize*sizeof(u_char));
	if( T2b == NULL )
	{
		fprintf(stderr, "記憶體不足\n");
		exit(1);
	}
	for (int i=0;i<t2bsize;i++)
	{
		T2b[i] = fgetc(fptr);
		//ss << T2b[i];
		//ss >> boolalpha  >> T2_bool[i];
		T2_bool[i] = T2b[i]&1;
	}
	for(int i=0;i<255;i++)
	{
		if(T2_bool[i]!=CheckT2(i))
		{
			cout << "T2 Different!!! at: " << i << endl;
		}
	}

  /////////////////////////////////////  build fullTable
	int charIndex = 0;
	int charIndex_winsize = 0;
	//int local_sum =0;
	int t2Loc = 0;
	int counterTest =0 ;
	//r = udaMallocManaged(&(fullTable),(65536*128));//2^16 *  2^7
	//r = cudaMallocManaged(&(d_fullTable),sizeof(u_char)*65536*32);
	
	fullTable = (u_char*)malloc(65536*32);
	for(int c_1 = 0; c_1< 256; c_1++){
		for( int c_2 = 0 ; c_2 < 256;  c_2++){
			charIndex = c_1*256+c_2;
			charIndex_winsize=	charIndex-(charIndex%win_size); //貌似沒用
			//local_sum = 0;
			
			if(T1[ charIndex*4/8] & (bitmasks[(charIndex*4)%8+3]) )
			{
				for(int i = 0 ; i <32; i++)
				{	
						fullTable[charIndex*32+i]=T2[t2Loc*32+i];
						//fullTable[charIndex*32+i]=T2_char[t2Loc*32+i];
						counterTest++;
				}
				T2ptr[charIndex] = &T2[t2Loc*32];	
				t2Loc++;
				//t2Loc = BT[charIndex/win_size]+local_sum;
				//T2_bool[charIndex] = &T2b[t2Loc*32];
			}else{
				for(int i = 0 ; i <32; i++)
				{	
					fullTable[charIndex*32+i]=0;
				}	
				T2ptr[charIndex] =NULL;
			}		
		}
	}
	
	for(int i = 0 ; i<65536 ; i++)
	{
		if(T2ptr[i])
		{
			t2Loc--;
		}			
	}
	
	cout<<"counterTest  "<<counterTest<<endl<<"t2Loc  "<<t2Loc<<endl;
	
	cudaMalloc((void**)&d_fullTable,sizeof(u_char)*65536*32);
	
	cudaMemcpy(d_fullTable,fullTable,65536*32,cudaMemcpyHostToDevice);
	
	cudaBindTexture(0,texFulltable,d_fullTable ,65536*32);
	cudaBindTexture(NULL,texacsm,acsm,sizeof(acsm));
	//free(fullTable);
  
  //////////////////////////////////////////////////////////////////////// build acsm(AC)
  //acsm pattern
  vector<string> patNumstr;
  vector<string> patTERN;
  cout<<"Start to read Pattern file!"<<endl;
  
  //load pattern data
  inFile.open(PATTERN_FILE_PATH);
  while(getline(inFile,line))
  {
  	patTERN.push_back(line);
  }
  inFile.close();
  inFile.clear();
  cout<<"End read Pattern file!"<<endl;
  //end!

  //load pattern num data
  inFile.open(PAT_FILE_PATH);
  while(getline(inFile,line))
  {
  	patNumstr.push_back(line);
  }
  inFile.close();
  inFile.clear();
  cout<<"Done for load pattern!"<<endl;

  //stable_sort(patNumstr.begin(),patNumstr.end(), sortRule);

  vector<int> patternNum[patNumstr.size()];
  for(int i=0; i<patNumstr.size();i++)
  {
  	for(int j=0;j<patNumstr[i].size();j=j+3)
	{
		patternNum[i].push_back(StrToInt(patNumstr[i].substr(j,3)));
	}
  }
  //end!
  
  //snort mwm
  ps = mwmNew();
  //snort ac
#define acsm_print printf ("MAX_Memory: %d bytes, acsmMacStates: %d, acsmNumStates: %d  mem: acsm: %d maxstate: %d numstate: %d pattern %d statetalbe %d\n", max_memory, acsm->acsmMaxStates, acsm->acsmNumStates, &acsm, &(acsm->acsmMaxStates), &(acsm->acsmNumStates), &(acsm->acsmPatterns), &(acsm-<acsmStateTable));

  //acsmNew()
  printf("cudaMallocManaged\n");
  r = cudaMallocManaged(&(acsm), sizeof(ACSM_STRUCT));
  //err acsm_print printf("acsm NER\n");
  init_xlatcase();
  
  memset(acsm, 0, sizeof(ACSM_STRUCT));
  //end!

  //add pattern
  cout<<"add pattern"<<endl;
  for(int x=0; x<patNumstr.size();x++)
  {
  	char* s_mwm = (char*) malloc (sizeof(char)*(patternNum[x].size()+1));

	for(int y=0; y<patternNum[x].size();y++)
	{
		s_mwm[y] = (unsigned char)patternNum[x][y];
	}

	mwmAddPatternEx(ps, (unsigned char*)s_mwm, patternNum[x].size(), nocase, 0, 0, (void*)npats, 3000);
	acsmAddPattern(acsm, (unsigned char*)s_mwm, patternNum[x].size(), nocase, 0, 0, s_mwm, x);

	#ifdef _test
	patArray[npats] = s_mwm;
	#endif
	npats++;
  }
  mwmPrepPatterns(ps);
  
  cout<<"patNumstr.size() :"<<patNumstr.size()<<endl;

  //acsmCompile()
  cout<<"acsmCompile"<<endl;
  acsmCompile(acsm);

  ///////////////////////////////////////////////////////////////// pfring_zc info
  zc = pfring_zc_create_cluster(
    cluster_id, 
    max_packet_len(device1), 
    0, 
    ((2 * MAX_CARD_SLOTS) + 1) * (1 + bidirectional),
    NULL, //pfring_zc_numa_get_cpu_node(dir[0].bind_core)
    NULL /* auto hugetlb mountpoint */ 
  );

  if(zc == NULL) {
    fprintf(stderr, "pfring_zc_create_cluster error [%s] Please check your hugetlb configuration\n",
	    strerror(errno));
    return -1;
  }
	
	if(two_NIC == 0) //only use one NIC and one thread
	{
		for(int i = 0; i < num_threads; i++)
		{
			ss << i;
			ss >> idder;
			string temp1 = string(device1) + string(device_at) + idder; //ens4f1 + @ + i
			string temp2 = string(device2) + string(device_at) + idder; //ens4f0 + @ + i
			device1_rss[i]=strdup(temp1.c_str());
			device2_rss[i]=strdup(temp2.c_str());
			/*if (init_direction(&dir[0], device1, device2) < 0) 
				return -1;*/
			if (init_direction(&dir[i], device1_rss[i], device2_rss[i]) < 0)
			{
				return -1;
			}
			ss.clear();	
		}
	}else if(two_NIC > 0) //use both two NIC and 2*threads
	{
		for(int i = 0; i < num_threads/2; i++)
		{
			cout<<"i: "<<i<<endl;
			ss << i;
			ss >> idder;
			string temp1 = string(device1) + string(device_at) + idder;       //zc:ens4f1 + @ + i
			string temp2 = string(device2) + string(device_at) + idder;       //zc:ens4f0 + @ + i
			string temp3 = string(device_10_in) + string(device_at) + idder;  //zc:ens10f1 + @ + i
			string temp4 = string(device_10_out) + string(device_at) + idder; //zc:ens10f0 + @ + i
			
			device1_rss[i] = strdup(temp1.c_str());        //zc:ens4f1@i
			device2_rss[i] = strdup(temp2.c_str());        //zc:ens4f0@i
			device1_rss_NIC[i] = strdup(temp3.c_str());  //zc:ens10f1@i
			device2_rss_NIC[i] = strdup(temp4.c_str());  //zc:ens10f0@i
			/*if (init_direction(&dir[0], device1, device2) < 0) 
				return -1;*/
			if (init_direction(&dir[2*i], device1_rss[i], device2_rss[i]) < 0)
			{
				return -1;
			}
			if (init_direction(&dir[(2*i)+1], device1_rss_NIC[i], device2_rss_NIC[i]) < 0)
			{
				return -1;
			}
			ss.clear();	
		}
	}
  
	if (bidirectional)
	{
		if (init_direction(&dir[1], device2, device1) < 0) 
		{
			return -1;
		}
	}
	
  	//signal(SIGINT, sigproc);
	//signal(SIGTERM, sigproc);
	//signal(SIGINT, sigproc);

	pthread_create(&persistentyo, NULL, persistentkernel, NULL);
  	
	cout << "The ZX cluster [id: " << cluster_id << "][num consumer threads: " << num_threads << "] is running..." <<endl;
	for(int i = 0; i < num_threads; i++)
	{
		if (two_NIC==0)
		{
			cout<<"Thread"<<i<<": ";
			cout<<"In_device: "<<device1<<"@"<<i<<"  ;  Out_device: "<<device2<<"@"<<i<<endl;
		}else if (two_NIC > 0)
		{
			cout<<"Thread"<<i<<": ";
			cout<<"In_device: "<<device1<<"@"<<i<<", "<<device_10_in<<"@"<<i<<" ; ";
			cout<<"Out_device: "<<device2<<"@"<<i<<", "<<device_10_out<<"@"<<i<<endl;
		}
		/*pthread_create(&dir[0].thread, NULL, packet_consumer_thread, (void *) &dir[0]);
		if (bidirectional) pthread_create(&dir[1].thread, NULL, packet_consumer_thread, (void *) &dir[1]);*/
		pthread_create(&dir[i].thread, NULL, packet_consumer_thread, (void *) &dir[i]);
	}
	
	//output+again
    	signal(SIGINT,  sigproc);
	signal(SIGTERM, sigproc);
	signal(SIGINT,  sigproc);

  if (!verbose) while (!do_shutdown) {
    //sleep(ALARM_SLEEP);
	  usleep(countrate*1000000); //10000=1s
	  gettimeofday(&startREAL,NULL);
    print_stats();
    	  gettimeofday(&endREAL,NULL);
	  diffREAL += 1000000*(endREAL.tv_sec-startREAL.tv_sec)+endREAL.tv_usec-startREAL.tv_usec;
	  cout << "print_stats time: " << diffREAL << endl;
	  diffREAL = 0;
	  
  }
  //no again
  //signal(SIGINT, sigproc);
	
	for(int i = 0; i < num_threads; i++)
	{
		/*pthread_join(dir[0].thread, NULL);
		if (bidirectional) pthread_join(dir[1].thread, NULL);*/
		pthread_join(dir[i].thread, NULL);
	}
	cout<<"hello?"<<endl;
	outputyo.close();
	outputyoGPU.close();

  sleep(1);

  pfring_zc_destroy_cluster(zc);
	sem_destroy(&os_sem);
  return 0;
}

