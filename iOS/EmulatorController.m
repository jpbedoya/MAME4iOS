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

#include "myosd.h"
#import "EmulatorController.h"
#import <GameController/GameController.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

#if TARGET_OS_IOS
#import <Intents/Intents.h>
#import "OptionsController.h"
#import "AnalogStick.h"
#import "AnalogStick.h"
#import "LayoutView.h"
#import "NetplayGameKit.h"
#import "FileItemProvider.h"
#import "InfoHUD.h"
#import "PopupSegmentedControl.h"
#endif

#import "ChooseGameController.h"

#if TARGET_OS_TV
#import "TVOptionsController.h"
#endif

#import "iCadeView.h"
#import <pthread.h>
#import "UIView+Toast.h"
#import "Bootstrapper.h"
#import "Options.h"
#import "WebServer.h"
#import "Alert.h"
#import "ZipFile.h"
#import "SystemImage.h"
#import "SteamController.h"
#import "SkinManager.h"

// declare these selectors, so we can use them, and ARC wont complain
#ifndef __IPHONE_14_0
@interface NSObject()
-(GCControllerButtonInput*)buttonHome;
@end
#endif

#define DebugLog 0
#if DebugLog == 0
#define NSLog(...) (void)0
#endif

#define UPDATE_FPS_EVERY    60
#define OPAQUE_FPS          FALSE

// mfi Controllers
NSMutableArray *controllers;

// Turbo functionality
int cyclesAfterButtonPressed[NUM_JOY][NUM_BUTTONS];
int turboBtnEnabled[NUM_BUTTONS];

// On-screen touch gamepad button state
unsigned long buttonState;      // on-screen button state, MYOSD_*
int buttonMask[NUM_BUTTONS];    // map a button index to a button MYOSD_* mask

// Touch Directional Input tracking
int touchDirectionalCyclesAfterMoved = 0;

int g_isMetalSupported = 0;

int g_emulation_paused = 0;
int g_emulation_initiated=0;

int g_joy_used = 0;
int g_iCade_used = 0;

int g_enable_debug_view = 0;
int g_controller_opacity = 50;

int g_device_is_landscape = 0;
int g_device_is_fullscreen = 0;

NSString* g_pref_screen_shader;
NSString* g_pref_line_shader;
NSString* g_pref_filter;
NSString* g_pref_skin;
NSString* g_pref_colorspace;

int g_pref_metal = 0;
int g_pref_integer_scale_only = 0;
int g_pref_showFPS = 0;

enum {
    HudSizeZero = 0,        // HUD is not visible at all.
    HudSizeNormal = 1,      // HUD is 'normal' size, just a toolbar and FPS.
    HudSizeTiny = 2,        // HUD is single button, press to expand.
    HudSizeLarge = 3,       // HUD is expanded to include in-game menu.
    HudSizeEditor = 4,      // HUD is expanded to include Shader editing sliders.
};
int g_pref_showHUD = 0;
int g_pref_saveHUD = 0;     // previous value of g_pref_showHUD

int g_pref_keep_aspect_ratio = 0;

int g_pref_animated_DPad = 0;
int g_pref_full_screen_land = 1;
int g_pref_full_screen_port = 1;
int g_pref_full_screen_joy = 1;

int g_pref_BplusX=0;
int g_pref_full_num_buttons=4;

int g_pref_input_touch_type = TOUCH_INPUT_DSTICK;
int g_pref_analog_DZ_value = 2;
int g_pref_ext_control_type = 1;

int g_pref_nintendoBAYX = 0;

int g_pref_nativeTVOUT = 1;
int g_pref_overscanTVOUT = 1;

int g_pref_lightgun_enabled = 1;
int g_pref_lightgun_bottom_reload = 0;

int g_pref_touch_analog_enabled = 1;
int g_pref_touch_analog_hide_dpad = 1;
int g_pref_touch_analog_hide_buttons = 0;
float g_pref_touch_analog_sensitivity = 500.0;

int g_pref_touch_directional_enabled = 0;

int g_skin_data = 1;

float g_buttons_size = 1.0f;
float g_stick_size = 1.0f;

int global_low_latency_sound = 0;
static int main_thread_priority = 46;
int video_thread_priority = 46;
static int main_thread_priority_type = 1;
int video_thread_priority_type = 1;

int prev_myosd_light_gun = 0;
int prev_myosd_mouse = 0;
        
static pthread_t main_tid;

static int ways_auto = 0;
static int change_layout=0;

#define kHUDPositionLandKey  @"hud_rect_land"
#define kHUDScaleLandKey     @"hud_scale_land"
#define kHUDPositionPortKey  @"hud_rect_port"
#define kHUDScalePortKey     @"hud_scale_port"
#define kSelectedGameInfoKey @"selected_game_info"
static NSDictionary* g_mame_game_info;
static BOOL g_mame_reset = FALSE;           // do a full reset (delete cfg files) before running MAME
static char g_mame_game[MAX_GAME_NAME];     // game MAME should run (or empty is menu)
static char g_mame_game_error[MAX_GAME_NAME];
static BOOL g_no_roms_found = FALSE;

static NSInteger g_settings_roms_count;
static NSInteger g_settings_file_count;

static BOOL g_bluetooth_enabled;

static EmulatorController *sharedInstance = nil;

static const int buttonPressReleaseCycles = 2;
static const int buttonNextPressCycles = 32;

static BOOL g_video_reset = FALSE;

// called by the OSD layer when redner target changes size
// **NOTE** this is called on the MAME background thread, dont do anything stupid.
void iphone_Reset_Views(void)
{
    NSLog(@"iphone_Reset_Views: %dx%d [%dx%d] %f",
          myosd_vis_video_width, myosd_vis_video_height,
          myosd_video_width, myosd_video_height,
          (double)myosd_vis_video_width / myosd_vis_video_height);
    
    if (sharedInstance == nil)
        return;
    
    if (!myosd_inGame)
        [sharedInstance performSelectorOnMainThread:@selector(moveROMS) withObject:nil waitUntilDone:NO];

    // set this flag to cause the next call to myosd_handle_turbo (aka myosd_poll_input) to reset the UI
    // ...we need this delay so MAME/OSD can setup some variables we need to configure the UI
    // ...like myosd_mouse, myosd_num_ways, myosd_num_players, etc....
    g_video_reset = TRUE;
    //[sharedInstance performSelectorOnMainThread:@selector(changeUI) withObject:nil waitUntilDone:NO];
}
// called by the OSD layer to update the current software frame
// **NOTE** this is called on the MAME background thread, dont do anything stupid.
void iphone_UpdateScreen()
{
    if (sharedInstance == nil || g_emulation_paused || sharedInstance->screenView == nil)
        return;
    
    UIView<ScreenView>* screenView = sharedInstance->screenView;
    [screenView performSelectorOnMainThread:@selector(setNeedsDisplay) withObject:nil waitUntilDone:NO];

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wundeclared-selector"
    if (g_pref_showFPS && (screenView.frameCount % UPDATE_FPS_EVERY) == 0)
        [sharedInstance performSelectorOnMainThread:@selector(updateFrameRate) withObject:nil waitUntilDone:NO];
    #pragma clang diagnostic pop
}
// called by the OSD layer to render the current frame
// return 1 if you did the render, 0 if you want a software render.
// **NOTE** this is called on the MAME background thread, dont do anything stupid.
// ...not doing something stupid includes not leaking autoreleased objects! use a autorelease pool if you need to!
int iphone_DrawScreen(myosd_render_primitive* prim_list) {

    if (sharedInstance == nil || g_emulation_paused || sharedInstance->screenView == nil)
        return 0;

    @autoreleasepool {
        UIView<ScreenView>* screenView = sharedInstance->screenView;

#ifdef DEBUG
        [CGScreenView drawScreenDebug:prim_list];
#endif
        BOOL result = [screenView drawScreen:prim_list];
        
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wundeclared-selector"
        if (g_pref_showFPS && result && (screenView.frameCount % UPDATE_FPS_EVERY) == 0)
            [sharedInstance performSelectorOnMainThread:@selector(updateFrameRate) withObject:nil waitUntilDone:NO];
        #pragma clang diagnostic pop

        return result;
    }
}

// run MAME (or pass NULL for main menu)
int run_mame(char* game)
{
    char* argv[] = {"mame4ios", "-pause_brightness", "1.0", game};
    
    int argc = sizeof(argv) / sizeof(argv[0]);
    
    if (game == NULL || *game == 0)
        argc--;

    return iOS_main(argc,argv);
}

void* app_Thread_Start(void* args)
{
    g_emulation_initiated = 1;
    
    while (g_emulation_initiated) {
        prev_myosd_mouse = myosd_mouse = 0;
        prev_myosd_light_gun = myosd_light_gun = 0;
        
        // reset MAME by deleteing CFG file cfg/default.cfg
        if (g_mame_reset) @autoreleasepool {
            NSString *cfg_path = [NSString stringWithUTF8String:get_documents_path("cfg")];
            
            // NOTE we need to delete the default.cfg file here because MAME saves cfg files on exit.
            [[NSFileManager defaultManager] removeItemAtPath: [cfg_path stringByAppendingPathComponent:@"default.cfg"] error:nil];

#if 0 // should we use this big of hammer? the user can always delete settings on a game by game basis via context menu in ChooseGameController.
            // delete *all* the cfg files, not just default.cfg so we reset settings for all games.
            [[NSFileManager defaultManager] removeItemAtPath:cfg_path error:nil];
            [[NSFileManager defaultManager] createDirectoryAtPath:cfg_path withIntermediateDirectories:NO attributes:nil error:nil];
#endif
            g_mame_reset = FALSE;
        }
        
        // set this myosd global so the netplay code knows what the current game is.
        if (g_mame_game[0] != 0 && g_mame_game[0] != ' ')
            strcpy(myosd_selected_game, g_mame_game);
        
        if (run_mame(g_mame_game) != 0 && g_mame_game[0]) {
            strncpy(g_mame_game_error, g_mame_game, sizeof(g_mame_game_error));
            g_mame_game[0] = 0;
        }
    }
    NSLog(@"thread exit");
    g_emulation_initiated = -1;
    return NULL;
}

// load Category.ini (a copy of a similar function from uimenu.c)
NSDictionary* load_category_ini()
{
    FILE* file = fopen(get_documents_path("Category.ini"), "r");
    assert(file != NULL);
    
    if (file == NULL)
        return nil;

    NSMutableDictionary* category_dict = [[NSMutableDictionary alloc] init];
    char line[256];
    NSString* curcat = @"";

    while (fgets(line, sizeof(line), file) != NULL)
    {
        if (line[strlen(line) - 1] == '\n') line[strlen(line) - 1] = '\0';
        if (line[strlen(line) - 1] == '\r') line[strlen(line) - 1] = '\0';
        
        if (line[0] == '\0')
            continue;
        
        if (line[0] == '[')
        {
            line[strlen(line) - 1] = '\0';
            curcat = [NSString stringWithUTF8String:line+1];
            continue;
        }
        
        [category_dict setObject:curcat forKey:[NSString stringWithUTF8String:line]];
    }
    fclose(file);
    return category_dict;
}

// find the category for a game/rom using Category.ini
NSString* find_category(NSString* name)
{
    static NSDictionary* g_category_dict = nil;
    g_category_dict = g_category_dict ?: load_category_ini();
    return g_category_dict[name] ?: @"Unkown";
}

// called from deep inside MAME select_game menu, to give us the valid list of games/drivers
void myosd_set_game_info(myosd_game_info* game_info[], int game_count)
{
    @autoreleasepool {
        NSMutableArray* games = [[NSMutableArray alloc] init];
        
        for (int i=0; i<game_count; i++)
        {
            if (game_info[i] == NULL)
                continue;
            [games addObject:@{
                kGameInfoDriver:      [[NSString stringWithUTF8String:game_info[i]->source_file ?: ""].lastPathComponent stringByDeletingPathExtension],
                kGameInfoParent:      [NSString stringWithUTF8String:game_info[i]->parent ?: ""],
                kGameInfoName:        [NSString stringWithUTF8String:game_info[i]->name],
                kGameInfoDescription: [NSString stringWithUTF8String:game_info[i]->description],
                kGameInfoYear:        [NSString stringWithUTF8String:game_info[i]->year],
                kGameInfoManufacturer:[NSString stringWithUTF8String:game_info[i]->manufacturer],
                kGameInfoCategory:    find_category([NSString stringWithUTF8String:game_info[i]->name]),
            }];
        }
        
        [sharedInstance performSelectorOnMainThread:@selector(chooseGame:) withObject:games waitUntilDone:FALSE];
    }
}

@implementation UINavigationController(KeyboardDismiss)

- (BOOL)disablesAutomaticKeyboardDismissal
{
    return NO;
}

@end

@interface EmulatorController() {
    CSToastStyle *toastStyle;
    CGPoint mouseTouchStartLocation;
    CGPoint mouseInitialLocation;
    CGPoint touchDirectionalMoveStartLocation;
    CGPoint touchDirectionalMoveInitialLocation;
    CGSize  layoutSize;
    SkinManager* skinManager;
}
@end

@implementation EmulatorController

@synthesize externalView;
@synthesize stick_radio;

#if TARGET_OS_IOS
- (NSString*)getButtonName:(int)i {
    static NSString* button_name[NUM_BUTTONS] = {@"A",@"B",@"Y",@"X",@"L1",@"R1",@"A+Y",@"A+X",@"B+Y",@"B+X",@"A+B",@"SELECT",@"START",@"EXIT",@"OPTION",@"STICK"};
    _Static_assert(NUM_BUTTONS == 16, "enum size change");
    assert(i < NUM_BUTTONS);
    return button_name[i];
}
- (CGRect)getButtonRect:(int)i {
    assert(i < NUM_BUTTONS);
    return rButton[i];
}
// called by the LayoutView editor (and internaly)
- (void)setButtonRect:(int)i rect:(CGRect)rect {
    assert(i < NUM_BUTTONS);
    rInput[i] = rButton[i] = rect;
    
    _Static_assert(BTN_A==0 && BTN_R1== 5, "enum order change");
    if (i <= BTN_R1)
        rInput[i] = scale_rect(rButton[i], 0.80);
    
    if (buttonViews[i])
        buttonViews[i].frame = rect;

    // fix the aspect ratio of the input rect, if the image is not square.
    if (buttonViews[i].image != nil && buttonViews[i].image.size.width != buttonViews[i].image.size.height) {
        CGFloat h = floor(rect.size.width * buttonViews[i].image.size.height / buttonViews[i].image.size.width);
        rInput[i].origin.y += (rect.size.height-h)/2;
        rInput[i].size.height = h;
    }
    
    // move the analog stick (and maybe the stick background image)
    if (i == BTN_STICK && analogStickView != nil) {
        analogStickView.frame = rect;
        UIView* back = imageBack.subviews.firstObject;
        rect = scale_rect(rect, g_device_is_landscape ? 1.0 : 1.2);
        back.frame = [inputView convertRect:rect toView:imageBack];
    }
}

#endif

+ (NSArray*)romList {
    // NOTE we cant just use g_category_dict, because that is accessed on the MAME background thread.
    return [load_category_ini() allKeys];
}

- (void)startEmulation {
    if (g_emulation_initiated == 1)
        return;
    [self updateOptions];
    
    sharedInstance = self;
    
    g_mame_game_info = [[NSUserDefaults standardUserDefaults] objectForKey:kSelectedGameInfoKey];
    NSString* name = g_mame_game_info[kGameInfoName] ?: @"";
    if ([name isEqualToString:kGameInfoNameMameMenu])
        name = @" ";
    strncpy(g_mame_game, [name cStringUsingEncoding:NSUTF8StringEncoding], sizeof(g_mame_game));
    g_mame_game_error[0] = 0;
    
    // delete the UserDefaults, this way if we crash we wont try this game next boot
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSelectedGameInfoKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
	     		    				
    pthread_create(&main_tid, NULL, app_Thread_Start, NULL);
		
	struct sched_param param;
 
    printf("main priority %d\n",main_thread_priority);
    param.sched_priority = main_thread_priority;
    int policy;
    if(main_thread_priority_type == 1)
      policy = SCHED_OTHER;
    else if(main_thread_priority_type == 2)
      policy = SCHED_RR;
    else
      policy = SCHED_FIFO;
           
    if(pthread_setschedparam(main_tid, policy, &param) != 0)
        fprintf(stderr, "Error setting pthread priority\n");
    
#if TARGET_OS_IOS
    _impactFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    _selectionFeedback = [[UISelectionFeedbackGenerator alloc] init];
#endif
}

// called durring app exit to cleanly shutdown MAME thread
- (void)stopEmulation {
    if (g_emulation_initiated == 0)
        return;
    
    NSLog(@"stopEmulation: START");
    
    if (g_emulation_paused)
        change_pause(g_emulation_paused = 0);
    
    g_emulation_initiated = 0;
    while (g_emulation_initiated == 0) {
        NSLog(@"stopEmulation: EXIT");
        myosd_exitGame = 1;
        [NSThread sleepForTimeInterval:0.100];
    }
    NSLog(@"stopEmulation: DONE");
    g_emulation_initiated = 0;
}

- (void)startMenu
{
    g_emulation_paused = 1;
    change_pause(1);
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}


enum {LOAD_STATE, SAVE_STATE, ASK_STATE};

void mame_state(int load_save, int slot)
{
    myosd_loadstate = (load_save == LOAD_STATE);
    myosd_savestate = (load_save == SAVE_STATE);
    push_mame_buttons(0, 0, (slot == 1) ? MYOSD_B : MYOSD_X);       // delay, slot #
}

- (void)runState:(int)load_save
{
    if (self.presentedViewController)
        return NSLog(@"runLoadSaveState: BUSY!");
    
    if (load_save == ASK_STATE) {
        [self startMenu];
        [self showAlertWithTitle:nil message:nil buttons:@[@"Save State 1", @"Load State 1", @"Save State 2", @"Load State 2", @"Cancel"] handler:^(NSUInteger button) {
            if (button < 4)
                mame_state((button & 1) ? LOAD_STATE : SAVE_STATE, (button < 2) ? 1 : 2);
            [self endMenu];
        }];
    }
    else {
        NSString* message = [NSString stringWithFormat:@"Select State to %@", (load_save == LOAD_STATE) ? @"Load" : @"Save"];
        NSString* state1 = (controllers.count > 0 && TARGET_OS_IOS) ? @"Ⓧ State 1" : @"State 1";
        NSString* state2 = (controllers.count > 0 && TARGET_OS_IOS) ? @"Ⓨ State 2" : @"State 2";
        
        [self startMenu];
        [self showAlertWithTitle:nil message:message buttons:@[state1, state2, @"Cancel"] handler:^(NSUInteger button) {
            if (button <= 1)
                mame_state(load_save, (button == 0) ? 1 : 2);
            [self endMenu];
        }];
    }
}
- (void)runLoadState
{
    [self runState:LOAD_STATE];
}
- (void)runSaveState
{
    [self runState:SAVE_STATE];
}

- (void)presentPopup:(UIViewController *)viewController from:(UIView*)view animated:(BOOL)flag completion:(void (^)(void))completion {
#if TARGET_OS_IOS // UIPopoverPresentationController does not exist on tvOS.
    UIPopoverPresentationController *popoverController = viewController.popoverPresentationController;
    if ( popoverController != nil ) {
        if (view == nil || view.hidden || CGRectIsEmpty(view.bounds) ) {
            popoverController.sourceView = self.view;
            popoverController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0.0f, 0.0f);
            popoverController.permittedArrowDirections = 0; /*UIPopoverArrowDirectionNone*/
        }
        else if ([view isKindOfClass:[UIImageView class]] && view.contentMode == UIViewContentModeScaleAspectFit) {
            popoverController.sourceView = view;
            popoverController.sourceRect = AVMakeRectWithAspectRatioInsideRect([(UIImageView*)view image].size, view.bounds);
            popoverController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        }
        else {
            popoverController.sourceView = view;
            popoverController.sourceRect = view.bounds;
            popoverController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        }
    }
#endif
    [self presentViewController:viewController animated:flag completion:completion];
}

// player is zero based 0=P1, 1=P2, etc
- (void)startPlayer:(int)player {
    
    // P1 or P2 Start
    if (player < 2 && myosd_num_players <= 2) {
        // add an extra COIN for good luck, some games need two coins to play by default
        push_mame_button(0, MYOSD_SELECT);      // Player 1 COIN
        // insert a COIN, make sure to not exceed the max coin slot for game
        push_mame_button((player < myosd_num_coins ? player : 0), MYOSD_SELECT);  // Player X (or P1) COIN
        // then hit START
        push_mame_button(player, MYOSD_START);  // Player X START
    }
    // P3 or P4 Start
    else {
        // insert a COIN for each player, make sure to not exceed the max coin slot for game
        for (int i=0; i<=player; i++)
             push_mame_button((i < myosd_num_coins ? i : 0), MYOSD_SELECT);  // Player X coin

        // then hit START for each player
        for (int i=player; i>=0; i--)
            push_mame_button(i, MYOSD_START);  // Player X START
    }
}

- (void)runMenu:(int)player from:(UIView*)view
{
    if (self.presentedViewController != nil)
        return;
    
    [self startMenu];

    int enable_menu_exit_option = TRUE; // (myosd_inGame && myosd_in_menu==0) || !myosd_inGame;
    
    NSString* title = nil;
    NSInteger controller_count = controllers.count;
#if TARGET_OS_TV
    if (controller_count > 1 && ((GCController*)controllers.lastObject).extendedGamepad == nil)
        controller_count--;
#endif
    if (controller_count > 1)
        title = [NSString stringWithFormat:@"Player %d", player+1];
    
    UIAlertController* menu = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    CGFloat size = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline].pointSize;

    if(myosd_inGame && myosd_in_menu==0)
    {
        // MENU item to insert a coin and do a start. usefull for fullscreen and AppleTV siri remote, and discoverability on a GameController
        if (player >= 2 && myosd_num_players > 2) {
            // in-game menu for player 3+ just give them a COIN+START option....
            [menu addAction:[UIAlertAction actionWithTitle:@"Coin+Start" style:UIAlertActionStyleDefault image:[UIImage systemImageNamed:@"centsign.circle" withPointSize:size] handler:^(UIAlertAction* action) {
                push_mame_button((player < myosd_num_coins ? player : 0), MYOSD_SELECT);  // Player X (or P1) COIN
                push_mame_button(player, MYOSD_START);  // Player X START
                [self endMenu];
            }]];
        }
        else {
            // in-game menu for player 1-4, give them options to start.
            int num_players = MIN(myosd_num_players, 4);

            for (int player=0; player<num_players; player++) {
                title = [NSString stringWithFormat:@"%d Player Start", player+1];
                NSString* image = @[@"person", @"person.2", @"person.3", @"person.3"][player];
                [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault image:[UIImage systemImageNamed:image withPointSize:size] handler:^(UIAlertAction* action) {
                    [self startPlayer:player];
                    [self endMenu];
                }]];
            }
        }
        [menu addAction:[UIAlertAction actionWithTitle:@"Load/Save State" style:UIAlertActionStyleDefault image:[UIImage systemImageNamed:@"bookmark" withPointSize:size] handler:^(UIAlertAction* action) {
            [self runState:ASK_STATE];
        }]];
        [menu addAction:[UIAlertAction actionWithTitle:@"MAME Menu" style:UIAlertActionStyleDefault image:[UIImage systemImageNamed:@"slider.horizontal.3" withPointSize:size] handler:^(UIAlertAction* action) {
            myosd_configure = 1;
            [self endMenu];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Settings" style:UIAlertActionStyleDefault image:[UIImage systemImageNamed:@"gear" withPointSize:size] handler:^(UIAlertAction* action) {
        [self runSettings];
    }]];

    if(enable_menu_exit_option) {
        [menu addAction:[UIAlertAction actionWithTitle:((myosd_inGame && myosd_in_menu==0) ? @"Exit Game" : @"Exit") style:UIAlertActionStyleDestructive image:[UIImage systemImageNamed:@"arrow.uturn.left.circle" withPointSize:size] handler:^(UIAlertAction* action) {
            [self endMenu];
            [self runExit:NO]; // the user just selected "Exit Game" from a menu, dont ask again
        }]];
    }
    
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction* action) {
        [self endMenu];
    }]];
    
    [self presentPopup:menu from:view animated:YES completion:nil];
}
- (void)runMenu:(int)player
{
    [self runMenu:player from:nil];
}
- (void)runMenu
{
    [self runMenu:0];
}

