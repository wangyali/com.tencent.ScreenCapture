//
//  DAUserManager.h
//  Sprout
//
//  Created by sven on 14-3-28.
//  Copyright (c) 2014年 AllGateways Software, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DAUserManager : NSObject

+ (NSArray *)getAllXmppUsers;

//+ (NSArray *)getAllDAUsers;

+ (CDUser *)synDAUserWithXmppUser:(XMPPJID *)jid save:(BOOL)save;

@end
