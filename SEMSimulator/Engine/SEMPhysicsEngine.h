#import <Foundation/Foundation.h>
#import "SEMTypes.h"

@class SEMSpecimen;

NS_ASSUME_NONNULL_BEGIN

@interface SEMPhysicsEngine : NSObject

@property (nonatomic, readonly) SEMVacuumState vacuumState;
@property (nonatomic, readonly) double pressurePa;
@property (nonatomic, readonly) BOOL roughingPumpOn;
@property (nonatomic, readonly) BOOL diffusionPumpOn;
@property (nonatomic, readonly) BOOL highVoltageOn;
@property (nonatomic, readonly) BOOL beamOn;
@property (nonatomic, readonly) BOOL vacuumReady;
@property (nonatomic, readonly) BOOL fault;
@property (nonatomic, readonly) double dpWarmupRemaining;
@property (nonatomic, readonly) BOOL autoHighVoltage;

@property (nonatomic, readonly) double filamentCurrent;
@property (nonatomic, readonly) double filamentLife;
@property (nonatomic, readonly) double emissionCurrent;
@property (nonatomic, readonly) NSInteger acceleratingVoltageKV;

@property (nonatomic, readonly) double magnification;
@property (nonatomic, readonly) double workingDistanceMM;
@property (nonatomic, readonly) double spotSize;
@property (nonatomic, readonly) double focus;
@property (nonatomic, readonly) double stigmatorX;
@property (nonatomic, readonly) double stigmatorY;

@property (nonatomic, readonly) double stageX;
@property (nonatomic, readonly) double stageY;
@property (nonatomic, readonly) double stageZ;
@property (nonatomic, readonly) double tilt;
@property (nonatomic, readonly) double rotation;

@property (nonatomic, readonly) double brightness;
@property (nonatomic, readonly) double contrast;
@property (nonatomic, readonly) SEMDetectorMode detectorMode;
@property (nonatomic, readonly) SEMScanMode scanMode;
@property (nonatomic, readonly) double scanDuration;
@property (nonatomic, readonly) BOOL goldCoated;
@property (nonatomic, readonly) double charge;
@property (nonatomic, readonly) NSUInteger revision;
@property (nonatomic, readonly) NSUInteger contaminationResetToken;
@property (nonatomic, copy) NSString *statusMessage;

@property (nonatomic, strong, nullable) SEMSpecimen *specimen;

- (void)tick:(NSTimeInterval)dt;

- (void)evac;
- (void)vent;
- (void)resetFault;
- (void)replaceFilament;
- (void)resetContamination;

- (void)setRoughingPumpOn:(BOOL)on;
- (void)setDiffusionPumpOn:(BOOL)on;
- (void)setHighVoltageOn:(BOOL)on;
- (void)setFilamentCurrent:(double)value;
- (void)setAcceleratingVoltageKV:(NSInteger)kv;
- (void)setMagnification:(double)value;
- (void)setWorkingDistanceMM:(double)value;
- (void)setSpotSize:(double)value;
- (void)setFocus:(double)value;
- (void)setStigmatorX:(double)value;
- (void)setStigmatorY:(double)value;
- (void)setStageX:(double)value;
- (void)setStageY:(double)value;
- (void)setStageZ:(double)value;
- (void)setTilt:(double)value;
- (void)setRotation:(double)value;
- (void)setBrightness:(double)value;
- (void)setContrast:(double)value;
- (void)setDetectorMode:(SEMDetectorMode)mode;
- (void)setScanMode:(SEMScanMode)mode;
- (void)setScanDuration:(double)value;
- (void)setGoldCoated:(BOOL)coated;

@end

NS_ASSUME_NONNULL_END
