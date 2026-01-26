#ifndef ShaderTypes_h
#define ShaderTypes_h

// Shared by Objective-C and Metal. Only scalar fields are used so the layout
// is identical in both languages.

typedef struct {
    float viewCenterX;
    float viewCenterY;
    float viewScale;
    float rotation;
    float tilt;
    float focus;
    float stigmatorX;
    float stigmatorY;
    float kV;
    float spot;
    float wd;
    float brightness;
    float contrast;
    float charge;
    float time;
    float scanProgress;
    float textureWidth;
    float textureHeight;
    float meanZ;
    float noiseAmount;
    float contaminationAmount;

    int detectorMode;
    int goldCoated;
    int conductive;
    int scanMode;
    int phosphorMode;
    int padding0;

    float padding[5];
} SEMShaderUniforms;

typedef struct {
    float width;
    float height;
    float time;
    float scanProgress;
    float persistence;
    float charge;
    float barrel;
    float noiseAmount;

    int scanMode;
    int phosphorMode;
    int slowScanning;
    int beamOn;

    float sweepGlow;
    float padding[3];
} CRTShaderUniforms;

#endif
