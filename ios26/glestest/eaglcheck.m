// eaglcheck: vphone-cli issue #793's check, as a command-line tool for the serial root shell.
// It ships inside GLESTest.app, so its CDHash goes into the trust cache with the app's:
//   /Applications/GLESTest.app/eaglcheck
// With a context it also draws one triangle into a 64x64 renderbuffer and reads its centre back.
// Copyright (c) 2026 ASoftware. MIT License, see LICENSE.
#define GLES_SILENCE_DEPRECATION 1
#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <Metal/Metal.h>
#include <stdio.h>

int
main(void)
{
	@autoreleasepool {
		for (int api = 1; api <= 3; api++)
			printf("EAGL %d: %s\n", api, [[EAGLContext alloc] initWithAPI:(EAGLRenderingAPI)api] ? "OK" : "nil");
		printf("Metal: %s\n", MTLCreateSystemDefaultDevice().name.UTF8String);

		EAGLContext *ctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
		if (!ctx || ![EAGLContext setCurrentContext:ctx])
			return 1;
		printf("GL_VENDOR: %s\nGL_RENDERER: %s\nGL_VERSION: %s\n", glGetString(GL_VENDOR), glGetString(GL_RENDERER),
			glGetString(GL_VERSION));
		GLuint rb, fb;
		glGenRenderbuffers(1, &rb);
		glBindRenderbuffer(GL_RENDERBUFFER, rb);
		glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, 64, 64);
		glGenFramebuffers(1, &fb);
		glBindFramebuffer(GL_FRAMEBUFFER, fb);
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
		printf("framebuffer status 0x%x\n", glCheckFramebufferStatus(GL_FRAMEBUFFER));

		const char *vsrc = "attribute vec2 p; void main() { gl_Position = vec4(p, 0.0, 1.0); }";
		const char *fsrc = "precision mediump float; void main() { gl_FragColor = vec4(1.0, 0.5, 0.0, 1.0); }";
		GLuint vs = glCreateShader(GL_VERTEX_SHADER), fs = glCreateShader(GL_FRAGMENT_SHADER);
		glShaderSource(vs, 1, &vsrc, NULL);
		glCompileShader(vs);
		glShaderSource(fs, 1, &fsrc, NULL);
		glCompileShader(fs);
		GLuint prog = glCreateProgram();
		glAttachShader(prog, vs);
		glAttachShader(prog, fs);
		glBindAttribLocation(prog, 0, "p");
		glLinkProgram(prog);
		GLint ok = 0;
		glGetProgramiv(prog, GL_LINK_STATUS, &ok);
		printf("program link: %s\n", ok ? "OK" : "failed");

		static const GLfloat tri[] = { 0.0f, 0.9f, -0.9f, -0.9f, 0.9f, -0.9f };
		glViewport(0, 0, 64, 64);
		glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		glUseProgram(prog);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, tri);
		glEnableVertexAttribArray(0);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		GLubyte mid[4] = {0}, corner[4] = {0};
		glReadPixels(32, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, mid);
		glReadPixels(1, 62, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, corner);
		printf("centre rgba %d,%d,%d,%d (want 255,128,0,255), corner rgba %d,%d,%d,%d (want 0,0,255,255), glGetError 0x%x\n",
			mid[0], mid[1], mid[2], mid[3], corner[0], corner[1], corner[2], corner[3], glGetError());
		return 0;
	}
}
