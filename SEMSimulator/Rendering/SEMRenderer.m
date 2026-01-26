#import "SEMRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "SEMPhysicsEngine.h"
#import "SEMSpecimen.h"
#import "ShaderTypes.h"
#import "TelemetryRenderer.h"

static const NSUInteger SEMScanSize = 1024;
static const NSUInteger SEMContaminationSize = 512;

static id<MTLTexture> SEMCreateTexture(id<MTLDevice> device, MTLPixelFormat format, NSUInteger width, NSUInteger height,
                                       MTLTextureUsage usage, MTLStorageMode storage) {
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:width height:height mipmapped:NO];
    desc.usage = usage;
    desc.storageMode = storage;
    return [device newTextureWithDescriptor:desc];
}

static void SEMClearTexture(id<MTLTexture> texture, id<MTLCommandBuffer> commandBuffer) {
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
}

@implementation SEMRenderer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _specimenPipeline;
    id<MTLRenderPipelineState> _crtPipeline;
    id<MTLRenderPipelineState> _presentPipeline;

    id<MTLTexture> _scanNew;
    id<MTLTexture> _scanAccum;
    id<MTLTexture> _crtA;
    id<MTLTexture> _crtB;
    id<MTLTexture> _overlay;
    id<MTLTexture> _contamination;
    id<MTLTexture> _lastPresentedTexture;
    id<MTLCommandBuffer> _lastCommandBuffer;
    TelemetryRenderer *_telemetry;

    uint8_t *_contaminationBytes;
    SEMSpecimen *_trackedSpecimen;
    NSUInteger _lastContaminationToken;
    NSUInteger _lastScanRevision;
    CFTimeInterval _scanStart;
    CFTimeInterval _scanHoldStart;
    CFTimeInterval _lastOverlayUpdate;
    CFTimeInterval _lastContaminationUpdate;
    BOOL _scanComplete;
    BOOL _wasInteractive;
    NSUInteger _lastRow;
    CGSize _crtSize;
    BOOL _crtCleared;
    NSString *_shaderError;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (!device) {
        _shaderError = @"Metal is unavailable on this system.";
        return self;
    }
    _device = device;
    _queue = [device newCommandQueue];
    _telemetry = [[TelemetryRenderer alloc] init];
    _lastScanRevision = NSUIntegerMax;
    _lastContaminationToken = NSUIntegerMax;
    _contaminationBytes = calloc(SEMContaminationSize * SEMContaminationSize, sizeof(uint8_t));

    _scanNew = SEMCreateTexture(device, MTLPixelFormatRGBA16Float, SEMScanSize, SEMScanSize,
                                MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead, MTLStorageModePrivate);
    _scanAccum = SEMCreateTexture(device, MTLPixelFormatRGBA16Float, SEMScanSize, SEMScanSize,
                                  MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead, MTLStorageModePrivate);
    _overlay = SEMCreateTexture(device, MTLPixelFormatRGBA8Unorm, 1024, 768,
                                MTLTextureUsageShaderRead, MTLStorageModeShared);
    _contamination = SEMCreateTexture(device, MTLPixelFormatR8Unorm, SEMContaminationSize, SEMContaminationSize,
                                      MTLTextureUsageShaderRead, MTLStorageModeShared);

    [self buildPipelines];
    return self;
}

- (void)dealloc {
    free(_contaminationBytes);
}

