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

static BOOL SEMTextContainsWord(NSString *text, NSString *word) {
    if (text.length == 0 || word.length == 0) return NO;
    NSString *pattern = [NSString stringWithFormat:@"\\b%@\\b", word.lowercaseString];
    return [text.lowercaseString rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

static float SEMEllipseDistance(float x, float y, float cx, float cy, float rx, float ry) {
    float dx = (x - cx) / MAX(rx, 0.0001f);
    float dy = (y - cy) / MAX(ry, 0.0001f);
    return sqrtf(dx * dx + dy * dy);
}

static float SEMRotatedEllipseMask(float x, float y, float cx, float cy, float rx, float ry,
                                   float angle, float softness, float *outLocalX, float *outLocalY) {
    float dx = x - cx;
    float dy = y - cy;
    float c = cosf(angle);
    float s = sinf(angle);
    float lx = dx * c + dy * s;
    float ly = -dx * s + dy * c;
    if (outLocalX) *outLocalX = lx;
    if (outLocalY) *outLocalY = ly;
    float d = sqrtf((lx / MAX(rx, 0.0001f)) * (lx / MAX(rx, 0.0001f)) +
                    (ly / MAX(ry, 0.0001f)) * (ly / MAX(ry, 0.0001f)));
    return SEMSmooth(1.0f, 1.0f - softness, d);
}

static float SEMSegmentDistance(float x, float y, float ax, float ay, float bx, float by) {
    float pax = x - ax;
    float pay = y - ay;
    float bax = bx - ax;
    float bay = by - ay;
    float denom = bax * bax + bay * bay;
    float t = denom > 0.000001f ? SEMClampf((pax * bax + pay * bay) / denom, 0.0f, 1.0f) : 0.0f;
    float dx = pax - bax * t;
    float dy = pay - bay * t;
    return sqrtf(dx * dx + dy * dy);
}

typedef struct {
    float headX, headY, headRX, headRY;
    float thoraxX, thoraxY, thoraxRX, thoraxRY;
    float abdomenX, abdomenY, abdomenRX, abdomenRY;
    BOOL hasWings;
    BOOL hasAntennae;
    BOOL bigEyes;
    BOOL splitElytra;
    BOOL hasWaist;
    int legCount;
    float legStartX[8], legStartY[8], legEndX[8], legEndY[8];
    float legRadius;
    float wingRX, wingRY, wingAngle;
    float antennaScale;
} SEMInsectPlan;

static void SEMConfigureInsectLegPair(SEMInsectPlan *plan, int pair, float startX, float startY,
                                      float endX, float endY) {
    plan->legStartX[pair * 2] = 0.5f - startX;
    plan->legStartY[pair * 2] = startY;
    plan->legEndX[pair * 2] = 0.5f - endX;
    plan->legEndY[pair * 2] = endY;
    plan->legStartX[pair * 2 + 1] = 0.5f + startX;
    plan->legStartY[pair * 2 + 1] = startY;
    plan->legEndX[pair * 2 + 1] = 0.5f + endX;
    plan->legEndY[pair * 2 + 1] = endY;
}

static SEMInsectPlan SEMInsectPlanForName(NSString *name) {
    NSString *lower = name.lowercaseString ?: @"";
    BOOL spider = [lower containsString:@"spider"] || [lower containsString:@"arachnid"] ||
                  [lower containsString:@"mite"] || [lower containsString:@"tick"];
    BOOL ant = SEMTextContainsWord(lower, @"ant");
    BOOL beetle = [lower containsString:@"beetle"] || [lower containsString:@"weevil"] ||
                  [lower containsString:@"ladybug"];
    BOOL bigWings = [lower containsString:@"butterfly"] || [lower containsString:@"moth"];

    SEMInsectPlan plan = {0};
    plan.hasWings = !spider && !ant && !beetle;
    plan.hasAntennae = !spider;
    plan.bigEyes = !spider && !ant && !beetle;
    plan.splitElytra = beetle;
    plan.hasWaist = ant;
    plan.wingRX = bigWings ? 0.28f : 0.23f;
    plan.wingRY = bigWings ? 0.105f : 0.075f;
    plan.wingAngle = bigWings ? 0.50f : 0.42f;
    plan.antennaScale = bigWings ? 1.30f : 0.85f;

    if (spider) {
        plan.antennaScale = 0.0f;
        plan.headX = 0.5f; plan.headY = 0.36f; plan.headRX = 0.13f; plan.headRY = 0.11f;
        plan.thoraxX = 0.5f; plan.thoraxY = 0.36f; plan.thoraxRX = 0.13f; plan.thoraxRY = 0.11f;
        plan.abdomenX = 0.5f; plan.abdomenY = 0.60f; plan.abdomenRX = 0.15f; plan.abdomenRY = 0.18f;
        plan.legCount = 8;
        plan.legRadius = 0.010f;
        SEMConfigureInsectLegPair(&plan, 0, 0.09f, 0.32f, 0.30f, 0.24f);
        SEMConfigureInsectLegPair(&plan, 1, 0.09f, 0.38f, 0.36f, 0.36f);
        SEMConfigureInsectLegPair(&plan, 2, 0.09f, 0.44f, 0.36f, 0.58f);
        SEMConfigureInsectLegPair(&plan, 3, 0.09f, 0.50f, 0.30f, 0.72f);
    } else if (ant) {
        plan.antennaScale = 1.45f;
        plan.headX = 0.5f; plan.headY = 0.28f; plan.headRX = 0.065f; plan.headRY = 0.060f;
        plan.thoraxX = 0.5f; plan.thoraxY = 0.42f; plan.thoraxRX = 0.070f; plan.thoraxRY = 0.090f;
        plan.abdomenX = 0.5f; plan.abdomenY = 0.62f; plan.abdomenRX = 0.100f; plan.abdomenRY = 0.140f;
        plan.legCount = 6;
        plan.legRadius = 0.008f;
        SEMConfigureInsectLegPair(&plan, 0, 0.05f, 0.39f, 0.22f, 0.30f);
        SEMConfigureInsectLegPair(&plan, 1, 0.05f, 0.44f, 0.28f, 0.46f);
        SEMConfigureInsectLegPair(&plan, 2, 0.05f, 0.49f, 0.22f, 0.62f);
    } else if (beetle) {
        plan.antennaScale = 1.15f;
        plan.headX = 0.5f; plan.headY = 0.27f; plan.headRX = 0.070f; plan.headRY = 0.055f;
        plan.thoraxX = 0.5f; plan.thoraxY = 0.37f; plan.thoraxRX = 0.100f; plan.thoraxRY = 0.065f;
        plan.abdomenX = 0.5f; plan.abdomenY = 0.55f; plan.abdomenRX = 0.145f; plan.abdomenRY = 0.200f;
        plan.legCount = 6;
        plan.legRadius = 0.010f;
        SEMConfigureInsectLegPair(&plan, 0, 0.07f, 0.36f, 0.26f, 0.28f);
        SEMConfigureInsectLegPair(&plan, 1, 0.07f, 0.40f, 0.32f, 0.44f);
        SEMConfigureInsectLegPair(&plan, 2, 0.07f, 0.44f, 0.30f, 0.62f);
    } else {
        plan.headX = 0.5f; plan.headY = 0.30f; plan.headRX = 0.085f; plan.headRY = 0.065f;
        plan.thoraxX = 0.5f; plan.thoraxY = 0.42f; plan.thoraxRX = 0.115f; plan.thoraxRY = 0.095f;
        plan.abdomenX = 0.5f; plan.abdomenY = 0.60f; plan.abdomenRX = 0.100f; plan.abdomenRY = 0.170f;
        plan.legCount = 6;
        plan.legRadius = 0.009f;
        SEMConfigureInsectLegPair(&plan, 0, 0.07f, 0.40f, 0.28f, 0.32f);
        SEMConfigureInsectLegPair(&plan, 1, 0.07f, 0.45f, 0.33f, 0.50f);
        SEMConfigureInsectLegPair(&plan, 2, 0.07f, 0.50f, 0.27f, 0.68f);
    }
    return plan;
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

    SEMInsectPlan insectPlan = {0};
    if ([templateName isEqualToString:@"insect"]) {
        insectPlan = SEMInsectPlanForName(recipe.name);
    }

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
            } else if ([templateName isEqualToString:@"insect"]) {
                float bodyH = 0.0f;
                float bodyZ = 0.04f;

                // Wings are thin membranes behind the body.
                if (insectPlan.hasWings) {
                    for (int side = -1; side <= 1; side += 2) {
                        float wx = 0.5f + (float)side * 0.18f;
                        float wy = 0.475f;
                        float angle = (float)side * insectPlan.wingAngle;
                        float lx = 0.0f;
                        float ly = 0.0f;
                        float wing = SEMRotatedEllipseMask(p, q, wx, wy,
                                                           insectPlan.wingRX, insectPlan.wingRY,
                                                           angle, 0.18f, &lx, &ly);
                        if (wing > 0.0f) {
                            float veins = 0.5f + 0.5f * sinf(ly * 150.0f + lx * 6.0f);
                            float crossVeins = 0.5f + 0.5f * sinf(lx * 55.0f - ly * 18.0f);
                            float vein = SEMSmooth(0.55f, 0.95f, veins) * 0.65f +
                                         SEMSmooth(0.78f, 0.99f, crossVeins) * 0.35f;
                            float membrane = wing * (0.12f + vein * 0.075f);
                            if (membrane > bodyH) {
                                bodyH = membrane;
                                bodyZ = 0.10f;
                            }
                        }
                    }
                }

                // Six or eight jointed legs.
                float limbH = 0.0f;
                for (int leg = 0; leg < insectPlan.legCount; leg++) {
                    float ax = insectPlan.legStartX[leg];
                    float ay = insectPlan.legStartY[leg];
                    float bx = insectPlan.legEndX[leg];
                    float by = insectPlan.legEndY[leg];
                    float mx = (ax + bx) * 0.5f;
                    float my = (ay + by) * 0.5f;
                    float ox = mx - 0.5f;
                    float oy = my - 0.45f;
                    float olen = sqrtf(ox * ox + oy * oy);
                    float bend = 0.032f;
                    float kx = mx + (olen > 0.0001f ? ox / olen : 0.0f) * bend;
                    float ky = my + (olen > 0.0001f ? oy / olen : 0.0f) * bend;
                    float d = fminf(SEMSegmentDistance(p, q, ax, ay, kx, ky),
                                    SEMSegmentDistance(p, q, kx, ky, bx, by));
                    float r = insectPlan.legRadius;
                    float tube = SEMSmooth(r, r * 0.25f, d);
                    float knee = SEMSmooth(r * 1.7f, r * 0.4f,
                                           sqrtf((p - kx) * (p - kx) + (q - ky) * (q - ky)));
                    float foot = SEMSmooth(r * 1.6f, r * 0.5f,
                                           sqrtf((p - bx) * (p - bx) + (q - by) * (q - by)));
                    float value = tube * 0.14f + knee * 0.035f + foot * 0.020f;
                    if (value > limbH) limbH = value;
                }

                // Antennae: an elbowed pair rising from the head.
                if (insectPlan.hasAntennae) {
                    float scale = insectPlan.antennaScale;
                    float baseOffset = insectPlan.headRX * 0.40f;
                    float baseY = insectPlan.headY - insectPlan.headRY * 0.72f;
                    float reach = insectPlan.headRX * 2.0f * scale;
                    float rise = insectPlan.headRY * 1.6f * scale;
                    float r = 0.0034f + 0.0012f * scale;
                    for (int side = -1; side <= 1; side += 2) {
                        float sx = 0.5f + (float)side * baseOffset;
                        float kx = 0.5f + (float)side * reach * 0.55f;
                        float ky = baseY - rise * 0.55f;
                        float ex = 0.5f + (float)side * reach;
                        float ey = baseY - rise;
                        float d = fminf(SEMSegmentDistance(p, q, sx, baseY, kx, ky),
                                        SEMSegmentDistance(p, q, kx, ky, ex, ey));
                        float tube = SEMSmooth(r, r * 0.25f, d);
                        float club = SEMSmooth(r * 2.8f, r * 0.6f,
                                               sqrtf((p - ex) * (p - ex) + (q - ey) * (q - ey)));
                        float value = tube * 0.11f + club * 0.04f;
                        if (value > limbH) limbH = value;
                    }
                }

                if (limbH > bodyH) {
                    bodyH = limbH;
                    bodyZ = 0.20f;
                }

                // Head.
                float d = SEMEllipseDistance(p, q, insectPlan.headX, insectPlan.headY,
                                             insectPlan.headRX, insectPlan.headRY);
                float mask = SEMSmooth(1.0f, 0.88f, d);
                float part = sqrtf(MAX(0.0f, 1.0f - d * d)) * 0.30f * mask;
                part += (n - 0.5f) * 0.016f * roughness * mask;
                if (part > bodyH) { bodyH = part; bodyZ = 0.30f; }

                // Thorax with fine setae.
                d = SEMEllipseDistance(p, q, insectPlan.thoraxX, insectPlan.thoraxY,
                                       insectPlan.thoraxRX, insectPlan.thoraxRY);
                mask = SEMSmooth(1.0f, 0.88f, d);
                part = sqrtf(MAX(0.0f, 1.0f - d * d)) * 0.34f * mask;
                float setae = powf(0.5f + 0.5f * sinf(p * 240.0f + n * 9.0f) *
                                   sinf(q * 240.0f + n * 7.0f), 10.0f);
                part += setae * 0.014f * mask * (0.4f + roughness);
                part += (n - 0.5f) * 0.014f * roughness * mask;
                if (part > bodyH) { bodyH = part; bodyZ = 0.33f; }

                // Abdomen with segment rings; beetle elytra get a split and striae.
                d = SEMEllipseDistance(p, q, insectPlan.abdomenX, insectPlan.abdomenY,
                                       insectPlan.abdomenRX, insectPlan.abdomenRY);
                mask = SEMSmooth(1.0f, 0.90f, d);
                part = sqrtf(MAX(0.0f, 1.0f - d * d)) * 0.37f * mask;
                float ringPhase = (q - (insectPlan.abdomenY - insectPlan.abdomenRY)) /
                                  MAX(2.0f * insectPlan.abdomenRY, 0.0001f);
                float rings = 0.5f + 0.5f * cosf(ringPhase * 6.2831853f * 7.0f);
                part -= SEMSmooth(0.55f, 0.95f, rings) * 0.032f * mask;
                if (insectPlan.splitElytra) {
                    float split = 1.0f - SEMSmooth(0.0f, 0.009f, fabsf(p - 0.5f));
                    part -= split * 0.10f * mask;
                    float striae = 0.5f + 0.5f * sinf((p - 0.5f) * 180.0f);
                    part -= SEMSmooth(0.82f, 0.99f, striae) * 0.014f * mask;
                }
                part += (n - 0.5f) * 0.014f * roughness * mask;
                if (part > bodyH) { bodyH = part; bodyZ = 0.35f; }

                // Ant waist.
                if (insectPlan.hasWaist) {
                    d = SEMEllipseDistance(p, q, 0.5f, 0.515f, 0.026f, 0.055f);
                    mask = SEMSmooth(1.0f, 0.85f, d);
                    part = sqrtf(MAX(0.0f, 1.0f - d * d)) * 0.19f * mask;
                    if (part > bodyH) { bodyH = part; bodyZ = 0.31f; }
                }

                // Compound eyes for flies, moths, and butterflies; simple eyes otherwise.
                if (insectPlan.bigEyes) {
                    for (int side = -1; side <= 1; side += 2) {
                        float ex = insectPlan.headX + (float)side * insectPlan.headRX * 0.58f;
                        float ey = insectPlan.headY - insectPlan.headRY * 0.05f;
                        float erx = insectPlan.headRX * 0.48f;
                        float ery = insectPlan.headRY * 0.80f;
                        d = SEMEllipseDistance(p, q, ex, ey, erx, ery);
                        mask = SEMSmooth(1.0f, 0.84f, d);
                        part = sqrtf(MAX(0.0f, 1.0f - d * d)) * 0.38f * mask;
                        SEMWorley facets = SEMWorleyNoise(p * 190.0f, q * 190.0f, seed + 31u);
                        float bump = 1.0f - SEMSmooth(0.08f, 0.55f, facets.f1);
                        part += bump * 0.010f * mask;
                        if (part > bodyH) { bodyH = part; bodyZ = 0.13f; }
                    }
                } else if (insectPlan.hasWaist || insectPlan.splitElytra) {
                    for (int side = -1; side <= 1; side += 2) {
                        float ex = insectPlan.headX + (float)side * insectPlan.headRX * 0.52f;
                        float ey = insectPlan.headY;
                        d = SEMEllipseDistance(p, q, ex, ey,
                                               insectPlan.headRX * 0.28f,
                                               insectPlan.headRY * 0.46f);
                        mask = SEMSmooth(1.0f, 0.80f, d);
                        part = sqrtf(MAX(0.0f, 1.0f - d * d)) * 0.35f * mask;
                        if (part > bodyH) { bodyH = part; bodyZ = 0.14f; }
                    }
                } else {
                    // Spider: two pairs of simple eyes at the front of the cephalothorax.
                    for (int side = -1; side <= 1; side += 2) {
                        float ex = 0.5f + (float)side * 0.030f;
                        float ey = 0.318f;
                        d = SEMEllipseDistance(p, q, ex, ey, 0.012f, 0.012f);
                        mask = SEMSmooth(1.0f, 0.72f, d);
                        part = sqrtf(MAX(0.0f, 1.0f - d * d)) * 0.36f * mask;
                        if (part > bodyH) { bodyH = part; bodyZ = 0.12f; }
                        ex = 0.5f + (float)side * 0.060f;
                        ey = 0.338f;
                        d = SEMEllipseDistance(p, q, ex, ey, 0.008f, 0.008f);
                        mask = SEMSmooth(1.0f, 0.72f, d);
                        part = sqrtf(MAX(0.0f, 1.0f - d * d)) * 0.35f * mask;
                        if (part > bodyH) { bodyH = part; bodyZ = 0.12f; }
                    }
                }

                // Short proboscis below the head for fly-like insects.
                if (insectPlan.bigEyes && !insectPlan.splitElytra) {
                    d = SEMEllipseDistance(p, q, 0.5f,
                                           insectPlan.headY + insectPlan.headRY * 0.95f,
                                           0.018f, 0.042f);
                    mask = SEMSmooth(1.0f, 0.72f, d);
                    part = sqrtf(MAX(0.0f, 1.0f - d * d)) * 0.16f * mask;
                    if (part > bodyH) { bodyH = part; bodyZ = 0.24f; }
                }

                h = bodyH;
                z = bodyZ;
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
