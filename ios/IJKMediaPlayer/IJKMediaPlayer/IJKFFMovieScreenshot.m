//
//  IJKFFScreenshot.m
//  IJKMediaFramework
//
//  Created by 翟泉 on 2019/4/24.
//  Copyright © 2019 bilibili. All rights reserved.
//

#import "IJKFFMovieScreenshot.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/pixdesc.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"

@interface IJKFFMovieScreenshot ()
{
    AVFormatContext *_formatContext;
    AVFrame *_videoFrame;
    AVCodecContext *_codecContext;
    int _videoStream;
}
@end

@implementation IJKFFMovieScreenshot

+ (UIImage *)screenshotWithVideo:(NSString *)path forSeconds:(CGFloat)seconds {
    IJKFFMovieScreenshot *screenshot = [[IJKFFMovieScreenshot alloc] initWithVideo:path];
    return [screenshot screenshotForSeconds:seconds];
}

- (instancetype)initWithVideo:(NSString *)path {
    if (self = [super init]) {
        _formatContext = NULL;
        _videoFrame = NULL;
        _codecContext = NULL;
        _videoStream = -1;
        
        av_register_all();
        if (![self openVideo:path]) {
            return nil;
        }
        if (![self openVideoStream]) {
            return nil;
        }
    }
    return self;
}

- (UIImage *)screenshotForSeconds:(CGFloat)seconds {
    [self seekToSeconds:seconds];
    return [self decodeFrame];
}

- (void)dealloc {
    if (_codecContext) {
        avcodec_close(_codecContext);
    }

    if (_videoFrame) {
        av_frame_free(&_videoFrame);
    }

    if (_formatContext) {
        avformat_free_context(_formatContext);
    }
}

- (BOOL)openVideo:(NSString *)filePath {
    AVFormatContext *formatContext = avformat_alloc_context();
    if (avformat_open_input(&formatContext, filePath.UTF8String, NULL, NULL) < 0) {
        if (formatContext) {
            avformat_free_context(formatContext);
        }
        return NO;
    }
    if (avformat_find_stream_info(formatContext, NULL) < 0) {
        avformat_close_input(&formatContext);
        return NO;
    }
    av_dump_format(formatContext, 0, filePath.lastPathComponent.UTF8String, false);

    _formatContext = formatContext;
    return YES;
}

- (BOOL)openVideoStream {
    for (NSNumber *n in  [self collectStreamsWithCodecType:AVMEDIA_TYPE_VIDEO]) {
        const int streamIndex = n.intValue;
        if (0 == (_formatContext->streams[streamIndex]->disposition & AV_DISPOSITION_ATTACHED_PIC)) {
            _codecContext = _formatContext->streams[streamIndex]->codec;
            AVCodec *codec = avcodec_find_decoder(_codecContext->codec_id);
            if (!codec) {
                continue;
            }
            if (avcodec_open2(_codecContext, codec, NULL) < 0) {
                continue;
            }
            _videoFrame = av_frame_alloc();
            if (!_videoFrame) {
                continue;
            }
            _videoStream = streamIndex;
            return YES;
        }
    }
    return NO;
}

- (BOOL)seekToSeconds:(CGFloat)seconds {
    CGFloat timebase;
    AVStream *stream = _formatContext->streams[_videoStream];
    if (stream->time_base.den && stream->time_base.num) {
        timebase = av_q2d(stream->time_base);
    }
    else if(stream->codec->time_base.den && stream->codec->time_base.num) {
        timebase = av_q2d(stream->codec->time_base);
    }
    else {
        timebase = 0.04;
    }

    int64_t ts = (int64_t)(seconds / timebase);
    avformat_seek_file(_formatContext, _videoStream, ts, ts, ts, AVSEEK_FLAG_FRAME);
    avcodec_flush_buffers(_codecContext);
    return YES;
}

- (UIImage *)decodeFrame {
    BOOL finished = NO;
    AVPacket packet;
    while (!finished) {
        if (av_read_frame(_formatContext, &packet) < 0) {
            break;
        }
        if (packet.stream_index != _videoStream) {
            av_free_packet(&packet);
            continue;
        }
        while (packet.size > 0) {
            int gotframe = 0;
            if (avcodec_decode_video2(_codecContext, _videoFrame, &gotframe, &packet) < 0) {
                break;
            }
            if (gotframe == 0) {
                break;
            }
            if (!_videoFrame->data[0]) {
                break;
            }
            CGFloat width = _codecContext->width, height = _codecContext->height;
            AVPicture picture;;
            if (avpicture_alloc(&picture, AV_PIX_FMT_RGB24, width, height) != 0) {
                break;
            }
            struct SwsContext *swsContext = NULL;
            swsContext = sws_getCachedContext(swsContext, width, height, _codecContext->pix_fmt, width, height, AV_PIX_FMT_RGB24, SWS_FAST_BILINEAR, NULL, NULL, NULL);
            sws_scale(swsContext, (const uint8_t **)_videoFrame->data, _videoFrame->linesize, 0, height, picture.data, picture.linesize);
            NSUInteger linesize = picture.linesize[0];
            NSData *rgb = [NSData dataWithBytes:picture.data[0] length:linesize * height];
            UIImage *image = [self imageWithRGBData:rgb linesize:linesize width:width height:height];
            avpicture_free(&picture);
            av_free_packet(&packet);
            return image;
        }
        av_free_packet(&packet);
    }
    return nil;
}

- (NSArray *)collectStreamsWithCodecType:(enum AVMediaType)codecType {
    NSMutableArray *videoStreams = [NSMutableArray array];
    for (int i=0; i<_formatContext->nb_streams; ++i) {
        if (_formatContext->streams[i]->codec->codec_type == codecType) {
            [videoStreams addObject:@(i)];
        }
    }
    return [videoStreams copy];
}

- (UIImage *)imageWithRGBData:(NSData *)data linesize:(NSInteger)linesize width:(CGFloat)width height:(CGFloat)height
{
    UIImage *image = nil;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)(data));
    if (provider) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        if (colorSpace) {
            CGImageRef imageRef = CGImageCreate(width, height, 8, 24, linesize, colorSpace, kCGBitmapByteOrderDefault, provider, NULL, YES, kCGRenderingIntentDefault);
            if (imageRef) {
                image = [UIImage imageWithCGImage:imageRef];
                CGImageRelease(imageRef);
            }
            CGColorSpaceRelease(colorSpace);
        }
        CGDataProviderRelease(provider);
    }
    return image;
}

@end

#pragma clang diagnostic pop
