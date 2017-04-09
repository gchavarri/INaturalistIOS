//
//  ImageStore.m
//  iNaturalist
//
//  Created by Ken-ichi Ueda on 2/20/12.
//  Copyright (c) 2012 iNaturalist. All rights reserved.
// 
//  Largely based on the ImageStore example in iOS Programming: The Big Nerd Range Guide, 
//  Second Edition by Joe Conway and Aaron Hillegass.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import <FontAwesomeKit/FAKIonIcons.h>
#import <SDWebImage/SDImageCache.h>
#import <ImageIO/ImageIO.h>

#import "ImageStore.h"
#import "Analytics.h"

#define INATURALIST_ORG_MAX_PHOTO_EDGE      2048

@interface ImageStore ()
@end

@implementation ImageStore
@synthesize dictionary;

// singleton
+ (ImageStore *)sharedImageStore {
    static ImageStore *_sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[ImageStore alloc] init];
    });
    return _sharedInstance;
}


- (instancetype)init {
    if (self = [super init]) {
        [self setDictionary:[[NSMutableDictionary alloc] init]];
        
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(clearCache:)
                                                   name:UIApplicationDidReceiveMemoryWarningNotification
                                                 object:nil];
    }
    return self;
}

- (UIImage *)find:(NSString *)key {
    return [self find:key forSize:ImageStoreLargeSize];
}

- (UIImage *)find:(NSString *)key forSize:(int)size {
    NSString *sizedKey = [self keyForKey:key forSize:size];
    
    // prefer the non-expiring version
    UIImage *image = [self findInNonExpiringCacheSizedKey:sizedKey];
    if (!image) {
        image = [self findInExpiringCacheSizedKey:sizedKey];
    }
    return image;
}

- (BOOL)storeImage:(UIImage *)image forKey:(NSString *)key error:(NSError **)error {
    [[Analytics sharedClient] debugLog:@"IMAGE STORE: begin"];

    @autoreleasepool {
        // large = fullsize image but truncated to 2048x2048 pixels max (aspect ratio scaled)
        CGSize imageSize = image.size;
        CGFloat longestSide = imageSize.width > imageSize.height ? imageSize.width : imageSize.height;
        CGFloat scale = 1;
        
        if (longestSide > INATURALIST_ORG_MAX_PHOTO_EDGE) {
            scale = INATURALIST_ORG_MAX_PHOTO_EDGE / longestSide;
        }
        
        // resize with CGImage is fast enough for us
        UIImage *resized = [UIImage imageWithCGImage:image.CGImage
                                               scale:scale
                                         orientation:image.imageOrientation];
        NSString *largeKey = [self keyForKey:key forSize:ImageStoreLargeSize];
        [self storeInNonExpiringCacheImage:image withSizedKey:largeKey];
    }
    
    @autoreleasepool {
        // small = 640x640
        CGSize imageSize = image.size;
        CGFloat longestSide = imageSize.width > imageSize.height ? imageSize.width : imageSize.height;
        CGFloat scale = 1;
        
        if (longestSide > 640.0) {
            scale = 640.0 / longestSide;
        }
        
        // resize with CGImage is fast enough for us
        UIImage *resized = [UIImage imageWithCGImage:image.CGImage
                                               scale:scale
                                         orientation:image.imageOrientation];

        NSString *smallKey = [self keyForKey:key forSize:ImageStoreSmallSize];
        [self storeInNonExpiringCacheImage:resized withSizedKey:smallKey];
    }
    
    @autoreleasepool {
        UIImage *thumb = [[self class] imageWithImage:image scaledToFillSize:CGSizeMake(128, 128)];
        NSString *squareKey = [self keyForKey:key forSize:ImageStoreSquareSize];
        [self storeInNonExpiringCacheImage:thumb withSizedKey:squareKey];
    }
    
    [[Analytics sharedClient] debugLog:@"IMAGE STORE: done"];
    return YES;
}

