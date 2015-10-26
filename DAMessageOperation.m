
//
//  DAMessageOperation.m
//  Sprout
//
//  Created by Allgateways on 14-5-5.
//  Copyright (c) 2014年 AllGateways Software, Inc. All rights reserved.
//

#import "DAMessageOperation.h"
#import "DAMessageManager.h"
#import "DASMMsg.h"
#import "DASMSetting.h"
#import "DAXMPPService.h"
#import "CoreDataHandler.h"
#import <CoreLocation/CoreLocation.h>
#import "LocationHandler.h"
#import "DAStatusBar.h"
#import <AudioToolbox/AudioToolbox.h>
#import "CLLocation+YCLocation.h"
#import "DAMapSetting.h"
#import "DAXMPPError.h"
#import <MapKit/MapKit.h>
#import "GALocationHelper.h"


#define __MAX_DISTANSE_ 50 //定位圆周半径


@interface DAMessageOperation ()<LocationHandlerDelegate>{
    NSMutableSet *operationqueue;
    NSMutableArray *_currentSchedule;
    NSMutableArray *_currentScheduleLocation;
    NSMutableArray *_currentPlaceScheldule;
    NSMutableArray *_currentOutdateTheard;
    NSMutableArray *_shouldResend;
}

@property (strong, nonatomic) NSMutableDictionary *timers;
@property (strong, nonatomic) MKLocalSearch *localSearch;

@end


@implementation DAMessageOperation

+(instancetype)sharedInstance{
    static dispatch_once_t once;
    static DAMessageOperation *operation;
    dispatch_once(&once, ^ { operation = [[DAMessageOperation alloc] init]; });
    return operation;
}

- (void)clear {
    [operationqueue removeAllObjects];
    [_currentSchedule removeAllObjects];
    [_currentScheduleLocation removeAllObjects];
}


- (void)loadNotificationStatusBar:(NSString *)title status:(BOOL)err{
    
    if (err) {
        [DAStatusBar showErrorWithStatus:title];
    }else{
        [DAStatusBar showSuccessWithStatus:title];
    }
}

-(id)init{
    self = [super init];
    if (self) {

        _currentSchedule = [[NSMutableArray alloc] init];
        _currentScheduleLocation = [[NSMutableArray alloc] init];
        _currentOutdateTheard = [NSMutableArray new];
        _currentPlaceScheldule = [NSMutableArray new];
        _shouldResend = [NSMutableArray new];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recieveMessage:) name:kReceiveMsgNF object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shouldSendmessage:) name:kDAMessageTimeUp object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(locationUpdata:) name:kDAMessageLocationChang object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shouldDeletRegion:) name:kDeleteMsgNF object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shouldDeletRegion:) name:kDeleteRegionNF object:nil];
        [self loaddata];
        __weak typeof(self) weakself = self;
        [[NSNotificationCenter defaultCenter] addObserverForName:kWlanConected object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note){
            NSMutableArray *resend = [NSMutableArray arrayWithArray:_shouldResend];
            for (CDMessage *message in resend) {
                
                [weakself locationSendMessage:message];
                [_shouldResend removeObject:message];
            }
        }];
        
        [self startSearch];
        
    }
    return self;
}

-(void)loaddata{
    NSArray *array = [NSArray arrayWithArray:[kCoreData fetchCDMessageByStatus:@(2)]];
    for (CDMessage *message in array) {
        [self analysedSetting:message];
    }
    if (array.count == 0) {
        [[LocationHandler sharedInstance] clearRegion];
    }
}

- (void)addMessageRegion:(CDMessage *)message{
    message.msgcanread = @(NO);
    DASMSetting *setting = [DASMSetting smSetting:message.msgsettingstr];
    DAMapSetting *mapsetting = [DAMapSetting mapSettingfromstring:message.isMine?setting.fromlocation:setting.readatlocation];
    
    CLLocationCoordinate2D coord = mapsetting.coord;
    [LocationHandler sharedInstance].delegate = self;
    
    [[LocationHandler sharedInstance] setRegion:coord radius:mapsetting.radius identifier:message.identifier];
}


