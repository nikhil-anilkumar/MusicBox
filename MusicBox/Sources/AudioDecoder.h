// AudioDecoder: a uniform "give me interleaved 16-bit PCM" interface over
// several decoding back ends, so one playback engine can play every format.
//
//   MBExtAudioFileDecoder  - Apple's own codecs: MP3, AAC/M4A, ALAC, WAV, AIFF, CAF, AU, AMR
//   MBFLACDecoder          - FLAC (dr_flac)
//   MBVorbisDecoder        - Ogg Vorbis (stb_vorbis)
//   MBAssetReaderDecoder   - items from the device's iPod music library (ipod-library:// URLs)

#import <Foundation/Foundation.h>

@protocol MBAudioDecoder <NSObject>
@property (nonatomic, readonly) double sampleRate;
@property (nonatomic, readonly) UInt32 channels;      // 1 or 2
@property (nonatomic, readonly) SInt64 totalFrames;   // -1 if unknown
// Fill `buffer` with up to `frames` interleaved int16 frames. Returns frames written; 0 = end of stream.
- (UInt32)readFrames:(UInt32)frames into:(SInt16 *)buffer;
- (BOOL)seekToFrame:(SInt64)frame;
@end

@interface MBDecoderFactory : NSObject
+ (NSSet *)supportedExtensions;                       // lowercase, no dot
+ (id<MBAudioDecoder>)decoderForURL:(NSURL *)url error:(NSError **)error;
@end

// Tag / artwork reading for the formats AVFoundation does not understand.
@interface MBTagReader : NSObject
// Returns keys: "title", "artist", "album" (NSString), "duration" (NSNumber seconds), "artwork" (NSData)
+ (NSDictionary *)tagsForFileURL:(NSURL *)url;
@end

@interface MBTagReader (Technical)
// Technical details for the info screen. Keys (all optional): "codec", "container", "decoder", "encoder" (NSString),
// "sampleRate", "bitDepth", "channels", "bitrate" (kbps), "duration" (seconds) as NSNumber.
+ (NSDictionary *)technicalInfoForFileURL:(NSURL *)url;
@end
