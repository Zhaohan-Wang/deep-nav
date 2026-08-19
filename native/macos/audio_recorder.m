#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <signal.h>
#import <stdatomic.h>
#import <time.h>
#import <unistd.h>

static volatile sig_atomic_t should_stop = 0;
static atomic_ullong written_frames = 0;

static void handle_signal(int signal_number) {
	(void)signal_number;
	should_stop = 1;
}

static uint64_t monotonic_us(void) {
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC_RAW, &now);
	return (uint64_t)now.tv_sec * 1000000ULL + (uint64_t)now.tv_nsec / 1000ULL;
}

static NSString *iso_utc(void) {
	NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
	formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
	return [formatter stringFromDate:[NSDate date]];
}

static void write_metadata(
	NSString *path,
	NSString *session_id,
	NSString *audio_path,
	uint64_t requested_start_us,
	uint64_t helper_start_us,
	double sample_rate,
	AVAudioChannelCount channels,
	NSString *status,
	NSString *error_message
) {
	NSDictionary *metadata = @{
		@"schema_version": @"1.0.0",
		@"session_id": session_id,
		@"audio_file": audio_path,
		@"format": @"linear_pcm_16bit_caf",
		@"sample_rate_hz": @(sample_rate),
		@"channels": @(channels),
		@"requested_godot_monotonic_us": @(requested_start_us),
		@"helper_started_monotonic_us": @(helper_start_us),
		@"metadata_written_utc": iso_utc(),
		@"written_frames": @(atomic_load(&written_frames)),
		@"duration_seconds": sample_rate > 0.0 ? @(atomic_load(&written_frames) / sample_rate) : @0,
		@"status": status,
		@"error": error_message ?: @"",
	};
	NSData *json = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:nil];
	[json writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		if (argc < 5) {
			fprintf(stderr, "usage: %s AUDIO_PATH META_PATH SESSION_ID GODOT_MONOTONIC_US\n", argv[0]);
			return 64;
		}
		signal(SIGTERM, handle_signal);
		signal(SIGINT, handle_signal);
		NSString *audio_path = [NSString stringWithUTF8String:argv[1]];
		NSString *meta_path = [NSString stringWithUTF8String:argv[2]];
		NSString *session_id = [NSString stringWithUTF8String:argv[3]];
		uint64_t requested_start_us = strtoull(argv[4], NULL, 10);
		uint64_t helper_start_us = monotonic_us();

		AVAudioEngine *engine = [[AVAudioEngine alloc] init];
		AVAudioInputNode *input = engine.inputNode;
		AVAudioFormat *format = [input inputFormatForBus:0];
		if (format.sampleRate <= 0.0 || format.channelCount == 0) {
			write_metadata(meta_path, session_id, audio_path, requested_start_us, helper_start_us, 0.0, 0, @"failed", @"no microphone input format");
			return 2;
		}
		NSDictionary *settings = @{
			AVFormatIDKey: @(kAudioFormatLinearPCM),
			AVSampleRateKey: @(format.sampleRate),
			AVNumberOfChannelsKey: @(format.channelCount),
			AVLinearPCMBitDepthKey: @16,
			AVLinearPCMIsFloatKey: @NO,
			AVLinearPCMIsBigEndianKey: @NO,
			AVLinearPCMIsNonInterleaved: @(!format.isInterleaved),
		};
		NSError *file_error = nil;
		AVAudioFile *file = [[AVAudioFile alloc]
			initForWriting:[NSURL fileURLWithPath:audio_path]
			settings:settings
			commonFormat:format.commonFormat
			interleaved:format.isInterleaved
			error:&file_error
		];
		if (file == nil) {
			write_metadata(meta_path, session_id, audio_path, requested_start_us, helper_start_us, format.sampleRate, format.channelCount, @"failed", file_error.localizedDescription);
			return 3;
		}
		__block NSString *write_error_message = nil;
		[input installTapOnBus:0 bufferSize:4096 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
			(void)when;
			if (write_error_message != nil) return;
			NSError *write_error = nil;
			if (![file writeFromBuffer:buffer error:&write_error]) {
				write_error_message = write_error.localizedDescription ?: @"unknown audio write error";
				should_stop = 1;
				return;
			}
			atomic_fetch_add(&written_frames, buffer.frameLength);
		}];
		NSError *start_error = nil;
		if (![engine startAndReturnError:&start_error]) {
			[input removeTapOnBus:0];
			write_metadata(meta_path, session_id, audio_path, requested_start_us, helper_start_us, format.sampleRate, format.channelCount, @"failed", start_error.localizedDescription);
			return 4;
		}
		write_metadata(meta_path, session_id, audio_path, requested_start_us, helper_start_us, format.sampleRate, format.channelCount, @"recording", @"");
		while (!should_stop) {
			usleep(100000);
		}
		[engine stop];
		[input removeTapOnBus:0];
		write_metadata(
			meta_path, session_id, audio_path, requested_start_us, helper_start_us,
			format.sampleRate, format.channelCount,
			write_error_message == nil ? @"complete" : @"failed", write_error_message
		);
		return write_error_message == nil ? 0 : 5;
	}
}
