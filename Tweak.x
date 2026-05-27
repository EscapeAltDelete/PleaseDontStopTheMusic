#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#define LOG_FILE @"/var/mobile/Library/Logs/PleaseDontStopTheMusic.log"

// Logging function that writes timestamped messages to file
// Logs to both file and NSLog for comprehensive debugging
static void LogToFile(NSString *format, ...) {
    // Entry logging
    NSLog(@"[PleaseDontStopTheMusic] LogToFile() called with format: %@", format);
    
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
        NSLog(@"[PleaseDontStopTheMusic] LogToFile() wrote to file successfully");
    } else {
        NSLog(@"[PleaseDontStopTheMusic] LogToFile() FAILED to open file at %s", [LOG_FILE UTF8String]);
    }
    
    // Also log to system log for debugging
    NSLog(@"[PleaseDontStopTheMusic] %@", message);
    
    // Exit logging
    NSLog(@"[PleaseDontStopTheMusic] LogToFile() exiting");
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
    LogToFile(@"");
    LogToFile(@">>> [HOOK ENTRY] setCategory:error:");
    LogToFile(@"    category = '%@'", category);
    LogToFile(@"    isOtherAudioPlaying = %@", self.isOtherAudioPlaying ? @"YES" : @"NO");
    
    if (self.isOtherAudioPlaying) {
        LogToFile(@"    [DECISION] Other audio IS playing - checking for SoloAmbient or Playback");
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            LogToFile(@"    [MODIFICATION] Category is SoloAmbient - converting to Ambient (mixable)");
            // SoloAmbient cannot mix; Ambient is the mixable equivalent.
            LogToFile(@"    [BEFORE %orig] Calling with category=AVAudioSessionCategoryAmbient");
            BOOL result = %orig(AVAudioSessionCategoryAmbient, outError);
            LogToFile(@"    [AFTER %orig] Returned: %@", result ? @"YES (success)" : @"NO (failure)");
            LogToFile(@"<<< [HOOK EXIT] setCategory:error: returning %@", result ? @"YES" : @"NO");
            return result;
        }
        if ([category isEqualToString:AVAudioSessionCategoryPlayback]) {
            LogToFile(@"    [MODIFICATION] Category is Playback - routing through mode/options setter with MixWithOthers");
            // Route through the mode/options setter (also hooked) so the
            // MixWithOthers option is applied.
            LogToFile(@"    [BEFORE %orig] Calling setCategory:mode:options:error: with MixWithOthers option");
            BOOL result = [self setCategory:category
                                        mode:AVAudioSessionModeDefault
                                     options:AVAudioSessionCategoryOptionMixWithOthers
                                       error:outError];
            LogToFile(@"    [AFTER recursive call] Returned: %@", result ? @"YES (success)" : @"NO (failure)");
            LogToFile(@"<<< [HOOK EXIT] setCategory:error: returning %@", result ? @"YES" : @"NO");
            return result;
        }
        LogToFile(@"    [DECISION] Category is neither SoloAmbient nor Playback - no modification needed");
    } else {
        LogToFile(@"    [DECISION] Other audio is NOT playing - no modification needed");
    }
    LogToFile(@"    [BEFORE %orig] Calling original with category='%@'", category);
    BOOL result = %orig;
    LogToFile(@"    [AFTER %orig] Returned: %@", result ? @"YES (success)" : @"NO (failure)");
    LogToFile(@"<<< [HOOK EXIT] setCategory:error: returning %@", result ? @"YES" : @"NO");
    return result;
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    LogToFile(@"");
    LogToFile(@">>> [HOOK ENTRY] setCategory:mode:options:error:");
    LogToFile(@"    category = '%@'", category);
    LogToFile(@"    mode = '%@'", mode);
    LogToFile(@"    options = 0x%lx (raw)", (unsigned long)options);
    LogToFile(@"    options contains MixWithOthers = %@", (options & AVAudioSessionCategoryOptionMixWithOthers) ? @"YES" : @"NO");
    LogToFile(@"    isOtherAudioPlaying = %@", self.isOtherAudioPlaying ? @"YES" : @"NO");
    
    if (self.isOtherAudioPlaying) {
        LogToFile(@"    [DECISION] Other audio IS playing - will apply mixing");
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            LogToFile(@"    [MODIFICATION] Category is SoloAmbient - converting to Ambient");
            category = AVAudioSessionCategoryAmbient;
        }
        LogToFile(@"    [MODIFICATION] Adding MixWithOthers option");
        LogToFile(@"    [BEFORE] options = 0x%lx", (unsigned long)options);
        options |= AVAudioSessionCategoryOptionMixWithOthers;
        LogToFile(@"    [AFTER] options = 0x%lx", (unsigned long)options);
        LogToFile(@"    [DECISION] About to call %orig with category='%@', mode='%@', options=0x%lx", category, mode, (unsigned long)options);
    } else {
        LogToFile(@"    [DECISION] Other audio is NOT playing - no modification needed");
        LogToFile(@"    [BEFORE %orig] Calling with original parameters");
    }
    
    LogToFile(@"    [BEFORE %orig] Calling original setCategory:mode:options:error:");
    BOOL result = %orig(category, mode, options, outError);
    LogToFile(@"    [AFTER %orig] Returned: %@", result ? @"YES (success)" : @"NO (failure)");
    LogToFile(@"<<< [HOOK EXIT] setCategory:mode:options:error: returning %@", result ? @"YES" : @"NO");
    LogToFile(@"");
    return result;
}

