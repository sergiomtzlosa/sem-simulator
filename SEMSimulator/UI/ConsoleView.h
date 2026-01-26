#import <Cocoa/Cocoa.h>
#import "SEMTypes.h"

@class SEMPhysicsEngine;

NS_ASSUME_NONNULL_BEGIN

@protocol ConsoleViewDelegate <NSObject>
- (void)consoleViewDidRequestAI:(id)consoleView;
- (void)consoleViewDidRequestSave:(id)consoleView;
- (void)consoleViewDidRequestSettings:(id)consoleView;
- (void)consoleViewDidRequestHelp:(id)consoleView;
- (void)consoleView:(id)consoleView didSelectPhosphorMode:(SEMPhosphorMode)mode;
@end

@interface ConsoleView : NSView

@property (nonatomic, strong) SEMPhysicsEngine *engine;
@property (nonatomic, weak, nullable) id<ConsoleViewDelegate> delegate;
@property (nonatomic, readonly) SEMPhosphorMode phosphorMode;

- (instancetype)initWithEngine:(SEMPhysicsEngine *)engine;
- (void)refreshFromEngine;

@end

NS_ASSUME_NONNULL_END
