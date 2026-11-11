#pragma once

#include <folly/dynamic.h>
#include <react/renderer/components/RNRaTeXSpec/Props.h>

namespace facebook::react {

// Serialize the props the Kotlin measure() needs. Color does not affect the
// measured size, so it is intentionally omitted.
inline folly::dynamic toDynamic(const RaTeXViewProps& props) {
  folly::dynamic serializedProps = folly::dynamic::object();
  serializedProps["latex"] = props.latex;
  serializedProps["fontSize"] = props.fontSize;
  serializedProps["displayMode"] = props.displayMode;
  return serializedProps;
}

// Serialize the props RaTeXInlineViewManager.measure() needs. Colors do not affect the
// measured size and are omitted.
inline folly::dynamic toDynamic(const RaTeXInlineViewProps& props) {
  folly::dynamic serializedProps = folly::dynamic::object();
  serializedProps["content"] = props.content;
  serializedProps["fontSize"] = props.fontSize;
  serializedProps["textFontSize"] = props.textFontSize;
  serializedProps["textFontFamily"] = props.textFontFamily;
  serializedProps["textLineHeight"] = props.textLineHeight;
  serializedProps["textItalic"] = props.textItalic;
  serializedProps["textUnderline"] = props.textUnderline;
  serializedProps["textLineThrough"] = props.textLineThrough;
  return serializedProps;
}

} // namespace facebook::react
