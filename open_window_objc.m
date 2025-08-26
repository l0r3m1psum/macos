#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>
#import <CoreVideo/CVDisplayLink.h>
#include <stdio.h>

/*

# Simple cross platform graphics

https://github.com/zserge/fenster
https://github.com/samizzo/pixie
https://github.com/ColleagueRiley/RGFW
https://medium.com/@colleagueriley/rgfw-under-the-hood-software-rendering-82f54a6da419
*/

/* Resources:
 *   + OpenGL:
 *     - https://github.com/beelsebob/Cocoa-GL-Tutorial
 *     - https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_intro/opengl_intro.html
 *   + Metal:
 *     - https://developer.apple.com/documentation/metal/mtlcommandbuffer/present(_:)?language=objc
 *     - https://developer.apple.com/documentation/QuartzCore/CAMetalLayer?language=objc
 *   + Cocoa
 *     - https://leopard-adc.pepas.com/documentation/Cocoa/Conceptual/WinPanel/WinPanel.html
 */

// TODO: do it with MTKView

#define countof(a) (sizeof (a) / sizeof *(a))

#define kFailedToInitialiseGLException @"Failed to initialise OpenGL"

typedef struct {
	GLfloat x,y;
} Vector2;

typedef struct {
	GLfloat x,y,z,w;
} Vector4;

typedef struct {
	GLfloat r,g,b,a;
} Colour;

typedef struct {
	Vector4 position;
	Colour colour;
} Vertex;

static const GLchar fragmentShaderSource[] =
	"#version 150\n"
	"\n"
	"in vec4 colourV;\n"
	"out vec4 fragColour;\n"
	"\n"
	"void main(void) {\n"
	"\tfragColour = colourV;\n"
	"}\n"
;

static const GLchar vertexShaderSource[] =
	"#version 150\n"
	"\n"
	"uniform vec2 p;\n"
	"\n"
	"in vec4 position;\n"
	"in vec4 colour;\n"
	"\n"
	"out vec4 colourV;\n"
	"\n"
	"void main (void) {\n"
	"\tcolourV = colour;\n"
	"\tgl_Position = vec4(p, 0.0, 0.0) + position;\n"
	"}\n"
;

static void
validateProgram(GLuint program) {
	GLint logLength;

	glValidateProgram(program);
	glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength) {
		GLchar *log = malloc(logLength);
		if (log) {
			glGetProgramInfoLog(program, logLength, &logLength, log);
			NSLog(@"Program validation produced errors:\n%s", log);
		}
		free(log);
	}

	GLint status;
	glGetProgramiv(program, GL_VALIDATE_STATUS, &status);
	if (0 == status) {
		[NSException raise:kFailedToInitialiseGLException format:@"Failed to link shader program"];
	}
}

typedef struct DisplayCallbackContext DisplayCallbackContext;
struct DisplayCallbackContext {
	NSOpenGLContext *openGLContext;
	GLint positionUniform;
	GLuint shaderProgram;
};

static CVReturn
displayCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext) {
	DisplayCallbackContext *ctx = displayLinkContext;

	CVTimeStamp time = *inOutputTime;

	[ctx->openGLContext makeCurrentContext];

	glClearColor(0.0, 0.0, 0.0, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);

	glUseProgram(ctx->shaderProgram);

	GLfloat timeValue = (GLfloat)(time.videoTime) / (GLfloat)(time.videoTimeScale);
	Vector2 p = { .x = 0.5f * sinf(timeValue), .y = 0.5f * cosf(timeValue) };
	glUniform2fv(ctx->positionUniform, 1, (const GLfloat *)&p);

	glDrawArrays(GL_TRIANGLE_FAN, 0, 4);

	[ctx->openGLContext flushBuffer];

	return kCVReturnSuccess;
}

#include <CoreGraphics/CoreGraphics.h>

@interface CustomNSView : NSView {
	@public void* dataPtr_;
	CGContextRef backBuffer_;
}
@end

@implementation CustomNSView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame: frameRect];
	if (self) {
		int width = frameRect.size.width;
		int height = frameRect.size.height;
		int rowBytes = 4 * width;
		dataPtr_ = calloc(1, rowBytes * height);

		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

		backBuffer_ = CGBitmapContextCreate(dataPtr_, width, height, 8, rowBytes, colorSpace, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
		CGColorSpaceRelease(colorSpace);
	}
	return self;
}