// show or dismiss our in-game menu (called on joystick MENU button)
- (void)toggleMenu:(int)player
{
    // if menu is up take it down
    if (self.presentedViewController != nil) {
        if ([self.presentedViewController isKindOfClass:[UIAlertController class]]) {
            UIAlertController* alert = (UIAlertController*)self.presentedViewController;
            if (!alert.isBeingDismissed && alert.preferredStyle == UIAlertControllerStyleActionSheet) {
                [alert dismissWithCancel];
            }
        }
        return;
    }
    else {
        [self runMenu:player];
    }
}

- (void)runExit:(BOOL)ask_user from:(UIView*)view
{
    if (self.presentedViewController != nil)
        return;

    if (myosd_in_menu == 0 && ask_user)
    {
        NSString* yes = (controllers.count > 0 && TARGET_OS_IOS) ? @"Ⓐ Yes" : @"Yes";
        NSString* no  = (controllers.count > 0 && TARGET_OS_IOS) ? @"Ⓑ No" : @"No";
        UIAlertControllerStyle style = UIAlertControllerStyleAlert;
        
        if (view != nil && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular && self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular)
            style = UIAlertControllerStyleActionSheet;

        UIAlertController *exitAlertController = [UIAlertController alertControllerWithTitle:@"Are you sure you want to exit?" message:nil preferredStyle:style];

        [self startMenu];
        [exitAlertController addAction:[UIAlertAction actionWithTitle:yes style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
            [self endMenu];
            [self runExit:NO from:view];
        }]];
        [exitAlertController addAction:[UIAlertAction actionWithTitle:no style:UIAlertActionStyleCancel handler:^(UIAlertAction* action) {
            [self endMenu];
        }]];
        exitAlertController.preferredAction = exitAlertController.actions.firstObject;

        [self presentPopup:exitAlertController from:view animated:YES completion:nil];
    }
    else if (myosd_inGame && myosd_in_menu == 0)
    {
        if (g_mame_game[0] != ' ') {
            g_mame_game[0] = 0;
            g_mame_game_info = nil;
        }
        myosd_exitGame = 1;
    }
    else if (myosd_inGame && myosd_in_menu != 0)
    {
        myosd_exitGame = 1;
    }
    else
    {
        g_mame_game[0] = 0;
        g_mame_game_info = nil;
        myosd_exitGame = 1;
    }
}

- (void)runExit:(BOOL)ask
{
    [self runExit:ask from:nil];
}
- (void)runExit
{
    [self runExit:YES];
}

- (void)runPause
{
    // this is called from bootstrapper when app is going into the background, save the current game we are playing so we can restore next time.
    [[NSUserDefaults standardUserDefaults] setObject:g_mame_game_info forKey:kSelectedGameInfoKey];
    
    // also save the position of the HUD
    [self saveHUD];
    
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    if (self.presentedViewController != nil || g_emulation_paused)
        return;
    
    // dont pause the MAME select game menu.
    if (!myosd_inGame)
        return;

    [self startMenu];
    [self showAlertWithTitle:@PRODUCT_NAME message:@"Game is PAUSED" buttons:@[@"Continue"] handler:^(NSUInteger button) {
        [self endMenu];
    }];
}

- (void)runSettings {
    
    g_settings_file_count = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSString stringWithUTF8String:get_documents_path("")] error:nil] count];
    g_settings_roms_count = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSString stringWithUTF8String:get_documents_path("roms")] error:nil] count];

    [self startMenu];
    
#if TARGET_OS_IOS
    OptionsController* optionsController = [[OptionsController alloc] initWithEmuController:self];
#elif TARGET_OS_TV
    TVOptionsController *optionsController = [[TVOptionsController alloc] initWithEmuController:self];
#endif

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:optionsController];
#if TARGET_OS_IOS
    [navController setModalPresentationStyle:UIModalPresentationPageSheet];
#endif
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        navController.modalInPresentation = YES;    // disable iOS 13 swipe to dismiss...
        navController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    [self.topViewController presentViewController:navController animated:YES completion:nil];
}

- (void)endMenu{
    int old_joy_used = g_joy_used;
    g_joy_used = myosd_num_of_joys!=0;
    
    if (old_joy_used != g_joy_used)
        [self changeUI];
    
    g_emulation_paused = 0;
    change_pause(0);
    
    // always enable iCadeView so we can get input from a Hardware keyboard.
    icadeView.active = TRUE; //force renable
    
    [UIApplication sharedApplication].idleTimerDisabled = (myosd_inGame || g_joy_used) ? YES : NO;//so atract mode dont sleep
}

-(void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    NSLog(@"PRESENT VIEWCONTROLLER: %@", viewControllerToPresent);
    
    if ([viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
        if (@available(iOS 13.0, tvOS 13.0, *))
            viewControllerToPresent.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }

#if TARGET_OS_TV
    self.controllerUserInteractionEnabled = YES;
#endif
    [super presentViewController:viewControllerToPresent animated:flag completion:completion];
}
-(void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion {
    NSLog(@"DISMISS VIEWCONTROLLER: %@", [self presentedViewController]);
#if TARGET_OS_TV
    self.controllerUserInteractionEnabled = NO;
#endif
    [super dismissViewControllerAnimated:flag completion:completion];
}


-(void)updateOptions{
    
    //printf("load options\n");
    
    g_isMetalSupported = [MetalScreenView isSupported];
    
    Options *op = [[Options alloc] init];
    
    g_pref_keep_aspect_ratio = [op keepAspectRatio];
    
    g_pref_filter = [Options.arrayFilter optionData:op.filter];
    g_pref_screen_shader = [Options.arrayScreenShader optionData:op.screenShader];
    g_pref_line_shader = [Options.arrayLineShader optionData:op.lineShader];
    g_pref_colorspace = [Options.arrayColorSpace optionData:op.colorSpace];

    g_pref_skin = [Options.arraySkin optionData:op.skin];
    [skinManager setCurrentSkin:g_pref_skin];

    g_pref_integer_scale_only = op.integerScalingOnly;
    g_pref_metal = op.useMetal;
    g_pref_showFPS = [op showFPS];
    g_pref_showHUD = [op showHUD];

    myosd_showinfo =  [op showINFO];
    g_pref_animated_DPad  = [op animatedButtons];
    g_pref_full_screen_land  = [op fullscreenLandscape];
    g_pref_full_screen_port  = [op fullscreenPortrait];
    g_pref_full_screen_joy   = [op fullscreenJoystick];

    myosd_pxasp1 = [op p1aspx];
    
    g_pref_nativeTVOUT = [op tvoutNative];
    g_pref_overscanTVOUT = [op overscanValue];
    
    g_pref_input_touch_type = [op touchtype];
    g_pref_analog_DZ_value = [op analogDeadZoneValue];
    g_pref_ext_control_type = [op controltype];
    
    switch  ([op soundValue]){
        case 0: myosd_sound_value=-1;break;
        case 1: myosd_sound_value=11025;break;
        case 2: myosd_sound_value=22050;break;
        case 3: myosd_sound_value=32000;break;
        case 4: myosd_sound_value=44100;break;
        case 5: myosd_sound_value=48000;break;
        default:myosd_sound_value=-1;}
    
    myosd_throttle = [op throttle];
    myosd_cheat = [op cheats];
    myosd_vsync = [op vsync] == 1 ? 6000 : -1;
       
    myosd_sleep = [op sleep];
    
    g_pref_nintendoBAYX = [op nintendoBAYX];

    g_pref_full_num_buttons = [op numbuttons] - 1;  // -1 == Auto
    
    if([op aplusb] == 1 && (g_pref_full_num_buttons == 2 || (g_pref_full_num_buttons == -1 && myosd_num_buttons == 2)))
    {
        g_pref_BplusX = 1;
        g_pref_full_num_buttons = 3;
    }
    else
    {
        g_pref_BplusX = 0;
    }
        
    //////
    ways_auto = 0;
    if([op sticktype]==0)
    {
        ways_auto = 1;
        myosd_waysStick = myosd_num_ways;
    }
    else if([op sticktype]==1)
    {
        myosd_waysStick = 2;
    }
    else if([op sticktype]==2)
    {
        myosd_waysStick = 4;
    }
    else
    {
        myosd_waysStick = 8;
    }
    
    if([op fsvalue] == 0)
    {
        myosd_frameskip_value = -1;
    }
    else 
    {
        myosd_frameskip_value = [op fsvalue]-1;
    }
    
    myosd_force_pxaspect = [op forcepxa];
    
    myosd_res = [op emures]+1;

    myosd_filter_clones = op.filterClones;
    myosd_filter_not_working = op.filterNotWorking;
    
    global_low_latency_sound = [op lowlsound];
    if(myosd_video_threaded==-1)
    {
        myosd_video_threaded = [op threaded];
        main_thread_priority =  MAX(1,[op mainPriority] * 10);
        video_thread_priority = MAX(1,[op videoPriority] * 10);
        myosd_dbl_buffer = [op dblbuff];
        main_thread_priority_type = [op mainThreadType]+1;
        main_thread_priority_type = [op videoThreadType]+1;
        NSLog(@"thread Type %d %d\n",main_thread_priority_type,main_thread_priority_type);
    }
    
    myosd_autofire = [op autofire];
    myosd_hiscore = [op hiscore];
    
    switch ([op buttonSize]) {
        case 0: g_buttons_size = 0.8; break;
        case 1: g_buttons_size = 0.9; break;
        case 2: g_buttons_size = 1.0; break;
        case 3: g_buttons_size = 1.1; break;
        case 4: g_buttons_size = 1.2; break;
    }
    
    switch ([op stickSize]) {
        case 0: g_stick_size = 0.8; break;
        case 1: g_stick_size = 0.9; break;
        case 2: g_stick_size = 1.0; break;
        case 3: g_stick_size = 1.1; break;
        case 4: g_stick_size = 1.2; break;
    }
    
    myosd_vector_bean2x = [op vbean2x];
    myosd_vector_antialias = [op vantialias];
    myosd_vector_flicker = [op vflicker];

    switch ([op emuspeed]) {
        case 0: myosd_speed = -1; break;
        case 1: myosd_speed = 50; break;
        case 2: myosd_speed = 60; break;
        case 3: myosd_speed = 70; break;
        case 4: myosd_speed = 80; break;
        case 5: myosd_speed = 85; break;
        case 6: myosd_speed = 90; break;
        case 7: myosd_speed = 95; break;
        case 8: myosd_speed = 100; break;
        case 9: myosd_speed = 105; break;
        case 10: myosd_speed = 110; break;
        case 11: myosd_speed = 115; break;
        case 12: myosd_speed = 120; break;
        case 13: myosd_speed = 130; break;
        case 14: myosd_speed = 140; break;
        case 15: myosd_speed = 150; break;
    }
    
    turboBtnEnabled[BTN_X] = [op turboXEnabled];
    turboBtnEnabled[BTN_Y] = [op turboYEnabled];
    turboBtnEnabled[BTN_A] = [op turboAEnabled];
    turboBtnEnabled[BTN_B] = [op turboBEnabled];
    turboBtnEnabled[BTN_L1] = [op turboLEnabled];
    turboBtnEnabled[BTN_R1] = [op turboREnabled];
    
    // ignore some settings in the Metal case
    if (g_pref_metal && [MetalScreenView isSupported]) {
        myosd_sleep = 1;            // sleep to let Metal get work done.
        myosd_video_threaded = 0;   // dont need an extra thread
        myosd_vsync = -1;           // dont force 60Hz, just use the machine value, let MAME frameskip do what it can.
        myosd_frameskip_value = -1; // AUTO frameskip
    }
    
#if TARGET_OS_IOS
    g_pref_lightgun_enabled = [op lightgunEnabled];
    g_pref_lightgun_bottom_reload = [op lightgunBottomScreenReload];
    
    g_pref_touch_analog_enabled = [op touchAnalogEnabled];
    g_pref_touch_analog_hide_dpad = [op touchAnalogHideTouchDirectionalPad];
    g_pref_touch_analog_hide_buttons = [op touchAnalogHideTouchButtons];
    g_pref_touch_analog_sensitivity = [op touchAnalogSensitivity];
    g_controller_opacity = [op touchControlsOpacity];
    
    g_pref_touch_directional_enabled = [op touchDirectionalEnabled];
#else
    g_pref_lightgun_enabled = NO;
    g_pref_touch_analog_enabled = NO;
    g_pref_touch_directional_enabled = NO;
#endif
}

// DONE button on Settings dialog
-(void)done:(id)sender {
    
	Options *op = [[Options alloc] init];
    
    // have the parent of the options/setting dialog dismiss
    // we present settings two ways, from in-game menu (we are parent) and from ChooseGameUI (it is the parent)
    UIViewController* parent = self.topViewController.presentingViewController;
    [(parent ?: self) dismissViewControllerAnimated:YES completion:^{
        
        if(global_low_latency_sound != [op lowlsound])
        {
            if(myosd_sound_value!=-1)
            {
               myosd_closeSound();
               global_low_latency_sound = [op lowlsound];
               myosd_openSound(myosd_sound_value, 1);
            }
        }
        
        // if we are at the root menu, exit and restart.
        if (myosd_inGame == 0 || g_mame_reset)
            myosd_exitGame = 1;

        [self updateOptions];
        [self changeUI];
        
        NSInteger file_count = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSString stringWithUTF8String:get_documents_path("")] error:nil] count];
        NSInteger roms_count = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSString stringWithUTF8String:get_documents_path("roms")] error:nil] count];

        if (file_count != g_settings_file_count)
            NSLog(@"SETTINGS DONE: files added to root %ld => %ld", g_settings_file_count, file_count);
        if (roms_count != g_settings_roms_count)
            NSLog(@"SETTINGS DONE: files added to roms %ld => %ld", g_settings_roms_count, roms_count);

        if (g_settings_file_count != file_count)
            [self performSelector:@selector(moveROMS) withObject:nil afterDelay:0.0];
        else if (g_settings_roms_count != roms_count || (g_mame_reset && myosd_inGame == 0))
            [self performSelector:@selector(playGame:) withObject:nil afterDelay:0.0];
        
        // dont call endMenu (and unpause MAME) if we still have a dialog up.
        if (self.presentedViewController == nil)
            [self endMenu];
    }];
}

- (void)handle_MENU:(NSNumber*)status {
    
    // if we are showing an alert map controller input to the alert
    UIAlertController* alert = (UIAlertController*)[self presentedViewController];

    if ([alert isKindOfClass:[UIAlertController class]])
    {
        unsigned long pad_status = [status longValue];

        if (pad_status & (MYOSD_A|MYOSD_SELECT))
            [alert dismissWithDefault];
        if (pad_status & MYOSD_B)
            [alert dismissWithCancel];
        if (pad_status & MYOSD_Y)
            [alert dismissWithTitle:@"Ⓨ"];
        if (pad_status & MYOSD_X)
            [alert dismissWithTitle:@"Ⓧ"];
        if (pad_status & MYOSD_UP)
            [alert moveDefaultAction:-1];
        if (pad_status & MYOSD_DOWN)
            [alert moveDefaultAction:+1];
    }
}

- (void)handle_MENU
{
    // get input from all DPADs
    unsigned long pad_status = myosd_pad_status | myosd_joy_status[0] | myosd_joy_status[1] | myosd_joy_status[2] | myosd_joy_status[3];

#if TARGET_OS_IOS   // NOT needed on tvOS it handles it with the focus engine
    UIViewController* viewController = [self presentedViewController];

    // if a viewController is up send the input to it.
    if (viewController != nil) {

        if ([viewController isKindOfClass:[UINavigationController class]])
            viewController = [(UINavigationController*)viewController topViewController];

        // get input from left and right joystick of any player
        static NSTimeInterval g_last_input_time;
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if ((now - g_last_input_time) > 0.250 && (pad_status & (MYOSD_UP|MYOSD_DOWN|MYOSD_LEFT|MYOSD_RIGHT)) == 0) {
            for (int i=0; i<NUM_JOY; i++) {
                if (round(joy_analog_y[i][0] * 1000.0) / 1000.0 == +1.0 || round(joy_analog_y[i][1] * 1000.0) / 1000.0 == +1.0)
                    pad_status |= MYOSD_UP;
                if (round(joy_analog_y[i][0] * 1000.0) / 1000.0 == -1.0 || round(joy_analog_y[i][1] * 1000.0) / 1000.0 == -1.0)
                    pad_status |= MYOSD_DOWN;
                if (round(joy_analog_x[i][0] * 1000.0) / 1000.0 == +1.0 || round(joy_analog_x[i][1] * 1000.0) / 1000.0 == +1.0)
                    pad_status |= MYOSD_RIGHT;
                if (round(joy_analog_x[i][0] * 1000.0) / 1000.0 == -1.0 || round(joy_analog_x[i][1] * 1000.0) / 1000.0 == -1.0)
                    pad_status |= MYOSD_LEFT;
            }
            if  (pad_status & (MYOSD_UP|MYOSD_DOWN|MYOSD_LEFT|MYOSD_RIGHT))
                g_last_input_time = now;
        }

        // if we are showing some other UI, give it a chance to handle input.
        if ([viewController respondsToSelector:@selector(handle_MENU:)])
            [viewController performSelector:@selector(handle_MENU:) withObject:@(pad_status)];
        else
            [self handle_MENU:@(pad_status)];
        
        return;
    }
    
    // touch screen START button, when no COIN button
    if (CGRectIsEmpty(rInput[BTN_SELECT]) && (buttonState & MYOSD_START) && !(pad_status & MYOSD_START))
    {
        // TODO: handle 2P START?
        [self startPlayer:0];
    }

    // touch screen EXIT button
    if ((buttonState & MYOSD_EXIT) && !(pad_status & MYOSD_EXIT))
    {
        [self runExit:YES from:buttonViews[BTN_EXIT]];
    }
    
    // touch screen OPTION button
    if ((buttonState & MYOSD_OPTION) && !(pad_status & MYOSD_OPTION))
    {
        [self runMenu:0 from:buttonViews[BTN_OPTION]];
    }
#endif
    
    // exit MAME MENU with B (but only if we are not mapping a input)
    if (myosd_in_menu == 1 && (pad_status & MYOSD_B))
    {
        [self runExit];
    }
    
    // SELECT and START at the same time (iCade, keyboard, 8bitDo, touch)
    if ((pad_status & MYOSD_SELECT) && (pad_status & MYOSD_START))
    {
        // hide these keys from MAME
        myosd_pad_status &= ~(MYOSD_SELECT|MYOSD_START);
        [self runMenu];
    }
}

