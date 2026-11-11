/**
 * Hand-written override of the codegen ComponentDescriptors.h. It is placed
 * ahead of the generated one on the include path so that autolinking (which
 * registers `RaTeXViewComponentDescriptor`) and the codegen registration both
 * pick up the measurable descriptors for <RaTeXView> and <RaTeXInlineView>.
 */
#pragma once

#include <react/renderer/components/RNRaTeXSpec/ShadowNodes.h>
#include <react/renderer/componentregistry/ComponentDescriptorProviderRegistry.h>
#include <react/renderer/core/ConcreteComponentDescriptor.h>

#include "RaTeXInlineViewMeasuringComponentDescriptor.h"
#include "RaTeXViewMeasuringComponentDescriptor.h"

namespace facebook::react {

using RaTeXInlineViewComponentDescriptor = RaTeXInlineViewMeasuringComponentDescriptor;
using RaTeXViewComponentDescriptor = RaTeXViewMeasuringComponentDescriptor;

void RNRaTeXSpec_registerComponentDescriptorsFromCodegen(
    std::shared_ptr<const ComponentDescriptorProviderRegistry> registry);

} // namespace facebook::react
