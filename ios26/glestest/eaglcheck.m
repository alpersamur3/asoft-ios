// eaglcheck: vphone-cli issue #793's check, as a command-line tool for the serial root shell.
// It ships inside GLESTest.app, so its CDHash goes into the trust cache with the app's:
//   /Applications/GLESTest.app/eaglcheck
// With a context it draws into a 64x64 renderbuffer and reads all of it back, after each of:
//   clear       a blue clear
//   scissor     a green clear of the 32x32 square at (16,16), which AppleMetalGLRenderer draws with
//               its own precompiled shaders (default.metallib), not with GL IR
//   client      an orange triangle from a client-memory vertex array (GL IR shaders)
//   vbo         the same from a vertex buffer object
//   elements    the same as glDrawElements with 16-bit indices in an element buffer
// Each line counts the texels of each colour and gives the box the non-blue ones lie in.
// Copyright (c) 2026 ASoftware. MIT License, see LICENSE.
#define GLES_SILENCE_DEPRECATION 1
#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>

enum { N = 64 };

static GLuint
shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	GLint ok = 0;
	char log[512] = "";
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	glGetShaderInfoLog(s, sizeof log, NULL, log);
	printf("%s shader: %s%s%s\n", type == GL_VERTEX_SHADER ? "vertex" : "fragment", ok ? "OK" : "failed",
		log[0] ? ", log: " : "", log);
	return s;
}

// Reads the renderbuffer back and prints what is in it.
static void
report(const char *what)
{
	static GLubyte px[N * N * 4];
	glFinish();
	glReadPixels(0, 0, N, N, GL_RGBA, GL_UNSIGNED_BYTE, px);
	int blue = 0, green = 0, orange = 0, other = 0, x0 = N, y0 = N, x1 = -1, y1 = -1;
	GLubyte *odd = NULL;
	for (int y = 0; y < N; y++)
		for (int x = 0; x < N; x++) {
			GLubyte *p = px + (y * N + x) * 4;
			if (p[0] < 8 && p[1] < 8 && p[2] > 247) {
				blue++;
				continue;
			}
			if (p[0] < 8 && p[1] > 247 && p[2] < 8)
				green++;
			else if (p[0] > 247 && abs(p[1] - 128) < 8 && p[2] < 8)
				orange++;
			else {
				other++;
				if (!odd)
					odd = p;
			}
			if (x < x0) x0 = x;
			if (y < y0) y0 = y;
			if (x > x1) x1 = x;
			if (y > y1) y1 = y;
		}
	printf("%-8s blue %d green %d orange %d other %d", what, blue, green, orange, other);
	if (x1 >= 0)
		printf(", non-blue in x %d..%d y %d..%d", x0, x1, y0, y1);
	if (odd)
		printf(", first other rgba %d,%d,%d,%d", odd[0], odd[1], odd[2], odd[3]);
	printf(", glGetError 0x%x\n", glGetError());
}

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
		glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, N, N);
		glGenFramebuffers(1, &fb);
		glBindFramebuffer(GL_FRAMEBUFFER, fb);
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
		printf("framebuffer status 0x%x\n", glCheckFramebufferStatus(GL_FRAMEBUFFER));

		GLuint prog = glCreateProgram();
		glAttachShader(prog, shader(GL_VERTEX_SHADER,
			"attribute vec2 p; void main() { gl_Position = vec4(p, 0.0, 1.0); }"));
		glAttachShader(prog, shader(GL_FRAGMENT_SHADER,
			"precision mediump float; void main() { gl_FragColor = vec4(1.0, 0.5, 0.0, 1.0); }"));
		glBindAttribLocation(prog, 0, "p");
		glLinkProgram(prog);
		GLint ok = 0;
		glGetProgramiv(prog, GL_LINK_STATUS, &ok);
		printf("program link: %s\n", ok ? "OK" : "failed");

		static const GLfloat tri[] = { 0.0f, 0.9f, -0.9f, -0.9f, 0.9f, -0.9f };
		static const GLushort idx[] = { 0, 1, 2 };
		glViewport(0, 0, N, N);

		glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		report("clear");

		glEnable(GL_SCISSOR_TEST);
		glScissor(16, 16, 32, 32);
		glClearColor(0.0f, 1.0f, 0.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		glDisable(GL_SCISSOR_TEST);
		report("scissor");

		glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		glUseProgram(prog);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, tri);
		glEnableVertexAttribArray(0);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		report("client");

		GLuint vbo, ibo;
		glGenBuffers(1, &vbo);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, sizeof tri, tri, GL_STATIC_DRAW);
		glClear(GL_COLOR_BUFFER_BIT);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		report("vbo");

		glGenBuffers(1, &ibo);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof idx, idx, GL_STATIC_DRAW);
		glClear(GL_COLOR_BUFFER_BIT);
		glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_SHORT, 0);
		report("elements");
		return 0;
	}
}
