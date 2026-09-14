import 'package:flutter/material.dart';

import '../../widgets/branding.dart';

/// Original first-launch onboarding + terms flow (extracted unchanged).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onAccepted});

  final Future<void> Function() onAccepted;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  static const int _slideCount = 5;
  int _page = 0;
  bool _agreed = false;
  bool _submitting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _slideCount - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    if (!_agreed || _submitting) return;

    setState(() => _submitting = true);
    await widget.onAccepted();
    if (!mounted) return;
    setState(() => _submitting = false);
  }

  Future<void> _back() async {
    if (_page == 0) return;
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _skipToTerms() async {
    if (_page >= _slideCount - 1) {
      return;
    }

    await _pageController.animateToPage(
      _slideCount - 1,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  Widget _buildBullet(ColorScheme scheme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlide({
    required IconData icon,
    required String title,
    required String body,
    required String kicker,
    Widget? footer,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primaryContainer,
                          scheme.surfaceContainerHighest,
                        ],
                      ),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      size: 30,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: scheme.primaryContainer.withValues(alpha: 0.55),
                    ),
                    child: Text(
                      kicker,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  if (footer != null) ...[const SizedBox(height: 20), footer],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTutorialFooter(ColorScheme scheme) {
    final List<String> supportedGestures = <String>[
      'Open Palm',
      'Closed Fist',
      'Pointing Up',
      'Thumb Up',
      'Thumb Down',
      'Victory',
      'I Love You',
      'None',
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.78),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.asset(
              'assets/tutorial/hand_signs_guide.png',
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recognized gestures',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: supportedGestures
                      .map((String gesture) => Chip(label: Text(gesture)))
                      .toList(),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tip: Start with Open Palm, Closed Fist, and Victory for best consistency.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'If prediction flickers, move to better lighting and keep only one hand in frame.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsFooter(ColorScheme scheme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.78),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBullet(
                  scheme,
                  'Accuracy is not guaranteed. Always verify critical meaning with a qualified interpreter.',
                ),
                _buildBullet(
                  scheme,
                  'Do not rely on this app alone for medical, legal, emergency, or high-risk decisions.',
                ),
                _buildBullet(
                  scheme,
                  'Camera and microphone data are used only to run translation features while you are using them.',
                ),
                _buildBullet(
                  scheme,
                  'Use in safe environments. Never operate while driving, crossing roads, or in hazardous settings.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: scheme.secondaryContainer.withValues(alpha: 0.28),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data and reliability summary',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _buildBullet(
                  scheme,
                  'Recognition confidence can vary with lighting, camera angle, and hand visibility.',
                ),
                _buildBullet(
                  scheme,
                  'No cloud upload is required for basic translation flow; permissions can be revoked in Settings.',
                ),
                _buildBullet(
                  scheme,
                  'You remain responsible for verifying critical communication outcomes.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('I agree to the Terms and Conditions'),
            subtitle: const Text(
              'You can review this notice again later in the About page.',
            ),
            value: _agreed,
            onChanged: (bool? value) {
              setState(() => _agreed = value ?? false);
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double progress = (_page + 1) / _slideCount;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -120,
            left: -70,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer.withValues(alpha: 0.48),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            right: -80,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.tertiaryContainer.withValues(alpha: 0.35),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.44),
                  scheme.surface,
                  scheme.surface,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Card(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    SmartBridgeLogo(
                                      size: 46,
                                      backgroundColor: scheme.surface,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'SmartBridge Setup',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                          Text(
                                            'Step ${_page + 1} of $_slideCount',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    minHeight: 8,
                                    value: progress,
                                    backgroundColor:
                                        scheme.surfaceContainerHighest,
                                  ),
                                ),
                                if (_page < _slideCount - 1) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _skipToTerms,
                                      icon: const Icon(
                                        Icons.fast_forward_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Skip to Terms'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: PageView(
                              controller: _pageController,
                              onPageChanged: (int value) =>
                                  setState(() => _page = value),
                              children: [
                                _buildSlide(
                                  icon: Icons.waving_hand_rounded,
                                  kicker: 'Welcome',
                                  title:
                                      'Your communication bridge starts here',
                                  body:
                                      'SmartBridge helps you turn hand gestures, speech, and text into faster two-way communication.',
                                  footer: Align(
                                    alignment: Alignment.topLeft,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: const [
                                        Chip(label: Text('Camera recognition')),
                                        Chip(label: Text('Speech-to-text')),
                                        Chip(label: Text('Text-to-speech')),
                                        Chip(
                                          label: Text('Accessibility controls'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _buildSlide(
                                  icon: Icons.hub_outlined,
                                  kicker: 'Workflow',
                                  title: 'Translate in three quick steps',
                                  body:
                                      '1) Keep your hand centered. 2) Hold the gesture steady for a moment. 3) Review confidence and optional voice output.',
                                  footer: Align(
                                    alignment: Alignment.topLeft,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildBullet(
                                          scheme,
                                          'Best performance in bright, even lighting.',
                                        ),
                                        _buildBullet(
                                          scheme,
                                          'Use one visible hand at a time for clearer results.',
                                        ),
                                        _buildBullet(
                                          scheme,
                                          'Keep 40–80 cm distance from the camera.',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _buildSlide(
                                  icon: Icons.image_search_outlined,
                                  kicker: 'Tutorial',
                                  title: 'Sample hand-sign guide',
                                  body:
                                      'Use this quick visual reference to practice supported gestures before running live recognition.',
                                  footer: _buildTutorialFooter(scheme),
                                ),
                                _buildSlide(
                                  icon: Icons.accessibility_new,
                                  kicker: 'Accessibility',
                                  title: 'Adapt SmartBridge to your comfort',
                                  body:
                                      'Tune text size, contrast, haptics, motion, and voice behavior anytime from Settings.',
                                  footer: Align(
                                    alignment: Alignment.topLeft,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildBullet(
                                          scheme,
                                          'High contrast mode for stronger readability.',
                                        ),
                                        _buildBullet(
                                          scheme,
                                          'Reduced motion if you are sensitive to animation.',
                                        ),
                                        _buildBullet(
                                          scheme,
                                          'Voice speed, pitch, and volume controls.',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _buildSlide(
                                  icon: Icons.gavel_rounded,
                                  kicker: 'Agreement',
                                  title: 'Terms and Conditions',
                                  body:
                                      'Please review these usage conditions carefully before entering the app.',
                                  footer: _buildTermsFooter(scheme),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                for (int i = 0; i < _slideCount; i++)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    margin: const EdgeInsets.only(right: 6),
                                    width: i == _page ? 22 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: i == _page
                                          ? scheme.primary
                                          : scheme.outlineVariant.withValues(
                                              alpha: 0.5,
                                            ),
                                    ),
                                  ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _page == 0 ? null : _back,
                                  child: const Text('Back'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed:
                                      (_page == _slideCount - 1 && !_agreed) ||
                                          _submitting
                                      ? null
                                      : _next,
                                  child: Text(
                                    _page == _slideCount - 1
                                        ? (_submitting
                                              ? 'Entering...'
                                              : 'Enter App')
                                        : 'Next',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Adapter used by the messaging app entry point: wraps the original
/// OnboardingFlow with the callback signature main.dart expects.
class OnboardingGate extends StatelessWidget {
  const OnboardingGate({super.key, required this.onAccepted});

  final Future<void> Function() onAccepted;

  @override
  Widget build(BuildContext context) {
    return OnboardingFlow(onAccepted: onAccepted);
  }
}
