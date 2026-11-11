// RaTeXInlineViewManager.mm — Apple bridge for RaTeXInlineView (old arch & Fabric).

#ifdef RCT_NEW_ARCH_ENABLED
#import <React/RCTComponentViewProtocol.h>
#import <React/RCTFabricComponentsPlugins.h>
#import <React/RCTViewComponentView.h>
#import <react/renderer/components/RNRaTeXSpec/ComponentDescriptors.h>
#import <react/renderer/components/RNRaTeXSpec/EventEmitters.h>
#import <react/renderer/components/RNRaTeXSpec/Props.h>
#import <react/renderer/components/RNRaTeXSpec/RCTComponentViewHelpers.h>
#import <react/renderer/core/LayoutConstraints.h>
#import <react/renderer/core/LayoutContext.h>
#include <cmath>
#else
#import "RaTeXInlineViewManager.h"
#import <React/RCTUIManager.h>
#endif

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

// Prefer the framework/module form (forces the Swift module to build before this
// Objective-C++ TU, avoiding a non-deterministic "-Swift.h file not found" compile
// race on clean xcodebuild/EAS/CI builds). Fall back to the quote form when the
// module form does not resolve — i.e. when the library builds as a *static library*
// rather than a framework/clang module (`use_frameworks! :linkage => :static` /
// Expo `useFrameworks: 'static'`), where the generated header lands only in this
// target's own DerivedSources. Guard with __has_include so both linkages work.
#if __has_include(<ratex_react_native/ratex_react_native-Swift.h>)
#import <ratex_react_native/ratex_react_native-Swift.h>
#else
#import "ratex_react_native-Swift.h"
#endif
#import "RaTeXColorUtils.h"

// ---------------------------------------------------------------------------
// MARK: - New Architecture (Fabric)
// ---------------------------------------------------------------------------

#ifdef RCT_NEW_ARCH_ENABLED

using namespace facebook::react;

#if !TARGET_OS_OSX
namespace {

// Measures the text during Yoga layout so the view's height is right on the commit that
// changes its content. Without a measure function the height came only from JS (a one-line
// estimate, then onContentSizeChange after the native layout), so every content change first
// dropped the view to one line and then grew it back — visible as jitter while a chat message
// streams in. RaTeXInlineMeasure builds the same attributed string RaTeXInlineView draws and
// is safe to call off the main thread.
class RaTeXInlineViewMeasuringShadowNode final : public RaTeXInlineViewShadowNode {
 public:
  using RaTeXInlineViewShadowNode::RaTeXInlineViewShadowNode;

  static ShadowNodeTraits BaseTraits() {
    auto traits = RaTeXInlineViewShadowNode::BaseTraits();
    traits.set(ShadowNodeTraits::Trait::LeafYogaNode);
    traits.set(ShadowNodeTraits::Trait::MeasurableYogaNode);
    return traits;
  }

  facebook::react::Size measureContent(const LayoutContext &layoutContext,
                                       const LayoutConstraints &layoutConstraints) const override {
    const auto &props = getConcreteProps();
    if (props.content.empty()) {
      return layoutConstraints.clamp(facebook::react::Size{0, 0});
    }
    CGSize measured = CGSizeZero;
    @autoreleasepool {
      NSString *content = [NSString stringWithUTF8String:props.content.c_str()];
      if (content == nil) {
        return layoutConstraints.clamp(facebook::react::Size{0, 0});
      }
      NSString *family = props.textFontFamily.empty()
          ? nil
          : [NSString stringWithUTF8String:props.textFontFamily.c_str()];
      // Same defaults the component view falls back to when a size prop is 0 (unset).
      CGFloat fontSize = props.fontSize > 0 ? static_cast<CGFloat>(props.fontSize) : 16;
      CGFloat textFontSize = props.textFontSize > 0 ? static_cast<CGFloat>(props.textFontSize) : 16;
      Float maxWidth = layoutConstraints.maximumSize.width;
      CGFloat width = std::isfinite(maxWidth) && maxWidth > 0 ? static_cast<CGFloat>(maxWidth)
                                                              : CGFLOAT_MAX;
      measured = [RaTeXInlineMeasure measureContent:content
                                           fontSize:fontSize
                                       textFontSize:textFontSize
                                     textFontFamily:family
                                     textLineHeight:static_cast<CGFloat>(props.textLineHeight)
                                         textItalic:props.textItalic ? YES : NO
                                      textUnderline:props.textUnderline ? YES : NO
                                    textLineThrough:props.textLineThrough ? YES : NO
                                           maxWidth:width
                                              scale:static_cast<CGFloat>(layoutContext.pointScaleFactor)];
    }
    return layoutConstraints.clamp(
        facebook::react::Size{static_cast<Float>(measured.width), static_cast<Float>(measured.height)});
  }
};

using RaTeXInlineViewMeasuringComponentDescriptor =
    ConcreteComponentDescriptor<RaTeXInlineViewMeasuringShadowNode>;

}  // namespace
#endif

@interface RaTeXInlineViewComponentView : RCTViewComponentView
@end

