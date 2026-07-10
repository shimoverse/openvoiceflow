#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <AVFoundation/AVFoundation.h>

static BOOL isSmokeTest(void) {
    const char *value = getenv("OVF_SMOKE_TEST");
    return value != NULL && strcmp(value, "1") == 0;
}

static BOOL requestMicrophoneAccess(void) {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status == AVAuthorizationStatusAuthorized) {
        return YES;
    }
    if (status != AVAuthorizationStatusNotDetermined) {
        return NO;
    }

    __block BOOL granted = NO;
    dispatch_semaphore_t completion = dispatch_semaphore_create(0);
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                             completionHandler:^(BOOL allowed) {
                                 granted = allowed;
                                 dispatch_semaphore_signal(completion);
                             }];

    while (dispatch_semaphore_wait(completion, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC)) != 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return granted;
}

static void showMicrophoneHelp(void) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Microphone access is off";
    alert.informativeText = @"OpenVoiceFlow cannot record until it is enabled in Privacy & Security. "
                             "Open the Microphone settings now, enable OpenVoiceFlow, then relaunch the app.";
    [alert addButtonWithTitle:@"Open Microphone Settings"];
    [alert addButtonWithTitle:@"Continue"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSURL *settingsURL = [NSURL URLWithString:
            @"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"];
        [[NSWorkspace sharedWorkspace] openURL:settingsURL];
    }
}

static void requestAccessibilityAccess(void) {
    if (AXIsProcessTrusted()) {
        return;
    }

    const void *keys[] = {kAXTrustedCheckOptionPrompt};
    const void *values[] = {kCFBooleanTrue};
    CFDictionaryRef options = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        1,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    AXIsProcessTrustedWithOptions(options);
    CFRelease(options);
}

static void showBootstrapFailure(int status) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"OpenVoiceFlow could not finish starting";
    alert.informativeText = [NSString stringWithFormat:
        @"The background service exited with status %d. Open the launcher log for details.",
        status];
    [alert addButtonWithTitle:@"Open Launcher Log"];
    [alert addButtonWithTitle:@"Close"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *logPath = [@"~/OpenVoiceFlow/launcher.log" stringByExpandingTildeInPath];
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:logPath]];
    }
}

static int runBootstrap(int argc, const char *argv[]) {
    NSString *scriptPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"launcher.sh"];
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:scriptPath];
    for (int index = 1; index < argc; index++) {
        [arguments addObject:[NSString stringWithUTF8String:argv[index]]];
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = arguments;

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"OpenVoiceFlow could not start";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
        return 1;
    }

    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        showBootstrapFailure(task.terminationStatus);
    }
    return task.terminationStatus;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        if (!isSmokeTest()) {
            [NSApp activateIgnoringOtherApps:YES];
            if (!requestMicrophoneAccess()) {
                showMicrophoneHelp();
            }
            requestAccessibilityAccess();
        }

        return runBootstrap(argc, argv);
    }
}
