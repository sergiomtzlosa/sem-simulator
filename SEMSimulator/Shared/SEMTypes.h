#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SEMVacuumState) {
    SEMVacuumStateVented = 0,
    SEMVacuumStateRoughing,
    SEMVacuumStateRoughVacuum,
    SEMVacuumStateDPWarmup,
    SEMVacuumStateHighVacuum,
    SEMVacuumStateVenting,
    SEMVacuumStateFault
};

typedef NS_ENUM(NSInteger, SEMScanMode) {
    SEMScanModeTV = 0,
    SEMScanModeSlow,
    SEMScanModePhoto
};

typedef NS_ENUM(NSInteger, SEMDetectorMode) {
    SEMDetectorModeSE = 0,
    SEMDetectorModeBSE
};

typedef NS_ENUM(NSInteger, SEMPhosphorMode) {
    SEMPhosphorModeGreen = 0,
    SEMPhosphorModeAmber,
    SEMPhosphorModeWhite
};

static inline NSString *SEMVacuumStateName(SEMVacuumState state) {
    switch (state) {
        case SEMVacuumStateVented: return @"VENTED";
        case SEMVacuumStateRoughing: return @"ROUGHING";
        case SEMVacuumStateRoughVacuum: return @"ROUGH VAC";
        case SEMVacuumStateDPWarmup: return @"DP WARMUP";
        case SEMVacuumStateHighVacuum: return @"HIGH VAC";
        case SEMVacuumStateVenting: return @"VENTING";
        case SEMVacuumStateFault: return @"FAULT";
    }
    return @"UNKNOWN";
}
