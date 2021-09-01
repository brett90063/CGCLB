#
# PF_RING
#
PFRINGDIR  = ../lib
LIBPFRING  = ${PFRINGDIR}/libpfring.a

#
# PF_RING aware libpcap
#
PCAPDIR    = ../libpcap
LIBPCAP    = ${PCAPDIR}/libpcap.a

#
# Search directories
#
PFRING_KERNEL=../../kernel
INCLUDE    = -I${PFRINGDIR} -I${PFRING_KERNEL} -I${PCAPDIR} `../lib/pfring_config --include`

#
# User and System libraries
#
LIBS       = ${LIBPFRING} `../lib/pfring_config --libs` ../libpcap/libpcap.a `../libpcap/pcap-config --additional-libs --static` -lpthread -lrt -ldl -lnuma

#
# C compiler and flags
#
CC         = ${CROSS_COMPILE}nvcc
CFLAGS     = -O2 -DHAVE_PF_RING -w  ${INCLUDE} -D HAVE_PF_RING_FT -arch=sm_61 -ccbin /usr/bin/g++-7 -Xcompiler -mavx2

#%.o: %.cu zutils.c
#	${CC}  ${CFLAGS} -c $< -o $@

#
# Main targets
#
PFPROGS   = 

ifneq (-D HAVE_PF_RING_ZC,)
	PFPROGS += zbounce
endif

TARGETS   =  ${PFPROGS}

#all: ${TARGETS}
#all: zbounce zbounce_hpma zbounce_GPU
all: zbounce_hpma.o zbounce_GPU.o

#zbounce: zbounce.o ${LIBPFRING}
#zbounce: zbounce.cu ${LIBPFRING}
#	${CC} ${CFLAGS} -D_hpma ${LIBS} -o zbounce_hpma zbounce.cu
zbounce_hpma.o: zbounce.cu zutils.c
	${CC} ${CFLAGS} -D_hpma ${LIBS} -o zbounce_hpma zbounce.cu 
zbounce_GPU.o: zbounce.cu zutils.c
	${CC} ${CFLAGS} -D_GPU ${LIBS} -o zbounce_GPU zbounce.cu

#-L /usr/local/cuda/lib64 -lcudart
install:
	mkdir -p $(DESTDIR)/usr/bin
	cp $(TARGETS) $(DESTDIR)/usr/bin/

clean:
	@rm -f ${TARGETS} *.o *~ config.*