-(void)viewDidLoad{
    
   self.view.backgroundColor = [UIColor blackColor];

   controllers = [[NSMutableArray alloc] initWithCapacity:4];
    
   skinManager = [[SkinManager alloc] init];
    
   nameImgButton_NotPress[BTN_B] = @"button_NotPress_B.png";
   nameImgButton_NotPress[BTN_X] = @"button_NotPress_X.png";
   nameImgButton_NotPress[BTN_A] = @"button_NotPress_A.png";
   nameImgButton_NotPress[BTN_Y] = @"button_NotPress_Y.png";
   nameImgButton_NotPress[BTN_L1] = @"button_NotPress_L1.png";
   nameImgButton_NotPress[BTN_R1] = @"button_NotPress_R1.png";
   nameImgButton_NotPress[BTN_START] = @"button_NotPress_start.png";
   nameImgButton_NotPress[BTN_SELECT] = @"button_NotPress_select.png";
   nameImgButton_NotPress[BTN_EXIT] = @"button_NotPress_exit.png";
   nameImgButton_NotPress[BTN_OPTION] = @"button_NotPress_option.png";
   
   nameImgButton_Press[BTN_B] = @"button_Press_B.png";
   nameImgButton_Press[BTN_X] = @"button_Press_X.png";
   nameImgButton_Press[BTN_A] = @"button_Press_A.png";
   nameImgButton_Press[BTN_Y] = @"button_Press_Y.png";
   nameImgButton_Press[BTN_L1] = @"button_Press_L1.png";
   nameImgButton_Press[BTN_R1] = @"button_Press_R1.png";
   nameImgButton_Press[BTN_START] = @"button_Press_start.png";
   nameImgButton_Press[BTN_SELECT] = @"button_Press_select.png";
   nameImgButton_Press[BTN_EXIT] = @"button_Press_exit.png";
   nameImgButton_Press[BTN_OPTION] = @"button_Press_option.png";
    
    // map a button index to a MYOSD button mask
    buttonMask[BTN_A] = MYOSD_A;
    buttonMask[BTN_B] = MYOSD_B;
    buttonMask[BTN_X] = MYOSD_X;
    buttonMask[BTN_Y] = MYOSD_Y;
    buttonMask[BTN_L1] = MYOSD_L1;
    buttonMask[BTN_R1] = MYOSD_R1;
    buttonMask[BTN_EXIT] = MYOSD_EXIT;
    buttonMask[BTN_OPTION] = MYOSD_OPTION;
    buttonMask[BTN_SELECT] = MYOSD_SELECT;
    buttonMask[BTN_START] = MYOSD_START;
         
	self.view.userInteractionEnabled = YES;

#if TARGET_OS_IOS
	self.view.multipleTouchEnabled = YES;
	self.view.exclusiveTouch = NO;
#endif
	
	//kito
	[NSThread setThreadPriority:1.0];
	
    [self updateOptions];

#if TARGET_OS_IOS
    // Button to hide/show onscreen controls for lightgun games
    // Also functions as a show menu button when a game controller is used
    hideShowControlsForLightgun = [[UIButton alloc] initWithFrame:CGRectZero];
    hideShowControlsForLightgun.hidden = YES;
    [hideShowControlsForLightgun.imageView setContentMode:UIViewContentModeScaleAspectFit];
    [hideShowControlsForLightgun setImage:[UIImage imageNamed:@"dpad"] forState:UIControlStateNormal];
    [hideShowControlsForLightgun addTarget:self action:@selector(toggleControlsForLightgunButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    hideShowControlsForLightgun.alpha = 0.2f;
    hideShowControlsForLightgun.translatesAutoresizingMaskIntoConstraints = NO;
    [hideShowControlsForLightgun addConstraint:[NSLayoutConstraint constraintWithItem:hideShowControlsForLightgun attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:[[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad ? 30.0f : 20.0f]];
    [hideShowControlsForLightgun addConstraint:[NSLayoutConstraint constraintWithItem:hideShowControlsForLightgun attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:[[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad ? 30.0f :20.0f]];
    [self.view addSubview:hideShowControlsForLightgun];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:hideShowControlsForLightgun attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1.0f constant:0.0f]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:hideShowControlsForLightgun attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTopMargin multiplier:1.0f constant:8.0f]];
    areControlsHidden = NO;
#endif
    
    [self changeUI];
    
    icadeView = [[iCadeView alloc] initWithFrame:CGRectZero withEmuController:self];
    [self.view addSubview:icadeView];

    // always enable iCadeView for hardware keyboard support
    icadeView.active = YES;
    
    // see if bluetooth is enabled...
    
    if (@available(iOS 13.1, tvOS 13.0, *))
        g_bluetooth_enabled = CBCentralManager.authorization == CBManagerAuthorizationAllowedAlways;
    else if (@available(iOS 13.0, *))
        g_bluetooth_enabled = FALSE; // authorization is not in iOS 13.0, so no bluetooth for you.
    else
        g_bluetooth_enabled = TRUE;  // pre-iOS 13.0, bluetooth allways.
    
    NSLog(@"BLUETOOTH ENABLED: %@", g_bluetooth_enabled ? @"YES" : @"NO");
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(MFIControllerConnected:)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(MFIControllerDisconnected:)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
    
    if ([[GCController controllers] count] != 0) {
        [self performSelectorOnMainThread:@selector(setupMFIControllers) withObject:nil waitUntilDone:NO];
    }
    
    toastStyle = [[CSToastStyle alloc] initWithDefaultStyle];
    toastStyle.backgroundColor = [UIColor colorWithWhite:0.333 alpha:0.50];
    toastStyle.messageColor = [UIColor whiteColor];
    
    mouseInitialLocation = CGPointMake(9111, 9111);
    mouseTouchStartLocation = mouseInitialLocation;

    if (g_mame_game[0] && g_mame_game[0] != ' ')
        [self updateUserActivity:g_mame_game_info];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self scanForDevices];
}

#if TARGET_OS_IOS
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
    return UIRectEdgeBottom;
}
- (BOOL)prefersStatusBarHidden
{
    return YES;
}
-(BOOL)prefersHomeIndicatorAutoHidden
{
    return g_device_is_fullscreen;
}

- (BOOL)shouldAutorotate {
    return change_layout ? NO : YES;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (!CGSizeEqualToSize(layoutSize, self.view.bounds.size)) {
        layoutSize = self.view.bounds.size;
        [self loadHUD];
        [self changeUI];
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [self saveHUD];
}

#endif

#if TARGET_OS_IOS
-(void) toggleControlsForLightgunButtonPressed:(id)sender {
    // hack for when using a game controller - it will display the menu
    if ( g_joy_used ) {
        [self runMenu];
        return;
    }
    areControlsHidden = !areControlsHidden;
    
    if(analogStickView!=nil)
    {
        analogStickView.hidden = areControlsHidden;
    }
    
    for(int i=0; i<NUM_BUTTONS;i++)
    {
        if(buttonViews[i]!=nil)
        {
            buttonViews[i].hidden = areControlsHidden;
        }
    }
}
#endif

// hide or show the screen view
// called from changeUI, and changeUI is called from iphone_Reset_Views() each time a new game (or menu) is started.
- (void)updateScreenView {
    CGFloat alpha;
    if (myosd_inGame || g_mame_game[0])
        alpha = 1.0;
    else
        alpha = 0.0;
    
#if TARGET_OS_IOS
    if (change_layout) {
        alpha = 0.0;
        [self.view bringSubviewToFront:layoutView];
    }
#endif
    
    if (screenView.alpha != alpha) {
        if (alpha == 0.0)
            NSLog(@"**** HIDING ScreenView ****");
        else
            NSLog(@"**** SHOWING ScreenView ****");
    }

    screenView.alpha = alpha;
    imageOverlay.alpha = alpha;
    fpsView.alpha = alpha;
    imageLogo.alpha = (1.0 - alpha);
#if TARGET_OS_IOS
    hudView.alpha *= alpha;
#endif
}

-(void)buildLogoView {
    // no need to show logo in fullscreen.
    if (g_device_is_fullscreen || TARGET_OS_TV)
        return;

    // put a AirPlay logo on the iPhone screen when playing on external display
    if (externalView != nil)
    {
        imageExternalDisplay = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"airplayvideo"] ?: [UIImage imageNamed:@"mame_logo"]];
        imageExternalDisplay.contentMode = UIViewContentModeScaleAspectFit;
        imageExternalDisplay.frame = g_device_is_landscape ? rFrames[LANDSCAPE_VIEW_NOT_FULL] : rFrames[PORTRAIT_VIEW_NOT_FULL];
        [self.view addSubview:imageExternalDisplay];
    }

    // create a logo view to show when no-game is displayed. (place on external display, or in app.)
    imageLogo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"mame_logo"]];
    imageLogo.contentMode = UIViewContentModeScaleAspectFit;
    if (externalView != nil)
        imageLogo.frame = externalView.bounds;
    else if (g_device_is_fullscreen)
        imageLogo.frame = self.view.bounds;
    else
        imageLogo.frame = g_device_is_landscape ? rFrames[LANDSCAPE_VIEW_NOT_FULL] : rFrames[PORTRAIT_VIEW_NOT_FULL];
    [screenView.superview insertSubview:imageLogo aboveSubview:screenView];
}

-(void)buildFrameRateView {
    
    BOOL showFPS = g_pref_showFPS && (g_pref_showHUD == HudSizeZero || g_pref_showHUD == HudSizeTiny);

    myosd_fps = showFPS;

    if (!showFPS)
        return;
    
    // create a frame rate/info view and put it in the upper left corner of the screenView
    
    fpsView = [[UILabel alloc] init];
    fpsView.userInteractionEnabled = NO;
    fpsView.numberOfLines = 2;
    fpsView.font = [UIFont monospacedDigitSystemFontOfSize:(TARGET_OS_IOS ? 16.0 : 32.0) weight:UIFontWeightMedium];
    fpsView.textColor = UIColor.whiteColor; // self.view.tintColor;
#if OPAQUE_FPS
    fpsView.backgroundColor = UIColor.blackColor;
#else
    fpsView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.333];
#endif
    fpsView.shadowColor = UIColor.blackColor;
    fpsView.shadowOffset = CGSizeMake(1.0,1.0);
#if UPDATE_FPS_EVERY == 1
    fpsView.text = @"000:00:00🅼🆆\n0000.00fps 0.0ms";
#else
    fpsView.text = @"000.00fps 0.0ms 🅼🆆";
#endif
    
    CGPoint pos = screenView.frame.origin;

    // if we have room above, go single line.
    if (pos.y - fpsView.font.pointSize > screenView.superview.safeAreaInsets.top) {
        fpsView.numberOfLines = 1;
        fpsView.text =[fpsView.text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    }
    
    // put label in upper-left of screenView, or just above if room...
    CGSize size = [fpsView sizeThatFits:CGSizeZero];
    
    if (pos.y - (size.height+4) >= screenView.superview.safeAreaInsets.top)
        pos.y -= size.height+4;
    else if (pos.x - (size.width+4) >= screenView.superview.safeAreaInsets.left)
        pos.x -= size.width+4;
    else {
        pos.x += 4; pos.y += 4;
    }
    
    fpsView.frame = (CGRect){pos, size};
    [screenView.superview addSubview:fpsView];
}

#if TARGET_OS_IOS && defined(DEBUG)
static int gcd(int a, int b) {
    int c;
    while (a != 0) {
       c = a; a = b%a; b = c;
    }
    return b;
}
#endif

-(void)updateFrameRate {
    assert([NSThread isMainThread]);

    NSUInteger frame_count = screenView.frameCount;

    if (frame_count == 0)
        return;

#if UPDATE_FPS_EVERY == 1
    // get the timecode assuming 60fps
    NSUInteger frame = frame_count % 60;
    NSUInteger sec = (frame_count / 60) % 60;
    NSUInteger min = (frame_count / 3600);
    
    NSString* fps = [NSString stringWithFormat:@"%03d:%02d:%02d%@%@ %.2ffps %.1fms", (int)min, (int)sec, (int)frame,
                    [screenView isKindOfClass:[MetalScreenView class]] ? @"🅼" : @"",
                    [screenView isKindOfClass:[MetalScreenView class]] && [(MetalScreenView*)screenView pixelFormat] == MTLPixelFormatBGR10_XR ? @"🆆" : @"",
                    screenView.frameRateAverage, screenView.renderTimeAverage * 1000.0];
#else
    NSString* fps = [NSString stringWithFormat:@"%.2ffps %.1fms %@%@",
                     screenView.frameRateAverage, screenView.renderTimeAverage * 1000.0,
                     [screenView isKindOfClass:[MetalScreenView class]] ? @"🅼" : @"",
                     [screenView isKindOfClass:[MetalScreenView class]] && [(MetalScreenView*)screenView pixelFormat] != MTLPixelFormatBGRA8Unorm ? @"🆆" : @""];
#endif
    
    fpsView.text = fps;
#if TARGET_OS_IOS
    [hudView setValue:fps forKey:@"FPS"];
#ifdef DEBUG
    CGSize size = screenView.bounds.size;
    CGFloat scale = screenView.window.screen.scale;
    int n = gcd((int)(size.width * scale), (int)(size.height * scale));
    [hudView setValue:[NSString stringWithFormat:@"%dx%d@%dx [%d:%d]", (int)size.width, (int)size.height, (int)scale,
                       (int)(size.width * scale) / n,  (int)(size.height * scale) / n] forKey:@"SIZE"];
#endif
#endif
}

#if TARGET_OS_IOS

-(void)hudChange:(InfoHUD*)hud {
    NSLog(@"HUD CHANGE: %@=%@", hud.changedKey, [hud valueForKey:hud.changedKey]);
    
    if ([screenView isKindOfClass:[MetalScreenView class]]) {
        [(MetalScreenView*)screenView setShaderVariables:@{
            hud.changedKey: [hud valueForKey:hud.changedKey]
        }];
    }
    
#if DebugLog
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(logShader) object:nil];
    [self performSelector:@selector(logShader) withObject:nil afterDelay:0.500];
#endif
}
-(void)hudOptionChange:(PopupSegmentedControl*)seg {
    NSLog(@"HUD OPTION CHANGE %ld: %@", seg.selectedSegmentIndex, [seg titleForSegmentAtIndex:seg.selectedSegmentIndex]);
    NSString* str = [seg titleForSegmentAtIndex:seg.selectedSegmentIndex];
    BOOL is_vector_game = seg.tag;
    Options* op = [[Options alloc] init];
    switch ([seg.superview.subviews indexOfObject:seg]) {
        case 0:
            op.filter = str;
            break;
        case 1:
            op.skin = str;
            break;
        case 2:
            if (is_vector_game)
                op.lineShader = str;
            else
                op.screenShader = str;
            break;
    }
    [op saveOptions];
    [self updateOptions];
    [self changeUI];
}

