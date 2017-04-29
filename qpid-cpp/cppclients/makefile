
SLASH = /
REMOVE = -rm

#----------------------- Compiler Options ---------------------

COMPILER = g++

DEBUG =

#DEBUG = -DDEBUG
#DEBUG = -g

PROFILE =

#PROFILE = -pg


CFLAGS = -O6 -march=native -pthread\
         -Wall -posix $(DEBUG) $(PROFILE)

CDEFINES =  -D_POSIX_C_SOURCE=199506L\
            -D_XOPEN_SOURCE\
            -D_XOPEN_SOURCE_EXTENDED\
            -D_REENTRANT\
            -D_THREAD_SAFE

# -------------------------------------------------------------


CINCLUDES = \
	-Iinclude\

LIBS = \
	-Llib\

SRCFILES = \
	\


CPPOBJFILES = $(SRCFILES:.cpp=.o)
OBJFILES = $(CPPOBJFILES:.c=.o)

all : ItemProducer ItemConsumer

ItemProducer : ItemProducer.o
	$(COMPILER) $(CFLAGS) $(CDEFINES) \
	$(OBJFILES) ItemProducer.o $(LIBS) -lqpidinit -lqpidmessaging -ldl -luuid -lsasl2 -lnss3 -lnspr4 -lplc4 -lssl3 -o $@

ItemProducer.o : ItemProducer.cpp
	$(COMPILER) $(CFLAGS) $(CDEFINES) $(CINCLUDES) -c $?

ItemConsumer : ItemConsumer.o
	$(COMPILER) $(CFLAGS) $(CDEFINES) \
	$(OBJFILES) ItemConsumer.o $(LIBS) -lqpidinit -lqpidmessaging -ldl -luuid -lsasl2 -lnss3 -lnspr4 -lplc4 -lssl3 -o $@

ItemConsumer.o : ItemConsumer.cpp
	$(COMPILER) $(CFLAGS) $(CDEFINES) $(CINCLUDES) -c $?


# Makes all of the .cpp & .c specified in the SRCFILES macro

.objects : $(SRCFILES)
	$(COMPILER) $(CFLAGS) $(CDEFINES) $(CINCLUDES) -c $?
	echo touched > .objects

clean :
	$(REMOVE) *~
	$(REMOVE) *.~*
	$(REMOVE) *.o
	$(REMOVE) .objects
	$(REMOVE) ItemProducer
	$(REMOVE) ItemConsumer

