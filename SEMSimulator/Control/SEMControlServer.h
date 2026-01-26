#import <Foundation/Foundation.h>

@class SEMControlServer;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SEMControlErrorDomain;

typedef NS_ENUM(NSInteger, SEMControlErrorCode) {
    SEMControlErrorInvalidRequest = 1,
    SEMControlErrorNotFound,
    SEMControlErrorMethodNotAllowed,
    SEMControlErrorUnauthorized,
    SEMControlErrorInterlock,
    SEMControlErrorTimeout,
    SEMControlErrorBusy,
    SEMControlErrorInternal
};

FOUNDATION_EXPORT NSError *SEMControlMakeError(SEMControlErrorCode code, NSString *message);

/// A deliberately small localhost-only JSON control surface for the running
/// simulator. It is used by the OpenCode MCP bridge (and is handy with curl).
@protocol SEMControlServerDelegate <NSObject>
- (NSDictionary<NSString *, id> *)statusForControlServer:(SEMControlServer *)server;

- (void)controlServer:(SEMControlServer *)server
    setSampleWithPrompt:(NSString *)prompt
              variation:(NSUInteger)variation
                   load:(BOOL)load
               goldCoat:(BOOL)goldCoat
             completion:(void (^)(NSDictionary<NSString *, id> * _Nullable result,
                                  NSError * _Nullable error))completion;

- (BOOL)controlServer:(SEMControlServer *)server
  performVacuumAction:(NSString *)action
                error:(NSError **)error;

- (BOOL)controlServer:(SEMControlServer *)server
       setHighVoltage:(BOOL)on
                error:(NSError **)error;

- (BOOL)controlServer:(SEMControlServer *)server
        setGoldCoated:(BOOL)coated
                error:(NSError **)error;
@end

@interface SEMControlServer : NSObject

@property (nonatomic, weak, nullable) id<SEMControlServerDelegate> delegate;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

- (instancetype)initWithDelegate:(id<SEMControlServerDelegate>)delegate;
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
