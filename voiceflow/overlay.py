"""Floating overlay indicator for recording/processing state.

Uses PyObjC/AppKit for a native macOS overlay window that floats above all apps.
Shows recording state (red dot), processing state (spinner), and briefly flashes
the cleaned text result.

Falls back gracefully if PyObjC is not available (e.g., non-macOS or missing deps).
"""
import threading
import time

# PyObjC imports — graceful fallback if unavailable
try:
    import objc
    from AppKit import (
        NSApplication,
        NSWindow,
        NSView,
        NSTextField,
        NSColor,
        NSFont,
        NSScreen,
        NSWindowStyleMaskBorderless,
        NSWindowLevelFloating,
        NSBackingStoreBuffered,
        NSWindowCollectionBehaviorCanJoinAllSpaces,
        NSWindowCollectionBehaviorStationary,
        NSTextAlignmentCenter,
        NSVisualEffectView,
        NSVisualEffectBlendingModeBehindWindow,
        NSVisualEffectMaterialHUDWindow,
        NSLayoutAttributeCenterX,
        NSLayoutAttributeCenterY,
        NSLayoutAttributeWidth,
        NSLayoutAttributeHeight,
        NSLayoutConstraint,
        NSLayoutRelationEqual,
        NSAnimationContext,
        NSViewWidthSizable,
        NSViewHeightSizable,
        NSImageView,
        NSImage,
        NSMakeRect,
        NSBezierPath,
    )
    from Foundation import NSTimer, NSRunLoop, NSDefaultRunLoopMode, NSObject
    from Quartz import CGFloat
    HAS_APPKIT = True
except ImportError:
    HAS_APPKIT = False


class OverlayState:
    """Enum-like state constants."""
    HIDDEN = "hidden"
    RECORDING = "recording"
    PROCESSING = "processing"
    RESULT = "result"
    ERROR = "error"


class _OverlayAnimator(NSObject):
    """NSObject subclass to handle animation timer callbacks."""

    def init(self):
        self = objc.super(_OverlayAnimator, self).init()
        if self is None:
            return None
        self._dot_count = 0
        self._label = None
        self._timer = None
        return self

    def setLabel_(self, label):
        self._label = label

    def startProcessingAnimation(self):
        """Start the processing dots animation."""
        self._dot_count = 0
        self._timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            0.4, self, b"animateDots:", None, True
        )
        NSRunLoop.currentRunLoop().addTimer_forMode_(self._timer, NSDefaultRunLoopMode)

    def stopAnimation(self):
        if self._timer:
            self._timer.invalidate()
            self._timer = None

    def animateDots_(self, timer):
        """Timer callback for processing animation."""
        self._dot_count = (self._dot_count + 1) % 4
        dots = "." * self._dot_count
        if self._label:
            self._label.setStringValue_(f"Processing{dots}")


