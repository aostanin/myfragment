//
//  FRGViewController.m
//  myfragmentapp
//
//  Created by Andrei Ostanin on 8/3/14.
//  Copyright (c) 2014 Andrei Ostanin. All rights reserved.
//

#import "FRGViewController.h"
#import <Accelerate/Accelerate.h>
#import <MBProgressHUD.h>
#import <SRWebSocket.h>

#include <arpa/inet.h>
#include "lz4.h"

static const GLsizei kDepthWidth  = 320;
static const GLsizei kDepthHeight = 240;

static const GLfloat kVertices[] = {
     1, -1,  1,
     1,  1,  1,
    -1,  1,  1,
    -1, -1,  1
};

static const GLubyte kIndices[] = {
    0, 1, 2,
    2, 3, 0
};

@interface FRGViewController () <GLKViewControllerDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate, SRWebSocketDelegate>

@property (weak, nonatomic) IBOutlet UILabel *countdownLabel;
@property (weak, nonatomic) IBOutlet UIView *flashView;

@property (assign, nonatomic) GLuint programObject;
@property (assign, nonatomic) GLuint vertexArray;
@property (assign, nonatomic) GLuint depthTexture;
@property (assign, nonatomic) GLuint depthTextureUniform;

@property (strong, nonatomic) NSNetServiceBrowser *kinectWebSocketServiceBrowser;
@property (strong, nonatomic) NSNetService *kinectWebSocketService;
@property (strong, nonatomic) SRWebSocket *webSocket;

@end

@implementation FRGViewController
            
- (void)viewDidLoad {
    [super viewDidLoad];

    self.kinectWebSocketServiceBrowser = [[NSNetServiceBrowser alloc] init];
    self.kinectWebSocketServiceBrowser.delegate = self;

    self.preferredFramesPerSecond = 30;

    GLKView *glView = (GLKView *)self.view;
    glView.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    [self initializeOpenGL];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self searchForServers];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    [self updateScreenSize];
}

#pragma mark - Actions

- (IBAction)viewTapped:(id)sender
{
    self.countdownLabel.text = @"3";
    self.countdownLabel.hidden = NO;
    self.countdownLabel.alpha = 0;
    [self.countdownLabel layoutIfNeeded];
    [UIView animateWithDuration:1 animations:^{
        self.countdownLabel.alpha = 1;
    } completion:^(BOOL firstFinished) {
        self.countdownLabel.text = @"2";
        self.countdownLabel.alpha = 0;
        [self.countdownLabel layoutIfNeeded];
        [UIView animateWithDuration:1 animations:^{
            self.countdownLabel.alpha = 1;
        } completion:^(BOOL secondFinished) {
            self.countdownLabel.text = @"1";
            self.countdownLabel.alpha = 0;
            [self.countdownLabel layoutIfNeeded];
            [UIView animateWithDuration:1 animations:^{
                self.countdownLabel.alpha = 1;
            } completion:^(BOOL thirdFinished) {
                self.countdownLabel.hidden = YES;
                [self capture];
            }];
        }];
    }];
}

#pragma mark - Capture

- (void)capture
{
    self.flashView.hidden = NO;
    self.flashView.alpha = 0;
    [UIView animateWithDuration:0.125 animations:^{
        self.flashView.alpha = 1;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.125 animations:^{
            self.flashView.alpha = 0;
        } completion:^(BOOL finished) {
            self.flashView.hidden = YES;
        }];
    }];
}

#pragma mark - Server

- (void)searchForServers
{
    [self.kinectWebSocketServiceBrowser searchForServicesOfType:@"_kinect-ws._tcp." inDomain:@"local."];

    [MBProgressHUD hideHUDForView:self.view animated:NO];
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.labelText = @"Searching for server...";
}

- (void)connectToServerWithHost:(NSString *)host port:(NSUInteger)port
{
    [self.webSocket close];

    self.webSocket = [[SRWebSocket alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"ws://%@:%ld", host, (unsigned long)port]]];
    self.webSocket.delegate = self;
    [self.webSocket open];

    [MBProgressHUD hideHUDForView:self.view animated:NO];
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:NO];
    hud.labelText = @"Connecting to server...";
}

#pragma mark - Graphics