+ (UIImage *)imageWithImage:(UIImage *)image scaledToFillSize:(CGSize)size {
    CGFloat scale = MAX(size.width/image.size.width, size.height/image.size.height);
    CGFloat width = image.size.width * scale;
    CGFloat height = image.size.height * scale;
    CGRect imageRect = CGRectMake((size.width - width)/2.0f,
                                  (size.height - height)/2.0f,
                                  width,
                                  height);
    
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [image drawInRect:imageRect];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

- (BOOL)storeAsset:(ALAsset *)asset forKey:(NSString *)key error:(NSError *__autoreleasing *)storeError {
    [[Analytics sharedClient] debugLog:@"ASSET STORE: begin"];
    
    @autoreleasepool {
        // large = fullsize image but truncated to 2048x2048 pixels max (aspect ratio scaled)
        CGSize imageSize = [[asset defaultRepresentation] dimensions];
        CGFloat longestSide = imageSize.width > imageSize.height ? imageSize.width : imageSize.height;
        CGFloat scale = [[asset defaultRepresentation] scale];
        
        if (longestSide > INATURALIST_ORG_MAX_PHOTO_EDGE) {
            scale = INATURALIST_ORG_MAX_PHOTO_EDGE / longestSide;
        }
        
        // resize with CGImage is fast enough for us
        UIImage *resized = [UIImage imageWithCGImage:[[asset defaultRepresentation] fullResolutionImage]
                                               scale:scale
                                         orientation:[[asset defaultRepresentation] orientation]];
        NSString *largeKey = [self keyForKey:key forSize:ImageStoreLargeSize];
        [self storeInNonExpiringCacheImage:resized withSizedKey:largeKey];
    }
    
    @autoreleasepool {
        // small = full screen asset
        UIImage *small = [UIImage imageWithCGImage:[[asset defaultRepresentation] fullScreenImage]];
        NSString *smallKey = [self keyForKey:key forSize:ImageStoreSmallSize];
        [self storeInNonExpiringCacheImage:small withSizedKey:smallKey];
    }
    
    @autoreleasepool {
        // square = asset thumbnail
        UIImage *thumb = [UIImage imageWithCGImage:asset.thumbnail];
        NSString *squareKey = [self keyForKey:key forSize:ImageStoreSquareSize];
        [self storeInNonExpiringCacheImage:thumb withSizedKey:squareKey];
    }
    
    [[Analytics sharedClient] debugLog:@"ASSET STORE: done"];
    return YES;
}

- (void)destroy:(NSString *)baseKey {
    if (!baseKey) {
        return;
    }
    [self.dictionary removeObjectForKey:baseKey];
    [[NSFileManager defaultManager] removeItemAtPath:[self pathForKey:baseKey] error:nil];
    
    for (int size = 1; size <= ImageStoreLargeSize; size++) {
        NSString *sizedKey = [self keyForKey:baseKey forSize:size];
        [self.dictionary removeObjectForKey:sizedKey];
        [self deleteFromNonExpiringCacheSizedKey:sizedKey];
        [self deleteFromExpiringCacheSizedKey:sizedKey];
    }
}

- (NSString *)createKey {
    return [[NSUUID UUID] UUIDString];
}

- (NSString *)pathForKey:(NSString *)key {
    return [self pathForKey:key forSize:ImageStoreLargeSize];
}

- (NSString *)pathForKey:(NSString *)key forSize:(int)size {
    NSString *sizedKey = [self keyForKey:key forSize:size];
    
    // prefer nonexpiring
    NSString *path = [self pathInNonExpiringCacheSizedKey:sizedKey];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return path;
    } else {
        return [self pathInExpiringCacheSizedKey:sizedKey];
    }    
}

- (void)makeExpiring:(NSString *)imgKey {
    if (!imgKey) { return; }
    
    NSString *largeKey = [self keyForKey:imgKey forSize:ImageStoreLargeSize];
    UIImage *large = [self findInNonExpiringCacheSizedKey:largeKey];
    [[SDImageCache sharedImageCache] storeImage:large forKey:largeKey toDisk:YES completion:^{
        [self deleteFromNonExpiringCacheSizedKey:largeKey];
    }];

    NSString *smallKey = [self keyForKey:imgKey forSize:ImageStoreSmallSize];
    UIImage *small = [self findInNonExpiringCacheSizedKey:smallKey];
    [[SDImageCache sharedImageCache] storeImage:small forKey:smallKey toDisk:YES completion:^{
        [self deleteFromNonExpiringCacheSizedKey:smallKey];
    }];

    NSString *thumbKey = [self keyForKey:imgKey forSize:ImageStoreSquareSize];
    UIImage *thumb = [self findInNonExpiringCacheSizedKey:thumbKey];
    [[SDImageCache sharedImageCache] storeImage:thumb forKey:thumbKey toDisk:YES completion:^{
        [self deleteFromNonExpiringCacheSizedKey:thumbKey];
    }];
}

