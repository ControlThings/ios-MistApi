/**
 * Copyright (C) 2020, ControlThings Oy Ab
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * @license Apache-2.0
 */
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h> 
#include <time.h>
#include <arpa/inet.h>
#include <errno.h>


#include "wish_relay_client.h"
#include "wish_connection.h"
#include "wish_debug.h"
#include "port_dns.h"

void socket_set_nonblocking(int sockfd);

/* Function used by Wish to send data over the Relay control connection
 * */
int relay_send(int sockfd, unsigned char* buffer, int len) {
    int n = write(sockfd, buffer, len);
    //printf("Wrote %i bytes to relay\n", n);
    if (n < 0) {
        perror("ERROR writing to relay");
    }
    return 0;
}




void port_relay_client_open(wish_relay_client_t* relay, wish_ip_addr_t *relay_ip) {
    struct sockaddr_in relay_serv_addr;

    relay->curr_state = WISH_RELAY_CLIENT_CONNECTING;
    
    printf("Open relay connection");
    relay->sockfd = socket(AF_INET, SOCK_STREAM, 0);
    
    if (relay->sockfd == -1) {
        relay->curr_state = WISH_RELAY_CLIENT_WAIT_RECONNECT;
        return;
    }

    socket_set_nonblocking(relay->sockfd);

    if (relay->sockfd < 0) {
        perror("ERROR opening socket");
    }
    relay_serv_addr.sin_family = AF_INET;
    char ip_str[12+3+1] = { 0 };
    sprintf(ip_str, "%i.%i.%i.%i", 
        relay_ip->addr[0], relay_ip->addr[1],
        relay_ip->addr[2], relay_ip->addr[3]);

    printf("Connecting to relay server: %s:%d\n", ip_str, relay->port);
    inet_aton(ip_str, &relay_serv_addr.sin_addr);
    relay_serv_addr.sin_port = htons(relay->port);
    if (connect(relay->sockfd, (struct sockaddr *) &relay_serv_addr, 
            sizeof(relay_serv_addr)) == -1) {
        if (errno == EINPROGRESS) {
            printf("Started connecting to relay server\n");
            relay->send = relay_send;
        }
        else {
            perror("relay server connect()");
            relay->curr_state = WISH_RELAY_CLIENT_WAIT_RECONNECT;
        }
    } else {
        WISHDEBUG(LOG_CRITICAL, "Relay client connection succeeded but we expected error.");
    }
}

void wish_relay_client_open(wish_core_t* core, wish_relay_client_t* relay, uint8_t uid[WISH_ID_LEN]) {
    /* FIXME this has to be split into port-specific and generic
     * components. For example, setting up the RB, next state, expect
     * byte, copying of id is generic to all ports */
    
    ring_buffer_init(&(relay->rx_ringbuf), relay->rx_ringbuf_storage, RELAY_CLIENT_RX_RB_LEN);
    memcpy(relay->uid, uid, WISH_ID_LEN);
    
    /* Linux/Unix-specific from now on */
    wish_ip_addr_t relay_ip;
    if (wish_parse_transport_ip(relay->host, 0, &relay_ip) == RET_FAIL) {
        /* The relay's host was not an IP address. DNS Resolve first. */
        relay->curr_state = WISH_RELAY_CLIENT_RESOLVING;
        
        int ret = port_dns_start_resolving(core, NULL, relay, relay->host);
        if (ret != 0) {
            printf("Relay name resolution failure\n");
            relay_ctrl_disconnect_cb(core, relay);
        }
    }
    else {
        relay->curr_state = WISH_RELAY_CLIENT_CONNECTING;
        port_relay_client_open(relay, &relay_ip);
    }
    
}

void wish_relay_client_close(wish_core_t* core, wish_relay_client_t *relay) {
    close(relay->sockfd);
    relay_ctrl_disconnect_cb(core, relay);
}




