/// Microphone lifecycle + consent state for one reading session
/// (PRD §8 Unit 4 "Microphone lifecycle", §8 Unit 10 consent).
///
/// Pinned design this class encodes:
/// - The mic is open **only** while an active reading/practice interaction
///   owns it (the reading screen, twister nodes, Sound Garden echo) — never
///   on navigation or parent screens. A session is opened at
///   `ReadingTracker.start()`/`resume()` and closed at `pause()`/`stop()`,
///   on fallback to tap mode, and the moment consent is revoked.
/// - A small, non-alarming "listening" indicator is visible whenever the mic
///   is open. The indicator widget is the design system's and the reading
///   screen's to place; this unit only exposes the state it renders, surfaced
///   as `ReadingTracker.isListening`.
/// - Consent (Unit 10) takes effect **immediately**: it is read per session
///   start and again on every change. Without consent the mic never opens at
///   all — the tracker starts directly in tap mode.
///
/// Deliberately platform-free: there is no permission plugin, no audio
/// route, and no buffer here. Acquiring the OS microphone is the ASR
/// engine's job behind the `AsrEngine` seam; this type is the tracker's
/// bookkeeping of *whether it is allowed to, and whether it currently has
/// it open*, which is the only part Units 5-6 observe.
library;

/// Consent-gated open/closed state of the microphone for one session.
class MicSession {
  /// Creates a session for a profile whose current consent state is
  /// [consentGranted]. The session starts closed.
  MicSession({required bool consentGranted}) : _consentGranted = consentGranted;

  bool _consentGranted;
  bool _isOpen = false;

  /// Whether microphone consent is currently granted (Unit 10).
  bool get consentGranted => _consentGranted;

  /// Whether the microphone is open right now.
  ///
  /// This is the flag the design-system listening indicator renders, exposed
  /// upward as `ReadingTracker.isListening`.
  bool get isOpen => _isOpen;

  /// Whether [open] would succeed — i.e. consent is granted.
  bool get canOpen => _consentGranted;

  /// Opens the session if consent allows.
  ///
  /// Returns true when the mic is (now) open, false when consent forbids it —
  /// the caller then degrades to tap mode rather than surfacing an error.
  bool open() {
    if (!_consentGranted) {
      _isOpen = false;
      return false;
    }
    _isOpen = true;
    return true;
  }

  /// Closes the session. Idempotent.
  void close() {
    _isOpen = false;
  }

  /// Applies a consent change immediately (Unit 10: changes take effect at
  /// once, not at the next session). Revoking consent closes the session in
  /// the same call.
  void updateConsent(bool granted) {
    _consentGranted = granted;
    if (!granted) close();
  }

  @override
  String toString() =>
      'MicSession(consentGranted: $_consentGranted, isOpen: $_isOpen)';
}
