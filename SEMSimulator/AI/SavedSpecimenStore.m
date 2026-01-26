#import "SavedSpecimenStore.h"
#import <AppKit/AppKit.h>

#import "AISampleRecipe.h"
#import "SEMSpecimen.h"
#import "SpecimenLibrary.h"

NSString * const SEMSavedSpecimensDidChangeNotification = @"SEMSavedSpecimensDidChangeNotification";
NSString * const SEMSpecimenFileExtension = @"semspecimen";

static NSString * const SEMSpecimenFileFormat = @"SEMSimulatorSpecimen";
static const NSInteger SEMSpecimenFileVersion = 1;

static NSError *SEMSpecimenFileError(NSString *message, NSInteger code) {
    return [NSError errorWithDomain:@"SEM.SpecimenFile"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSData *SEMPNGDataForImage(NSImage *image) {
    if (!image) return nil;
    NSData *tiff = image.TIFFRepresentation;
    if (!tiff) return nil;
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static NSString *SEMDisplayDate(NSString *savedAt) {
    if (![savedAt isKindOfClass:[NSString class]] || savedAt.length == 0) return @"saved specimen";
    NSISO8601DateFormatter *parser = [[NSISO8601DateFormatter alloc] init];
    NSDate *date = [parser dateFromString:savedAt];
    if (!date) return savedAt;
    return [NSDateFormatter localizedStringFromDate:date
                                          dateStyle:NSDateFormatterMediumStyle
                                          timeStyle:NSDateFormatterShortStyle];
}

@interface SavedSpecimenStore ()
@property (nonatomic, strong) NSURL *directoryURL;
@end

@implementation SavedSpecimenStore

+ (instancetype)sharedStore {
    static SavedSpecimenStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                              NSUserDomainMask,
                                                              YES).firstObject;
        NSURL *directory = [[[NSURL fileURLWithPath:base isDirectory:YES]
                             URLByAppendingPathComponent:@"SEM Simulator" isDirectory:YES]
                            URLByAppendingPathComponent:@"Specimens" isDirectory:YES];
        store = [[SavedSpecimenStore alloc] initWithDirectoryURL:directory];
    });
    return store;
}

- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL {
    self = [super init];
    if (self) {
        _directoryURL = [directoryURL copy];
        [[NSFileManager defaultManager] createDirectoryAtURL:_directoryURL
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:NULL];
    }
    return self;
}

#pragma mark - Reading

- (nullable NSDictionary<NSString *, id> *)payloadFromURL:(NSURL *)url error:(NSError **)error {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
    if (!data) {
        if (error) *error = readError ?: SEMSpecimenFileError(@"The specimen file could not be read.", 10);
        return nil;
    }

    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error) *error = jsonError ?: SEMSpecimenFileError(@"The specimen file is not a JSON object.", 11);
        return nil;
    }

    NSDictionary<NSString *, id> *payload = object;
    NSString *format = [payload[@"format"] isKindOfClass:[NSString class]] ? payload[@"format"] : nil;
    if (![format isEqualToString:SEMSpecimenFileFormat]) {
        if (error) *error = SEMSpecimenFileError(@"This is not a SEM Simulator specimen file.", 12);
        return nil;
    }

    NSString *name = [payload[@"name"] isKindOfClass:[NSString class]] ? payload[@"name"] : nil;
    NSDictionary *recipe = [payload[@"recipe"] isKindOfClass:[NSDictionary class]] ? payload[@"recipe"] : nil;
    if (name.length == 0 || recipe.count == 0) {
        if (error) *error = SEMSpecimenFileError(@"The specimen file is missing its name or recipe.", 13);
        return nil;
    }
    if (![AISampleRecipe recipeFromDictionary:recipe error:NULL]) {
        if (error) *error = SEMSpecimenFileError(@"The specimen recipe is invalid.", 14);
        return nil;
    }
    return payload;
}

