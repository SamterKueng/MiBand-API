//
//  MBPeripheral.m
//  MiBandApiSample
//
//  Created by TracyYih on 15/1/2.
//  Copyright (c) 2015年 esoftmobile.com. All rights reserved.
//

#import "MBPeripheral.h"
#import <CoreBluetooth/CoreBluetooth.h>

#import "MBDataBuilder.h"
#import "MBDataReader.h"
#import "MBActivityDataReader.h"

#import "MBUserInfoModel.h"
#import "MBBatteryInfoModel.h"
#import "MBLEParamsModel.h"
#import "MBDeviceInfoModel.h"
#import "MBAlarmClockModel.h"
#import "MBDateTimeModel.h"
#import "MBActivityDataModel.h"
#import "MBStatisticsModel.h"


@interface MBPeripheral ()<CBPeripheralDelegate>

@property (nonatomic, strong) MBActivityDataReader *activityDataReader;
@property (nonatomic, strong) NSMutableDictionary *characteristicDictionary;
@property (nonatomic, copy) MBDiscoverServicesResultBlock discoverServicesBlock;
@property (nonatomic, copy) MBDiscoverCharacteristicsResultBlock discoverCharacteristicsBlock;
@property (nonatomic, copy) MBRealtimeStepsResultBlock realtimeStepsBlock;
@property (nonatomic, copy) MBActivityDataHandleBlock activityDataBlock;
@property (nonatomic, strong) NSMutableArray *callbackBlocks;

@end

@implementation MBPeripheral

- (instancetype)initWithPeripheral:(CBPeripheral *)cbPeripheral centralManager:(MBCentralManager *)manager{
    self = [super init];
    if (self) {
        _cbPeripheral = cbPeripheral;
        _centralManager = manager;
        _cbPeripheral.delegate = self;
        self.characteristicDictionary = [[NSMutableDictionary alloc] init];
        self.callbackBlocks = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSString *)name {
    return _cbPeripheral.name;
}

- (NSString *)identifier {
    if ([_cbPeripheral respondsToSelector:@selector(identifier)]) {
        return [_cbPeripheral.identifier UUIDString];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CFUUIDRef uuid = _cbPeripheral.UUID;
        CFStringRef string = CFUUIDCreateString(kCFAllocatorDefault, uuid);
        NSString *identifier = (NSString *)CFBridgingRelease(string);
        return identifier;
#pragma clang diagnostic pop
    }
}

- (BOOL)isConnected {
    BOOL result = NO;
    if (self.cbPeripheral.state == CBPeripheralStateConnected) {
        result = YES;
    }
    return result;
}

- (NSString *)UUIDStringForType:(MBCharacteristicType)type {
    return [[NSString stringWithFormat:@"%x", (int)type] uppercaseString];
}

- (CBCharacteristic *)characteristicForType:(MBCharacteristicType)type {
    NSString *address = [[NSString stringWithFormat:@"%x", (int)type] uppercaseString];
    return self.characteristicDictionary[address];
}

#pragma mark -
- (void)setNotifyValue:(BOOL)enabled forCharacteristic:(CBCharacteristic *)characteristic withBlock:(MBPeripheralWriteValueResultBlock)block {
    [self.callbackBlocks addObject:block];
    [self.cbPeripheral setNotifyValue:enabled forCharacteristic:characteristic];
}

- (void)enableRealtimeStepsNotification:(BOOL)isEnable withBlock:(MBPeripheralWriteValueResultBlock)block {
    [self setNotifyValue:isEnable
       forCharacteristic:[self characteristicForType:MBCharacteristicTypeRealtimeSteps]
               withBlock:block];
}

- (void)enableActivityDataNotification:(BOOL)isEnable withBlock:(MBPeripheralWriteValueResultBlock)block {
    [self setNotifyValue:isEnable
       forCharacteristic:[self characteristicForType:MBCharacteristicTypeActivityData]
               withBlock:block];
}

#pragma mark -
- (void)readValueForCharacteristic:(CBCharacteristic *)characteristic withBlock:(MBPeripheralReadValueResultBlock)block {
    [self.callbackBlocks addObject:block];
    [self.cbPeripheral readValueForCharacteristic:characteristic];
}

- (void)executeReadValueCallbackWithData:(NSData *)data withError:(NSError *)error {
    if (error) {
        NSLog(@"error %@", [error localizedDescription]);
    }
    MBPeripheralReadValueResultBlock block = [self.callbackBlocks firstObject];
    [self.callbackBlocks removeObjectAtIndex:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        block(data, error);
    });
}

