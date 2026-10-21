import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A [LayoutBuilder] that still rebuilds when a descendant asks for a rebuild
/// during its own child layout.
///
/// [LayoutBuilder] builds in an isolated scope and schedules that scope by
/// marking itself for layout. A request that arrives after the scope has run,
/// while the child is being laid out, sets the rebuild flag and then has the
/// flag's layout mark cleared as this layout finishes. The next request sees
/// the flag and, in release, returns without laying out again: the sidebar,
/// which listens on its own, moves to the new chat, and the editor keeps the
/// session it already built. This builder records that request and lays the
/// child out again on the next frame.
class FrameLayoutBuilder extends RenderObjectWidget {
  const FrameLayoutBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, BoxConstraints constraints)
  builder;

  @override
  RenderObjectElement createElement() => _FrameLayoutElement(this);

  @override
  RenderBox createRenderObject(BuildContext context) => _RenderFrameLayout();

  @override
  void updateRenderObject(BuildContext context, RenderBox renderObject) {}
}

class _FrameLayoutElement extends RenderObjectElement {
  _FrameLayoutElement(FrameLayoutBuilder super.widget);

  @override
  _RenderFrameLayout get renderObject =>
      super.renderObject as _RenderFrameLayout;

  @override
  BuildScope get buildScope => _scope;

  late final BuildScope _scope = BuildScope(scheduleRebuild: _scheduleRebuild);

  Element? _child;
  BoxConstraints? _previousConstraints;
  bool _needsBuild = true;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject.updateCallback(_rebuild);
  }

  @override
  void update(FrameLayoutBuilder newWidget) {
    super.update(newWidget);
    renderObject.updateCallback(_rebuild);
    // As [LayoutBuilder]: a new configuration builds again, constraints or not.
    _needsBuild = true;
    renderObject.requestRebuild();
  }

  /// The isolated scope's descendants, and this element, rebuild from layout.
  void _scheduleRebuild() => renderObject.requestRebuild();

  @override
  void markNeedsBuild() {
    // Not [Element.markNeedsBuild]: the child is built from layout, and a
    // dirty flag here would be waiting on a scope the root frame never flushes.
    _needsBuild = true;
    renderObject.requestRebuild();
  }

  @override
  void performRebuild() {
    _needsBuild = true;
    renderObject.requestRebuild();
    super.performRebuild();
  }

  void _rebuild() {
    final constraints = renderObject.constraints;
    void updateChildCallback() {
      Widget built;
      try {
        built = (widget as FrameLayoutBuilder).builder(this, constraints);
        debugWidgetBuilderValue(widget, built);
      } catch (error, stack) {
        built = ErrorWidget.builder(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'baocode',
            context: ErrorDescription('while building $widget'),
          ),
        );
      }
      try {
        _child = updateChild(_child, built, null);
      } catch (error, stack) {
        built = ErrorWidget.builder(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'baocode',
            context: ErrorDescription('while building $widget'),
          ),
        );
        _child = updateChild(null, built, null);
      } finally {
        _needsBuild = false;
        _previousConstraints = constraints;
      }
    }

    final changed = _previousConstraints != constraints;
    final callback = _needsBuild || changed ? updateChildCallback : null;
    owner!.buildScope(this, callback);
  }

  @override
  void unmount() {
    renderObject.updateCallback(null);
    super.unmount();
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }

  @override
  void forgetChild(Element child) {
    assert(child == _child);
    _child = null;
    super.forgetChild(child);
  }

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    final renderObject = this.renderObject;
    assert(slot == null);
    renderObject.child = child as RenderBox;
  }

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) {
    assert(false);
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    final renderObject = this.renderObject;
    assert(renderObject.child == child);
    renderObject.child = null;
  }
}

class _RenderFrameLayout extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  VoidCallback? _callback;
  bool _layingOut = false;
  bool _inCallback = false;
  bool _followUp = false;
  bool _followUpScheduled = false;
  bool _callbackScheduled = false;

  void updateCallback(VoidCallback? value) {
    _callback = value;
  }

  /// Runs the builder again once this object is laid out.
  ///
  /// While the child is being laid out, marking layout now would be cleared
  /// when this pass finishes, and a later request would see a rebuild already
  /// pending and do nothing. The follow-up is the next frame. Outside a
  /// frame, the mark waits until the next frame's layout, as [LayoutBuilder].
  void requestRebuild() {
    if (_layingOut && !_inCallback) {
      _followUp = true;
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      _scheduleFrameCallback();
      return;
    }
    markNeedsLayout();
  }

  void _scheduleFrameCallback() {
    if (_callbackScheduled) return;
    _callbackScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _callbackScheduled = false;
      if (attached) markNeedsLayout();
    });
  }

  void _scheduleFollowUp() {
    if (_followUpScheduled) return;
    _followUpScheduled = true;
    SchedulerBinding.instance.scheduleFrame();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _followUpScheduled = false;
      if (attached) markNeedsLayout();
    });
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    assert(_throwIfNotCheckingIntrinsics());
    return 0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    assert(_throwIfNotCheckingIntrinsics());
    return 0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    assert(_throwIfNotCheckingIntrinsics());
    return 0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    assert(_throwIfNotCheckingIntrinsics());
    return 0;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason:
            'Calculating the dry layout would require running the layout '
            'callback speculatively, which might mutate the live render '
            'object tree.',
      ),
    );
    return Size.zero;
  }

  bool _throwIfNotCheckingIntrinsics() {
    if (!RenderObject.debugCheckingIntrinsics) {
      throw FlutterError(
        'FrameLayoutBuilder does not support returning intrinsic dimensions.',
      );
    }
    return true;
  }

  @override
  void performLayout() {
    _layingOut = true;
    try {
      _inCallback = true;
      try {
        invokeLayoutCallback<BoxConstraints>((_) => _callback?.call());
      } finally {
        _inCallback = false;
      }
      final child = this.child;
      if (child != null) {
        child.layout(constraints, parentUsesSize: true);
        size = constraints.constrain(child.size);
      } else {
        size = constraints.biggest;
      }
    } finally {
      final followUp = _followUp;
      _followUp = false;
      _layingOut = false;
      if (followUp) _scheduleFollowUp();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position) ?? false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset);
  }
}
