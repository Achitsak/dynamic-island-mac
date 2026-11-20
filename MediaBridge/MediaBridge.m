// MediaBridge — a tiny helper that streams "Now Playing" info as JSON lines.
//
// Since macOS 15.4 the private MediaRemote framework only answers processes
// signed by Apple. This library is loaded into /usr/bin/perl (an Apple
// platform binary) via DynaLoader, so MediaRemote talks to it normally.
//
//   stdout: one JSON object per line, emitted whenever playback changes
//   stdin : commands, one per line — play | pause | toggle | next | prev | seek <seconds>
//
// The process exits as soon as stdin closes (i.e. the app quit or crashed).

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*MRGetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);
typedef NSString *(*MRClientStringFn)(id);

static MRGetInfoFn MRGetInfo;
static MRGetIsPlayingFn MRGetIsPlaying;
static MRGetClientFn MRGetClient;
static MRGetPIDFn MRGetPID;
static MRRegisterFn MRRegister;
static MRSendCommandFn MRSendCommand;
static MRSetElapsedFn MRSetElapsed;
static MRClientStringFn MRClientBundleID;
static MRClientStringFn MRClientParentBundleID;

static NSUInteger gLastArtworkHash = 0;
static BOOL gHadArtwork = NO;
static NSString *gLastLine = nil;
static uint64_t gGeneration = 0;

enum { kCmdPlay = 0, kCmdPause = 1, kCmdToggle = 2, kCmdNext = 4, kCmdPrevious = 5 };

static NSString *constantString(void *handle, const char *symbol, NSString *fallback) {
    CFStringRef *ptr = (CFStringRef *)dlsym(handle, symbol);
    return (ptr && *ptr) ? (__bridge NSString *)*ptr : fallback;
}

static void writeLine(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id valueFor(NSDictionary *info, NSString *suffix) {
    return info[[@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:suffix]];
}

static void emitSnapshot(NSDictionary *info, BOOL isPlaying, NSString *bundleID, int pid) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"type"] = @"nowPlaying";
    out[@"playing"] = @(isPlaying);
    out[@"pid"] = @(pid);
    if (bundleID.length) out[@"bundle"] = bundleID;

    for (NSString *key in @[ @"Title", @"Artist", @"Album" ]) {
        id v = valueFor(info, key);
        if ([v isKindOfClass:NSString.class]) out[key.lowercaseString] = v;
    }
    NSNumber *duration = valueFor(info, @"Duration");
    NSNumber *elapsed = valueFor(info, @"ElapsedTime");
    NSNumber *rate = valueFor(info, @"PlaybackRate");
    NSDate *timestamp = valueFor(info, @"Timestamp");
    if ([duration isKindOfClass:NSNumber.class]) out[@"duration"] = duration;
    if ([elapsed isKindOfClass:NSNumber.class]) out[@"elapsed"] = elapsed;
    if ([rate isKindOfClass:NSNumber.class]) out[@"rate"] = rate;
    if ([timestamp isKindOfClass:NSDate.class]) out[@"timestamp"] = @(timestamp.timeIntervalSince1970);

    // Artwork is large, so only send it when it actually changes.
    NSData *artwork = valueFor(info, @"ArtworkData");
    if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
        NSUInteger hash = artwork.length;
        const uint8_t *bytes = artwork.bytes;
        for (NSUInteger i = 0; i < artwork.length; i += MAX(1, artwork.length / 512)) hash = hash * 31 + bytes[i];
        if (!gHadArtwork || hash != gLastArtworkHash) {
            out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
            gLastArtworkHash = hash;
            gHadArtwork = YES;
        }
        out[@"artworkId"] = @(hash);
    } else if (gHadArtwork) {
        out[@"artwork"] = @"";
        gHadArtwork = NO;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
    NSString *line = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!line || [line isEqualToString:gLastLine]) return;
    gLastLine = line;
    writeLine(out);
}

