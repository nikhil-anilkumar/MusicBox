#import "AudioDecoder.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#include "dr_flac.h"
#include "stb_vorbis_api.h"

static NSError *MBError(NSString *msg) {
    return [NSError errorWithDomain:@"MusicBox" code:1 userInfo:@{NSLocalizedDescriptionKey: msg}];
}

#pragma mark - Apple codecs (ExtAudioFile)

@interface MBExtAudioFileDecoder : NSObject <MBAudioDecoder> {
    ExtAudioFileRef _file;
}
- (id)initWithURL:(NSURL *)url error:(NSError **)error;
@end

@implementation MBExtAudioFileDecoder
@synthesize sampleRate = _sampleRate, channels = _channels, totalFrames = _totalFrames;

- (id)initWithURL:(NSURL *)url error:(NSError **)error {
    if ((self = [super init])) {
        OSStatus st = ExtAudioFileOpenURL((__bridge CFURLRef)url, &_file);
        if (st != noErr) { if (error) *error = MBError([NSString stringWithFormat:@"Cannot open audio file (%d)", (int)st]); return nil; }
        AudioStreamBasicDescription fileFmt; UInt32 sz = sizeof(fileFmt);
        ExtAudioFileGetProperty(_file, kExtAudioFileProperty_FileDataFormat, &sz, &fileFmt);
        _sampleRate = fileFmt.mSampleRate > 0 ? fileFmt.mSampleRate : 44100;
        _channels = fileFmt.mChannelsPerFrame >= 2 ? 2 : 1;

        AudioStreamBasicDescription client = {0};
        client.mSampleRate = _sampleRate;
        client.mFormatID = kAudioFormatLinearPCM;
        client.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        client.mBitsPerChannel = 16;
        client.mChannelsPerFrame = _channels;
        client.mBytesPerFrame = 2 * _channels;
        client.mFramesPerPacket = 1;
        client.mBytesPerPacket = client.mBytesPerFrame;
        st = ExtAudioFileSetProperty(_file, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client);
        if (st != noErr) { if (error) *error = MBError([NSString stringWithFormat:@"Unsupported audio format (%d)", (int)st]); return nil; }

        SInt64 len = -1; sz = sizeof(len);
        if (ExtAudioFileGetProperty(_file, kExtAudioFileProperty_FileLengthFrames, &sz, &len) != noErr) len = -1;
        _totalFrames = len;
    }
    return self;
}

- (UInt32)readFrames:(UInt32)frames into:(SInt16 *)buffer {
    AudioBufferList abl;
    abl.mNumberBuffers = 1;
    abl.mBuffers[0].mNumberChannels = _channels;
    abl.mBuffers[0].mDataByteSize = frames * 2 * _channels;
    abl.mBuffers[0].mData = buffer;
    UInt32 n = frames;
    if (ExtAudioFileRead(_file, &n, &abl) != noErr) return 0;
    return n;
}

- (BOOL)seekToFrame:(SInt64)frame { return ExtAudioFileSeek(_file, frame) == noErr; }
- (void)dealloc { if (_file) ExtAudioFileDispose(_file); }
@end

#pragma mark - FLAC (dr_flac)

@interface MBFLACDecoder : NSObject <MBAudioDecoder> {
    drflac *_flac;
    SInt16 *_scratch; UInt32 _scratchFrames;
}
- (id)initWithURL:(NSURL *)url error:(NSError **)error;
@end

@implementation MBFLACDecoder
@synthesize sampleRate = _sampleRate, channels = _channels, totalFrames = _totalFrames;

- (id)initWithURL:(NSURL *)url error:(NSError **)error {
    if ((self = [super init])) {
        _flac = drflac_open_file(url.path.fileSystemRepresentation, NULL);
        if (!_flac) { if (error) *error = MBError(@"Invalid FLAC file"); return nil; }
        _sampleRate = _flac->sampleRate;
        _channels = _flac->channels >= 2 ? 2 : 1;
        _totalFrames = _flac->totalPCMFrameCount ? (SInt64)_flac->totalPCMFrameCount : -1;
    }
    return self;
}

