#import "SEMPhysicsEngine.h"
#import "SEMSpecimen.h"
#import "SEMScaleMath.h"

static double SEMClamp(double v, double lo, double hi) {
    return MIN(MAX(v, lo), hi);
}

@implementation SEMPhysicsEngine {
    SEMVacuumState _vacuumState;
    double _pressurePa;
    BOOL _roughingPumpOn;
    BOOL _diffusionPumpOn;
    BOOL _highVoltageOn;
    BOOL _fault;
    double _dpWarmupRemaining;
    BOOL _autoEvac;
    BOOL _autoHighVoltage;
    double _vacuumFaultGrace;
    double _autoStatusAccumulator;

    double _filamentCurrent;
    double _filamentLife;
    double _emissionCurrent;
    NSInteger _acceleratingVoltageKV;

    double _magnification;
    double _workingDistanceMM;
    double _spotSize;
    double _focus;
    double _stigmatorX;
    double _stigmatorY;

    double _stageX;
    double _stageY;
    double _stageZ;
    double _tilt;
    double _rotation;

    double _brightness;
    double _contrast;
    SEMDetectorMode _detectorMode;
    SEMScanMode _scanMode;
    double _scanDuration;
    BOOL _goldCoated;
    double _charge;
    NSUInteger _revision;
    NSUInteger _contaminationResetToken;
    SEMSpecimen *_specimen;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _vacuumState = SEMVacuumStateVented;
        _pressurePa = 101325.0;
        _vacuumFaultGrace = 0.0;
        _filamentCurrent = 0.62;
        _filamentLife = 1.0;
        _acceleratingVoltageKV = 15;
        _magnification = 1000.0;
        _workingDistanceMM = 15.0;
        _spotSize = 4.0;
        _focus = 0.0;
        _stageX = 5.0;
        _stageY = 5.0;
        _stageZ = 0.0;
        _scanMode = SEMScanModeTV;
        _scanDuration = 5.0;
        _detectorMode = SEMDetectorModeSE;
        _revision = 1;
        _contaminationResetToken = 1;
        self.statusMessage = @"SYSTEM READY - CHAMBER VENTED";
    }
    return self;
}

- (void)bumpRevision {
    _revision++;
}

#pragma mark - Read-only state

- (SEMVacuumState)vacuumState { return _vacuumState; }
- (double)pressurePa { return _pressurePa; }
- (BOOL)roughingPumpOn { return _roughingPumpOn; }
- (BOOL)diffusionPumpOn { return _diffusionPumpOn; }
- (BOOL)highVoltageOn { return _highVoltageOn; }
- (BOOL)fault { return _fault; }
- (double)dpWarmupRemaining { return MAX(_dpWarmupRemaining, 0.0); }
- (BOOL)autoHighVoltage { return _autoHighVoltage; }
- (double)filamentCurrent { return _filamentCurrent; }
- (double)filamentLife { return _filamentLife; }
- (double)emissionCurrent { return _emissionCurrent; }
- (NSInteger)acceleratingVoltageKV { return _acceleratingVoltageKV; }
- (double)magnification { return _magnification; }
- (double)workingDistanceMM { return _workingDistanceMM; }
- (double)spotSize { return _spotSize; }
- (double)focus { return _focus; }
- (double)stigmatorX { return _stigmatorX; }
- (double)stigmatorY { return _stigmatorY; }
- (double)stageX { return _stageX; }
- (double)stageY { return _stageY; }
- (double)stageZ { return _stageZ; }
- (double)tilt { return _tilt; }
- (double)rotation { return _rotation; }
- (double)brightness { return _brightness; }
- (double)contrast { return _contrast; }
- (SEMDetectorMode)detectorMode { return _detectorMode; }
- (SEMScanMode)scanMode { return _scanMode; }
- (double)scanDuration { return _scanDuration; }
- (BOOL)goldCoated { return _goldCoated; }
- (double)charge { return _charge; }
- (NSUInteger)revision { return _revision; }
- (NSUInteger)contaminationResetToken { return _contaminationResetToken; }

- (BOOL)vacuumReady {
    return !_fault && _pressurePa < 5e-3;
}

- (BOOL)beamOn {
    return _highVoltageOn && self.vacuumReady && _filamentLife > 0.001 && _emissionCurrent > 0.5 && !_fault;
}

- (SEMSpecimen *)specimen { return _specimen; }

- (void)setSpecimen:(SEMSpecimen *)specimen {
    _specimen = specimen;
    _charge = 0.0;
    _contaminationResetToken++;
    [self bumpRevision];
    if (specimen) {
        self.statusMessage = [NSString stringWithFormat:@"SPECIMEN LOADED: %@", specimen.name];
    }
}