- (NSString *)oldPathForKey:(NSString *)key forSize:(int)size {
    NSArray *docDirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [docDirs objectAtIndex:0];
    NSString *photoDirPath = [docDir stringByAppendingPathComponent:@"photos"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:photoDirPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:photoDirPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    
    return [NSString stringWithFormat:@"%@.jpg",
            [photoDirPath stringByAppendingPathComponent:
             [self keyForKey:key forSize:size]]];
}

- (NSString *)keyForKey:(NSString *)key forSize:(int)size
{
    NSString *str;
    switch (size) {
        case ImageStoreSquareSize:
            str = [NSString stringWithFormat:@"%@-square", key];
            break;
        case ImageStoreSmallSize:
            str = [NSString stringWithFormat:@"%@-small", key];
            break;
        case ImageStoreMediumSize:
            str = [NSString stringWithFormat:@"%@-medium", key];
            break;
        case ImageStoreLargeSize:
            str = [NSString stringWithFormat:@"%@-large", key];
            break;
        default:
            str = key;
            break;
    }
    return str;
}

- (NSString *)usageStatsString {
    static NSNumberFormatter *numberFormatter = nil;
    if (!numberFormatter) {
        numberFormatter = [[NSNumberFormatter alloc] init];
        numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        numberFormatter.groupingSize = 3;
        numberFormatter.groupingSeparator = @",";
    }
    
    NSString *sdSize = [numberFormatter stringFromNumber:@([[SDImageCache sharedImageCache] getSize])];
    NSString *sdCount = [numberFormatter stringFromNumber:@([[SDImageCache sharedImageCache] getDiskCount])];
    NSString *sdCacheStats = [NSString stringWithFormat:@"SDImageCache: %@ for %@ files",
                              sdSize, sdCount];
    
    NSArray *docDirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [docDirs objectAtIndex:0];
    NSString *photoDirPath = [docDir stringByAppendingPathComponent:@"photos"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:photoDirPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:photoDirPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:photoDirPath error:nil];
    NSString *photosCount = [numberFormatter stringFromNumber:@([files count])];

    unsigned long long int allPhotosSize = 0;
    for (NSString *fileName in files) {
        NSString *filePath = [photoDirPath stringByAppendingPathComponent:fileName];
        NSDictionary *fileDictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        allPhotosSize += [fileDictionary fileSize];
    }
    NSString *photosSize = [numberFormatter stringFromNumber:@(allPhotosSize)];

    NSString *photoCacheStats = [NSString stringWithFormat:@"Un-Uploaded Photos: %@ for %@ files",
                                 photosSize, photosCount];
    return [NSString stringWithFormat:@"%@ - %@", sdCacheStats, photoCacheStats];
}

- (void)clearCache
{
    [dictionary removeAllObjects];
}

- (void)clearCache:(NSNotification *)note
{
    [self clearCache];
}

- (UIImage *)iconicTaxonImageForName:(NSString *)name
{
    NSString *iconicTaxonName = name ? [name lowercaseString] : @"unknown";
    NSString *key = [NSString stringWithFormat:@"ic_%@", iconicTaxonName];
    return [UIImage imageNamed:key];
}

#pragma mark - Expiring Cache Methods

- (UIImage *)findInExpiringCacheSizedKey:(NSString *)sizedKey {
    return [[SDImageCache sharedImageCache] imageFromDiskCacheForKey:sizedKey];
}

- (NSString *)pathInExpiringCacheSizedKey:(NSString *)sizedKey {
    return [[SDImageCache sharedImageCache] defaultCachePathForKey:sizedKey];
}

- (void)storeInExpiringCacheImage:(UIImage *)image withSizedKey:(NSString *)sizedKey {
    [[SDImageCache sharedImageCache] storeImage:image forKey:sizedKey toDisk:YES completion:nil];
}

- (void)deleteFromExpiringCacheSizedKey:(NSString *)sizedKey {
    [[SDImageCache sharedImageCache] removeImageForKey:sizedKey fromDisk:YES withCompletion:nil];
}

#pragma mark - Non-expiring Cache Methods

- (UIImage *)findInNonExpiringCacheSizedKey:(NSString *)sizedKey {
    return [UIImage imageWithContentsOfFile:[self pathInNonExpiringCacheSizedKey:sizedKey]];
}

- (NSString *)pathInNonExpiringCacheSizedKey:(NSString *)sizedKey {
    NSArray *docDirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [docDirs objectAtIndex:0];
    NSString *photoDirPath = [docDir stringByAppendingPathComponent:@"photos"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:photoDirPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:photoDirPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    
    NSString *filePath = [photoDirPath stringByAppendingPathComponent:sizedKey];
    return filePath;
}

- (BOOL)storeInNonExpiringCacheImage:(UIImage *)image withSizedKey:(NSString *)sizedKey {
    NSString *path = [self pathInNonExpiringCacheSizedKey:sizedKey];
    NSData *imageData = UIImageJPEGRepresentation(image, 0.9);
    return [imageData writeToFile:path atomically:YES];
}

- (void)deleteFromNonExpiringCacheSizedKey:(NSString *)sizedKey {
    NSString *path = [self pathInNonExpiringCacheSizedKey:sizedKey];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}



@end
