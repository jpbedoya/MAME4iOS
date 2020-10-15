/*
 * This file is part of MAME4iOS.
 *
 * Copyright (C) 2013 David Valdeita (Seleuco)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses>.
 *
 * Linking MAME4iOS statically or dynamically with other modules is
 * making a combined work based on MAME4iOS. Thus, the terms and
 * conditions of the GNU General Public License cover the whole
 * combination.
 *
 * In addition, as a special exception, the copyright holders of MAME4iOS
 * give you permission to combine MAME4iOS with free software programs
 * or libraries that are released under the GNU LGPL and with code included
 * in the standard release of MAME under the MAME License (or modified
 * versions of such code, with unchanged license). You may copy and
 * distribute such a system following the terms of the GNU GPL for MAME4iOS
 * and the licenses of the other code concerned, provided that you include
 * the source code of that other code when and as the GNU GPL requires
 * distribution of source code.
 *
 * Note that people who make modified versions of MAME4iOS are not
 * obligated to grant this special exception for their modified versions; it
 * is their choice whether to do so. The GNU General Public License
 * gives permission to release a modified version without this exception;
 * this exception also makes it possible to release a modified version
 * which carries forward this exception.
 *
 * MAME4iOS is dual-licensed: Alternatively, you can license MAME4iOS
 * under a MAME license, as set out in http://mamedev.org/
 */

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#import "Bootstrapper.h"
#import "Globals.h"
#import "BTJoyHelper.h"

#import "myosd.h"
#import "EmulatorController.h"
#import <GameController/GameController.h>
#import "Alert.h"

#include <sys/stat.h>

const char* get_resource_path(const char* file)
{
    static char resource_path[1024];
    
#ifdef JAILBREAK
    sprintf(resource_path, "/Applications/MAME4iOS.app/%s", file);
#else
    const char *userPath = [[[NSBundle mainBundle] resourcePath] cStringUsingEncoding:NSASCIIStringEncoding];
    sprintf(resource_path, "%s/%s", userPath, file);
#endif
    return resource_path;
}

const char* get_documents_path(const char* file)
{
    static char documents_path[1024];
    
#ifdef JAILBREAK
    sprintf(documents_path, "/var/mobile/Media/ROMs/MAME4iOS/%s", file);
#else
#if TARGET_OS_IOS
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
#elif TARGET_OS_TV
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
#endif
	const char *userPath = [[paths objectAtIndex:0] cStringUsingEncoding:NSUTF8StringEncoding];
    sprintf(documents_path, "%s/%s",userPath, file);
#endif
    return documents_path;
}

unsigned long read_mfi_controller(unsigned long res){
    return res;
}

@implementation Bootstrapper

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey,id> *)launchOptions {

    chdir (get_documents_path(""));
    
    // create directories
    for (NSString* dir in @[@"iOS", @"artwork", @"titles", @"cfg", @"nvram", @"ini", @"snap", @"sta", @"hi", @"inp", @"memcard", @"samples", @"roms", @"dats", @"cheat", @"skins"])
    {
        NSString* dirPath = [NSString stringWithUTF8String:get_documents_path(dir.UTF8String)];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:dirPath])
            continue;
        
        mkdir(dirPath.UTF8String, 0755);
        
        // copy pre-canned files.
        for (NSString* file in @[@"cheat0139.zip", @"history0139.zip", @"Category.ini", @"hiscore.dat"])
        {
            NSString* fromPath = [NSString stringWithUTF8String:get_resource_path(file.UTF8String)];
            NSString* toPath = [NSString stringWithUTF8String:get_documents_path(file.UTF8String)];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:fromPath] && ![[NSFileManager defaultManager] fileExistsAtPath:toPath])
            {
                NSError* error = nil;
                if (![[NSFileManager defaultManager] copyItemAtPath: fromPath toPath:toPath error:&error])
                    NSLog(@"Unable to copy file %@! %@", fromPath, [error localizedDescription]);
            }
        }
    }

    // set non-backup items.
    for (NSString* path in @[@"roms", @"artwork", @"titles", @"samples", @"nvram", @"cheat.zip"])
    {
        NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:get_documents_path(path.UTF8String)]];
        [url setResourceValue:@(YES) forKey:NSURLIsExcludedFromBackupKey error:nil];
    }

