// asoftinstalld: installs the .ipa files dropped into an inbox folder (ASoftware iOS on QEMU).
// Copyright (c) 2026 ASoftware. MIT License, see LICENSE.
//
// A root launchd job (RunAtLoad, KeepAlive; tools/asoft-disk.sh adds it). Once
// SpringBoard has started up (installs asked for earlier never returned), every 10 s
// it looks at /private/var/mobile/Media/ASoftware/Inbox: each NAME.ipa there is installed
// through LaunchServices (installd does the work) and moved to ../Installed or, after
// three failed attempts or one that hangs, to ../Failed, with NAME.ipa.log saying what
// happened. Every message also goes to stderr, which the job sends to
// /dev/console (the kernel log on the serial port).
//
// It also asks the host: scripts/ipa-server.py (started by the Windows launcher)
// serves a Windows folder at 10.0.2.2:8765, QEMU's user network address of the
// host. Each .ipa listed there is fetched into the inbox and its result posted back.
//
// At start it gives iOS the PC's time zone, region format and 12/24-hour clock, which
// the launcher passes as boot-args, and keeps SpringBoard from dimming and locking.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <notify.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <unistd.h>
#include <zlib.h>

static NSString *const kRoot = @"/private/var/mobile/Media/ASoftware";
static const int kAttempts = 3;
static const char *const kHost = "10.0.2.2";
static const uint16_t kPort = 8765;
static const int kReadyUptime = 300;      // s after boot: iOS is surely up by then
static const int kInstallTimeout = 300;   // s; installd answers within seconds

static void
say(NSString *format, ...)
{
	va_list ap;
	va_start(ap, format);
	NSString *s = [[NSString alloc] initWithFormat:format arguments:ap];
	va_end(ap);
	// stderr is the console as launchd opened it when it spawned us, early in boot; nothing
	// written to that descriptor after SpringBoard's startup reached the serial log any more,
	// so every message opens the console anew.
	const char *line = [NSString stringWithFormat:@"asoftinstalld: %@\n", s].UTF8String;
	int fd = open("/dev/console", O_WRONLY | O_NOCTTY | O_NONBLOCK);
	if (fd >= 0) {
		write(fd, line, strlen(line));
		close(fd);
	} else {
		fputs(line, stderr);
	}
}

static NSError *
failure(NSString *what)
{
	return [NSError errorWithDomain:@"asoftinstalld" code:1 userInfo:@{NSLocalizedDescriptionKey: what}];
}

static uint32_t
le16(const uint8_t *p)
{
	return p[0] | p[1] << 8;
}

