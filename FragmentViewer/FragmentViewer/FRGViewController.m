//
//  FRGViewController.m
//  FragmentViewer
//
//  Created by Andrei Ostanin on 8/12/14.
//  Copyright (c) 2014 Andrei Ostanin. All rights reserved.
//

#import "FRGViewController.h"
#import <AFNetworking.h>
#import <AFNetworking/UIImageView+AFNetworking.h>

@interface FRGViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *imageView1;
@property (weak, nonatomic) IBOutlet UIImageView *imageView2;

@property (strong, nonatomic) NSArray *imageURLs;

@property (strong, nonatomic) NSTimer *updateTimer;
@property (strong, nonatomic) NSTimer *nextImageTimer;
@end

@implementation FRGViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(updateTimerFired) userInfo:nil repeats:YES];
    self.nextImageTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(nextImageTimerFired) userInfo:nil repeats:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateTimerFired];
}

- (void)updateTimerFired
{
    NSURL *url = [NSURL URLWithString:@"http://169.254.121.73:3000/api/fragments.json"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    operation.responseSerializer = [AFJSONResponseSerializer serializer];

    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        self.imageURLs = responseObject[@"fragments"];
        if (self.imageView1.image == nil && self.imageView2.image == nil) {
            [self nextImageTimerFired];
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Failed with error: %@", error);
    }];

    [operation start];
}

- (void)nextImageTimerFired
{
    if (self.imageURLs.count == 0) {
        return;
    }

    NSUInteger i = arc4random() % self.imageURLs.count;

    UIImageView *activeImageView = self.imageView1.hidden ? self.imageView1 : self.imageView2;
    UIImageView *inactiveImageView = self.imageView1.hidden ? self.imageView2 : self.imageView1;

    activeImageView.alpha = 0;
    activeImageView.hidden = NO;

    [activeImageView setImageWithURL:[NSURL URLWithString:self.imageURLs[i]]];
    [inactiveImageView setImage:nil];

    [UIView animateWithDuration:1 animations:^{
        activeImageView.alpha = 1;
        inactiveImageView.alpha = 0;
    } completion:^(BOOL finished) {
        inactiveImageView.hidden = YES;
    }];
}

@end