// split and trim a string
static NSMutableArray* split(NSString* str, NSString* sep) {
    NSMutableArray* arr = [[str componentsSeparatedByString:sep] mutableCopy];
    for (int i=0; i<arr.count; i++)
        arr[i] = [arr[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return arr;
}

// if the list items are of the form "Name : Data", we only want to show "Name" to the user.
static NSArray* list_trim(NSArray* _list) {
    NSMutableArray* list = [_list mutableCopy];
    for (NSInteger i=0; i<list.count; i++)
        list[i] = [[list[i] componentsSeparatedByString:@":"].firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return [list copy];
}

#if DebugLog
-(void)logShader {
    NSDictionary* shader_variables = ([screenView isKindOfClass:[MetalScreenView class]]) ?  [(MetalScreenView*)screenView getShaderVariables] : nil;
    
    for (NSString* shader in @[g_pref_line_shader, g_pref_screen_shader]) {
        NSMutableArray* arr = [split(shader, @",") mutableCopy];
        
        for (int i=0; i<arr.count; i++) {
            if ([arr[i] hasPrefix:@"blend="] || ![arr[i] containsString:@"="])
                continue;
            NSString* key = split(arr[i], @"=").firstObject;
            NSArray* vals = split(split(arr[i], @"=").lastObject, @" ");
            arr[i] = shader_variables[key] ?: vals.firstObject;

            float step = (vals.count > 3) ? [vals[3] floatValue] : 0.001;
            arr[i] = @(round([arr[i] floatValue] / step) * step);
        }
        NSLog(@"%s SHADER: \"%@\"", (shader==g_pref_screen_shader) ? "SCREEN" : "LINE", [arr componentsJoinedByString:@", "]);
    }
}
#endif

-(void)saveHUD {
    if (hudView) {
        BOOL wide = self.view.bounds.size.width > self.view.bounds.size.height;
        [NSUserDefaults.standardUserDefaults setObject:NSStringFromCGRect(hudView.frame) forKey:wide ? kHUDPositionLandKey : kHUDPositionPortKey];
        [NSUserDefaults.standardUserDefaults setFloat:hudView.transform.a forKey:wide ? kHUDScaleLandKey : kHUDScalePortKey];
    }
}

-(void)loadHUD {
    
    if (hudView) {
        BOOL wide = self.view.bounds.size.width > self.view.bounds.size.height;

        CGRect rect = CGRectFromString([NSUserDefaults.standardUserDefaults stringForKey:wide ? kHUDPositionLandKey : kHUDPositionPortKey] ?: @"");
        CGFloat scale = [NSUserDefaults.standardUserDefaults floatForKey:wide ? kHUDScaleLandKey : kHUDScalePortKey] ?: 1.0;

        if (CGRectIsEmpty(rect)) {
            rect = CGRectMake(self.view.bounds.size.width/2, self.view.safeAreaInsets.top + 16, 0, 0);
            scale = 1.0;
        }

        hudView.transform = CGAffineTransformMakeScale(scale, scale);
        hudView.frame = rect;
    }
}


-(void)buildHUD {

    if (g_pref_showHUD == HudSizeZero) {
        [self saveHUD];
        [hudView removeFromSuperview];
        hudView = nil;
        return;
    }
    
    if (hudView == nil) {
        hudView = [[InfoHUD alloc] init];
        hudView.font = [UIFont monospacedDigitSystemFontOfSize:hudView.font.pointSize weight:UIFontWeightRegular];
        hudView.layoutMargins = UIEdgeInsetsMake(8, 8, 8, 8);
        [hudView addTarget:self action:@selector(hudChange:) forControlEvents:UIControlEventValueChanged];
        [self loadHUD];
        [self.view addSubview:hudView];
    }
    else {
        [self.view bringSubviewToFront:hudView];
    }
    
    [hudView removeAll];
    EmulatorController* _self = self;

    BOOL is_vector_game = [screenView isKindOfClass:[MetalScreenView class]] ? [(MetalScreenView*)screenView numScreens] == 0 : FALSE;
    NSString* shader = is_vector_game ? g_pref_line_shader : g_pref_screen_shader;
    BOOL can_edit_shader = [[shader stringByReplacingOccurrencesOfString:@"blend=" withString:@""] componentsSeparatedByString:@"="].count > 1;
    
    if (g_pref_showHUD == HudSizeEditor && !can_edit_shader)
        g_pref_showHUD = HudSizeLarge;
    
    if (g_pref_showHUD == HudSizeTiny) {
        [hudView addButton:@":command:⌘:" handler:^{
            Options* op = [[Options alloc] init];
            if (g_pref_saveHUD != HudSizeZero && g_pref_saveHUD != HudSizeTiny)
                g_pref_showHUD = g_pref_saveHUD;    // restore HUD to previous size.
            else
                g_pref_showHUD = HudSizeNormal;     // if HUD is OFF turn it on at Normal size.
            op.showHUD = g_pref_showHUD;
            [op saveOptions];
            [_self changeUI];
        }];
    }
    
    if (g_pref_showHUD != HudSizeTiny) {
        // add a toolbar of quick actions.
        NSArray* items = @[
            @"Coin", @"Start",
            @":rectangle.and.arrow.up.right.and.arrow.down.left:⤢:",
            @":gear:#:",
            (g_pref_showHUD == HudSizeLarge && can_edit_shader) ? @":slider.horizontal.3:=:" : @":list.dash:=:",
            @":command:⌘:"
        ];
        [hudView addToolbar:items handler:^(NSUInteger button) {
            NSLog(@"HUD BUTTON: %ld", button);
            switch (button) {
                case 0:
                    push_mame_button(0, MYOSD_SELECT);
                    break;
                case 1:
                    push_mame_button(0, MYOSD_START);
                    break;
                case 2:
                    [_self commandKey:'\r'];
                    break;
                case 3:
                    [_self runSettings];
                    break;
                case 4:
                {
                    Options* op = [[Options alloc] init];
                    if (g_pref_showHUD <= HudSizeNormal)
                        g_pref_showHUD = HudSizeLarge;
                    else if (g_pref_showHUD == HudSizeLarge && can_edit_shader)
                        g_pref_showHUD = HudSizeEditor;
                    else
                        g_pref_showHUD = HudSizeNormal;
                    op.showHUD = g_pref_showHUD;
                    [op saveOptions];
                    [_self changeUI];
                    break;
                }
                case 5:
                {
                    Options* op = [[Options alloc] init];
                    g_pref_saveHUD = g_pref_showHUD;
                    g_pref_showHUD = HudSizeTiny;
                    op.showHUD = g_pref_showHUD;
                    [op saveOptions];
                    [_self changeUI];
                    break;
                }
            }
        }];
        
        // add debug toolbar too
#ifdef DEBUG
        items = @[
            @":z.square.fill:Z:",
            @":a.square.fill:A:",
            @":x.square.fill:X:",
            @":i.square.fill:I:",
            @":p.square.fill:P:",
            @":d.square.fill:D:",
        ];
        [hudView addToolbar:items handler:^(NSUInteger button) {
            [_self commandKey:"ZAXIPD"[button]];
        }];
#endif
        // add FPS display
        if (g_pref_showFPS) {
            [hudView addValue:@"0000.00fps 000.0ms" forKey:@"FPS"];
#ifdef DEBUG
            [hudView addValue:@"WWWWxHHHH@2x" forKey:@"SIZE"];
#endif
        }
    }

    if (g_pref_showHUD == HudSizeLarge || g_pref_showHUD == HudSizeEditor) {
        // add set of buttons to select the Filter, Skin, and Effect/Shader
        NSArray* items = @[
            [[PopupSegmentedControl alloc] initWithItems:list_trim(Options.arrayFilter)],
            [[PopupSegmentedControl alloc] initWithItems:list_trim(Options.arraySkin)],
            [[PopupSegmentedControl alloc] initWithItems:list_trim(is_vector_game ? Options.arrayLineShader : Options.arrayScreenShader)],
        ];

        Options *op = [[Options alloc] init];
        [items[0] setSelectedSegmentIndex:[Options.arrayFilter indexOfOption:op.filter]];
        [items[1] setSelectedSegmentIndex:[Options.arraySkin indexOfOption:op.skin]];
        [items[2] setTag:is_vector_game];

        if (is_vector_game)
            [items[2] setSelectedSegmentIndex:[Options.arrayLineShader indexOfOption:op.lineShader]];
        else
            [items[2] setSelectedSegmentIndex:[Options.arrayScreenShader indexOfOption:op.screenShader]];

        [items[0] setTitle:@"Filter" forSegmentAtIndex:UISegmentedControlNoSegment];
        [items[1] setTitle:@"Skin" forSegmentAtIndex:UISegmentedControlNoSegment];
        [items[2] setTitle:@"Shader" forSegmentAtIndex:UISegmentedControlNoSegment];

        for (PopupSegmentedControl* seg in items) {
            [seg addTarget:self action:@selector(hudOptionChange:) forControlEvents:UIControlEventValueChanged];
            
            [seg setTitleTextAttributes:@{NSFontAttributeName:hudView.font} forState:UIControlStateNormal];
            CGFloat h = hudView.font.lineHeight * 1.5;
            [seg addConstraint:[NSLayoutConstraint constraintWithItem:seg attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:h]];

            if (@available(iOS 13.0, *)) {
                seg.selectedSegmentTintColor = self.view.tintColor;
                seg.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            }
        }
        [hudView addButtons:items handler:^(NSUInteger button) {}];
    }

    if (g_pref_showHUD == HudSizeLarge) {
        [hudView addButtons:(myosd_num_players >= 2) ? @[@":person:P1 Start", @":person.2:P2 Start"] : @[@":centsign.circle:Coin+Start"] handler:^(NSUInteger button) {
            [_self startPlayer:(int)button];
        }];
        if (myosd_num_players >= 3) {
            // FYI there is no person.4 symbol, so we just reuse person.3
            [hudView addButtons:@[@":person.3:P3 Start", (myosd_num_players >= 4) ? @":person.3:P4 Start" : @""] handler:^(NSUInteger button) {
                if (button+2 < myosd_num_players)
                    [_self startPlayer:(int)button + 2];
            }];
        }
        [hudView addButtons:@[@":bookmark:Load",@":bookmark.fill:Save"] handler:^(NSUInteger button) {
             [_self runState:button == 0 ? LOAD_STATE : SAVE_STATE];
        }];
        [hudView addButtons:@[@":slider.horizontal.3:Configure",@":power:Reset"] handler:^(NSUInteger button) {
            if (button == 0)
                myosd_configure = 1;
            else
                myosd_reset = 1;
        }];
        [hudView addButton:(myosd_inGame && myosd_in_menu==0) ? @":xmark.circle:Exit Game" : @":arrow.uturn.left.circle:Exit" color:UIColor.systemRedColor handler:^{
            [_self runExit:NO];
        }];
    }

    // add a bunch of slider controls to tweak with the current Shader
    if (g_pref_showHUD == HudSizeEditor) {
        NSDictionary* shader_variables = ([screenView isKindOfClass:[MetalScreenView class]]) ?  [(MetalScreenView*)screenView getShaderVariables] : nil;
        NSArray* shader_arr = split(shader, @",");

        [hudView addSeparator];
        [hudView addText:[NSString stringWithFormat:@"Shader: %@", shader_arr.firstObject]];

        for (NSString* str in shader_arr) {
            NSArray* arr = split(str, @"=");
            if (arr.count < 2 || [arr[0] isEqualToString:@"blend"])
                continue;

            NSString* name = arr[0];
            arr = split(arr[1], @" ");
            NSNumber* value = shader_variables[name] ?: @([arr[0] floatValue]);
            NSNumber* min = (arr.count > 1) ? @([arr[1] floatValue]) : @(0);
            NSNumber* max = (arr.count > 2) ? @([arr[2] floatValue]) : @([arr[0] floatValue]);
            NSNumber* step= (arr.count > 3) ? @([arr[3] floatValue]) : nil;

            [hudView addValue:value forKey:name format:nil min:min max:max step:step];
        }
#if DebugLog
        [self logShader];
#endif
    }
    
    // add a grab handle on the left so you can move the HUD without hitting a button.
    if (g_pref_showHUD != HudSizeZero) {
        hudView.layoutMargins = UIEdgeInsetsMake(8, 16, 8, 8);
        CGFloat height = [hudView sizeThatFits:CGSizeZero].height;
        CGFloat h = MIN(height * 0.5, 64.0);
        CGFloat w = hudView.layoutMargins.left / 4;
        UIView* grab = [hudView viewWithTag:42] ?: [[UIView alloc] init];
        grab.frame = CGRectMake((hudView.layoutMargins.left - w)/2, (height - h)/2, w, h);
        grab.tag = 42;
        grab.backgroundColor = [UIColor.darkGrayColor colorWithAlphaComponent:0.25];
        grab.layer.cornerRadius = w/2;
        [hudView addSubview:grab];
    }
    
    CGRect rect;
    CGRect bounds = self.view.bounds;
    CGRect frame = hudView.frame;
    CGFloat scale = hudView.transform.a;
    CGSize size = [hudView sizeThatFits:CGSizeZero];
    CGFloat w = size.width * scale;
    CGFloat h = size.height * scale;
    
    if (CGRectGetMidX(frame) < CGRectGetMidX(bounds) - (bounds.size.width * 0.1))
        rect = CGRectMake(frame.origin.x, frame.origin.y, w, h);
    else if (CGRectGetMidX(frame) > CGRectGetMidX(bounds) + (bounds.size.width * 0.1))
        rect = CGRectMake(frame.origin.x + frame.size.width - w, frame.origin.y, w, h);
    else
        rect = CGRectMake(frame.origin.x + frame.size.width/2 - w/2, frame.origin.y, w, h);

    rect.origin.x = MAX(self.view.safeAreaInsets.left + 8, MIN(self.view.bounds.size.width  - self.view.safeAreaInsets.right  - w - 8, rect.origin.x));
    rect.origin.y = MAX(self.view.safeAreaInsets.top + 8,  MIN(self.view.bounds.size.height - self.view.safeAreaInsets.bottom - h - 8, rect.origin.y));
    [self saveHUD];

    [UIView animateWithDuration:0.250 animations:^{
        self->hudView.frame = rect;
        if (g_pref_showHUD == HudSizeTiny)
            self->hudView.alpha = ((float)g_controller_opacity / 100.0f);
        else
            self->hudView.alpha = 1.0;
    }];
}
#else
// TODO: HUD on tvOS
-(void)saveHUD {
}
-(void)buildHUD {
}
#endif

- (void)resetUI {
    NSLog(@"RESET UI (MAME VIDEO MODE CHANGE)");
    [self changeUI];
}

- (void)changeUI { @autoreleasepool {

    int prev_emulation_paused = g_emulation_paused;
   
    if (g_emulation_paused == 0) {
        g_emulation_paused = 1;
        change_pause(1);
    }
    
    // reset the frame count when you first turn on/off
    if (g_pref_showFPS != (fpsView != nil))
        screenView.frameCount = 0;
#if TARGET_OS_IOS
    if ((g_pref_showHUD != 0) != (hudView != nil))
        screenView.frameCount = 0;
#endif
    
    [imageBack removeFromSuperview];
    imageBack = nil;

    [imageOverlay removeFromSuperview];
    imageOverlay = nil;

    [imageLogo removeFromSuperview];
    imageLogo = nil;
    
    [fpsView removeFromSuperview];
    fpsView = nil;

    [imageExternalDisplay removeFromSuperview];
    imageExternalDisplay = nil;
    
    // load the skin based on <ROMNAME>,<PARENT>,<MACHINE>,<USER PREF>
    if (g_mame_game[0] && g_mame_game[0] != ' ' && g_mame_game_info != nil)
        [skinManager setCurrentSkin:[NSString stringWithFormat:@"%s,%@,%@,%@", g_mame_game, g_mame_game_info[kGameInfoParent], g_mame_game_info[kGameInfoDriver], g_pref_skin]];
    else if (g_mame_game[0])
        [skinManager setCurrentSkin:g_pref_skin];

    [self buildScreenView];
    [self buildLogoView];
    [self buildFrameRateView];
    [self buildHUD];
    [self updateScreenView];

    if ( g_joy_used ) {
        [hideShowControlsForLightgun setImage:[UIImage imageNamed:@"menu"] forState:UIControlStateNormal];
    } else {
        [hideShowControlsForLightgun setImage:[UIImage imageNamed:@"dpad"] forState:UIControlStateNormal];
    }
    
    if (prev_emulation_paused != 1) {
        g_emulation_paused = 0;
        change_pause(0);
    }
    
    [UIApplication sharedApplication].idleTimerDisabled = (myosd_inGame || g_joy_used) ? YES : NO;//so atract mode dont sleep

    if ( prev_myosd_light_gun == 0 && myosd_light_gun == 1 && g_pref_lightgun_enabled ) {
        [self.view makeToast:@"Touch Lightgun Mode Enabled!" duration:2.0 position:CSToastPositionCenter style:toastStyle];
    }
    prev_myosd_light_gun = myosd_light_gun;
    
    if ( prev_myosd_mouse == 0 && myosd_mouse == 1 && g_pref_touch_analog_enabled ) {
        [self.view makeToast:@"Touch Mouse Mode Enabled!" duration:2.0 position:CSToastPositionCenter style:toastStyle];
    }
    prev_myosd_mouse = myosd_mouse;

    areControlsHidden = NO;
    
    memset(cyclesAfterButtonPressed, 0, sizeof(cyclesAfterButtonPressed));
}}

#define MAME_BUTTON_PLAYER_MASK     0xF0000000
#define MAME_BUTTON_PLAYER_SHIFT    28
NSMutableArray<NSNumber*>* g_mame_buttons;  // FIFO queue of buttons to press
NSLock* g_mame_buttons_lock;
NSInteger g_mame_buttons_tick;              // ticks until we send next one
        
static void push_mame_button(int player, int button)
{
    assert([NSThread isMainThread]);     // only add buttons from main thread
    if (g_mame_buttons == nil) {
        g_mame_buttons = [[NSMutableArray alloc] init];
        g_mame_buttons_lock = [[NSLock alloc] init];
    }
    button = button | (player << MAME_BUTTON_PLAYER_SHIFT);
    [g_mame_buttons_lock lock];
    [g_mame_buttons addObject:@(button)];
    [g_mame_buttons_lock unlock];
}
static void push_mame_buttons(int player, int button1, int button2)
{
    push_mame_button(player, button1);
    push_mame_button(player, button2);
}

// called from inside MAME droid_ios_poll_input
void myosd_handle_turbo() {
    
    // g_video_reset is set when iphone_Reset_Views is called, and we need to configure the UI fresh
    if (g_video_reset) {
        g_video_reset = FALSE;
        [sharedInstance performSelectorOnMainThread:@selector(resetUI) withObject:nil waitUntilDone:NO];
    }
    
    // keep myosd_waysStick uptodate
    if (ways_auto)
        myosd_waysStick = myosd_num_ways;

    // this is called on the MAME thread, need to be carefull and clean up!
    @autoreleasepool {
        
        // send keys - we do this inside of myosd_handle_turbo() because it is called from droid_ios_poll_input
        // ...and we are sure MAME is in a state to accept input, and not waking up from being paused or loading a ROM
        // ...we hold a key DOWN for 2 frames (buttonPressReleaseCycles) and wait (buttonNextPressCycles) frames  between keys.
        // ...these are *magic* numbers that seam to work good. if we hold a key down too long, games may ignore it. if we send too fast bad too.

        if (g_mame_buttons.count > 0) {
            
            if (g_mame_buttons_tick > 0) {
                g_mame_buttons_tick--;
                return;
            }
            
            [g_mame_buttons_lock lock];
            unsigned long button = g_mame_buttons.firstObject.intValue;
            unsigned long player = (button & MAME_BUTTON_PLAYER_MASK) >> MAME_BUTTON_PLAYER_SHIFT;
            button = button & ~MAME_BUTTON_PLAYER_MASK;
            
            if ((myosd_joy_status[player] & button) == button) {
                [g_mame_buttons removeObjectAtIndex:0];
                if (g_mame_buttons.count > 0)
                    g_mame_buttons_tick = buttonNextPressCycles;  // wait this long before next button
                myosd_joy_status[player] &= ~button;
                if (player == 0)
                    myosd_pad_status &= ~button;
            }
            else {
                g_mame_buttons_tick = buttonPressReleaseCycles;  // keep button DOWN for this long.
                myosd_joy_status[player] |= button;
                if (player == 0)
                    myosd_pad_status |= button;
            }
            [g_mame_buttons_lock unlock];
            return;
        }


        // dont do turbo mode in MAME menus.
        if (!(myosd_inGame && myosd_in_menu == 0))
            return;
        
        // also dont do turbo mode if all checks are off
        if ((turboBtnEnabled[BTN_X] | turboBtnEnabled[BTN_Y] |
             turboBtnEnabled[BTN_A] | turboBtnEnabled[BTN_B] |
             turboBtnEnabled[BTN_L1] | turboBtnEnabled[BTN_R1]) == 0) {
            return;
        }
        
        if (controllers.count > 0) {
            unsigned long mfi_button_state[NUM_JOY];
            
            // poll mfi controllers and read current state of buttons
            for (int i = 0; i < controllers.count; i++) {
                GCController *mfiController = [controllers objectAtIndex:i];
                GCExtendedGamepad *gamepad = mfiController.extendedGamepad;
                mfi_button_state[i]=(gamepad.buttonX.isPressed ? MYOSD_X : 0) |
                                    (gamepad.buttonY.isPressed ? MYOSD_Y : 0) |
                                    (gamepad.buttonA.isPressed ? MYOSD_A : 0) |
                                    (gamepad.buttonB.isPressed ? MYOSD_B : 0) |
                                    (gamepad.leftShoulder.isPressed ? MYOSD_L1 : 0) |
                                    (gamepad.rightShoulder.isPressed ? MYOSD_R1 : 0) ;
            }
            
            for (int button=0; button<NUM_BUTTONS; button++) {
                for (int i = 0; i < controllers.count; i++) {
                    if ( turboBtnEnabled[button] && (mfi_button_state[i] & buttonMask[button])) {
                        if ( cyclesAfterButtonPressed[i][button] > buttonPressReleaseCycles ) {
                            //NSLog(@"Turbo enabled! (mfi)");
                            if ( myosd_joy_status[i] & buttonMask[button]) {
                                myosd_joy_status[i] &= ~buttonMask[button];
                            } else {
                                myosd_joy_status[i] |= buttonMask[button];
                            }
                            cyclesAfterButtonPressed[i][button] = 0;
                        }
                        cyclesAfterButtonPressed[i][button]++;
                    }
                }
            }
        }
        else {
            // For the on-screen touch controlls
            for (int button=0; button<NUM_BUTTONS; button++) {
                if ( turboBtnEnabled[button] && (buttonState & buttonMask[button]) ) {
                    if ( cyclesAfterButtonPressed[0][button] > buttonPressReleaseCycles ) {
                        //NSLog(@"Turbo enabled!");
                        if ( myosd_pad_status & buttonMask[button]) {
                            myosd_pad_status &= ~buttonMask[button];
                        } else {
                            myosd_pad_status |= buttonMask[button];
                        }
                        cyclesAfterButtonPressed[0][button] = 0;
                    }
                    cyclesAfterButtonPressed[0][button]++;
                }
            }
        }
    }
}

#pragma mark - view layout

#if TARGET_OS_IOS

- (void)showDebugRect:(CGRect)rect color:(UIColor*)color title:(NSString*)title {

    if (CGRectIsEmpty(rect))
        return;

    UILabel* label = [[UILabel alloc] initWithFrame:rect];
    label.text = title;
    [label sizeToFit];
    label.userInteractionEnabled = NO;
    label.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.75];
    label.backgroundColor = [color colorWithAlphaComponent:0.25];
    [inputView addSubview:label];
    
    UIView* view = [[UIView alloc] initWithFrame:rect];
    view.userInteractionEnabled = NO;
    view.layer.borderColor = [color colorWithAlphaComponent:0.50].CGColor;
    view.layer.borderWidth = 1.0;
    [inputView addSubview:view];
}

// show debug rects
- (void) showDebugRects {
#ifdef DEBUG
    if (g_enable_debug_view)
    {
        UIView* null = [[UIView alloc] init];
        for (UIView* view in @[screenView, analogStickView ?: null, imageOverlay ?: null])
            [self showDebugRect:view.frame color:UIColor.systemYellowColor title:NSStringFromClass([view class])];
        
        for (int i=0; i<NUM_BUTTONS; i++)
        {
            CGRect rect = rInput[i];
            if (CGRectIsEmpty(rect) || CGRectEqualToRect(rect, rButton[i]))
                continue;
            [self showDebugRect:rect color:UIColor.systemBlueColor title:[NSString stringWithFormat:@"%d", i]];
        }
        for (int i=0; i<NUM_BUTTONS; i++)
        {
            CGRect rect = rButton[i];
            if (CGRectIsEmpty(rect))
                continue;
            [self showDebugRect:rect color:UIColor.systemPurpleColor title:[NSString stringWithFormat:@"%d", i]];
        }
    }
#endif
}


- (void)removeTouchControllerViews{

    [inputView removeFromSuperview];

    inputView=nil;
    analogStickView=nil;

    for (int i=0; i<NUM_BUTTONS;i++)
      buttonViews[i] = nil;
}

- (void)buildTouchControllerViews {

    [self removeTouchControllerViews];
    
    inputView = [[UIView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:inputView];
    
    g_joy_used = myosd_num_of_joys!=0;
   
    // no touch controlls for fullscreen with a joystick
    if (g_joy_used && g_device_is_fullscreen)
        return;
   
    BOOL touch_dpad_disabled = (myosd_mouse == 1 && g_pref_touch_analog_enabled && g_pref_touch_analog_hide_dpad) ||
                               (g_pref_touch_directional_enabled && g_pref_touch_analog_hide_dpad);
    if ( !touch_dpad_disabled || !myosd_inGame ) {
        //analogStickView
        analogStickView = [[AnalogStickView alloc] initWithFrame:rButton[BTN_STICK] withEmuController:self];
        [inputView addSubview:analogStickView];
        // stick background
        if (imageBack != nil) {
            NSString* back = g_device_is_landscape ? @"stick-background-landscape" : @"stick-background";
            UIImageView* image = [[UIImageView alloc] initWithImage:[self loadImage:back]];
            [imageBack addSubview:image];
            [self setButtonRect:BTN_STICK rect:rButton[BTN_STICK]];
        }
    }
    
    // get the number of fullscreen buttons to display, handle the auto case.
    int num_buttons = g_pref_full_num_buttons;
    if (num_buttons == -1)  // -1 == Auto
        num_buttons = (myosd_num_buttons == 0) ? 2 : myosd_num_buttons;
   
    BOOL touch_buttons_disabled = myosd_mouse == 1 && g_pref_touch_analog_enabled && g_pref_touch_analog_hide_buttons;
    buttonState = 0;
    for (int i=0; i<NUM_BUTTONS; i++)
    {
        if (nameImgButton_Press[i] == nil)
            continue;
        
        // hide buttons that are not used in fullscreen mode (and not laying out)
        if (g_device_is_fullscreen && !change_layout && !g_enable_debug_view)
        {
            if(i==BTN_X && (num_buttons < 4 && myosd_inGame))continue;
            if(i==BTN_Y && (num_buttons < 3 || !myosd_inGame))continue;
            if(i==BTN_B && (num_buttons < 2 || !myosd_inGame))continue;
            if(i==BTN_A && (num_buttons < 1 && myosd_inGame))continue;
            
            if(i==BTN_L1 && (num_buttons < 5 || !myosd_inGame))continue;
            if(i==BTN_R1 && (num_buttons < 6 || !myosd_inGame))continue;
            
            if (touch_buttons_disabled && !(i == BTN_SELECT || i == BTN_START || i == BTN_EXIT || i == BTN_OPTION)) continue;
            
            if ((g_pref_showHUD > 0) && (i == BTN_SELECT || i == BTN_START || i == BTN_EXIT || i == BTN_OPTION)) continue;
        }
        
        UIImage* image_up = [self loadImage:nameImgButton_NotPress[i]];
        UIImage* image_down = [self loadImage:nameImgButton_Press[i]];
        if (image_up == nil)
            continue;
        buttonViews[i] = [ [ UIImageView alloc ] initWithImage:image_up highlightedImage:image_down];
        buttonViews[i].contentMode = UIViewContentModeScaleAspectFit;
        
        [self setButtonRect:i rect:rButton[i]];

#ifdef __IPHONE_13_4
        if (@available(iOS 13.4, *)) {
            if (i == BTN_SELECT || i == BTN_START || i == BTN_EXIT || i == BTN_OPTION) {
// this hilights the whole square button, not the AspectFit part!
//                [buttonViews[i] addInteraction:[[UIPointerInteraction alloc] initWithDelegate:(id)self]];
//                [buttonViews[i] setUserInteractionEnabled:TRUE];
            }
        }
#endif
        if (g_device_is_fullscreen)
            [buttonViews[i] setAlpha:((float)g_controller_opacity / 100.0f)];
        
        [inputView addSubview: buttonViews[i]];
    }

    [self showDebugRects];
}

#pragma mark - UIPointerInteractionDelegate

#ifdef __IPHONE_13_4
- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region API_AVAILABLE(ios(13.4)) {
    UITargetedPreview* preview = [[UITargetedPreview alloc] initWithView:interaction.view];
    return [UIPointerStyle styleWithEffect:[UIPointerEffect effectWithPreview:preview] shape:nil];
}
#endif

#endif  // TARGET_OS_IOS

#pragma mark - background and overlay image

- (void)buildBackgroundImage {

    self.view.backgroundColor = [UIColor blackColor];

    // set a tiled image as our background
    UIImage* image = [self loadTileImage:@"background.png"];
    
    if (image != nil)
        self.view.backgroundColor = [UIColor colorWithPatternImage:image];

#if TARGET_OS_IOS
    if (g_device_is_fullscreen)
        return;
    
    imageBack = [[UIImageView alloc] init];
    imageBack.frame = rFrames[g_device_is_landscape ? LANDSCAPE_IMAGE_BACK : PORTRAIT_IMAGE_BACK];
    [self.view addSubview: imageBack];
    
    image = [self loadTileImage:g_device_is_landscape ? @"background_landscape_tile.png" : @"background_portrait_tile.png"];

    if (image != nil)
        imageBack.backgroundColor = [UIColor colorWithPatternImage:image];

    if (g_device_is_landscape)
        imageBack.image = [self loadImage:[self isPad] ? @"background_landscape.png" : @"background_landscape_wide.png"];
    else
        imageBack.image = [self loadImage:[self isPad] ? @"background_portrait.png" : @"background_portrait_tall.png"];
#endif
}

// load any border image and return the size needed to inset the game rect
- (void)getOverlayImage:(UIImage**)pImage andSize:(CGSize*)pSize {
    
    NSString* border_name = @"border";
    CGFloat   border_size = 0.25;
    UIImage*  image = [self loadTileImage:border_name];
    
    if (image == nil) {
        *pImage = nil;
        *pSize = CGSizeZero;
        return;
    }
    
    CGFloat scale = externalView ? externalView.window.screen.scale : UIScreen.mainScreen.scale;
    
    CGFloat cap_x = floor((image.size.width * image.scale  - 1.0) / 2.0) / image.scale;
    CGFloat cap_y = floor((image.size.height * image.scale - 1.0) / 2.0) / image.scale;
    image = [image resizableImageWithCapInsets:UIEdgeInsetsMake(cap_y, cap_x, cap_y, cap_x) resizingMode:UIImageResizingModeStretch];

    CGSize size;
    size.width  = floor(cap_x * border_size * scale) / scale;
    size.height = floor(cap_y * border_size * scale) / scale;

    *pImage = image;
    *pSize = size;
}

- (void)buildOverlayImage:(UIImage*)image rect:(CGRect)rect {
    if (image != nil) {
        imageOverlay = [[UIImageView alloc] initWithImage:image];
        imageOverlay.frame = rect;
        [screenView.superview addSubview:imageOverlay];
    }
}

#pragma mark - SCREEN VIEW SETUP

- (void)buildScreenView {
    
    g_device_is_landscape = (self.view.bounds.size.width >= self.view.bounds.size.height * 1.00);

    if (g_device_is_landscape)
        g_device_is_fullscreen = g_pref_full_screen_land;
    else
        g_device_is_fullscreen = g_pref_full_screen_port;

    if (g_joy_used && g_pref_full_screen_joy)
         g_device_is_fullscreen = TRUE;

    if (externalView != nil)
        g_device_is_fullscreen = FALSE;
    
#if TARGET_OS_MACCATALYST
    if (self.view.window != nil) {
        CGSize windowSize = self.view.window.bounds.size;
        CGSize screenSize = self.view.window.screen.bounds.size;
        
        // on Catalina the screenSize is a lie, so go to the NSScreen to get it!
        // on BigSur the screen size is correct, so check for the 960x540 "lie" value.
        if (screenSize.width == 960 && screenSize.height == 540)
            screenSize = [(id)([NSClassFromString(@"NSScreen") mainScreen]) frame].size;

        // To ensure that your text and interface elements are consistent with the macOS display environment, iOS views automatically scale down to 77%.
        // ...UIUserInterfaceIdiomMac (5) does not do this scaling.
        // https://developer.apple.com/design/human-interface-guidelines/ios/overview/mac-catalyst/
        if (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            screenSize.width = floor(screenSize.width / 0.77);
            screenSize.height = floor(screenSize.height / 0.77);
        }

        NSLog(@"screenSize: %@", NSStringFromSize(screenSize));
        NSLog(@"windowSize: %@", NSStringFromSize(windowSize));

        if (windowSize.width >= screenSize.width && windowSize.height >= screenSize.height) {
            NSLog(@"CATALYST FULLSCREEN");
            g_device_is_fullscreen = TRUE;
        }
    }
#endif
    
    if (change_layout)
        g_device_is_fullscreen = FALSE;

    CGRect r;

#if TARGET_OS_IOS
    [self loadLayout];      // load layout from skinManager
    [self adjustSizes];     // size buttons based on Settings

    [self buildBackgroundImage];
    
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];

    if (externalView != nil)
    {
        r = externalView.window.screen.bounds;
       
        CGFloat overscan = (g_pref_overscanTVOUT *  0.025f);
        CGFloat overscan_x = ceil(r.size.width * overscan / 2.0);
        CGFloat overscan_y = ceil(r.size.height * overscan / 2.0);

        r = CGRectInset(r, overscan_x, overscan_y);
    }
    else if (g_device_is_fullscreen)
    {
        r = rFrames[g_device_is_landscape ? LANDSCAPE_VIEW_FULL : PORTRAIT_VIEW_FULL];
    }
    else
    {
        r = rFrames[g_device_is_landscape ? LANDSCAPE_VIEW_NOT_FULL : PORTRAIT_VIEW_NOT_FULL];
    }

    // Handle Safe Area (iPhone X and above) adjust the view down away from the notch, before adjusting for aspect
    if ( externalView == nil ) {
        UIEdgeInsets safeArea = self.view.safeAreaInsets;

        // in fullscreen mode, we dont want to correct for the bottom inset, because we hide the home indicator.
        if (g_device_is_fullscreen)
            safeArea.bottom = 0.0;

#if TARGET_OS_MACCATALYST
        // in macApp, we dont want to correct for the top inset, if we have hidden the titlebar and want to go edge to edge.
        if (self.view.window.windowScene.titlebar.titleVisibility == UITitlebarTitleVisibilityHidden && self.view.window.windowScene.titlebar.toolbar == nil)
            safeArea.top = 0.0;
#endif
        r = CGRectIntersection(r, UIEdgeInsetsInsetRect(self.view.bounds, safeArea));
    }
#elif TARGET_OS_TV
    [self buildBackgroundImage];
    r = [[UIScreen mainScreen] bounds];
#endif
    // get the output device scale (mainSreen or external display)
    CGFloat scale = (externalView ?: self.view).window.screen.scale;
    
    // NOTE: view.window may be nil use mainScreen.scale in this case.
    if (scale == 0.0)
        scale = UIScreen.mainScreen.scale;

    // tell the OSD how big the screen is, so it can optimize texture sizes.
    if (myosd_display_width != (r.size.width * scale) || myosd_display_height != (r.size.height * scale)) {
        NSLog(@"DISPLAY SIZE CHANGE: %dx%d", (int)(r.size.width * scale), (int)(r.size.height * scale));
        myosd_display_width = (r.size.width * scale);
        myosd_display_height = (r.size.height * scale);
    }

    // make room for a border
    UIImage* border_image = nil;
    CGSize border_size = CGSizeZero;
    [self getOverlayImage:&border_image andSize:&border_size];
    r = CGRectInset(r, border_size.width, border_size.height);
    
    // preserve aspect ratio, and snap to pixels.
    if (g_pref_keep_aspect_ratio) {
        CGSize aspect;
        
        // use an exact aspect ratio of 4:3 or 3:4 iff possible
        if (floor(4.0 * myosd_vis_video_height / 3.0 + 0.5) == myosd_vis_video_width)
            aspect = CGSizeMake(4, 3);
        else if (floor(3.0 * myosd_vis_video_width / 4.0 + 0.5) == myosd_vis_video_height)
            aspect = CGSizeMake(4, 3);
        else if (floor(3.0 * myosd_vis_video_height / 4.0 + 0.5) == myosd_vis_video_width)
            aspect = CGSizeMake(3, 4);
        else if (floor(4.0 * myosd_vis_video_width / 3.0 + 0.5) == myosd_vis_video_height)
            aspect = CGSizeMake(3, 4);
        else
            aspect = CGSizeMake(myosd_vis_video_width, myosd_vis_video_height);

        //        r = AVMakeRectWithAspectRatioInsideRect(aspect, r);
        //        r.origin.x    = floor(r.origin.x * scale) / scale;
        //        r.origin.y    = floor(r.origin.y * scale) / scale;
        //        r.size.width  = floor(r.size.width * scale + 0.5) / scale;
        //        r.size.height = floor(r.size.height * scale + 0.5) / scale;

        CGFloat width = r.size.width * scale;
        CGFloat height = r.size.height * scale;
        
        if ((height * aspect.width / aspect.height) <= width) {
            for (int i=0; i<4; i++) {
                width = floor(height * aspect.width / aspect.height);
                height = floor(width * aspect.height / aspect.width);
            }
        }
        else {
            for (int i=0; i<4; i++) {
                height = floor(width * aspect.height / aspect.width);
                width = floor(height * aspect.width / aspect.height);
            }
        }
        r.origin.x    = r.origin.x + floor((r.size.width * scale - width) / 2.0) / scale;
        r.origin.y    = r.origin.y + floor((r.size.height * scale - height) / 2.0) / scale;
        r.size.width  = width / scale;
        r.size.height = height / scale;
    }
    
    // integer only scaling
    if (g_pref_integer_scale_only && myosd_vis_video_width < r.size.width * scale && myosd_vis_video_height < r.size.height * scale) {
        CGFloat n_w = floor(r.size.width * scale / myosd_vis_video_width);
        CGFloat n_h = floor(r.size.height * scale / myosd_vis_video_height);

        CGFloat new_width  = (n_w * myosd_vis_video_width) / scale;
        CGFloat new_height = (n_h * myosd_vis_video_height) / scale;
        
        NSLog(@"INTEGER SCALE[%d,%d] %dx%d => %0.3fx%0.3f@%dx", (int)n_w, (int)n_h, myosd_vis_video_width, myosd_vis_video_height, new_width, new_height, (int)scale);

        r.origin.x += floor((r.size.width - new_width)/2);
        r.origin.y += floor((r.size.height - new_height)/2);
        r.size.width = new_width;
        r.size.height = new_height;
    }
    
    NSDictionary* options = @{
        kScreenViewFilter: g_pref_filter,
        kScreenViewScreenShader: g_pref_screen_shader,
        kScreenViewLineShader: g_pref_line_shader,
        kScreenViewColorSpace: g_pref_colorspace,
    };
    
    // select a CoreGraphics or Metal ScreenView
    Class screen_view_class = [CGScreenView class];
    
    if (g_pref_metal && [MetalScreenView isSupported])
        screen_view_class = [MetalScreenView class];

    // the reason we dont re-create screenView each time is because we access screenView from background threads
    // (see iPhone_UpdateScreen, iPhone_DrawScreen) and we dont want to risk race condition on release.
    // and not creating/destroying the ScreenView on a simple size change or rotation, is good for performace.
    if (screenView == nil || [screenView class] != screen_view_class) {
        [screenView removeFromSuperview];
        screenView = [[screen_view_class alloc] init];
    }
    screenView.frame = r;
    screenView.userInteractionEnabled = NO;
    [screenView setOptions:options];
    
    UIView* superview = (externalView ?: self.view);
    if (screenView.superview != superview) {
        [screenView removeFromSuperview];
        [superview addSubview:screenView];
    }
    else {
        [superview bringSubviewToFront:screenView];
    }
           
    [self buildOverlayImage:border_image rect:CGRectInset(r, -border_size.width, -border_size.height)];

#if TARGET_OS_IOS
    screenView.multipleTouchEnabled = NO;
    [self buildTouchControllerViews];
#endif
   
    hideShowControlsForLightgun.hidden = YES;
    if (g_device_is_fullscreen &&
        (
         (myosd_light_gun && g_pref_lightgun_enabled) ||
         (myosd_mouse && g_pref_touch_analog_enabled)
        )) {
        // make a button to hide/display the controls
        hideShowControlsForLightgun.hidden = NO;
        [self.view bringSubviewToFront:hideShowControlsForLightgun];
    }
}

#pragma mark - INPUT

// handle_INPUT - called when input happens on a controller, keyboard, or screen
- (void)handle_INPUT {
#if defined(DEBUG) && DebugLog
    for (int i=0; i<MAX(1, myosd_num_of_joys); i++) {
        unsigned long pad_status = myosd_joy_status[i] | (i == 0 ? myosd_pad_status : 0);
        
        NSLog(@"%s[%d]: %s%s%s%s (%+1.3f,%+1.3f) %s%s%s%s %s%s%s%s%s%s %s%s%s%s (%+1.3f,%+1.3f) (%1.3f,%1.3f) inGame=%d, inMenu=%d",
              i==0 ? "handle_INPUT" : "            ", i,
              (pad_status & MYOSD_UP) ?   "U" : "-", (pad_status & MYOSD_DOWN) ?  "D" : "-",
              (pad_status & MYOSD_LEFT) ? "L" : "-", (pad_status & MYOSD_RIGHT) ? "R" : "-",

              joy_analog_x[i][0], joy_analog_y[i][0],

              (pad_status & MYOSD_A) ? "A" : "-", (pad_status & MYOSD_B) ? "B" : "-",
              (pad_status & MYOSD_X) ? "X" : "-", (pad_status & MYOSD_Y) ? "Y" : "-",
  
              (pad_status & MYOSD_L1) ? "L1" : "--", (pad_status & MYOSD_L2) ? "L2" : "--",
              (pad_status & MYOSD_L3) ? "L3" : "--", (pad_status & MYOSD_R3) ? "R3" : "--",
              (pad_status & MYOSD_R2) ? "R2" : "--", (pad_status & MYOSD_R1) ? "R1" : "--",

              (pad_status & MYOSD_SELECT) ? "C" : "-", (pad_status & MYOSD_EXIT) ? "X" : "-",
              (pad_status & MYOSD_OPTION) ? "M" : "-", (pad_status & MYOSD_START) ? "S" : "-",

              joy_analog_x[i][1], joy_analog_y[i][1], joy_analog_x[i][2],joy_analog_x[i][3],
              
              myosd_inGame, myosd_in_menu
              );
    }
#endif

    // call handle_MENU first so it can use buttonState to see key up.
    [self handle_MENU];
#if TARGET_OS_IOS
    [self handle_DPAD];
#endif
}

#if TARGET_OS_IOS
// update the state of the on-screen buttons and dpad/stick
- (void)handle_DPAD{
    unsigned long pad_status = myosd_pad_status | myosd_joy_status[0];
    
    if (!g_pref_animated_DPad || (g_device_is_fullscreen && g_joy_used)) {
        buttonState = pad_status;
        return;
    }

    for(int i=0; i< NUM_BUTTONS; i++)
    {
        if((buttonState & buttonMask[i]) != (pad_status & buttonMask[i]))
        {
            buttonViews[i].highlighted = (pad_status & buttonMask[i]) != 0;
            
#ifdef XDEBUG
            if(pad_status & buttonMask[i])
                NSLog(@"****** BUZZ! *******: %08X %@", (int)pad_status, [nameImgButton_Press[i] stringByDeletingPathExtension]);
            else
                NSLog(@"****** BONK! *******: %08X", (int)pad_status);
#endif
            
            if(pad_status & buttonMask[i])
                [self.impactFeedback impactOccurred];
            else
                [self.selectionFeedback selectionChanged];
        }
    }
    
    buttonState = pad_status;
    
    if (analogStickView != nil && ![analogStickView isHidden])
        [analogStickView update];
}
#endif

#pragma mark - MENU

-(BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(mameSelect) ||
        action == @selector(mameStart) ||
        action == @selector(mameStartP1) ||
        action == @selector(mameConfigure) ||
        action == @selector(mameSettings) ||
        action == @selector(mameFullscreen) ||
        action == @selector(mamePause) ||
        action == @selector(mameExit) ||
        action == @selector(mameReset)) {

        NSLog(@"canPerformAction: %@: %d", NSStringFromSelector(action), !g_emulation_paused && [self presentedViewController] == nil);
        
        return !g_emulation_paused && [self presentedViewController] == nil;
    }
    return [super canPerformAction:action withSender:sender];
}
-(void)mameSelect {
    push_mame_button(0, MYOSD_SELECT);
}
-(void)mameStart {
    push_mame_button(0, MYOSD_START);
}
-(void)mameStartP1 {
    [self startPlayer:0];
}
-(void)mameConfigure {
    myosd_configure = 1;
}
-(void)mameSettings {
    [self runSettings];
}
-(void)mamePause {
    myosd_mame_pause = 1;
}
-(void)mameReset {
    myosd_reset = 1;
}
-(void)mameFullscreen {
    [self commandKey:'\r'];
}
-(void)mameExit {
    [self runExit];
}



#pragma mark - KEYBOARD INPUT

// called from keyboard handler on any CMD+key (or OPTION+key) used for DEBUG stuff.
-(void)commandKey:(char)key {
// TODO: these temp toggles dont work the first time, because changUI will call updateSettings when waysAuto changes.
    switch (key) {
        case '\r':
            {
                Options* op = [[Options alloc] init];

                if (g_device_is_landscape)
                    op.fullscreenLandscape = g_pref_full_screen_land = !g_device_is_fullscreen;
                else
                    op.fullscreenPortrait = g_pref_full_screen_port = !g_device_is_fullscreen;

                // if user is manualy controling fullscreen, then turn off fullscreen joy.
                op.fullscreenJoystick = g_pref_full_screen_joy = FALSE;
                
#if TARGET_OS_MACCATALYST
                // in macApp we really only want one flag for "fullscreen"
                // NOTE: macApp has two concepts of fullsceen g_device_is_fullscreen is if
                // the game SCREEN fills our window, and a macApp's window can be fullscreen
                op.fullscreenLandscape = g_pref_full_screen_land = !g_device_is_fullscreen;
                op.fullscreenPortrait = g_pref_full_screen_port = !g_device_is_fullscreen;
#endif
                [op saveOptions];
                [self changeUI];
                break;
            }
            break;
        case '1':
        case '2':
            [self startPlayer:(key - '1')];
            break;
        case 'I':
            g_pref_integer_scale_only = !g_pref_integer_scale_only;
            [self changeUI];
            break;
        case 'Z':
            g_pref_showFPS = !g_pref_showFPS;
            [self changeUI];
            break;
        case 'F':
            g_pref_filter = [g_pref_filter isEqualToString:kScreenViewFilterNearest] ? kScreenViewFilterLinear : kScreenViewFilterNearest;
            [self changeUI];
            break;
        case 'H':   /* CMD+H is hide on macOS, so CMD+U will also show/hide the HUD */
        case 'U':
        {
            Options* op = [[Options alloc] init];

            if (g_pref_showHUD == HudSizeZero) {
                if (g_pref_saveHUD != HudSizeZero)
                    g_pref_showHUD = g_pref_saveHUD;    // restore HUD to previous size.
                else
                    g_pref_showHUD = HudSizeNormal;     // if HUD is OFF turn it on at Normal size.
            }
            else {
                g_pref_saveHUD = g_pref_showHUD;        // if HUD is ON, hide it but keep the size.
                g_pref_showHUD = HudSizeZero;
            }

            op.showHUD = g_pref_showHUD;
            [op saveOptions];
            [self changeUI];
            break;
        }
        case 'T':
            myosd_throttle = !myosd_throttle;
            [self changeUI];
            break;
        case 'V':
            myosd_vsync = myosd_vsync == -1 ? 6000 : -1;
            [self changeUI];
            break;
        case 'X':
            myosd_force_pxaspect = !myosd_force_pxaspect;
            [self changeUI];
            break;
        case 'A':
            g_pref_keep_aspect_ratio = !g_pref_keep_aspect_ratio;
            [self changeUI];
            break;
        case 'P':
            myosd_mame_pause = 1;
            break;
        case 'M':
        {
            // toggle Metal, but in order to load the right shader we need to change the global Options.
            Options* op = [[Options alloc] init];
            op.useMetal = !op.useMetal;
            [op saveOptions];
            [self updateOptions];
            [self changeUI];
            break;
        }
#ifdef DEBUG
        case 'R':
            g_enable_debug_view = !g_enable_debug_view;
            [self changeUI];
            break;
        case 'D':
            [CGScreenView drawScreenDebugDump];
            break;
#endif
    }
}


#if TARGET_OS_IOS

#pragma mark Touch Handling

-(NSSet*)touchHandler:(NSSet *)touches withEvent:(UIEvent *)event {
    if(change_layout)
    {
        [layoutView handleTouches:touches withEvent: event];
    }
    else if (g_joy_used && g_device_is_fullscreen)
    {
        // If controller is connected and display is full screen:
        // handle lightgun touches or
        // analog touches
        // else show the menu if touched
        NSSet *allTouches = [event allTouches];
        UITouch *touch = [[allTouches allObjects] objectAtIndex:0];
        
        if ( myosd_light_gun == 1 && g_pref_lightgun_enabled ) {
            [self handleLightgunTouchesBegan:touches];
            return nil;
        }
        
        if ( myosd_mouse == 1 && g_pref_touch_analog_enabled ) {
            return nil;
        }
        
        if(touch.phase == UITouchPhaseBegan && allTouches.count == 1)
        {
            [self runMenu];
        }
    }
    else
    {
        return [self touchesController:touches withEvent:event];
    }
    return nil;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
//    NSLog(@"👉👉👉👉👉👉 Touch Began!!! 👉👉👉👉👉👉👉");
    NSSet *handledTouches = [self touchHandler:touches withEvent:event];
    NSSet *allTouches = [event allTouches];
    NSMutableSet *unhandledTouches = [NSMutableSet set];
    for (int i =0; i < allTouches.count; i++) {
        UITouch *touch = [[allTouches allObjects] objectAtIndex:i];
        if ( ![handledTouches containsObject:touch] ) {
            [unhandledTouches addObject:touch];
        }
    }
    if ( g_pref_touch_analog_enabled && myosd_mouse == 1 && unhandledTouches.count > 0 ) {
        [self handleMouseTouchesBegan:unhandledTouches];
    }
    if ( g_pref_touch_directional_enabled && unhandledTouches.count > 0 ) {
        [self handleTouchMovementTouchesBegan:unhandledTouches];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
//    NSLog(@"👋👋👋👋👋👋👋 Touch Moved!!! 👋👋👋👋👋👋👋👋");
    NSSet *handledTouches = [self touchHandler:touches withEvent:event];
    NSSet *allTouches = [event allTouches];
    NSMutableSet *unhandledTouches = [NSMutableSet set];
    for (int i =0; i < allTouches.count; i++) {
        UITouch *touch = [[allTouches allObjects] objectAtIndex:i];
        if ( ![handledTouches containsObject:touch] ) {
            [unhandledTouches addObject:touch];
        }
    }
    if ( g_pref_touch_analog_enabled && myosd_mouse == 1 && unhandledTouches.count > 0 ) {
        [self handleMouseTouchesMoved:unhandledTouches];
    }
    if ( g_pref_touch_directional_enabled && unhandledTouches.count > 0 ) {
        [self handleTouchMovementTouchesMoved:unhandledTouches];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
//    NSLog(@"👊👊👊👊👊👊 Touch Cancelled!!! 👊👊👊👊👊👊");
    NSSet *handledTouches = [self touchHandler:touches withEvent:event];
    NSSet *allTouches = [event allTouches];
    NSMutableSet *unhandledTouches = [NSMutableSet set];
    for (int i =0; i < allTouches.count; i++) { 
        UITouch *touch = [[allTouches allObjects] objectAtIndex:i];
        if ( ![handledTouches containsObject:touch] ) {
            [unhandledTouches addObject:touch];
        }
    }
    if ( g_pref_touch_analog_enabled && myosd_mouse == 1 && unhandledTouches.count > 0 ) {
        [self handleMouseTouchesBegan:unhandledTouches];
    }
    if ( g_pref_touch_directional_enabled && unhandledTouches.count > 0 ) {
        [self handleTouchMovementTouchesBegan:unhandledTouches];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
//    NSLog(@"🖐🖐🖐🖐🖐🖐🖐 Touch Ended!!! 🖐🖐🖐🖐🖐🖐");
    [self touchHandler:touches withEvent:event];
    
    // light gun release?
    if ( myosd_light_gun == 1 && g_pref_lightgun_enabled ) {
        myosd_pad_status &= ~MYOSD_A;
        myosd_joy_status[0] &= ~MYOSD_A;
        myosd_pad_status &= ~MYOSD_B;
        myosd_joy_status[0] &= ~MYOSD_B;
    }
    
    if ( g_pref_touch_analog_enabled && myosd_mouse == 1 ) {
        mouse_x[0] = 0.0f;
        mouse_y[0] = 0.0f;
    }
    
    if ( g_pref_touch_directional_enabled ) {
        myosd_pad_status &= ~MYOSD_DOWN;
        myosd_pad_status &= ~MYOSD_UP;
        myosd_pad_status &= ~MYOSD_LEFT;
        myosd_pad_status &= ~MYOSD_RIGHT;
    }
}

- (NSSet*)touchesController:(NSSet *)touches withEvent:(UIEvent *)event {
    
    int i;
    static UITouch *stickTouch = nil;
    BOOL stickWasTouched = NO;
    NSMutableSet *handledTouches = [NSMutableSet set];
    
    //Get all the touches.
    NSSet *allTouches = [event allTouches];
    NSUInteger touchcount = [allTouches count];
    
    if ( areControlsHidden && g_pref_lightgun_enabled && g_device_is_landscape) {
        [self handleLightgunTouchesBegan:touches];
        return nil;
    }

    unsigned long pad_status = 0;

    for (i = 0; i < touchcount; i++)
    {
        UITouch *touch = [[allTouches allObjects] objectAtIndex:i];
        
        if(touch == nil)
        {
            continue;
        }
        
        if( touch.phase == UITouchPhaseBegan        ||
           touch.phase == UITouchPhaseMoved        ||
           touch.phase == UITouchPhaseStationary    )
        {
            struct CGPoint point;
            point = [touch locationInView:self.view];
            BOOL touch_dpad_disabled =
                // touch mouse is enabled and hiding dpad
                (myosd_mouse == 1 && g_pref_touch_analog_enabled && g_pref_touch_analog_hide_dpad) ||
                // OR directional touch is enabled and hiding dpad, and running a game
                (g_pref_touch_directional_enabled && g_pref_touch_analog_hide_dpad && myosd_inGame);
            if(!touch_dpad_disabled )
            {
                if(MyCGRectContainsPoint(analogStickView.frame, point) || stickTouch == touch)
                {
                    stickTouch = touch;
                    stickWasTouched = YES;
                    [analogStickView analogTouches:touch withEvent:event];
                }
            }
            
            if(touch == stickTouch) continue;
            
            BOOL touch_buttons_disabled = myosd_mouse == 1 && g_pref_touch_analog_enabled && g_pref_touch_analog_hide_buttons;
            
            if (buttonViews[BTN_Y] != nil &&
                !buttonViews[BTN_Y].hidden && MyCGRectContainsPoint(rInput[BTN_Y], point) &&
                !touch_buttons_disabled) {
                pad_status |= MYOSD_Y;
                //NSLog(@"MYOSD_Y");
                [handledTouches addObject:touch];
            }
            else if (buttonViews[BTN_X] != nil &&
                     !buttonViews[BTN_X].hidden && MyCGRectContainsPoint(rInput[BTN_X], point) &&
                     !touch_buttons_disabled) {
                pad_status |= MYOSD_X;
                //NSLog(@"MYOSD_X");
                [handledTouches addObject:touch];
            }
            else if (buttonViews[BTN_A] != nil &&
                     !buttonViews[BTN_A].hidden && MyCGRectContainsPoint(rInput[BTN_A], point) &&
                     !touch_buttons_disabled) {
                if(g_pref_BplusX)
                    pad_status |= MYOSD_X | MYOSD_B;
                else
                    pad_status |= MYOSD_A;
                //NSLog(@"MYOSD_A");
                [handledTouches addObject:touch];
            }
            else if (buttonViews[BTN_B] != nil && !buttonViews[BTN_B].hidden && MyCGRectContainsPoint(rInput[BTN_B], point) &&
                     !touch_buttons_disabled) {
                pad_status |= MYOSD_B;
                [handledTouches addObject:touch];
                //NSLog(@"MYOSD_B");
            }
            else if (buttonViews[BTN_A] != nil &&
                     buttonViews[BTN_Y] != nil &&
                     !buttonViews[BTN_A].hidden &&
                     !buttonViews[BTN_Y].hidden &&
                     MyCGRectContainsPoint(rInput[BTN_A_Y], point) &&
                     !touch_buttons_disabled) {
                pad_status |= MYOSD_Y | MYOSD_A;
                [handledTouches addObject:touch];
                //NSLog(@"MYOSD_Y | MYOSD_A");
            }
            else if (buttonViews[BTN_X] != nil &&
                     buttonViews[BTN_A] != nil &&
                     !buttonViews[BTN_X].hidden &&
                     !buttonViews[BTN_A].hidden &&
                     MyCGRectContainsPoint(rInput[BTN_A_X], point) &&
                     !touch_buttons_disabled) {
                
                pad_status |= MYOSD_X | MYOSD_A;
                [handledTouches addObject:touch];
                //NSLog(@"MYOSD_X | MYOSD_A");
            }
            else if (buttonViews[BTN_Y] != nil &&
                     buttonViews[BTN_B] != nil &&
                     !buttonViews[BTN_Y].hidden &&
                     !buttonViews[BTN_B].hidden &&
                     MyCGRectContainsPoint(rInput[BTN_B_Y], point) &&
                     !touch_buttons_disabled) {
                pad_status |= MYOSD_Y | MYOSD_B;
                [handledTouches addObject:touch];
                //NSLog(@"MYOSD_Y | MYOSD_B");
            }
            else if (!buttonViews[BTN_B].hidden &&
                     !buttonViews[BTN_X].hidden &&
                     MyCGRectContainsPoint(rInput[BTN_B_X], point) &&
                     !touch_buttons_disabled) {
                if(!g_pref_BplusX /*&& g_pref_land_num_buttons>=3*/)
                {
                    pad_status |= MYOSD_X | MYOSD_B;
                    [handledTouches addObject:touch];
                }
                //NSLog(@"MYOSD_X | MYOSD_B");
            }
            else if (!buttonViews[BTN_B].hidden &&
                     !buttonViews[BTN_A].hidden &&
                     MyCGRectContainsPoint(rInput[BTN_A_B], point) &&
                     !touch_buttons_disabled) {
                    pad_status |= MYOSD_A | MYOSD_B;
                    [handledTouches addObject:touch];
                //NSLog(@"MYOSD_A | MYOSD_B");
            }
            else if (MyCGRectContainsPoint(rInput[BTN_SELECT], point)) {
                //NSLog(@"MYOSD_SELECT");
                pad_status |= MYOSD_SELECT;
                [handledTouches addObject:touch];
            }
            else if (MyCGRectContainsPoint(rInput[BTN_START], point)) {
                //NSLog(@"MYOSD_START");
                pad_status |= MYOSD_START;
                [handledTouches addObject:touch];
            }
            else if (buttonViews[BTN_L1] != nil && !buttonViews[BTN_L1].hidden && MyCGRectContainsPoint(rInput[BTN_L1], point) && !touch_buttons_disabled) {
                //NSLog(@"MYOSD_L");
                pad_status |= MYOSD_L1;
                [handledTouches addObject:touch];
            }
            else if (buttonViews[BTN_R1] != nil && !buttonViews[BTN_R1].hidden && MyCGRectContainsPoint(rInput[BTN_R1], point) && !touch_buttons_disabled ) {
                //NSLog(@"MYOSD_R");
                pad_status |= MYOSD_R1;
                [handledTouches addObject:touch];
            }
            else if (buttonViews[BTN_EXIT] != nil && !buttonViews[BTN_EXIT].hidden && MyCGRectContainsPoint(rInput[BTN_EXIT], point)) {
                //NSLog(@"MYOSD_EXIT");
                pad_status |= MYOSD_EXIT;
                [handledTouches addObject:touch];
            }
            else if (buttonViews[BTN_OPTION] != nil && !buttonViews[BTN_OPTION].hidden && MyCGRectContainsPoint(rInput[BTN_OPTION], point) ) {
                 //NSLog(@"MYOSD_OPTION");
                 pad_status |= MYOSD_OPTION;
                 [handledTouches addObject:touch];
            }
            else if ( myosd_light_gun == 1 && g_pref_lightgun_enabled ) {
                [self handleLightgunTouchesBegan:touches];
            }
            // if the OPTION button is hidden (zero size) by the current Skin, support a tap on the game area.
            else if (CGRectIsEmpty(rInput[BTN_OPTION]) && CGRectContainsPoint(screenView.frame, point) ) {
                 pad_status |= MYOSD_OPTION;
                 [handledTouches addObject:touch];
            }
        }
        else
        {
            if(touch == stickTouch)
            {
                [analogStickView analogTouches:touch withEvent:event];
                stickWasTouched = YES;
                stickTouch = nil;
            }
        }
    }
    
    // merge in the button state this way, instead of setting to zero and |=, so MAME wont see a random button flip.
    const unsigned long BUTTON_MASK = (MYOSD_A|MYOSD_B|MYOSD_X|MYOSD_Y|MYOSD_L1|MYOSD_R1|MYOSD_SELECT|MYOSD_START|MYOSD_EXIT|MYOSD_OPTION);
    myosd_pad_status = pad_status | (myosd_pad_status & ~BUTTON_MASK);

    if (buttonState != myosd_pad_status || (stickWasTouched && g_pref_input_touch_type == TOUCH_INPUT_ANALOG)) {
        [self handle_INPUT];
    }
    
//    BOOL touchWasHandled = stickTouch != nil || handledTouches.count != 0;
//    NSLog(@"touchController touch stick touch =  %@ , buttonTouched = %@, wasStickTouched = %@",stickTouch != nil ? @"YES" : @"NO",buttonTouched ? @"YES" : @"NO",stickWasTouched ? @"YES" : @"NO");
    return handledTouches;
}


#pragma mark - Lightgun Touch Handler

- (void) handleLightgunTouchesBegan:(NSSet *)touches {
    NSUInteger touchcount = touches.count;
    if ( screenView.window != nil ) {
        UITouch *touch = [[touches allObjects] objectAtIndex:0];
        CGPoint touchLoc = [touch locationInView:screenView];
        CGFloat newX = (touchLoc.x - (screenView.bounds.size.width / 2.0f)) / (screenView.bounds.size.width / 2.0f);
        CGFloat newY = (touchLoc.y - (screenView.bounds.size.height / 2.0f)) / (screenView.bounds.size.height / 2.0f) * -1.0f;
//        NSLog(@"touch began light gun? loc: %f, %f",touchLoc.x, touchLoc.y);
//        NSLog(@"new loc = %f , %f",newX,newY);
        myosd_joy_status[0] |= MYOSD_A;
        myosd_pad_status |= MYOSD_A;
        if ( touchcount > 3 ) {
            // 4 touches = insert coin
            NSLog(@"LIGHTGUN: COIN");
            push_mame_button(0, MYOSD_SELECT);
        } else if ( touchcount > 2 ) {
            // 3 touches = press start
            NSLog(@"LIGHTGUN: START");
            push_mame_button(0, MYOSD_START);
        } else if ( touchcount > 1 ) {
            // more than one touch means secondary button press
            NSLog(@"LIGHTGUN: B");
            myosd_pad_status |= MYOSD_B;
            myosd_joy_status[0] |= MYOSD_B;
            myosd_pad_status &= ~MYOSD_A;
            myosd_joy_status[0] &= ~MYOSD_A;
        } else if ( touchcount == 1 ) {
            if ( g_pref_lightgun_bottom_reload && newY < -0.80 ) {
                NSLog(@"LIGHTGUN: RELOAD");
                newY = -12.1f;
            }
            NSLog(@"LIGHTGUN: %f,%f",newX,newY);
            lightgun_x[0] = newX;
            lightgun_y[0] = newY;
            
            if (joy_analog_x[0][0] != 0 || joy_analog_y[0][0] != 0 ||
                joy_analog_x[0][1] != 0 || joy_analog_y[0][1] != 0) {
                NSLog(@"LIGHTGUN: NON ZERO JOYSTICK! (%f,%f) (%f,%f)", joy_analog_x[0][0], joy_analog_y[0][0], joy_analog_x[0][1], joy_analog_y[0][1]);
            }
        }
    }
}

#pragma mark - Mouse Touch Support

-(void) handleMouseTouchesBegan:(NSSet *)touches {
    if ( screenView.window != nil ) {
        UITouch *touch = [[touches allObjects] objectAtIndex:0];
        mouseTouchStartLocation = [touch locationInView:screenView];
    }
}

- (void) handleMouseTouchesMoved:(NSSet *)touches {
    if ( screenView.window != nil && !CGPointEqualToPoint(mouseTouchStartLocation, mouseInitialLocation) ) {
        UITouch *touch = [[touches allObjects] objectAtIndex:0];
        CGPoint currentLocation = [touch locationInView:screenView];
        CGFloat dx = currentLocation.x - mouseTouchStartLocation.x;
        CGFloat dy = currentLocation.y - mouseTouchStartLocation.y;
        mouse_x[0] = dx * g_pref_touch_analog_sensitivity;
        mouse_y[0] = dy * g_pref_touch_analog_sensitivity;
        NSLog(@"mouse x = %f , mouse y = %f",mouse_x[0],mouse_y[0]);
        mouseTouchStartLocation = [touch locationInView:screenView];
    }
}

#pragma mark - Touch Movement Support
-(void) handleTouchMovementTouchesBegan:(NSSet *)touches {
    if ( screenView.window != nil ) {
        UITouch *touch = [[touches allObjects] objectAtIndex:0];
        touchDirectionalMoveStartLocation = [touch locationInView:screenView];
    }
}

-(void) handleTouchMovementTouchesMoved:(NSSet *)touches {
    if ( screenView.window != nil && !CGPointEqualToPoint(touchDirectionalMoveStartLocation, mouseInitialLocation) ) {
        myosd_pad_status &= ~MYOSD_DOWN;
        myosd_pad_status &= ~MYOSD_UP;
        myosd_pad_status &= ~MYOSD_LEFT;
        myosd_pad_status &= ~MYOSD_RIGHT;
        UITouch *touch = [[touches allObjects] objectAtIndex:0];
        CGPoint currentLocation = [touch locationInView:screenView];
        CGFloat dx = currentLocation.x - touchDirectionalMoveStartLocation.x;
        CGFloat dy = currentLocation.y - touchDirectionalMoveStartLocation.y;
        int threshold = 2;
        if ( dx > threshold ) {
            myosd_pad_status |= MYOSD_RIGHT;
            myosd_pad_status &= ~MYOSD_LEFT;
        } else if ( dx < -threshold ) {
            myosd_pad_status &= ~MYOSD_RIGHT;
            myosd_pad_status |= MYOSD_LEFT;
        }
        if ( dy > threshold ) {
            myosd_pad_status |= MYOSD_DOWN;
            myosd_pad_status &= ~MYOSD_UP;
        } else if (dy < -threshold ) {
            myosd_pad_status &= ~MYOSD_DOWN;
            myosd_pad_status |= MYOSD_UP;
        }
        if ( touchDirectionalCyclesAfterMoved++ > 5 ) {
            touchDirectionalMoveStartLocation = [touch locationInView:screenView];
            touchDirectionalCyclesAfterMoved = 0;
        }
    }
}

#endif

#pragma mark - BUTTON LAYOUT

- (UIImage *)loadImage:(NSString *)name {
    return [skinManager loadImage:name];
}
- (UIImage *)loadTileImage:(NSString *)name {
    UIImage* image = [skinManager loadImage:name];
    
    // if the image does not have a scale, use a default
    // we can use the screen scale, or assume @2x or @3x.
    //
    // @1x devices dont exist, so assuming @3x will be pixel perfect on hi-res devices
    // ...and scaled down a tad on @2x devices.
    if (image != nil && image.scale == 1.0)
        image = [[UIImage alloc] initWithCGImage:image.CGImage scale:3.0 orientation:image.imageOrientation];
    
    return image;
}


#if TARGET_OS_IOS

- (BOOL)isPhone {
    CGSize windowSize = self.view.bounds.size;
    return MAX(windowSize.width, windowSize.height) >= MIN(windowSize.width, windowSize.height) * 1.5;
}
- (BOOL)isPad {
    return ![self isPhone];
}

- (void)loadLayout {
    
    CGSize windowSize = self.view.bounds.size;
    assert(windowSize.width != 0.0 && windowSize.height != 0.0);
    BOOL isPhone = [self isPhone];

    // set the background and view rects.
    if (g_device_is_landscape) {
        // try to fit a 4:3 game screen with space on each side.
        CGFloat w = floor(MIN(windowSize.height * 4 / 3, windowSize.width * 0.75));
        CGFloat h = floor(w * 3 / 4);

        rFrames[LANDSCAPE_VIEW_FULL] = CGRectMake(0, 0, windowSize.width, windowSize.height);
        rFrames[LANDSCAPE_IMAGE_BACK] = CGRectMake(0, 0, windowSize.width, windowSize.height);
        rFrames[LANDSCAPE_VIEW_NOT_FULL] = CGRectMake(floor((windowSize.width-w)/2), 0, w, h);
    }
    else {
        // split the window, keeping the aspect ratio of the background image, on the bottom.
        UIImage* image = [self loadImage:isPhone ? @"background_portrait_tall" : @"background_portrait"];
        CGFloat aspect = image.size.height != 0 ? (image.size.width / image.size.height) : 1.0;
        
        // use a default aspect if the image is nil or square.
        if (aspect <= 1.0)
            aspect = isPhone ? 1.333 : 1.714;
        
        CGFloat h = floor(windowSize.width / aspect);

        rFrames[PORTRAIT_VIEW_FULL] = CGRectMake(0, 0, windowSize.width, windowSize.height);
        rFrames[PORTRAIT_VIEW_NOT_FULL] = CGRectMake(0, 0, windowSize.width, windowSize.height - h);
        rFrames[PORTRAIT_IMAGE_BACK] = CGRectMake(0, windowSize.height - h, windowSize.width, h);
    }
    
    for (int button=0; button<NUM_BUTTONS; button++)
        rInput[button] = rButton[button] = [self getLayoutRect:button];
    
    // if we are fullscreen portrait, we need to move the command buttons to the top of screen
    if (g_device_is_fullscreen && !g_device_is_landscape) {
        CGFloat x = 0, y = 0;
        rInput[BTN_SELECT].origin = rButton[BTN_SELECT].origin = CGPointMake(x, y);
        rInput[BTN_EXIT].origin   = rButton[BTN_EXIT].origin   = CGPointMake(x + rButton[BTN_SELECT].size.width, y);
        x = self.view.bounds.size.width - rButton[BTN_START].size.width;
        rInput[BTN_START].origin  = rButton[BTN_START].origin = CGPointMake(x, y);
        rInput[BTN_OPTION].origin = rButton[BTN_OPTION].origin  = CGPointMake(x - rButton[BTN_OPTION].size.width, y);
    }
    
    // set the default "radio" (percent size of the AnalogStick)
    stick_radio = 60;

    #define SWAPRECT(a,b) {CGRect t = a; a = b; b = t;}
        
    // swap A and B, swap X and Y
    if(g_pref_nintendoBAYX)
    {
        SWAPRECT(rButton[BTN_A], rButton[BTN_B]);
        SWAPRECT(rButton[BTN_X], rButton[BTN_Y]);

        SWAPRECT(rInput[BTN_A], rInput[BTN_B]);
        SWAPRECT(rInput[BTN_X], rInput[BTN_Y]);

        SWAPRECT(rInput[BTN_A_X], rInput[BTN_B_Y]);
        SWAPRECT(rInput[BTN_A_Y], rInput[BTN_B_X]);
    }
}

- (NSString*)getLayoutName {
    if ([self isPad])
        return g_device_is_landscape ? @"landscape" : @"portrait";
    else
        return g_device_is_landscape ? @"landscape_wide" : @"portrait_tall";
}

- (CGRect)getLayoutRect:(int)button {
    NSString* name = [self getLayoutName];
    CGRect back = g_device_is_landscape ? rFrames[LANDSCAPE_IMAGE_BACK] : rFrames[PORTRAIT_IMAGE_BACK];

    NSString* keyPath = [NSString stringWithFormat:@"%@.%@", name, [self getButtonName:button]];
    NSString* str = [skinManager valueForKeyPath:keyPath];
    if (![str isKindOfClass:[NSString class]])
        return CGRectZero;
    NSArray* arr = [str componentsSeparatedByString:@","];
    if (arr.count < 2)
        return CGRectZero;
    

    CGFloat scale_x = back.size.width / 1000.0;
    CGFloat scale_y = back.size.height / 1000.0;
    CGFloat scale = (scale_x + scale_y) / 2;

    CGFloat x = round(back.origin.x + [arr[0] intValue] * scale_x);
    CGFloat y = round(back.origin.y + [arr[1] intValue] * scale_y);
    CGFloat r = (arr.count > 2) ? [arr[2] intValue] : (g_device_is_landscape ? 120 : 180);

    CGFloat w = round(r * scale);
    CGFloat h = w;
    return CGRectMake(floor(x - w/2), floor(y - h/2), w, h);
}

// scale a CGRect but dont move the center
CGRect scale_rect(CGRect rect, CGFloat scale) {
    return CGRectInset(rect, -0.5 * rect.size.width * (scale - 1.0), -0.5 * rect.size.height * (scale - 1.0));
}

-(void)adjustSizes{
    
    if (change_layout)
        return;
    
    for(int i=0;i<NUM_BUTTONS;i++)
    {
        if(i==BTN_A || i==BTN_B || i==BTN_X || i==BTN_Y || i==BTN_R1 || i==BTN_L1)
        {
            rButton[i] = scale_rect(rButton[i], g_buttons_size);
            rInput[i] = scale_rect(rInput[i], g_buttons_size);
        }
    }
    
    if (g_device_is_fullscreen)
    {
        rButton[BTN_STICK] = scale_rect(rButton[BTN_STICK], g_stick_size);
        rInput[BTN_STICK] = scale_rect(rInput[BTN_STICK], g_stick_size);
    }
}

#pragma mark - BUTTON LAYOUT (save)

// json file with custom layout with same name as current skin
- (NSString*)getLayoutPath {
    NSString* skin_name = g_pref_skin;
    return [NSString stringWithFormat:@"%s/%@.json", get_documents_path("skins"), skin_name];
}

- (void)saveLayout {
    
    NSString* skin_name = g_pref_skin;
    NSString* layout_name = [self getLayoutName];

    // load json file with custom layout with same name as current skin
    NSString* path = [self getLayoutPath];
    NSData* data = [NSData dataWithContentsOfFile:path];
    NSMutableDictionary* dict = [(data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : @{}) mutableCopy];

    dict[layout_name] = [(dict[layout_name] ?: @{}) mutableCopy];
    dict[@"info"] = [(dict[@"info"] ?: @{}) mutableCopy];
    
    NSString* desc = [NSString stringWithFormat:@"Custom Button Layout for %@", skin_name];
    [dict setValue:@(1) forKeyPath:@"info.version"];
    [dict setValue:@PRODUCT_NAME_LONG forKeyPath:@"info.author"];
    [dict setValue:desc forKeyPath:@"info.description"];

    NSLog(@"SAVE LAYOUT: %@\n%@", layout_name, dict);

    for (int i=0; i<NUM_BUTTONS; i++) {
        CGRect rect = [self getButtonRect:i];
        CGRect rectLay = [self getLayoutRect:i];
        
        if (CGRectEqualToRect(rect, rectLay))
            continue;
        
        CGRect back = g_device_is_landscape ? rFrames[LANDSCAPE_IMAGE_BACK] : rFrames[PORTRAIT_IMAGE_BACK];
        CGFloat scale_x = back.size.width / 1000.0;
        CGFloat scale_y = back.size.height / 1000.0;
        CGFloat scale = (scale_x + scale_y) / 2;
        CGFloat x = round((CGRectGetMidX(rect) - back.origin.x) / scale_x);
        CGFloat y = round((CGRectGetMidY(rect) - back.origin.y) / scale_y);
        CGFloat w = round(rect.size.width / scale);

        NSString* keyPath = [NSString stringWithFormat:@"%@.%@", layout_name, [self getButtonName:i]];

        // if the size of the button did not change dont update w to prevent rounding creep
        if (rect.size.width == rectLay.size.width) {
            NSString* str = [skinManager valueForKeyPath:keyPath];
            w = [[str componentsSeparatedByString:@","].lastObject intValue];
        }
        
        NSString* value = [NSString stringWithFormat:@"%.0f,%.0f,%.0f", x, y, w];
        [dict setValue:value forKeyPath:keyPath];
    }
    
    NSLog(@"SAVE LAYOUT: %@\n%@", layout_name, dict);
    data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:path atomically:NO];
}

#endif

#pragma MOVE ROMs

// move a single ZIP file from the document root into where it belongs.
//
// we handle three kinds of ZIP files...
//
//  * zipset, if the ZIP contains other ZIP files, then it is a zip of romsets, aka zipset?.
//  * chdset, if the ZIP has CHDs in it, unzip and place in roms folder.
//  * artwork, if the ZIP contains a .LAY file, then it is artwork
//  * romset, if the ZIP has "normal" files in it assume it is a romset.
//
//  because we are registered to open *any* zip file, we also verify that a romset looks
//  valid, we dont want to copy "Funny Cat Pictures.zip" to our roms directory, no one wants that.
//  a valid romset must be a short <= 20 name with no spaces.
//
//  we will move a artwork zip file to the artwork directory
//  we will move a romset zip file to the roms directory
//  we will unzip (in place) a zipset or chdset
//
-(BOOL)moveROM:(NSString*)romName progressBlock:(void (^)(double progress))block {

    if (![[romName.pathExtension uppercaseString] isEqualToString:@"ZIP"])
        return FALSE;
    
    NSError *error = nil;

    NSString *rootPath = [NSString stringWithUTF8String:get_documents_path("")];
    NSString *romsPath = [NSString stringWithUTF8String:get_documents_path("roms")];
    NSString *artwPath = [NSString stringWithUTF8String:get_documents_path("artwork")];
    NSString *sampPath = [NSString stringWithUTF8String:get_documents_path("samples")];
    NSString *datsPath = [NSString stringWithUTF8String:get_documents_path("dats")];
    NSString *skinPath = [NSString stringWithUTF8String:get_documents_path("skins")];

    NSString *romPath = [rootPath stringByAppendingPathComponent:romName];
    
    // if the ROM had a name like "foobar 1.zip", "foobar (1).zip" use only the first word as the ROM name.
    // this most likley came when a user downloaded the zip and a foobar.zip already existed, MAME ROMs are <=20 char and no spaces.
    NSArray* words = [[romName stringByDeletingPathExtension] componentsSeparatedByString:@" "];
    if (words.count == 2 && [words.lastObject stringByTrimmingCharactersInSet:[NSCharacterSet punctuationCharacterSet]].intValue != 0)
        romName = [words.firstObject stringByAppendingPathExtension:@"zip"];

    NSLog(@"ROM NAME: '%@' PATH:%@", romName, romPath);

    //
    // scan the ZIP file to see what kind it is.
    //
    //  * zipset, if the ZIP contains other ZIP files, then it is a zip of romsets, aka zipset?.
    //  * chdset, if the ZIP has CHDs in it.
    //  * datset, if the ZIP has DATs in it. *NOTE* many ROMSETs have .DAT files, so we only check a whitelist of files.
    //  * artwork, if the ZIP contains a .LAY file, then it is artwork
    //  * samples, if the ZIP contains a .WAV file, then it is samples
    //  * skin, if the ZIP contains certain .PNG files that we use to draw buttons/etc
    //  * romset, if the ZIP has "normal" files in it assume it is a romset.
    //
    
    // list of files that mark a zip as a SKIN
    NSArray* skin_files = @[@"skin.json", @"border.png", @"background.png",
                            @"background_landscape.png", @"background_landscape_wide.png",
                            @"background_portrait.png", @"back_portrait_tall.png"];

    // whitelist of valid .DAT files we will copy to the dats folder
    NSArray* dat_files = @[@"HISTORY.DAT", @"MAMEINFO.DAT"];
    
    int __block numSKIN = 0;
    int __block numLAY = 0;
    int __block numZIP = 0;
    int __block numCHD = 0;
    int __block numWAV = 0;
    int __block numDAT = 0;
    int __block numFiles = 0;
    BOOL result = [ZipFile enumerate:romPath withOptions:ZipFileEnumFiles usingBlock:^(ZipFileInfo* info) {
        NSString* ext = [info.name.pathExtension uppercaseString];
        numFiles++;
        if ([ext isEqualToString:@"LAY"])
            numLAY++;
        if ([ext isEqualToString:@"ZIP"])
            numZIP++;
        if ([ext isEqualToString:@"WAV"])
            numWAV++;
        if ([ext isEqualToString:@"CHD"])
            numCHD++;
        if ([dat_files containsObject:info.name.lastPathComponent.uppercaseString])
            numDAT++;
        for (int i=0; i<NUM_BUTTONS; i++)
            numSKIN += [info.name.lastPathComponent isEqualToString:nameImgButton_Press[i]];
        if ([skin_files containsObject:info.name.lastPathComponent])
            numSKIN++;
    }];

    NSString* toPath = nil;

    if (!result)
    {
        NSLog(@"%@ is a CORRUPT ZIP (deleting)", romPath);
    }
    else if (numZIP != 0 || numCHD != 0 || numDAT != 0)
    {
        NSLog(@"%@ is a ZIPSET", [romPath lastPathComponent]);
        int maxFiles = numFiles;
        numFiles = 0;
        [ZipFile enumerate:romPath withOptions:(ZipFileEnumFiles + ZipFileEnumLoadData) usingBlock:^(ZipFileInfo* info) {
            
            if (info.data == nil)
                return;
            
            NSString* toPath = nil;
            NSString* ext  = info.name.pathExtension.uppercaseString;
            NSString* name = info.name.lastPathComponent;
            
            // only UNZIP files to specific directories, send a ZIP file with a unspecifed directory to roms/
            if ([info.name hasPrefix:@"roms/"] || [info.name hasPrefix:@"artwork/"] || [info.name hasPrefix:@"titles/"] || [info.name hasPrefix:@"samples/"] ||
                [info.name hasPrefix:@"cfg/"] || [info.name hasPrefix:@"ini/"] || [info.name hasPrefix:@"sta/"] || [info.name hasPrefix:@"hi/"] || [info.name hasPrefix:@"skins/"])
                toPath = [rootPath stringByAppendingPathComponent:info.name];
            else if ([name.uppercaseString isEqualToString:@"CHEAT.ZIP"])
                toPath = [rootPath stringByAppendingPathComponent:name];
            else if ([ext isEqualToString:@"DAT"])
                toPath = [datsPath stringByAppendingPathComponent:name];
            else if ([ext isEqualToString:@"ZIP"])
                toPath = [romsPath stringByAppendingPathComponent:name];
            else if ([ext isEqualToString:@"CHD"] && [info.name containsString:@"/"]) {
                // CHD will be of the form XXXXXXX/ROMNAME/file.chd, so move to roms/ROMNAME/file.chd
                NSString* romname = info.name.stringByDeletingLastPathComponent.lastPathComponent;
                toPath = [[romsPath stringByAppendingPathComponent:romname] stringByAppendingPathComponent:info.name.lastPathComponent];
            }

            if (toPath != nil)
                NSLog(@"...UNZIP: %@ => %@", info.name, [toPath stringByReplacingOccurrencesOfString:rootPath withString:@"~/"]);
            else
                NSLog(@"...UNZIP: %@ (ignoring)", info.name);

            if (toPath != nil)
            {
                if (![info.data writeToFile:toPath atomically:YES])
                {
                    NSLog(@"ERROR UNZIPing %@ (trying to create directory)", info.name);
                    
                    if (![NSFileManager.defaultManager createDirectoryAtPath:[toPath stringByDeletingLastPathComponent] withIntermediateDirectories:TRUE attributes:nil error:nil])
                        NSLog(@"ERROR CREATING DIRECTORY: %@", [info.name stringByDeletingLastPathComponent]);

                    if (![info.data writeToFile:toPath atomically:YES])
                        NSLog(@"ERROR UNZIPing %@", info.name);
                }
            }
            
            numFiles++;
            block((double)numFiles / maxFiles);
        }];
        toPath = nil;   // nothing to move, we unziped the file "in place"
    }
    else if (numLAY != 0)
    {
        NSLog(@"%@ is a ARTWORK file", romName);
        toPath = [artwPath stringByAppendingPathComponent:romName];
    }
    else if (numWAV != 0)
    {
        NSLog(@"%@ is a SAMPLES file", romName);
        toPath = [sampPath stringByAppendingPathComponent:romName];
    }
    else if (numSKIN != 0)
    {
        NSLog(@"%@ is a SKIN file", romName);
        toPath = [skinPath stringByAppendingPathComponent:romName];
    }
    else if ([romName length] <= 20 && ![romName containsString:@" "])
    {
        NSLog(@"%@ is a ROMSET", romName);
        toPath = [romsPath stringByAppendingPathComponent:romName];
    }
    else
    {
        NSLog(@"%@ is a NOT a ROMSET (deleting)", romName);
    }

    // move file to either ROMS, ARTWORK or SAMPLES
    if (toPath)
    {
        //first attemp to delete de old one
        [[NSFileManager defaultManager] removeItemAtPath:toPath error:&error];
        
        //now move it
        error = nil;
        [[NSFileManager defaultManager] moveItemAtPath:romPath toPath:toPath error:&error];
        if(error!=nil)
        {
            NSLog(@"Unable to move rom: %@", [error localizedDescription]);
            [[NSFileManager defaultManager] removeItemAtPath:romPath error:nil];
            result = FALSE;
        }
    }
    else
    {
        NSLog(@"DELETE: %@", romPath);
        [[NSFileManager defaultManager] removeItemAtPath:romPath error:nil];
    }
    return result;
}

-(void)moveROMS {
    
    NSArray *filelist;
    NSUInteger count;
    NSUInteger i;
    static int g_move_roms = 0;
    
    NSString *fromPath = [NSString stringWithUTF8String:get_documents_path("")];
    filelist = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fromPath error:nil];
    count = [filelist count];
    
    NSMutableArray *romlist = [[NSMutableArray alloc] init];
    for (i = 0; i < count; i++)
    {
        NSString *file = [filelist objectAtIndex: i];
        if([file isEqualToString:@"cheat.zip"])
            continue;
        if(![file hasSuffix:@".zip"])
            continue;
        [romlist addObject: file];
    }
    count = [romlist count];
    
    // on the first-boot cheat.zip will not exist, we want to be silent in this case.
    BOOL first_boot = [filelist containsObject:@"cheat0139.zip"];
    
    if(count != 0)
        NSLog(@"found (%d) ROMs to move....", (int)count);
    if(count != 0 && g_move_roms != 0)
        NSLog(@"....cant moveROMs now");
    
    if(count != 0 && g_move_roms++ == 0)
    {
        UIAlertController *progressAlert = nil;

        if (!first_boot) {
            progressAlert = [UIAlertController alertControllerWithTitle:@"Moving ROMs" message:@"Please wait..." preferredStyle:UIAlertControllerStyleAlert];
            [progressAlert setProgress:0.0];
            [self.topViewController presentViewController:progressAlert animated:YES completion:nil];
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL result = FALSE;
            for (int i = 0; i < count; i++)
            {
                result = result | [self moveROM:[romlist objectAtIndex: i] progressBlock:^(double progress) {
                    [progressAlert setProgress:((double)i / count) + progress * (1.0 / count)];
                }];
                [progressAlert setProgress:(double)(i+1) / count];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (progressAlert == nil)
                    g_move_roms = 0;
                [progressAlert.presentingViewController dismissViewControllerAnimated:YES completion:^{
                    
                    // tell the SkinManager new files have arived.
                    [self->skinManager reload];
                    
                    // reset MAME last game selected...
                    myosd_last_game_selected = 0;
                    
                    // reload the MAME menu....
                    [self performSelectorOnMainThread:@selector(playGame:) withObject:nil waitUntilDone:NO];
                    
                    g_move_roms = 0;
                }];
            });
        });
    }
}

