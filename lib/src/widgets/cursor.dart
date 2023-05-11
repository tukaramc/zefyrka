// ignore_for_file: unused_field

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../rendering/editor.dart';

// The time it takes for the cursor to fade from fully opaque to fully
// transparent and vice versa. A full cursor blink, from transparent to opaque
// to transparent, is twice this duration.
const Duration _kCursorBlinkHalfPeriod = Duration(milliseconds: 500);

// The time the cursor is static in opacity before animating to become
// transparent.
const Duration _kCursorBlinkWaitForStart = Duration(milliseconds: 150);

/// Style properties of editing cursor.
class CursorStyle {
  /// The color to use when painting the cursor.
  ///
  /// Cannot be null.
  final Color color;

  /// The color to use when painting the background cursor aligned with the text
  /// while rendering the floating cursor.
  ///
  /// Cannot be null. By default it is the disabled grey color from
  /// CupertinoColors.
  final Color backgroundColor;

  /// How thick the cursor will be.
  ///
  /// Defaults to 1.0
  ///
  /// The cursor will draw under the text. The cursor width will extend
  /// to the right of the boundary between characters for left-to-right text
  /// and to the left for right-to-left text. This corresponds to extending
  /// downstream relative to the selected position. Negative values may be used
  /// to reverse this behavior.
  final double width;

  /// How tall the cursor will be.
  ///
  /// By default, the cursor height is set to the preferred line height of the
  /// text.
  final double? height;

  /// How rounded the corners of the cursor should be.
  ///
  /// By default, the cursor has no radius.
  final Radius? radius;

  /// The offset that is used, in pixels, when painting the cursor on screen.
  ///
  /// By default, the cursor position should be set to an offset of
  /// (-[cursorWidth] * 0.5, 0.0) on iOS platforms and (0, 0) on Android
  /// platforms. The origin from where the offset is applied to is the arbitrary
  /// location where the cursor ends up being rendered from by default.
  final Offset? offset;

  /// Whether the cursor will animate from fully transparent to fully opaque
  /// during each cursor blink.
  ///
  /// By default, the cursor opacity will animate on iOS platforms and will not
  /// animate on Android platforms.
  final bool opacityAnimates;

  /// If the cursor should be painted on top of the text or underneath it.
  ///
  /// By default, the cursor should be painted on top for iOS platforms and
  /// underneath for Android platforms.
  final bool paintAboveText;

  const CursorStyle({
    required this.color,
    required this.backgroundColor,
    this.width = 1.0,
    this.height,
    this.radius,
    this.offset,
    this.opacityAnimates = false,
    this.paintAboveText = false,
  });

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (other is! CursorStyle) return false;
    return other.color == color &&
        other.backgroundColor == backgroundColor &&
        other.width == width &&
        other.height == height &&
        other.radius == radius &&
        other.offset == offset &&
        other.opacityAnimates == opacityAnimates &&
        other.paintAboveText == paintAboveText;
  }

  @override
  // ignore: deprecated_member_use
  int get hashCode => hashValues(color, backgroundColor, width, height, radius,
      offset, opacityAnimates, paintAboveText);
}

/// Controls cursor of an editable widget.
///
/// This class is a [ChangeNotifier] and allows to listen for updates on the
/// cursor [style].
class CursorController extends ChangeNotifier {
  CursorController({
    required ValueNotifier<bool> showCursor,
    required CursorStyle style,
    required TickerProvider tickerProvider,
  })  : showCursor = showCursor,
        _style = style,
        _cursorBlink = ValueNotifier(false),
        _cursorColor = ValueNotifier(style.color) {
    _cursorBlinkOpacityController =
        AnimationController(vsync: tickerProvider, duration: _fadeDuration);
    _cursorBlinkOpacityController.addListener(_onCursorColorTick);
  }

  // This value is an eyeball estimation of the time it takes for the iOS cursor
  // to ease in and out.
  static const Duration _fadeDuration = Duration(milliseconds: 250);

