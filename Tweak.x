#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#define LOG_FILE @"/var/mobile/Library/Logs/PleaseDontStopTheMusic.log"

// Logging function that writes timestamped messages to file
static void LogToFile(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [formatter stringFromDate:now];
    
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    FILE *file = fopen([LOG_FILE UTF8String], "a");
    if (file) {
        fputs([logEntry UTF8String], file);
        fclose(file);
    }
    
    // Also log to system log for debugging
    NSLog(@"[PleaseDontStopTheMusic] %@", message);
}
// PleaseDontStopTheMusic
//
// Goal: let a second app (TikTok, a game, etc.) play audio WITHOUT pausing the
// music that is already playing, while leaving that music app in full control of
// the lock screen / Control Center "Now Playing" transport controls.
//
// Key insight: an audio session that opts into MixWithOthers is treated by iOS
// as a *secondary* source. It will not interrupt others, but it also gives up
// the Now Playing controls. So we must NOT force mixing on the primary music
// app, or its lock-screen skip/pause controls vanish (the old behaviour, and
// exactly the bug we are fixing).
//
// Heuristic: use -isOtherAudioPlaying at the moment an app configures its
// session.
//   * No other audio playing  -> this app is the primary source. Leave it
//     untouched so it keeps Now Playing controls and normal behaviour.
//   * Other audio already playing -> this app is the "intruder". Force it to
//     mix so it joins the existing playback instead of interrupting it (and so
//     it doesn't steal the lock-screen controls from the music app).

%hook AVAudioSession

// Older convenience setter (category only).
- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    LogToFile(@"setCategory:error: called with category='%@', isOtherAudioPlaying=%@", category, self.isOtherAudioPlaying ? @"YES" : @"NO");
    if (self.isOtherAudioPlaying) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            // SoloAmbient cannot mix; Ambient is the mixable equivalent.
            return %orig(AVAudioSessionCategoryAmbient, outError);
        }
        if ([category isEqualToString:AVAudioSessionCategoryPlayback]) {
            // Route through the mode/options setter (also hooked) so the
            // MixWithOthers option is applied.
            return [self setCategory:category
                                mode:AVAudioSessionModeDefault
                             options:AVAudioSessionCategoryOptionMixWithOthers
                               error:outError];
        }
    }
    return %orig;
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    LogToFile(@"setCategory:mode:options:error: called with category='%@', mode='%@', options=0x%lx, isOtherAudioPlaying=%@", category, mode, (unsigned long)options, self.isOtherAudioPlaying ? @"YES" : @"NO");
    if (self.isOtherAudioPlaying) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            category = AVAudioSessionCategoryAmbient;
        }
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, options, outError);
}

// Modern setter (iOS 11+). This is the one TikTok and most current apps use,
// and it was previously unhooked — which is why they interrupted background
// audio. Hooking it here is the core fix for the "audio stops" bug.
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    LogToFile(@"setCategory:mode:routeSharingPolicy:options:error: called with category='%@', mode='%@', policy=%ld, options=0x%lx, isOtherAudioPlaying=%@", category, mode, (long)policy, (unsigned long)options, self.isOtherAudioPlaying ? @"YES" : @"NO");
    if (self.isOtherAudioPlaying) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            category = AVAudioSessionCategoryAmbient;
        }
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, policy, options, outError);
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    LogToFile(@"setCategory:withOptions:error: called with category='%@', options=0x%lx, isOtherAudioPlaying=%@", category, (unsigned long)options, self.isOtherAudioPlaying ? @"YES" : @"NO");
    if (self.isOtherAudioPlaying) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            category = AVAudioSessionCategoryAmbient;
        }
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, options, outError);
}

// Some apps configure their category once (when nothing else is playing) and
// only call -setActive: later. Catch that case at activation time: if other
// audio is playing and we are about to activate a non-mixing interrupting
// session, re-apply the category with MixWithOthers so we don't cut it off.
- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    LogToFile(@"setActive:error: called with active=%@, isOtherAudioPlaying=%@, currentCategory='%@', categoryOptions=0x%lx", active ? @"YES" : @"NO", self.isOtherAudioPlaying ? @"YES" : @"NO", self.category, (unsigned long)self.categoryOptions);
    if (active && self.isOtherAudioPlaying
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            cat = AVAudioSessionCategoryAmbient;
        }
        [self setCategory:cat
                     mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers
                    error:nil];
    }
    return %orig;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    LogToFile(@"setActive:withOptions:error: called with active=%@, options=0x%lx, isOtherAudioPlaying=%@, currentCategory='%@', categoryOptions=0x%lx", active ? @"YES" : @"NO", (unsigned long)options, self.isOtherAudioPlaying ? @"YES" : @"NO", self.category, (unsigned long)self.categoryOptions);
    if (active && self.isOtherAudioPlaying
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            cat = AVAudioSessionCategoryAmbient;
        }
        [self setCategory:cat
                     mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers
                    error:nil];
    }
    return %orig;
}

%end

%ctor {
    NSLog(@"[PleaseDontStopTheMusic] loaded");
    LogToFile(@"PleaseDontStopTheMusic tweak initialized at startup");
}
