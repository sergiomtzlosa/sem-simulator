#import "ProceduralSampleGenerator.h"
#import "AISampleRecipe.h"
#import "SEMSpecimen.h"
#import <math.h>

static const int SEMMapSize = 2048;

static inline float SEMClampf(float v, float lo, float hi) { return fminf(fmaxf(v, lo), hi); }
static inline float SEMLerpf(float a, float b, float t) { return a + (b - a) * t; }
static inline float SEMFractf(float v) { return v - floorf(v); }
static inline float SEMSmooth(float a, float b, float x) {
    float t = SEMClampf((x - a) / (b - a), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

static float SEMHash2(int x, int y, uint32_t seed) {
    uint32_t h = (uint32_t)x * 374761393u ^ (uint32_t)y * 668265263u ^ seed;
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= h >> 16;
    return (float)(h & 0x00FFFFFFu) / 16777215.0f;
}

static float SEMValueNoise(float x, float y, uint32_t seed) {
    int xi = (int)floorf(x);
    int yi = (int)floorf(y);
    float xf = x - (float)xi;
    float yf = y - (float)yi;
    float u = xf * xf * (3.0f - 2.0f * xf);
    float v = yf * yf * (3.0f - 2.0f * yf);
    float a = SEMHash2(xi, yi, seed);
    float b = SEMHash2(xi + 1, yi, seed);
    float c = SEMHash2(xi, yi + 1, seed);
    float d = SEMHash2(xi + 1, yi + 1, seed);
    return SEMLerpf(SEMLerpf(a, b, u), SEMLerpf(c, d, u), v);
}

static float SEMFbm(float x, float y, int octaves, uint32_t seed) {
    float sum = 0.0f;
    float amp = 0.5f;
    float freq = 1.0f;
    float norm = 0.0f;
    for (int i = 0; i < octaves; i++) {
        sum += amp * SEMValueNoise(x * freq, y * freq, seed + (uint32_t)i * 131u);
        norm += amp;
        freq *= 2.02f;
        amp *= 0.5f;
    }
    return sum / MAX(norm, 0.0001f);
}

typedef struct {
    float f1;
    float f2;
    float cell;
} SEMWorley;

static SEMWorley SEMWorleyNoise(float x, float y, uint32_t seed) {
    int xi = (int)floorf(x);
    int yi = (int)floorf(y);
    float f1 = 1e9f;
    float f2 = 1e9f;
    float cell = 0.0f;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int cx = xi + dx;
            int cy = yi + dy;
            float px = (float)cx + SEMHash2(cx, cy, seed);
            float py = (float)cy + SEMHash2(cx, cy, seed + 17u);
            float ddx = x - px;
            float ddy = y - py;
            float d = sqrtf(ddx * ddx + ddy * ddy);
            if (d < f1) {
                f2 = f1;
                f1 = d;
                cell = SEMHash2(cx, cy, seed + 91u);
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
    return (SEMWorley){f1, f2, cell};
}

@implementation ProceduralSampleGenerator {
    id<MTLDevice> _device;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) _device = device;
    return self;
}

- (nullable SEMSpecimen *)generateSpecimenWithRecipe:(AISampleRecipe *)recipe error:(NSError **)error {
    if (!_device) {
        if (error) *error = [NSError errorWithDomain:@"SEM.AI" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Metal device unavailable."}];
        return nil;
    }

    const int N = SEMMapSize;
    const int count = N * N;
    float *height = calloc((size_t)count, sizeof(float));
    float *zmap = calloc((size_t)count, sizeof(float));
    uint8_t *normalBytes = calloc((size_t)count * 4, sizeof(uint8_t));
    uint8_t *heightBytes = calloc((size_t)count, sizeof(uint8_t));
    uint8_t *zBytes = calloc((size_t)count, sizeof(uint8_t));
    uint8_t *thumb = calloc((size_t)256 * 256 * 4, sizeof(uint8_t));
    if (!height || !zmap || !normalBytes || !heightBytes || !zBytes || !thumb) {
        free(height); free(zmap); free(normalBytes); free(heightBytes); free(zBytes); free(thumb);
        if (error) *error = [NSError errorWithDomain:@"SEM.AI" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Out of memory while synthesizing specimen."}];
        return nil;
    }

    NSString *templateName = recipe.templateName ?: @"fracture";
    uint32_t seed = (uint32_t)(recipe.seed ?: 1);
    float roughness = (float)recipe.roughness;
    float spikes = (float)recipe.spikes;
    float pores = (float)recipe.pores;
    float cracks = (float)recipe.cracks;
    float fibers = (float)recipe.fibers;
    float grain = (float)recipe.grain;
    float meanZ = (float)recipe.meanZ;

    for (int y = 0; y < N; y++) {
        for (int x = 0; x < N; x++) {
            int i = y * N + x;
            float p = ((float)x + 0.5f) / (float)N;
            float q = ((float)y + 0.5f) / (float)N;
            float cx = p - 0.5f;
            float cy = q - 0.5f;
            float n = SEMFbm(p * 6.0f, q * 6.0f, 5, seed);
            float h = 0.5f;
            float z = SEMClampf((meanZ + (n - 0.5f) * 6.0f) / 30.0f, 0.04f, 1.0f);

            if ([templateName isEqualToString:@"pollen"]) {
                float d = sqrtf(cx * cx + cy * cy) * 2.0f;
                float sphere = sqrtf(MAX(0.0f, 1.0f - d * d));
                float theta = atan2f(cy, cx);
                float angular = 0.5f + 0.5f * sinf(theta * 22.0f + n * 5.0f);
                float spike = powf(angular, 10.0f) * spikes * SEMSmooth(1.10f, 0.55f, d);
                SEMWorley w = SEMWorleyNoise(p * 28.0f, q * 28.0f, seed + 5u);
                float pore = SEMSmooth(0.16f, 0.42f, w.f1) * pores * sphere;
                h = sphere * 0.46f + spike * 0.36f + (n - 0.5f) * 0.10f * roughness - pore * 0.16f;
                z = SEMClampf(0.06f + n * 0.10f + (w.f1 < 0.10f ? 0.22f : 0.0f), 0.03f, 0.55f);
            } else if ([templateName isEqualToString:@"diatom"]) {
                float r = sqrtf(cx * cx + (cy * 1.25f) * (cy * 1.25f)) * 2.0f;
                float mask = SEMSmooth(1.0f, 0.70f, r);
                float theta = atan2f(cy, cx);
                SEMWorley w = SEMWorleyNoise(p * 34.0f, q * 34.0f, seed + 9u);
                float ribs = 0.5f + 0.5f * sinf(theta * 34.0f + n * 2.0f);
                float pore = SEMSmooth(0.12f, 0.38f, w.f1) * pores;
                h = mask * (0.30f + ribs * 0.18f * (1.0f - pore) + (n - 0.5f) * 0.12f * roughness);
                z = SEMClampf(0.10f + n * 0.12f, 0.03f, 0.5f);
            } else if ([templateName isEqualToString:@"foram"]) {
                float r = sqrtf(cx * cx + cy * cy) * 2.0f;
                float theta = atan2f(cy, cx);
                float mask = SEMSmooth(1.05f, 0.72f, r);
                float spiral = 0.5f + 0.5f * sinf(theta * 7.0f + r * 20.0f + n * 2.5f);
                float chamber = SEMSmooth(0.20f, 0.52f, spiral);
                SEMWorley w = SEMWorleyNoise(p * 30.0f, q * 30.0f, seed + 19u);
                float pore = SEMSmooth(0.10f, 0.34f, w.f1) * pores;
                h = mask * (0.20f + chamber * 0.38f + (n - 0.5f) * 0.10f * roughness - pore * 0.12f);
                z = SEMClampf(0.08f + chamber * 0.34f + n * 0.08f, 0.03f, 0.7f);
            } else if ([templateName isEqualToString:@"circuit"]) {
                float gx = fabsf(SEMFractf(p * 10.0f) - 0.5f);
                float gy = fabsf(SEMFractf(q * 10.0f) - 0.5f);
                float dist = fminf(gx, gy);
                float trace = 1.0f - SEMSmooth(0.02f, 0.10f, dist);
                float fx = SEMFractf(p * 10.0f) - 0.5f;
                float fy = SEMFractf(q * 10.0f) - 0.5f;
                float pad = 1.0f - SEMSmooth(0.05f, 0.15f, sqrtf(fx * fx + fy * fy));
                float cell = SEMHash2((int)floorf(p * 10.0f), (int)floorf(q * 10.0f), seed);
                h = 0.14f + trace * 0.56f + pad * 0.22f + (n - 0.5f) * 0.04f + cell * 0.04f * roughness;
                z = SEMClampf(0.12f + trace * 0.68f + pad * 0.16f + n * 0.04f, 0.05f, 1.0f);
            } else if ([templateName isEqualToString:@"powder"]) {
                SEMWorley w = SEMWorleyNoise(p * 11.0f, q * 11.0f, seed + 11u);
                float grainShape = 1.0f - SEMSmooth(0.0f, 0.70f, w.f1);
                h = 0.12f + grainShape * 0.62f * (0.7f + grain * 0.3f) + (n - 0.5f) * 0.12f * roughness;
                z = SEMClampf(0.12f + w.cell * 0.68f, 0.04f, 0.95f);
            } else if ([templateName isEqualToString:@"crystal"]) {
                SEMWorley w = SEMWorleyNoise(p * 7.0f, q * 7.0f, seed + 13u);
                float facet = 0.5f + 0.5f * sinf((p + q) * 34.0f + w.cell * 6.283f);
                h = 0.18f + w.cell * 0.38f * (0.65f + grain * 0.35f) + facet * 0.16f * roughness;
                z = SEMClampf(0.15f + w.cell * 0.75f, 0.05f, 0.98f);
            } else if ([templateName isEqualToString:@"fiber"]) {
                float ridges = 0.5f + 0.5f * sinf(q * 42.0f + n * 4.0f);
                h = 0.42f + (ridges - 0.5f) * 0.42f * (0.4f + fibers) + (n - 0.5f) * 0.14f * roughness;
                z = SEMClampf((meanZ + (n - 0.5f) * 4.0f) / 30.0f, 0.04f, 0.8f);
            } else if ([templateName isEqualToString:@"tissue"]) {
                SEMWorley w = SEMWorleyNoise(p * 9.0f, q * 9.0f, seed + 15u);
                float membrane = SEMSmooth(0.0f, 0.12f, w.f2 - w.f1);
                h = 0.32f + membrane * 0.16f + (n - 0.5f) * 0.12f * roughness;
                z = SEMClampf(0.05f + n * 0.10f + membrane * 0.04f, 0.03f, 0.4f);
            } else if ([templateName isEqualToString:@"bone"]) {
                SEMWorley w = SEMWorleyNoise(p * 7.0f, q * 7.0f, seed + 21u);
                float strut = SEMSmooth(0.0f, 0.16f, w.f2 - w.f1);
                float marrow = SEMSmooth(0.18f, 0.55f, w.f1);
                h = 0.18f + strut * 0.52f + (n - 0.5f) * 0.10f * roughness - marrow * 0.12f * pores;
                z = SEMClampf(0.08f + strut * 0.30f + w.cell * 0.16f, 0.03f, 0.8f);
            } else if ([templateName isEqualToString:@"wing"]) {
                float rowCoord = q * 15.0f + SEMHash2((int)floorf(p * 9.0f), (int)floorf(q * 15.0f), seed + 23u) * 0.9f;
                float row = SEMFractf(rowCoord);
                float ridge = 1.0f - SEMSmooth(0.0f, 0.10f, fabsf(row - 0.5f));
                float cell = SEMHash2((int)floorf(p * 9.0f), (int)floorf(q * 15.0f), seed + 27u);
                h = 0.22f + ridge * 0.32f + cell * 0.14f + (n - 0.5f) * 0.08f * roughness;
                z = SEMClampf(0.08f + ridge * 0.26f + cell * 0.18f, 0.03f, 0.65f);
            } else {
                SEMWorley w = SEMWorleyNoise(p * 9.0f, q * 9.0f, seed + 3u);
                float ridged = 1.0f - fabsf(2.0f * SEMFbm(p * 4.0f, q * 4.0f, 5, seed + 7u) - 1.0f);
                float inside = SEMSmooth(0.0f, 0.08f, w.f2 - w.f1);
                float crack = 1.0f - inside;
                h = 0.22f + ridged * 0.34f + w.cell * 0.16f * roughness - crack * 0.34f * cracks;
                z = SEMClampf((meanZ + (w.cell - 0.5f) * 8.0f) / 30.0f, 0.04f, 1.0f);
            }

            height[i] = h;
            zmap[i] = SEMClampf(z, 0.0f, 1.0f);
        }
    }

    float hmin = 1e9f, hmax = -1e9f;
    for (int i = 0; i < count; i++) {
        hmin = fminf(hmin, height[i]);
        hmax = fmaxf(hmax, height[i]);
    }
    float range = fmaxf(hmax - hmin, 0.0001f);
    for (int i = 0; i < count; i++) {
        height[i] = SEMClampf((height[i] - hmin) / range, 0.0f, 1.0f);
    }

    const float normalStrength = (2.2f + roughness * 3.0f) * ((float)N / 512.0f);
    for (int y = 0; y < N; y++) {
        for (int x = 0; x < N; x++) {
            int i = y * N + x;
            int xl = MAX(0, x - 1), xr = MIN(N - 1, x + 1);
            int yu = MAX(0, y - 1), yd = MIN(N - 1, y + 1);
            float dx = height[y * N + xr] - height[y * N + xl];
            float dy = height[yd * N + x] - height[yu * N + x];
            float nx = -dx * normalStrength;
            float ny = -dy * normalStrength;
            float nz = 1.0f;
            float len = sqrtf(nx * nx + ny * ny + nz * nz);
            nx /= len; ny /= len; nz /= len;
            normalBytes[i * 4 + 0] = (uint8_t)SEMClampf((nx * 0.5f + 0.5f) * 255.0f, 0, 255);
            normalBytes[i * 4 + 1] = (uint8_t)SEMClampf((ny * 0.5f + 0.5f) * 255.0f, 0, 255);
            normalBytes[i * 4 + 2] = (uint8_t)SEMClampf((nz * 0.5f + 0.5f) * 255.0f, 0, 255);
            normalBytes[i * 4 + 3] = 255;
            heightBytes[i] = (uint8_t)SEMClampf(height[i] * 255.0f, 0, 255);
            zBytes[i] = (uint8_t)SEMClampf(zmap[i] * 255.0f, 0, 255);
        }
    }

    for (int y = 0; y < 256; y++) {
        for (int x = 0; x < 256; x++) {
            int sx = MIN(N - 1, x * N / 256);
            int sy = MIN(N - 1, y * N / 256);
            int si = sy * N + sx;
            float h = height[si];
            float nz = ((float)normalBytes[si * 4 + 2] / 255.0f) * 2.0f - 1.0f;
            float edge = 1.0f - nz;
            float signal = SEMClampf(0.16f + h * 0.58f + edge * 0.55f, 0.0f, 1.0f);
            int ti = (y * 256 + x) * 4;
            thumb[ti + 0] = (uint8_t)(signal * 235.0f);
            thumb[ti + 1] = (uint8_t)(signal * 245.0f);
            thumb[ti + 2] = (uint8_t)(signal * 220.0f);
            thumb[ti + 3] = 255;
        }
    }

    MTLTextureDescriptor *heightDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                                                          width:N height:N mipmapped:NO];
    heightDesc.usage = MTLTextureUsageShaderRead;
    heightDesc.storageMode = MTLStorageModeShared;
    id<MTLTexture> heightTexture = [_device newTextureWithDescriptor:heightDesc];

    MTLTextureDescriptor *normalDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:N height:N mipmapped:NO];
    normalDesc.usage = MTLTextureUsageShaderRead;
    normalDesc.storageMode = MTLStorageModeShared;
    id<MTLTexture> normalTexture = [_device newTextureWithDescriptor:normalDesc];

    MTLTextureDescriptor *zDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                                                     width:N height:N mipmapped:NO];
    zDesc.usage = MTLTextureUsageShaderRead;
    zDesc.storageMode = MTLStorageModeShared;
    id<MTLTexture> zTexture = [_device newTextureWithDescriptor:zDesc];

    if (!heightTexture || !normalTexture || !zTexture) {
        free(height); free(zmap); free(normalBytes); free(heightBytes); free(zBytes); free(thumb);
        if (error) *error = [NSError errorWithDomain:@"SEM.AI" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Could not allocate specimen textures."}];
        return nil;
    }

    MTLRegion region = MTLRegionMake2D(0, 0, N, N);
    [heightTexture replaceRegion:region mipmapLevel:0 withBytes:heightBytes bytesPerRow:N];
    [normalTexture replaceRegion:region mipmapLevel:0 withBytes:normalBytes bytesPerRow:N * 4];
    [zTexture replaceRegion:region mipmapLevel:0 withBytes:zBytes bytesPerRow:N];

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:256
                                                                    pixelsHigh:256
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:256 * 4
                                                                  bitsPerPixel:32];
    if (rep.bitmapData) memcpy(rep.bitmapData, thumb, 256 * 256 * 4);
    NSImage *thumbnail = [[NSImage alloc] initWithSize:NSMakeSize(256, 256)];
    [thumbnail addRepresentation:rep];

    SEMSpecimen *specimen = [[SEMSpecimen alloc] init];
    specimen.name = recipe.name.length > 0 ? recipe.name : @"Specimen";
    specimen.templateName = templateName;
    specimen.heightTexture = heightTexture;
    specimen.normalTexture = normalTexture;
    specimen.zTexture = zTexture;
    specimen.thumbnail = thumbnail;
    specimen.conductive = recipe.conductive;
    specimen.meanZ = recipe.meanZ;
    specimen.coatingRecommended = recipe.coatingRecommended;
    specimen.scaleMicrometers = recipe.scaleMicrometers;
    specimen.seed = recipe.seed;
    specimen.recipe = [recipe dictionaryRepresentation];

    free(height);
    free(zmap);
    free(normalBytes);
    free(heightBytes);
    free(zBytes);
    free(thumb);
    return specimen;
}

@end