-(void)recieveMessage:(NSNotification *)note{
    CDMessage *message = [note object];
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
        [self loadNotificationStatusBar:kString(@"MAESTRO_NEW_MESSAGE") status:NO];
        
        static BOOL shuoldNotify = NO;
        if (!shuoldNotify) {
            shuoldNotify = YES;
            if (!TARGET_IPHONE_SIMULATOR) {
                static SystemSoundID soundID;
                if (!soundID) {
                    NSString *soundFile = [[NSBundle mainBundle] pathForResource:@"new_message" ofType:@"mp3"];
                    if (soundFile) {
                        AudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath:soundFile], &soundID);
                    }
                }
                AudioServicesPlaySystemSound(soundID);
            }else {
                AudioServicesPlaySystemSound(1012);
            }
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                shuoldNotify = NO;
            });
        }
    }

    [self addOperation:message];
}

//将消息添加到任务队列中
-(CDMessage *)addOperation:(id)msg{
    CDMessage *cdMsg;
    if ([msg isKindOfClass:[CDMessage class]]) {
        cdMsg = msg;
    }else if([msg isKindOfClass:[DASMMsg class]]){
        //dialogID决定此对话是新对话还是回复原对话
        cdMsg = [DAMessageManager storeMessage:msg];
    }
    
    if (cdMsg.msgsettingstr) {
        [self analysedSetting:cdMsg];
    }else{
        if (cdMsg.isMine && cdMsg.fromUser == kMe) {
            __weak typeof(self) weakSelf = self;
            [kXMPPService.xmppMessage sendMessage:cdMsg response:^(NSError *err, CDMessage *obj) {
                if (err) {
                    [weakSelf loadNotificationStatusBar:kString(@"MAESTRO_MESSAGE_SENT_ERROR") status:YES];
                }else{
                    [weakSelf loadNotificationStatusBar:kString(@"MAESTRO_MESSAGE_SENT") status:NO];
                }
            }];
        }
        [_currentSchedule removeObject:cdMsg];
    }
    
    if (_currentScheduleLocation.count) {
        [LocationHandler sharedInstance].delegate = self;
        [[LocationHandler sharedInstance] enableLocationService];
    }
    
    return cdMsg;
}

//分析消息中的设置字段
-(void)analysedSetting:(CDMessage *)message{
    CDMessage *msg = message;
    DASMSetting *setting = [DASMSetting smSetting:msg.msgsettingstr];
    if (msg.isMine && message.fromUser == [SproutHelper myAccount]) {
        
        if (!setting.fromlocation) {
            if(setting.sendtime){
                msg.receiptState = @(DAMessageWaitingSend);
            }
            __weak typeof(self) weakSelf = self;
            [kXMPPService.xmppMessage sendMessage:msg response:^(NSError *err, CDMessage *obj) {
                if(setting.sendtime){
                    if (err) {
                        [weakSelf loadNotificationStatusBar:kString(@"MAESTRO_MESSAGE_ERROR") status:YES];
                    }else{
                        [weakSelf loadNotificationStatusBar:kString(@"MAESTRO_MESSAGE_SCHEDULED") status:NO];
                    }
                }else{
                    if (err) {
                        [weakSelf loadNotificationStatusBar:kString(@"MAESTRO_MESSAGE_SENT_ERROR") status:YES];
                    }
                    
                }
            }];
            return;
        }else if(setting.fromlocation && msg.status.integerValue != 1) {
            DAMapSetting *msetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];
            if ([_currentScheduleLocation containsObject:msg]) {
                return;
            }else{
                if (!message.messagesettingoutdate.integerValue) {
                    message.messagesettingoutdate = @([[NSDate date] timeIntervalSince1970] + msetting.outdate);
                }
                NSInteger removetime = message.messagesettingoutdate.integerValue - [[NSDate date] timeIntervalSince1970];
                if (removetime < 0) {
                    [self removeFromLocationService:message];
                    return;
                }else{
                    if (![_currentOutdateTheard containsObject:message]) {
                        [self performSelector:@selector(removeFromLocationService:) withObject:message afterDelay:removetime];
                        [_currentOutdateTheard addObject:message];
                    }
                }
                [_currentScheduleLocation addObject:msg];
            }
            msg.receiptState = @(DAMessageWaitingSend);
            msg.status = @(2);
            [kCoreData saveCoreData];

            //an new way
#ifdef __POWER_SAVE_
            if (msetting.isPlace) {
                if (![_currentPlaceScheldule containsObject:message]) {
                    [_currentPlaceScheldule addObject:message];
                }
                
            }else{
                [self addMessageRegion:msg];
            }
#else

#endif
            return;
        }
    
    }else if(![message.fromUser.accountEncoded isEqualToString:kMe.accountEncoded]){

        if (msg.destorytime.integerValue) {
            if ([_currentSchedule containsObject:msg]) {
                return;
            }else{
                [_currentSchedule addObject:msg];
            }
            [self scheduletodelmessage:msg];
        }
        
        if (setting.readatlocation && msg.status.integerValue != 1) {
            DAMapSetting *msetting = [DAMapSetting mapSettingfromstring:setting.readatlocation];
            if ([_currentScheduleLocation containsObject:msg]) {
                return;
            }else{
                if (!message.messagesettingoutdate.integerValue) {
                    message.messagesettingoutdate = @([[NSDate date] timeIntervalSince1970] + msetting.outdate);
                }
                NSInteger removetime = message.messagesettingoutdate.integerValue - [[NSDate date] timeIntervalSince1970];
                if (removetime < 0) {
                    [self removeFromLocationService:message];
                    return;
                }else{
                    if (![_currentOutdateTheard containsObject:message]) {
                        [self performSelector:@selector(removeFromLocationService:) withObject:message afterDelay:removetime];
                        [_currentOutdateTheard addObject:message];
                    }
                }
                
                [_currentScheduleLocation addObject:msg];
            }
            msg.receiptState = @(DAMessageWaitingSend);
            msg.status = @(2);
            [kCoreData saveCoreData];
            //an new way
            if (msetting.isPlace) {
                if (![_currentPlaceScheldule containsObject:message]) {
                    [_currentPlaceScheldule addObject:message];
                }
            }else{
                [self addMessageRegion:msg];
            }
        }
    }
}