- (void)buildPipelines {
    NSError *error = nil;
    id<MTLLibrary> semLibrary = [self compileLibraryNamed:@"SEMShaders" error:&error];
    if (!semLibrary) {
        _shaderError = error.localizedDescription ?: @"Could not compile SEM shaders.";
        return;
    }
    id<MTLLibrary> crtLibrary = [self compileLibraryNamed:@"CRTShaders" error:&error];
    if (!crtLibrary) {
        _shaderError = error.localizedDescription ?: @"Could not compile CRT shaders.";
        return;
    }

    id<MTLFunction> vertex = [semLibrary newFunctionWithName:@"fullscreenVertex"];
    id<MTLFunction> specimenFragment = [semLibrary newFunctionWithName:@"specimenFragment"];
    id<MTLFunction> crtFragment = [crtLibrary newFunctionWithName:@"crtFragment"];
    id<MTLFunction> presentFragment = [crtLibrary newFunctionWithName:@"presentFragment"];
    if (!vertex || !specimenFragment || !crtFragment || !presentFragment) {
        _shaderError = @"Shader function lookup failed. Check SEMShaders.metal and CRTShaders.metal.";
        return;
    }

    MTLRenderPipelineDescriptor *specimenDesc = [[MTLRenderPipelineDescriptor alloc] init];
    specimenDesc.vertexFunction = vertex;
    specimenDesc.fragmentFunction = specimenFragment;
    specimenDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
    NSError *pipelineError = nil;
    _specimenPipeline = [_device newRenderPipelineStateWithDescriptor:specimenDesc error:&pipelineError];
    if (!_specimenPipeline) {
        _shaderError = pipelineError.localizedDescription ?: @"Specimen pipeline creation failed.";
        return;
    }

    MTLRenderPipelineDescriptor *crtDesc = [[MTLRenderPipelineDescriptor alloc] init];
    crtDesc.vertexFunction = vertex;
    crtDesc.fragmentFunction = crtFragment;
    crtDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    _crtPipeline = [_device newRenderPipelineStateWithDescriptor:crtDesc error:&pipelineError];
    if (!_crtPipeline) {
        _shaderError = pipelineError.localizedDescription ?: @"CRT pipeline creation failed.";
        return;
    }

    MTLRenderPipelineDescriptor *presentDesc = [[MTLRenderPipelineDescriptor alloc] init];
    presentDesc.vertexFunction = vertex;
    presentDesc.fragmentFunction = presentFragment;
    presentDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _presentPipeline = [_device newRenderPipelineStateWithDescriptor:presentDesc error:&pipelineError];
    if (!_presentPipeline) {
        _shaderError = pipelineError.localizedDescription ?: @"Present pipeline creation failed.";
    }
}

- (id<MTLLibrary>)compileLibraryNamed:(NSString *)name error:(NSError **)error {
    NSString *headerPath = [[NSBundle mainBundle] pathForResource:@"ShaderTypes" ofType:@"h"];
    NSString *sourcePath = [[NSBundle mainBundle] pathForResource:name ofType:@"metal.txt"];
    if (!headerPath || !sourcePath) {
        if (error) *error = [NSError errorWithDomain:@"SEM.Metal" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Missing bundled shader %@.metal.txt or ShaderTypes.h.", name]}];
        return nil;
    }
    NSString *header = [NSString stringWithContentsOfFile:headerPath encoding:NSUTF8StringEncoding error:error];
    NSString *source = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:error];
    if (!header || !source) return nil;
    source = [source stringByReplacingOccurrencesOfString:@"#include \"ShaderTypes.h\"" withString:@""];
    NSString *combined = [header stringByAppendingFormat:@"\n%@", source];
    MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
    options.fastMathEnabled = YES;
    NSError *compileError = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:combined options:options error:&compileError];
    if (!library) {
        if (error) *error = compileError;
        NSLog(@"Metal compile error (%@): %@", name, compileError);
    }
    return library;
}

- (void)ensureCRTTexturesForSize:(CGSize)size commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (CGSizeEqualToSize(size, _crtSize) && _crtA && _crtB) return;
    _crtSize = size;
    _crtA = SEMCreateTexture(_device, MTLPixelFormatRGBA8Unorm, (NSUInteger)MAX(size.width, 1), (NSUInteger)MAX(size.height, 1),
                             MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead, MTLStorageModeShared);
    _crtB = SEMCreateTexture(_device, MTLPixelFormatRGBA8Unorm, (NSUInteger)MAX(size.width, 1), (NSUInteger)MAX(size.height, 1),
                             MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead, MTLStorageModeShared);
    SEMClearTexture(_crtA, commandBuffer);
    SEMClearTexture(_crtB, commandBuffer);
    _crtCleared = YES;
}

