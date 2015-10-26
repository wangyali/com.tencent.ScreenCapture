//
//  DAXMPPBlockContact.m
//  MemoMaestro
//
//  Created by sven on 14-8-25.
//  Copyright (c) 2014年 AllGateways Software, Inc. All rights reserved.
//

#import "DAXMPPBlockContact.h"
#import "DAXMPPConfig.h"
#import "XMPPIQ+Helper.h"


@implementation DAXMPPBlockContact

- (void)fetchBlockedContacts:(void (^)(NSError *, NSArray *))block {
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get" elementID:[NSString UUID]];
    NSXMLElement *query = [NSXMLElement elementWithName:@"blocklist" xmlns:kContactBlockXmlns];
    [iq addChild:query];
    [self.xmppStream sendElement:iq];
    
    //result tracker
    [self.idTracker addID:iq.elementID block:^(id obj, id<XMPPTrackingInfo> info) {
        [XMPPIQ checkIQ:obj errorBlock:block result:^(XMPPIQ *result) {
            NSXMLElement *blockList = [result elementForName:@"blocklist" xmlns:kContactBlockXmlns];
            NSArray *items = [blockList elementsForName:@"item"];
            NSMutableArray *results = [NSMutableArray arrayWithCapacity:items.count];
            for (NSXMLElement *item in items) {
                NSString *account = [XMPPJID jidWithString:[item attributeStringValueForName:@"jid"]].user;
                [results addObject:account];
            }
            kXMPPService.blockedContacts = results;
            block(nil,results);
        }];
    } timeout:TIMEOUT_XMPP_IQ_REQUEST];
}

- (void)doBlockContact:(NSString *)account block:(void (^)(NSError *, NSString *))block {
    XMPPIQ *iq = [XMPPIQ iqWithType:@"set" elementID:[NSString UUID]];
    [iq addAttributeWithName:@"from" stringValue:(kJIDWithAccount(kMe.accountEncoded)).full];
    NSXMLElement *query = [NSXMLElement elementWithName:@"block" xmlns:kContactBlockXmlns];
    NSXMLElement *item = [NSXMLElement elementWithName:@"item"];
    [item addAttributeWithName:@"jid" stringValue:(kJIDWithAccount(account)).full];
    [query addChild:item];
    [iq addChild:query];
    [self.xmppStream sendElement:iq];
    
    //result tracker
    [self.idTracker addID:iq.elementID block:^(id obj, id<XMPPTrackingInfo> info) {
        [XMPPIQ checkIQ:obj errorBlock:block result:^(XMPPIQ *result) {
            block(nil,account);
        }];
    } timeout:TIMEOUT_XMPP_IQ_REQUEST];
}

- (void)doUnBlockContact:(NSString *)account block:(void (^)(NSError *, NSString *))block {
    XMPPIQ *iq = [XMPPIQ iqWithType:@"set" elementID:[NSString UUID]];
//    [iq addAttributeWithName:@"to" stringValue:(kJIDWithAccount(account)).full];
    NSXMLElement *query = [NSXMLElement elementWithName:@"unblock" xmlns:kContactBlockXmlns];
    NSXMLElement *item = [NSXMLElement elementWithName:@"item"];
    [item addAttributeWithName:@"jid" stringValue:(kJIDWithAccount(account)).full];
    [query addChild:item];
    [iq addChild:query];
    [self.xmppStream sendElement:iq];
    
    //result tracker
    [self.idTracker addID:iq.elementID block:^(id obj, id<XMPPTrackingInfo> info) {
        [XMPPIQ checkIQ:obj errorBlock:block result:^(XMPPIQ *result) {
            block(nil,account);
        }];
    } timeout:TIMEOUT_XMPP_IQ_REQUEST];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPStream Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender {
    [self fetchBlockedContacts:^(NSError *err, NSArray *result) {
        
    }];
}

- (void)xmppStream:(XMPPStream *)sender didFailToSendIQ:(XMPPIQ *)iq error:(NSError *)error {
    [self.idTracker invokeForID:iq.elementID withObject:error];
}


- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq {
    return [self.idTracker invokeForID:iq.elementID withObject:iq];
}


- (BOOL)activate:(XMPPStream *)aXmppStream {
	if ([super activate:aXmppStream]) {
        _idTracker = [[XMPPIDTracker alloc] initWithDispatchQueue:moduleQueue];
//        _idTracker = [[XMPPIDTracker alloc] initWithStream:xmppStream dispatchQueue:moduleQueue];
		return YES;
	}
	return NO;
}

- (void)deactivate {
    dispatch_block_t block = ^{ @autoreleasepool {
        [_idTracker removeAllIDs];
		_idTracker = nil;
	}};
	if (dispatch_get_specific(moduleQueueTag))
		block();
	else
		dispatch_sync(moduleQueue, block);
	
	[super deactivate];
}


@end
