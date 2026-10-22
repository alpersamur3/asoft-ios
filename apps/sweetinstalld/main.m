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
#include <zlib.h>

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

static NSError *
failure(NSString *what)
{
	return [NSError errorWithDomain:@"sweetinstalld" code:1 userInfo:@{NSLocalizedDescriptionKey: what}];
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