- (GLuint)loadShaderWithSource:(NSString *)shaderSource type:(GLenum)type
{
    GLuint shader = glCreateShader(type);
    GLint compiled;

    if (!shader)
        return 0;

    const char *source = shaderSource.UTF8String;
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);

    if (!compiled) {
        GLint infoLength;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infoLength);

        if (infoLength > 0) {
            char *infoLog = malloc(infoLength);
            glGetShaderInfoLog(shader, infoLength, NULL, infoLog);
            NSLog(@"Failed compiling shader:\n%s", infoLog);
            free(infoLog);
        }

        glDeleteShader(shader);
        return 0;
    }

    return shader;
}

- (GLuint)compileAndLinkProgramWithVertexShaderPath:(NSString *)vertexShaderPath fragmentShaderPath:(NSString *)fragmentShaderPath
{
    NSString *vertexShaderSource = [NSString stringWithContentsOfFile:vertexShaderPath encoding:NSUTF8StringEncoding error:nil];
    NSString *fragmentShaderSource = [NSString stringWithContentsOfFile:fragmentShaderPath encoding:NSUTF8StringEncoding error:nil];

    GLuint vertexShader = [self loadShaderWithSource:vertexShaderSource type:GL_VERTEX_SHADER];
    GLuint fragmentShader = [self loadShaderWithSource:fragmentShaderSource type:GL_FRAGMENT_SHADER];

    GLuint programObject = glCreateProgram();
    glAttachShader(programObject, vertexShader);
    glAttachShader(programObject, fragmentShader);

    glBindAttribLocation(programObject, GLKVertexAttribPosition, "position");

    GLint linked;
    glLinkProgram(programObject);
    glGetProgramiv(programObject, GL_LINK_STATUS, &linked);

    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);

    if (!linked) {
        GLint infoLength;
        glGetProgramiv(programObject, GL_INFO_LOG_LENGTH, &infoLength);

        if (infoLength > 0) {
            char *infoLog = malloc(infoLength);
            glGetProgramInfoLog(shadow, infoLength, NULL, infoLog);
            NSLog(@"Failed linking program:\n%s", infoLog);
            free(infoLog);
        }

        glDeleteShader(programObject);
        return 0;
    }

    return programObject;
}

- (void)initializeOpenGL
{
    GLKView *glView = (GLKView *)self.view;
    [EAGLContext setCurrentContext:glView.context];

    self.programObject = [self compileAndLinkProgramWithVertexShaderPath:[[NSBundle mainBundle] pathForResource:@"shader" ofType:@"vert"] fragmentShaderPath:[[NSBundle mainBundle] pathForResource:@"shader" ofType:@"frag"]];

    if (!self.programObject)
        return;

    glClearColor(0.8f, 0.8f, 1.0f, 1.0f);

    glGenVertexArraysOES(1, &_vertexArray);
    glBindVertexArrayOES(self.vertexArray);

    GLuint vertexBuffer;
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(kVertices), kVertices, GL_STATIC_DRAW);

    GLuint indexBuffer;
    glGenBuffers(1, &indexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(kIndices), kIndices, GL_STATIC_DRAW);

    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 0, 0);

    glBindVertexArrayOES(0);

    glUseProgram(self.programObject);

    self.depthTextureUniform = glGetUniformLocation(self.programObject, "depthTexture");
}

- (void)updateScreenSize
{
    GLint screenSize = glGetUniformLocation(self.programObject, "screenSize");
    if (screenSize >= 0) {
        CGFloat scale = [UIScreen mainScreen].scale;
        glUniform2f(screenSize, self.view.bounds.size.width * scale, self.view.bounds.size.height * scale);
    }
}

