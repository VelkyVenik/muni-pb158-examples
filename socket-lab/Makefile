CC     = gcc
CFLAGS = -g -O0 -Wall -Wextra -Wpedantic

all: server client

server: server.c
	$(CC) $(CFLAGS) -o server server.c

client: client.c
	$(CC) $(CFLAGS) -o client client.c

clean:
	rm -f server client

.PHONY: all clean