#pragma mark - Vacuum controls

- (void)evac {
    if (_fault) {
        self.statusMessage = @"RESET FAULT BEFORE EVAC";
        return;
    }

    // EVAC is a one-press automatic sequence: rough vacuum, diffusion pump
    // warm-up, high vacuum, then high voltage. Re-pressing it while the
    // sequence is already running must not restart the diffusion-pump timer.
    _autoEvac = YES;
    _autoHighVoltage = YES;
    _autoStatusAccumulator = 0.0;

    if (self.vacuumReady) {
        self.statusMessage = @"HIGH VACUUM READY - AUTO HV";
        [self bumpRevision];
        return;
    }
    if (_diffusionPumpOn || _vacuumState == SEMVacuumStateDPWarmup) {
        self.statusMessage = @"EVAC ALREADY IN PROGRESS";
        [self bumpRevision];
        return;
    }

    _roughingPumpOn = YES;
    _diffusionPumpOn = NO;
    _dpWarmupRemaining = 0.0;
    _vacuumFaultGrace = 0.0;
    _vacuumState = (_pressurePa > 1000.0) ? SEMVacuumStateRoughing : SEMVacuumStateRoughVacuum;
    self.statusMessage = @"EVAC SEQUENCE STARTED - AUTO HV";
    [self bumpRevision];
}

- (void)vent {
    _autoEvac = NO;
    _autoHighVoltage = NO;
    _autoStatusAccumulator = 0.0;
    _highVoltageOn = NO;
    _diffusionPumpOn = NO;
    _roughingPumpOn = NO;
    _dpWarmupRemaining = 0.0;
    _fault = NO;
    _vacuumState = SEMVacuumStateVenting;
    self.statusMessage = @"VENTING CHAMBER";
    [self bumpRevision];
}

- (void)resetFault {
    _fault = NO;
    _highVoltageOn = NO;
    if (_pressurePa < 5e-3) {
        _vacuumState = SEMVacuumStateHighVacuum;
    } else if (_pressurePa < 1000.0) {
        _vacuumState = SEMVacuumStateRoughVacuum;
    } else {
        _vacuumState = SEMVacuumStateVented;
    }
    self.statusMessage = @"FAULT RESET";
    [self bumpRevision];
}

- (void)replaceFilament {
    _filamentLife = 1.0;
    _filamentCurrent = 0.55;
    self.statusMessage = @"FILAMENT REPLACED";
    [self bumpRevision];
}

- (void)resetContamination {
    _contaminationResetToken++;
    self.statusMessage = @"CONTAMINATION MAP CLEARED";
    [self bumpRevision];
}

- (void)setRoughingPumpOn:(BOOL)on {
    if (on) {
        _autoEvac = NO;
        _roughingPumpOn = YES;
        if (_vacuumState == SEMVacuumStateVented || _vacuumState == SEMVacuumStateVenting) {
            _vacuumState = SEMVacuumStateRoughing;
        }
        self.statusMessage = @"ROTARY PUMP ON";
    } else {
        _roughingPumpOn = NO;
        if (_diffusionPumpOn) {
            _diffusionPumpOn = NO;
            _dpWarmupRemaining = 0.0;
            if (_vacuumState == SEMVacuumStateDPWarmup || _vacuumState == SEMVacuumStateHighVacuum) {
                _vacuumState = SEMVacuumStateRoughVacuum;
            }
        }
        self.statusMessage = @"ROTARY PUMP OFF";
    }
    [self bumpRevision];
}

- (void)setDiffusionPumpOn:(BOOL)on {
    if (on) {
        if (!_roughingPumpOn || _pressurePa >= 10.0) {
            self.statusMessage = @"DP INTERLOCK: ROUGH VACUUM REQUIRED";
            [self bumpRevision];
            return;
        }
        _diffusionPumpOn = YES;
        _dpWarmupRemaining = 8.0;
        _vacuumState = SEMVacuumStateDPWarmup;
        self.statusMessage = @"DIFFUSION PUMP WARMING";
    } else {
        _diffusionPumpOn = NO;
        _dpWarmupRemaining = 0.0;
        if (_vacuumState == SEMVacuumStateDPWarmup || _vacuumState == SEMVacuumStateHighVacuum) {
            _vacuumState = SEMVacuumStateRoughVacuum;
        }
        self.statusMessage = @"DIFFUSION PUMP OFF";
    }
    [self bumpRevision];
}

