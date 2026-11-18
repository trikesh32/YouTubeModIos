// Native category/group integration adapted from YTKACE NativeSettingsEntry.mm
// (MIT, copyright 2026 YTKACE contributors). See licenses/YTKACE-MIT.txt.
// This implementation adds ABI gates, isolated hooks and idempotent insertion.
#import "NativeMenu.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

static const NSUInteger YMCategoryID=0x594d6f64,YMGroupID=0x594d6772;
static BOOL installed;
static void (^presentMenu)(id);
static NSMutableDictionary *State(void) {
    static NSMutableDictionary *state;static dispatch_once_t once;
    dispatch_once(&once,^{state=[@{@"mode":@"native_category",@"status":@"pending"} mutableCopy];});return state;
}
static void Count(NSString *key) {State()[key]=@([State()[key] unsignedLongLongValue]+1);}
static Method Checked(Class cls,NSString *selector,const char *encoding) {
    Method method=cls?class_getInstanceMethod(cls,NSSelectorFromString(selector)):NULL;
    if(!method || strcmp(method_getTypeEncoding(method),encoding))return NULL;
    return method;
}
static void Hook(Class cls,NSString *selector,id block) {
    SEL sel=NSSelectorFromString(selector);Method method=class_getInstanceMethod(cls,sel);
    IMP replacement=imp_implementationWithBlock(block);
    if(!class_addMethod(cls,sel,replacement,method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(cls,sel),replacement);
}
@protocol YMGroupInitializer
- (instancetype)initWithGroupType:(NSUInteger)type;
@end

BOOL YMInstallNativeMenu(void (^present)(id)) {
    if(installed)return YES;
    if(!present)return NO;
    Class order=object_getClass(NSClassFromString(@"YTAppSettingsPresentationData"));
    Class groups=object_getClass(NSClassFromString(@"YTAppSettingsGroupPresentationData"));
    Class group=NSClassFromString(@"YTSettingsGroupData");
    Class manager=NSClassFromString(@"YTSettingsSectionItemManager");
    Class items=NSClassFromString(@"YTSettingsSectionItem");
    Class controller=NSClassFromString(@"YTSettingsViewController");
    NSString *factory=@"itemWithTitle:accessibilityIdentifier:detailTextBlock:selectBlock:";
    NSString *setter=@"setSectionItems:forCategory:title:icon:titleDescription:headerHidden:";
    Method orderMethod=Checked(order,@"settingsCategoryOrder","@16@0:8");
    Method groupsMethod=Checked(groups,@"orderedGroups","@16@0:8");
    Method titleMethod=Checked(group,@"titleForSettingGroupType:","@24@0:8Q16");
    Method categoriesMethod=Checked(group,@"orderedCategoriesForGroupType:","@24@0:8Q16");
    Method updateMethod=Checked(manager,@"updateSectionForCategory:withEntry:","v32@0:8Q16@24");
    if(!orderMethod || !groupsMethod || !titleMethod || !categoriesMethod || !updateMethod ||
       !Checked(group,@"initWithGroupType:","@24@0:8Q16") ||
       !Checked(object_getClass(items),factory,"@48@0:8@16@24@?32@?40") ||
       !Checked(controller,setter,"v60@0:8@16Q24@32@40@48B56") ||
       !class_getInstanceVariable(manager,"_settingsViewControllerDelegate")) {
        State()[@"status"]=@"missing_or_changed_abi";return NO;
    }
    // Resolve every dependency before publishing a category to the host UI.
    presentMenu=[present copy];
    IMP originalOrder=method_getImplementation(orderMethod);
    IMP originalGroups=method_getImplementation(groupsMethod);
    IMP originalTitle=method_getImplementation(titleMethod);
    IMP originalCategories=method_getImplementation(categoriesMethod);
    IMP originalUpdate=method_getImplementation(updateMethod);
    Hook(manager,@"updateSectionForCategory:withEntry:",^(id object,NSUInteger category,id entry){
        if(category!=YMCategoryID) {
            ((void(*)(id,SEL,NSUInteger,id))originalUpdate)(object,NSSelectorFromString(@"updateSectionForCategory:withEntry:"),category,entry);return;
        }
        id owner=nil;
        @try {owner=[object valueForKey:@"_settingsViewControllerDelegate"];} @catch(NSException *exception){(void)exception;}
        if(!owner || !Checked(object_getClass(owner),setter,"v60@0:8@16Q24@32@40@48B56")) {
            Count(@"delegate_unavailable");return;
        }
        __weak id weakOwner=owner;
        BOOL (^select)(id,NSUInteger)=^BOOL(id cell,NSUInteger index){
            (void)cell;(void)index;id strongOwner=weakOwner;if(!strongOwner)return NO;
            Count(@"opened");presentMenu(strongOwner);return YES;
        };
        id item=((id(*)(id,SEL,id,id,id,id))objc_msgSend)(items,NSSelectorFromString(factory),
            @"Открыть настройки мода",@"youtubeMod.settings",nil,select);
        if(!item){Count(@"item_unavailable");return;}
        ((void(*)(id,SEL,id,NSUInteger,id,id,id,BOOL))objc_msgSend)(owner,NSSelectorFromString(setter),
            @[item],YMCategoryID,@"Настройки мода",nil,@"YouTube Mod",NO);
        Count(@"sections_built");
    });
    Hook(group,@"titleForSettingGroupType:",^id(id object,NSUInteger type){
        return type==YMGroupID?@"YouTube Mod":((id(*)(id,SEL,NSUInteger))originalTitle)(object,NSSelectorFromString(@"titleForSettingGroupType:"),type);
    });
    Hook(group,@"orderedCategoriesForGroupType:",^id(id object,NSUInteger type){
        return type==YMGroupID?@[ @(YMCategoryID) ]:((id(*)(id,SEL,NSUInteger))originalCategories)(object,NSSelectorFromString(@"orderedCategoriesForGroupType:"),type);
    });
    Hook(order,@"settingsCategoryOrder",^id(id object){
        id result=((id(*)(id,SEL))originalOrder)(object,NSSelectorFromString(@"settingsCategoryOrder"));
        if(![result isKindOfClass:NSArray.class] || [result containsObject:@(YMCategoryID)])return result;
        NSMutableArray *copy=[result mutableCopy];[copy addObject:@(YMCategoryID)];return copy;
    });
    // Remember our own group instances without modifying or retaining host groups.
    NSHashTable *ownGroups=[NSHashTable weakObjectsHashTable];
    Hook(groups,@"orderedGroups",^id(id object){
        id result=((id(*)(id,SEL))originalGroups)(object,NSSelectorFromString(@"orderedGroups"));
        if(![result isKindOfClass:NSArray.class])return result;
        for(id candidate in result)if([ownGroups containsObject:candidate])return result;
        id item=[(id<YMGroupInitializer>)[group alloc] initWithGroupType:YMGroupID];
        if(!item)return result;
        [ownGroups addObject:item];NSMutableArray *copy=[result mutableCopy];[copy addObject:item];return copy;
    });
    installed=YES;State()[@"status"]=@"installed";return YES;
}
NSDictionary *YMNativeMenuSnapshot(void) {return [State() copy];}
