//
//  InfoHUD.h
//  Wombat
//
//  Created by Todd Laney on 6/4/20.
//  Copyright © 2020 Wombat. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface InfoHUD : UIControl

@property(nonatomic) CGFloat spacing;
@property(nonatomic) BOOL moveable;
@property(nonatomic) BOOL sizeable;
@property(null_resettable,nonatomic,strong) UIFont* font;
@property(readonly,nonatomic,strong) NSString* changedKey;

- (NSArray<NSString*>*)allKeys;

- (void)removeAll;

- (void)addValue:(id)value;
- (void)addValue:(id)value forKey:(NSString *)key;
- (void)addValue:(id)value forKey:(NSString *)key format:(NSString*)format;
- (void)addValue:(id)value forKey:(nullable NSString *)key format:(nullable NSString*)format min:(nullable id)min max:(nullable id)max;
- (void)addValue:(id)value forKey:(nullable NSString *)key format:(nullable NSString*)format min:(nullable id)min max:(nullable id)max step:(nullable id)step;
- (void)addValues:(NSDictionary*)values;

- (void)addTitle:(NSString*)str;
- (void)addText:(NSString*)str;
- (void)addView:(UIView*)view;
- (void)addSeparator;

// toolbar and button items can be a UIImage or a NSString
// strings starting with ":symbol-name:fallback:" will be expanded to a SF Symbol (or use fallback text)
- (void)addToolbar:(NSArray*)items handler:(void (^)(NSUInteger button))handler;
- (void)addButtons:(NSArray*)items handler:(void (^)(NSUInteger button))handler;
- (void)addButton:(id)item color:(nullable UIColor*)color handler:(void (^)(void))handler;
- (void)addButton:(id)item handler:(void (^)(void))handler;

- (void)setValue:(nullable id)value forKey:(NSString *)key;
- (void)setValues:(NSDictionary*)values;

- (id)valueForKey:(NSString *)key;
- (NSDictionary*)getValues;

@end

NS_ASSUME_NONNULL_END