- (nullable SpecimenPreset *)presetFromPayload:(NSDictionary<NSString *, id> *)payload {
    NSString *identifier = [payload[@"identifier"] isKindOfClass:[NSString class]] ? payload[@"identifier"] : nil;
    NSString *name = [payload[@"name"] isKindOfClass:[NSString class]] ? payload[@"name"] : nil;
    NSDictionary *recipe = [payload[@"recipe"] isKindOfClass:[NSDictionary class]] ? payload[@"recipe"] : nil;
    if (identifier.length == 0 || name.length == 0 || recipe.count == 0) return nil;

    NSString *sourcePrompt = [payload[@"sourcePrompt"] isKindOfClass:[NSString class]] ? payload[@"sourcePrompt"] : nil;
    if (sourcePrompt.length == 0) sourcePrompt = name;
    NSString *savedAt = [payload[@"savedAt"] isKindOfClass:[NSString class]] ? payload[@"savedAt"] : nil;
    NSUInteger seed = [payload[@"seed"] respondsToSelector:@selector(unsignedIntegerValue)]
        ? [payload[@"seed"] unsignedIntegerValue]
        : 0;

    NSString *detail = [NSString stringWithFormat:@"Saved specimen · %@", SEMDisplayDate(savedAt)];
    SpecimenPreset *preset = [[SpecimenPreset alloc] initWithIdentifier:identifier
                                                                   name:name
                                                               category:@"SAVED"
                                                                 prompt:sourcePrompt
                                                                 detail:detail
                                                              variation:seed
                                                       recipeDictionary:recipe];

    NSString *preview = [payload[@"previewPNG"] isKindOfClass:[NSString class]] ? payload[@"previewPNG"] : nil;
    NSData *previewData = preview.length > 0 ? [[NSData alloc] initWithBase64EncodedString:preview options:0] : nil;
    if (previewData.length > 0) {
        preset.previewImage = [[NSImage alloc] initWithData:previewData];
    }
    return preset;
}

- (NSArray<SpecimenPreset *> *)savedPresets {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray<NSURL *> *files = [manager contentsOfDirectoryAtURL:self.directoryURL
                                     includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                        options:NSDirectoryEnumerationSkipsHiddenFiles
                                                          error:NULL];
    if (files.count == 0) return @[];

    NSMutableDictionary<NSString *, SpecimenPreset *> *byIdentifier = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDate *> *dates = [NSMutableDictionary dictionary];

    for (NSURL *fileURL in files) {
        if (![fileURL.pathExtension.lowercaseString isEqualToString:SEMSpecimenFileExtension]) continue;
        NSDictionary *payload = [self payloadFromURL:fileURL error:NULL];
        SpecimenPreset *preset = [self presetFromPayload:payload];
        if (!preset) continue;

        NSDate *modified = nil;
        [fileURL getResourceValue:&modified forKey:NSURLContentModificationDateKey error:NULL];
        if (!modified) modified = [NSDate distantPast];

        NSDate *existing = dates[preset.identifier];
        if (!existing || [modified compare:existing] == NSOrderedDescending) {
            byIdentifier[preset.identifier] = preset;
            dates[preset.identifier] = modified;
        }
    }

    return [byIdentifier.allValues sortedArrayUsingComparator:^NSComparisonResult(SpecimenPreset *a, SpecimenPreset *b) {
        NSDate *dateA = dates[a.identifier] ?: [NSDate distantPast];
        NSDate *dateB = dates[b.identifier] ?: [NSDate distantPast];
        return [dateB compare:dateA];
    }];
}

#pragma mark - Writing

- (NSURL *)previewURLForSpecimenURL:(NSURL *)url {
    NSString *base = url.lastPathComponent.stringByDeletingPathExtension ?: @"Specimen";
    NSString *name = [base stringByAppendingString:@"-preview.png"];
    return [url.URLByDeletingLastPathComponent URLByAppendingPathComponent:name];
}

- (NSDictionary<NSString *, id> *)payloadForSpecimen:(SEMSpecimen *)specimen
                                        sourcePrompt:(NSString *)sourcePrompt
                                          identifier:(NSString *)identifier {
    NSDictionary *recipe = [specimen.recipe isKindOfClass:[NSDictionary class]] ? specimen.recipe : nil;
    if (recipe.count == 0) {
        recipe = @{
            @"name": specimen.name.length > 0 ? specimen.name : @"Specimen",
            @"template": specimen.templateName.length > 0 ? specimen.templateName : @"fracture",
            @"features": @{},
            @"material": @{
                @"meanZ": @(specimen.meanZ),
                @"conductive": @(specimen.conductive),
                @"coatingRecommended": @(specimen.coatingRecommended)
            },
            @"scaleUm": @(specimen.scaleMicrometers > 0 ? specimen.scaleMicrometers : 50),
            @"seed": @(specimen.seed)
        };
    }

    NSMutableDictionary<NSString *, id> *payload = [@{
        @"format": SEMSpecimenFileFormat,
        @"version": @(SEMSpecimenFileVersion),
        @"identifier": identifier,
        @"name": specimen.name.length > 0 ? specimen.name : @"Specimen",
        @"template": specimen.templateName.length > 0 ? specimen.templateName : @"fracture",
        @"sourcePrompt": sourcePrompt.length > 0 ? sourcePrompt : @"",
        @"recipe": recipe,
        @"conductive": @(specimen.conductive),
        @"coatingRecommended": @(specimen.coatingRecommended),
        @"meanZ": @(specimen.meanZ),
        @"scaleUm": @(specimen.scaleMicrometers),
        @"seed": @(specimen.seed),
        @"savedAt": [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]]
    } mutableCopy];

    NSData *preview = SEMPNGDataForImage(specimen.thumbnail);
    if (preview.length > 0) {
        payload[@"previewPNG"] = [preview base64EncodedStringWithOptions:0];
    }
    return payload;
}