- (void)setHighVoltageOn:(BOOL)on {
    if (on) {
        if (!self.vacuumReady) {
            self.statusMessage = @"HV INTERLOCK: VACUUM NOT READY";
            _highVoltageOn = NO;
        } else if (_filamentLife <= 0.001) {
            self.statusMessage = @"HV INTERLOCK: FILAMENT OPEN";
            _highVoltageOn = NO;
        } else if (_fault) {
            self.statusMessage = @"HV INTERLOCK: FAULT ACTIVE";
            _highVoltageOn = NO;
        } else {
            _highVoltageOn = YES;
            self.statusMessage = @"HIGH VOLTAGE ON";
        }
    } else {
        _highVoltageOn = NO;
        _autoHighVoltage = NO;
        self.statusMessage = @"HIGH VOLTAGE OFF";
    }
    [self bumpRevision];
}

#pragma mark - Optics and stage

- (void)setFilamentCurrent:(double)value {
    _filamentCurrent = SEMClamp(value, 0.0, 1.0);
    [self bumpRevision];
}

- (void)setAcceleratingVoltageKV:(NSInteger)kv {
    NSArray<NSNumber *> *steps = [SEMScaleMath voltageSteps];
    NSInteger nearest = steps.firstObject.integerValue;
    for (NSNumber *n in steps) {
        if (labs((long)(n.integerValue - kv)) < labs((long)(nearest - kv))) nearest = n.integerValue;
    }
    _acceleratingVoltageKV = nearest;
    [self bumpRevision];
}

- (void)setMagnification:(double)value {
    _magnification = SEMClamp(value, 10.0, 100000.0);
    [self bumpRevision];
}

- (void)setWorkingDistanceMM:(double)value {
    _workingDistanceMM = SEMClamp(value, 8.0, 48.0);
    [self bumpRevision];
}

- (void)setSpotSize:(double)value {
    _spotSize = SEMClamp(value, 0.0, 7.0);
    [self bumpRevision];
}

- (void)setFocus:(double)value {
    _focus = SEMClamp(value, -1.0, 1.0);
    [self bumpRevision];
}

- (void)setStigmatorX:(double)value {
    _stigmatorX = SEMClamp(value, -1.0, 1.0);
    [self bumpRevision];
}

- (void)setStigmatorY:(double)value {
    _stigmatorY = SEMClamp(value, -1.0, 1.0);
    [self bumpRevision];
}

- (void)setStageX:(double)value {
    _stageX = SEMClamp(value, 0.0, 10.0);
    [self bumpRevision];
}

- (void)setStageY:(double)value {
    _stageY = SEMClamp(value, 0.0, 10.0);
    [self bumpRevision];
}

- (void)setStageZ:(double)value {
    _stageZ = SEMClamp(value, -1.0, 1.0);
    [self bumpRevision];
}

- (void)setTilt:(double)value {
    _tilt = SEMClamp(value, -10.0, 90.0);
    [self bumpRevision];
}

- (void)setRotation:(double)value {
    _rotation = fmod(value, 360.0);
    if (_rotation < 0) _rotation += 360.0;
    [self bumpRevision];
}

- (void)setBrightness:(double)value {
    _brightness = SEMClamp(value, -1.0, 1.0);
    [self bumpRevision];
}

- (void)setContrast:(double)value {
    _contrast = SEMClamp(value, -1.0, 1.0);
    [self bumpRevision];
}

- (void)setDetectorMode:(SEMDetectorMode)mode {
    _detectorMode = (mode == SEMDetectorModeBSE) ? SEMDetectorModeBSE : SEMDetectorModeSE;
    [self bumpRevision];
}

- (void)setScanMode:(SEMScanMode)mode {
    _scanMode = mode;
    [self bumpRevision];
}

- (void)setScanDuration:(double)value {
    _scanDuration = SEMClamp(value, 1.0, 15.0);
    [self bumpRevision];
}

- (void)setGoldCoated:(BOOL)coated {
    _goldCoated = coated;
    [self bumpRevision];
}

#pragma mark - Simulation