  final ValueNotifier<bool> showCursor;

  Timer? _cursorTimer;
  bool _targetCursorVisibility = false;
  late AnimationController _cursorBlinkOpacityController;

  ValueNotifier<bool> get cursorBlink => _cursorBlink;
  final ValueNotifier<bool> _cursorBlink;

  ValueNotifier<Color> get cursorColor => _cursorColor;
  final ValueNotifier<Color> _cursorColor;

  CursorStyle get style => _style;
  CursorStyle _style;

  set style(CursorStyle value) {
    if (_style == value) return;
    _style = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _cursorBlinkOpacityController.removeListener(_onCursorColorTick);
    stopCursorTimer();
    _cursorBlinkOpacityController.dispose();
    assert(_cursorTimer == null);
    super.dispose();
  }

  void _cursorTick(Timer timer) {
    _targetCursorVisibility = !_targetCursorVisibility;
    final targetOpacity = _targetCursorVisibility ? 1.0 : 0.0;
    if (style.opacityAnimates) {
      // If we want to show the cursor, we will animate the opacity to the value
      // of 1.0, and likewise if we want to make it disappear, to 0.0. An easing
      // curve is used for the animation to mimic the aesthetics of the native
      // iOS cursor.
      //
      // These values and curves have been obtained through eyeballing, so are
      // likely not exactly the same as the values for native iOS.
      _cursorBlinkOpacityController.animateTo(targetOpacity,
          curve: Curves.easeOut);
    } else {
      _cursorBlinkOpacityController.value = targetOpacity;
    }
  }

  void _cursorWaitForStart(Timer timer) {
    assert(_kCursorBlinkHalfPeriod > _fadeDuration);
    _cursorTimer?.cancel();
    _cursorTimer = Timer.periodic(_kCursorBlinkHalfPeriod, _cursorTick);
  }

  void startCursorTimer() {
    _targetCursorVisibility = true;
    _cursorBlinkOpacityController.value = 1.0;

    if (style.opacityAnimates) {
      _cursorTimer =
          Timer.periodic(_kCursorBlinkWaitForStart, _cursorWaitForStart);
    } else {
      _cursorTimer = Timer.periodic(_kCursorBlinkHalfPeriod, _cursorTick);
    }
  }

  void stopCursorTimer({bool resetCharTicks = true}) {
    _cursorTimer?.cancel();
    _cursorTimer = null;
    _targetCursorVisibility = false;
    _cursorBlinkOpacityController.value = 0.0;

    if (style.opacityAnimates) {
      _cursorBlinkOpacityController.stop();
      _cursorBlinkOpacityController.value = 0.0;
    }
  }

  void startOrStopCursorTimerIfNeeded(bool hasFocus, TextSelection selection) {
    if (showCursor.value &&
        _cursorTimer == null &&
        hasFocus &&
        selection.isCollapsed) {
      startCursorTimer();
    } else if (_cursorTimer != null && (!hasFocus || !selection.isCollapsed)) {
      stopCursorTimer();
    }
  }

  void _onCursorColorTick() {
    _cursorColor.value =
        _style.color.withOpacity(_cursorBlinkOpacityController.value);
    cursorBlink.value =
        showCursor.value && _cursorBlinkOpacityController.value > 0;
  }
}

class FloatingCursorController {
  FloatingCursorController({
    required TickerProvider tickerProvider,
  }) {
    _floatingCursorResetController = AnimationController(vsync: tickerProvider);
    _floatingCursorResetController.addListener(_onFloatingCursorResetTick);
  }

  // The time it takes for the floating cursor to snap to the text aligned
  // cursor position after the user has finished placing it.
  static const Duration _floatingCursorResetTime = Duration(milliseconds: 125);

  late AnimationController _floatingCursorResetController;

  // The original position of the caret on FloatingCursorDragState.start.
  Rect? _startCaretRect;

  // The most recent text position as determined by the location of the floating
  // cursor.
  TextPosition? _lastTextPosition;

