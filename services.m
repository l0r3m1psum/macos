#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

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
    if (!string) {
        return;
    }

    [pasteboard clearContents];
    [pasteboard setString:@"a" forType:NSPasteboardTypeString];
}

- (void)decode:(NSPasteboard *)pasteboard
      userData:(NSString *)userData
         error:(NSString **)error {

    NSString *string = [pasteboard stringForType:NSPasteboardTypeString];
    if (!string) {
        return;
    }

    [pasteboard clearContents];
    [pasteboard setString:@"b" forType:NSPasteboardTypeString];
}

@end

int main(void) {
    [NSApplication sharedApplication].servicesProvider = [[EncodeDecodeServiceProvider alloc] init];
    [NSApp run];
}