#if TARGET_OS_IOS
#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation : UIStatusBarAnimationNone];
#endif
#endif

	hrViewController = [[EmulatorController alloc] init];
	
	deviceWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
#if TARGET_OS_TV
    deviceWindow.backgroundColor = [UIColor colorWithWhite:0.111 alpha:1.0];
    deviceWindow.tintColor = [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0];
#endif
    [deviceWindow setRootViewController:hrViewController];
    
    [hrViewController startEmulation];
	[deviceWindow makeKeyAndVisible];
        
    [UIApplication sharedApplication].idleTimerDisabled = YES;
	 
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    externalWindow = [[UIWindow alloc] initWithFrame:CGRectZero];
    externalWindow.hidden = YES;
    
	if(g_pref_nativeTVOUT)
	{
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(prepareScreen) name:UIScreenDidConnectNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(prepareScreen) name:UIScreenDidDisconnectNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateScreen)  name:UIScreenModeDidChangeNotification object:nil];
	}
    
    [self prepareScreen];
#endif
    
    NSError *audioSessionError = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:&audioSessionError];
    if (audioSessionError != nil) {
        NSLog(@"Could not set audio session category: %@",audioSessionError.localizedDescription);
    }

    return TRUE;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options
{
    NSLog(@"OPEN URL: %@ %@", url, options);
    
    // handle our own scheme mame4ios://name
    if ([url.scheme isEqualToString:@"mame4ios"] && [url.host length] != 0 && [url.path length] == 0 && [url.query length] == 0) {
        NSDictionary* game = @{@"name":url.host};
        [hrViewController performSelectorOnMainThread:@selector(playGame:) withObject:game waitUntilDone:NO];
        return TRUE;
    }

    // copy a ZIP file to document root, and then let moveROMS take care of it....
    // only handle .zip files
    if (!url.fileURL || ![url.pathExtension.lowercaseString isEqualToString:@"zip"])
        return FALSE;
    
    // dont share with myself
    if ([[url URLByDeletingLastPathComponent].path isEqualToString:[NSString stringWithUTF8String:get_documents_path("roms")]])
        return FALSE;
    
    NSURL* destURL = [[NSURL fileURLWithPath:[NSString stringWithUTF8String:get_documents_path("")]]
                      URLByAppendingPathComponent:url.lastPathComponent];

    BOOL open_in_place = [options[UIApplicationOpenURLOptionsOpenInPlaceKey] boolValue];
    
    if (open_in_place)
    {
        if (![url startAccessingSecurityScopedResource])
            return FALSE;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError* error = nil;
            NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&error byAccessor:^(NSURL * newURL) {
                NSError* error = nil;
                [NSFileManager.defaultManager copyItemAtURL:newURL toURL:destURL error:&error];
                
                if (error != nil)
                    NSLog(@"copyItemAtURL ERROR: (%@)", error);
                
                [url stopAccessingSecurityScopedResource];
                [self->hrViewController performSelectorOnMainThread:@selector(moveROMS) withObject:nil waitUntilDone:NO];
            }];
            if (error != nil)
                NSLog(@"coordinateReadingItemAtURL ERROR: (%@)", error);
        });
    }
    else {
        NSError* error = nil;
        [NSFileManager.defaultManager copyItemAtURL:url toURL:destURL error:&error];
        
        if (error != nil)
            NSLog(@"copyItemAtURL ERROR: (%@)", error);
        
        if ([[[url URLByDeletingLastPathComponent] lastPathComponent] hasSuffix:@"Inbox"])
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        
        [self->hrViewController performSelectorOnMainThread:@selector(moveROMS) withObject:nil waitUntilDone:NO];
    }
    
    return TRUE;
}

- (BOOL)performActivity:(NSString*)activityType userInfo:(NSDictionary*)info {
    
    if (![activityType hasPrefix:[[NSBundle mainBundle] bundleIdentifier]])
        return FALSE;
    
    NSString* cmd = [[activityType componentsSeparatedByString:@"."] lastObject];
    
    if ([cmd isEqualToString:@"play"])
    {
        [hrViewController performSelectorOnMainThread:@selector(playGame:) withObject:info waitUntilDone:NO];
        return TRUE;
    }
        
    return FALSE;
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> * _Nullable))restorationHandler {
    NSLog(@"continueUserActivity: %@ %@", userActivity.activityType, userActivity.userInfo);
    return [self performActivity:userActivity.activityType userInfo:userActivity.userInfo];
}

