#import <Foundation/Foundation.h>

@interface OpenCVWrapper : NSObject
+ (NSString *)openCVVersion;
+ (void)analyzeVideo:(NSString *)inputPath outputPath:(NSString *)outputPath; // <-- Just a prototype here!
@end