  // The offset of the floating cursor as determined from the first update call.
  Offset? _pointOffsetOrigin;

  // The most recent position of the floating cursor.
  Offset? _lastBoundedOffset;

  // Because the center of the cursor is preferredLineHeight / 2 below the touch
  // origin, but the touch origin is used to determine which line the cursor is
  // on, we need this offset to correctly render and move the cursor.
//  Offset get _floatingCursorOffset =>
//      Offset(0, renderEditor.preferredLineHeight / 2);

  void updateFloatingCursor(
      RawFloatingCursorPoint point, RenderEditor renderEditor) {
//    switch (point.state) {
//      case FloatingCursorDragState.Start:
//        if (_floatingCursorResetController.isAnimating) {
//          _floatingCursorResetController.stop();
//          _onFloatingCursorResetTick();
//        }
//        final TextPosition currentTextPosition =
//            TextPosition(offset: renderEditor.selection.baseOffset);
//        _startCaretRect =
//            renderEditor.getLocalRectForCaret(currentTextPosition);
//        renderEditor.setFloatingCursor(
//            point.state,
//            _startCaretRect.center - _floatingCursorOffset,
//            currentTextPosition);
//        break;
//      case FloatingCursorDragState.Update:
//        // We want to send in points that are centered around a (0,0) origin, so we cache the
//        // position on the first update call.
//        if (_pointOffsetOrigin != null) {
//          final Offset centeredPoint = point.offset - _pointOffsetOrigin;
//          final Offset rawCursorOffset =
//              _startCaretRect.center + centeredPoint - _floatingCursorOffset;
//          _lastBoundedOffset = renderEditor
//              .calculateBoundedFloatingCursorOffset(rawCursorOffset);
//          _lastTextPosition = renderEditor.getPositionForPoint(renderEditor
//              .localToGlobal(_lastBoundedOffset + _floatingCursorOffset));
//          renderEditor.setFloatingCursor(
//              point.state, _lastBoundedOffset, _lastTextPosition);
//        } else {
//          _pointOffsetOrigin = point.offset;
//        }
//        break;
//      case FloatingCursorDragState.End:
//        // We skip animation if no update has happened.
//        if (_lastTextPosition != null && _lastBoundedOffset != null) {
//          _floatingCursorResetController.value = 0.0;
//          _floatingCursorResetController.animateTo(1.0,
//              duration: _floatingCursorResetTime, curve: Curves.decelerate);
//        }
//        break;
//    }
  }

  void dispose() {
    _floatingCursorResetController.removeListener(_onFloatingCursorResetTick);
  }

  void _onFloatingCursorResetTick() {
//    final Offset finalPosition =
//        renderEditable.getLocalRectForCaret(_lastTextPosition).centerLeft -
//            _floatingCursorOffset;
//    if (_floatingCursorResetController.isCompleted) {
//      renderEditable.setFloatingCursor(
//          FloatingCursorDragState.End, finalPosition, _lastTextPosition);
//      if (_lastTextPosition.offset != renderEditable.selection.baseOffset)
//        // The cause is technically the force cursor, but the cause is listed as tap as the desired functionality is the same.
//        _handleSelectionChanged(
//            TextSelection.collapsed(offset: _lastTextPosition.offset),
//            renderEditable,
//            SelectionChangedCause.forcePress);
//      _startCaretRect = null;
//      _lastTextPosition = null;
//      _pointOffsetOrigin = null;
//      _lastBoundedOffset = null;
//    } else {
//      final double lerpValue = _floatingCursorResetController.value;
//      final double lerpX =
//          ui.lerpDouble(_lastBoundedOffset.dx, finalPosition.dx, lerpValue);
//      final double lerpY =
//          ui.lerpDouble(_lastBoundedOffset.dy, finalPosition.dy, lerpValue);
//
//      renderEditable.setFloatingCursor(FloatingCursorDragState.Update,
//          Offset(lerpX, lerpY), _lastTextPosition,
//          resetLerpValue: lerpValue);
//    }
  }
}
