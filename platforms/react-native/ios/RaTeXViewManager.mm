// RaTeXViewManager.mm — Apple bridge for RaTeXView (supports old arch & Fabric new arch).

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
#else
#import "RaTeXViewManager.h"
#import <React/RCTUIManager.h>
#endif

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

// Swift-generated header (module name derived from podspec/target name).
// Prefer the framework/module form (<module/module-Swift.h>) when it resolves: it
// creates a module dependency that forces the Swift target to build BEFORE this
// Objective-C++ TU, avoiding a non-deterministic build race that fails `xcodebuild`
// (and EAS/CI) with "ratex_react_native-Swift.h file not found". But when the
// library is built as a *static library* rather than a framework/clang module —
// e.g. `use_frameworks! :linkage => :static` (Expo's `useFrameworks: 'static'`,
// required to statically link some RN pods such as RNFirebase) — the generated
// header is emitted only into this target's own DerivedSources and the
// angle/module form no longer resolves. Guard with __has_include so framework
// builds keep the race-avoidance and static-library builds fall back to the quote
// form (which resolves against DerivedSources). Linkage-agnostic.
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

namespace {

// A ShadowNode that measures the formula synchronously during Yoga layout, using
// the (thread-safe) RaTeX engine. This makes the view's size available on the very
// first commit — i.e. at JS `useLayoutEffect` — instead of only after the async
// `onContentSizeChange` event, which otherwise causes a one-frame 0-size flash and
// breaks synchronous reserve-then-place layout (e.g. TextKit attachments).
class RaTeXViewMeasuringShadowNode final : public RaTeXViewShadowNode {
 public:
  using RaTeXViewShadowNode::RaTeXViewShadowNode;

  static ShadowNodeTraits BaseTraits() {
    auto traits = RaTeXViewShadowNode::BaseTraits();
    traits.set(ShadowNodeTraits::Trait::LeafYogaNode);
    traits.set(ShadowNodeTraits::Trait::MeasurableYogaNode);
    return traits;
  }

  facebook::react::Size measureContent(const LayoutContext &layoutContext,
                                       const LayoutConstraints &layoutConstraints) const override {
    const auto &props = getConcreteProps();
    if (props.latex.empty() || props.fontSize <= 0) {
      return layoutConstraints.clamp(facebook::react::Size{0, 0});
    }
    NSString *latex = [NSString stringWithUTF8String:props.latex.c_str()];
    if (latex == nil) {
      return layoutConstraints.clamp(facebook::react::Size{0, 0});
    }
    CGSize measured = [RaTeXMeasure measureLatex:latex
                                        fontSize:static_cast<CGFloat>(props.fontSize)
                                     displayMode:props.displayMode ? YES : NO];
    facebook::react::Size size{static_cast<Float>(measured.width), static_cast<Float>(measured.height)};
    return layoutConstraints.clamp(size);
  }
};

using RaTeXViewMeasuringComponentDescriptor =
    ConcreteComponentDescriptor<RaTeXViewMeasuringShadowNode>;

}  // namespace

// Class name follows RN Fabric convention: {ComponentName}ComponentView
// so that RCTThirdPartyComponentsProvider can resolve it via NSClassFromString.
@interface RaTeXViewComponentView : RCTViewComponentView
@end

@implementation RaTeXViewComponentView {
  RaTeXRNView *_nativeView;
  // An onError that has not reached JS yet. Fabric mounts a view by calling updateProps
  // before updateEventEmitter, and prepareForRecycle clears the emitter, so a parse error
  // raised while props are applied would otherwise be dropped. It is sent from
  // finalizeUpdates, which runs after the emitter is attached.
  BOOL _errorPending;
  BOOL _applyingProps;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<RaTeXViewMeasuringComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const RaTeXViewProps>();
    _props = defaultProps;

    _nativeView = [[RaTeXRNView alloc] initWithFrame:self.bounds];
#if TARGET_OS_OSX
    _nativeView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
#else
    _nativeView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
#endif

    __weak RaTeXViewComponentView *weakSelf = self;
    [_nativeView setErrorCallback:^(NSString *errorMsg) {
      RaTeXViewComponentView *strongSelf = weakSelf;
      if (!strongSelf) return;
      strongSelf->_errorPending = YES;
      // During updateProps the emitter may be missing (first mount) or still belong to the
      // previous mount; finalizeUpdates delivers it. Outside a props update (e.g. a
      // light/dark change re-renders) deliver right away.
      if (!strongSelf->_applyingProps) {
        [strongSelf deliverPendingError];
      }
    }];
    [_nativeView setContentSizeCallback:^(CGFloat width, CGFloat height) {
      RaTeXViewComponentView *strongSelf = weakSelf;
      if (!strongSelf || !strongSelf->_eventEmitter) return;
      auto emitter = std::dynamic_pointer_cast<const RaTeXViewEventEmitter>(
          strongSelf->_eventEmitter);
      if (emitter) {
        RaTeXViewEventEmitter::OnContentSizeChange event{
            .width = static_cast<Float>(width), .height = static_cast<Float>(height)};
        emitter->onContentSizeChange(event);
      }
    }];

    self.contentView = _nativeView;
  }
  return self;
}

