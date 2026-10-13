/*
 * client.c - a deliberately simple, verbose TCP client.
 *
 * It connects to the server on 127.0.0.1:8080, sends one message,
 * waits for the reply and closes the connection.
 */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define SERVER_IP "127.0.0.1"
#define PORT 8080
#define BUF_SIZE 1024
#define DELAY_SECONDS 2

int main(void)
{
    /* Print immediately, even when stdout is not a terminal. */
    setvbuf(stdout, NULL, _IONBF, 0);

    /* 1. Create a socket. The kernel returns a new file descriptor. */
    printf("CLIENT: calling socket()\n");
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("CLIENT: socket() failed");
        return EXIT_FAILURE;
    }
    printf("CLIENT: socket() -> fd=%d\n\n", fd);

    /* 2. Connect to the server. This performs the TCP three-way handshake. */
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    inet_pton(AF_INET, SERVER_IP, &addr.sin_addr);

    printf("CLIENT: calling connect() to %s:%d\n", SERVER_IP, PORT);
    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (rc < 0) {
        perror("CLIENT: connect() failed");
        return EXIT_FAILURE;
    }
    printf("CLIENT: connect() -> %d\n", rc);

    /* The kernel picked a random local port for us. Look for it in tcpdump. */
    struct sockaddr_in local;
    socklen_t local_len = sizeof(local);
    getsockname(fd, (struct sockaddr *)&local, &local_len);
    printf("CLIENT: my address is %s:%d\n\n",
           inet_ntoa(local.sin_addr), ntohs(local.sin_port));

    /* Pause so you can see the server blocked in recv(). */
    printf("CLIENT: sleeping %d s before sending...\n\n", DELAY_SECONDS);
    sleep(DELAY_SECONDS);

    /* 3. Send a message. */
    const char *msg = "Hello server!";
    printf("CLIENT: calling send()\n");
    printf("CLIENT: sending \"%s\"\n", msg);
    ssize_t n = send(fd, msg, strlen(msg), 0);
    if (n < 0) {
        perror("CLIENT: send() failed");
        return EXIT_FAILURE;
    }
    printf("CLIENT: send() -> %zd bytes\n\n", n);

    /* 4. Wait for the reply. recv() BLOCKS until data arrives. */
    char buf[BUF_SIZE];
    printf("CLIENT: calling recv()\n");
    printf("CLIENT: waiting for response...\n");
    n = recv(fd, buf, sizeof(buf) - 1, 0);
    if (n < 0) {
        perror("CLIENT: recv() failed");
        return EXIT_FAILURE;
    }
    buf[n] = '\0'; /* recv() does not add a terminating '\0' */
    printf("CLIENT: recv() -> %zd bytes\n", n);
    printf("CLIENT: received: \"%s\"\n\n", buf);

    /* 5. Close the connection. This sends a FIN to the server. */
    printf("CLIENT: calling close(fd=%d)\n", fd);
    rc = close(fd);
    printf("CLIENT: close() -> %d\n", rc);

    return EXIT_SUCCESS;
}
