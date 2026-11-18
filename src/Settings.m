#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core.h"
#include <string.h>

static NSMutableDictionary *MenuState(void) {
    static NSMutableDictionary *state;static dispatch_once_t once;
    dispatch_once(&once,^{state=[NSMutableDictionary new];});return state;
}
static NSDictionary *Diagnostics(void) {
    NSMutableDictionary *result=[YMSnapshot() mutableCopy];
    result[@"menu"]=[MenuState() copy];return result;
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
    return section==0?@"Экспериментальное фоновое воспроизведение. После изменения открой видео заново. Shorts остаются без изменений.":@"0.1.1 — исследовательская сборка. Диагностика содержит только состояния и счётчики мода.";
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
    else {cell.textLabel.text=@"Версия мода";cell.detailTextLabel.text=@"0.1.1";cell.selectionStyle=UITableViewCellSelectionStyleNone;}
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

@interface YMMenuTarget:NSObject
@property(nonatomic,weak) UIViewController *owner;
- (void)show;
@end
@implementation YMMenuTarget
- (void)show {
    UIViewController *owner=self.owner;if(!owner || owner.presentedViewController)return;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:[[YMSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped]];
    [owner presentViewController:nav animated:YES completion:nil];
}
@end
static char targetKey,buttonKey;
static void Attach(UIViewController *controller) {
    if(!controller.isViewLoaded || !controller.view.window)return;
    YMMenuTarget *target=objc_getAssociatedObject(controller,&targetKey);
    if(!target){target=[YMMenuTarget new];target.owner=controller;objc_setAssociatedObject(controller,&targetKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    UIBarButtonItem *button=objc_getAssociatedObject(controller,&buttonKey);
    if(!button){button=[[UIBarButtonItem alloc] initWithTitle:@"Мод" style:UIBarButtonItemStylePlain target:target action:@selector(show)];button.accessibilityIdentifier=@"youtubeMod.settings";objc_setAssociatedObject(controller,&buttonKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    UINavigationController *nav=controller.navigationController;
    UINavigationItem *item=nav.navigationBar.topItem?:controller.navigationItem;
    NSMutableArray *items=[item.rightBarButtonItems mutableCopy]?:[NSMutableArray new];
    NSIndexSet *old=[items indexesOfObjectsPassingTest:^BOOL(UIBarButtonItem *entry,NSUInteger idx,BOOL *stop){
        return [entry.accessibilityIdentifier isEqualToString:@"youtubeMod.settings"];
    }];
    [items removeObjectsAtIndexes:old];[items addObject:button];item.rightBarButtonItems=items;
    MenuState()[@"last_settings_class"]=NSStringFromClass(controller.class);
    MenuState()[@"navigation_controller_present"]=@(nav!=nil);
    MenuState()[@"navigation_bar_hidden"]=@(nav.navigationBarHidden);
    MenuState()[@"button_attached"]=@YES;SaveDiagnostics();
}
static void InstallMenuForClass(NSString *name) {
    if([MenuState()[name] isEqual:@"installed"])return;
    Class cls=NSClassFromString(name);SEL selector=@selector(viewDidAppear:);
    Method method=cls?class_getInstanceMethod(cls,selector):NULL;
    if(!method || method_getNumberOfArguments(method)!=3){MenuState()[name]=@"missing_method";return;}
    char *ret=method_copyReturnType(method),*arg=method_copyArgumentType(method,2);
    BOOL valid=ret && arg && !strcmp(ret,"v") && !strcmp(arg,@encode(BOOL));free(ret);free(arg);if(!valid){MenuState()[name]=@"unsupported_abi";return;}
    IMP original=method_getImplementation(method);
    IMP hook=imp_implementationWithBlock(^(UIViewController *object,BOOL animated){
        ((void(*)(id,SEL,BOOL))original)(object,selector,animated);
        MenuState()[@"appearances"]=@([MenuState()[@"appearances"] unsignedLongLongValue]+1);
        Attach(object);
        __weak UIViewController *weakObject=object;
        dispatch_async(dispatch_get_main_queue(),^{UIViewController *current=weakObject;if(current)Attach(current);});
    });
    if(!class_addMethod(cls,selector,hook,method_getTypeEncoding(method)))method_setImplementation(class_getInstanceMethod(cls,selector),hook);
    MenuState()[name]=@"installed";
}
static void Bootstrap(void) {
    if(![[NSBundle.mainBundle objectForInfoDictionaryKey:@"YouTubeModVersion"] isEqual:@"0.1.1"])return;
    YMInstall();
    InstallMenuForClass(@"YTSettingsViewController");
    InstallMenuForClass(@"YTSearchableSettingsViewController");
    MenuState()[@"bootstrap_completed"]=@YES;SaveDiagnostics();
}
__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        for(NSNumber *delay in @[@0,@0.5,@1,@2,@4,@8])
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{Bootstrap();});
    }
}