static uint32_t
le32(const uint8_t *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

// The bundle identifier in Payload/NAME.app/Info.plist of an .ipa (a zip file):
// installd wants it in the install options.
static NSString *
bundleIdentifier(NSString *ipa, NSError **error)
{
	NSData *zip = [NSData dataWithContentsOfFile:ipa options:NSDataReadingMappedIfSafe error:error];
	if (!zip) {
		return nil;
	}
	const uint8_t *z = zip.bytes;
	size_t n = zip.length;
	// End of central directory record: in the last 22 + 65535 bytes
	size_t eocd = SIZE_MAX;
	for (size_t i = n >= 22 ? n - 22 : 0; n >= 22 && i + 65557 >= n; i--) {
		if (le32(z + i) == 0x06054b50) {
			eocd = i;
			break;
		}
		if (i == 0) {
			break;
		}
	}
	if (eocd == SIZE_MAX) {
		*error = failure(@"not a zip file");
		return nil;
	}
	NSRegularExpression *infoPlist = [NSRegularExpression
	    regularExpressionWithPattern:@"^Payload/[^/]+\\.app/Info\\.plist$" options:0 error:nil];
	size_t entries = le16(z + eocd + 10), off = le32(z + eocd + 16);
	for (size_t e = 0; e < entries && off + 46 <= n && le32(z + off) == 0x02014b50; e++) {
		uint32_t method = le16(z + off + 10), csize = le32(z + off + 20), usize = le32(z + off + 24);
		uint32_t nlen = le16(z + off + 28), local = le32(z + off + 42);
		NSString *name = [[NSString alloc] initWithBytes:z + off + 46 length:MIN(nlen, n - off - 46)
		    encoding:NSUTF8StringEncoding];
		off += 46 + nlen + le16(z + off + 30) + le16(z + off + 32);
		if (!name || ![infoPlist firstMatchInString:name options:0 range:NSMakeRange(0, name.length)]) {
			continue;
		}
		if (local + 30 > n || le32(z + local) != 0x04034b50) {
			break;
		}
		size_t data = local + 30 + le16(z + local + 26) + le16(z + local + 28);
		if (data + csize > n || usize > (64 << 20)) {
			break;
		}
		NSMutableData *plist = [NSMutableData dataWithLength:usize];
		if (method == 0 && csize == usize) {
			memcpy(plist.mutableBytes, z + data, usize);
		} else if (method == 8) {
			z_stream s = {.next_in = (Bytef *)z + data, .avail_in = csize,
				      .next_out = plist.mutableBytes, .avail_out = usize};
			int rc = inflateInit2(&s, -MAX_WBITS);
			if (rc == Z_OK) {
				rc = inflate(&s, Z_FINISH);
				inflateEnd(&s);
			}
			if (rc != Z_STREAM_END) {
				break;
			}
		} else {
			break;
		}
		NSDictionary *info = [NSPropertyListSerialization propertyListWithData:plist options:0 format:NULL error:nil];
		NSString *identifier = [info isKindOfClass:NSDictionary.class] ? info[@"CFBundleIdentifier"] : nil;
		if ([identifier isKindOfClass:NSString.class]) {
			return identifier;
		}
		break;
	}
	*error = failure(@"no Payload/*.app/Info.plist with a CFBundleIdentifier in the .ipa");
	return nil;
}

// LSApplicationWorkspace is private (CoreServices, loaded with MobileCoreServices).
static BOOL
install(NSString *path, NSError **error)
{
	NSString *identifier = bundleIdentifier(path, error);
	if (!identifier) {
		return NO;
	}
	say(@"%@: bundle identifier %@", path.lastPathComponent, identifier);
	Class cls = NSClassFromString(@"LSApplicationWorkspace");
	id workspace = cls ? ((id (*)(Class, SEL))objc_msgSend)(cls, @selector(defaultWorkspace)) : nil;
	SEL sel = @selector(installApplication:withOptions:error:);
	if (!workspace || ![workspace respondsToSelector:sel]) {
		*error = failure(@"LSApplicationWorkspace is not available");
		return NO;
	}
	BOOL (*call)(id, SEL, NSURL *, NSDictionary *, NSError **) = (void *)objc_msgSend;
	return call(workspace, sel, [NSURL fileURLWithPath:path],
	           @{@"CFBundleIdentifier": identifier, @"PackageType": @"Customer"}, error);
}

static double
uptime(void)
{
	struct timeval boot, now;
	size_t size = sizeof(boot);
	int mib[2] = {CTL_KERN, KERN_BOOTTIME};
	if (sysctl(mib, 2, &boot, &size, NULL, 0) != 0 || gettimeofday(&now, NULL) != 0) {
		return 0;
	}
	return (double)(now.tv_sec - boot.tv_sec) + (now.tv_usec - boot.tv_usec) / 1e6;
}

// The value of boot-arg NAME=value, or nil.
static NSString *
bootArg(NSString *name)
{
	static NSArray<NSString *> *args;
	if (!args) {
		char buf[1024] = {0};
		size_t size = sizeof(buf) - 1;
		args = sysctlbyname("kern.bootargs", buf, &size, NULL, 0) == 0
		    ? [[NSString stringWithUTF8String:buf] componentsSeparatedByString:@" "] : @[];
	}
	NSString *prefix = [name stringByAppendingString:@"="];
	for (NSString *arg in args) {
		if ([arg hasPrefix:prefix]) {
			return [arg substringFromIndex:prefix.length];
		}
	}
	return nil;
}

// iOS keeps its time zone as the symlink /var/db/timezone/localtime, which timed sets from
// the cell network or the location; there is neither here, so it stayed at the image's
// US/Pacific.
static BOOL
setTimeZone(NSString *zone)
{
	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *link = @"/private/var/db/timezone/localtime";
	NSString *target = [@"/var/db/timezone/zoneinfo/" stringByAppendingString:zone];
	if ([zone hasPrefix:@"/"] || [zone containsString:@".."] || ![fm fileExistsAtPath:target]) {
		say(@"time zone %@: no such zone", zone);
		return NO;
	}
	NSString *was = [fm destinationOfSymbolicLinkAtPath:link error:nil];
	if (![was isEqualToString:target]) {
		// a new link renamed over the old one: never a moment without a time zone
		NSString *tmp = [link stringByAppendingString:@".asoft"];
		unlink(tmp.fileSystemRepresentation);
		if (symlink(target.fileSystemRepresentation, tmp.fileSystemRepresentation) != 0 ||
		    rename(tmp.fileSystemRepresentation, link.fileSystemRepresentation) != 0) {
			say(@"time zone %@: %s", zone, strerror(errno));
			unlink(tmp.fileSystemRepresentation);
			return NO;
		}
		notify_post("com.apple.system.timezone");
	}
	say(@"time zone %@ (was %@)", zone, [was stringByReplacingOccurrencesOfString:@"/var/db/timezone/zoneinfo/"
	                                                                      withString:@""]);
	return YES;
}

// The region format, AppleLocale: iOS's language with the PC's region (English with Turkey
// is en_TR, English words in Turkish date, time and number formats).
static BOOL
setRegion(NSString *region)
{
	if ([region rangeOfString:@"^([A-Z]{2}|[0-9]{3})$" options:NSRegularExpressionSearch].location == NSNotFound) {
		say(@"region %@: not a region code", region);
		return NO;
	}
	CFStringRef user = CFSTR("mobile");
	id languages = CFBridgingRelease(CFPreferencesCopyValue(CFSTR("AppleLanguages"),
	    kCFPreferencesAnyApplication, user, kCFPreferencesAnyHost));
	id first = [languages isKindOfClass:NSArray.class] ? [languages firstObject] : nil;
	NSString *language = [first isKindOfClass:NSString.class] ? first : @"en";
	NSMutableDictionary *parts = [[NSLocale componentsFromLocaleIdentifier:language] mutableCopy];
	parts[NSLocaleCountryCode] = region;
	NSString *locale = [NSLocale localeIdentifierFromComponents:parts];
	CFPreferencesSetValue(CFSTR("AppleLocale"), (__bridge CFStringRef)locale, kCFPreferencesAnyApplication,
	    user, kCFPreferencesAnyHost);
	say(@"region %@ (%@)", region, locale);
	return YES;
}

// 24 or 12: the 24-Hour Time switch of Settings > General > Date & Time.
static BOOL
setClock(NSString *clock)
{
	BOOL h24 = [clock isEqualToString:@"24"];
	if (!h24 && ![clock isEqualToString:@"12"]) {
		say(@"clock %@: not 12 or 24", clock);
		return NO;
	}
	CFStringRef user = CFSTR("mobile");
	CFPreferencesSetValue(CFSTR("AppleICUForce24HourTime"), h24 ? kCFBooleanTrue : NULL,
	    kCFPreferencesAnyApplication, user, kCFPreferencesAnyHost);
	CFPreferencesSetValue(CFSTR("AppleICUForce12HourTime"), h24 ? NULL : kCFBooleanTrue,
	    kCFPreferencesAnyApplication, user, kCFPreferencesAnyHost);
	say(@"%@-hour clock", clock);
	return YES;
}

// Processes keep the locale they have read, and SpringBoard starts before us: these make
// CoreFoundation read it again, as Settings does after changing the clock.
static void
postLocaleChanged(void)
{
	notify_post("AppleTimePreferencesChangedNotification");
	notify_post("AppleDatePreferencesChangedNotification");
	notify_post("AppleNumberPreferencesChangedNotification");
}

// The PC's settings, from the Windows launcher's boot-args asoft_tz (time zone, Area/City),
// asoft_region (region, TR) and asoft_clock (24 or 12). Each is applied only when it differs
// from what was applied last (Host.plist next to the inbox): a change made in iOS's Settings
// stays until the PC's own setting changes. Returns whether the region or clock changed.
static BOOL
applyHostSettings(void)
{
	NSString *path = [kRoot stringByAppendingPathComponent:@"Host.plist"];
	NSMutableDictionary *applied = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy]
	    ?: [NSMutableDictionary dictionary];
	NSDictionary<NSString *, NSString *> *args = @{@"TimeZone": @"asoft_tz", @"Region": @"asoft_region",
	                                               @"Clock": @"asoft_clock"};
	BOOL changed = NO, locale = NO;
	for (NSString *key in args) {
		NSString *value = bootArg(args[key]);
		if (value.length == 0 || [applied[key] isEqual:value]) {
			continue;
		}
		BOOL zone = [key isEqualToString:@"TimeZone"];
		BOOL ok = zone ? setTimeZone(value) : [key isEqualToString:@"Region"] ? setRegion(value) : setClock(value);
		if (ok) {
			applied[key] = value;
			changed = YES;
			locale |= !zone;
		}
	}
	if (changed) {
		CFPreferencesSynchronize(kCFPreferencesAnyApplication, CFSTR("mobile"), kCFPreferencesAnyHost);
		[NSFileManager.defaultManager createDirectoryAtPath:kRoot withIntermediateDirectories:YES
		                                          attributes:nil error:nil];
		[applied writeToFile:path atomically:YES];
	}
	if (locale) {
		postLocaleChanged();
	}
	return locale;
}