@implementation RaTeXInlineViewComponentView {
  RaTeXInlineRNView *_nativeView;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
#if TARGET_OS_OSX
  return concreteComponentDescriptorProvider<RaTeXInlineViewComponentDescriptor>();
#else
  return concreteComponentDescriptorProvider<RaTeXInlineViewMeasuringComponentDescriptor>();
#endif
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const RaTeXInlineViewProps>();
    _props = defaultProps;

    _nativeView = [[RaTeXInlineRNView alloc] initWithFrame:self.bounds];
#if TARGET_OS_OSX
    _nativeView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
#else
    _nativeView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
#endif

    __weak RaTeXInlineViewComponentView *weakSelf = self;
    [_nativeView setContentSizeCallback:^(CGFloat width, CGFloat height) {
      RaTeXInlineViewComponentView *strongSelf = weakSelf;
      if (!strongSelf || !strongSelf->_eventEmitter) return;
      auto emitter = std::dynamic_pointer_cast<const RaTeXInlineViewEventEmitter>(
          strongSelf->_eventEmitter);
      if (emitter) {
        RaTeXInlineViewEventEmitter::OnContentSizeChange event{
            .width = static_cast<Float>(width), .height = static_cast<Float>(height)};
        emitter->onContentSizeChange(event);
      }
    }];

    self.contentView = _nativeView;
  }
  return self;
}

- (void)updateProps:(Props::Shared const &)props
           oldProps:(Props::Shared const &)oldProps
{
  const auto &newProps = *std::static_pointer_cast<const RaTeXInlineViewProps>(props);

  NSString *content = [NSString stringWithUTF8String:newProps.content.c_str()];
  if (![content isEqualToString:_nativeView.content]) {
    _nativeView.content = content;
  }

  CGFloat fontSize = static_cast<CGFloat>(newProps.fontSize);
  if (fontSize > 0 && fontSize != _nativeView.fontSize) {
    _nativeView.fontSize = fontSize;
  }

#if TARGET_OS_OSX
  NSColor *color = RaTeXPlatformColorFromSharedColor(newProps.color);
#else
  UIColor *color = RaTeXPlatformColorFromSharedColor(newProps.color);
#endif
  if ((color == nil) != (_nativeView.color == nil) ||
      (color != nil && ![color isEqual:_nativeView.color])) {
    _nativeView.color = color;
  }

#if TARGET_OS_OSX
  NSColor *textColor = RaTeXPlatformColorFromSharedColor(newProps.textColor);
#else
  UIColor *textColor = RaTeXPlatformColorFromSharedColor(newProps.textColor);
#endif
  if ((textColor == nil) != (_nativeView.textColor == nil) ||
      (textColor != nil && ![textColor isEqual:_nativeView.textColor])) {
    _nativeView.textColor = textColor;
  }

  CGFloat textFontSize = static_cast<CGFloat>(newProps.textFontSize);
  if (textFontSize > 0 && textFontSize != _nativeView.textFontSize) {
    _nativeView.textFontSize = textFontSize;
  }

  CGFloat textLineHeight = static_cast<CGFloat>(newProps.textLineHeight);
  if (textLineHeight != _nativeView.textLineHeight) {
    _nativeView.textLineHeight = textLineHeight;
  }

  NSString *textFontFamily = nil;
  if (!newProps.textFontFamily.empty()) {
    textFontFamily =
        [NSString stringWithUTF8String:newProps.textFontFamily.c_str()];
  }
  if ((textFontFamily == nil) != (_nativeView.textFontFamily == nil) ||
      (textFontFamily != nil &&
       ![textFontFamily isEqualToString:_nativeView.textFontFamily])) {
    _nativeView.textFontFamily = textFontFamily;
  }

  if (newProps.textItalic != _nativeView.textItalic) {
    _nativeView.textItalic = newProps.textItalic;
  }

  if (newProps.textUnderline != _nativeView.textUnderline) {
    _nativeView.textUnderline = newProps.textUnderline;
  }

  if (newProps.textLineThrough != _nativeView.textLineThrough) {
    _nativeView.textLineThrough = newProps.textLineThrough;
  }

  [super updateProps:props oldProps:oldProps];
}

- (void)updateEventEmitter:(EventEmitter::Shared const &)eventEmitter
{
  [super updateEventEmitter:eventEmitter];
  if (_nativeView) {
    [_nativeView resetContentSizeReporting];
  }
}

@end

Class<RCTComponentViewProtocol> RaTeXInlineViewCls(void)
{
  return RaTeXInlineViewComponentView.class;
}

// ---------------------------------------------------------------------------
// MARK: - Old Architecture (Bridge)
// ---------------------------------------------------------------------------

#else // !RCT_NEW_ARCH_ENABLED

@implementation RaTeXInlineViewManager

RCT_EXPORT_MODULE(RaTeXInlineView)

#if TARGET_OS_OSX
- (NSView *)view
#else
- (UIView *)view
#endif
{
  return [[RaTeXInlineRNView alloc] init];
}

RCT_EXPORT_VIEW_PROPERTY(content, NSString)
RCT_EXPORT_VIEW_PROPERTY(fontSize, CGFloat)
#if TARGET_OS_OSX
RCT_EXPORT_VIEW_PROPERTY(color, NSColor)
RCT_EXPORT_VIEW_PROPERTY(textColor, NSColor)
#else
RCT_EXPORT_VIEW_PROPERTY(color, UIColor)
RCT_EXPORT_VIEW_PROPERTY(textColor, UIColor)
#endif
RCT_EXPORT_VIEW_PROPERTY(textFontSize, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(textFontFamily, NSString)
RCT_EXPORT_VIEW_PROPERTY(textLineHeight, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(textItalic, BOOL)
RCT_EXPORT_VIEW_PROPERTY(textUnderline, BOOL)
RCT_EXPORT_VIEW_PROPERTY(textLineThrough, BOOL)
RCT_EXPORT_VIEW_PROPERTY(onContentSizeChange, RCTDirectEventBlock)

@end

#endif // RCT_NEW_ARCH_ENABLED
