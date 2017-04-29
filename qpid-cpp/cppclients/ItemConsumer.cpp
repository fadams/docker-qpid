#include <qpid/messaging/Address.h>
#include <qpid/messaging/Connection.h>
#include <qpid/messaging/Message.h>
#include <qpid/messaging/Receiver.h>
#include <qpid/messaging/Session.h>
#include <qpid/types/Variant.h>

#include <sys/time.h> // For gettimeofday()
#include <iostream>

using namespace std;
using namespace qpid::messaging;
using namespace qpid::types;

unsigned long currentTimeMillis() {
	struct timeval curTime;
	gettimeofday(&curTime, NULL);
	return (curTime.tv_usec + curTime.tv_sec * 1000000ul)/1000;
}

int kbhit(void)
{
	struct timeval tv;  fd_set
	read_fd;  /* Do not wait at all, not even a microsecond */
	tv.tv_sec=0;
	tv.tv_usec=0;  /* Must be done first to initialize read_fd */
	FD_ZERO(&read_fd);  /* Makes select() ask if input is ready: 0 is the file descriptor for stdin      */
	FD_SET(0,&read_fd);  /* The first parameter is the number of the largest file descriptor to check + 1. */
    if (select(1, &read_fd, NULL, /*No writes*/ NULL, /*No exceptions*/&tv) == -1) return 0; /* An error occured */

	/* read_fd now holds a bit map of files that are readable. We test the entry for the standard input (file 0). */
	if (FD_ISSET(0,&read_fd))    /* Character pending on stdin */
		return 1;  /* no characters were pending */
	return 0;
} 

/*
	There is a bug in the Qpid C++ AddressParser code up to at least version 0.12
    whereby strings values get encoded as raw binary values as opposed to UTF8.
    In many circumstances this doesn't cause significant problems, however for
    the case of bindings to the headers exchange it has the potential to create
    a serious interoperability problem as Java producers in particular will
    certainly set header strings as UTF8 Java Strings.

	These methods "repair" an Address by re-encoding x-bindings argument values
    as UTF8 strings so that they work in an interoperable way with the Headers
    exchange. Note well the use of references as we're changing the underlying
    Address passed to the method.
*/


/*
	This method looks for the "x-bindings" Map within a "node" or "link" block
    and if one is found it then iterates through the bindings. For each binding
    that is found the "arguments" Map is looked up and if an "arguments" Map is
    found the method iterates though each argument explicitly setting the encoding
	of VAR_STRING valued arguments to utf8.
*/
void utf8EncodeBlock(Variant::Map& block) {
	Variant::Map::iterator i = block.find("x-bindings");
	if (i != block.end()) {
		Variant::List& bindings = i->second.asList();
		for (Variant::List::iterator li = bindings.begin(); li != bindings.end(); li++) {
			Variant::Map& binding = li->asMap();
			i = binding.find("arguments");
			if (i != binding.end()) {
				Variant::Map& arguments = i->second.asMap();
				for (i = arguments.begin(); i != arguments.end(); i++) {
					if (i->second.getType() == VAR_STRING) {
						i->second.setEncoding("utf8");
					}
				}
			}
		}
	}
}

/*
	This method extracts the "node" and "link" Maps from the options part of the
    Address and passes references to them to the utf8EncodeBlock method in order
    to repair the contents of the block.
*/
Address& utf8EncodeAddress(Address& addr) {
	Variant::Map& options = addr.getOptions();
	Variant::Map::iterator i = options.find("node");
	if (i != options.end()) {
		utf8EncodeBlock(i->second.asMap());
	}

	i = options.find("link");
	if (i != options.end()) {
		utf8EncodeBlock(i->second.asMap());
	}
	return addr;
}



int main(int argc, char** argv) {
    string broker = "localhost:5672";
    string connectionOptions = "{reconnect: true}";

    string address = "testqueue; {create: receiver, node: {x-declare: {arguments: {'qpid.policy_type': ring, 'qpid.max_size': 500000000}}, x-bindings: [{exchange: 'amq.match', queue: 'testqueue', key: 'data1', arguments: {x-match: all, data-service: amqp-delivery, item-owner: fadams}}]}}";

	Address addr(address);
	addr = utf8EncodeAddress(addr);
	
	int count = 0;
    
    Connection connection(broker, connectionOptions);
    try {
        connection.open();
        Session session = connection.createSession();
        Receiver receiver = session.createReceiver(addr);
		receiver.setCapacity(100); // Enable receiver prefetch

		//unsigned long startTime = currentTimeMillis();
		while (true) {
			Message message;// receiver.fetch();
			if (receiver.fetch(message, Duration::SECOND * 1)) {
				//const char* buffer = message.getContentPtr();
				cout << "message count = " << count << ", length = " << message.getContentSize() << endl;

				if ((count % 100) == 99) {
					session.acknowledge();
					//cout << "Committed message #" << count << endl;
				}

				count++;
			}

			if (kbhit()) break;
		}
		
		session.acknowledge();
		//unsigned long finishTime = currentTimeMillis();

		//cout << "Elapsed time = " << (finishTime - startTime) << ", messages/second = " << NUMBER_OF_ITERATIONS*1000.0f/(finishTime - startTime) << endl;
    
        connection.close();
        return 0;
    } catch(const exception& error) {
        cerr << "ItemConsumer Exception: " << error.what() << endl;
        connection.close();
        return 1;   
    }
}

