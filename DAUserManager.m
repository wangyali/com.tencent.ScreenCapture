//
//  DAUserManager.m
//  Sprout
//
//  Created by sven on 14-3-28.
//  Copyright (c) 2014年 AllGateways Software, Inc. All rights reserved.
//

#import "DAUserManager.h"
#import "DAXMPPService.h"
#import "CoreDataHandler.h"
#import "XMPPvCardTemp.h"

@implementation DAUserManager

+ (NSArray *)getAllXmppUsers {
    NSManagedObjectContext *moc = [kXMPPService managedObjectContext_roster];

    NSEntityDescription *entity = [NSEntityDescription entityForName:@"XMPPUserCoreDataStorageObject"
                                              inManagedObjectContext:moc];
    NSSortDescriptor *sd2 = [[NSSortDescriptor alloc] initWithKey:@"displayName" ascending:YES];
    
    NSArray *sortDescriptors = [NSArray arrayWithObjects:sd2, nil];
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:entity];
    [fetchRequest setSortDescriptors:sortDescriptors];
//    [fetchRequest setPredicate:predicate];
    [fetchRequest setFetchBatchSize:10];
    
    NSArray *results = [moc executeFetchRequest:fetchRequest error:nil];
    return results;
}

+ (CDUser *)synDAUserWithXmppUser:(XMPPJID *)jid save:(BOOL)save{
    XMPPvCardTempModule *vCardTempMudole = kXMPPService.xmppvCardTempModule;
    XMPPvCardTemp *vcard = [vCardTempMudole vCardTempForJID:jid shouldFetch:NO];
    NSLog(@"nick : %@  photo length : %@",vcard.nickname,@(vcard.photo.length));
    if (vcard.nickname || vcard.photo.length) {
        CoreDataHandler *coreData = kCoreData;
        CDUser *user = [kCoreData touchCDUserByAccount:jid.user];
        user.avatar = vcard.photo;
        user.nickName = vcard.nickname;
        NSLog(@"sync vcard account :%@  nick:%@ avatar:%@",jid.user,vcard.nickname,@(vcard.photo.length));
        if (save) {
            [coreData saveCoreData];
        }
        return user;
    }
    return nil;
}

@end
