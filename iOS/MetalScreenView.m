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
#import <Metal/Metal.h>
#import "MetalScreenView.h"
#import "myosd.h"
#import "ColorSpace.h"

#define DebugLog 0
#if DebugLog == 0
#define NSLog(...) (void)0
#endif

#pragma mark - TIMERS

//#define WANT_TIMERS
#import "Timer.h"

TIMER_INIT_BEGIN
TIMER_INIT(draw_screen)
TIMER_INIT(texture_load)
TIMER_INIT(texture_load_pal16)
TIMER_INIT(texture_load_rgb32)
TIMER_INIT(texture_load_rgb15)
TIMER_INIT(line_prim)
TIMER_INIT(quad_prim)
TIMER_INIT_END

#pragma mark - MetalScreenView

@implementation MetalScreenView {
    NSDictionary* _options;
    MTLSamplerMinMagFilter _filter;
    
    Shader _screen_shader;
    CGColorSpaceRef _screenColorSpace;  // color space used to render MAME screen
    
    Shader _line_shader;
    CGFloat _line_width_scale;
    NSString* _line_width_scale_variable;
    BOOL _line_shader_wants_past_lines;
    
    NSTimeInterval _drawScreenStart;

    #define LINE_BUFFER_SIZE (8*1024)
    #define LINE_MAX_FADE_TIME 1.0
    myosd_render_primitive* _line_buffer;
    int _line_buffer_base;
    int _line_buffer_count;
}

#pragma mark - SCREEN SHADER and LINE SHADER Options

// SCREEN SHADER
//
// Metal shader string is of the form:
//        <Friendly Name> : <shader description>
//
// NOTE: see MetalView.h for what a <shader description> is.
// in addition to the <shader description> in MetalView.h you can specify a named variable like so....
//
//       variable_name = <default value> <min value> <max value> <step value>
//
//  you dont use commas to separate values, use spaces.
//  min, max, and step are all optional, and only effect the InfoHUD, MetalView ignores them.
//
//  the following variables are pre-defined by MetalView and MetalScreenView
//
//      frame-count             - current frame number, this will reset to zero from time to time (like on resize)
//      render-target-size      - size of the render target (in pixels)
//      mame-screen-dst-rect    - the size (in pixels) of the output quad
//      mame-screen-src-rect    - the size (in pixels) of the input SCREEN texture
//      mame-screen-size        - the size (in pixels) of the input SCREEN texture
//      mame-screen-matrix      - matrix to convert texture coordinates (u,v) to crt (x,scanline)
//
//  Presets are simply the @string without the key names, only numbers!
//
+ (NSArray*)screenShaderList {
    return @[kScreenViewShaderDefault, kScreenViewShaderNone,
             @"simpleTron: simpleCRT, mame-screen-dst-rect, mame-screen-src-rect,\
                            Vertical Curvature = 5.0 1.0 10.0 0.1,\
                            Horizontal Curvature = 4.0 1.0 10.0 0.1,\
                            Curvature Strength = 0.25 0.0 1.0 0.05,\
                            Light Boost = 1.3 0.1 3.0 0.1, \
                            Vignette Strength = 0.05 0.0 1.0 0.05,\
                            Zoom Factor = 1.0 0.01 5.0 0.1",
             @"megaTron : megaTron, mame-screen-src-rect, mame-screen-dst-rect,\
                            Shadow Mask Type = 3.0 0.0 3.0 1.0,\
                            Shadow Mask Intensity = 0.5 0.0 1.0 0.05,\
                            Scanline Thinness = 0.7 0.0 1.0 0.05,\
                            Horizontal Scanline Blur = 1.8 1.0 10.0 0.05,\
                            CRT Curvature = 0.02 0.0 0.25 0.01,\
                            Use Trinitron-style Curvature = 0.0 0.0 1.0 1.0,\
                            CRT Corner Roundness = 3.0 2.0 11.0 1.0,\
                            CRT Gamma = 2.9 0.0 5.0 0.1",
             @"megaTron - Shadow Mask Strong: megaTron, mame-screen-src-rect, mame-screen-dst-rect,3.0,0.75,0.6,1.4,0.02,1.0,2.0,3.0",
             @"megaTron - Vertical Games (Use Linear Filter): megaTron, mame-screen-src-rect, mame-screen-dst-rect,3.0,0.4,0.8,3.0,0.02,0.0,3.0,2.9",
             @"megaTron - Grille Mask: megaTron, mame-screen-src-rect, mame-screen-dst-rect,2.0,0.85,0.6,2.0,0.02,1.0,2.0,3.0",
             @"megaTron - Grille Mask Lite: megaTron, mame-screen-src-rect, mame-screen-dst-rect,1.0,0.6,0.6,1.6,0.02,1.0,2.0,2.8",
             @"megaTron - No Shadow Mask but Blurred: megaTron, mame-screen-src-rect, mame-screen-dst-rect,0.0,0.6,0.6,1.0,0.02,0.0,2.0,2.6",
             
             @"ulTron : ultron,\
                        mame-screen-src-rect,\
                        mame-screen-dst-rect,\
                        Scanline Sharpness = -6.0 -20.0 0.0 1.0,\
                        Pixel Sharpness = -3.0 -20.0 0.0 1.0,\
                        Horizontal Curve = 0.031 0.0 0.125 0.01,\
                        Vertical Curve = 0.041 0.0 0.125 0.01,\
                        Dark Shadow Mask Strength = 0.5 0.0 2.0 0.1,\
                        Bright Shadow Mask Strength = 1.0 0.0 2.0 0.1,\
                        Shadow Mask Type = 3.0 0.0 4.0 1.0,\
                        Overal Brightness Boost = 1.0 0.0 2.0 0.05,\
                        Horizontal Phosphor Glow Softness = -1.5 -2.0 -0.5 0.1,\
                        Vertical Phosphor Glow Softness = -2.0 -4.0 -1.0 0.1,\
                        Glow Amount = 0.15 0.0 1.0 0.05,\
                        Phosphor Focus = 1.75 0.0 10.0 0.05",
             
#ifdef DEBUG
             @"Wombat1: mame_screen_test, mame-screen-size, frame-count, 1.0, 8.0, 8.0",
             @"Wombat2: mame_screen_test, mame-screen-size, frame-count, wombat_rate=2.0, wombat_u=16.0, wombat_v=16.0",
             @"Test (dot): mame_screen_dot, mame-screen-matrix",
             @"Test (scanline): mame_screen_line, mame-screen-matrix",
             @"Test (rainbow): mame_screen_rainbow, mame-screen-matrix, frame-count, rainbow_h = 16.0 4.0 32.0 1.0, rainbow_speed = 1.0 1.0 16.0",
             @"Test (color): texture, blend=copy, color-test-pattern=1 0 1 1",
#endif
    ];
}