- (void)writeValue:(NSData *)data forCharacteristic:(CBCharacteristic *)characteristic withBlock:(MBPeripheralWriteValueResultBlock)block {
    NSLog(@"%s\t%d %@", __FUNCTION__, __LINE__, data);
    [self.callbackBlocks addObject:block];
    [self.cbPeripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
}

- (void)executeWriteValueCallbackWithError:(NSError *)error {
    if (error) {
        NSLog(@"error %@", [error localizedDescription]);
    }
    MBPeripheralWriteValueResultBlock block = [self.callbackBlocks firstObject];
    [self.callbackBlocks removeObjectAtIndex:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        block(error);
    });
}

#pragma mark -
- (void)handleNotifyCharaterisitc:(CBCharacteristic *)characteristic withError:(NSError *)error{
    
    NSString *uuidString = [characteristic.UUID UUIDString];
    //步行
    if ([uuidString isEqualToString:[self UUIDStringForType:MBCharacteristicTypeRealtimeSteps]]) {
        if (error) {
            if (self.realtimeStepsBlock) {
                return self.realtimeStepsBlock(0, error);
            }
        }
        NSLog(@"realtimeSteps: %@", characteristic.value);
        MBDataReader *reader = [[MBDataReader alloc] initWithData:characteristic.value];
        NSUInteger steps = [reader readInt:2];
        if (self.realtimeStepsBlock) {
            self.realtimeStepsBlock(steps, error);
        }
    } else if ([uuidString isEqualToString:[self UUIDStringForType:MBCharacteristicTypeActivityData]]) {
        if (error) {
            if (self.activityDataBlock) {
                __weak typeof(self) weakSelf = self;
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.activityDataBlock(nil, error);
                    weakSelf.activityDataBlock = nil;
                });
            }
            self.activityDataReader = nil;
        }
        NSLog(@"activityData: %@", characteristic.value);
        [self.activityDataReader appendData:characteristic.value];
        if ([self.activityDataReader isDone]) {
            if (self.activityDataBlock) {
                __weak typeof(self) weakSelf = self;
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.activityDataBlock([self.activityDataReader activityDataFragmentList], nil);
                    weakSelf.activityDataBlock = nil;
                    weakSelf.activityDataReader = nil;
                });
            } else {
                self.activityDataReader = nil;
            }
        }
    } else if ([uuidString isEqualToString:[self UUIDStringForType:MBCharacteristicTypeNotification]]) {
        NSLog(@"FF03: %@", characteristic.value);
    }
}

#pragma mark -
#pragma mark - Public Methods
- (void)discoverServices:(NSArray *)serviceUUIDs withBlock:(MBDiscoverServicesResultBlock)block {
    self.discoverServicesBlock = block;
    [self.cbPeripheral discoverServices:serviceUUIDs];
}

- (void)discoverCharacteristics:(NSArray *)characteristicUUIDs forService:(CBService *)service withBlock:(MBDiscoverCharacteristicsResultBlock)block {
    if (service) {
        self.discoverCharacteristicsBlock = block;
        [self.cbPeripheral discoverCharacteristics:characteristicUUIDs forService:service];
    }
}

//Control
- (void)readUserInfoWithBlock:(void (^)(MBUserInfoModel *userInfo, NSError *error))block {
    [self readValueForCharacteristic:[self characteristicForType:MBCharacteristicTypeUserInfo]
        withBlock:^(NSData *data, NSError *error) {
            if (error) {
                return block(nil, error);
            }
            MBUserInfoModel *userInfo = [[MBUserInfoModel alloc] initWithData:data];
            block(userInfo, error);
    }];
}

