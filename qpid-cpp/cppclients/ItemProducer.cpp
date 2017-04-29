#include <qpid/messaging/Connection.h>
#include <qpid/messaging/Message.h>
#include <qpid/messaging/Sender.h>
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

inline Variant utf8(const char* s) {
	Variant utf8Value(s);
	utf8Value.setEncoding("utf8");
	return utf8Value;
}

int main(int argc, char** argv) {
    string broker = "localhost:5672";
    string address = "amq.match";
    string connectionOptions = "{reconnect: true}";

    Connection connection(broker, connectionOptions);
    try {
        connection.open();
        Session session = connection.createSession();
        Sender sender = session.createSender(address);

		int NUMBER_OF_ITERATIONS = 1000000;
		unsigned long startTime = currentTimeMillis();

		for (int i = 0; i < NUMBER_OF_ITERATIONS; i++) {
			char* buffer = new char[50000];
			Message message(buffer, 50000);
if ((i % 3) == 0) message.setProperty("item-owner", utf8("jdadams"));
else message.setProperty("item-owner", utf8("fadams"));

message.setProperty("data-service", utf8("amqp-delivery"));

        	sender.send(message);
			
			delete buffer;

			cout << "Sent message #" << i << endl;
			if ((i % 100) == 99) {
				session.sync();
			}
		}
		
		session.sync();
		unsigned long finishTime = currentTimeMillis();

		cout << "Elapsed time = " << (finishTime - startTime) << ", messages/second = " << NUMBER_OF_ITERATIONS*1000.0f/(finishTime - startTime) << endl;
    
        connection.close();
        return 0;
    } catch(const exception& error) {
        cerr << "ItemProducer Exception: " << error.what() << endl;
        connection.close();
        return 1;   
    }
}