- (UInt32)readFrames:(UInt32)frames into:(SInt16 *)buffer {
    if (_flac->channels <= 2) return (UInt32)drflac_read_pcm_frames_s16(_flac, frames, buffer);
    // Multichannel: keep the front left/right channels.
    if (_scratchFrames < frames) { free(_scratch); _scratch = malloc(frames * _flac->channels * 2); _scratchFrames = frames; }
    UInt32 n = (UInt32)drflac_read_pcm_frames_s16(_flac, frames, _scratch);
    for (UInt32 i = 0; i < n; i++) { buffer[i*2] = _scratch[i*_flac->channels]; buffer[i*2+1] = _scratch[i*_flac->channels+1]; }
    return n;
}

- (BOOL)seekToFrame:(SInt64)frame { return drflac_seek_to_pcm_frame(_flac, (drflac_uint64)frame); }
- (void)dealloc { if (_flac) drflac_close(_flac); free(_scratch); }
@end

#pragma mark - Ogg Vorbis (stb_vorbis)

@interface MBVorbisDecoder : NSObject <MBAudioDecoder> {
    stb_vorbis *_vorbis;
}
- (id)initWithURL:(NSURL *)url error:(NSError **)error;
@end

@implementation MBVorbisDecoder
@synthesize sampleRate = _sampleRate, channels = _channels, totalFrames = _totalFrames;

- (id)initWithURL:(NSURL *)url error:(NSError **)error {
    if ((self = [super init])) {
        int err = 0;
        _vorbis = stb_vorbis_open_filename(url.path.fileSystemRepresentation, &err, NULL);
        if (!_vorbis) { if (error) *error = MBError([NSString stringWithFormat:@"Invalid Ogg Vorbis file (%d)", err]); return nil; }
        stb_vorbis_info info = stb_vorbis_get_info(_vorbis);
        _sampleRate = info.sample_rate;
        _channels = info.channels >= 2 ? 2 : 1;
        unsigned int len = stb_vorbis_stream_length_in_samples(_vorbis);
        _totalFrames = len ? len : -1;
    }
    return self;
}

- (UInt32)readFrames:(UInt32)frames into:(SInt16 *)buffer {
    // stb_vorbis down-mixes to the requested channel count for us.
    return (UInt32)stb_vorbis_get_samples_short_interleaved(_vorbis, (int)_channels, buffer, (int)(frames * _channels));
}

- (BOOL)seekToFrame:(SInt64)frame { return stb_vorbis_seek(_vorbis, (unsigned int)frame) != 0; }
- (void)dealloc { if (_vorbis) stb_vorbis_close(_vorbis); }
@end

#pragma mark - iPod library items (AVAssetReader)

@interface MBAssetReaderDecoder : NSObject <MBAudioDecoder> {
    AVURLAsset *_asset;
    AVAssetTrack *_track;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_output;
    NSMutableData *_pending;   // decoded bytes not yet handed out
    NSUInteger _pendingOffset;
}
- (id)initWithURL:(NSURL *)url error:(NSError **)error;
@end

@implementation MBAssetReaderDecoder
@synthesize sampleRate = _sampleRate, channels = _channels, totalFrames = _totalFrames;

- (id)initWithURL:(NSURL *)url error:(NSError **)error {
    if ((self = [super init])) {
        _asset = [AVURLAsset URLAssetWithURL:url options:nil];
        NSArray *tracks = [_asset tracksWithMediaType:AVMediaTypeAudio];
        if (tracks.count == 0) { if (error) *error = MBError(@"No audio track (protected or unavailable item)"); return nil; }
        _track = tracks[0];
        _sampleRate = 44100; _channels = 2;
        Float64 secs = CMTimeGetSeconds(_asset.duration);
        _totalFrames = isfinite(secs) && secs > 0 ? (SInt64)(secs * _sampleRate) : -1;
        _pending = [NSMutableData data];
        if (![self startReaderAt:kCMTimeZero error:error]) return nil;
    }
    return self;
}

