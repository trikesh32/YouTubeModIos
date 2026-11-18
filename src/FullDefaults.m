#import "FullBridge.h"
#import "Core.h"
void YMPrepareFullDefaults(void) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    if(![defaults objectForKey:YMBackgroundKey]) {
        id old=[defaults objectForKey:@"io.github.trikesh32.youtube.background.v1"];
        if(old)[defaults setBool:[old boolValue] forKey:YMBackgroundKey];
    }
}
void YMApplyFullDefaults(void) {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"YTKACE.Preference.Ads.Blocking":@YES,
        @"YTKACE.Preference.SponsorBlock.Enabled":@YES,
        @"YTKACE.Preference.Downloads.Enabled":@YES,
        @"YTKACE.Preference.Downloads.PlaylistEnabled":@YES,
        @"YTKACE.Preference.Player.SpeedControls":@YES,
        @"YTKACE.Preference.Player.QualityButton":@YES,
        @"YTKACE.Preference.ActionBar.ReturnDislike":@YES,
        @"YTKACE.Preference.ActionBar.ReturnDislikeVotes":@NO,
        @"YTKACE.Preference.Shorts.FeedHidden":@NO,
        @"YTKACE.Preference.Shorts.LimitEnabled":@NO,
        @"YTKACE.Preference.Player.PiP":@NO
    }];
}
