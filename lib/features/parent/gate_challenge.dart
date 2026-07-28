/// Gate challenge widget: a written multiplication challenge for adult users.
///
/// Part of the parental gate mechanism (PRD §8 Unit 10, A-4 stage 2). This
/// widget displays a multiplication problem with two factors and solicits a
/// numeric answer via a text input field. Designed to be solvable by adults
/// but not guessable by pre-readers through random interaction.
///
/// The challenge is stateless: regeneration (on wrong answers) is handled by
/// the parent [ParentalGate] widget, which passes new factor values.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:learn_to_read/design/tokens.dart';

/// A multiplication challenge widget for the parental gate.
///
/// Displays a multiplication problem (factor1 × factor2) with a numeric input
/// field for the answer and a submit button.
///
/// **Parameters:**
/// - `factor1`: First factor (typically 1-99, single or double digits)
/// - `factor2`: Second factor (typically 1-99, single or double digits)
/// - `onAnswerSubmitted`: Callback when an answer is submitted. Returns a
///   `Future<bool>` indicating whether the answer was correct. The widget clears
///   the input field after submission regardless of correctness.
///
/// **Semantics:**
/// - Numeric-only input (letters and special characters rejected)
/// - Empty answers are rejected (submit button disabled or callback not invoked)
/// - Wrong answers clear the input field and remain on the challenge
/// - Correct answers pass control back to the parent gate widget
/// - Challenge uses design tokens only (no hardcoded colors or fonts)
/// - Respects safe area boundaries across all layout classes
class GateChallenge extends StatefulWidget {
  /// Creates a multiplication challenge.
  const GateChallenge({
    super.key,
    required this.factor1,
    required this.factor2,
    required this.onAnswerSubmitted,
  });

  /// First factor of the multiplication problem.
  final int factor1;

  /// Second factor of the multiplication problem.
  final int factor2;

  /// Callback invoked when an answer is submitted.
  ///
  /// Called with the user's entered answer (as a string). Should return
  /// `Future<bool>` indicating whether the answer is correct.
  final Future<bool> Function(String answer) onAnswerSubmitted;

  @override
  State<GateChallenge> createState() => _GateChallengeState();
}

class _GateChallengeState extends State<GateChallenge> {
  late TextEditingController _controller;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    // Listen for text changes to update button state
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Rebuild when text changes to update button enable/disable state
    setState(() {});
  }

  Future<void> _handleSubmit() async {
    final answer = _controller.text.trim();

    setState(() => _isSubmitting = true);

    try {
      final isCorrect = await widget.onAnswerSubmitted(answer);

      if (mounted) {
        setState(() => _isSubmitting = false);

        if (!isCorrect) {
          // Clear the field for the next attempt
          _controller.clear();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Challenge prompt text
            Text(
              'Solve the multiplication problem:',
              style: TextStyle(
                color: DesignTokens.wordUnreadInk,
                fontFamily: DesignTokens.displayFontFamily,
                fontSize: 20.0,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignTokens.spacingLg),

            // Display the multiplication problem
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingLg,
                vertical: DesignTokens.spacingMd,
              ),
              decoration: BoxDecoration(
                color: DesignTokens.surfaceBackground,
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${widget.factor1}',
                      style: TextStyle(
                        color: DesignTokens.wordUnreadInk,
                        fontFamily: DesignTokens.readingFontFamily,
                        fontSize: 32.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spacingMd),
                    Text(
                      '×',
                      style: TextStyle(
                        color: DesignTokens.wordUnreadInk,
                        fontFamily: DesignTokens.readingFontFamily,
                        fontSize: 32.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spacingMd),
                    Text(
                      '${widget.factor2}',
                      style: TextStyle(
                        color: DesignTokens.wordUnreadInk,
                        fontFamily: DesignTokens.readingFontFamily,
                        fontSize: 32.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spacingMd),
                    Text(
                      '=',
                      style: TextStyle(
                        color: DesignTokens.wordUnreadInk,
                        fontFamily: DesignTokens.readingFontFamily,
                        fontSize: 32.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spacingMd),
                    Text(
                      '?',
                      style: TextStyle(
                        color: DesignTokens.wordUnreadInk,
                        fontFamily: DesignTokens.readingFontFamily,
                        fontSize: 32.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingLg),

            // Input field for the answer
            SizedBox(
              width: 200.0,
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                enabled: !_isSubmitting,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DesignTokens.wordUnreadInk,
                  fontFamily: DesignTokens.readingFontFamily,
                  fontSize: 24.0,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter answer',
                  hintStyle: TextStyle(
                    color: DesignTokens.wordUnreadInk.withAlpha(128),
                    fontFamily: DesignTokens.readingFontFamily,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(
                      color: DesignTokens.wordUnreadInk.withAlpha(64),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(
                      color: DesignTokens.wordReadGreen,
                      width: 2.0,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(
                      color: DesignTokens.wordUnreadInk.withAlpha(32),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingLg),

            // Submit button
            ElevatedButton(
              onPressed: _isSubmitting ? null : () => _handleSubmit(),
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignTokens.wordReadGreen,
                disabledBackgroundColor: DesignTokens.wordReadGreen.withAlpha(
                  128,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingLg,
                  vertical: DesignTokens.spacingMd,
                ),
              ),
              child: Text(
                _isSubmitting ? 'Checking...' : 'Submit',
                style: const TextStyle(
                  // Token-lint (PRD §8 Unit 1 accept #6): no raw Colors.*
                  // literals under lib/features/. readingBackground is the
                  // token palette's near-white shade, giving legible
                  // contrast against the wordReadGreen button fill.
                  color: DesignTokens.readingBackground,
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
