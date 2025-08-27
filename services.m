#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <os/log.h>

@interface EncodeDecodeServiceProvider : NSObject

- (void)encode:(NSPasteboard *)pasteboard
      userData:(NSString *)userData
         error:(NSString **)error;

- (void)decode:(NSPasteboard *)pasteboard
      userData:(NSString *)userData
         error:(NSString **)error;

@end

@implementation EncodeDecodeServiceProvider

- (void)encode:(NSPasteboard *)pasteboard
      userData:(NSString *)userData
         error:(NSString **)error {

    NSString *string = [pasteboard stringForType:NSPasteboardTypeString];
    os_log(OS_LOG_DEFAULT, "userData: %@", userData);
    os_log(OS_LOG_DEFAULT, "string: %@", string);

    [pasteboard clearContents];
    [pasteboard setString:@"a" forType:NSPasteboardTypeString];
}

- (void)decode:(NSPasteboard *)pasteboard
      userData:(NSString *)userData
         error:(NSString **)error {

    NSString *string = [pasteboard stringForType:NSPasteboardTypeString];

    [pasteboard clearContents];
    [pasteboard setString:@"b" forType:NSPasteboardTypeString];
}

@end

// https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/introduction.html

// Foundation tool is how Apple referred to command line applications
// https://discussions.apple.com/thread/2465930?answerId=11694763022

// https://www.notesfromandy.com/2013/04/05/writing-a-service-bundle

// Store it in ~/Library/Services
int main(void) {
    id serviceProvider = [[EncodeDecodeServiceProvider alloc] init];
    NSRegisterServicesProvider(serviceProvider, @"EncodeDecode");
    [[NSRunLoop currentRunLoop] run];
    return 0;
}
