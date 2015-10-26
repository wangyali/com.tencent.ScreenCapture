//
//  DAXMPPBlockContact.h
//  MemoMaestro
//
//  Created by sven on 14-8-25.
//  Copyright (c) 2014年 AllGateways Software, Inc. All rights reserved.
//

#import "XMPPModule.h"
@class CDUser;

#define kContactBlockXmlns @"urn:xmpp:blocking"

@interface DAXMPPBlockContact : XMPPModule

@property (strong, nonatomic) XMPPIDTracker *idTracker;


- (void)fetchBlockedContacts:(void(^)(NSError *err,NSArray *result))block;
//block contact
- (void)doBlockContact:(NSString *)account block:(void(^)(NSError *err,NSString *account))block;
//unBlock contact
- (void)doUnBlockContact:(NSString *)account block:(void(^)(NSError *err,NSString *account))block;


@end