- (void)tick:(NSTimeInterval)dt {
    dt = SEMClamp(dt, 0.0, 0.25);
    if (dt <= 0.0) return;

    double target = _pressurePa;
    double tau = 90.0;

    if (_vacuumState == SEMVacuumStateVenting) {
        target = 101325.0;
        tau = 0.75;
    } else if (_vacuumState == SEMVacuumStateVented) {
        target = 101325.0;
        tau = 20.0;
    } else if (_vacuumState == SEMVacuumStateFault) {
        target = _pressurePa;
        tau = 100.0;
    } else if (_diffusionPumpOn && _dpWarmupRemaining <= 0.0) {
        target = 1.0e-4;
        tau = 1.5;
    } else if (_roughingPumpOn) {
        target = 1.0;
        tau = 2.5;
    } else {
        target = MAX(_pressurePa, 1.0);
        tau = 120.0;
    }

    _pressurePa += (target - _pressurePa) * (1.0 - exp(-dt / tau));
    _pressurePa = MAX(_pressurePa, 1.0e-6);

    if (_vacuumState == SEMVacuumStateVenting && _pressurePa > 90000.0) {
        _vacuumState = SEMVacuumStateVented;
        self.statusMessage = @"CHAMBER VENTED";
    } else if (_vacuumState == SEMVacuumStateRoughing && _pressurePa < 5.0) {
        _vacuumState = SEMVacuumStateRoughVacuum;
    }

    if (_autoEvac && _pressurePa < 10.0 && !_diffusionPumpOn && _roughingPumpOn) {
        _diffusionPumpOn = YES;
        _dpWarmupRemaining = 8.0;
        _vacuumState = SEMVacuumStateDPWarmup;
        self.statusMessage = @"DIFFUSION PUMP WARMING";
    }

    if (_vacuumState == SEMVacuumStateDPWarmup) {
        _dpWarmupRemaining -= dt;
        if (_dpWarmupRemaining <= 0.0) {
            _dpWarmupRemaining = 0.0;
            _vacuumState = SEMVacuumStateHighVacuum;
            _autoEvac = NO;
            _vacuumFaultGrace = 18.0;
            self.statusMessage = @"HIGH VACUUM READY";
        }
    }

    // Keep the operator informed while the automatic EVAC/HV sequence runs.
    if (_autoHighVoltage && !_highVoltageOn && !_fault) {
        _autoStatusAccumulator += dt;
        if (_autoStatusAccumulator >= 0.4) {
            _autoStatusAccumulator = 0.0;
            if (_vacuumState == SEMVacuumStateDPWarmup) {
                self.statusMessage = [NSString stringWithFormat:@"EVAC: DIFFUSION PUMP WARMING %.0fs",
                                      ceil(_dpWarmupRemaining)];
            } else if (_vacuumState == SEMVacuumStateRoughing || _vacuumState == SEMVacuumStateRoughVacuum) {
                self.statusMessage = [NSString stringWithFormat:@"EVAC: ROUGH VACUUM %.2g Pa", _pressurePa];
            } else if (_vacuumState == SEMVacuumStateHighVacuum) {
                self.statusMessage = [NSString stringWithFormat:@"EVAC: PUMPING DOWN %.2g Pa", _pressurePa];
            }
        }
    }

    if (_vacuumFaultGrace > 0.0) {
        _vacuumFaultGrace = MAX(0.0, _vacuumFaultGrace - dt);
    }

    if (_vacuumState == SEMVacuumStateHighVacuum && _vacuumFaultGrace <= 0.0 && _pressurePa > 1.0e-2) {
        _fault = YES;
        _vacuumState = SEMVacuumStateFault;
        _highVoltageOn = NO;
        self.statusMessage = @"VACUUM FAULT - HV TRIPPED";
    }

    if (_filamentLife > 0.0) {
        double drive = SEMClamp((_filamentCurrent - 0.18) / 0.62, 0.0, 1.0);
        double smooth = drive * drive * (3.0 - 2.0 * drive);
        _emissionCurrent = 80.0 * smooth;
        if (_filamentCurrent > 0.85) {
            _filamentLife -= dt * (_filamentCurrent - 0.85) * 0.02;
        }
        if (_filamentLife <= 0.0) {
            _filamentLife = 0.0;
            _emissionCurrent = 0.0;
            _highVoltageOn = NO;
            self.statusMessage = @"FILAMENT BURNT OUT";
        }
    } else {
        _emissionCurrent = 0.0;
    }

    if (_autoHighVoltage && _highVoltageOn) {
        _autoHighVoltage = NO;
    }
    if (_autoHighVoltage && !_fault && self.vacuumReady && _filamentLife > 0.001) {
        [self setHighVoltageOn:YES];
        if (_highVoltageOn) {
            _autoHighVoltage = NO;
            self.statusMessage = @"HIGH VACUUM READY - HV ON";
        }
    }

    if (_highVoltageOn && !self.vacuumReady) {
        _highVoltageOn = NO;
        self.statusMessage = @"HV TRIP - VACUUM INTERLOCK";
    }

    BOOL specimenConductive = _specimen ? _specimen.conductive : NO;
    if (self.beamOn && _specimen && !specimenConductive) {
        double rate = (0.012 + 0.050 * (_acceleratingVoltageKV / 25.0)) * (0.35 + _spotSize / 7.0);
        if (_goldCoated) rate *= 0.04;
        _charge += rate * dt;
    } else {
        double decay = (specimenConductive || _goldCoated) ? 2.2 : 0.45;
        _charge *= exp(-dt * decay);
    }
    _charge = SEMClamp(_charge, 0.0, 1.0);
}

@end
