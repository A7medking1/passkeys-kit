import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_state.dart';
import 'src/config.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/sign_in_screen.dart';
import 'src/theme.dart';

void main() {
  runApp(PasskeysKitExample(state: AppState(serverUrl: serverUrl())));
}

class PasskeysKitExample extends StatelessWidget {
  const PasskeysKitExample({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // A dark app: light status bar icons on every screen.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AppScope(
        state: state,
        child: MaterialApp(
          title: 'Passkeys Kit',
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: const _Start(),
        ),
      ),
    );
  }
}

/// The sign-in screen, or the home screen once signed in.
class _Start extends StatelessWidget {
  const _Start();

  @override
  Widget build(BuildContext context) => AppScope.of(context).isSignedIn
      ? const HomeScreen()
      : const SignInScreen();
}