- (void)bindingWithUser:(MBUserInfoModel *)user withBlock:(MBPeripheralWriteValueResultBlock)block {
    [self writeValue:[user data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeUserInfo]
           withBlock:block];
}

- (void)sendNotificationWithType:(MBNotificationType)type withBlock:(MBPeripheralWriteValueResultBlock)block {
    MBDataBuilder *builder = [[MBDataBuilder alloc] init];
    [builder writeInt:MBControlPointSendNotification bytesCount:1];
    [builder writeInt:type bytesCount:1];
    [self writeValue:[builder data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeControl]
           withBlock:block];
}

- (void)stopNotificationWithBlock:(MBPeripheralWriteValueResultBlock)block {
    MBDataBuilder *builder = [[MBDataBuilder alloc] init];
    [builder writeInt:MBControlPointStopVibrate bytesCount:1];
    [self writeValue:[builder data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeControl]
           withBlock:block];
}

- (void)readDeviceInfoWithBlock:(void (^)(MBDeviceInfoModel *deviceInfo, NSError *))block {
    [self readValueForCharacteristic:[self characteristicForType:MBCharacteristicTypeDeviceInfo]
        withBlock:^(NSData *data, NSError *error) {
            if (error) {
                return block(nil, error);
            }
            MBDeviceInfoModel *deviceInfo = [[MBDeviceInfoModel alloc] initWithData:data];
            block(deviceInfo, error);
    }];
}

- (void)readStatisticsWithBlock:(void (^)(MBStatisticsModel *statistics, NSError *error))block {
    [self readValueForCharacteristic:[self characteristicForType:MBCharacteristicTypeStatistics] withBlock:^(NSData *data, NSError *error) {
        if (error) {
            return block(nil, error);
        }
        MBStatisticsModel *model = [[MBStatisticsModel alloc] initWithData:data];
        block(model, error);
    }];
}

- (void)readDeviceName:(void (^)(NSString *name, NSError *error))block {
    [self readValueForCharacteristic:[self characteristicForType:MBCharacteristicTypeDeviceName]
        withBlock:^(NSData *data, NSError *error) {
            if (error) {
                return block(nil, error);
            }
            NSString *name = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            block(name, error);
    }];
}

- (void)readBatteryInfoWithBlock:(void (^)(MBBatteryInfoModel *batteryInfo, NSError *error))block {
    [self readValueForCharacteristic:[self characteristicForType:MBCharacteristicTypeBatteryInfo]
        withBlock:^(NSData *data, NSError *error) {
            if (error) {
                return block(nil, error);
            }
            MBBatteryInfoModel *batteryInfo = [[MBBatteryInfoModel alloc] initWithData:data];
            block(batteryInfo, error);
    }];
}

- (void)readDateTimeWithBlock:(void (^)(MBDateTimeModel *dateTime, NSError *error))block {
    [self readValueForCharacteristic:[self characteristicForType:MBCharacteristicTypeDateTime]
        withBlock:^(NSData *data, NSError *error) {
            if (error) {
                return block(nil, error);
            }
            MBDateTimeModel *model = [[MBDateTimeModel alloc] initWithData:data];
            block(model, nil);
    }];
}

- (void)setDateTimeInfo:(MBDateTimeModel *)datetime withBlock:(MBPeripheralWriteValueResultBlock)block {
    [self writeValue:[datetime data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeDateTime]
           withBlock:block];
}

- (void)readLEParamsWithBlock:(void (^)(MBLEParamsModel *, NSError *))block {
    [self readValueForCharacteristic:[self characteristicForType:MBCharacteristicTypeLEParams]
        withBlock:^(NSData *data, NSError *error) {
            if (error) {
                return block(nil, error);
            }
            MBLEParamsModel *leparams = [[MBLEParamsModel alloc] initWithData:data];
            block(leparams, error);
    }];
}