// LINE SHADER - a line shader is exactly like a screen shader.
//
// **EXCEPT** the first parameter of a line-shader is assumed to be the `line-width-scale`
//
// all line widths will be multiplied by `line-width-scale` before being converted to triangles
//
// when the line fragment shader is called, the following is set:
//
//      color.rgb is the line color
//      color.a is itterated from 1.0 on center line to 0.25 on the line edge.
//      texture.x is itterated along the length of the line 0 ... length (the length is in model cordinates)
//      texture.y is itterated along the width of the line, -1 .. +1, with 0 being the center line
//
//  the default line shader just uses the passed color and a blend mode of ADD.
//  so the default line shader depends on the color.a being ramped down to 0.25x and color.rgb being the line color.
//
//  PAST LINES
//
//  if a line shader specifies `line-time` as a parameter value, we will re-draw a buffer of past lines every frame.
//
//      `line-time` == 0.0  - lines for the current frame
//      `line-time` > 0.0   - lines for past frames (line-time is the number of seconds in the past)
//
+ (NSArray*)lineShaderList {
    return @[kScreenViewShaderDefault, kScreenViewShaderNone,
        @"lineTron: lineTron, blend=alpha, fade-width-scale=1.2 0.1 8, line-time, fade-falloff=3 1 8, fade-strength = 0.2 0.1 3.0 0.1",

#ifdef DEBUG
        @"Dash: mame_test_vector_dash, blend=add, width-scale=1.0 0.25 6.0, frame-count, length=25.0, speed=16.0",
        @"Dash (Fast): mame_test_vector_dash, blend=add, 1.0, frame-count, 15.0, 16.0",
        @"Dash (Slow): mame_test_vector_dash, blend=add, 1.0, frame-count, 15.0, 2.0",
                 
        @"Pulse: mame_test_vector_pulse, blend=add, width-scale=1.0 0.25 6.0, frame-count, rate=2.0",
        @"Pulse (Fast): mame_test_vector_pulse, blend=add, 1.0, frame-count, 0.5",
        @"Pulse (Slow): mame_test_vector_pulse, blend=add, 1.0, frame-count, 2.0",

        @"Fade (Alpha): mame_test_vector_fade, blend=alpha, fade-width-scale=1.2 1 8, line-time, fade-falloff=2 1 4, fade-strength = 0.5 0.1 3.0 0.1",
        @"Fade (Add):   mame_test_vector_fade, blend=add,   fade-width-scale=1.2 1 8, line-time, fade-falloff=2 1 4, fade-strength = 0.5 0.1 3.0 0.1",
#endif
    ];
}
+ (NSArray*)filterList {
    return @[kScreenViewFilterLinear, kScreenViewFilterNearest];
}

//
// COLOR SPACE
//
// color space data, we define the colorSpaces here, in one place, so it stays in-sync with the UI.
//
// you can specify a colorSpace in two ways, with a system name or with parameters.
// these strings are of the form <Friendly Name> : <colorSpace name OR colorSpace parameters>
//
// colorSpace name is one of the sytem contants passed to `CGColorSpaceCreateWithName`
// see (Color Space Names)[https://developer.apple.com/documentation/coregraphics/cgcolorspace/color_space_names]
//
// colorSpace parameters are 3 - 18 floating point numbers separated with commas.
// see [CGColorSpaceCreateCalibratedRGB](https://developer.apple.com/documentation/coregraphics/1408861-cgcolorspacecreatecalibratedrgb)
//
// if <colorSpace name OR colorSpace parameters> is blank or not valid, a device-dependent RGB color space is used.
//
+ (NSArray*)colorSpaceList {

    return @[kScreenViewColorSpaceDefault,
             @"sRGB : kCGColorSpaceSRGB",
             @"CRT (sRGB, D65, 2.5) :    0.95047,1.0,1.08883, 0,0,0, 2.5,2.5,2.5, 0.412456,0.212673,0.019334,0.357576,0.715152,0.119192,0.180437,0.072175,0.950304",
             @"Rec709 (sRGB, D65, 2.4) : 0.95047,1.0,1.08883, 0,0,0, 2.4,2.4,2.4, 0.412456,0.212673,0.019334,0.357576,0.715152,0.119192,0.180437,0.072175,0.950304",
#ifdef DEBUG
             @"Adobe RGB : kCGColorSpaceAdobeRGB1998",
             @"Linear sRGB : kCGColorSpaceLinearSRGB",
             @"NTSC Luminance : 0.9504,1.0000,1.0888, 0,0,0, 1,1,1, 0.299,0.299,0.299, 0.587,0.587,0.587, 0.114,0.114,0.114",
#endif
    ];
}

