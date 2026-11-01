// GLESTest: does OpenGL ES work in the iOS 26 guest? (vphone-cli issue #793: on the paravirtual GPU
// every EAGLContext initializer returns nil.) The app runs the issue's check, then draws a turning
// triangle with OpenGL ES 2 into a CAEAGLLayer. The results go on screen, to os_log ("GLESTest:")
// and to /var/mobile/Media/glestest.log, which the serial root shell can read.
// Copyright (c) 2026 ASoftware. MIT License, see LICENSE.
#define GLES_SILENCE_DEPRECATION 1
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <Metal/Metal.h>

static NSMutableString *gLog;

static void
Say(NSString *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
	va_end(ap);
	NSLog(@"GLESTest: %@", s);
	if (!gLog)
		gLog = [NSMutableString new];
	[gLog appendFormat:@"%@\n", s];
	[gLog writeToFile:@"/var/mobile/Media/glestest.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@interface GLView : UIView
@end

@implementation GLView
+ (Class)layerClass
{
	return CAEAGLLayer.class;
}
@end

@interface TriangleController : UIViewController
@end

@implementation TriangleController {
	EAGLContext *_ctx;
	GLuint _fb, _rb, _prog, _vbo;
	GLint _w, _h, _angle;
	UILabel *_label;
	NSString *_status;
	CADisplayLink *_link;
	NSUInteger _frames;
}

static GLuint
Shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	GLint ok = 0;
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char msg[512] = "";
		glGetShaderInfoLog(s, sizeof msg, NULL, msg);
		Say(@"shader %s failed: %s", type == GL_VERTEX_SHADER ? "vertex" : "fragment", msg);
	}
	return s;
}

- (void)loadView
{
	self.view = [[GLView alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.view.backgroundColor = UIColor.blackColor;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	NSMutableArray *lines = [NSMutableArray new];
	for (int api = 1; api <= 3; api++) {
		EAGLContext *c = [[EAGLContext alloc] initWithAPI:(EAGLRenderingAPI)api];
		NSString *l = [NSString stringWithFormat:@"EAGL %d: %s", api, c ? "OK" : "nil"];
		Say(@"%@", l);
		[lines addObject:l];
	}
	id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
	Say(@"Metal: %@", dev.name);
	[lines addObject:[NSString stringWithFormat:@"Metal: %@", dev.name]];

	_label = [UILabel new];
	_label.numberOfLines = 0;
	_label.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightSemibold];
	_label.textColor = UIColor.whiteColor;
	_label.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_label];
	[NSLayoutConstraint activateConstraints:@[
		[_label.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
		[_label.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
		[_label.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
	]];

	_ctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
	if (!_ctx || ![EAGLContext setCurrentContext:_ctx]) {
		self.view.backgroundColor = UIColor.systemRedColor;
		_status = [lines componentsJoinedByString:@"\n"];
		_label.text = [_status stringByAppendingString:@"\n\nNo OpenGL ES context."];
		return;
	}
	[lines addObject:[NSString stringWithFormat:@"GL_RENDERER: %s", glGetString(GL_RENDERER)]];
	[lines addObject:[NSString stringWithFormat:@"GL_VERSION: %s", glGetString(GL_VERSION)]];
	Say(@"%@", lines[lines.count - 2]);
	Say(@"%@", lines[lines.count - 1]);
	_status = [lines componentsJoinedByString:@"\n"];
	_label.text = _status;
	[self setUpGL];
	_link = [CADisplayLink displayLinkWithTarget:self selector:@selector(draw)];
	[_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)setUpGL
{
	CAEAGLLayer *layer = (CAEAGLLayer *)self.view.layer;
	layer.opaque = YES;
	layer.contentsScale = UIScreen.mainScreen.scale;
	glGenRenderbuffers(1, &_rb);
	glBindRenderbuffer(GL_RENDERBUFFER, _rb);
	if (![_ctx renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer])
		Say(@"renderbufferStorage:fromDrawable: failed");
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_w);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_h);
	glGenFramebuffers(1, &_fb);
	glBindFramebuffer(GL_FRAMEBUFFER, _fb);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _rb);
	Say(@"drawable %dx%d, framebuffer status 0x%x", _w, _h, glCheckFramebufferStatus(GL_FRAMEBUFFER));

	GLuint vs = Shader(GL_VERTEX_SHADER,
		"attribute vec2 pos;\n"
		"attribute vec3 col;\n"
		"uniform float angle;\n"
		"varying vec3 v;\n"
		"void main() {\n"
		"  float c = cos(angle), s = sin(angle);\n"
		"  gl_Position = vec4(c * pos.x - s * pos.y, (s * pos.x + c * pos.y) * 0.46, 0.0, 1.0);\n"
		"  v = col;\n"
		"}\n");
	GLuint fs = Shader(GL_FRAGMENT_SHADER,
		"precision mediump float;\n"
		"varying vec3 v;\n"
		"void main() { gl_FragColor = vec4(v, 1.0); }\n");
	_prog = glCreateProgram();
	glAttachShader(_prog, vs);
	glAttachShader(_prog, fs);
	glBindAttribLocation(_prog, 0, "pos");
	glBindAttribLocation(_prog, 1, "col");
	glLinkProgram(_prog);
	GLint ok = 0;
	glGetProgramiv(_prog, GL_LINK_STATUS, &ok);
	Say(@"program link %s", ok ? "OK" : "failed");
	_angle = glGetUniformLocation(_prog, "angle");

	static const GLfloat tri[] = {
		0.0f, 0.8f, 1.0f, 0.2f, 0.2f,
		-0.7f, -0.45f, 0.2f, 1.0f, 0.2f,
		0.7f, -0.45f, 0.2f, 0.4f, 1.0f,
	};
	glGenBuffers(1, &_vbo);
	glBindBuffer(GL_ARRAY_BUFFER, _vbo);
	glBufferData(GL_ARRAY_BUFFER, sizeof tri, tri, GL_STATIC_DRAW);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat), (void *)0);
	glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat), (void *)(2 * sizeof(GLfloat)));
	glEnableVertexAttribArray(0);
	glEnableVertexAttribArray(1);
}

- (void)draw
{
	[EAGLContext setCurrentContext:_ctx];
	glBindFramebuffer(GL_FRAMEBUFFER, _fb);
	glViewport(0, 0, _w, _h);
	glClearColor(0.05f, 0.08f, 0.2f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	glUseProgram(_prog);
	glUniform1f(_angle, (GLfloat)(_frames * 0.02));
	glDrawArrays(GL_TRIANGLES, 0, 3);
	if (_frames == 0 || _frames == 300) {
		// the pixel at the centre of the drawable (inside the triangle) and one in a corner (clear colour)
		GLubyte mid[4] = {0}, corner[4] = {0};
		glReadPixels(_w / 2, _h / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, mid);
		glReadPixels(4, 4, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, corner);
		Say(@"frame %lu: centre rgba %d,%d,%d,%d corner rgba %d,%d,%d,%d, glGetError 0x%x", (unsigned long)_frames,
			mid[0], mid[1], mid[2], mid[3], corner[0], corner[1], corner[2], corner[3], glGetError());
	}
	glBindRenderbuffer(GL_RENDERBUFFER, _rb);
	[_ctx presentRenderbuffer:GL_RENDERBUFFER];
	_frames++;
	if (_frames % 30 == 1)
		_label.text = [NSString stringWithFormat:@"%@\nframes: %lu", _status, (unsigned long)_frames];
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = [TriangleController new];
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