// ZIP up all the important files in our documents directory
// this is more than just "ROMs" it saves *all* important files, kind of like an archive or backup.
// TODO: maybe we should also export the settings.bin or the UserDefaults plist
// NOTE we specificaly *dont* export CHDs because they are too big, we support importing CHDs just not exporting
-(BOOL)saveROMS:(NSURL*)url progressBlock:(BOOL (^)(double progress))block {

    NSString *rootPath = [NSString stringWithUTF8String:get_documents_path("")];
    NSString *romsPath = [NSString stringWithUTF8String:get_documents_path("roms")];
    NSString *skinPath = [NSString stringWithUTF8String:get_documents_path("skins")];

    NSMutableArray* files = [[NSMutableArray alloc] init];

    NSArray* roms = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:romsPath error:nil];
    for (NSString* rom in roms) {
        NSString* ext = [rom.pathExtension uppercaseString];
        
        if (![ext isEqualToString:@"ZIP"])
            continue;
        
        NSArray* paths = @[@"roms/%@.zip", @"artwork/%@.zip", @"titles/%@.png", @"samples/%@.zip", @"cfg/%@.cfg", @"ini/%@.ini", @"sta/%@/1.sta", @"sta/%@/2.sta", @"hi/%@.hi"];
        for (NSString* path in paths) {
            [files addObject:[NSString stringWithFormat:path, [rom stringByDeletingPathExtension]]];
        }
    }
    
    // save everything in the `skins` directory too
    for (NSString* skin in [NSFileManager.defaultManager contentsOfDirectoryAtPath:skinPath error:nil]) {
        if ([skin.pathExtension.uppercaseString isEqualToString:@"ZIP"])
            [files addObject:[NSString stringWithFormat:@"skins/%@", skin]];
    }
    
    NSLog(@"saveROMS: ROMS: %@", roms);
    NSLog(@"saveROMS: FILES: %@", files);
    
    return [ZipFile exportTo:url.path fromDirectory:rootPath withFiles:files withOptions:(ZipFileWriteFiles | ZipFileWriteAtomic | ZipFileWriteNoCompress) progressBlock:block];
}