- (void)setLEParams:(MBLEParamsModel *)leparams withBlock:(MBPeripheralWriteValueResultBlock)block {
    [self writeValue:[leparams data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeLEParams]
           withBlock:block];
}

- (void)setHighLEParamsWithBlock:(MBPeripheralWriteValueResultBlock)block {
    MBLEParamsModel *params = [[MBLEParamsModel alloc] init];
    params.connIntMax = 500;
    params.connIntMin = 460;
    params.timeout = 72;
    params.connInt = 24;
    params.advInt = 2400;
    [self writeValue:[params data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeLEParams]
           withBlock:block];
}

- (void)setLowLEParamsWithBlock:(MBPeripheralWriteValueResultBlock)block {
    MBLEParamsModel *params = [[MBLEParamsModel alloc] init];
    params.connIntMax = 32;
    params.connIntMin = 16;
    params.timeout = 600;
    [self writeValue:[params data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeLEParams]
           withBlock:block];
}

- (void)setWearPosition:(MBWearPosition)position withBlock:(MBPeripheralWriteValueResultBlock)block {
    MBDataBuilder *builder = [[MBDataBuilder alloc] init];
    [builder writeInt:MBControlPointWearPosition bytesCount:1];
    [builder writeInt:position bytesCount:1];
    [self writeValue:[builder data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeControl]
           withBlock:block];
}

- (void)setColorWithRed:(NSUInteger)red green:(NSUInteger)green blue:(NSUInteger)blue blink:(BOOL)blink withBlock:(MBPeripheralWriteValueResultBlock)block {
    MBDataBuilder *bulder = [[MBDataBuilder alloc] init];
    [bulder writeInt:MBControlPointColor bytesCount:1];
    [bulder writeInt:red bytesCount:1];
    [bulder writeInt:green bytesCount:1];
    [bulder writeInt:blue bytesCount:1];
    [bulder writeInt:blink bytesCount:1];
    [self writeValue:[bulder data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeControl]
           withBlock:block];
}

- (void)setCallRemindInterval:(NSUInteger)interval withBlock:(MBPeripheralWriteValueResultBlock)block {
    MBDataBuilder *builder = [[MBDataBuilder alloc] init];
    if (interval == 0) {
        [builder writeInt:MBControlPointStopCallRemind bytesCount:1];
        [builder writeInt:0 bytesCount:1];
    } else {
        [builder writeInt:MBControlPointCallRemind bytesCount:1];
        [builder writeInt:interval bytesCount:1];
    }
    [self writeValue:[builder data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeControl]
           withBlock:block];
}

- (void)setAlarmClock:(MBAlarmClockModel *)info withBlock:(MBPeripheralWriteValueResultBlock)block {
    [self writeValue:[info data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeControl]
           withBlock:block];
}

#pragma mark - 
///////////////////////////////////////////////////////////////////////////////////////////////////
//Data
- (void)readRealtimeStepsWithBlock:(MBRealtimeStepsResultBlock)block {
    [self readValueForCharacteristic:[self characteristicForType:MBCharacteristicTypeRealtimeSteps]
        withBlock:^(NSData *data, NSError *error) {
            if (error) {
                return block(0, error);
            }
            MBDataReader *reader = [[MBDataReader alloc] initWithData:data];
            NSUInteger steps = [reader readInt:2];
            block(steps, error);
    }];
}

- (void)subscribeRealtimeStepsWithBlock:(MBRealtimeStepsResultBlock)block {
    __weak typeof(self) weakSelf = self;
    [self enableRealtimeStepsNotification:YES withBlock:^(NSError *error) {
        if (error) {
            return block(0, error);
        }
        MBDataBuilder *builder = [[MBDataBuilder alloc] init];
        [builder writeInt:MBControlPointRealtimeSetpsNotification bytesCount:1];
        [builder writeInt:1 bytesCount:1];
        [weakSelf writeValue:[builder data]
            forCharacteristic:[self characteristicForType:MBCharacteristicTypeControl]
               withBlock:^(NSError *error) {
                   if (error) {
                       return block(0, nil);
                   }
                   weakSelf.realtimeStepsBlock = block;
        }];
    }];
}

