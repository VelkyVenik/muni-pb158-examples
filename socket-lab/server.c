/*
 * server.c - a deliberately simple, verbose TCP server.
 *
 * It prints every socket call before making it and the result afterwards,
 * so you can watch the program block and see which file descriptors
 * the kernel hands out.
 */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define PORT 8080
#define BUF_SIZE 1024
#define DELAY_SECONDS 2

int main(void)
{
    /* Print immediately, even when stdout is not a terminal. */
    setvbuf(stdout, NULL, _IONBF, 0);

    /* 1. Create a socket. The kernel returns a new file descriptor. */
    printf("SERVER: calling socket()\n");
    int listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        perror("SERVER: socket() failed");
        return EXIT_FAILURE;
    }
    printf("SERVER: socket() -> fd=%d\n\n", listen_fd);

    /* Allow restarting the server right away without "Address already in use". */
    int yes = 1;
    setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    /* 2. Bind the socket to 127.0.0.1:8080. */
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    printf("SERVER: calling bind() to 127.0.0.1:%d\n", PORT);
    int rc = bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr));
    if (rc < 0) {
        perror("SERVER: bind() failed");
        return EXIT_FAILURE;
    }
    printf("SERVER: bind() -> %d\n\n", rc);

    /* 3. Mark the socket as passive: it will accept incoming connections. */
    printf("SERVER: calling listen()\n");
    rc = listen(listen_fd, 5);
    if (rc < 0) {
        perror("SERVER: listen() failed");
        return EXIT_FAILURE;
    }
    printf("SERVER: listen() -> %d\n\n", rc);

    /* Serve clients one after another, forever (stop with Ctrl-C). */
    for (;;) {
        /* 4. Wait for a client. accept() BLOCKS until someone connects. */
        printf("SERVER: calling accept()\n");
        printf("SERVER: waiting for connection...\n");
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int conn_fd = accept(listen_fd, (struct sockaddr *)&client_addr, &client_len);
        if (conn_fd < 0) {
            perror("SERVER: accept() failed");
            continue;
        }
        printf("SERVER: accept() -> fd=%d   <-- NEW fd for this connection\n", conn_fd);
        printf("SERVER: client is %s:%d\n",
               inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));
        printf("SERVER: listening socket is still fd=%d\n\n", listen_fd);

        /* 5. Read the client's message. recv() BLOCKS until data arrives. */
        char buf[BUF_SIZE];
        printf("SERVER: calling recv() on fd=%d\n", conn_fd);
        printf("SERVER: waiting for data...\n");
        ssize_t n = recv(conn_fd, buf, sizeof(buf) - 1, 0);
        if (n < 0) {
            perror("SERVER: recv() failed");
            close(conn_fd);
            continue;
        }
        if (n == 0) {
            printf("SERVER: recv() -> 0 (client closed the connection)\n\n");
            close(conn_fd);
            continue;
        }
        buf[n] = '\0'; /* recv() does not add a terminating '\0' */
        printf("SERVER: recv() -> %zd bytes\n", n);
        printf("SERVER: received: \"%s\"\n\n", buf);

        /* Pause so you can see the client blocked in its own recv(). */
        printf("SERVER: sleeping %d s before replying...\n\n", DELAY_SECONDS);
        sleep(DELAY_SECONDS);

        /* 6. Send a reply back on the same connected socket. */
        const char *reply = "Hello client!";
        printf("SERVER: calling send() on fd=%d\n", conn_fd);
        printf("SERVER: sending \"%s\"\n", reply);
        n = send(conn_fd, reply, strlen(reply), 0);
        if (n < 0) {
            perror("SERVER: send() failed");
            close(conn_fd);
            continue;
        }
        printf("SERVER: send() -> %zd bytes\n\n", n);

        /* 7. Wait for the client to hang up. recv() returns 0 on close. */
        printf("SERVER: calling recv() on fd=%d\n", conn_fd);
        printf("SERVER: waiting for client to close...\n");
        n = recv(conn_fd, buf, sizeof(buf) - 1, 0);
        if (n == 0)
            printf("SERVER: recv() -> 0 (client closed the connection)\n\n");
        else
            printf("SERVER: recv() -> %zd\n\n", n);

        /* 8. Close our end of the connection. listen_fd stays open. */
        printf("SERVER: calling close(fd=%d)\n", conn_fd);
        rc = close(conn_fd);
        printf("SERVER: close() -> %d\n\n", rc);

        printf("----- ready for the next client (run ./client again) -----\n\n");
    }
}