//到时发送消息
- (void)shouldSendmessage:(NSNotification *)note{
    
    NSDictionary *dic = [note object];
    __weak typeof(self) weakSelf = self;
    CDMessage *message = [kCoreData fetchCDMessageByIdentifier:dic[@"identifier"]];
    if (message) {
        [kXMPPService.xmppMessage sendMessage:message response:^(NSError *error, CDMessage *msg){
            if (error) {
                [weakSelf loadNotificationStatusBar:kString(@"MAESTRO_MESSAGE_SENT_ERROR") status:YES];
            }else{
                [weakSelf loadNotificationStatusBar:kString(@"MAESTRO_MESSAGE_SENT") status:NO];
            }
        }];
    }
}

//消息销毁
-(void)scheduletodelmessage:(CDMessage *)message{
    NSInteger currenttime = (NSInteger)[[NSDate date] timeIntervalSince1970];
    NSInteger delay = message.destorytime.integerValue - currenttime;
    if (delay > 0) {
        [self performSelector:@selector(deleteMessage:) withObject:message afterDelay:delay];
    }else{
        [self deleteMessage:message];
    }
}

//将消息从数据库删除
-(void)deleteMessage:(CDMessage *)message{
    [kXMPPService.xmppMessage sendMsgState:message state:DAMessageDestroy response:NULL];

    [kCoreData deleteCDMessageReally:message save:YES];
    [_currentSchedule removeObject:message];
    [[NSNotificationCenter defaultCenter] postNotificationName:KDAMessageStatusDidChang object:@{@"status": @(MSG_SHOULDDELET),@"message":message}];
    
}

//将消息携带的设置信息从设置队列中删除
-(void)shouldDeletRegion:(NSNotification *)note{
    NSMutableArray *messagearray = [NSMutableArray array];
    if ([[note object] isKindOfClass:[CDMessage class]]) {
        [messagearray addObject:[note object]];
    }else{
        [messagearray addObjectsFromArray:[note object]];
    }
    
    NSArray *regions = [LocationHandler sharedInstance].locationManager.monitoredRegions.allObjects;
    NSMutableArray *removeregion = [NSMutableArray new];
    for (CLRegion *region in regions) {
        for (CDMessage *message in messagearray) {
            if ([region.identifier isEqualToString:message.identifier]) {
                [removeregion addObject:region];
                break;
            }
        }
    }
    for (CLRegion *region in removeregion) {
        [[LocationHandler sharedInstance].locationManager stopMonitoringForRegion:region];
    }
}

