#import "Core.h"
#include <assert.h>
@interface Parent:NSObject
@property(nonatomic) NSUInteger reads;
- (BOOL)available;
@end
@implementation Parent
- (BOOL)available {self.reads++;return NO;}
@end
@interface Child:Parent @end
@implementation Child @end
@interface Wrong:NSObject
- (id)available;
@end
@implementation Wrong
- (id)available{return @"original";}
@end
int main(void){@autoreleasepool {
    NSString *key=[@"ym-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
    assert(!YMEnabled(key));assert(!YMInstallBool(Wrong.class,@selector(available),key));
    assert(YMInstallBool(Child.class,@selector(available),key));assert(YMInstallBool(Child.class,@selector(available),key));
    Parent *parent=[Parent new];Child *child=[Child new];
    assert(![child available]);assert(child.reads==1);
    YMSetEnabled(key,YES);assert([child available]);assert(child.reads==2);assert(![parent available]);
    YMSetEnabled(key,NO);assert(![child available]);assert(child.reads==3);
    NSDictionary *row=YMSnapshot()[@"hooks"][@"Child.available"];
    assert([row[@"calls"] unsignedIntegerValue]==3 && [row[@"overrides"] unsignedIntegerValue]==1);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    puts("Core tests passed: OFF, original execution, ABI rejection, inheritance, repeated install and counters");
}return 0;}
