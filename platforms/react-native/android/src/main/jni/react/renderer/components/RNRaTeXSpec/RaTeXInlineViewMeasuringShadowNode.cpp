#include "RaTeXInlineViewMeasuringShadowNode.h"

#include <react/renderer/core/LayoutContext.h>

namespace facebook::react {

void RaTeXInlineViewMeasuringShadowNode::setMeasurementManager(
    const std::shared_ptr<RaTeXViewMeasurementManager>& measurementsManager) {
  ensureUnsealed();
  measurementsManager_ = measurementsManager;
}

Size RaTeXInlineViewMeasuringShadowNode::measureContent(
    const LayoutContext& layoutContext,
    const LayoutConstraints& layoutConstraints) const {
  const auto& props = getConcreteProps();
  if (props.content.empty()) {
    return layoutConstraints.clamp({0, 0});
  }
  return layoutConstraints.clamp(
      measurementsManager_->measure(getSurfaceId(), layoutConstraints, props));
}

} // namespace facebook::react