// Modern setter (iOS 11+). This is the one TikTok and most current apps use,
// and it was previously unhooked — which is why they interrupted background
// audio. Hooking it here is the core fix for the "audio stops" bug.
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    LogToFile(@"");
    LogToFile(@">>> [HOOK ENTRY] setCategory:mode:routeSharingPolicy:options:error: [CRITICAL - iOS 11+ setter]");
    LogToFile(@"    category = '%@'", category);
    LogToFile(@"    mode = '%@'", mode);
    LogToFile(@"    routeSharingPolicy = %ld", (long)policy);
    LogToFile(@"    options = 0x%lx (raw)", (unsigned long)options);
    LogToFile(@"    options contains MixWithOthers = %@", (options & AVAudioSessionCategoryOptionMixWithOthers) ? @"YES" : @"NO");
    LogToFile(@"    isOtherAudioPlaying = %@", self.isOtherAudioPlaying ? @"YES" : @"NO");
    LogToFile(@"    NOTE: This is the modern setter that TikTok and current apps use!");
    
    if (self.isOtherAudioPlaying) {
        LogToFile(@"    [DECISION] Other audio IS playing - will apply mixing");
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            LogToFile(@"    [MODIFICATION] Category is SoloAmbient - converting to Ambient");
            category = AVAudioSessionCategoryAmbient;
        }
        LogToFile(@"    [MODIFICATION] Adding MixWithOthers option");
        LogToFile(@"    [BEFORE] options = 0x%lx", (unsigned long)options);
        options |= AVAudioSessionCategoryOptionMixWithOthers;
        LogToFile(@"    [AFTER] options = 0x%lx", (unsigned long)options);
        LogToFile(@"    [DECISION] About to call %orig with category='%@', mode='%@', policy=%ld, options=0x%lx", category, mode, (long)policy, (unsigned long)options);
    } else {
        LogToFile(@"    [DECISION] Other audio is NOT playing - no modification needed");
        LogToFile(@"    [BEFORE %orig] Calling with original parameters");
    }
    
    LogToFile(@"    [BEFORE %orig] Calling original setCategory:mode:routeSharingPolicy:options:error:");
    BOOL result = %orig(category, mode, policy, options, outError);
    LogToFile(@"    [AFTER %orig] Returned: %@", result ? @"YES (success)" : @"NO (failure)");
    LogToFile(@"<<< [HOOK EXIT] setCategory:mode:routeSharingPolicy:options:error: returning %@", result ? @"YES" : @"NO");
    LogToFile(@"");
    return result;
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    LogToFile(@"");
    LogToFile(@">>> [HOOK ENTRY] setCategory:withOptions:error:");
    LogToFile(@"    category = '%@'", category);
    LogToFile(@"    options = 0x%lx (raw)", (unsigned long)options);
    LogToFile(@"    options contains MixWithOthers = %@", (options & AVAudioSessionCategoryOptionMixWithOthers) ? @"YES" : @"NO");
    LogToFile(@"    isOtherAudioPlaying = %@", self.isOtherAudioPlaying ? @"YES" : @"NO");
    
    if (self.isOtherAudioPlaying) {
        LogToFile(@"    [DECISION] Other audio IS playing - will apply mixing");
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            LogToFile(@"    [MODIFICATION] Category is SoloAmbient - converting to Ambient");
            category = AVAudioSessionCategoryAmbient;
        }
        LogToFile(@"    [MODIFICATION] Adding MixWithOthers option");
        LogToFile(@"    [BEFORE] options = 0x%lx", (unsigned long)options);
        options |= AVAudioSessionCategoryOptionMixWithOthers;
        LogToFile(@"    [AFTER] options = 0x%lx", (unsigned long)options);
    } else {
        LogToFile(@"    [DECISION] Other audio is NOT playing - no modification needed");
    }
    
    LogToFile(@"    [BEFORE %orig] Calling original setCategory:withOptions:error:");
    BOOL result = %orig(category, options, outError);
    LogToFile(@"    [AFTER %orig] Returned: %@", result ? @"YES (success)" : @"NO (failure)");
    LogToFile(@"<<< [HOOK EXIT] setCategory:withOptions:error: returning %@", result ? @"YES" : @"NO");
    LogToFile(@"");
    return result;
}

