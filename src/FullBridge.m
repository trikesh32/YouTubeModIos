#import "FullBridge.h"
#import "Core.h"
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>
#import <objc/runtime.h>
#include <string.h>
BOOL YMLiveContainer(void) {
    Method method=class_getClassMethod(NSUserDefaults.class,NSSelectorFromString(@"lcMainBundle"));
    if(!method || method_getNumberOfArguments(method)!=2)return NO;
    char *type=method_copyReturnType(method);BOOL valid=type && !strcmp(type,"@");free(type);if(!valid)return NO;
    id host=((id(*)(id,SEL))method_getImplementation(method))(NSUserDefaults.class,NSSelectorFromString(@"lcMainBundle"));
    if(![host isKindOfClass:NSBundle.class] || host==NSBundle.mainBundle)return NO;
    NSString *identifier=[host bundleIdentifier];
    return [identifier isEqual:@"com.kdt.livecontainer"] || [identifier hasPrefix:@"com.kdt.livecontainer."];
}
static void Save(void) {
    NSMutableDictionary *state=[YMSnapshot() mutableCopy];
    state[@"engine"]=@"YTKACE 1.1.8 / 5f8cb77";
    state[@"runtime_environment"]=YMLiveContainer()?@"livecontainer":@"standalone";
    state[@"audio_category"]=AVAudioSession.sharedInstance.category?:@"unknown";
    state[@"app_state"]=@(UIApplication.sharedApplication.applicationState);
    NSData *data=[NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil];
    NSURL *folder=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    if(data && folder)[data writeToURL:[folder URLByAppendingPathComponent:@"YouTubeMod-diagnostics.json"] options:NSDataWritingAtomic error:nil];
}
void YMStartFullDiagnostics(void) {
    Save();
    for(NSString *event in @[UIApplicationDidEnterBackgroundNotification,UIApplicationDidBecomeActiveNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:event object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;Save();}];
}