#if TARGET_OS_IOS
- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    NSLog(@"performActionForShortcutItem: %@ %@", shortcutItem.type, shortcutItem.userInfo);
    completionHandler([self performActivity:shortcutItem.type userInfo:shortcutItem.userInfo]);
}
#endif

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [hrViewController runPause];
}

- (void)applicationWillResignActive:(UIApplication *)application {
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // need to cleanly exit MAME thread
    // MAME static destructors are getting called onexit in Catalyst, sigh C++
    [hrViewController stopEmulation];
}

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
// called when a screen is attached *or* detached
- (void)prepareScreen
{
    // dont show alert asking for screen mode more than once!
    static UIAlertController *g_alert;
    if (g_alert != nil) {
        [g_alert dismissWithCancel];
        return;
    }

    if ([[UIScreen screens] count] > 1 && g_pref_nativeTVOUT) {
        
        // Internal display is 0, external is 1.
        UIScreen* externalScreen = [[UIScreen screens] objectAtIndex:1];
        NSArray* screenModes = [externalScreen availableModes];
        
        if (screenModes.count <= 1) {
            // only one mode, just use it no quesrtions asked
            [self setupScreen:externalScreen];
        }
        else {
			// Allow user to choose from available screen-modes (pixel-sizes).
            g_alert = [UIAlertController alertControllerWithTitle:@"External Display Detected!" message:@"Choose a size for the external display." preferredStyle:UIAlertControllerStyleAlert];
			for (UIScreenMode *mode in screenModes) {
                [g_alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%.0f x %.0f pixels", mode.size.width, mode.size.height] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
                    g_alert = nil;
                    [externalScreen setCurrentMode:mode];
                    [self setupScreen:externalScreen];
                    if (!myosd_inGame)
                        [self->hrViewController performSelectorOnMainThread:@selector(playGame:) withObject:nil waitUntilDone:NO];
                }]];
                if (mode == externalScreen.preferredMode)
                    [g_alert setPreferredAction:g_alert.actions.lastObject];
			}
            [g_alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                g_alert = nil;
                [self setupScreen:nil];
                if (!myosd_inGame)
                    [self->hrViewController performSelectorOnMainThread:@selector(playGame:) withObject:nil waitUntilDone:NO];
            }]];
             
            [hrViewController.topViewController presentViewController:g_alert animated:YES completion:nil];
		}
    }
    else {
        [self setupScreen:nil];
    }
}

// called to use an external screen (or nil for none)
- (void)setupScreen:(UIScreen*)screen
{
    if (screen != nil)
    {
        [screen setOverscanCompensation:UIScreenOverscanCompensationNone];
        [externalWindow setScreen:screen];
                            
        for (UIView *view in externalWindow.subviews)
            [view removeFromSuperview];
                            
        UIView *view = [[UIView alloc] initWithFrame:screen.bounds];
        view.backgroundColor = [UIColor blackColor];
        [externalWindow addSubview:view];
#ifdef DEBUG
        view.backgroundColor = [UIColor systemOrangeColor];
#endif
        [hrViewController setExternalView:view];
        externalWindow.hidden = NO;
    }
    else
    {
        [hrViewController setExternalView:nil];
        externalWindow.hidden = YES;
    }
    [hrViewController performSelectorOnMainThread:@selector(changeUI) withObject:nil waitUntilDone:NO];
}

// called when a mode change happens on a external display
- (void)updateScreen
{
    if (externalWindow.hidden == NO && externalWindow.screen != nil) {
        // update window and view frame to new screen mode/size
        externalWindow.frame = externalWindow.screen.bounds;
        externalWindow.subviews.firstObject.frame = externalWindow.bounds;
        [hrViewController performSelectorOnMainThread:@selector(changeUI) withObject:nil waitUntilDone:NO];
    }
}
#endif

@end

int main(int argc, char **argv){
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"Bootstrapper");
    }
}