- (BOOL)writePayload:(NSDictionary<NSString *, id> *)payload
               toURL:(NSURL *)url
               error:(NSError **)error {
    if (![NSJSONSerialization isValidJSONObject:payload]) {
        if (error) *error = SEMSpecimenFileError(@"The specimen metadata is not valid JSON.", 20);
        return NO;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:payload
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!data) return NO;

    NSURL *parent = url.URLByDeletingLastPathComponent;
    if (parent) {
        [[NSFileManager defaultManager] createDirectoryAtURL:parent
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:NULL];
    }
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (BOOL)saveSpecimen:(SEMSpecimen *)specimen
        sourcePrompt:(NSString *)sourcePrompt
               toURL:(NSURL *)url
               error:(NSError **)error {
    if (!specimen || url == nil) {
        if (error) *error = SEMSpecimenFileError(@"No specimen or destination was supplied.", 21);
        return NO;
    }

    NSString *identifier = [NSUUID UUID].UUIDString;
    NSDictionary *payload = [self payloadForSpecimen:specimen sourcePrompt:sourcePrompt identifier:identifier];

    NSURL *managedURL = [self.directoryURL URLByAppendingPathComponent:
                         [identifier stringByAppendingPathExtension:SEMSpecimenFileExtension]];
    if (![self writePayload:payload toURL:managedURL error:error]) return NO;

    if (![url.URLByStandardizingPath.path isEqualToString:managedURL.URLByStandardizingPath.path]) {
        if (![self writePayload:payload toURL:url error:error]) {
            [[NSFileManager defaultManager] removeItemAtURL:managedURL error:NULL];
            return NO;
        }
    }

    NSString *preview = [payload[@"previewPNG"] isKindOfClass:[NSString class]] ? payload[@"previewPNG"] : nil;
    NSData *previewData = preview.length > 0 ? [[NSData alloc] initWithBase64EncodedString:preview options:0] : nil;
    if (previewData.length > 0) {
        [previewData writeToURL:[self previewURLForSpecimenURL:url] options:NSDataWritingAtomic error:NULL];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SEMSavedSpecimensDidChangeNotification
                                                        object:self
                                                      userInfo:@{@"identifier": identifier,
                                                                 @"name": specimen.name ?: @"Specimen"}];
    return YES;
}

- (nullable SpecimenPreset *)importSpecimenFromURL:(NSURL *)url error:(NSError **)error {
    NSDictionary *payload = [self payloadFromURL:url error:error];
    if (!payload) return nil;

    NSMutableDictionary<NSString *, id> *managedPayload = [payload mutableCopy];
    NSString *identifier = [payload[@"identifier"] isKindOfClass:[NSString class]] ? payload[@"identifier"] : nil;
    NSUUID *uuid = identifier.length > 0 ? [[NSUUID alloc] initWithUUIDString:identifier] : nil;
    if (!uuid) {
        identifier = [NSUUID UUID].UUIDString;
        managedPayload[@"identifier"] = identifier;
    }

    SpecimenPreset *preset = [self presetFromPayload:managedPayload];
    if (!preset) {
        if (error) *error = SEMSpecimenFileError(@"The specimen file is missing required metadata.", 22);
        return nil;
    }

    NSURL *managedURL = [self.directoryURL URLByAppendingPathComponent:
                         [identifier stringByAppendingPathExtension:SEMSpecimenFileExtension]];
    if (![url.URLByStandardizingPath.path isEqualToString:managedURL.URLByStandardizingPath.path]) {
        if (![self writePayload:managedPayload toURL:managedURL error:error]) return nil;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SEMSavedSpecimensDidChangeNotification
                                                        object:self
                                                      userInfo:@{@"identifier": identifier,
                                                                 @"name": preset.name}];
    return preset;
}

@end