// Some apps configure their category once (when nothing else is playing) and
// only call -setActive: later. Catch that case at activation time: if other
// audio is playing and we are about to activate a non-mixing interrupting
// session, re-apply the category with MixWithOthers so we don't cut it off.
- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    LogToFile(@"");
    LogToFile(@">>> [HOOK ENTRY] setActive:error:");
    LogToFile(@"    active = %@", active ? @"YES (activate)" : @"NO (deactivate)");
    LogToFile(@"    isOtherAudioPlaying = %@", self.isOtherAudioPlaying ? @"YES" : @"NO");
    LogToFile(@"    currentCategory = '%@'", self.category);
    LogToFile(@"    categoryOptions = 0x%lx", (unsigned long)self.categoryOptions);
    LogToFile(@"    categoryOptions contains MixWithOthers = %@", (self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) ? @"YES" : @"NO");
    
    if (active && self.isOtherAudioPlaying
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        LogToFile(@"    [DECISION] Need to re-apply category with MixWithOthers:");
        LogToFile(@"             - active=YES, other audio playing, and MixWithOthers NOT in options");
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            LogToFile(@"    [MODIFICATION] Category is SoloAmbient - converting to Ambient");
            cat = AVAudioSessionCategoryAmbient;
        }
        LogToFile(@"    [MODIFICATION] Re-applying category with MixWithOthers option");
        LogToFile(@"    [BEFORE setCategory call] category='%@', mode='%@', options will include MixWithOthers", cat, self.mode);
        [self setCategory:cat
                     mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers
                    error:nil];
        LogToFile(@"    [AFTER setCategory call] Category re-applied successfully");
    } else {
        LogToFile(@"    [DECISION] No re-application needed:");
        if (!active) {
            LogToFile(@"             - active=NO (deactivating)");
        }
        if (!self.isOtherAudioPlaying) {
            LogToFile(@"             - other audio NOT playing");
        }
        if (self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) {
            LogToFile(@"             - MixWithOthers already in options");
        }
    }
    
    LogToFile(@"    [BEFORE %orig] Calling original setActive:error: with active=%@", active ? @"YES" : @"NO");
    BOOL result = %orig;
    LogToFile(@"    [AFTER %orig] Returned: %@", result ? @"YES (success)" : @"NO (failure)");
    LogToFile(@"<<< [HOOK EXIT] setActive:error: returning %@", result ? @"YES" : @"NO");
    LogToFile(@"");
    return result;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    LogToFile(@"");
    LogToFile(@">>> [HOOK ENTRY] setActive:withOptions:error:");
    LogToFile(@"    active = %@", active ? @"YES (activate)" : @"NO (deactivate)");
    LogToFile(@"    options = 0x%lx (setActiveOptions)", (unsigned long)options);
    LogToFile(@"    isOtherAudioPlaying = %@", self.isOtherAudioPlaying ? @"YES" : @"NO");
    LogToFile(@"    currentCategory = '%@'", self.category);
    LogToFile(@"    categoryOptions = 0x%lx", (unsigned long)self.categoryOptions);
    LogToFile(@"    categoryOptions contains MixWithOthers = %@", (self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) ? @"YES" : @"NO");
    
    if (active && self.isOtherAudioPlaying
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        LogToFile(@"    [DECISION] Need to re-apply category with MixWithOthers:");
        LogToFile(@"             - active=YES, other audio playing, and MixWithOthers NOT in options");
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            LogToFile(@"    [MODIFICATION] Category is SoloAmbient - converting to Ambient");
            cat = AVAudioSessionCategoryAmbient;
        }
        LogToFile(@"    [MODIFICATION] Re-applying category with MixWithOthers option");
        LogToFile(@"    [BEFORE setCategory call] category='%@', mode='%@', options will include MixWithOthers", cat, self.mode);
        [self setCategory:cat
                     mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers
                    error:nil];
        LogToFile(@"    [AFTER setCategory call] Category re-applied successfully");
    } else {
        LogToFile(@"    [DECISION] No re-application needed:");
        if (!active) {
            LogToFile(@"             - active=NO (deactivating)");
        }
        if (!self.isOtherAudioPlaying) {
            LogToFile(@"             - other audio NOT playing");
        }
        if (self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) {
            LogToFile(@"             - MixWithOthers already in options");
        }
    }
    
    LogToFile(@"    [BEFORE %orig] Calling original setActive:withOptions:error: with active=%@", active ? @"YES" : @"NO");
    BOOL result = %orig;
    LogToFile(@"    [AFTER %orig] Returned: %@", result ? @"YES (success)" : @"NO (failure)");
    LogToFile(@"<<< [HOOK EXIT] setActive:withOptions:error: returning %@", result ? @"YES" : @"NO");
    LogToFile(@"");
    return result;
}

