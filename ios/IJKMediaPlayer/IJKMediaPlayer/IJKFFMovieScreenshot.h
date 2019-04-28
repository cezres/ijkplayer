//
//  IJKFFScreenshot.h
//  IJKMediaFramework
//
//  Created by 翟泉 on 2019/4/24.
//  Copyright © 2019 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IJKFFMovieScreenshot : NSObject

+ (nullable UIImage *)screenshotWithVideo:(NSString *)path forSeconds:(CGFloat)seconds;

@end

NS_ASSUME_NONNULL_END
