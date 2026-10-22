// Hello: the smallest UIKit app, to test installing an .ipa on ASoftware iOS.
// Copyright (c) 2026 ASoftware. MIT License, see LICENSE.
#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
	UIViewController *vc = [UIViewController new];
	vc.view.backgroundColor = UIColor.systemTealColor;
	UILabel *label = [UILabel new];
	label.text = @"Hello from ASoftware";
	label.font = [UIFont boldSystemFontOfSize:32];
	label.textColor = UIColor.whiteColor;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	[vc.view addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
		[label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
	]];
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = vc;
	[self.window makeKeyAndVisible];
	return YES;
}

@end

int
main(int argc, char *argv[])
{
	@autoreleasepool {
		return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
	}
}