- (void)deliverPendingError
{
  if (!_errorPending) return;
  NSString *message = _nativeView.renderErrorMessage;
  if (message == nil) {
    // A later render succeeded; the error is no longer what the view shows.
    _errorPending = NO;
    return;
  }
  auto emitter = std::dynamic_pointer_cast<const RaTeXViewEventEmitter>(_eventEmitter);
  if (!emitter) return;
  _errorPending = NO;
  RaTeXViewEventEmitter::OnError event{.error = std::string(message.UTF8String ?: "")};
  emitter->onError(event);
}

- (void)updateProps:(Props::Shared const &)props
           oldProps:(Props::Shared const &)oldProps
{
  const auto &newProps = *std::static_pointer_cast<const RaTeXViewProps>(props);
  _applyingProps = YES;

  NSString *latex = [NSString stringWithUTF8String:newProps.latex.c_str()];
  if (![latex isEqualToString:_nativeView.latex]) {
    _nativeView.latex = latex;
  }

  CGFloat fontSize = static_cast<CGFloat>(newProps.fontSize);
  if (fontSize > 0 && fontSize != _nativeView.fontSize) {
    _nativeView.fontSize = fontSize;
  }

  BOOL displayMode = newProps.displayMode ? YES : NO;
  if (displayMode != _nativeView.displayMode) {
    _nativeView.displayMode = displayMode;
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
  _applyingProps = NO;

  [super updateProps:props oldProps:oldProps];
}

- (void)finalizeUpdates:(RNComponentViewUpdateMask)updateMask
{
  [super finalizeUpdates:updateMask];
  [self deliverPendingError];
}

- (void)prepareForRecycle
{
  [super prepareForRecycle];
  // The next mount may set the same latex, which skips the setter and re-parses nothing.
  // If this view is in an error state, the new listener still has to hear about it.
  _errorPending = _nativeView.renderErrorMessage != nil;
}

// When JS remounts (e.g. Fast Refresh or key changes), Fabric can reuse the same
// native view instance but swap the EventEmitter. If props don't change, the
// view would not re-emit content size, causing JS-side auto-sizing to get stuck.
- (void)updateEventEmitter:(EventEmitter::Shared const &)eventEmitter
{
  [super updateEventEmitter:eventEmitter];
  if (_nativeView) {
    [_nativeView resetContentSizeReporting];
  }
}

@end

Class<RCTComponentViewProtocol> RaTeXViewCls(void)
{
  return RaTeXViewComponentView.class;
}

// ---------------------------------------------------------------------------
// MARK: - Old Architecture (Bridge)
// ---------------------------------------------------------------------------

#else // !RCT_NEW_ARCH_ENABLED

@implementation RaTeXViewManager

RCT_EXPORT_MODULE(RaTeXView)

#if TARGET_OS_OSX
- (NSView *)view
#else
- (UIView *)view
#endif
{
  return [[RaTeXRNView alloc] init];
}

RCT_EXPORT_VIEW_PROPERTY(latex, NSString)
RCT_EXPORT_VIEW_PROPERTY(fontSize, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(displayMode, BOOL)
#if TARGET_OS_OSX
RCT_EXPORT_VIEW_PROPERTY(color, NSColor)
#else
RCT_EXPORT_VIEW_PROPERTY(color, UIColor)
#endif
RCT_EXPORT_VIEW_PROPERTY(onError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onContentSizeChange, RCTDirectEventBlock)

@end

#endif // RCT_NEW_ARCH_ENABLED