- (void)restartSlowScanWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer now:(CFTimeInterval)now {
    SEMClearTexture(_scanAccum, commandBuffer);
    _scanStart = now;
    _scanHoldStart = 0;
    _scanComplete = NO;
    _lastRow = 0;
}

- (void)updateContaminationForEngine:(SEMPhysicsEngine *)engine specimen:(SEMSpecimen *)specimen now:(CFTimeInterval)now {
    if (!_contaminationBytes) return;
    BOOL reset = (specimen != _trackedSpecimen) || (engine.contaminationResetToken != _lastContaminationToken);
    if (reset) {
        memset(_contaminationBytes, 0, SEMContaminationSize * SEMContaminationSize);
        _trackedSpecimen = specimen;
        _lastContaminationToken = engine.contaminationResetToken;
        MTLRegion region = MTLRegionMake2D(0, 0, SEMContaminationSize, SEMContaminationSize);
        [_contamination replaceRegion:region mipmapLevel:0 withBytes:_contaminationBytes bytesPerRow:SEMContaminationSize];
    }
    if (now - _lastContaminationUpdate < 0.25) return;
    double dt = now - _lastContaminationUpdate;
    _lastContaminationUpdate = now;
    if (!engine.beamOn || !specimen || engine.magnification < 1500.0) return;

    double viewScale = 0.5 * pow(10.0 / MAX(engine.magnification, 10.0), 0.30);
    double centerX = 0.5 + (engine.stageX - 5.0) * 0.02;
    double centerY = 0.5 + (engine.stageY - 5.0) * 0.02;
    int x0 = (int)floor((centerX - viewScale) * SEMContaminationSize);
    int x1 = (int)ceil((centerX + viewScale) * SEMContaminationSize);
    int y0 = (int)floor((centerY - viewScale) * SEMContaminationSize);
    int y1 = (int)ceil((centerY + viewScale) * SEMContaminationSize);
    x0 = MAX(0, MIN((int)SEMContaminationSize - 1, x0));
    x1 = MAX(0, MIN((int)SEMContaminationSize, x1));
    y0 = MAX(0, MIN((int)SEMContaminationSize - 1, y0));
    y1 = MAX(0, MIN((int)SEMContaminationSize, y1));
    if (x1 <= x0 || y1 <= y0) return;

    double dose = (1.5 + 4.0 * (engine.magnification / 10000.0) * (0.4 + engine.spotSize / 7.0)) * MIN(dt, 0.5) / 0.25;
    for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
            int index = y * (int)SEMContaminationSize + x;
            int value = _contaminationBytes[index] + (int)lrint(dose);
            _contaminationBytes[index] = (uint8_t)MIN(255, value);
        }
    }
    MTLRegion region = MTLRegionMake2D(0, 0, SEMContaminationSize, SEMContaminationSize);
    [_contamination replaceRegion:region mipmapLevel:0 withBytes:_contaminationBytes bytesPerRow:SEMContaminationSize];
}