#pragma mark - MetalScreenView INIT

// split and trim a string
// TODO: move this to a common place??
static NSMutableArray* split(NSString* str, NSString* sep) {
    NSMutableArray* arr = [[str componentsSeparatedByString:sep] mutableCopy];
    for (int i=0; i<arr.count; i++)
        arr[i] = [arr[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return arr;
}

- (void)setOptions:(NSDictionary *)options {
    _options = options;
    
    // set our framerate
    self.preferredFramesPerSecond = 60;
    
    // set a custom color space
    NSString* color_space = _options[kScreenViewColorSpace];

    if (color_space != nil && color_space.length != 0 && ![color_space isEqualToString:kScreenViewColorSpaceDefault])
        _screenColorSpace = ColorSpaceFromString(color_space);
    else
        _screenColorSpace = NULL;
    
    // enable filtering (default to Linear)
    NSString* filter_string = _options[kScreenViewFilter];

    if ([filter_string isEqualToString:kScreenViewFilterNearest])
        _filter = MTLSamplerMinMagFilterNearest;
    else
        _filter = MTLSamplerMinMagFilterLinear;

    // get the shader to use when drawing the SCREEN, default to the 3 entry in the list (simpleTron).
    NSString* screen_shader = _options[kScreenViewScreenShader] ?: kScreenViewShaderDefault;

    assert([MetalScreenView.screenShaderList[0] isEqualToString:kScreenViewShaderDefault]);
    assert([MetalScreenView.screenShaderList[1] isEqualToString:kScreenViewShaderNone]);
    assert(MetalScreenView.screenShaderList.count > 2);
    if ([screen_shader length] == 0 || [screen_shader isEqualToString:kScreenViewShaderDefault])
        screen_shader = split(MetalScreenView.screenShaderList[2], @":").lastObject;

    if ([screen_shader isEqualToString:kScreenViewShaderNone])
        screen_shader = ShaderTexture;
    
    _screen_shader = screen_shader;

    // get the shader to use when drawing VECTOR lines, default to lineTron
    NSString* line_shader = _options[kScreenViewLineShader] ?: kScreenViewShaderDefault;
    
    assert([MetalScreenView.lineShaderList[0] isEqualToString:kScreenViewShaderDefault]);
    assert([MetalScreenView.lineShaderList[1] isEqualToString:kScreenViewShaderNone]);
    assert(MetalScreenView.lineShaderList.count > 2);
    if ([line_shader length] == 0 || [line_shader isEqualToString:kScreenViewShaderDefault])
        line_shader = split(MetalScreenView.lineShaderList[2], @":").lastObject;

    if ([line_shader isEqualToString:kScreenViewShaderNone])
        line_shader = nil;
    
    _line_shader = line_shader;
    
    // see if the line shader wants past lines, ie does it list `line-time` in the parameter list.x
    _line_shader_wants_past_lines = [_line_shader rangeOfString:@"line-time"].length != 0;
    
    if (_line_shader_wants_past_lines)
        [self setShaderVariables:@{@"line-time": @(0.0)}];

    // parse the first param of the line shader to get the line width scale factor.
    // NOTE the first param can be a variable or a constant, support variables for the HUD.
    _line_width_scale = 1.0;
    _line_width_scale_variable = nil;
    NSArray* arr = split(_line_shader, @",");
    NSUInteger idx = 1; // skip first component that is the shader name.
    if (idx < arr.count && [arr[idx] hasPrefix:@"blend="])
        idx++;
    if (idx < arr.count && [arr[idx] floatValue] != 0.0)
        _line_width_scale = [arr[idx] floatValue];
    else if (idx < arr.count)
        _line_width_scale_variable = split(arr[idx],@"=").firstObject;
    
    NSLog(@"FILTER: %@", _filter == MTLSamplerMinMagFilterNearest ? @"NEAREST" : @"LINEAR");
    NSLog(@"SCREEN SHADER: %@", split(_screen_shader, @",").firstObject);
    NSLog(@"SCREEN COLORSPACE: %@", _screenColorSpace);
    NSLog(@"LINE SHADER: %@", split(_line_shader, @",").firstObject);
    NSLog(@"LINE SHADER WANTS PAST LINES: %@", _line_shader_wants_past_lines ? @"YES" : @"NO");
    if (_line_width_scale_variable != nil)
        NSLog(@"    width-scale: %@", _line_width_scale_variable);
    else
        NSLog(@"    width-scale: %0.3f", _line_width_scale);

    [self setNeedsLayout];
}

- (void)dealloc {
    if (_line_buffer != NULL)
        free(_line_buffer);
}

#pragma mark - LINE BUFFER

- (void)saveLine:(myosd_render_primitive*) line {
    assert(line->type == RENDER_PRIMITIVE_LINE);
    
    if (_line_buffer == NULL)
        _line_buffer = malloc(LINE_BUFFER_SIZE * sizeof(_line_buffer[0]));

    int i = (_line_buffer_base + _line_buffer_count + 1) % LINE_BUFFER_SIZE;
    
    _line_buffer[i] = *line;
    _line_buffer[i].texcoords[0].u = _drawScreenStart;

    if (_line_buffer_count < LINE_BUFFER_SIZE)
        _line_buffer_count++;
    else
        _line_buffer_base = (_line_buffer_base + 1) % LINE_BUFFER_SIZE;
}

- (void)drawPastLines {
    CGFloat line_time = CGFLOAT_MAX;
    
    for (int i=0; i<_line_buffer_count; i++) {
        myosd_render_primitive* prim = _line_buffer + (_line_buffer_base + i) % LINE_BUFFER_SIZE;
        
        // calculate how far back in time this line is....
        NSTimeInterval t = _drawScreenStart - prim->texcoords[0].u;

        // ignore lines from the future, or too far in the past
        if (t <= 0.0 || t > LINE_MAX_FADE_TIME)
            continue;
        
        if (line_time != t) {
            line_time = t;
            [self setShaderVariables:@{@"line-time": @(line_time)}];
        }
        
        VertexColor color = VertexColor(prim->color_r, prim->color_g, prim->color_b, prim->color_a);
        color = color * simd_make_float4(color.a, color.a, color.a, 1/color.a);     // pre-multiply alpha
        
        [self drawLine:CGPointMake(prim->bounds_x0, prim->bounds_y0) to:CGPointMake(prim->bounds_x1, prim->bounds_y1) width:(prim->width * _line_width_scale) color:color];
    }
}

#pragma mark - texture conversion

static void load_texture_prim(id<MTLTexture> texture, myosd_render_primitive* prim) {
    
    NSUInteger width = texture.width;
    NSUInteger height = texture.height;
    
    assert(texture.pixelFormat == MTLPixelFormatBGRA8Unorm);
    assert(texture.width == prim->texture_width);
    assert(texture.height == prim->texture_height);

    static char* texture_format_name[] = {"UNDEFINED", "PAL16", "PALA16", "555", "RGB", "ARGB", "YUV16"};
    texture.label = [NSString stringWithFormat:@"MAME %08lX:%d %dx%d %s", (NSUInteger)prim->texture_base, prim->texture_seqid, prim->texture_width, prim->texture_height, texture_format_name[prim->texformat]];

    TIMER_START(texture_load);

    switch (prim->texformat) {
        case TEXFORMAT_RGB15:
        {
            // map 0-31 -> 0-255
            static uint32_t pal_ident[32] = {0,8,16,24,32,41,49,57,65,74,82,90,98,106,115,123,131,139,148,156,164,172,180,189,197,205,213,222,230,238,246,255};
            TIMER_START(texture_load_rgb15);
            uint16_t* src = prim->texture_base;
            uint32_t* dst = (uint32_t*)myosd_screen;
            const uint32_t* pal = prim->texture_palette ?: pal_ident;
            for (NSUInteger y=0; y<height; y++) {
                for (NSUInteger x=0; x<width; x++) {
                    uint16_t u16 = *src++;
                    *dst++ = (pal[(u16 >>  0) & 0x1F] >>  0) |
                             (pal[(u16 >>  5) & 0x1F] <<  8) |
                             (pal[(u16 >> 10) & 0x1F] << 16) |
                             0xFF000000;
                }
                src += prim->texture_rowpixels - width;
            }
            TIMER_STOP(texture_load_rgb15);
            [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:myosd_screen bytesPerRow:width*4];
            break;
        }
        case TEXFORMAT_RGB32:
        case TEXFORMAT_ARGB32:
        {
            TIMER_START(texture_load_rgb32);
            if (prim->texture_palette == NULL) {
                [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:prim->texture_base bytesPerRow:prim->texture_rowpixels*4];
            }
            else {
                uint32_t* src = prim->texture_base;
                uint32_t* dst = (uint32_t*)myosd_screen;
                const uint32_t* pal = prim->texture_palette;
                for (NSUInteger y=0; y<height; y++) {
                    for (NSUInteger x=0; x<width; x++) {
                        uint32_t rgba = *src++;
                        *dst++ = (pal[(rgba >>  0) & 0xFF] <<  0) |
                                 (pal[(rgba >>  8) & 0xFF] <<  8) |
                                 (pal[(rgba >> 16) & 0xFF] << 16) |
                                 (pal[(rgba >> 24) & 0xFF] << 24) ;
                    }
                    src += prim->texture_rowpixels - width;
                }
                [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:myosd_screen bytesPerRow:width*4];
            }
            TIMER_STOP(texture_load_rgb32);
            break;
        }
        case TEXFORMAT_PALETTE16:
        case TEXFORMAT_PALETTEA16:
        {
            TIMER_START(texture_load_pal16);
            uint16_t* src = prim->texture_base;
            uint32_t* dst = (uint32_t*)myosd_screen;
            const uint32_t* pal = prim->texture_palette;
            for (NSUInteger y=0; y<height; y++) {
                NSUInteger dx = width;
                if ((intptr_t)dst % 8 == 0) {
                    while (dx >= 4) {
                        uint64_t u64 = *(uint64_t*)src;
                        ((uint64_t*)dst)[0] = ((uint64_t)pal[(u64 >>  0) & 0xFFFF]) | (((uint64_t)pal[(u64 >> 16) & 0xFFFF]) << 32);
                        ((uint64_t*)dst)[1] = ((uint64_t)pal[(u64 >> 32) & 0xFFFF]) | (((uint64_t)pal[(u64 >> 48) & 0xFFFF]) << 32);
                        dst += 4; src += 4; dx -= 4;
                    }
                    if (dx >= 2) {
                        uint32_t u32 = *(uint32_t*)src;
                        ((uint64_t*)dst)[0] = ((uint64_t)pal[(u32 >>  0) & 0xFFFF]) | (((uint64_t)pal[(u32 >> 16) & 0xFFFF]) << 32);
                        dst += 2; src += 2; dx -= 2;
                    }
                }
                while (dx-- > 0)
                    *dst++ = pal[*src++];
                src += prim->texture_rowpixels - width;
            }
            TIMER_STOP(texture_load_pal16);
            [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:myosd_screen bytesPerRow:width*4];
            break;
        }
        case TEXFORMAT_YUY16:
        {
            // this texture format is only used for AVI files and LaserDisc player!
            assert(FALSE);
            break;
        }
        default:
            assert(FALSE);
            break;
    }
    TIMER_STOP(texture_load);
}

#pragma mark - draw MAME primitives

// return 1 if you handled the draw, 0 for a software render
// NOTE this is called on MAME background thread, dont do anything stupid.
- (int)drawScreen:(void*)prim_list {
    static Shader shader_map[] = {ShaderNone, ShaderAlpha, ShaderMultiply, ShaderAdd};
    static Shader shader_tex_map[]  = {ShaderTexture, ShaderTextureAlpha, ShaderTextureMultiply, ShaderTextureAdd};

#ifdef DEBUG
    [self drawScreenDebug:prim_list];
#endif
    
    if (![self drawBegin]) {
        NSLog(@"drawBegin *FAIL* dropping frame on the floor.");
        return 1;
    }
    _drawScreenStart = CACurrentMediaTime();
    TIMER_START(draw_screen);

    NSUInteger num_screens = 0;
    
    [self setViewRect:CGRectMake(0, 0, myosd_video_width, myosd_video_height)];
    
    CGFloat scale_x = self.drawableSize.width  / myosd_video_width;
    CGFloat scale_y = self.drawableSize.height / myosd_video_height;
    CGFloat scale   = MIN(scale_x, scale_y);
    
    // get the line width scale for this frame, if it is variable.
    if (_line_width_scale_variable != nil) {
        NSValue* val = [self getShaderVariables][_line_width_scale_variable];
        if (val != nil && [val isKindOfClass:[NSNumber class]])
            _line_width_scale = [(NSNumber*)val floatValue];
    }
    
    BOOL first_line = TRUE;
    
    // walk the primitive list and render
    for (myosd_render_primitive* prim = prim_list; prim != NULL; prim = prim->next) {
        
        if (prim->type == RENDER_PRIMITIVE_QUAD)
            TIMER_START(quad_prim);
        else
            TIMER_START(line_prim);

        VertexColor color = VertexColor(prim->color_r, prim->color_g, prim->color_b, prim->color_a);
        
        CGRect rect = CGRectMake(floor(prim->bounds_x0 + 0.5),  floor(prim->bounds_y0 + 0.5),
                                 floor(prim->bounds_x1 + 0.5) - floor(prim->bounds_x0 + 0.5),
                                 floor(prim->bounds_y1 + 0.5) - floor(prim->bounds_y0 + 0.5));

        if (prim->type == RENDER_PRIMITIVE_QUAD && prim->texture_base != NULL) {
            
            // set the texture
            [self setTexture:0 texture:prim->texture_base hash:prim->texture_seqid
                       width:prim->texture_width height:prim->texture_height
                      format:MTLPixelFormatBGRA8Unorm
                  colorspace:(prim->screentex ? _screenColorSpace : NULL)
                texture_load:^(id<MTLTexture> texture) {load_texture_prim(texture, prim);} ];

            // set the shader
            if (prim->screentex) {
                // render of the game screen, use a custom shader
                // set the following shader variables so the shader knows the pixel size of a scanline etc....
                //
                //      mame-screen-dst-rect - the size (in pixels) of the output quad
                //      mame-screen-src-rect - the size (in pixels) of the input texture
                //      mame-screen-size     - the size (in pixels) of the input texture
                //      mame-screen-matrix   - matrix to convert texture coordinates (u,v) to crt (x,scanline)
                //
                CGSize src_size = CGSizeMake((prim->texorient & ORIENTATION_SWAP_XY) ? prim->texture_height : prim->texture_width,
                                             (prim->texorient & ORIENTATION_SWAP_XY) ? prim->texture_width : prim->texture_height);
                
                CGRect src_rect = CGRectMake(0, 0, src_size.width, src_size.height);
                CGRect dst_rect = CGRectMake(rect.origin.x * scale_x, rect.origin.y * scale_y, rect.size.width * scale_x, rect.size.height * scale_y);
                
                // create a matrix to convert texture coordinates (u,v) to crt scanlines (x,y)
                simd_float2x2 mame_screen_matrix;
                if (prim->texorient & ORIENTATION_SWAP_XY)
                    mame_screen_matrix = (matrix_float2x2){{ {0,prim->texture_width}, {prim->texture_height,0} }};
                else
                    mame_screen_matrix = (matrix_float2x2){{ {prim->texture_width,0}, {0,prim->texture_height} }};
                
                [self setShaderVariables:@{
                    @"mame-screen-dst-rect" :@(dst_rect),
                    @"mame-screen-src-rect" :@(src_rect),
                    @"mame-screen-size"     :@(src_size),
                    @"mame-screen-matrix"   :[NSValue value:&mame_screen_matrix withObjCType:@encode(float[2][2])],
                }];
                [self setTextureFilter:_filter];
                [self setShader:_screen_shader];
                num_screens++;
            }
            else {
                // render of artwork (or mame text). use normal shader with no filtering
                [self setTextureFilter:MTLSamplerMinMagFilterNearest];
                [self setShader:shader_tex_map[prim->blendmode]];
            }
            
            // set the address mode.
            if (prim->texwrap)
                [self setTextureAddressMode:MTLSamplerAddressModeRepeat];
            else
                [self setTextureAddressMode:MTLSamplerAddressModeClampToZero];

            // draw a quad in the correct orientation
            UIImageOrientation orientation = UIImageOrientationUp;
            if (prim->texorient == ORIENTATION_ROT90)
                orientation = UIImageOrientationRight;
            else if (prim->texorient == ORIENTATION_ROT180)
                orientation = UIImageOrientationDown;
            else if (prim->texorient == ORIENTATION_ROT270)
                orientation = UIImageOrientationLeft;

            [self drawRect:rect color:color orientation:orientation];
        }
        else if (prim->type == RENDER_PRIMITIVE_QUAD) {
            // solid color quad. only ALPHA or NONE blend mode.
            
            if (prim->blendmode == BLENDMODE_ALPHA && prim->color_a != 1.0)
                [self setShader:ShaderAlpha];
            else
                [self setShader:ShaderNone];

            [self drawRect:rect color:color];
        }
        else if (prim->type == RENDER_PRIMITIVE_LINE && (prim->width * scale) <= 1.0) {
            // single pixel line.
            [self setShader:shader_map[prim->blendmode]];
            [self drawLine:CGPointMake(prim->bounds_x0, prim->bounds_y0) to:CGPointMake(prim->bounds_x1, prim->bounds_y1) color:color];
        }
        else if (prim->type == RENDER_PRIMITIVE_LINE) {
            // wide line, if the blendmode is ADD this is a VECTOR line, else a UI line.
            if (prim->blendmode == BLENDMODE_ADD && _line_shader != nil) {
                // this line is a vector line, use a special shader

                // pre-multiply color, so shader has non-iterated color
                color = color * simd_make_float4(color.a, color.a, color.a, 1/color.a);
                [self setShader:_line_shader];

                // handle lines from the past.
                if (_line_shader_wants_past_lines) {
                    // first time we see a line, draw all old lines, and set line-time=0.0
                    if (first_line) {
                        first_line = FALSE;
                        [self drawPastLines];
                        [self setShaderVariables:@{@"line-time": @(0.0)}];
                    }
                    [self saveLine:prim];

                    [self drawLine:CGPointMake(prim->bounds_x0, prim->bounds_y0) to:CGPointMake(prim->bounds_x1, prim->bounds_y1) width:prim->width color:color edgeAlpha:0.0];
                }
                else {
                    [self drawLine:CGPointMake(prim->bounds_x0, prim->bounds_y0) to:CGPointMake(prim->bounds_x1, prim->bounds_y1) width:(prim->width * _line_width_scale) color:color];
                }
            }
            else {
                // this line is from MAME UI, draw normal
                [self setShader:shader_map[prim->blendmode]];
                
                if (prim->blendmode == BLENDMODE_NONE)
                    [self drawLine:CGPointMake(prim->bounds_x0, prim->bounds_y0) to:CGPointMake(prim->bounds_x1, prim->bounds_y1) width:prim->width color:color];
                else
                    [self drawLine:CGPointMake(prim->bounds_x0, prim->bounds_y0) to:CGPointMake(prim->bounds_x1, prim->bounds_y1) width:prim->width color:color edgeAlpha:0.0];
            }
        }
        else {
            NSLog(@"Unknown RENDER_PRIMITIVE!");
            assert(FALSE);  // bad primitive
        }
        
        if (prim->type == RENDER_PRIMITIVE_QUAD)
            TIMER_STOP(quad_prim);
        else
            TIMER_STOP(line_prim);
    }
    
#ifdef DEBUG
    if ([_screen_shader containsString:@"color-test-pattern"] && [(id)self.getShaderVariables[@"color-test-pattern"] boolValue]) {
        [self drawTestPattern:CGRectMake(0, 0, myosd_video_width, myosd_video_height)];
    }
#endif
    
    [self drawEnd];
    TIMER_STOP(draw_screen);
    
    // set the number of SCREENs we rendered, so the app can detect RASTER vs VECTOR game.
    _numScreens = num_screens;

    // DUMP TIMERS....
    if (TIMER_COUNT(draw_screen) % 100 == 0) {
        TIMER_DUMP();
        TIMER_RESET();
    }
    
    // always return 1 saying we handled the draw.
    return 1;
}

#pragma mark - TEST PATTERN

#ifdef DEBUG
// DisplayP3 -> sRGB (ExtendedSRGB)
VertexColor VertexColorP3(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return ColorMatch(kCGColorSpaceExtendedSRGB, kCGColorSpaceDisplayP3, simd_make_float4(r, g, b, a));
}
-(void)drawTestPattern:(CGRect)rect {
    CGFloat width = rect.size.width;

    simd_float4 colors[] = {simd_make_float4(1, 0, 0, 1), simd_make_float4(0, 1, 0, 1), simd_make_float4(0, 0, 1, 1), simd_make_float4(1, 1, 0, 1), simd_make_float4(1, 1, 1, 1)};
    int n = sizeof(colors)/sizeof(colors[0]);
    
    CGFloat space_x = width / 32;
    CGFloat space_y = width / 32;
    CGFloat y = 0;
    CGFloat x = 0;
    CGFloat w = (width - (n-1) * space_x) / n;
    CGFloat h = w;

    // draw squares via polygons
    x = 0;
    y += space_y;
    [self setShader:ShaderCopy];
    for (int i=0; i<n; i++) {
        simd_float4 color = colors[i];
        simd_float4 colorP3 = VertexColorP3(color.r, color.g, color.b, color.a);
        [self drawRect:CGRectMake(x,y,w,h) color:color];
        [self drawRect:CGRectMake(x+w/3,y+h/3,w/3,h/3) color:colorP3];
        x += w + space_x;
    }
    y += h;
    
    // draw squares as P3 textures.
    x = 0;
    y += space_y;
    for (int i=0; i<sizeof(colors)/sizeof(colors[0]); i++) {
        simd_float4 color = colors[i];
        
        [self setShader:ShaderTextureAlpha];
        [self setTextureFilter:MTLSamplerMinMagFilterNearest];
        NSString* ident = [NSString stringWithFormat:@"TestP3%d", i];
        [self setTexture:0 texture:(void*)ident hash:0 width:3 height:3 format:MTLPixelFormatBGRA8Unorm colorspace:ColorSpaceWithName(kCGColorSpaceDisplayP3) texture_load:^(id<MTLTexture> texture) {
            
            simd_float4 c0 = ColorMatch(kCGColorSpaceDisplayP3, kCGColorSpaceDisplayP3,    color); // P3 -> P3 (should be a NOOP)
            simd_float4 c1 = ColorMatch(kCGColorSpaceDisplayP3, kCGColorSpaceExtendedSRGB, color); // sRGB -> P3
            
            uint32_t dw0 = 0xFF000000 |
                ((uint32_t)(c0.r * 255.0) << 16) |
                ((uint32_t)(c0.g * 255.0) << 8) |
                ((uint32_t)(c0.b * 255.0) << 0);

            uint32_t dw1 = 0xFF000000 |
                ((uint32_t)(c1.r * 255.0) << 16) |
                ((uint32_t)(c1.g * 255.0) << 8) |
                ((uint32_t)(c1.b * 255.0) << 0);

            uint32_t rgb[3*3];
            for (int i=0; i<3*3; i++)
                rgb[i] = i==4 ? dw0 : dw1;
            [texture replaceRegion:MTLRegionMake2D(0, 0, 3, 3) mipmapLevel:0 withBytes:rgb bytesPerRow:3*4];
            texture.label = @"TestP3";
        }];

        [self drawRect:CGRectMake(x,y,w,h) color:VertexColorP3(1, 1, 1, 1)];
        x += w + space_x;
    }
    y += h;

    // draw RGB gradients in SRGB and P3.
    h = width/16;
    w = width/2;
    x = 0;
    y += space_y;
    [self setShader:ShaderCopy];
    for (int i=0; i<sizeof(colors)/sizeof(colors[0]); i++) {
        simd_float4 color = colors[i];
        simd_float4 colorP3 = VertexColorP3(color.r, color.g, color.b, color.a);
        [self drawGradientRect:CGRectMake(x,y,w,h)   color:VertexColor(0, 0, 0, 1) color:color   orientation:UIImageOrientationRight];
        [self drawGradientRect:CGRectMake(x+w,y,w,h) color:VertexColor(0, 0, 0, 1) color:colorP3 orientation:UIImageOrientationLeft];
        y += h;
    }
}
#endif

#pragma mark - CODE COVERAGE and DEBUG stuff

#ifdef DEBUG
//
// CODE COVERAGE - this is where we track what types of primitives MAME has given us.
//                 run the app in the debugger, and if you stop in this function, you
//                 have seen a primitive or texture format that needs verified, verify
//                 that the game runs and looks right, then check off that things worked
//
// LINES
//      [X] width <= 1.0                MAME menu
//      [X] width  > 1.0                dkong artwork
//      [ ] antialias <= 1.0
//      [X] antialias  > 1.0            asteroid
//      [ ] blend mode NONE
//      [X] blend mode ALPHA            MAME menu
//      [ ] blend mode MULTIPLY
//      [X] blend mode ADD              asteroid
//
// QUADS
//      [X] blend mode NONE             MAME menu
//      [X] blend mode ALPHA            MAME menu
//      [X] blend mode MULTIPLY         N/A
//      [X] blend mode ADD              N/A
//
// TEXTURED QUADS
//      [X] blend mode NONE
//      [X] blend mode ALPHA            MAME menu (text)
//      [X] blend mode MULTIPLY         bzone
//      [X] blend mode ADD              dkong artwork
//      [X] rotate 0                    MAME menu (text)
//      [X] rotate 90                   pacman
//      [X] rotate 180                  mario, cocktail
//      [X] rotate 270                  mario, cocktail.
//      [X] texture WRAP                MAME menu
//      [X] texture CLAMP               MAME menu
//
// TEXTURE FORMATS
//      [X] PALETTE16                   pacman
//      [ ] PALETTEA16
//      [X] RGB15                       megaplay, streets of rage II
//      [X] RGB32                       neogeo
//      [X] ARGB32                      MAME menu (text)
//      [-] YUY16                       N/A
//      [X] RGB15 with PALETTE          megaplay
//      [X] RGB32 with PALETTE          neogeo
//      [-] ARGB32 with PALETTE         N/A
//      [-] YUY16 with PALETTE          N/A
//
- (void)drawScreenDebug:(void*)prim_list {
    
    for (myosd_render_primitive* prim = prim_list; prim != NULL; prim = prim->next) {
        
        assert(prim->type == RENDER_PRIMITIVE_LINE || prim->type == RENDER_PRIMITIVE_QUAD);
        assert(prim->blendmode <= BLENDMODE_ADD);
        assert(prim->texformat <= TEXFORMAT_YUY16);
        assert(prim->texture_base == NULL || prim->texformat != TEXFORMAT_UNDEFINED);
        assert(prim->unused == 0);

        float width = prim->width;
        int blend = prim->blendmode;
        int fmt = prim->texformat;
        int aa = prim->antialias;
        int orient = prim->texorient;
        int wrap = prim->texwrap;

        if (prim->type == RENDER_PRIMITIVE_LINE) {
            if (width <= 1.0 && !aa)
                assert(TRUE);
            if (width  > 1.0 && !aa)
                assert(TRUE);
            if (width <= 1.0 && aa)
                assert(FALSE);
            if (width  > 1.0 && aa)
                assert(TRUE);
            if (blend == BLENDMODE_NONE)
                assert(FALSE);
            if (blend == BLENDMODE_ALPHA)
                assert(TRUE);
            if (blend == BLENDMODE_RGB_MULTIPLY)
                assert(FALSE);
            if (blend == BLENDMODE_ADD)
                assert(TRUE);
        }
        else if (prim->type == RENDER_PRIMITIVE_QUAD && prim->texture_base == NULL) {
            if (blend == BLENDMODE_NONE)
                assert(TRUE);
            if (blend == BLENDMODE_ALPHA)
                assert(TRUE);
            if (blend == BLENDMODE_RGB_MULTIPLY)
                assert(TRUE);
            if (blend == BLENDMODE_ADD)
                assert(TRUE);
        }
        else if (prim->type == RENDER_PRIMITIVE_QUAD) {
            if (blend == BLENDMODE_NONE)
                assert(TRUE);
            if (blend == BLENDMODE_ALPHA)
                assert(TRUE);
            if (blend == BLENDMODE_RGB_MULTIPLY)
                assert(TRUE);
            if (blend == BLENDMODE_ADD)
                assert(TRUE);
            
            if (orient == ORIENTATION_ROT0)
                assert(TRUE);
            if (orient == ORIENTATION_ROT90)
                assert(TRUE);
            if (orient == ORIENTATION_ROT180)
                assert(TRUE);
            if (orient == ORIENTATION_ROT270)
                assert(TRUE);
            
            if (wrap == 0)
                assert(TRUE);
            if (wrap == 1)
                assert(TRUE);

            if (fmt == TEXFORMAT_RGB15 && prim->texture_palette == NULL)
                assert(TRUE);
            if (fmt == TEXFORMAT_RGB32 && prim->texture_palette == NULL)
                assert(TRUE);
            if (fmt == TEXFORMAT_ARGB32 && prim->texture_palette == NULL)
                assert(TRUE);
            if (fmt == TEXFORMAT_YUY16 && prim->texture_palette == NULL)
                assert(FALSE);

            if (fmt == TEXFORMAT_PALETTE16 && prim->texture_palette != NULL)
                assert(TRUE);
            if (fmt == TEXFORMAT_PALETTEA16 && prim->texture_palette != NULL)
                assert(FALSE);
            if (fmt == TEXFORMAT_RGB15 && prim->texture_palette != NULL)
                assert(TRUE);
            if (fmt == TEXFORMAT_RGB32 && prim->texture_palette != NULL)
                assert(TRUE);
            if (fmt == TEXFORMAT_ARGB32 && prim->texture_palette != NULL)
                assert(TRUE);
            if (fmt == TEXFORMAT_YUY16 && prim->texture_palette != NULL)
                assert(FALSE);
        }
    }
}
#endif

@end


