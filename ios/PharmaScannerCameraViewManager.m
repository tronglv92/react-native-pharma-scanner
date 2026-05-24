#import <React/RCTViewManager.h>

@interface RCT_EXTERN_MODULE(PharmaScannerCameraViewManager, RCTViewManager)
RCT_EXPORT_VIEW_PROPERTY(overlayColor, NSString)
RCT_EXPORT_VIEW_PROPERTY(overlayLineWidth, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(overlayFillColor, NSString)
RCT_EXPORT_VIEW_PROPERTY(showOverlay, BOOL)
@end
