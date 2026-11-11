#include "RaTeXViewMeasurementManager.h"

#include "conversions.h"

#include <fbjni/fbjni.h>
#include <react/jni/ReadableNativeMap.h>
#include <react/renderer/core/conversions.h>

using namespace facebook::jni;

namespace facebook::react {

Size RaTeXViewMeasurementManager::measure(
    SurfaceId surfaceId,
    LayoutConstraints layoutConstraints,
    const RaTeXViewProps& props) const {
  return measure(surfaceId, layoutConstraints, "RaTeXView", toDynamic(props));
}

Size RaTeXViewMeasurementManager::measure(
    SurfaceId surfaceId,
    LayoutConstraints layoutConstraints,
    const RaTeXInlineViewProps& props) const {
  return measure(surfaceId, layoutConstraints, "RaTeXInlineView", toDynamic(props));
}

Size RaTeXViewMeasurementManager::measure(
    SurfaceId surfaceId,
    LayoutConstraints layoutConstraints,
    const char* componentNameValue,
    const folly::dynamic& serializedProps) const {
  const jni::global_ref<jobject>& fabricUIManager =
      contextContainer_->at<jni::global_ref<jobject>>("FabricUIManager");

  static const auto measure =
      facebook::jni::findClassStatic("com/facebook/react/fabric/FabricUIManager")
          ->getMethod<jlong(
              jint,
              jstring,
              ReadableMap::javaobject,
              ReadableMap::javaobject,
              ReadableMap::javaobject,
              jfloat,
              jfloat,
              jfloat,
              jfloat)>("measure");

  auto minimumSize = layoutConstraints.minimumSize;
  auto maximumSize = layoutConstraints.maximumSize;

  local_ref<JString> componentName = make_jstring(componentNameValue);

  local_ref<ReadableNativeMap::javaobject> propsRNM =
      ReadableNativeMap::newObjectCxxArgs(serializedProps);
  local_ref<ReadableMap::javaobject> propsRM =
      make_local(reinterpret_cast<ReadableMap::javaobject>(propsRNM.get()));

  auto measurement = yogaMeassureToSize(measure(
      fabricUIManager,
      surfaceId,
      componentName.get(),
      nullptr,
      propsRM.get(),
      nullptr,
      minimumSize.width,
      maximumSize.width,
      minimumSize.height,
      maximumSize.height));

  return measurement;
}

} // namespace facebook::react
