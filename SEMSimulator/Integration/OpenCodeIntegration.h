#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SEMOpenCodeDefaultURL;
extern NSString * const SEMOpenCodeURLDefaultsKey;
extern NSString * const SEMOpenCodeModelDefaultsKey;
extern NSString * const SEMOpenCodeKeychainService;
extern NSString * const SEMOpenCodeKeychainAccount;

@interface OpenCodeIntegration : NSObject

+ (NSString *)serverURL;
+ (void)setServerURL:(NSString *)url;
+ (nullable NSString *)configuredModel;
+ (void)setConfiguredModel:(nullable NSString *)model;
+ (nullable NSString *)password;
+ (BOOL)setPassword:(nullable NSString *)password error:(NSError **)error;
+ (BOOL)hasPassword;

+ (NSString *)normalizedURLString:(NSString *)url;
+ (void)testServerURL:(NSString *)url
             password:(nullable NSString *)password
           completion:(void (^)(BOOL ok, NSString *message))completion;

/// Fetches chat models from /api/model using the saved server URL and optional
/// saved password. Each entry contains identifier, providerID, modelID, name,
/// score, local, and free keys. Completion runs on the main queue.
+ (void)fetchAvailableModelsWithCompletion:(void (^)(NSArray<NSDictionary<NSString *, id> *> * _Nullable models,
                                                    NSError * _Nullable error))completion;

/// Fetches chat models using an explicit URL and password. An empty password
/// sends no Authorization header, so it works with an unauthenticated server.
+ (void)fetchAvailableModelsForURL:(NSString *)url
                          password:(nullable NSString *)password
                        completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> * _Nullable models,
                                            NSError * _Nullable error))completion;

/// Sends a stateless text-generation request to the OpenCode server. When
/// `model` is nil the configured model is used; when that is also nil a local
/// or free model is selected from /api/model. The completion runs on the main
/// queue. A nil text value is always accompanied by an error.
+ (void)generateTextWithPrompt:(NSString *)prompt
                         model:(nullable NSString *)model
                    completion:(void (^)(NSString * _Nullable text,
                                         NSInteger status,
                                         NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