// SpringBoard dims the lock screen and asks for the display off seconds after boot; the
// kernel keeps the display on (sweetfb_keepon), so the dimmed frame stayed until a key woke
// iOS. The emulated battery always charges: never dim or lock on power. SpringBoard reads
// its defaults when it launches, well after us (tools/asoft-disk.sh nodim does the same
// offline).
static void
keepDisplayOn(void)
{
	CFStringRef domain = CFSTR("com.apple.springboard");
	CFStringRef user = CFSTR("mobile");
	BOOL changed = NO;
	for (NSString *key in @[@"SBDontDimOrLockOnAC", @"SBDisableAutoDim"]) {
		CFPropertyListRef value = CFPreferencesCopyValue((__bridge CFStringRef)key, domain, user,
		    kCFPreferencesAnyHost);
		if (value != kCFBooleanTrue) {
			CFPreferencesSetValue((__bridge CFStringRef)key, kCFBooleanTrue, domain, user,
			    kCFPreferencesAnyHost);
			changed = YES;
		}
		if (value) {
			CFRelease(value);
		}
	}
	if (changed) {
		CFPreferencesSynchronize(domain, user, kCFPreferencesAnyHost);
		say(@"SpringBoard: no dimming or auto-lock on power");
	}
}

// An install asked for in the first seconds of boot, before lsd and installd ran, never
// returned. Wait until SpringBoard has finished starting up; when we start later than that
// (launchd restarted us), kReadyUptime after boot is enough.
static void
waitForSpringBoard(void)
{
	dispatch_semaphore_t up = dispatch_semaphore_create(0);
	int token = 0;
	BOOL registered = notify_register_dispatch("com.apple.springboard.finishedstartup", &token,
	    dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(__unused int t) {
		dispatch_semaphore_signal(up);
	}) == NOTIFY_STATUS_OK;
	while (uptime() < kReadyUptime &&
	    dispatch_semaphore_wait(up, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
	}
	if (registered) {
		notify_cancel(token);
	}
	say(@"iOS is up (%.0f s after boot)", uptime());
}

// install() on another thread: 1 installed, 0 failed, -1 no answer within kInstallTimeout.
static int
installWithTimeout(NSString *path, NSError **error)
{
	__block BOOL ok = NO;
	__block NSError *failed = nil;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *e = nil;
		ok = install(path, &e);
		failed = e;
		dispatch_semaphore_signal(done);
	});
	if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, kInstallTimeout * NSEC_PER_SEC)) != 0) {
		*error = failure([NSString stringWithFormat:@"installd did not answer within %d s", kInstallTimeout]);
		return -1;
	}
	*error = failed;
	return ok ? 1 : 0;
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

