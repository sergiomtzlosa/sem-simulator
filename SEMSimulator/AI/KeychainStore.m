#import "KeychainStore.h"
#import <Security/Security.h>

@implementation KeychainStore

+ (BOOL)setString:(NSString *)string forService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService: service,
                            (__bridge id)kSecAttrAccount: account};
    SecItemDelete((__bridge CFDictionaryRef)query);
    if (!string) return YES;

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *add = [query mutableCopy];
    add[(__bridge id)kSecValueData] = data;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    if (status != errSecSuccess) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey: @"Could not save API key to Keychain."}];
        return NO;
    }
    return YES;
}

+ (NSString *)stringForService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService: service,
                            (__bridge id)kSecAttrAccount: account,
                            (__bridge id)kSecReturnData: @YES,
                            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) return nil;
    if (status != errSecSuccess) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey: @"Could not read API key from Keychain."}];
        return nil;
    }
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
