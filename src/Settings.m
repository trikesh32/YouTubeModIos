#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core.h"
#include <string.h>

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
    return section==0?@"Экспериментальное фоновое воспроизведение. После изменения открой видео заново. Shorts остаются без изменений.":@"0.1.0 — исследовательская сборка. Диагностика содержит только состояния и счётчики мода.";
}
- (void)toggle:(UISwitch *)sender {YMSetEnabled(YMBackgroundKey,sender.on);}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.numberOfLines=0;
    if(index.section==0) {
        cell.textLabel.text=@"Фоновое воспроизведение";UISwitch *toggle=[UISwitch new];toggle.on=YMEnabled(YMBackgroundKey);
        toggle.accessibilityLabel=cell.textLabel.text;[toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView=toggle;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else if(index.row==0)cell.textLabel.text=@"Скопировать диагностику";
    else {cell.textLabel.text=@"Версия мода";cell.detailTextLabel.text=@"0.1.0";cell.selectionStyle=UITableViewCellSelectionStyleNone;}
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if(index.section!=1 || index.row!=0)return;
    NSData *json=[NSJSONSerialization dataWithJSONObject:YMSnapshot() options:NSJSONWritingPrettyPrinted error:nil];
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
    YMMenuTarget *target=objc_getAssociatedObject(controller,&targetKey);
    if(!target){target=[YMMenuTarget new];target.owner=controller;objc_setAssociatedObject(controller,&targetKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    UIBarButtonItem *button=objc_getAssociatedObject(controller,&buttonKey);
    if(!button){button=[[UIBarButtonItem alloc] initWithTitle:@"Мод" style:UIBarButtonItemStylePlain target:target action:@selector(show)];button.accessibilityIdentifier=@"youtubeMod.settings";objc_setAssociatedObject(controller,&buttonKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    NSMutableArray *items=[controller.navigationItem.rightBarButtonItems mutableCopy]?:[NSMutableArray new];
    if(![items containsObject:button]){[items addObject:button];controller.navigationItem.rightBarButtonItems=items;}
}
static void InstallMenu(void) {
    static BOOL installed;if(installed)return;
    Class cls=NSClassFromString(@"YTSettingsViewController");SEL selector=@selector(viewDidAppear:);
    Method method=cls?class_getInstanceMethod(cls,selector):NULL;
    if(!method || method_getNumberOfArguments(method)!=3)return;
    char *ret=method_copyReturnType(method),*arg=method_copyArgumentType(method,2);
    BOOL valid=ret && arg && !strcmp(ret,"v") && !strcmp(arg,@encode(BOOL));free(ret);free(arg);if(!valid)return;
    IMP original=method_getImplementation(method);
    IMP hook=imp_implementationWithBlock(^(UIViewController *object,BOOL animated){
        ((void(*)(id,SEL,BOOL))original)(object,selector,animated);Attach(object);
    });
    if(!class_addMethod(cls,selector,hook,method_getTypeEncoding(method)))method_setImplementation(class_getInstanceMethod(cls,selector),hook);
    installed=YES;
}
__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        if(![[NSBundle.mainBundle objectForInfoDictionaryKey:@"YouTubeModVersion"] isEqual:@"0.1.0"])return;
        for(NSNumber *delay in @[@0,@0.5,@1,@2,@4,@8])
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{YMInstall();InstallMenu();});
    }
}
