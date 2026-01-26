#import <Foundation/Foundation.h>

@class SEMSpecimen;
@class SpecimenPreset;

NS_ASSUME_NONNULL_BEGIN

/// Posted after a specimen file is saved or imported. The offline model lists
/// (drawer, Settings, and the Specimen menu) refresh when this fires.
extern NSString * const SEMSavedSpecimensDidChangeNotification;

/// File extension used by saved specimen documents.
extern NSString * const SEMSpecimenFileExtension;

/// Stores user-saved specimens as small JSON documents. The file contains the
/// recipe, metadata, source prompt, and an embedded preview image; the maps are
/// re-synthesized deterministically from the recipe when the file is loaded.
///
/// Every saved/imported specimen is also copied into the store directory so it
/// remains available in the offline model list even if the user's exported copy
/// is moved or deleted.
@interface SavedSpecimenStore : NSObject

+ (instancetype)sharedStore;

- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSURL *directoryURL;

/// Saved specimens, newest first. Invalid or missing files are skipped.
@property (nonatomic, readonly) NSArray<SpecimenPreset *> *savedPresets;

/// Writes the specimen document to `url` and keeps a managed copy for the
/// offline list. When the specimen has a preview image, a sibling
/// `<name>-preview.png` file is written as well.
- (BOOL)saveSpecimen:(SEMSpecimen *)specimen
        sourcePrompt:(nullable NSString *)sourcePrompt
               toURL:(NSURL *)url
               error:(NSError **)error;

/// Reads a specimen document, adds a managed copy to the offline list, and
/// returns a preset that can be loaded by the specimen generator.
- (nullable SpecimenPreset *)importSpecimenFromURL:(NSURL *)url
                                             error:(NSError **)error;

/// Companion PNG path used next to a saved specimen document.
- (NSURL *)previewURLForSpecimenURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