- (BOOL)startReaderAt:(CMTime)start error:(NSError **)error {
    [_reader cancelReading];
    NSError *e = nil;
    _reader = [[AVAssetReader alloc] initWithAsset:_asset error:&e];
    if (!_reader) { if (error) *error = e; return NO; }
    NSDictionary *settings = @{AVFormatIDKey: @(kAudioFormatLinearPCM),
                               AVSampleRateKey: @(_sampleRate),
                               AVNumberOfChannelsKey: @(_channels),
                               AVLinearPCMBitDepthKey: @16,
                               AVLinearPCMIsFloatKey: @NO,
                               AVLinearPCMIsBigEndianKey: @NO,
                               AVLinearPCMIsNonInterleaved: @NO};
    _output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:_track outputSettings:settings];
    [_reader addOutput:_output];
    _reader.timeRange = CMTimeRangeMake(start, kCMTimePositiveInfinity);
    _pending.length = 0; _pendingOffset = 0;
    if (![_reader startReading]) { if (error) *error = _reader.error ?: MBError(@"Cannot read item"); return NO; }
    return YES;
}

- (UInt32)readFrames:(UInt32)frames into:(SInt16 *)buffer {
    NSUInteger want = frames * 2 * _channels, got = 0;
    while (got < want) {
        if (_pendingOffset >= _pending.length) {
            _pending.length = 0; _pendingOffset = 0;
            if (_reader.status != AVAssetReaderStatusReading) break;
            CMSampleBufferRef sb = [_output copyNextSampleBuffer];
            if (!sb) break;
            CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
            size_t len = bb ? CMBlockBufferGetDataLength(bb) : 0;
            if (len) { _pending.length = len; CMBlockBufferCopyDataBytes(bb, 0, len, _pending.mutableBytes); }
            CFRelease(sb);
            continue;
        }
        NSUInteger n = MIN(want - got, _pending.length - _pendingOffset);
        memcpy((char *)buffer + got, (char *)_pending.mutableBytes + _pendingOffset, n);
        got += n; _pendingOffset += n;
    }
    return (UInt32)(got / (2 * _channels));
}

- (BOOL)seekToFrame:(SInt64)frame { return [self startReaderAt:CMTimeMake(frame, (int32_t)_sampleRate) error:NULL]; }
- (void)dealloc { [_reader cancelReading]; }
@end

#pragma mark - Factory

@implementation MBDecoderFactory

+ (NSSet *)supportedExtensions {
    static NSSet *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exts = [NSSet setWithObjects:@"mp3", @"m4a", @"m4b", @"m4p", @"aac", @"adts", @"mp4", @"3gp", @"3g2",
                @"wav", @"wave", @"aif", @"aiff", @"aifc", @"caf", @"au", @"snd", @"amr",
                @"flac", @"ogg", @"oga", nil];
    });
    return exts;
}

+ (id<MBAudioDecoder>)decoderForURL:(NSURL *)url error:(NSError **)error {
    if (![url isFileURL]) return [[MBAssetReaderDecoder alloc] initWithURL:url error:error];
    NSString *ext = url.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"flac"]) return [[MBFLACDecoder alloc] initWithURL:url error:error];
    if ([ext isEqualToString:@"ogg"] || [ext isEqualToString:@"oga"]) return [[MBVorbisDecoder alloc] initWithURL:url error:error];
    id<MBAudioDecoder> d = [[MBExtAudioFileDecoder alloc] initWithURL:url error:error];
    // Some .mp4/.m4a containers are only readable through AVFoundation; fall back to it.
    if (!d) d = [[MBAssetReaderDecoder alloc] initWithURL:url error:error];
    return d;
}
@end

#pragma mark - Tags for FLAC / Ogg

static void MBApplyVorbisComment(NSMutableDictionary *tags, const char *c, NSUInteger len) {
    NSString *s = [[NSString alloc] initWithBytes:c length:len encoding:NSUTF8StringEncoding];
    NSRange eq = [s rangeOfString:@"="];
    if (!s || eq.location == NSNotFound) return;
    NSString *key = [[s substringToIndex:eq.location] uppercaseString];
    NSString *val = [s substringFromIndex:eq.location + 1];
    if ([key isEqualToString:@"TITLE"]) tags[@"title"] = val;
    else if ([key isEqualToString:@"ARTIST"]) tags[@"artist"] = val;
    else if ([key isEqualToString:@"ALBUM"]) tags[@"album"] = val;
}

