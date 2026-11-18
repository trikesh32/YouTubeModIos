#import "NativeMenu.h"
#import <objc/runtime.h>
#include <assert.h>
static NSArray *categoryOrder,*orderedGroups;
static NSUInteger originalUpdates;
@interface YTAppSettingsPresentationData:NSObject
+ (NSArray *)settingsCategoryOrder;
@end
@implementation YTAppSettingsPresentationData
+ (NSArray *)settingsCategoryOrder{return categoryOrder;}
@end
@interface YTAppSettingsGroupPresentationData:NSObject
+ (NSArray *)orderedGroups;
@end
@implementation YTAppSettingsGroupPresentationData
+ (NSArray *)orderedGroups{return orderedGroups;}
@end
@interface YTSettingsGroupData:NSObject
@property NSUInteger type;
- (instancetype)initWithGroupType:(NSUInteger)type;
- (NSString *)titleForSettingGroupType:(NSUInteger)type;
- (NSArray *)orderedCategoriesForGroupType:(NSUInteger)type;
@end
@implementation YTSettingsGroupData
- (instancetype)initWithGroupType:(NSUInteger)type{if((self=[super init]))self.type=type;return self;}
- (NSString *)titleForSettingGroupType:(NSUInteger)type{(void)type;return @"Original";}
- (NSArray *)orderedCategoriesForGroupType:(NSUInteger)type{(void)type;return @[@1];}
@end
@interface YTSettingsSectionItem:NSObject
@property(copy) BOOL (^select)(id,NSUInteger);
@end
@implementation YTSettingsSectionItem @end
static id MakeItem(id object,SEL selector,id title,id identifier,id detail,BOOL (^select)(id,NSUInteger)) {
    (void)object;(void)selector;(void)title;(void)identifier;(void)detail;
    YTSettingsSectionItem *item=[YTSettingsSectionItem new];item.select=select;return item;
}
@interface YTSettingsViewController:NSObject
@property(copy) NSArray *items;
@property(copy) NSString *title;
- (void)setSectionItems:(NSArray *)items forCategory:(NSUInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)description headerHidden:(BOOL)hidden;
@end
@implementation YTSettingsViewController
- (void)setSectionItems:(NSArray *)items forCategory:(NSUInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)description headerHidden:(BOOL)hidden {
    (void)category;(void)icon;(void)description;(void)hidden;self.items=items;self.title=title;
}
@end
@interface YTSettingsSectionItemManager:NSObject {
@public __weak id _settingsViewControllerDelegate;
}
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry;
@end
@implementation YTSettingsSectionItemManager
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry{(void)category;(void)entry;originalUpdates++;}
@end
static id Wrong(id object,SEL selector){(void)object;(void)selector;return nil;}
int main(int argc,const char **argv){@autoreleasepool {
    categoryOrder=@[@1,@2];orderedGroups=@[[[YTSettingsGroupData alloc] initWithGroupType:1]];
    __block NSUInteger presentations=0;
    void (^present)(id)=^(id owner){assert([owner isKindOfClass:YTSettingsViewController.class]);presentations++;};
    assert(!YMInstallNativeMenu(nil));
    // Reject missing/changed factories before publishing a menu category.
    Class meta=object_getClass(YTSettingsSectionItem.class);
    SEL factory=NSSelectorFromString(@"itemWithTitle:accessibilityIdentifier:detailTextBlock:selectBlock:");
    if(argc>1) {
        (void)argv;class_addMethod(meta,factory,(IMP)Wrong,"@16@0:8");
        assert(!YMInstallNativeMenu(present));
        assert([YTAppSettingsPresentationData settingsCategoryOrder]==categoryOrder);
        puts("Native menu: changed factory ABI rejected without partial installation");return 0;
    }
    assert(!YMInstallNativeMenu(present));
    assert([YTAppSettingsPresentationData settingsCategoryOrder]==categoryOrder);
    assert(class_addMethod(meta,factory,(IMP)MakeItem,"@48@0:8@16@24@?32@?40"));
    assert(YMInstallNativeMenu(present));assert(YMInstallNativeMenu(present));
    NSArray *order=[YTAppSettingsPresentationData settingsCategoryOrder];assert(order.count==3 && categoryOrder.count==2);
    NSUInteger category=[order.lastObject unsignedIntegerValue];categoryOrder=order;
    assert([YTAppSettingsPresentationData settingsCategoryOrder]==order);
    NSArray *groups=[YTAppSettingsGroupPresentationData orderedGroups];assert(groups.count==2 && orderedGroups.count==1);
    YTSettingsGroupData *group=groups.lastObject;orderedGroups=groups;
    assert([YTAppSettingsGroupPresentationData orderedGroups]==groups);
    assert([[group titleForSettingGroupType:group.type] isEqual:@"YouTube Mod"]);
    assert([[group orderedCategoriesForGroupType:group.type] isEqual:@[@(category)]]);
    assert([[group titleForSettingGroupType:1] isEqual:@"Original"]);
    assert([[group orderedCategoriesForGroupType:1] isEqual:@[@1]]);
    YTSettingsSectionItemManager *manager=[YTSettingsSectionItemManager new];
    [manager updateSectionForCategory:category withEntry:nil];assert(originalUpdates==0);
    __weak id weakOwner;YTSettingsSectionItem *item;
    @autoreleasepool {
    YTSettingsViewController *owner=[YTSettingsViewController new];manager->_settingsViewControllerDelegate=owner;
    [manager updateSectionForCategory:1 withEntry:nil];assert(originalUpdates==1);
    [manager updateSectionForCategory:category withEntry:nil];assert(owner.items.count==1);
    item=owner.items.firstObject;
    assert(item.select(nil,0) && presentations==1);
    [manager updateSectionForCategory:category withEntry:nil];assert(owner.items.count==1);
    weakOwner=owner;owner=nil;
    }
    assert(weakOwner==nil);
    assert(!item.select(nil,0) && presentations==1);
    categoryOrder=nil;orderedGroups=nil;
    assert([YTAppSettingsPresentationData settingsCategoryOrder]==nil);
    assert([YTAppSettingsGroupPresentationData orderedGroups]==nil);
    puts("Native menu: atomic ABI preflight, original categories, no duplicates, delegate/callback and weak lifetime passed");
}return 0;}