#pragma mark - IMPORT and EXPORT

#if TARGET_OS_IOS

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        NSLog(@"IMPORT CANCELED");
        [self performSelectorOnMainThread:@selector(playGame:) withObject:nil waitUntilDone:NO];
    }
    else {
        NSLog(@"EXPORT CANCELED");
    }
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray <NSURL *>*)urls {
    
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        UIApplication* application = UIApplication.sharedApplication;
        for (NSURL* url in urls) {
            NSLog(@"IMPORT: %@", url);
            // call our own openURL handler (in Bootstrapper)
            [application.delegate application:application openURL:url options:@{UIApplicationOpenURLOptionsOpenInPlaceKey:@(NO)}];
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(moveROMS) object:nil];
        }
        [self performSelectorOnMainThread:@selector(moveROMS) withObject:nil waitUntilDone:NO];
    }
    else {
        assert(urls.count == 1);
        NSLog(@"EXPORT: %@", urls.firstObject);
    }
}

- (void)runImport {
    UIDocumentPickerViewController* documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.zip-archive"] inMode:UIDocumentPickerModeImport];
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    [self.topViewController presentViewController:documentPicker animated:YES completion:nil];
}

- (NSURL*)createTempFile:(NSString*)name {
    NSString* temp = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    NSURL* url = [NSURL fileURLWithPath:temp];
    [[NSFileManager defaultManager] createFileAtPath:temp contents:nil attributes:nil];
    return url;
}