static BOOL
sendAll(int fd, NSData *data)
{
	const uint8_t *p = data.bytes;
	for (size_t left = data.length; left > 0;) {
		ssize_t n = send(fd, p, left, 0);
		if (n <= 0) {
			return NO;
		}
		p += n;
		left -= (size_t)n;
	}
	return YES;
}

// A minimal HTTP/1.0 client on a plain socket (no CFNetwork, so no App Transport
// Security): ipa-server.py closes the connection after each reply. Returns the
// body and sets *status, or nil when the host cannot be reached.
static NSData *
http(NSString *method, NSString *path, NSData *body, int timeout, int *status)
{
	*status = 0;
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0) {
		return nil;
	}
	struct timeval tv = {.tv_sec = timeout};
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
	struct sockaddr_in sa = {.sin_len = sizeof(sa), .sin_family = AF_INET, .sin_port = htons(kPort)};
	inet_pton(AF_INET, kHost, &sa.sin_addr);
	NSMutableData *response = nil;
	if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) == 0) {
		NSString *head = [NSString stringWithFormat:@"%@ %@ HTTP/1.0\r\nHost: %s\r\nContent-Length: %lu\r\n\r\n",
		    method, path, kHost, (unsigned long)body.length];
		NSMutableData *request = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
		if (body) {
			[request appendData:body];
		}
		if (sendAll(fd, request)) {
			response = [NSMutableData data];
			uint8_t buf[65536];
			ssize_t n;
			while ((n = recv(fd, buf, sizeof(buf), 0)) > 0) {
				[response appendBytes:buf length:(NSUInteger)n];
			}
			if (n < 0) {
				response = nil;
			}
		}
	}
	close(fd);
	NSData *crlf2 = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
	NSRange end = response ? [response rangeOfData:crlf2 options:0 range:NSMakeRange(0, response.length)]
	                       : NSMakeRange(NSNotFound, 0);
	if (end.location == NSNotFound) {
		return nil;
	}
	NSString *head = [[NSString alloc] initWithData:[response subdataWithRange:NSMakeRange(0, end.location)]
	    encoding:NSISOLatin1StringEncoding];
	NSArray<NSString *> *words = [head componentsSeparatedByString:@" "];
	*status = words.count > 1 ? words[1].intValue : 0;
	return [response subdataWithRange:NSMakeRange(NSMaxRange(end), response.length - NSMaxRange(end))];
}