static void MBFLACMeta(void *ud, drflac_metadata *m) {
    NSMutableDictionary *tags = (__bridge NSMutableDictionary *)ud;
    if (m->type == DRFLAC_METADATA_BLOCK_TYPE_VORBIS_COMMENT) {
        drflac_vorbis_comment_iterator it;
        drflac_init_vorbis_comment_iterator(&it, m->data.vorbis_comment.commentCount, m->data.vorbis_comment.pComments);
        drflac_uint32 len; const char *c;
        while ((c = drflac_next_vorbis_comment(&it, &len))) MBApplyVorbisComment(tags, c, len);
    } else if (m->type == DRFLAC_METADATA_BLOCK_TYPE_PICTURE && !tags[@"artwork"] && m->data.picture.pPictureData) {
        tags[@"artwork"] = [NSData dataWithBytes:m->data.picture.pPictureData length:m->data.picture.pictureDataSize];
    }
}

@implementation MBTagReader
+ (NSDictionary *)tagsForFileURL:(NSURL *)url {
    NSMutableDictionary *tags = [NSMutableDictionary dictionary];
    NSString *ext = url.pathExtension.lowercaseString;
    const char *path = url.path.fileSystemRepresentation;
    if ([ext isEqualToString:@"flac"]) {
        drflac *f = drflac_open_file_with_metadata(path, MBFLACMeta, (__bridge void *)tags, NULL);
        if (f) {
            if (f->sampleRate) tags[@"duration"] = @((double)f->totalPCMFrameCount / f->sampleRate);
            drflac_close(f);
        }
    } else if ([ext isEqualToString:@"ogg"] || [ext isEqualToString:@"oga"]) {
        int err = 0;
        stb_vorbis *v = stb_vorbis_open_filename(path, &err, NULL);
        if (v) {
            stb_vorbis_comment c = stb_vorbis_get_comment(v);
            for (int i = 0; i < c.comment_list_length; i++) MBApplyVorbisComment(tags, c.comment_list[i], strlen(c.comment_list[i]));
            tags[@"duration"] = @(stb_vorbis_stream_length_in_seconds(v));
            stb_vorbis_close(v);
        }
    }
    return tags;
}
@end

#pragma mark - Technical info

static NSString *MBCodecName(UInt32 fmt, UInt32 flags) {
    switch (fmt) {
        case kAudioFormatMPEGLayer3: return @"MPEG-1 Layer 3 (MP3)";
        case kAudioFormatMPEGLayer2: return @"MPEG-1 Layer 2 (MP2)";
        case kAudioFormatMPEG4AAC: return @"AAC-LC";
        case kAudioFormatMPEG4AAC_HE: return @"HE-AAC";
        case kAudioFormatMPEG4AAC_HE_V2: return @"HE-AAC v2";
        case kAudioFormatAppleLossless: return @"Apple Lossless (ALAC)";
        case kAudioFormatAMR: return @"AMR-NB";
        case kAudioFormatAppleIMA4: return @"IMA 4:1 ADPCM";
        case kAudioFormatULaw: return @"µ-law";
        case kAudioFormatALaw: return @"A-law";
        case kAudioFormatLinearPCM:
            return [NSString stringWithFormat:@"PCM %@%@", (flags & kAudioFormatFlagIsFloat) ? @"float" : @"integer",
                    (flags & kAudioFormatFlagIsBigEndian) ? @", big-endian" : @", little-endian"];
        default: {
            char c[5] = { (char)(fmt >> 24), (char)(fmt >> 16), (char)(fmt >> 8), (char)fmt, 0 };
            return [NSString stringWithFormat:@"'%s'", c];
        }
    }
}

static NSString *MBContainerName(UInt32 type) {
    switch (type) {
        case kAudioFileMP3Type: return @"MP3";
        case kAudioFileMP2Type: return @"MP2";
        case kAudioFileM4AType: return @"MPEG-4 Audio (M4A)";
        case kAudioFileMPEG4Type: return @"MPEG-4";
        case kAudioFileAAC_ADTSType: return @"ADTS (raw AAC)";
        case kAudioFileWAVEType: return @"WAVE";
        case kAudioFileAIFFType: return @"AIFF";
        case kAudioFileAIFCType: return @"AIFF-C";
        case kAudioFileCAFType: return @"Core Audio Format (CAF)";
        case kAudioFileNextType: return @"NeXT/Sun (AU)";
        case kAudioFileAMRType: return @"AMR";
        case kAudioFile3GPType: return @"3GPP";
        case kAudioFile3GP2Type: return @"3GPP2";
        default: return nil;
    }
}

