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

#import "ListOptionController.h"
#import "Options.h"
#if TARGET_OS_IOS
#import "OptionsController.h"
#elif TARGET_OS_TV
#import "TVOptionsController.h"
#endif

#define kTypeKeyValue    -1

@implementation ListOptionController {
    NSInteger type;
    NSString* key;  // for kTypeKeyValue
    NSArray<NSString*> *list;
    NSInteger value;
    NSArray<NSString*> *sections;
}

- (id)initWithStyle:(UITableViewStyle)style type:(NSInteger)typeValue list:(NSArray *)listValue{
    
    if(self = [super initWithStyle:style])
    {
        type = typeValue;
        list = listValue;
        
        switch (type) {
            case kTypeManufacturerValue:
            case kTypeDriverSourceValue:
            case kTypeCategoryValue:
                sections = @[@"#", @"a", @"b", @"c", @"d", @"e", @"f", @"g", @"h", @"i", @"j", @"k", @"l", @"m", @"n", @"o", @"p", @"q", @"r", @"s", @"t", @"u", @"v", @"w", @"x", @"y", @"z"];
                break;
        }
    }
    return self;
}
- (id)initWithType:(NSInteger)typeValue list:(NSArray *)listValue {
    return [self initWithStyle:UITableViewStyleGrouped type:typeValue list:listValue];
}
- (instancetype)initWithKey:(NSString*)keyValue list:(NSArray<NSString*>*)listValue {
    if (self = [super initWithStyle:UITableViewStyleGrouped])
    {
        NSAssert([[[Options alloc] init] valueForKey:keyValue] != nil, @"bad key");
        
        type = kTypeKeyValue;
        key = keyValue;
        list = [listValue mutableCopy];
        // if the list items are of the form "Name : Data", we only want to show "Name" to the user.
        for (NSInteger i=0; i<list.count; i++)
            ((NSMutableArray*)list)[i] = [[list[i] componentsSeparatedByString:@":"].firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    }
    return self;
}
- (instancetype)initWithKey:(NSString*)keyValue list:(NSArray<NSString*>*)listValue title:(NSString *)titleValue {
    self = [self initWithKey:keyValue list:listValue];
    self.title = titleValue;
    return self;
}

- (void)viewWillAppear:(BOOL)animated {

    Options *op = [[Options alloc] init];
    
    // get the current value and set the title
    switch (type) {
        case kTypeNumButtons:
            self.title = @"Number Of Buttons";
            value = op.numbuttons;
            break;
        case kTypeEmuRes:
            self.title = @"Emulated Resolution";
            value = op.emures;
            break;
        case kTypeStickType:
            self.title = @"Ways Stick";
            value = op.sticktype;
            break;
        case kTypeTouchType:
            self.title = @"Touch Type";
            value = op.touchtype;
            break;
        case kTypeControlType:
            self.title = @"External Controller";
            value = op.controltype;
            break;
        case kTypeAnalogDZValue:
            self.title = @"Stick Touch DZ";
            value = op.analogDeadZoneValue;
            break;
        case kTypeSoundValue:
            self.title = @"Sound";
            value = op.soundValue;
            break;
        case kTypeFSValue:
            self.title = @"Frame Skip";
            value = op.fsvalue;
            break;
        case kTypeOverscanValue:
            self.title = @"Overscan TV-OUT";
            value = op.overscanValue;
            break;
        case kTypeManufacturerValue:
            self.title = @"Manufacturer";
            value = op.manufacturerValue;
            break;
        case kTypeYearGTEValue:
            self.title = @"Year >=";
            value = op.yearGTEValue;
            break;
        case kTypeYearLTEValue:
            self.title = @"Year <=";
            value = op.yearLTEValue;
            break;
        case kTypeDriverSourceValue:
            self.title = @"Driver Source";
            value = op.driverSourceValue;
            break;
        case kTypeCategoryValue:
            self.title = @"Category";
            value = op.categoryValue;
            break;
        case kTypeVideoPriorityValue:
            self.title = @"Video Thread Priority";
            value = op.videoPriority;
            break;
        case kTypeMainPriorityValue:
            self.title = @"Main Thread Priority";
            value = op.mainPriority;
            break;
        case kTypeAutofireValue:
            self.title = @"A as Autofire";
            value = op.autofire;
            break;
        case kTypeButtonSizeValue:
            self.title = @"Buttons Size";
            value = op.buttonSize;
            break;
        case kTypeStickSizeValue:
            self.title = @"Fullscreen Stick Size";
            value = op.stickSize;
            break;
        case kTypeArrayWPANtype:
            self.title = @"WPAN mode";
            value = op.wpantype;
            break;
        case kTypeWFframeSync:
            self.title = @"Wi-Fi Frame Sync";
            value = op.wfframesync;
            break;
        case kTypeBTlatency:
            self.title = @"Bluetooth Latency";
            value = op.btlatency;
            break;
        case kTypeEmuSpeed:
            self.title = @"Emulation Speed";
            value = op.emuspeed;
            break;
        case kTypeVideoThreadTypeValue:
            self.title = @"Video Thread Type";
            value = op.videoThreadType;
            break;
        case kTypeMainThreadTypeValue:
            self.title = @"Main Thread Type";
            value = op.mainThreadType;
            break;
        case kTypeKeyValue:
        {
            id val = [op valueForKey:key];
            
            if ([val isKindOfClass:[NSString class]])
                value = [list indexOfOption:val];
            else if ([val isKindOfClass:[NSNumber class]])
                value = [val intValue];
            else
                value = 0;
            break;
        }
        default:
            NSAssert(FALSE, @"bad list type");
            break;
    }
    
    if (value == NSNotFound || value >= [list count]) {
        NSLog(@"list value out of range, setting to 0");
        value = 0;
    }
        
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (value > 10) {
        NSIndexPath *scrollIndexPath=nil;
        if(sections != nil)
        {
            NSString *s = [list optionAtIndex:value];
            NSString *l = [[s substringToIndex:1] lowercaseString];
            int sec = (uint32_t)[sections indexOfObject:l];
            NSArray *sectionArray = [list filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF beginswith[c] %@", [sections objectAtIndex: sec]]];
            int row = (uint32_t)[sectionArray indexOfObject:s];
            scrollIndexPath = [NSIndexPath indexPathForRow:row inSection:sec];
        }
        else
        {
           scrollIndexPath = [NSIndexPath indexPathForRow:(value) inSection:0];

        }
        [[self tableView] scrollToRowAtIndexPath:scrollIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    Options *op = [[Options alloc] init];
    int value = (int)self->value;
    
    // set the current value, in the kTypeCustom case call the handler to do it.
    switch (type) {
        case kTypeNumButtons:
            op.numbuttons =value;
            break;
        case kTypeEmuRes:
            op.emures =value;
            break;
        case kTypeTouchType:
            op.touchtype =value;
            break;
        case kTypeStickType:
            op.sticktype =value;
            break;
        case kTypeControlType:
            op.controltype =value;
            break;
        case kTypeAnalogDZValue:
            op.analogDeadZoneValue =value;
            break;
        case kTypeSoundValue:
            op.soundValue =value;
            break;
        case kTypeFSValue:
            op.fsvalue =value;
            break;
        case kTypeOverscanValue:
            op.overscanValue =value;
            break;
        case kTypeManufacturerValue:
            op.manufacturerValue =value;
            break;
        case kTypeYearGTEValue:
            op.yearGTEValue =value;
            break;
        case kTypeYearLTEValue:
            op.yearLTEValue =value;
            break;
        case kTypeDriverSourceValue:
            op.driverSourceValue =value;
            break;
        case kTypeCategoryValue:
            op.categoryValue =value;
            break;
        case kTypeVideoPriorityValue:
            op.videoPriority =value;
            break;
        case kTypeMainPriorityValue:
            op.mainPriority =value;
            break;
        case kTypeAutofireValue:
            op.autofire =value;
            break;
        case kTypeButtonSizeValue:
            op.buttonSize =value;
            break;
        case kTypeStickSizeValue:
            op.stickSize =value;
            break;
        case kTypeArrayWPANtype:
            op.wpantype =value;
            break;
        case kTypeWFframeSync:
            op.wfframesync =value;
            break;
        case kTypeBTlatency:
            op.btlatency =value;
            break;
        case kTypeEmuSpeed:
            op.emuspeed =value;
            break;
        case kTypeMainThreadTypeValue:
            op.mainThreadType =value;
            break;
        case kTypeVideoThreadTypeValue:
            op.videoThreadType =value;
            break;
        case kTypeKeyValue:
        {
            id val = [op valueForKey:key];

            if ([val isKindOfClass:[NSString class]])
                [op setValue:[list optionAtIndex:value] forKey:key];
            else if ([val isKindOfClass:[NSNumber class]])
                [op setValue:@(value) forKey:key];
            
            NSLog(@"LIST SELECT: %@ = %@", key, [op valueForKey:key]);
            break;
        }
        default:
            NSAssert(FALSE, @"bad type");
            break;
    }
    
    [op saveOptions];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (sections != nil)
        return [sections count];
    else
        return 1;
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return sections;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    
    if (sections != nil)
        return [[list filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF beginswith[c] %@", [sections objectAtIndex:section]]] count];
    else
        return [list count];
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CheckMarkCellIdentifier = @"CheckMarkCellIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CheckMarkCellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CheckMarkCellIdentifier];
    }
    
    NSUInteger row = [indexPath row];
    if (sections != nil)
    {
        NSString *txt = [self retrieveIndexedCellText:indexPath];
        cell.textLabel.text = txt;
        cell.accessoryType = ([list indexOfObject:txt] == value) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    else
    {
       cell.textLabel.text = [list objectAtIndex:row];
       cell.accessoryType = (row == value) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
        
    if (sections != nil)
    {
        NSInteger curr = [list indexOfObject:[self retrieveIndexedCellText:indexPath]];
        if(curr!=value) {
            value = curr;
        }
    }
    else
    {
       int row = (uint32_t)[indexPath row];
       if (row != value) {
           value = row;
       }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.tableView reloadData];
}

- (NSString *)retrieveIndexedCellText:(NSIndexPath *)indexPath{
    NSUInteger row = [indexPath row];
    NSArray *sectionArray = [list filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF beginswith[c] %@", [sections objectAtIndex:[indexPath section] ]]];
    return [sectionArray objectAtIndex:row];
}

@end