- (void)drawRect:(NSRect)dirtyRect {
	CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
	CGImageRef backImage = CGBitmapContextCreateImage(backBuffer_);
	CGContextDrawImage(ctx, self.frame, backImage);
	CGImageRelease(backImage);
}

- (void)dealloc {
	free(dataPtr_);
	CGContextRelease(backBuffer_);
	[super dealloc];
}
@end

static CVReturn
renderCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext) {
	uint32_t *bitmap = (uint32_t*)((CustomNSView *) displayLinkContext)->dataPtr_;
	int width = [(CustomNSView *) displayLinkContext frame].size.width,
		height = [(CustomNSView *) displayLinkContext frame].size.height;

	static int xOffset = 0;
	for (int y=0; y < height; ++y) {
		for (int x=0; x < width; ++x) {
			uint8_t blue = x + xOffset;
			uint8_t green = y;
			*bitmap++ = ((green << 16) | blue << 8);
		}
	}
	xOffset++;
	dispatch_sync(dispatch_get_main_queue(), ^{
		[(__bridge CustomNSView *) displayLinkContext setNeedsDisplay:YES];
	});
	return kCVReturnSuccess;
}

bool shouldQuit;

@interface WindowDelegate : NSObject<NSWindowDelegate>
@end

@implementation WindowDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender {
	shouldQuit = true;
	return YES;
}
@end

static CFAllocatorRef sJemallocAllocator;

static void *
logging_malloc(CFIndex allocSize, CFOptionFlags hint, void *info) {
	void *res = malloc(allocSize);
	printf("%p = malloc(%ld)\n", res, allocSize);
    return res;
}

static void *
logging_realloc(void *ptr, CFIndex newsize, CFOptionFlags hint, void *info) {
	void *res =realloc(ptr, newsize);
	printf("%p = realloc(%p, %ld)\n", res, ptr, newsize);
    return res;
}

static void
logging_free(void *ptr, void *info) {
    free(ptr);
    printf("free(%p)\n", ptr);
}

static CFIndex
FFOContextPreferredSize(CFIndex size, CFOptionFlags hint, void *info) {
    // Round up to the next multiple of 16 to copy what jemalloc does it allocates, since it's 16-byte aligned
    NSInteger remainder = size & 0xFF; // remainder = size % 16
    if (remainder == 0) {
        return size;
    }
    return size + 16 - remainder;
}

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface NSObject (AllocationLogging)

@end

@implementation NSObject (AllocationLogging)

static id (*original_allocWithZone)(Class, SEL, struct _NSZone *);
static void (*original_dealloc)(id, SEL);

+ (id)logged_allocWithZone:(struct _NSZone *)zone {
    NSLog(@"+[ALLOC] Allocating instance of class: %@", NSStringFromClass(self));
    return original_allocWithZone(self, @selector(allocWithZone:), zone);
}

- (void)logged_dealloc {
    NSLog(@"-[DEALLOC] Deallocating instance of class: %@", NSStringFromClass([self class]));
    original_dealloc(self, @selector(dealloc));
}

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = object_getClass((id)self);
        SEL allocSelector = @selector(allocWithZone:);
        SEL loggedAllocSelector = @selector(logged_allocWithZone:);

        Method originalAllocMethod = class_getClassMethod(class, allocSelector);
        Method loggedAllocMethod = class_getClassMethod(class, loggedAllocSelector);

        original_allocWithZone = (void *)method_getImplementation(originalAllocMethod);
        method_setImplementation(originalAllocMethod, method_getImplementation(loggedAllocMethod));

        // Note: We swizzle dealloc on the base NSObject class, not its metaclass.
        Class baseClass = [NSObject class];
        SEL deallocSelector = @selector(dealloc);
        SEL loggedDeallocSelector = @selector(logged_dealloc);

        Method originalDeallocMethod = class_getInstanceMethod(baseClass, deallocSelector);
        Method loggedDeallocMethod = class_getInstanceMethod(baseClass, loggedDeallocSelector);

        original_dealloc = (void *)method_getImplementation(originalDeallocMethod);
        method_setImplementation(originalDeallocMethod, method_getImplementation(loggedDeallocMethod));
    });
}
@end

