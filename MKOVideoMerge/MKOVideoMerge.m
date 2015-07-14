//
//  MKOVideoMerge.m
//  VideoMergeDemo
//
//  Created by Mathias Köhnke on 12/07/15.
//  Copyright (c) 2015 Mathias Koehnke. All rights reserved.
//

#import "MKOVideoMerge.h"
#import <AVFoundation/AVFoundation.h>

@implementation MKOVideoMerge

+ (void)mergeVideoFiles:(NSArray *)fileURLs
             completion:(void(^)(NSURL *mergedVideoFile, NSError *error))completion {
    
    NSLog(@"Start merging video files ...");
    
    AVMutableComposition *composition = [[AVMutableComposition alloc] init];
    AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    NSMutableArray *instructions = [NSMutableArray new];
    
    __block BOOL errorOccurred = NO;
    __block CMTime currentTime = kCMTimeZero;
    __block CGSize size = CGSizeZero;
    __block int32_t highestFrameRate = 0;
    
    [fileURLs enumerateObjectsUsingBlock:^(NSURL *fileURL, NSUInteger idx, BOOL *stop) {
        #pragma unused(idx)

        NSDictionary *options = @{AVURLAssetPreferPreciseDurationAndTimingKey:@YES};
        AVURLAsset *sourceAsset = [AVURLAsset URLAssetWithURL:fileURL options:options];
        AVAssetTrack *videoAsset = [[sourceAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        AVAssetTrack *audioAsset = [[sourceAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        if (CGSizeEqualToSize(size, CGSizeZero)) { size = videoAsset.naturalSize; }
        
        int32_t currentFrameRate = (int)roundf(videoAsset.nominalFrameRate);
        highestFrameRate = (currentFrameRate > highestFrameRate) ? currentFrameRate : highestFrameRate;
        
        NSLog(@"* %@ (%dfps)", [fileURL lastPathComponent], currentFrameRate);
        
        // According to Apple placing multiple video segments on the same composition track can potentially lead to dropping frames
        // at the transitions between video segments. Therefore we trim the first and last frame of each video.
        // https://developer.apple.com/library/ios/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html
        CMTime trimmingTime = CMTimeMake(lround(videoAsset.naturalTimeScale / videoAsset.nominalFrameRate), videoAsset.naturalTimeScale);
        CMTimeRange timeRange = CMTimeRangeMake(trimmingTime, CMTimeSubtract(videoAsset.timeRange.duration, trimmingTime));
        
        NSError *videoError;
        BOOL videoResult = [videoTrack insertTimeRange:timeRange ofTrack:videoAsset atTime:currentTime error:&videoError];
        
        NSError *audioError;
        BOOL audioResult = [audioTrack insertTimeRange:timeRange ofTrack:audioAsset atTime:currentTime error:&audioError];

        if(!videoResult || !audioResult || videoError || audioError) {
            if (completion) completion(nil, videoError? : audioError);
            errorOccurred = YES;
            *stop = YES;
        } else {
            AVMutableVideoCompositionInstruction *videoCompositionInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
            videoCompositionInstruction.timeRange = CMTimeRangeMake(currentTime, timeRange.duration);
            videoCompositionInstruction.layerInstructions = @[[AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack]];
            [instructions addObject:videoCompositionInstruction];
            
            currentTime = CMTimeAdd(currentTime, timeRange.duration);
        }
    }];
    
    if (errorOccurred == NO) {
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality];
        NSString *fileName = [MKOVideoMerge generateFileName];
        NSString *filePath = [MKOVideoMerge documentsPathWithFilePath:fileName];
        exportSession.outputURL = [NSURL fileURLWithPath:filePath];
        exportSession.outputFileType = AVFileTypeMPEG4;
        exportSession.shouldOptimizeForNetworkUse = YES;
        
        AVMutableVideoComposition *mutableVideoComposition = [AVMutableVideoComposition videoComposition];
        mutableVideoComposition.instructions = instructions;
        mutableVideoComposition.frameDuration = CMTimeMake(1, highestFrameRate);
        mutableVideoComposition.renderSize = size;
        exportSession.videoComposition = mutableVideoComposition;
        
        NSLog(@"Composition Duration: %ld seconds", lroundf(CMTimeGetSeconds(composition.duration)));
        NSLog(@"Composition Framerate: %d fps", highestFrameRate);
        
        void(^exportCompletion)(void) = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(exportSession.outputURL, exportSession.error);
            });
        };
        
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            switch (exportSession.status) {
                case AVAssetExportSessionStatusFailed:{
                    exportCompletion();
                    break;
                }
                case AVAssetExportSessionStatusCancelled:{
                    exportCompletion();
                    break;
                }
                case AVAssetExportSessionStatusCompleted: {
                    NSLog(@"Successfully merged video files into: %@", fileName);
                    exportCompletion();
                    break;
                }
                case AVAssetExportSessionStatusUnknown: {
                    NSLog(@"Export Status: Unknown");
                }
                case AVAssetExportSessionStatusExporting : {
                    NSLog(@"Export Status: Exporting");
                }
                case AVAssetExportSessionStatusWaiting: {
                    NSLog(@"Export Status: Wating");
                }
            };
        }];
    }
}

+ (NSURL *)applicationDocumentsDirectory {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

+ (NSString *)documentsPathWithFilePath:(NSString *)filePath {
    return [[MKOVideoMerge applicationDocumentsDirectory].path stringByAppendingPathComponent:filePath];
}

+ (NSString *)generateFileName {
    return [NSString stringWithFormat:@"video-%@.mp4", [[NSProcessInfo processInfo] globallyUniqueString]];
}

@end