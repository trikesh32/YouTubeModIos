#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
FOUNDATION_EXPORT NSString *const YMBackgroundKey;
BOOL YMEnabled(NSString *key);
void YMSetEnabled(NSString *key, BOOL enabled);
BOOL YMInstallBool(Class cls, SEL selector, NSString *preference);
void YMInstall(void);
NSDictionary *YMSnapshot(void);

#ifdef __cplusplus
}
#endif
