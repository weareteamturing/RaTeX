#pragma once

#include "RaTeXViewMeasurementManager.h"

#include <react/renderer/components/RNRaTeXSpec/ShadowNodes.h>

namespace facebook::react {

// Measurable shadow node for <RaTeXInlineView>. Adds the Yoga measure traits and a synchronous
// measureContent that lays the text out through RaTeXInlineViewManager.measure (Kotlin), so the
// height is right on the commit that changes the content. Mirrors the iOS node in
// RaTeXInlineViewManager.mm.
class RaTeXInlineViewMeasuringShadowNode final : public RaTeXInlineViewShadowNode {
 public:
  using RaTeXInlineViewShadowNode::RaTeXInlineViewShadowNode;

  static ShadowNodeTraits BaseTraits() {
    auto traits = RaTeXInlineViewShadowNode::BaseTraits();
    traits.set(ShadowNodeTraits::Trait::LeafYogaNode);
    traits.set(ShadowNodeTraits::Trait::MeasurableYogaNode);
    return traits;
  }

  void setMeasurementManager(
      const std::shared_ptr<RaTeXViewMeasurementManager>& measurementsManager);

  Size measureContent(
      const LayoutContext& layoutContext,
      const LayoutConstraints& layoutConstraints) const override;

 private:
  std::shared_ptr<RaTeXViewMeasurementManager> measurementsManager_;
};

} // namespace facebook::react
