#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KeychainStore : NSObject
+ (BOOL)setString:(nullable NSString *)string forService:(NSString *)service account:(NSString *)account error:(NSError **)error;
+ (nullable NSString *)stringForService:(NSString *)service account:(NSString *)account error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