- (void)runExport {
    NSString* name = @PRODUCT_NAME " (export)";
    
#if TARGET_OS_MACCATALYST
    NSURL *url = [self createTempFile:[name stringByAppendingPathExtension:@"zip"]];
    [self saveROMS:url progressBlock:nil];
    UIDocumentPickerViewController* documentPicker = [[UIDocumentPickerViewController alloc] initWithURLs:@[url] inMode:UIDocumentPickerModeMoveToService];
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    [self.topViewController presentViewController:documentPicker animated:YES completion:nil];
#else
    FileItemProvider* item = [[FileItemProvider alloc] initWithTitle:name typeIdentifier:@"public.zip-archive" saveHandler:^BOOL(NSURL* url, FileItemProviderProgressHandler progressHandler) {
        return [self saveROMS:url progressBlock:progressHandler];
    }];
    
    // NOTE UIActivityViewController is kind of broken in the Simulator, if you find a crash or problem verify it on a real device.
    UIActivityViewController* activity = [[UIActivityViewController alloc] initWithActivityItems:@[item] applicationActivities:nil];
    
    UIViewController* top = self.topViewController;

    if (activity.popoverPresentationController != nil) {
        activity.popoverPresentationController.sourceView = top.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0.0f, 0.0f);
        activity.popoverPresentationController.permittedArrowDirections = 0;
    }
    
    [top presentViewController:activity animated:YES completion:nil];
#endif
}
- (void)runExportSkin {
    
    BOOL isDefault = [g_pref_skin isEqualToString:kSkinNameDefault];

    NSString* skin_export_name;
    if (isDefault)
        skin_export_name = @PRODUCT_NAME " Default Skin";
    else
        skin_export_name = g_pref_skin;
    
#if TARGET_OS_MACCATALYST
    NSURL *url = [self createTempFile:[skin_export_name stringByAppendingPathExtension:@"zip"]];
    [skinManager exportTo:url.path progressBlock:nil];
    UIDocumentPickerViewController* documentPicker = [[UIDocumentPickerViewController alloc] initWithURLs:@[url] inMode:UIDocumentPickerModeMoveToService];
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    [self.topViewController presentViewController:documentPicker animated:YES completion:nil];
#else
    FileItemProvider* item = [[FileItemProvider alloc] initWithTitle:skin_export_name typeIdentifier:@"public.zip-archive" saveHandler:^BOOL(NSURL* url, FileItemProviderProgressHandler progressHandler) {
        return [self->skinManager exportTo:url.path progressBlock:progressHandler];
    }];
    
    // NOTE UIActivityViewController is kind of broken in the Simulator, if you find a crash or problem verify it on a real device.
    UIActivityViewController* activity = [[UIActivityViewController alloc] initWithActivityItems:@[item] applicationActivities:nil];
    
    UIViewController* top = self.topViewController;

    if (activity.popoverPresentationController != nil) {
        activity.popoverPresentationController.sourceView = top.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0.0f, 0.0f);
        activity.popoverPresentationController.permittedArrowDirections = 0;
    }
    
    [top presentViewController:activity animated:YES completion:nil];
#endif
}
#endif

- (void)runServer {
    [WebServer sharedInstance].webUploader.delegate = self;
    [[WebServer sharedInstance] startUploader];
}

#pragma mark - RESET

- (void)runReset {
    NSLog(@"RESET: %s", g_mame_game);
    
    NSString* msg = @"Reset " PRODUCT_NAME " back to factory defaults?";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
        for (NSString* key in @[kSelectedGameInfoKey, kHUDPositionLandKey, kHUDScaleLandKey, kHUDPositionPortKey, kHUDScalePortKey])
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        [Options resetOptions];
        [ChooseGameController reset];
        [SkinManager reset];
        g_mame_reset = TRUE;
        [self done:self];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.topViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - CUSTOM LAYOUT

#if TARGET_OS_IOS
-(void)beginCustomizeCurrentLayout{
    
    [self dismissViewControllerAnimated:YES completion:nil];
    
    layoutView = [[LayoutView alloc] initWithFrame:self.view.bounds withEmuController:self];
    layoutView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:layoutView];

    change_layout = 1;
    [self changeUI];
}

-(void)finishCustomizeCurrentLayout{
    
    [layoutView removeFromSuperview];
    layoutView = nil;
    
    change_layout = 0;
    [self changeUI]; //ensure GUI

    [self done:self];
}

-(void)resetCurrentLayout{
    
    [self showAlertWithTitle:nil message:@"Do you want to reset current layout to default?" buttons:@[@"Yes", @"No"] handler:^(NSUInteger buttonIndex) {
        if (buttonIndex == 0)
        {
            [NSFileManager.defaultManager removeItemAtPath:[self getLayoutPath] error:nil];
            [self->skinManager reload];
            [self done:self];
        }
    }];
}

-(void)saveCurrentLayout {
    [self saveLayout];
    [skinManager reload];
}

#endif

#pragma mark - MFI Controller

-(float) getDeadZone {
    float deadZone = 0;
    
    switch(g_pref_analog_DZ_value)
    {
        case 0:
            deadZone = 0.01f;
            break;
        case 1:
            deadZone = 0.05f;
            break;
        case 2:
            deadZone = 0.1f;
            break;
        case 3:
            deadZone = 0.15f;
            break;
        case 4:
            deadZone = 0.2f;
            break;
        case 5:
            deadZone = 0.3f;
            break;
    }
    
    return deadZone;
}