%end

%ctor {
    NSLog(@"[PleaseDontStopTheMusic] %ctor() STARTING initialization");
    
    // Create and initialize the log file immediately with a header
    NSLog(@"[PleaseDontStopTheMusic] Creating log file at: %@", LOG_FILE);
    
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [formatter stringFromDate:now];
    
    // Create directory if needed and write header
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *logDir = [LOG_FILE stringByDeletingLastPathComponent];
    
    NSLog(@"[PleaseDontStopTheMusic] Ensuring log directory exists: %@", logDir);
    NSError *dirError = nil;
    [fileManager createDirectoryAtPath:logDir 
            withIntermediateDirectories:YES 
                             attributes:nil 
                                  error:&dirError];
    
    if (dirError) {
        NSLog(@"[PleaseDontStopTheMusic] ERROR creating directory: %@", dirError);
    } else {
        NSLog(@"[PleaseDontStopTheMusic] Log directory ready");
    }
    
    // Write header to log file
    FILE *file = fopen([LOG_FILE UTF8String], "w");
    if (file) {
        fprintf(file, "================================================================================\n");
        fprintf(file, "PleaseDontStopTheMusic Tweak - DEBUG LOG\n");
        fprintf(file, "================================================================================\n");
        fprintf(file, "Log started at: %s\n", [timestamp UTF8String]);
        fprintf(file, "================================================================================\n\n");
        fclose(file);
        NSLog(@"[PleaseDontStopTheMusic] Log file created and initialized successfully");
    } else {
        NSLog(@"[PleaseDontStopTheMusic] ERROR: Could not create log file at %@", LOG_FILE);
    }
    
    LogToFile(@"");
    LogToFile(@"========== TWEAK INITIALIZATION START ==========");
    LogToFile(@"PleaseDontStopTheMusic tweak is LOADING");
    LogToFile(@"Tweak Version: 1.0.0");
    LogToFile(@"Target: AVAudioSession hooking");
    LogToFile(@"Tweak initialization complete - hooks are now active");
    LogToFile(@"========== TWEAK INITIALIZATION COMPLETE ==========");
    LogToFile(@"");
    
    NSLog(@"[PleaseDontStopTheMusic] %ctor() COMPLETED - tweak is now active");
}