- (void)stopSubscribeRealtimeStepsWithBlock:(MBPeripheralWriteValueResultBlock)block {
    __weak typeof(self) weakSelf = self;
    [self enableRealtimeStepsNotification:NO withBlock:^(NSError *error) {
        if (error) {
            return block(error);
        }
        weakSelf.realtimeStepsBlock = nil;
        block(nil);
    }];
}

- (void)setGoalSteps:(NSUInteger)steps withBlock:(MBPeripheralWriteValueResultBlock)block {
    MBDataBuilder *builder = [[MBDataBuilder alloc] init];
    [builder writeInt:MBControlPointGoal bytesCount:1];
    [builder writeInt:0 bytesCount:1];
    [builder writeInt:steps bytesCount:2];
    [self writeValue:[builder data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeControl]
           withBlock:block];
}

- (void)readActivityDataWithBlock:(MBActivityDataHandleBlock)block {
    __weak typeof(self) weakSelf = self;
    [self enableActivityDataNotification:YES withBlock:^(NSError *error) {
        if (error) {
            return block(nil, error);
        }
        MBDataBuilder *builder = [[MBDataBuilder alloc] init];
        [builder writeInt:MBControlPointFetchData bytesCount:1];
        [weakSelf writeValue:[builder data] forCharacteristic:[weakSelf characteristicForType:MBCharacteristicTypeControl] withBlock:^(NSError *error) {
            if (error) {
                return block(nil, error);
            }
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.activityDataBlock = block;
            strongSelf.activityDataReader = [[MBActivityDataReader alloc] init];
        }];
    }];
}

- (void)confirmActivityDataWithDate:(NSDate *)time withBlock:(MBPeripheralWriteValueResultBlock)block {
    MBDataBuilder *builder = [[MBDataBuilder alloc] init];
    [builder writeInt:MBControlPointConfirmData bytesCount:1];
    [builder writeDate:time];
    [builder writeInt:0 bytesCount:2];
    
    [self writeValue:[builder data]
        forCharacteristic:[self characteristicForType:MBCharacteristicTypeControl]
           withBlock:block];
}

#pragma mark - CBPeripheralDelegate Methods
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    self.service = [peripheral.services firstObject];
    if (self.discoverServicesBlock) {
        self.discoverServicesBlock(peripheral.services, error);
        self.discoverServicesBlock = nil;
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if ([service isEqual:self.service]) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            NSString *identifier = [characteristic.UUID UUIDString];
            self.characteristicDictionary[identifier] = characteristic;
        }
    }
    
    //TODO: 什么意义
    [self setNotifyValue:YES forCharacteristic:[self characteristicForType:MBCharacteristicTypeNotification] withBlock:^(NSError *error) {
        NSLog(@"FF03 Notify %@", error);
    }];
    
    if (self.discoverCharacteristicsBlock) {
        self.discoverCharacteristicsBlock(service.characteristics, error);
        self.discoverCharacteristicsBlock = nil;
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"%s\t%d\n%@", __FUNCTION__, __LINE__,characteristic);
    if (characteristic.isNotifying) {
        [self handleNotifyCharaterisitc:characteristic withError:error];
    } else {
        if ([self.callbackBlocks count]) {
            [self executeReadValueCallbackWithData:characteristic.value withError:error];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error{
    NSLog(@"%s\t%d\n%@", __FUNCTION__, __LINE__, characteristic);
    if ([self.callbackBlocks count]) {
        [self executeWriteValueCallbackWithError:error];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"%s\t%d\n%@", __FUNCTION__, __LINE__, characteristic);
    if ([self.callbackBlocks count]) {
        [self executeWriteValueCallbackWithError:error];
    }
}

@end