-(void)setupMFIControllers {
    
    // build list of controlers, put any non-game controllers (like the siri remote) at the end
    [controllers removeAllObjects];
    
    // add all the controllers with a extendedGamepad profile first
    for (GCController* controler in GCController.controllers) {
#if TARGET_IPHONE_SIMULATOR // ignore the bogus controller in the simulator
        if (controler.vendorName == nil || [controler.vendorName isEqualToString:@"Generic Controller"])
            continue;
#endif
        if (controler.extendedGamepad != nil)
            [controllers addObject:controler];
    }
    
    // now add any Steam Controllers, these should always have a extendedGamepad profile
    if (g_bluetooth_enabled) {
        for (GCController* controler in SteamControllerManager.sharedManager.controllers) {
            if (controler.extendedGamepad != nil)
                [controllers addObject:controler];
        }
    }
    // add all the controllers without a extendedGamepad profile last, ie the Siri Remote.
    for (GCController* controler in GCController.controllers) {
        if (controler.extendedGamepad == nil)
            [controllers addObject:controler];
    }

    if (controllers.count > NUM_JOY) {
        [controllers removeObjectsInRange:NSMakeRange(NUM_JOY,controllers.count - NUM_JOY)];
    }
    
    if (controllers.count != myosd_num_of_joys) {
        myosd_num_of_joys = (int)controllers.count;
        g_joy_used = (myosd_num_of_joys != 0);
        [self changeUI];
    }

    for (int index = 0; index < controllers.count; index++) {

        GCController *MFIController = [controllers objectAtIndex:index];
        
        [MFIController setPlayerIndex:GCControllerPlayerIndexUnset];
        [MFIController setPlayerIndex:index];
        
        NSLog(@" PlayerIndex: %li", (long)MFIController.playerIndex);
        
        BOOL isSiriRemote = (MFIController.extendedGamepad == nil && MFIController.microGamepad != nil);
        
        MFIController.extendedGamepad.dpad.valueChangedHandler = ^ (GCControllerDirectionPad *directionpad, float xValue, float yValue) {
            //NSLog(@"%d: %@", index, directionpad);
            
            int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.

            unsigned long dpad_status = myosd_joy_status[player];
            
            if (directionpad.up.pressed)
                myosd_joy_status[player] |= MYOSD_UP;
            else
                myosd_joy_status[player] &= ~MYOSD_UP;
            
            if (directionpad.down.pressed)
                myosd_joy_status[player] |= MYOSD_DOWN;
            else
                myosd_joy_status[player] &= ~MYOSD_DOWN;

            if (directionpad.left.pressed)
                myosd_joy_status[player] |= MYOSD_LEFT;
            else
                myosd_joy_status[player] &= ~MYOSD_LEFT;

            if (directionpad.right.pressed)
                myosd_joy_status[player] |= MYOSD_RIGHT;
            else
                myosd_joy_status[player] &= ~MYOSD_RIGHT;
            
            if (dpad_status != myosd_joy_status[player])
                [self handle_INPUT];
        };
        
        //
        // handle a MENU BUTTON modifier
        //
        //      MENU    = MAME4iOS MENU
        //      MENU+L1 = Pn COIN/SELECT
        //      MENU+R1 = Pn START
        //      MENU+L2 = P2 COIN/SELECT
        //      MENU+R2 = P2 START
        //      MENU+X  = EXIT
        //      MENU+B  = MAME MENU
        //      MENU+A  = LOAD STATE
        //      MENU+Y  = SAVE STATE
        //
        BOOL (^menuButtonHandler)(BOOL) = ^BOOL(BOOL pressed){
            static int g_menu_modifier_button_pressed[NUM_JOY];
            int player = (isSiriRemote || index >= myosd_num_inputs) ? 0 : index; // siri remote is always player 1

            NSLog(@"menuButtonHandler[%d]: %s", player, pressed ? "DOWN" : "UP");
#if TARGET_OS_TV
            // disable button presses while alert is shown
            if ([self controllerUserInteractionEnabled]) {
                return FALSE;
            }
#endif
            // on MENU button up, if no modifier was pressed then show menu
            if (!pressed) {
                BOOL result = g_menu_modifier_button_pressed[player] == FALSE;
                g_menu_modifier_button_pressed[player] = FALSE;  // reset for next time.
                return result;
            }

             // Add Coin
             if (MFIController.extendedGamepad.leftShoulder.pressed) {
                 NSLog(@"%d: MENU+L1 => COIN", player);
                 myosd_joy_status[player] &= ~MYOSD_L1;
                 push_mame_button((player < myosd_num_coins ? player : 0), MYOSD_SELECT);  // Player X coin
             }
             // Start
             else if (MFIController.extendedGamepad.rightShoulder.pressed) {
                 NSLog(@"%d: MENU+R1 => START", player);
                 myosd_joy_status[player] &= ~MYOSD_R1;
                 push_mame_button(player, MYOSD_START);
             }
            // Add P2 Coin
            else if (MFIController.extendedGamepad.leftTrigger.value == 1.0) {
                NSLog(@"%d: MENU+L2 => P2 COIN", player);
                myosd_joy_status[player] &= ~MYOSD_L2;
                push_mame_button((player < myosd_num_coins ? player : 0), MYOSD_SELECT);  // Player X coin
                push_mame_button((1 < myosd_num_coins ? 1 : 0), MYOSD_SELECT);  // Player 2 coin
            }
            // P2 Start
            else if (MFIController.extendedGamepad.rightTrigger.value == 1.0) {
                NSLog(@"%d: MENU+R1 => P2 START", player);
                myosd_joy_status[player] &= ~MYOSD_R2;
                push_mame_button(1, MYOSD_START);
            }
             //Show Mame menu
             else if (MFIController.extendedGamepad.buttonB.pressed) {
                 NSLog(@"%d: MENU+B => MAME MENU", player);
                 myosd_joy_status[player] &= ~MYOSD_B;
                 myosd_configure = 1;
             }
             //Exit Game
             else if (MFIController.extendedGamepad.buttonX.pressed) {
                 NSLog(@"%d: MENU+X => EXIT", player);
                 myosd_joy_status[player] &= ~MYOSD_X;
                 [self runExit];
             }
             // Load State
             else if (MFIController.extendedGamepad.buttonA.pressed ) {
                 NSLog(@"%d: MENU+A => LOAD STATE", player);
                 [self runLoadState];
             }
             // Save State
             else if (MFIController.extendedGamepad.buttonY.pressed ) {
                 NSLog(@"%d: MENU+Y => SAVE STATE", player);
                 [self runSaveState];
             }
             else {
                 return FALSE;
             }
             g_menu_modifier_button_pressed[player] = TRUE;
             return FALSE;
        };
        
        MFIController.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad* gamepad, GCControllerElement* element) {
            //NSLog(@"valueChangedHandler[%d]: %@ %s", index, element, ([element isKindOfClass:[GCControllerButtonInput class]] && [(GCControllerButtonInput*)element isPressed]) ? "PRESSED" : "");

            int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.
            
#if TARGET_OS_TV
            // disable button presses while alert is shown
            if ([self controllerUserInteractionEnabled]) {
                return;
            }
#endif
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wpartial-availability"
            GCControllerButtonInput *buttonHome = [gamepad respondsToSelector:@selector(buttonHome)] ? [gamepad buttonHome] : nil;
            GCControllerButtonInput *buttonMenu = [gamepad respondsToSelector:@selector(buttonMenu)] ? [gamepad buttonMenu] : nil;
            GCControllerButtonInput *buttonMeta = buttonHome ?: buttonMenu;
            if (element != buttonMeta && buttonMeta.pressed) {
                menuButtonHandler(TRUE);
                return;
            }
            #pragma clang diagnostic pop

            unsigned long dpad_status = myosd_joy_status[player];
            
            if (gamepad.buttonA.pressed)
                myosd_joy_status[player] |= MYOSD_A;
            else
                myosd_joy_status[player] &= ~MYOSD_A;
            
            if (gamepad.buttonB.pressed)
                myosd_joy_status[player] |= MYOSD_B;
            else
                myosd_joy_status[player] &= ~MYOSD_B;

            if (gamepad.buttonX.pressed)
                myosd_joy_status[player] |= MYOSD_X;
            else
                myosd_joy_status[player] &= ~MYOSD_X;
        
            if (gamepad.buttonY.pressed)
                myosd_joy_status[player] |= MYOSD_Y;
            else
                myosd_joy_status[player] &= ~MYOSD_Y;

            if (gamepad.leftShoulder.pressed)
                myosd_joy_status[player] |= MYOSD_L1;
            else
                myosd_joy_status[player] &= ~MYOSD_L1;
    
            if (gamepad.rightShoulder.pressed)
                myosd_joy_status[player] |= MYOSD_R1;
            else
                myosd_joy_status[player] &= ~MYOSD_R1;
            
            joy_analog_x[player][2] = gamepad.leftTrigger.value;
            if (gamepad.leftTrigger.pressed)
                myosd_joy_status[player] |= MYOSD_L2;
            else
                myosd_joy_status[player] &= ~MYOSD_L2;

            joy_analog_x[player][3] = gamepad.rightTrigger.value;
            if (gamepad.rightTrigger.pressed)
                myosd_joy_status[player] |= MYOSD_R2;
            else
                myosd_joy_status[player] &= ~MYOSD_R2;

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 120100 || __TV_OS_VERSION_MAX_ALLOWED >= 120100
            if (@available(iOS 12.1, *)) {
                if (gamepad.leftThumbstickButton.pressed)
                    myosd_joy_status[player] |= MYOSD_L3;
                else
                    myosd_joy_status[player] &= ~MYOSD_L3;
                
                if (gamepad.rightThumbstickButton.pressed)
                    myosd_joy_status[player] |= MYOSD_R3;
                else
                    myosd_joy_status[player] &= ~MYOSD_R3;
            }
#endif
            if (dpad_status != myosd_joy_status[player] || (element == gamepad.leftThumbstick && !g_device_is_fullscreen))
                [self handle_INPUT];
#ifdef DEBUG
            else if (element == gamepad.leftThumbstick || element == gamepad.rightThumbstick || element == gamepad.rightTrigger || element == gamepad.leftTrigger)
                [self handle_INPUT];
#endif
        };
        
        //
        // handle a siri remote, it only has a A,X,MENU button plus a dpad
        //
        if (isSiriRemote) {

            MFIController.microGamepad.allowsRotation = YES;
            MFIController.microGamepad.reportsAbsoluteDpadValues = NO;

            MFIController.microGamepad.valueChangedHandler = ^(GCMicroGamepad* gamepad, GCControllerElement* element) {
#if TARGET_OS_TV
                // disable button presses while alert is shown
                if ([self controllerUserInteractionEnabled]) {
                    return;
                }
#endif
                int player = 0; // siri remote is always player 1
                NSLog(@"%d(%d): %@", index, player, element);
                // in iOS 13.4 sometimes we get passed the wrong gamepad???
                if (gamepad != ((GCController*)controllers[index]).microGamepad) {
                    NSLog(@"WTF! %8@ != %8@", gamepad, ((GCController*)controllers[index]).microGamepad);
                    gamepad = ((GCController*)controllers[index]).microGamepad;
                }
                if (gamepad.buttonA.pressed)
                    myosd_joy_status[player] |= MYOSD_A;
                else
                    myosd_joy_status[player] &= ~MYOSD_A;
                
                if (gamepad.buttonX.pressed)
                    myosd_joy_status[player] |= MYOSD_X;
                else
                    myosd_joy_status[player] &= ~MYOSD_X;
            };
            MFIController.microGamepad.dpad.valueChangedHandler = ^ (GCControllerDirectionPad *directionpad, float xValue, float yValue) {
                NSInteger player = 0; // siri remote is always player 1

                //NSLog(@"%d(%d): %@", index, (int)player, directionpad);
                
                // emulate a analog joystick and a dpad, except when in a menu only a dpad
                if (myosd_inGame && !myosd_in_menu) {
                    joy_analog_x[player][0] = directionpad.xAxis.value;
                    if (STICK2WAY)
                        joy_analog_y[player][0] = 0.0;
                    else
                        joy_analog_y[player][0] = directionpad.yAxis.value;
                }
                else {
                    joy_analog_x[player][0] = 0.0;
                    joy_analog_y[player][0] = 0.0;
                }

                if (directionpad.up.pressed) {
                    myosd_joy_status[player] |= MYOSD_UP;
                }
                else {
                    myosd_joy_status[player] &= ~MYOSD_UP;
                }
                if (directionpad.down.pressed) {
                    myosd_joy_status[player] |= MYOSD_DOWN;
                }
                else {
                    myosd_joy_status[player] &= ~MYOSD_DOWN;
                }
                if (directionpad.left.pressed) {
                    myosd_joy_status[player] |= MYOSD_LEFT;
                }
                else {
                    myosd_joy_status[player] &= ~MYOSD_LEFT;
                }
                if (directionpad.right.pressed) {
                    myosd_joy_status[player] |= MYOSD_RIGHT;
                }
                else {
                    myosd_joy_status[player] &= ~MYOSD_RIGHT;
                }
                
                if (STICK2WAY) {
                     myosd_joy_status[player] &= ~(MYOSD_UP | MYOSD_DOWN);
                }
                else if (STICK4WAY) {
                    if (fabs(directionpad.yAxis.value) > fabs(directionpad.xAxis.value))
                        myosd_joy_status[player] &= ~(MYOSD_LEFT|MYOSD_RIGHT);
                    else
                        myosd_joy_status[player] &= ~(MYOSD_DOWN|MYOSD_UP);
                }
            };
        }
        
        MFIController.extendedGamepad.leftThumbstick.valueChangedHandler = ^ (GCControllerDirectionPad *directionpad, float xValue, float yValue) {
            
            float deadZone = [self getDeadZone];
            
            //NSLog(@"%d: %@", index, directionpad);
            
            int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.

            if (xValue < -deadZone)
                joy_analog_x[player][0] = xValue;
            if (xValue > deadZone)
                joy_analog_x[player][0] = xValue;
            if ( xValue <= deadZone && xValue >= -deadZone )
                joy_analog_x[player][0] = 0.0f;
            if (yValue > deadZone)
                joy_analog_y[player][0] = yValue;
            if (yValue < -deadZone)
                joy_analog_y[player][0] = yValue;
            if ( yValue <= deadZone && yValue >= -deadZone )
                joy_analog_y[player][0] = 0.0f;
        };
        
        MFIController.extendedGamepad.rightThumbstick.valueChangedHandler = ^ (GCControllerDirectionPad *directionpad, float xValue, float yValue) {
            
            float deadZone = [self getDeadZone];
            
            //NSLog(@"%d: %@", index, directionpad);
            
            int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.

            if (xValue < -deadZone)
                joy_analog_x[player][1] = xValue;
            if (xValue > deadZone)
                joy_analog_x[player][1] = xValue;
            if ( xValue <= deadZone && xValue >= -deadZone )
                joy_analog_x[player][1] = 0.0f;
            if (yValue > deadZone)
                joy_analog_y[player][1] = yValue;
            if (yValue < -deadZone)
                joy_analog_y[player][1] = yValue;
            if ( yValue <= deadZone && yValue >= -deadZone )
                joy_analog_y[player][1] = 0.0f;
        };
        
        // install handlers for MENU and OPTION buttons, if the controller has neither, insall a old skoool pause handler.
        id gamepad = MFIController.extendedGamepad ?: MFIController.microGamepad;
        
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wpartial-availability"
        GCControllerButtonInput *buttonHome = [gamepad respondsToSelector:@selector(buttonHome)] ? [gamepad buttonHome] : nil;
        GCControllerButtonInput *buttonMenu = [gamepad respondsToSelector:@selector(buttonMenu)] ? [gamepad buttonMenu] : nil;
        GCControllerButtonInput *buttonOptions = [gamepad respondsToSelector:@selector(buttonOptions)] ? [gamepad buttonOptions] : nil;
        #pragma clang diagnostic pop
        
        // iOS 14+ we have three buttons: OPTION(left) HOME(center), MENU(right)
        //      HOME   => MAME4iOS MENU
        //      OPTION => SELECT/COIN
        //      MENU   => START
        if (buttonHome != nil && buttonMenu != nil && buttonOptions != nil) {
            // HOME BUTTON => MAME4iOS MENU
            buttonHome.pressedChangedHandler = ^(GCControllerButtonInput* button, float value, BOOL pressed) {
                NSLog(@"%d: MENU/HOME %s", index, (pressed ? "DOWN" : "UP"));
                int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.
                if (menuButtonHandler(pressed))
                    [self toggleMenu:player];
            };
            // OPTION BUTTON => SELECT
            buttonOptions.pressedChangedHandler = ^(GCControllerButtonInput* button, float value, BOOL pressed) {
                NSLog(@"%d: SELECT %s", index, (pressed ? "DOWN" : "UP"));
                int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.
                if (pressed)
                    myosd_joy_status[player] |= MYOSD_SELECT;
                else
                    myosd_joy_status[player] &= ~MYOSD_SELECT;
                [self handle_INPUT];
            };
            // MENU BUTTON => START
            buttonMenu.pressedChangedHandler = ^(GCControllerButtonInput* button, float value, BOOL pressed) {
                NSLog(@"%d: START %s", index, (pressed ? "DOWN" : "UP"));
                int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.
                if (pressed)
                    myosd_joy_status[player] |= MYOSD_START;
                else
                    myosd_joy_status[player] &= ~MYOSD_START;
                [self handle_INPUT];
            };
        }
        // iOS 13+ we have (up to) two buttons MENU(right), and OPTION(left)
        //      MENU   => MAME4iOS MENU
        //      OPTION => do a SELECT + START (Px START)
        else {
            // MENU BUTTON
            buttonMenu.pressedChangedHandler = ^(GCControllerButtonInput* button, float value, BOOL pressed) {
                NSLog(@"%d: MENU %s", index, (pressed ? "DOWN" : "UP"));
                int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.
                if (menuButtonHandler(pressed))
                    [self toggleMenu:player];
            };
            // OPTION BUTTON => Px START
            buttonOptions.pressedChangedHandler = ^(GCControllerButtonInput* button, float value, BOOL pressed) {
                NSLog(@"%d: OPTION %s", index, (pressed ? "DOWN" : "UP"));
                int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.
                if (pressed && !g_emulation_paused) {
                    if (player < 2)    // add a extra coin for luck, for games that default to two credits.
                        push_mame_button(0, MYOSD_SELECT);  // Player 1 coin
                    push_mame_button((player < myosd_num_coins ? player : 0), MYOSD_SELECT);  // Player X COIN
                    push_mame_button(player, MYOSD_START); // Player X START
                }
            };
            // < iOS 13 we only have a PAUSE handler, and we only get a single event on button up
            // PASUE => MAME4iOS MENU
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated"
            if (buttonMenu == nil && buttonOptions == nil) {
                NSLog(@"%d: PAUSE", index);
                MFIController.controllerPausedHandler = ^(GCController *controller) {
                    int player = (index < myosd_num_inputs) ? index : 0; // act as Player 1 if MAME is not using us.
                    menuButtonHandler(TRUE);
                    if (menuButtonHandler(FALSE))
                        [self toggleMenu:player];
                };
            }
            #pragma clang diagnostic pop
        }
    }
}

-(void)scanForDevices{
    [GCController startWirelessControllerDiscoveryWithCompletionHandler:nil];
    if (g_bluetooth_enabled)
        [[SteamControllerManager sharedManager] scanForControllers];
}

-(void)MFIControllerConnected:(NSNotification*)notif{
    GCController *controller = (GCController *)[notif object];
    NSLog(@"Hello %@", controller.vendorName);

    // if we already have this controller, ignore
    if ([controllers containsObject:controller])
        return;

    [self setupMFIControllers];
#if TARGET_OS_IOS
    if ([controllers containsObject:controller]) {
        [self.view makeToast:[NSString stringWithFormat:@"%@ connected", controller.vendorName] duration:4.0 position:CSToastPositionTop style:toastStyle];
    }
#endif
}

-(void)MFIControllerDisconnected:(NSNotification*)notif{
    GCController *controller = (GCController *)[notif object];
    
    if (![controllers containsObject:controller])
        return;
    
    NSLog(@"Goodbye %@", controller.vendorName);
    [self setupMFIControllers];
#if TARGET_OS_IOS
    [self.view makeToast:[NSString stringWithFormat:@"%@ disconnected", controller.vendorName] duration:4.0 position:CSToastPositionTop style:toastStyle];
#endif
}

#pragma mark GCDWebServerDelegate

- (void)webServerDidStart:(GCDWebServer *)server {
    // give Bonjour some time to register, else go ahead
    [self performSelector:@selector(webServerShowAlert:) withObject:server afterDelay:2.0];
}

- (void)webServerDidCompleteBonjourRegistration:(GCDWebServer*)server {
    [self webServerShowAlert:server];
}

- (void)webServerShowAlert:(GCDWebServer*)server {
    // dont bring up this WebServer alert multiple times, for example the server will stop and restart when app goes into background.
    static BOOL g_web_server_alert = FALSE;
    
    if (g_web_server_alert)
        return;
    
    NSMutableString *servers = [[NSMutableString alloc] init];

    if ( server.serverURL != nil ) {
        [servers appendString:[NSString stringWithFormat:@"%@",server.serverURL]];
    }
    if ( servers.length > 0 ) {
        [servers appendString:@"\n\n"];
    }
    if ( server.bonjourServerURL != nil ) {
        [servers appendString:[NSString stringWithFormat:@"%@",server.bonjourServerURL]];
    }
    NSString* welcome = @"Welcome to " PRODUCT_NAME_LONG;
    NSString* message = [NSString stringWithFormat:@"\nTo transfer ROMs from your computer go to one of these addresses in your web browser:\n\n%@",servers];
    NSString* title = g_no_roms_found ? welcome : @"Web Server Started";
    NSString* done  = g_no_roms_found ? @"Reload ROMs" : @"Stop Server";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:done style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        g_web_server_alert = FALSE;
        [[WebServer sharedInstance] webUploader].delegate = nil;
        [[WebServer sharedInstance] stopUploader];
        if (!myosd_inGame)
            myosd_exitGame = 1;     /* exit mame menu and re-scan ROMs*/
    }]];
    alert.preferredAction = alert.actions.lastObject;
    g_web_server_alert = TRUE;
    [self.topViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark play GAME

// this is called a few ways
//    -- after the user has selected a game in the ChooseGame UI
//    -- if a NSUserActivity is restored
//    -- if a mame4ios: URL is opened.
//    -- called from moveROMs (with nil) to reload the gameList.
//
// NOTE we cant run a game in all situations, for example if the user is deep
// into the Settings dialog, we just give up, to complex to try to back out.
//
-(void)playGame:(NSDictionary*)game {
    NSLog(@"PLAY: %@", game);
    
    // if we are not presenting anything, we can just "run" the game
    // else we need to dismiss what is active and try again...
    //
    // we can be in the following states
    // 1. alert is up...
    //      pause
    //      exit
    //      menu
    //      server
    //      other/error
    //
    //      if the alert has a cancel button (or single default) dismiss and then run game....
    //
    // 2. settings view controller is active
    //      just fail in this case.
    //
    // 3. choose game controller is active.
    //      dissmiss and run game.
    //
    UIViewController* viewController = self.presentedViewController;
    if ([viewController isKindOfClass:[UINavigationController class]])
        viewController = [(UINavigationController*)viewController topViewController];
    
    if ([viewController isKindOfClass:[UIAlertController class]]) {
        UIAlertController* alert = (UIAlertController*)viewController;
        UIAlertAction* action;

        NSLog(@"ALERT: %@:%@", alert.title, alert.message);
        
        if (alert.actions.count == 1)
            action = alert.preferredAction ?: alert.cancelAction;
        else
            action = alert.cancelAction;
        
        if (action != nil) {
            [alert dismissWithAction:action completion:^{
                [self performSelectorOnMainThread:@selector(playGame:) withObject:game waitUntilDone:NO];
            }];
            return;
        }
        else {
            NSLog(@"CANT RUN GAME! (alert does not have a default or cancel button)");
            return;
        }
    }
    else if ([viewController isKindOfClass:[ChooseGameController class]] && viewController.presentedViewController == nil) {
        // if we are in the ChooseGame UI dismiss and run game
        ChooseGameController* choose = (ChooseGameController*)viewController;
        if (choose.selectGameCallback != nil)
            choose.selectGameCallback(game);
        return;
    }
    else if (viewController != nil) {
        NSLog(@"CANT RUN GAME! (%@ is active)", viewController);
        return;
    }

    
    NSString* name = game[kGameInfoName];
    
    if ([name isEqualToString:kGameInfoNameMameMenu])
        name = @" ";

    if (name != nil) {
        g_mame_game_info = game;
        strncpy(g_mame_game, [name cStringUsingEncoding:NSUTF8StringEncoding], sizeof(g_mame_game));
        [self updateUserActivity:game];
    }
    else {
        g_mame_game_info = nil;
        g_mame_game[0] = 0;     // run the MENU
    }

    g_emulation_paused = 0;
    change_pause(g_emulation_paused);
    myosd_exitGame = 1; // exit menu mode and start game or menu.
}

#pragma mark choose game UI

-(void)chooseGame:(NSArray*)games {
    // a Alert or Setting is up, bail
    if (self.presentedViewController != nil) {
        NSLog(@"CANT SHOW CHOOSE GAME UI: %@", self.presentedViewController);
        if (self.presentedViewController.beingDismissed) {
            NSLog(@"....TRY AGAIN");
            [self performSelector:_cmd withObject:games afterDelay:1.0];
        }
        return;
    }
    g_no_roms_found = [games count] == 0;
    if (g_no_roms_found) {
        NSLog(@"NO GAMES, ASK USER WHAT TO DO....");

        NSString* title = @"Welcome to " PRODUCT_NAME_LONG;
        NSString* message = @"\nTo transfer ROMs from your computer, Start Server, Import ROMs, or use AirDrop.";
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Start Server" style:UIAlertActionStyleDefault image:[UIImage systemImageNamed:@"arrow.up.arrow.down.circle"] handler:^(UIAlertAction * _Nonnull action) {
            [self runServer];
        }]];
#if TARGET_OS_IOS
        [alert addAction:[UIAlertAction actionWithTitle:@"Import ROMs" style:UIAlertActionStyleDefault image:[UIImage systemImageNamed:@"square.and.arrow.down"] handler:^(UIAlertAction * _Nonnull action) {
            [self runImport];
        }]];
#endif
        [alert addAction:[UIAlertAction actionWithTitle:@"Reload ROMs" style:UIAlertActionStyleCancel image:[UIImage systemImageNamed:@"arrow.2.circlepath.circle"] handler:^(UIAlertAction * _Nonnull action) {
            myosd_exitGame = 1;     /* exit mame menu and re-scan ROMs*/
        }]];
        [self.topViewController presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (g_mame_game_error[0] != 0) {
        NSLog(@"ERROR RUNNING GAME %s", g_mame_game_error);
        
        NSString* msg = [NSString stringWithFormat:@"ERROR RUNNING GAME %s", g_mame_game_error];
        g_mame_game_error[0] = 0;
        g_mame_game[0] = 0;
        g_mame_game_info = nil;
        
        [self showAlertWithTitle:@PRODUCT_NAME message:msg buttons:@[@"Ok"] handler:^(NSUInteger button) {
            [self performSelectorOnMainThread:@selector(chooseGame:) withObject:games waitUntilDone:FALSE];
        }];
        return;
    }
    if (g_mame_game[0] == ' ') {
        NSLog(@"RUNNING MAME MENU, DONT BRING UP UI.");
        return;
    }
    if (g_mame_game[0] != 0) {
        NSLog(@"RUNNING %s, DONT BRING UP UI.", g_mame_game);
        return;
    }
    
    // now that we have passed the startup phase, check on and maybe re-enable bluetooth.
    if (@available(iOS 13.1, tvOS 13.0, *)) {
        if (!g_bluetooth_enabled && CBCentralManager.authorization == CBManagerAuthorizationNotDetermined) {
            g_bluetooth_enabled = TRUE;
            [self performSelectorOnMainThread:@selector(scanForDevices) withObject:nil waitUntilDone:NO];
        }
    }

    NSLog(@"GAMES: %@", games);

    ChooseGameController* choose = [[ChooseGameController alloc] init];
    [choose setGameList:games];
    choose.backgroundImage = [self loadTileImage:@"ui-background.png"];
    g_emulation_paused = 1;
    change_pause(g_emulation_paused);
    choose.selectGameCallback = ^(NSDictionary* game) {
        if ([game[kGameInfoName] isEqualToString:kGameInfoNameSettings]) {
            [self runSettings];
            return;
        }
        [self dismissViewControllerAnimated:YES completion:^{
            self->icadeView.active = TRUE;
            [self performSelectorOnMainThread:@selector(playGame:) withObject:game waitUntilDone:FALSE];
        }];
    };
    UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:choose];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        nav.modalInPresentation = YES;    // disable iOS 13 swipe to dismiss...
    }
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark UIEvent handling for button presses

#if TARGET_OS_TV
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event; {
    // in the simulator we may not have any controllers
    if (controllers.count == 0) {
        for (UIPress *press in presses) {
            if (press.type == UIPressTypeMenu) {
                return [self runMenu];
            }
        }
    }
    // not a menu press, delegate to UIKit responder handling
    [super pressesBegan:presses withEvent:event];
}
#endif

#pragma mark NSUserActivty

-(void)updateUserActivity:(NSDictionary*)game
{
#if TARGET_OS_IOS
    self.userActivity = [ChooseGameController userActivityForGame:game];
#endif
}

@end
