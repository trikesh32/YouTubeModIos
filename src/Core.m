#import "Core.h"
#import <objc/runtime.h>
#include <string.h>

NSString *const YMBackgroundKey=@"io.github.trikesh32.youtube.background.v1";
static NSMutableDictionary *Rows(void) {
    static NSMutableDictionary *rows;static dispatch_once_t once;
    dispatch_once(&once,^{rows=[NSMutableDictionary new];});return rows;
}
BOOL YMEnabled(NSString *key) { return [NSUserDefaults.standardUserDefaults boolForKey:key]; }
void YMSetEnabled(NSString *key,BOOL enabled) { [NSUserDefaults.standardUserDefaults setBool:enabled forKey:key]; }
BOOL YMInstallBool(Class cls,SEL selector,NSString *preference) {
    if(!cls)return NO;
    NSString *key=[NSString stringWithFormat:@"%s.%s",class_getName(cls),sel_getName(selector)];
    @synchronized(Rows()) {
        NSMutableDictionary *row=Rows()[key];
        if([row[@"status"] isEqual:@"installed"])return YES;
        row=[@{@"status":@"unsupported_abi",@"calls":@0,@"overrides":@0} mutableCopy];Rows()[key]=row;
        Method method=class_getInstanceMethod(cls,selector);
        if(!method || method_getNumberOfArguments(method)!=2)return NO;
        char *type=method_copyReturnType(method);
        BOOL valid=type && !strcmp(type,@encode(BOOL));free(type);
        if(!valid)return NO;
        IMP original=method_getImplementation(method);
        IMP hook=imp_implementationWithBlock(^BOOL(id object){
            // Preserve original getter execution and its exceptions/side effects.
            BOOL result=((BOOL(*)(id,SEL))original)(object,selector);
            BOOL enabled=YMEnabled(preference);
            @synchronized(Rows()) {
                row[@"calls"]=@([row[@"calls"] unsignedLongLongValue]+1);
                if(enabled && !result)row[@"overrides"]=@([row[@"overrides"] unsignedLongLongValue]+1);
            }
            return enabled?YES:result;
        });
        // An inherited implementation must not be changed on the parent class.
        if(!class_addMethod(cls,selector,hook,method_getTypeEncoding(method)))
            method_setImplementation(class_getInstanceMethod(cls,selector),hook);
        row[@"status"]=@"installed";return YES;
    }
}
void YMInstall(void) {
    YMInstallBool(NSClassFromString(@"YTIPlayabilityStatus"),NSSelectorFromString(@"isPlayableInBackground"),YMBackgroundKey);
    YMInstallBool(NSClassFromString(@"MLVideo"),NSSelectorFromString(@"playableInBackground"),YMBackgroundKey);
}
NSDictionary *YMSnapshot(void) {
    @synchronized(Rows()) {
        NSMutableDictionary *copy=[NSMutableDictionary new];
        for(NSString *key in Rows())copy[key]=[Rows()[key] copy];
        return @{@"version":@"0.1.1",@"background_enabled":@(YMEnabled(YMBackgroundKey)),
            @"hooks":copy,@"shorts_modified":@NO};
    }
}