// https://stackoverflow.com/a/8154048
// https://developer.apple.com/library/archive/documentation/General/Conceptual/CocoaEncyclopedia/Toll-FreeBridgin/Toll-FreeBridgin.html
// https://www.mikeash.com/pyblog/friday-qa-2010-12-17-custom-object-allocators-in-objective-c.html
// https://www.mikeash.com/pyblog/friday-qa-2014-11-07-lets-build-nszombie.html
// https://defagos.github.io/yet_another_article_about_method_swizzling/
// https://stackoverflow.com/questions/21121032/dealloc-and-arc


// TODO: test malloc_zone
// https://stackoverflow.com/a/77157482
// https://flylib.com/books/en/3.126.1.98/1/
// https://issues.chromium.org/issues/40507007
// https://searchfox.org/firefox-main/rev/e2cbda2dd0f622553b5c825f319832db4863f6a4/memory/build/Zone.c

int main() {
	CFAllocatorContext sJemallocContext = {
		.version = 0,
		.info = NULL,
		.retain = NULL,
		.release = NULL,
		.copyDescription = NULL,
		.allocate = logging_malloc,
		.reallocate = logging_realloc,
		.deallocate = logging_free,
		.preferredSize = FFOContextPreferredSize,
	};
	CFAllocatorCreate(kCFAllocatorUseContext, &sJemallocContext);

	[NSApplication sharedApplication];
	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	NSWindow *window = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(0, 0, 320, 240)
		styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
		backing:NSBackingStoreBuffered
		defer:NO];

	WindowDelegate *windowDelegate = [[WindowDelegate alloc] init];
	[window setDelegate:windowDelegate];

	[window setTitle:@"Hello, Cocoa"];
	[window makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];

	{
		NSView *customView = [[[CustomNSView alloc] initWithFrame:[[window contentView] bounds]] autorelease];
		[[window contentView] addSubview:customView];

		CGDirectDisplayID displayID = CGMainDisplayID();
		CVReturn error = kCVReturnSuccess;
		CVDisplayLinkRef displayLink = NULL;
		error = CVDisplayLinkCreateWithCGDisplay(displayID, &displayLink);
		if (error) {
			NSLog(@"DisplayLink created with error:%d", error);
			displayLink = NULL;
		}
		CVDisplayLinkSetOutputCallback(displayLink, renderCallback, customView);
		CVDisplayLinkStart(displayLink);
	}

	if (false)
	{
		NSOpenGLPixelFormatAttribute pixelFormatAttributes[] = {
			NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
			NSOpenGLPFAColorSize    , 24                           ,
			NSOpenGLPFAAlphaSize    , 8                            ,
			NSOpenGLPFADoubleBuffer ,
			NSOpenGLPFAAccelerated  ,
			NSOpenGLPFANoRecovery   ,
			0
		};
		NSOpenGLPixelFormat *pixelFormat = [[[NSOpenGLPixelFormat alloc] initWithAttributes:pixelFormatAttributes] autorelease];
		NSOpenGLView *openGLView = [[[NSOpenGLView alloc] initWithFrame:[[window contentView] bounds] pixelFormat:pixelFormat] autorelease];
		[[window contentView] addSubview:openGLView];

		[[openGLView openGLContext] makeCurrentContext];

		GLuint shaders[2] = {0};
		const GLchar *shaderSources[2] = {vertexShaderSource, fragmentShaderSource};
		GLenum shaderTypes[2] = {GL_VERTEX_SHADER, GL_FRAGMENT_SHADER};

		for (size_t i = 0; i < countof(shaders); i++) {
			GLenum type = shaderTypes[i];
			const GLchar *source = shaderSources[i];
			GLuint shader = glCreateShader(type);
			glShaderSource(shader, 1, &source, NULL);
			glCompileShader(shader);

			GLint logLength;

			glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
			if (logLength) {
				GLchar *log = malloc((size_t)logLength);
				glGetShaderInfoLog(shader, logLength, &logLength, log);
				NSLog(@"Shader compilation failed with error:\n%s", log);
				free(log);
			}

			GLint status;
			glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
			if (0 == status) {
				glDeleteShader(shader);
				[NSException raise:kFailedToInitialiseGLException format:@"Shader compilation failed for file %s", source];
			}

			shaders[i] = shader;
		}

		GLuint vertexShader = shaders[0];
		GLuint fragmentShader = shaders[1];

		GLuint shaderProgram = glCreateProgram();

		glAttachShader(shaderProgram, vertexShader);
		glAttachShader(shaderProgram, fragmentShader);

		glBindFragDataLocation(shaderProgram, 0, "fragColour");

		glLinkProgram(shaderProgram);


		{
			GLint logLength;

			glGetProgramiv(shaderProgram, GL_INFO_LOG_LENGTH, &logLength);
			if (logLength) {
				GLchar *log = malloc(logLength);
				glGetProgramInfoLog(shaderProgram, logLength, &logLength, log);
				NSLog(@"Shader shaderProgram linking failed with error:\n%s", log);
				free(log);
			}

			GLint status;
			glGetProgramiv(shaderProgram, GL_LINK_STATUS, &status);
			if (!status) {
				[NSException raise:kFailedToInitialiseGLException format:@"Failed to link shader program"];
			}
		}

		GLint positionUniform = glGetUniformLocation(shaderProgram, "p");
		GLint colourAttribute = glGetAttribLocation(shaderProgram, "colour");
		GLint positionAttribute = glGetAttribLocation(shaderProgram, "position");

		glDeleteShader(vertexShader);
		glDeleteShader(fragmentShader);

		Vertex vertexData[4] = {
			{ .position = { .x=-0.5, .y=-0.5, .z=0.0, .w=1.0 }, .colour = { .r=1.0, .g=0.0, .b=0.0, .a=1.0 } },
			{ .position = { .x=-0.5, .y= 0.5, .z=0.0, .w=1.0 }, .colour = { .r=0.0, .g=1.0, .b=0.0, .a=1.0 } },
			{ .position = { .x= 0.5, .y= 0.5, .z=0.0, .w=1.0 }, .colour = { .r=0.0, .g=0.0, .b=1.0, .a=1.0 } },
			{ .position = { .x= 0.5, .y=-0.5, .z=0.0, .w=1.0 }, .colour = { .r=1.0, .g=1.0, .b=1.0, .a=1.0 } }
		};

		GLuint vertexArrayObject;
		glGenVertexArrays(1, &vertexArrayObject);
		glBindVertexArray(vertexArrayObject);

		GLuint vertexBuffer;
		glGenBuffers(1, &vertexBuffer);
		glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
		glBufferData(GL_ARRAY_BUFFER, 4 * sizeof(Vertex), vertexData, GL_STATIC_DRAW);

		glEnableVertexAttribArray(positionAttribute);
		glEnableVertexAttribArray(colourAttribute);
		glVertexAttribPointer(positionAttribute, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (const GLvoid *)offsetof(Vertex, position));
		glVertexAttribPointer(colourAttribute  , 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (const GLvoid *)offsetof(Vertex, colour  ));

		{
			GLenum err = GL_NO_ERROR;
			while ((err = glGetError()) != GL_NO_ERROR) {
				switch (err) { \
					case GL_INVALID_ENUM:      printf("%s\n", "GL_INVALID_ENUM"     ); break;
					case GL_INVALID_VALUE:     printf("%s\n", "GL_INVALID_VALUE"    ); break;
					case GL_INVALID_OPERATION: printf("%s\n", "GL_INVALID_OPERATION"); break;
					case GL_OUT_OF_MEMORY:     printf("%s\n", "GL_OUT_OF_MEMORY"    ); break;
					default:                                                           break;
				}
				if (err != GL_NO_ERROR) {
					return 1;
				}
			}
		}

		CVDisplayLinkRef displayLink = NULL;
		CGDirectDisplayID displayID = CGMainDisplayID();
		CVReturn error = CVDisplayLinkCreateWithCGDisplay(displayID, &displayLink);

		if (kCVReturnSuccess == error) {
			DisplayCallbackContext ctx = {
				.openGLContext = [openGLView openGLContext],
				.positionUniform = positionUniform,
				.shaderProgram = shaderProgram,
			};
			CVDisplayLinkSetOutputCallback(displayLink, displayCallback, &ctx);
			CVDisplayLinkStart(displayLink);
		} else {
			NSLog(@"Display Link created with error: %d", error);
		}
	}

	[NSApp finishLaunching];

	NSEvent *event = nil;
	NSDate *distantPast = [NSDate distantPast];

	while (!shouldQuit) {
		while ((event = [NSApp
				nextEventMatchingMask:NSEventMaskAny
				untilDate:distantPast
				inMode:NSDefaultRunLoopMode
				dequeue:YES])) {

			// NSLog(@"%@\n", event);

			switch ([event type]) {
			default:
				[NSApp sendEvent: event];
			}
		}

		// If we did not use CVDisplayLink rendering code should go here.
	}

	return 0;
}
