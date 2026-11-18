#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>
#import <objc/runtime.h>
#import "Core.h"
#import "NativeMenu.h"
#include <string.h>

static NSMutableDictionary *LifecycleState(void) {
    static NSMutableDictionary *state;static dispatch_once_t once;
    dispatch_once(&once,^{state=[NSMutableDictionary new];});return state;
}
static NSDictionary *Diagnostics(void) {
    NSMutableDictionary *result=[YMSnapshot() mutableCopy];
    result[@"menu"]=YMNativeMenuSnapshot();
    result[@"lifecycle"]=[LifecycleState() copy];
    AVAudioSession *audio=AVAudioSession.sharedInstance;
    result[@"audio_session"]=@{@"category":audio.category?:@"unknown",@"mode":audio.mode?:@"unknown"};
    result[@"background_audio_declared"]=@([[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIBackgroundModes"] containsObject:@"audio"]);
    return result;
}
static void SaveDiagnostics(void) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:Diagnostics() options:NSJSONWritingPrettyPrinted error:nil];
    NSURL *folder=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    if(data && folder)[data writeToURL:[folder URLByAppendingPathComponent:@"YouTubeMod-diagnostics.json"] options:NSDataWritingAtomic error:nil];
}

@interface YMSettingsController:UITableViewController @end
@implementation YMSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"YouTube Mod";
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=60;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table{return 2;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return section==0?1:2;}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return section==0?@"Экспериментальное фоновое воспроизведение. После изменения открой видео заново. Shorts остаются без изменений.":@"0.1.3 — исследовательская сборка. Диагностика содержит только состояния и счётчики мода.";
}
- (void)toggle:(UISwitch *)sender {YMSetEnabled(YMBackgroundKey,sender.on);SaveDiagnostics();}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.numberOfLines=0;
    if(index.section==0) {
        cell.textLabel.text=@"Фоновое воспроизведение";UISwitch *toggle=[UISwitch new];toggle.on=YMEnabled(YMBackgroundKey);
        toggle.accessibilityLabel=cell.textLabel.text;[toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView=toggle;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else if(index.row==0)cell.textLabel.text=@"Скопировать диагностику";
    else {cell.textLabel.text=@"Версия мода";cell.detailTextLabel.text=@"0.1.3";cell.selectionStyle=UITableViewCellSelectionStyleNone;}
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if(index.section!=1 || index.row!=0)return;
    NSData *json=[NSJSONSerialization dataWithJSONObject:Diagnostics() options:NSJSONWritingPrettyPrinted error:nil];
    if(json)UIPasteboard.generalPasteboard.string=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:json?@"Скопировано":@"Ошибка" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];
}
@end

static void PresentModSettings(id object) {
    if(![object isKindOfClass:UIViewController.class])return;
    UIViewController *owner=object;
    if(owner.presentedViewController)return;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:
        [[YMSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped]];
    [owner presentViewController:nav animated:YES completion:nil];SaveDiagnostics();
}
static void InstallLifecycleDiagnostics(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        NSDictionary *events=@{UIApplicationDidEnterBackgroundNotification:@"entered_background",
            UIApplicationWillEnterForegroundNotification:@"entered_foreground",
            UIApplicationDidBecomeActiveNotification:@"became_active"};
        for(NSString *notification in events) {
            NSString *name=events[notification];
            [NSNotificationCenter.defaultCenter addObserverForName:notification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
                LifecycleState()[name]=@([LifecycleState()[name] unsignedLongLongValue]+1);
                LifecycleState()[@"last_event"]=name;SaveDiagnostics();
            }];
        }
    });
}
static void Bootstrap(void) {
    if(![[NSBundle.mainBundle objectForInfoDictionaryKey:@"YouTubeModVersion"] isEqual:@"0.1.3"])return;
    YMInstall();
    InstallLifecycleDiagnostics();
    YMInstallNativeMenu(^(id owner){PresentModSettings(owner);});
    SaveDiagnostics();
}
__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        for(NSNumber *delay in @[@0,@0.5,@1,@2,@4,@8])
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{Bootstrap();});
    }
}