class FloatingOverlay:
    """Floating overlay window for visual feedback.

    Thread-safe: all AppKit calls are dispatched to the main thread.
    """

    # Pill dimensions
    WIDTH = 200
    HEIGHT = 40
    CORNER_RADIUS = 20
    MARGIN_BOTTOM = 80  # pixels from bottom of screen

    def __init__(self):
        self._state = OverlayState.HIDDEN
        self._window = None
        self._label = None
        self._dot_view = None
        self._animator = None
        self._hide_timer = None
        self._initialized = False

        if not HAS_APPKIT:
            return

        # Initialize on main thread
        self._perform_on_main(self._setup)

    def _perform_on_main(self, fn, *args):
        """Dispatch a function to the main thread."""
        try:
            from PyObjCTools import AppHelper
            AppHelper.callAfter(fn, *args)
        except Exception:
            # Fallback: just call directly (may not be on main thread)
            try:
                fn(*args)
            except Exception:
                pass

    def _setup(self):
        """Create the overlay window (must be called on main thread)."""
        if self._initialized:
            return

        try:
            screen = NSScreen.mainScreen()
            if not screen:
                return
            screen_frame = screen.frame()

            # Position: centered horizontally, near bottom of screen
            x = (screen_frame.size.width - self.WIDTH) / 2
            y = self.MARGIN_BOTTOM

            frame = NSMakeRect(x, y, self.WIDTH, self.HEIGHT)

            self._window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
                frame,
                NSWindowStyleMaskBorderless,
                NSBackingStoreBuffered,
                False,
            )
            self._window.setLevel_(NSWindowLevelFloating + 1)
            self._window.setOpaque_(False)
            self._window.setBackgroundColor_(NSColor.clearColor())
            self._window.setAlphaValue_(0.0)
            self._window.setHasShadow_(True)
            self._window.setIgnoresMouseEvents_(True)
            self._window.setCollectionBehavior_(
                NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary
            )

            # Visual effect view for blur background
            content = self._window.contentView()
            content_frame = content.frame()

            effect_view = NSVisualEffectView.alloc().initWithFrame_(content_frame)
            effect_view.setBlendingMode_(NSVisualEffectBlendingModeBehindWindow)
            effect_view.setMaterial_(NSVisualEffectMaterialHUDWindow)
            effect_view.setState_(1)  # Active
            effect_view.setWantsLayer_(True)
            effect_view.layer().setCornerRadius_(self.CORNER_RADIUS)
            effect_view.layer().setMasksToBounds_(True)
            effect_view.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
            content.addSubview_(effect_view)

            # Status label
            label_frame = NSMakeRect(10, 5, self.WIDTH - 20, self.HEIGHT - 10)
            self._label = NSTextField.alloc().initWithFrame_(label_frame)
            self._label.setEditable_(False)
            self._label.setBezeled_(False)
            self._label.setDrawsBackground_(False)
            self._label.setTextColor_(NSColor.whiteColor())
            self._label.setFont_(NSFont.systemFontOfSize_weight_(13, 0.3))
            self._label.setAlignment_(NSTextAlignmentCenter)
            self._label.setStringValue_("")
            content.addSubview_(self._label)

            # Create animator for processing dots
            self._animator = _OverlayAnimator.alloc().init()
            self._animator.setLabel_(self._label)

            self._initialized = True
        except Exception as e:
            print(f"⚠️  Overlay init failed: {e}")
            self._initialized = False

    def show_recording(self, style_label: str | None = None, with_context: bool = False):
        """Show recording indicator (red dot + "Recording...").

        Args:
            style_label:  Optional per-app style name to display (e.g. "code").
            with_context: When True, append "(with context)" to the label.
        """
        if not HAS_APPKIT:
            return
        self._perform_on_main(self._show_recording, style_label, with_context)

    def _show_recording(self, style_label=None, with_context=False):
        if not self._initialized:
            self._setup()
        if not self._initialized:
            return
        self._cancel_hide_timer()
        self._animator.stopAnimation()
        label = "🔴 Recording"
        if style_label:
            label += f" [{style_label}]"
        if with_context:
            label += " (with context)"
        label += "..."
        self._label.setStringValue_(label)
        self._label.setTextColor_(NSColor.whiteColor())
        self._fade_in()

    def show_streaming_text(self, text: str):
        """Show a live partial transcript during streaming mode."""
        if not HAS_APPKIT:
            return
        self._perform_on_main(self._show_streaming_text, text)

    def _show_streaming_text(self, text):
        if not self._initialized:
            return
        self._cancel_hide_timer()
        self._animator.stopAnimation()
        display = text if len(text) <= 35 else "…" + text[-32:]
        self._label.setStringValue_(f"🎙 {display}")
        self._label.setTextColor_(NSColor.colorWithWhite_alpha_(0.9, 1.0))
        if self._window.alphaValue() < 0.5:
            self._fade_in()

    def show_processing(self):
        """Show processing indicator (animated dots)."""
        if not HAS_APPKIT:
            return
        self._perform_on_main(self._show_processing)

    def _show_processing(self):
        if not self._initialized:
            return
        self._cancel_hide_timer()
        self._label.setStringValue_("Processing...")
        self._label.setTextColor_(NSColor.colorWithWhite_alpha_(0.9, 1.0))
        self._animator.startProcessingAnimation()
        # Ensure visible
        if self._window.alphaValue() < 0.5:
            self._fade_in()

    def show_result(self, text: str, duration: float = 2.0):
        """Briefly flash the result text, then hide."""
        if not HAS_APPKIT:
            return
        self._perform_on_main(self._show_result, text, duration)

    def _show_result(self, text, duration):
        if not self._initialized:
            return
        self._animator.stopAnimation()
        # Truncate for display
        display = text if len(text) <= 30 else text[:27] + "..."
        self._label.setStringValue_(f"✅ {display}")
        self._label.setTextColor_(NSColor.whiteColor())

        # Auto-resize window width for longer text
        text_width = max(self.WIDTH, min(400, len(display) * 9 + 40))
        screen = NSScreen.mainScreen()
        if screen:
            screen_frame = screen.frame()
            x = (screen_frame.size.width - text_width) / 2
            frame = NSMakeRect(x, self.MARGIN_BOTTOM, text_width, self.HEIGHT)
            self._window.setFrame_display_(frame, True)

        if self._window.alphaValue() < 0.5:
            self._fade_in()
        self._schedule_hide(duration)

    def show_learned(self, original: str, corrected: str, duration: float = 2.5):
        """Show a subtle dictionary learning notification.

        Displays a brief pill like "📚 mir → Meer" then fades out.
        Uses a smaller, dimmer style than the main overlay to avoid
        interrupting the user's flow.
        """
        if not HAS_APPKIT:
            return
        self._perform_on_main(self._show_learned, original, corrected, duration)

    def _show_learned(self, original, corrected, duration):
        if not self._initialized:
            self._setup()
        if not self._initialized:
            return
        self._cancel_hide_timer()
        self._animator.stopAnimation()

        display = f"📚 {original} → {corrected}"
        self._label.setStringValue_(display)
        # Subtle dim white — less attention-grabbing than result/error
        self._label.setTextColor_(NSColor.colorWithWhite_alpha_(0.75, 1.0))
        self._label.setFont_(NSFont.systemFontOfSize_weight_(12, 0.2))

        # Compact pill width
        text_width = max(160, min(350, len(display) * 8 + 40))
        screen = NSScreen.mainScreen()
        if screen:
            screen_frame = screen.frame()
            x = (screen_frame.size.width - text_width) / 2
            # Position slightly lower than main overlay
            frame = NSMakeRect(x, self.MARGIN_BOTTOM - 10, text_width, 32)
            self._window.setFrame_display_(frame, True)

        if self._window.alphaValue() < 0.5:
            self._fade_in()
        # Restore main font after hide
        self._schedule_hide(duration)

    def show_error(self, message: str, duration: float = 3.0):
        """Show an error message briefly."""
        if not HAS_APPKIT:
            return
        self._perform_on_main(self._show_error, message, duration)

    def _show_error(self, message, duration):
        if not self._initialized:
            return
        self._animator.stopAnimation()
        display = message if len(message) <= 35 else message[:32] + "..."
        self._label.setStringValue_(f"❌ {display}")
        self._label.setTextColor_(NSColor.colorWithRed_green_blue_alpha_(1.0, 0.4, 0.4, 1.0))
        if self._window.alphaValue() < 0.5:
            self._fade_in()
        self._schedule_hide(duration)

    def hide(self):
        """Hide the overlay."""
        if not HAS_APPKIT:
            return
        self._perform_on_main(self._hide)

    def _hide(self):
        if not self._initialized:
            return
        self._animator.stopAnimation()
        self._fade_out()

    def _fade_in(self):
        """Animate fade in."""
        self._window.orderFront_(None)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.currentContext().setDuration_(0.2)
        self._window.animator().setAlphaValue_(0.95)
        NSAnimationContext.endGrouping()

    def _fade_out(self):
        """Animate fade out."""
        NSAnimationContext.beginGrouping()
        NSAnimationContext.currentContext().setDuration_(0.3)
        self._window.animator().setAlphaValue_(0.0)
        NSAnimationContext.endGrouping()

    def _schedule_hide(self, delay: float):
        """Schedule auto-hide after delay."""
        self._cancel_hide_timer()
        self._hide_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            delay, self._animator, b"hideOverlay:", None, False
        )
        # Monkey-patch the animator to call our hide
        self._animator._overlay = self
        NSRunLoop.currentRunLoop().addTimer_forMode_(self._hide_timer, NSDefaultRunLoopMode)

    def _cancel_hide_timer(self):
        if self._hide_timer:
            self._hide_timer.invalidate()
            self._hide_timer = None


# Add hideOverlay: method to animator
if HAS_APPKIT:
    def _hide_overlay(self, timer):
        if hasattr(self, '_overlay') and self._overlay:
            self._overlay._hide()
    _OverlayAnimator.hideOverlay_ = _hide_overlay


# Module-level singleton
_overlay_instance = None


def get_overlay() -> FloatingOverlay:
    """Get or create the singleton overlay instance."""
    global _overlay_instance
    if _overlay_instance is None:
        _overlay_instance = FloatingOverlay()
    return _overlay_instance
