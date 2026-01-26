#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SEMSpecimen : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *templateName;
@property (nonatomic, strong) id<MTLTexture> heightTexture;
@property (nonatomic, strong) id<MTLTexture> normalTexture;
@property (nonatomic, strong) id<MTLTexture> zTexture;
@property (nonatomic, strong, nullable) NSImage *thumbnail;
@property (nonatomic, assign) BOOL conductive;
@property (nonatomic, assign) double meanZ;
@property (nonatomic, assign) BOOL coatingRecommended;
@property (nonatomic, assign) double scaleMicrometers;
@property (nonatomic, assign) NSUInteger seed;
@property (nonatomic, copy) NSDictionary *recipe;
@property (nonatomic, copy, nullable) NSString *sourcePrompt;

@end

NS_ASSUME_NONNULL_END