static NSString *
urlName(NSString *name)
{
	NSMutableCharacterSet *allowed = [NSCharacterSet.URLPathAllowedCharacterSet mutableCopy];
	[allowed removeCharactersInString:@"/?#%"];
	return [name stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

// Fetch the .ipa files the host lists into the inbox; remembers them in fromHost.
static void
fetchFromHost(NSString *inbox, NSMutableSet<NSString *> *fromHost)
{
	int status;
	NSData *list = http(@"GET", @"/list", nil, 5, &status);
	if (!list || status != 200) {
		return;
	}
	NSString *names = [[NSString alloc] initWithData:list encoding:NSUTF8StringEncoding];
	for (NSString *name in [names componentsSeparatedByString:@"\n"]) {
		if (![name.pathExtension.lowercaseString isEqualToString:@"ipa"] || [name containsString:@"/"] ||
		    [name hasPrefix:@"."] || [fromHost containsObject:name]) {
			continue;
		}
		NSData *ipa = http(@"GET", [@"/ipa/" stringByAppendingString:urlName(name)], nil, 60, &status);
		if (ipa && status == 200 && [ipa writeToFile:[inbox stringByAppendingPathComponent:name] atomically:YES]) {
			say(@"%@: fetched from the host (%lu bytes)", name, (unsigned long)ipa.length);
			[fromHost addObject:name];
		}
	}
}

static void
reportToHost(NSString *name, NSString *result, NSMutableSet<NSString *> *fromHost)
{
	if ([fromHost containsObject:name]) {
		int status;
		http(@"POST", [@"/done/" stringByAppendingString:urlName(name)],
		    [result dataUsingEncoding:NSUTF8StringEncoding], 10, &status);
		[fromHost removeObject:name];
	}
}

int
main(void)
{
	@autoreleasepool {
		BOOL localeChanged = applyHostSettings();
		keepDisplayOn();
		NSFileManager *fm = NSFileManager.defaultManager;
		NSString *inbox = [kRoot stringByAppendingPathComponent:@"Inbox"];
		[fm createDirectoryAtPath:inbox withIntermediateDirectories:YES
		    attributes:@{NSFilePosixPermissions: @0777} error:nil];
		NSMutableDictionary<NSString *, NSNumber *> *attempts = [NSMutableDictionary dictionary];
		NSMutableSet<NSString *> *fromHost = [NSMutableSet set];
		waitForSpringBoard();
		if (localeChanged) {
			postLocaleChanged();    // again, for what SpringBoard set up while it started
		}
		say(@"watching %@ and http://%s:%u/list", inbox, kHost, kPort);
		for (;;) {
			@autoreleasepool {
				fetchFromHost(inbox, fromHost);
				for (NSString *name in [fm contentsOfDirectoryAtPath:inbox error:nil]) {
					if (![name.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
						continue;
					}
					NSString *src = [inbox stringByAppendingPathComponent:name];
					int n = attempts[name].intValue + 1;
					attempts[name] = @(n);
					say(@"installing %@ (attempt %d)", name, n);
					NSError *error = nil;
					int status = installWithTimeout(src, &error);
					if (status == 1) {
						say(@"%@: installed", name);
						finish(fm, src, name, @"Installed", @"installed");
						reportToHost(name, @"installed", fromHost);
						[attempts removeObjectForKey:name];
					} else {
						NSString *result = [NSString stringWithFormat:@"failed: %@", error];
						say(@"%@: %@", name, result);
						if (n >= kAttempts || status < 0) {
							finish(fm, src, name, @"Failed", result);
							reportToHost(name, result, fromHost);
							[attempts removeObjectForKey:name];
						}
						if (status < 0) {
							exit(1);    // the hung request stays with this process; launchd starts a fresh one
						}
					}
				}
			}
			sleep(10);
		}
	}
}
