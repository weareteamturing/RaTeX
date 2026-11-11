#pragma once

#include "RaTeXInlineViewMeasuringShadowNode.h"
#include "RaTeXViewMeasurementManager.h"

#include <react/renderer/core/ConcreteComponentDescriptor.h>

namespace facebook::react {

// Component descriptor for the measurable <RaTeXInlineView> shadow node. Same shape as
// RaTeXViewMeasuringComponentDescriptor: one measurement manager per descriptor, injected into
// every shadow node via adopt().
class RaTeXInlineViewMeasuringComponentDescriptor final
    : public ConcreteComponentDescriptor<RaTeXInlineViewMeasuringShadowNode> {
 public:
  RaTeXInlineViewMeasuringComponentDescriptor(
      const ComponentDescriptorParameters& parameters)
      : ConcreteComponentDescriptor(parameters),
        measurementsManager_(
            std::make_shared<RaTeXViewMeasurementManager>(contextContainer_)) {}

  void adopt(ShadowNode& shadowNode) const override {
    ConcreteComponentDescriptor::adopt(shadowNode);
    auto& node = static_cast<RaTeXInlineViewMeasuringShadowNode&>(shadowNode);
    node.setMeasurementManager(measurementsManager_);
  }

 private:
  const std::shared_ptr<RaTeXViewMeasurementManager> measurementsManager_;
};

} // namespace facebook::react