static void refresh(void) {
    if (!MRGetInfo) return;
    dispatch_queue_t q = dispatch_get_main_queue();
    __block NSDictionary *info = nil;
    __block Boolean playing = false;
    __block NSString *bundleID = nil;
    __block int pid = 0;
    dispatch_group_t group = dispatch_group_create();

    dispatch_group_enter(group);
    MRGetInfo(q, ^(NSDictionary *d) { info = d; dispatch_group_leave(group); });
    if (MRGetIsPlaying) {
        dispatch_group_enter(group);
        MRGetIsPlaying(q, ^(Boolean p) { playing = p; dispatch_group_leave(group); });
    }
    if (MRGetPID) {
        dispatch_group_enter(group);
        MRGetPID(q, ^(int p) { pid = p; dispatch_group_leave(group); });
    }
    if (MRGetClient && MRClientBundleID) {
        dispatch_group_enter(group);
        MRGetClient(q, ^(id client) {
            if (client) {
                NSString *parent = MRClientParentBundleID ? MRClientParentBundleID(client) : nil;
                bundleID = parent.length ? parent : MRClientBundleID(client);
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_notify(group, q, ^{
        if (!MRGetIsPlaying) {
            NSNumber *rate = valueFor(info ?: @{}, @"PlaybackRate");
            playing = rate.doubleValue > 0;
        }
        emitSnapshot(info ?: @{}, playing, bundleID, pid);
    });
}

// Notifications arrive in bursts; coalesce them into one refresh.
static void scheduleRefresh(double delay) {
    uint64_t generation = ++gGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == gGeneration) refresh();
    });
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *cmd = parts.firstObject;
    if ([cmd isEqualToString:@"seek"] && parts.count > 1) {
        if (MRSetElapsed) MRSetElapsed(parts[1].doubleValue);
    } else if (MRSendCommand) {
        NSDictionary *map = @{ @"play" : @(kCmdPlay), @"pause" : @(kCmdPause), @"toggle" : @(kCmdToggle),
                               @"next" : @(kCmdNext), @"prev" : @(kCmdPrevious) };
        NSNumber *code = map[cmd];
        if (code) MRSendCommand(code.intValue, nil);
    }
    if ([cmd isEqualToString:@"refresh"]) gLastLine = nil;
    scheduleRefresh(0.15);
}

static void readCommands(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char buffer[512];
        while (fgets(buffer, sizeof buffer, stdin)) {
            NSString *line = [[NSString stringWithUTF8String:buffer]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!line.length) continue;
            dispatch_async(dispatch_get_main_queue(), ^{ handleCommand(line); });
        }
        exit(0);  // stdin closed: the host app is gone.
    });
}

// Entry point called from perl. Never returns.
void di_stream(void *unused1, void *unused2) {
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!mr) {
            writeLine(@{ @"type" : @"error", @"message" : @"MediaRemote unavailable" });
            exit(1);
        }
        MRGetInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        MRGetIsPlaying = (MRGetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        MRGetClient = (MRGetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        MRGetPID = (MRGetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
        MRRegister = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
        MRSendCommand = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
        MRSetElapsed = (MRSetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
        MRClientBundleID = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
        MRClientParentBundleID = (MRClientStringFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");

        if (MRRegister) MRRegister(dispatch_get_main_queue());
        NSArray *names = @[
            constantString(mr, "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            constantString(mr, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            constantString(mr, "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
        ];
        for (NSString *name in names) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
                scheduleRefresh(0.05);
            }];
        }

        writeLine(@{ @"type" : @"ready" });
        readCommands();
        refresh();
        // Safety net for players that do not post every change. Notifications do the
        // real work, so this stays slow and lets the system coalesce the wake-up.
        NSTimer *safetyNet = [NSTimer scheduledTimerWithTimeInterval:15 repeats:YES block:^(NSTimer *t) { refresh(); }];
        safetyNet.tolerance = 5;
        while (true) CFRunLoopRun();
    }
}