//消息设置过期后清理数据
-(void)removeFromLocationService:(CDMessage *)message{
    message.status = @(1);
    message.isRead = @(YES);
    message.receiptState = @(DAMessageScheduledCancle);
    [kCoreData saveCoreData];
    [_currentScheduleLocation removeObject:message];
    [_currentOutdateTheard removeObject:message];
    [[LocationHandler sharedInstance] removeRegionIdentifier:message.identifier];
}

//收到location 改变的通知 判定高级设置
- (void)locationUpdata:(id)notification{
    
    NSArray *messageArray = [NSMutableArray arrayWithArray:_currentScheduleLocation];
    if(!messageArray.count){
        return;
    }else{
        id obj;
        if ([notification isKindOfClass:[NSNotification class]]) {
            obj = [notification object];
        }else{
            obj = notification;
        }
        
        if ([obj isKindOfClass:[NSArray class]]) {
                [self judgeActionwithlocation:[obj lastObject] messagearray:messageArray];
        }else if([obj isKindOfClass:[CLLocation class]]){
            [self judgeActionwithlocation:obj messagearray:messageArray];
        }
    }
    
}

//计算目标位置和当前位置的距离
-(void)judgeActionwithlocation:(CLLocation *)location messagearray:(NSArray *)messages{
    
    NSMutableArray *seacharray = [NSMutableArray arrayWithArray:messages];
    for (CDMessage *message in seacharray) {
        CLLocationDistance distance = 0;
        DASMSetting *setting = [DASMSetting smSetting:message.msgsettingstr];
        if (message.isMine && setting.fromlocation && message.status.integerValue == 2) {
            DAMapSetting *mapsetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];
            CLLocation *location1 = [[CLLocation alloc]initWithLatitude:mapsetting.coord.latitude longitude:mapsetting.coord.longitude];
            NSInteger radius = mapsetting.radius;
            if (mapsetting.isEnter && [self isArriveLocation:location1 location:location radius:radius distance:&distance]) {
                [self locationSendMessage:message];
                continue;
            }
        }
        
        if (!message.isMine && setting.readatlocation) {
            DAMapSetting *mapsetting = [DAMapSetting mapSettingfromstring:setting.readatlocation];
            CLLocation *location1 = [[CLLocation alloc]initWithLatitude:mapsetting.coord.latitude longitude:mapsetting.coord.longitude];
            NSInteger radius = mapsetting.radius;
            [self locationChangStatus:message WhenEnterOrExit:[self isArriveLocation:location1 location:location radius:radius distance:&distance] once:mapsetting.isOnce];
        }
    }
}

//判断当前位置是否到达制定位置 用于主动获取设备的位置并比较
-(BOOL) isArriveLocation:(CLLocation *)targetlocation location:(CLLocation *)location radius:(NSInteger)radius distance:(CLLocationDistance *)distance{
    CLLocation *location2 = [location locationMarsFromEarth];
    
    if (targetlocation) {
        *distance = [location2 distanceFromLocation:targetlocation];
        if (*distance < radius) {
            return YES;
        }
    }
    return NO;
}



