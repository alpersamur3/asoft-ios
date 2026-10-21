// sweetinstalld: installs the .ipa files dropped into an inbox folder (SWEET on QEMU).
//
// A root launchd job (RunAtLoad, KeepAlive; tools/sweet-ipa.sh adds it). Every
// 10 s it looks at /private/var/mobile/Media/Sweet/Inbox: each NAME.ipa there is
// installed through LaunchServices (installd does the work) and moved to
// ../Installed or, after three failed attempts, to ../Failed, with NAME.ipa.log
// saying what happened. Every message also goes to stderr, which the job sends to
// /dev/console (the kernel log on the serial port).
#import <Foundation/Foundation.h>
#import <objc/message.h>

static NSString *const kRoot = @"/private/var/mobile/Media/Sweet";
static const int kAttempts = 3;

static void
say(NSString *format, ...)
{
	va_list ap;
	va_start(ap, format);
	NSString *s = [[NSString alloc] initWithFormat:format arguments:ap];
	va_end(ap);
	fprintf(stderr, "sweetinstalld: %s\n", s.UTF8String);
}

// LSApplicationWorkspace is private (CoreServices, loaded with MobileCoreServices).
static BOOL
install(NSString *path, NSError **error)
{
	Class cls = NSClassFromString(@"LSApplicationWorkspace");
	id workspace = cls ? ((id (*)(Class, SEL))objc_msgSend)(cls, @selector(defaultWorkspace)) : nil;
	SEL sel = @selector(installApplication:withOptions:error:);
	if (!workspace || ![workspace respondsToSelector:sel]) {
		*error = [NSError errorWithDomain:@"sweetinstalld" code:1
		    userInfo:@{NSLocalizedDescriptionKey: @"LSApplicationWorkspace is not available"}];
		return NO;
	}
	BOOL (*call)(id, SEL, NSURL *, NSDictionary *, NSError **) = (void *)objc_msgSend;
	return call(workspace, sel, [NSURL fileURLWithPath:path], @{@"PackageType": @"Customer"}, error);
}

static void
finish(NSFileManager *fm, NSString *src, NSString *name, NSString *where, NSString *result)
{
	NSString *dir = [kRoot stringByAppendingPathComponent:where];
	[fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *dst = [dir stringByAppendingPathComponent:name];
	[fm removeItemAtPath:dst error:nil];
	[fm moveItemAtPath:src toPath:dst error:nil];
	[[result stringByAppendingString:@"\n"] writeToFile:[dst stringByAppendingString:@".log"]
	    atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

int
main(void)
{
	@autoreleasepool {
		NSFileManager *fm = NSFileManager.defaultManager;
		NSString *inbox = [kRoot stringByAppendingPathComponent:@"Inbox"];
		[fm createDirectoryAtPath:inbox withIntermediateDirectories:YES
		    attributes:@{NSFilePosixPermissions: @0777} error:nil];
		NSMutableDictionary<NSString *, NSNumber *> *attempts = [NSMutableDictionary dictionary];
		say(@"watching %@", inbox);
		for (;;) {
			@autoreleasepool {
				for (NSString *name in [fm contentsOfDirectoryAtPath:inbox error:nil]) {
					if (![name.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
						continue;
					}
					NSString *src = [inbox stringByAppendingPathComponent:name];
					int n = attempts[name].intValue + 1;
					attempts[name] = @(n);
					say(@"installing %@ (attempt %d)", name, n);
					NSError *error = nil;
					if (install(src, &error)) {
						say(@"%@: installed", name);
						finish(fm, src, name, @"Installed", @"installed");
						[attempts removeObjectForKey:name];
					} else {
						NSString *result = [NSString stringWithFormat:@"failed: %@", error];
						say(@"%@: %@", name, result);
						if (n >= kAttempts) {
							finish(fm, src, name, @"Failed", result);
							[attempts removeObjectForKey:name];
						}
					}
				}
			}
			sleep(10);
		}
	}
}
