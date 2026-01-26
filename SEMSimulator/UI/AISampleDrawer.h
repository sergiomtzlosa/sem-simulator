#import <Cocoa/Cocoa.h>

@class SEMSpecimen;
@class SpecimenPreset;

NS_ASSUME_NONNULL_BEGIN

@protocol AISampleDrawerDelegate <NSObject>
- (void)aiDrawerDidRequestGenerate:(NSString *)prompt variation:(NSUInteger)variation;
- (void)aiDrawerDidRequestLoadBuiltInModel:(SpecimenPreset *)preset;
- (void)aiDrawerDidRequestSaveSpecimen:(id)drawer;
- (void)aiDrawerDidRequestLoadSpecimenFile:(id)drawer;
- (void)aiDrawerDidRequestSettings:(id)drawer;
@end

@interface AISampleDrawer : NSView

@property (nonatomic, weak, nullable) id<AISampleDrawerDelegate> delegate;
@property (nonatomic, strong, nullable) SEMSpecimen *specimen;
@property (nonatomic, assign, getter=isBusy) BOOL busy;

- (void)setStatusText:(NSString *)text;
- (void)setSpecimen:(nullable SEMSpecimen *)specimen;
- (void)reloadOfflineModels;

@end

NS_ASSUME_NONNULL_END