#pragma mark - Place
//搜索线程
-(void)startSearch{
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        while (1) {
            NSMutableSet *places = [NSMutableSet new];
            NSMutableDictionary *dic = [NSMutableDictionary new];
            for (CDMessage *message in _currentPlaceScheldule) {
                NSString *place;
                DASMSetting *setting = [DASMSetting smSetting:message.msgsettingstr];
                DAMapSetting *mapsetting;
                if (message.isMine && setting.fromlocation && message.status.integerValue == 2) {
                    mapsetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];
                    if (mapsetting.isPlace) {
                        place = mapsetting.place;
                    }
                }else if(!message.isMine && setting.readatlocation && message.status.integerValue == 2){
                    mapsetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];
                    if (mapsetting.isPlace) {
                        place = mapsetting.place;
                    }
                }
                if (place) {
                    NSMutableArray *placeArray =  [dic objectForKey:place];
                    if (placeArray) {
                        [placeArray addObject:message];
                    }else{
                        [dic setObject:[NSMutableArray arrayWithObject:message] forKey:place];
                    }
                    [places addObject:place];
                }
            }
            
            NSArray *allplace = places.allObjects;
            CLLocation *location = [[GALocationHelper new] getLocation];
            if (location) {
                for (NSString *place in allplace) {
                    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                    MKCoordinateRegion region = MKCoordinateRegionMake(CLLocationCoordinate2DMake(location.coordinate.latitude, location.coordinate.longitude), MKCoordinateSpanMake(0.1, 0.1));
                    MKLocalSearchRequest *searchRequest = [[MKLocalSearchRequest alloc] init];
                    searchRequest.naturalLanguageQuery = place;
                    searchRequest.region = region;
                    self.localSearch = [[MKLocalSearch alloc] initWithRequest:searchRequest];
                    [self.localSearch startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
                        if (!error) {
                            NSArray *mapitems = response.mapItems;
                            for (MKMapItem *item in mapitems) {
                                CLLocationDistance distance = [location distanceFromLocation:item.placemark.location];
                                if (distance < 500) {
                                    NSLog(@"find it!");
                                    [self placeDealMessags:dic[place]];
//                                    [self pushNotification:@"Find place!" message:[dic[place] firstObject]];
                                    break;
                                }
                            }
                        }
                        dispatch_semaphore_signal(sem);
                    }];
                    
                    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
                }
            }
            sleep(30);
        }
    });
}

//计算周边place
-(void)calculateNearbyPlace:(CDMessage *)message{
    DASMSetting *setting = [DASMSetting smSetting:message.msgsettingstr];
    DAMapSetting *mapsetting;
    NSString *place;
    if (message.isMine && setting.fromlocation && message.status.integerValue == 2) {
        mapsetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];
        if (mapsetting.isPlace) {
            place = mapsetting.place;
        }
    }else if(!message.isMine && setting.readatlocation && message.status.integerValue == 2){
        mapsetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];
        if (mapsetting.isPlace) {
            place = mapsetting.place;
        }
    }
    if (place) {
        MKCoordinateRegion region = MKCoordinateRegionMake(CLLocationCoordinate2DMake(0, 0), MKCoordinateSpanMake(0.5, 0.5));
        MKLocalSearchRequest *searchRequest = [[MKLocalSearchRequest alloc] init];
        searchRequest.naturalLanguageQuery = place;
        searchRequest.region = region;
        self.localSearch = [[MKLocalSearch alloc] initWithRequest:searchRequest];
        [self.localSearch startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
            
        }];
    }
    
    
}

-(void)placeDealMessags:(NSArray *)messages{
    for (CDMessage *message in messages) {
        if (message.isMine) {
            [self locationSendMessage:message];
        }else{
            [self locationChangStatus:message WhenEnterOrExit:YES once:YES];
        }
        [_currentPlaceScheldule removeObject:message];
    }
}


#pragma mark - LocationHandlerDelegate
-(void)locationHandler:(LocationHandler *)locationHandler didUpdataLocations:(NSArray *)locations{
    
#ifdef __POWER_SAVE_
    [[LocationHandler sharedInstance] disableLocationService];
    [self locationUpdata:locations];
    
#endif
}

-(void)locationHandler:(LocationHandler *)locationHandler didFailedWithError:(NSError *)error{
    
}

#pragma mark - LocationHandlerDelegate
#pragma mark - location system function (didenter) add (didexit)
- (void)locationHandler:(LocationHandler *)locationHandler didExitRegion:(CLRegion *)region{
    CDMessage *message = [kCoreData fetchCDMessageByIdentifier:region.identifier];
    
    if (!message.isMine) {
        //这里如果是离开不可读才需要设置为NO?
        DASMSetting *setting = [DASMSetting smSetting:message.msgsettingstr];
        DAMapSetting *msetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];

        [self locationChangStatus:message WhenEnterOrExit:NO once:msetting.isOnce];

    }else{
        DASMSetting *setting = [DASMSetting smSetting:message.msgsettingstr];
        DAMapSetting *mapsetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];
        if (!mapsetting.isEnter) {
            [self locationSendMessage:message];
        }
        [_shouldResend removeObject:message];
    }
}

