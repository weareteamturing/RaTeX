import React, {useCallback, useContext, useMemo, useState} from 'react';
import {Platform, StyleSheet} from 'react-native';
import type {ColorValue, StyleProp, TextStyle, ViewStyle} from 'react-native';
import RaTeXInlineViewNativeComponent from './RaTeXInlineViewNativeComponent';
import {RaTeXColorContext} from './RaTeXView';

export interface InlineTeXProps {
  /** Text content with $...$ markers for inline LaTeX formulas. */
  content: string;
  /** Font size for formula rendering (points). Defaults to 16. */
  fontSize?: number;
  /** Default formula color. Explicit LaTeX colors still take precedence. */
  color?: ColorValue;
  /**
   * Style applied to plain-text segments.
   * Supported fields: color, fontSize, fontFamily, fontStyle(italic),
   * textDecorationLine(underline/line-through).
   */
  textStyle?: StyleProp<TextStyle>;
  /** Style applied to the container view. */
  style?: StyleProp<ViewStyle>;
  /**
   * Fired when the native text layout settles. `width` is the used width
   * (longest line), so a single-line content reports its natural width even
   * when the view itself is stretched wider.
   */
  onContentSizeChange?: (size: {width: number; height: number}) => void;
}

// With the New Architecture the native shadow node measures the text during Yoga layout
// (iOS: RaTeXInlineViewManager.mm, Android: RaTeXInlineViewMeasuringShadowNode +
// RaTeXInlineViewManager.measure), so the height is right on the commit that changes the
// content. A JS minHeight on top of that would only get in the way: the one-line estimate can
// be taller than the real line, and the last reported height lingers for a commit after the
// content shrinks. The old architecture has no measure function and keeps the JS height.
const nativeMeasures =
  (Platform.OS === 'ios' || Platform.OS === 'android') &&
  (globalThis as {nativeFabricUIManager?: unknown}).nativeFabricUIManager != null;

/**
 * Renders a mixed string of plain text and `$...$` LaTeX formulas inline.
 *
 * Under the hood this delegates to a native view that uses
 * NSTextAttachment (iOS) / ReplacementSpan (Android) so that formulas
 * participate in the platform's native text layout — line-wrapping,
 * baseline alignment, and word-breaking all happen at character level.
 */
export function InlineTeX({
  content,
  fontSize = 16,
  color,
  textStyle,
  style,
  onContentSizeChange,
}: InlineTeXProps): React.JSX.Element {
  const inheritedColor = useContext(RaTeXColorContext);
  const resolvedColor = color ?? inheritedColor;

  const flatTextStyle = StyleSheet.flatten(textStyle) as TextStyle | undefined;
  const textColor = flatTextStyle?.color as ColorValue | undefined;
  const textFontSize = flatTextStyle?.fontSize ?? fontSize;
  const textFontFamily =
    typeof flatTextStyle?.fontFamily === 'string' && flatTextStyle.fontFamily.trim().length > 0
      ? flatTextStyle.fontFamily
      : undefined;
  const textLineHeight =
    typeof flatTextStyle?.lineHeight === 'number' && flatTextStyle.lineHeight > 0
      ? flatTextStyle.lineHeight
      : undefined;
  const textItalic = flatTextStyle?.fontStyle === 'italic';
  const rawDecorationLine = flatTextStyle?.textDecorationLine;
  const decorationLine = Array.isArray(rawDecorationLine)
    ? rawDecorationLine.join(' ')
    : rawDecorationLine;
  const textUnderline =
    typeof decorationLine === 'string' && decorationLine.includes('underline');
  const textLineThrough =
    typeof decorationLine === 'string' && decorationLine.includes('line-through');

  const [contentSize, setContentSize] = useState<{
    width: number;
    height: number;
  } | null>(null);

  // The last reported height stays the minHeight until the native view reports the
  // new one. Resetting it on every content change dropped the view to the one-line
  // estimate first, so text growing a few characters at a time (a streaming chat
  // message) shrank and grew back on each update — measured on an Android emulator:
  // 51 of 105 layouts shorter than the previous one.

  const handleContentSizeChange = useCallback(
    (e: {nativeEvent: {width: number; height: number}}) => {
      const size = {
        width: e.nativeEvent.width,
        height: e.nativeEvent.height,
      };
      setContentSize(size);
      onContentSizeChange?.(size);
    },
    [onContentSizeChange],
  );

  const flatStyle = StyleSheet.flatten(style) as ViewStyle | undefined;
  const hasHeight = typeof flatStyle?.height === 'number';
  const hasExplicitWidth = flatStyle?.width != null;
  const hasExplicitAlignSelf = flatStyle?.alignSelf != null;

  const estimatedHeight = useMemo(() => {
    const lineHeight = textLineHeight ?? Math.ceil(textFontSize * 1.4);
    return lineHeight;
  }, [textFontSize, textLineHeight]);

  const hasRenderableContent = content.trim().length > 0;
  const heightValue = hasRenderableContent
    ? (contentSize ? contentSize.height : estimatedHeight)
    : 0;

  // Always stretch to fill the parent (matching how RN's <Text> behaves for
  // wrapping content) unless the caller sets width or alignSelf explicitly.
  // Without a native measure function (old architecture) Yoga would otherwise
  // give the view a width of 0.
  const stretchFallback =
    !hasExplicitWidth && !hasExplicitAlignSelf
      ? {alignSelf: 'stretch' as const}
      : null;

  const resolvedStyle =
    hasHeight || nativeMeasures
      ? [style, stretchFallback]
      : [style, stretchFallback, {minHeight: heightValue}];

  return (
    <RaTeXInlineViewNativeComponent
      content={content}
      fontSize={fontSize}
      color={resolvedColor}
      textColor={textColor}
      textFontSize={textFontSize}
      textFontFamily={textFontFamily}
      textLineHeight={textLineHeight}
      textItalic={textItalic}
      textUnderline={textUnderline}
      textLineThrough={textLineThrough}
      style={resolvedStyle}
      onContentSizeChange={handleContentSizeChange}
    />
  );
}
