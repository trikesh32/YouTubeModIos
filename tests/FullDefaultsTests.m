#import "Core.h"
#import "FullBridge.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    NSString *domain=NSProcessInfo.processInfo.processName;
    [d removePersistentDomainForName:domain];
    NSString *old=@"io.github.trikesh32.youtube.background.v1";
    [d setBool:NO forKey:old];
    YMPrepareFullDefaults();
    [d registerDefaults:@{YMBackgroundKey:@YES,@"YTKACE.Preference.Enabled":@YES}];
    YMApplyFullDefaults();
    assert(!YMEnabled(YMBackgroundKey)); // explicit old OFF survives default YES
    [d setBool:YES forKey:old];
    YMPrepareFullDefaults();
    assert(!YMEnabled(YMBackgroundKey)); // migration never overwrites new choice
    [d setBool:YES forKey:YMBackgroundKey];
    assert(YMEnabled(YMBackgroundKey));
    [d setBool:NO forKey:@"YTKACE.Preference.Enabled"];
    assert(!YMEnabled(YMBackgroundKey)); // master toggle controls our hooks too
    assert(![d boolForKey:@"YTKACE.Preference.Shorts.FeedHidden"]);
    assert(![d boolForKey:@"YTKACE.Preference.Shorts.LimitEnabled"]);
    assert([d boolForKey:@"YTKACE.Preference.Ads.Blocking"]);
    [d setBool:NO forKey:@"YTKACE.Preference.Ads.Blocking"];
    YMApplyFullDefaults();
    assert(![d boolForKey:@"YTKACE.Preference.Ads.Blocking"]);
    assert(![d boolForKey:@"YTKACE.Preference.ActionBar.ReturnDislikeVotes"]);
    [d removePersistentDomainForName:domain];
    puts("Full defaults: migration, explicit OFF, master toggle, Shorts and vote defaults passed");
} return 0; }