- (void)updateDepthTextureWithData:(NSData *)data
{
    static GLfloat *correctedData = NULL;
    static GLfloat divide = (GLfloat)((1 << 11) - 1);
    if (!correctedData) {
        correctedData = malloc(kDepthWidth * kDepthHeight * sizeof(GLfloat));
    }

    vDSP_vfltu16(data.bytes, 1, correctedData, 1, kDepthWidth * kDepthHeight);
    vDSP_vsdiv(correctedData, 1, &divide, correctedData, 1, kDepthWidth * kDepthHeight);

    if (self.depthTexture == 0) {
        glGenTextures(1, &_depthTexture);
        glBindTexture(GL_TEXTURE_2D, self.depthTexture);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        // Needed for NPOT textures
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, kDepthWidth, kDepthHeight, 0, GL_LUMINANCE, GL_FLOAT, correctedData);
    } else {
        glBindTexture(GL_TEXTURE_2D, self.depthTexture);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, kDepthWidth, kDepthHeight, GL_LUMINANCE, GL_FLOAT, correctedData);
    }
}

#pragma mark - Web socket delegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    NSLog(@"Socket open");

    [MBProgressHUD hideHUDForView:self.view animated:NO];
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.mode = MBProgressHUDModeText;
    hud.labelText = @"Connected to server!";
    [hud hide:YES afterDelay:2];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    NSLog(@"Socket error: %@", error);

    [MBProgressHUD hideHUDForView:self.view animated:NO];
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.mode = MBProgressHUDModeText;
    hud.labelText = @"Failed to connect to server!";
    [hud hide:YES afterDelay:2];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self searchForServers];
    });
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    NSLog(@"Socket closed with code %ld reason: %@", (long)code, reason);

    [MBProgressHUD hideHUDForView:self.view animated:NO];
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.mode = MBProgressHUDModeText;
    hud.labelText = @"Connection to server closed!";
    [hud hide:YES afterDelay:2];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self searchForServers];
    });
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message
{
    static unsigned long messageCount = 0;
    static unsigned long byteCount = 0;
    static unsigned long uncompressedByteCount = 0;
    static NSDate *date = nil;

    if (!date)
        date = [NSDate date];

    NSData *data = message;
    int originalSize = kDepthWidth * kDepthHeight * sizeof(uint16_t);
    uncompressedByteCount += originalSize;

    messageCount++;
    byteCount += data.length;
    if (messageCount >= 120) {
        NSTimeInterval timeInterval = -[date timeIntervalSinceNow];
        NSLog(@"%ld messages in %f seconds: %f messages/sec", messageCount, timeInterval, messageCount / timeInterval);
        NSLog(@"%ld bytes in %f seconds: %f kB/s", byteCount, timeInterval, byteCount / timeInterval / 1024.0);
        NSLog(@"%ld bytes uncompressed into %ld bytes giving a %f%% compression", byteCount, uncompressedByteCount, 100.0 * byteCount / (CGFloat)uncompressedByteCount);
        messageCount = 0;
        byteCount = 0;
        uncompressedByteCount = 0;
        date = [NSDate date];
    }

    static char *buffer = NULL;
    if (buffer == NULL)
        buffer = malloc(originalSize);
    NSData *originalData = [NSData dataWithBytesNoCopy:buffer length:originalSize freeWhenDone:NO];
    if (LZ4_decompress_fast(data.bytes, buffer, originalSize) < 0) {
        NSLog(@"Decompression error!");
        return;
    }

    [self updateDepthTextureWithData:originalData];
}

#pragma mark - Net service delegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    if (sender.addresses == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self searchForServers];
        });
        return;
    }

    struct sockaddr_in *socketAddress = (struct sockaddr_in *)[sender.addresses[0] bytes];
    NSString *addressString = [NSString stringWithCString:inet_ntoa(socketAddress->sin_addr) encoding:NSUTF8StringEncoding];

    [self connectToServerWithHost:addressString port:sender.port];
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    NSLog(@"Failed to resolve server");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self searchForServers];
    });
}

#pragma mark - Net service browser delegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing
{
    [aNetServiceBrowser stop];

    self.kinectWebSocketService = aNetService;
    self.kinectWebSocketService.delegate = self;
    [self.kinectWebSocketService resolveWithTimeout:5];
}

#pragma mark - GLKViewController delegate

- (void)glkViewControllerUpdate:(GLKViewController *)controller
{
    NSLog(@"UPDATE");
}

#pragma mark - GLKView delegate

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT);

    if (self.depthTexture > 0) {
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, self.depthTexture);
        glUniform1i(self.depthTextureUniform, 0);
    }

    glBindVertexArrayOES(self.vertexArray);
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_BYTE, 0);
}

@end
