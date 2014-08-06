//
//  FRGViewController.m
//  myfragmentapp
//
//  Created by Andrei Ostanin on 8/3/14.
//  Copyright (c) 2014 Andrei Ostanin. All rights reserved.
//

#import "FRGViewController.h"
#import <GLKit/GLKit.h>
#import <MBProgressHUD.h>
#import <SRWebSocket.h>
#include <arpa/inet.h>
#include "lz4.h"

@interface FRGViewController () <GLKViewDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate, SRWebSocketDelegate>

@property (weak, nonatomic) IBOutlet GLKView *glView;
@property (weak, nonatomic) IBOutlet UILabel *countdownLabel;
@property (weak, nonatomic) IBOutlet UIView *flashView;

@property (assign, nonatomic) GLuint depthTexture;

@property (strong, nonatomic) NSNetServiceBrowser *kinectWebSocketServiceBrowser;
@property (strong, nonatomic) NSNetService *kinectWebSocketService;
@property (strong, nonatomic) SRWebSocket *webSocket;

@end

@implementation FRGViewController
            
- (void)viewDidLoad {
    [super viewDidLoad];

    self.kinectWebSocketServiceBrowser = [[NSNetServiceBrowser alloc] init];
    self.kinectWebSocketServiceBrowser.delegate = self;

    self.glView.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self searchForServers];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    [self.glView setNeedsDisplay];
}

#pragma mark - Actions

- (IBAction)viewTapped:(id)sender
{
    NSLog(@"TAP!");

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

- (void)updateDepthTextureWithData:(NSData *)data
{
    glGenTextures(1, &_depthTexture);
    glBindTexture(GL_TEXTURE_2D, self.depthTexture);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, 640, 480, 0, GL_LUMINANCE, GL_UNSIGNED_SHORT, data.bytes);
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

    [self searchForServers];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    NSLog(@"Socket closed with code %ld reason: %@", (long)code, reason);

    [MBProgressHUD hideHUDForView:self.view animated:NO];
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.mode = MBProgressHUDModeText;
    hud.labelText = @"Connection to server closed!";
    [hud hide:YES afterDelay:2];

    [self searchForServers];
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
    NSUInteger originalSize = 640 * 480 * sizeof(uint16_t);
    char *buffer = malloc(originalSize);
    if (LZ4_decompress_fast(data.bytes, buffer, originalSize) < 0) {
        NSLog(@"Decompression error!");
    }
    NSData *originalData = [NSData dataWithBytesNoCopy:buffer length:originalSize];
    uncompressedByteCount += originalData.length;

    messageCount++;
    byteCount += data.length;
    if (messageCount >= 60) {
        NSTimeInterval timeInterval = -[date timeIntervalSinceNow];
        NSLog(@"%ld messages in %f seconds: %f messages/sec", messageCount, timeInterval, messageCount / timeInterval);
        NSLog(@"%ld bytes in %f seconds: %f kB/s", byteCount, timeInterval, byteCount / timeInterval / 1024.0);
        NSLog(@"%ld bytes uncompressed into %ld bytes giving a %f%% compression", byteCount, uncompressedByteCount, 100.0 * uncompressedByteCount / (CGFloat)byteCount);
        messageCount = 0;
        byteCount = 0;
        uncompressedByteCount = 0;
        date = [NSDate date];
    }
}

#pragma mark - Net service delegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    if (sender.addresses == 0) {
        [self searchForServers];
        return;
    }

    struct sockaddr_in *socketAddress = (struct sockaddr_in *)[sender.addresses[0] bytes];
    NSString *addressString = [NSString stringWithCString:inet_ntoa(socketAddress->sin_addr) encoding:NSUTF8StringEncoding];

    [self connectToServerWithHost:addressString port:sender.port];
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    NSLog(@"Failed to resolve server");
    [self searchForServers];
}

#pragma mark - Net service browser delegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing
{
    [aNetServiceBrowser stop];

    self.kinectWebSocketService = aNetService;
    self.kinectWebSocketService.delegate = self;
    [self.kinectWebSocketService resolveWithTimeout:5];
}

#pragma mark - GLKView delegate

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClearColor(0.8f, 0.8f, 0.8f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

@end