@implementation MBTagReader (Technical)
+ (NSDictionary *)technicalInfoForFileURL:(NSURL *)url {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSString *ext = url.pathExtension.lowercaseString;
    unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:NULL] fileSize];
    const char *path = url.path.fileSystemRepresentation;

    if ([ext isEqualToString:@"flac"]) {
        drflac *f = drflac_open_file(path, NULL);
        if (f) {
            info[@"codec"] = @"FLAC (Free Lossless Audio Codec)";
            info[@"container"] = @"FLAC";
            info[@"decoder"] = @"dr_flac";
            info[@"sampleRate"] = @(f->sampleRate);
            info[@"bitDepth"] = @(f->bitsPerSample);
            info[@"channels"] = @(f->channels);
            if (f->sampleRate) info[@"duration"] = @((double)f->totalPCMFrameCount / f->sampleRate);
            drflac_close(f);
        }
    } else if ([ext isEqualToString:@"ogg"] || [ext isEqualToString:@"oga"]) {
        int err = 0;
        stb_vorbis *v = stb_vorbis_open_filename(path, &err, NULL);
        if (v) {
            stb_vorbis_info vi = stb_vorbis_get_info(v);
            stb_vorbis_comment c = stb_vorbis_get_comment(v);
            info[@"codec"] = @"Vorbis";
            info[@"container"] = @"Ogg";
            info[@"decoder"] = @"stb_vorbis";
            info[@"sampleRate"] = @(vi.sample_rate);
            info[@"channels"] = @(vi.channels);
            info[@"duration"] = @(stb_vorbis_stream_length_in_seconds(v));
            if (c.vendor && *c.vendor) info[@"encoder"] = [NSString stringWithUTF8String:c.vendor];
            stb_vorbis_close(v);
        }
    } else {
        AudioFileID af;
        if (AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &af) == noErr) {
            AudioStreamBasicDescription d; UInt32 sz = sizeof(d);
            if (AudioFileGetProperty(af, kAudioFilePropertyDataFormat, &sz, &d) == noErr) {
                info[@"codec"] = MBCodecName(d.mFormatID, d.mFormatFlags);
                info[@"sampleRate"] = @(d.mSampleRate);
                info[@"channels"] = @(d.mChannelsPerFrame);
                if (d.mFormatID == kAudioFormatLinearPCM) info[@"bitDepth"] = @(d.mBitsPerChannel);
                if (d.mFormatID == kAudioFormatAppleLossless) {
                    static const int depths[] = {0, 16, 20, 24, 32};
                    if (d.mFormatFlags >= 1 && d.mFormatFlags <= 4) info[@"bitDepth"] = @(depths[d.mFormatFlags]);
                }
            }
            UInt32 type = 0; sz = sizeof(type);
            if (AudioFileGetProperty(af, kAudioFilePropertyFileFormat, &sz, &type) == noErr) {
                NSString *n = MBContainerName(type);
                if (n) info[@"container"] = n;
            }
            UInt32 br = 0; sz = sizeof(br);
            if (AudioFileGetProperty(af, kAudioFilePropertyBitRate, &sz, &br) == noErr && br > 0) info[@"bitrate"] = @(br / 1000);
            Float64 dur = 0; sz = sizeof(dur);
            if (AudioFileGetProperty(af, kAudioFilePropertyEstimatedDuration, &sz, &dur) == noErr && dur > 0) info[@"duration"] = @(dur);
            AudioFileClose(af);
        }
        info[@"decoder"] = @"iOS Core Audio (ExtAudioFile)";
        // Encoder tag (e.g. LAME, iTunes) when AVFoundation exposes one.
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        for (NSString *fmt in asset.availableMetadataFormats) {
            for (AVMetadataItem *it in [asset metadataForFormat:fmt]) {
                NSString *key = [it.key description];
                if (([key isEqualToString:@"TSSE"] || [key isEqualToString:@"TSS"] || [key hasSuffix:@"too"]) &&
                    [it.value isKindOfClass:[NSString class]]) info[@"encoder"] = (NSString *)it.value;
            }
        }
    }
    // Average bitrate from file size when the container doesn't state it (lossless, Ogg).
    double dur = [info[@"duration"] doubleValue];
    if (!info[@"bitrate"] && dur > 0 && size > 0) info[@"bitrate"] = @((NSUInteger)(size * 8 / dur / 1000));
    return info;
}
@end