- (void)drawInView:(MTKView *)view
             engine:(SEMPhysicsEngine *)engine
           specimen:(SEMSpecimen *)specimen
       phosphorMode:(SEMPhosphorMode)phosphorMode
        interactive:(BOOL)interactive {
    if (!_specimenPipeline || !_crtPipeline || !_presentPipeline) return;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!drawable) return;
    CGSize drawableSize = view.drawableSize;
    if (drawableSize.width < 1 || drawableSize.height < 1) return;

    CFTimeInterval now = CACurrentMediaTime();
    id<MTLCommandBuffer> commandBuffer = [_queue commandBuffer];
    [self ensureCRTTexturesForSize:drawableSize commandBuffer:commandBuffer];

    if (now - _lastOverlayUpdate > 0.1) {
        [_telemetry updateTexture:_overlay engine:engine specimen:specimen];
        _lastOverlayUpdate = now;
    }
    [self updateContaminationForEngine:engine specimen:specimen now:now];

    SEMScanMode scanMode = engine.scanMode;
    BOOL tv = (scanMode == SEMScanModeTV);
    BOOL justFinishedInteractive = (!interactive && _wasInteractive);
    BOOL fastPreview = interactive || justFinishedInteractive;
    double progress = 1.0;
    BOOL slowScanning = NO;

    if (!tv && !fastPreview) {
        if (engine.revision != _lastScanRevision || specimen != _trackedSpecimen) {
            _lastScanRevision = engine.revision;
            [self restartSlowScanWithCommandBuffer:commandBuffer now:now];
        }
        double duration = MAX(engine.scanDuration, 0.5);
        if (!_scanComplete) {
            progress = MIN(MAX((now - _scanStart) / duration, 0.0), 1.0);
            if (progress >= 1.0) {
                progress = 1.0;
                _scanComplete = YES;
                _scanHoldStart = now;
            }
        }
        if (_scanComplete && scanMode == SEMScanModeSlow && now - _scanHoldStart > 1.2) {
            [self restartSlowScanWithCommandBuffer:commandBuffer now:now];
            progress = 0.0;
            _scanComplete = NO;
        }
        slowScanning = !_scanComplete && engine.beamOn;
    } else if (!tv && justFinishedInteractive) {
        // Zooming bypassed the slow scan. Restart it cleanly now that the
        // gesture has ended; this frame still shows the full fresh preview.
        [self restartSlowScanWithCommandBuffer:commandBuffer now:now];
        _lastScanRevision = engine.revision;
    }

    BOOL renderSpecimen = engine.beamOn && specimen && (tv || fastPreview || !_scanComplete);
    if (renderSpecimen) {
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = _scanNew;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];

        SEMShaderUniforms u = {0};
        double viewScale = 0.5 * pow(10.0 / MAX(engine.magnification, 10.0), 0.30);
        u.viewCenterX = 0.5f + (float)(engine.stageX - 5.0) * 0.02f;
        u.viewCenterY = 0.5f + (float)(engine.stageY - 5.0) * 0.02f;
        u.viewScale = (float)viewScale;
        u.rotation = (float)(engine.rotation * M_PI / 180.0);
        u.tilt = (float)(engine.tilt * M_PI / 180.0);
        u.focus = (float)engine.focus;
        u.stigmatorX = (float)engine.stigmatorX;
        u.stigmatorY = (float)engine.stigmatorY;
        u.kV = (float)engine.acceleratingVoltageKV;
        u.spot = (float)engine.spotSize;
        u.wd = (float)engine.workingDistanceMM;
        u.brightness = (float)engine.brightness;
        u.contrast = (float)engine.contrast;
        u.charge = (float)engine.charge;
        u.time = (float)now;
        u.scanProgress = (float)progress;
        u.textureWidth = (float)SEMScanSize;
        u.textureHeight = (float)SEMScanSize;
        u.meanZ = (float)(specimen.meanZ > 0 ? specimen.meanZ : 14.0);
        u.noiseAmount = tv ? 0.16f : 0.035f;
        u.detectorMode = (int)engine.detectorMode;
        u.goldCoated = engine.goldCoated ? 1 : 0;
        u.conductive = specimen.conductive ? 1 : 0;
        u.scanMode = (int)engine.scanMode;
        u.phosphorMode = (int)phosphorMode;

        [encoder setRenderPipelineState:_specimenPipeline];
        [encoder setFragmentBytes:&u length:sizeof(u) atIndex:0];
        [encoder setFragmentTexture:specimen.heightTexture atIndex:0];
        [encoder setFragmentTexture:specimen.normalTexture atIndex:1];
        [encoder setFragmentTexture:specimen.zTexture atIndex:2];
        [encoder setFragmentTexture:_contamination atIndex:3];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder endEncoding];

        if (!tv) {
            NSUInteger newRow = (NSUInteger)(progress * (double)SEMScanSize);
            newRow = MIN(newRow, SEMScanSize);
            if (newRow > _lastRow) {
                id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
                [blit copyFromTexture:_scanNew
                          sourceSlice:0
                          sourceLevel:0
                         sourceOrigin:MTLOriginMake(0, _lastRow, 0)
                           sourceSize:MTLSizeMake(SEMScanSize, newRow - _lastRow, 1)
                            toTexture:_scanAccum
                     destinationSlice:0
                     destinationLevel:0
                    destinationOrigin:MTLOriginMake(0, _lastRow, 0)];
                [blit endEncoding];
                _lastRow = newRow;
            }
        }
    } else {
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = _scanNew;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
        [encoder endEncoding];
    }

    id<MTLTexture> specimenTexture = (tv || fastPreview) ? _scanNew : _scanAccum;
    id<MTLTexture> history = _crtA;
    id<MTLTexture> destination = _crtB;

    float persistence = phosphorMode == SEMPhosphorModeGreen ? 0.86f : (phosphorMode == SEMPhosphorModeAmber ? 0.72f : 0.56f);
    if (fastPreview) {
        // Do not smear the previous zoom level across the viewport while the
        // operator is zooming; refresh the whole screen crisply each frame.
        persistence = MIN(persistence, 0.18f);
    }

    CRTShaderUniforms c = {0};
    c.width = (float)drawableSize.width;
    c.height = (float)drawableSize.height;
    c.time = (float)now;
    c.scanProgress = (float)progress;
    c.persistence = persistence;
    c.charge = (float)engine.charge;
    c.barrel = 0.10f;
    c.noiseAmount = tv ? 0.055f : 0.018f;
    c.scanMode = (int)engine.scanMode;
    c.phosphorMode = (int)phosphorMode;
    c.slowScanning = slowScanning ? 1 : 0;
    c.beamOn = engine.beamOn ? 1 : 0;
    c.sweepGlow = 0.8f;

    MTLRenderPassDescriptor *crtPass = [MTLRenderPassDescriptor renderPassDescriptor];
    crtPass.colorAttachments[0].texture = destination;
    crtPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    crtPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    crtPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLRenderCommandEncoder> crtEncoder = [commandBuffer renderCommandEncoderWithDescriptor:crtPass];
    [crtEncoder setRenderPipelineState:_crtPipeline];
    [crtEncoder setFragmentBytes:&c length:sizeof(c) atIndex:0];
    [crtEncoder setFragmentTexture:specimenTexture atIndex:0];
    [crtEncoder setFragmentTexture:history atIndex:1];
    [crtEncoder setFragmentTexture:_overlay atIndex:2];
    [crtEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [crtEncoder endEncoding];

    MTLRenderPassDescriptor *presentPass = [MTLRenderPassDescriptor renderPassDescriptor];
    presentPass.colorAttachments[0].texture = drawable.texture;
    presentPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    presentPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    presentPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLRenderCommandEncoder> presentEncoder = [commandBuffer renderCommandEncoderWithDescriptor:presentPass];
    [presentEncoder setRenderPipelineState:_presentPipeline];
    [presentEncoder setFragmentTexture:destination atIndex:0];
    [presentEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [presentEncoder endEncoding];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
    _lastPresentedTexture = destination;
    _lastCommandBuffer = commandBuffer;
    id<MTLTexture> swap = _crtA;
    _crtA = _crtB;
    _crtB = swap;
    _wasInteractive = interactive;
}

- (NSImage *)currentFrameImage {
    if (!_lastPresentedTexture) return nil;
    if (_lastCommandBuffer) [_lastCommandBuffer waitUntilCompleted];
    NSUInteger width = _lastPresentedTexture.width;
    NSUInteger height = _lastPresentedTexture.height;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:width
                                                                    pixelsHigh:height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:width * 4
                                                                  bitsPerPixel:32];
    if (!rep.bitmapData) return nil;
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [_lastPresentedTexture getBytes:rep.bitmapData bytesPerRow:width * 4 fromRegion:region mipmapLevel:0];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image addRepresentation:rep];
    return image;
}

@end