-(void)locationHandler:(LocationHandler *)locationHandler didEnterRegion:(CLRegion *)region{
    CDMessage *message = [kCoreData fetchCDMessageByIdentifier:region.identifier];
    if (message) {
        if (message.isMine) {
            DASMSetting *setting = [DASMSetting smSetting:message.msgsettingstr];
            DAMapSetting *msetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];
            if (!msetting.isEnter) {
                return;
            }
            [self locationSendMessage:message];
        }else{
            DASMSetting *setting = [DASMSetting smSetting:message.msgsettingstr];
            DAMapSetting *mapsetting = [DAMapSetting mapSettingfromstring:setting.readatlocation];
            [self locationChangStatus:message WhenEnterOrExit:YES once:mapsetting.isOnce];

        }
    }
}

//指定地点发送消息  发送成功从系统调度队列中移除，清楚数据库标识，清楚缓存数组
//发送失败，将消息加入到消息重发数组等待网络变化的调度
-(void)locationSendMessage:(CDMessage *)message{
    message.receiptState = @(DAMessageSending);
    [kCoreData saveCoreData];
    [kXMPPService.xmppMessage sendMessage:message response:^(NSError *error, CDMessage *msg){
        if(error){
            message.receiptState = @(DAMessageWaitingSend);
            message.status = @(2);
            [kCoreData saveCoreData];
            [self pushNotification:kString(@"MAESTRO_MESSAGE_SENT_ERROR") message:message];
            
            DASMSetting *setting = [DASMSetting smSetting:message.msgsettingstr];
            DAMapSetting *mapsetting = [DAMapSetting mapSettingfromstring:setting.fromlocation];
            if (!mapsetting.isEnter && ![_shouldResend containsObject:message]) {
                [_shouldResend addObject:message];
            }
            [_currentScheduleLocation addObject:message];
            
        }else{
            [self pushNotification:[NSString stringWithFormat:kString(@"%@'s_LOCATION_MESSAGE_SENT"),[((NSArray *)[msg.dialog.usersWithoutMe valueForKey:@"nickName"]) componentsJoinedByString:@","]] message:message];
            [[LocationHandler sharedInstance] removeRegionIdentifier:message.identifier];
            [_currentOutdateTheard removeObject:message];
        }
    }];
    message.status = @(1);
    [_currentScheduleLocation removeObject:message];
    [_shouldResend removeObject:message];
    [kCoreData saveCoreData];
}

//进入或退出指定区域更新消息状态并通知 退出区域将消息设置为不可读 进入区域将消息设置为可读
-(void)locationChangStatus:(CDMessage *)message WhenEnterOrExit:(BOOL)enter once:(BOOL)once{
    if (enter) {
        if (message.msgcanread.boolValue) {
            return;
        }
        message.msgcanread = @(YES);
        [kCoreData saveCoreData];
        [[NSNotificationCenter defaultCenter] postNotificationName:KDAMessageStatusDidChang object:@{@"status": @(MSG_CANREAD),@"message":message}];
        [self pushNotification:kString(@"MAESTRO_ENTER_TO_VIEW") message:message];
    
        if (!once) {
            [[LocationHandler sharedInstance] removeRegionIdentifier:message.identifier];
            message.status = @(1);
            [_currentScheduleLocation removeObject:message];
            [_currentOutdateTheard removeObject:message];
        }
        
        NSLog(@"------------------------------You are already arrive location ------------------ can read this message");
    }else{
        if (!message.msgcanread.boolValue) {
            return;
        }
        if (!once && message.msgcanread.boolValue) {
            return;
        }
        message.msgcanread = @(NO);
        [kCoreData saveCoreData];
        [[NSNotificationCenter defaultCenter] postNotificationName:KDAMessageStatusDidChang object:@{@"status": @(MSG_CANNOTREAD),@"message":message}];
    }
}

- (void)pushNotification:(NSString *)message message:(CDMessage *)msg{
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        UILocalNotification *localNotif = [[UILocalNotification alloc] init];
        localNotif.applicationIconBadgeNumber = [UIApplication sharedApplication].applicationIconBadgeNumber + 1;
        localNotif.soundName= UILocalNotificationDefaultSoundName;
        localNotif.alertBody = message;
        localNotif.userInfo = @{@"messageID":msg.identifier};
        [[UIApplication sharedApplication] presentLocalNotificationNow:localNotif];
    }else{
        [self loadNotificationStatusBar:message status:NO];
    }
}



@end
