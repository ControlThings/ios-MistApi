//
//  Sandbox.m
//  MistApi
//
//  Created by Jan on 23/04/2018.
//  Copyright © 2018 ControlThings. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MistApi.h"
#import "Sandbox.h"
#include "bson.h"
#include "bson_visit.h"
#include "mist_api.h"

static Sandbox *sandboxInstance;

/* This dictionary holds mapping between mist-api level RPC ids that we manage inside MistApi.m, and RPC ids from sandbox,
 key: mist_api_rpc_id, value: sandbox_rpc_id
 */
static NSMutableDictionary<NSNumber *, NSNumber *> *idRewriteDict;

char sandbox_id[SANDBOX_ID_LEN];

@implementation Sandbox
- (id)initWithCallback:(SandboxCb)cb {
    self = [super init];
    self.callback = cb;
    
    idRewriteDict = [[NSMutableDictionary<NSNumber *, NSNumber *> alloc] init];
    return self;
}

static void sandbox_callback(rpc_client_req* req, void *ctx, const uint8_t *payload, size_t payload_len) {
    bson_iterator it;
    if (BSON_INT == bson_find_from_buffer(&it, (const char *) payload, "ack")) {
        /* A reply to a normal request, rewrite the id and remove mapping */
        int rpc_id = bson_iterator_int(&it);
        NSNumber *key = [NSNumber numberWithInt:rpc_id];
        int sandbox_rpc_id = [idRewriteDict[key] intValue];
        bson_inplace_set_long(&it, sandbox_rpc_id);
        [idRewriteDict removeObjectForKey:key];
        NSLog(@"Ack for sandbox-rpc-id %i, which was rewritten as rpc-id %i", sandbox_rpc_id, rpc_id);
    }
    else if (BSON_INT == bson_find_from_buffer(&it, (const char *) payload, "sig")) {
        int rpc_id = bson_iterator_int(&it);
        NSNumber *key = [NSNumber numberWithInt:rpc_id];
        
        NSNumber *value = idRewriteDict[key];
        if (value != nil) {
            int sandbox_rpc_id = [value intValue];
            bson_inplace_set_long(&it, sandbox_rpc_id);
            NSLog(@"Sig for sandbox-rpc-id %i, which was rewritten as rpc-id %i", sandbox_rpc_id, rpc_id);
        }
        else {
            NSLog(@"Sig for rewritten rpc-id %i not found", rpc_id);
        }
    }
    else if (BSON_INT == bson_find_from_buffer(&it, (const char *) payload, "fin")) {
        /* Remove mapping */
        int rpc_id = bson_iterator_int(&it);
        NSNumber *key = [NSNumber numberWithInt:rpc_id];
        int sandbox_rpc_id = [idRewriteDict[key] intValue];
        [idRewriteDict removeObjectForKey:key];
        
        NSLog(@"Fin for sandbox-rpc-id %i, which was rewritten as rpc-id %i", sandbox_rpc_id, rpc_id);
    }
    
    sandboxInstance.callback([[NSData alloc] initWithBytes:payload length:payload_len]);
}

- (void)requestWithData:(NSData *)reqData {
    sandboxInstance = self;
    
    /* We must also have a RPC request id re-writing scheme in place, because we must ensure that all the requests sent to mist-api, both "normal" and "sandboxed" requests, have distinct ids.
     
     */
    
    
    
    int rpc_id = 0;
    int sandbox_rpc_id = 0;
    
    bson_iterator it;
    
    if (BSON_INT == bson_find_from_buffer(&it, reqData.bytes, "id")) {
        /* A normal RPC request from Sandbox, assign new RPC id and save mapping */
        rpc_id = get_next_rpc_id();
        sandbox_rpc_id = bson_iterator_int(&it);
        bson_inplace_set_long(&it, rpc_id);
        NSLog(@"Saving sandbox-rpc-id %i, which is rewritten as rpc-id %i", sandbox_rpc_id, rpc_id);
        [idRewriteDict setObject:[NSNumber numberWithInt:sandbox_rpc_id] forKey:[NSNumber numberWithInt:rpc_id]];
        //NSLog(@"sandbox-rpc-id count %lu", [idRewriteDict count]);
        bson bs;
        bson_init_with_data(&bs, reqData.bytes);
        
        sandboxed_api_request_context(get_mist_api(), sandbox_id, &bs, sandbox_callback, NULL);
    }
    else if (BSON_INT == bson_find_from_buffer(&it, reqData.bytes, "end")) {
        /* Request to end a RPC request ('sig') */
        sandbox_rpc_id = bson_iterator_int(&it);
        bool found = false;
        NSLog(@"sandbox-rpc-id count %lu", [idRewriteDict count]);
        for (NSNumber *key in idRewriteDict) {
            NSLog(@"sandbox-rp-id %i", [key intValue]);
            if ([idRewriteDict[key] intValue] == sandbox_rpc_id) {
                rpc_id = [key intValue];
                found = true;
                break;
            }
        }
        
        /* Call sandbox_api_cancel here */
        if (found == true) {
            NSLog(@"Cancelling sandbox-rpc-id %i, which is rewritten as rpc-id %i", sandbox_rpc_id, rpc_id);
            //sandboxed_api_request_cancel(get_mist_api(), sandbox_id, rpc_id);
        }
        else {
            NSLog(@"Cancelling sandbox-rpc-id %i, but rpc-id not found!", sandbox_rpc_id);
        }
        return;
    }
    else {
        NSLog(@"No RPC id in request from sandbox.");
        return;
    }
    
}



@end




