import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/telegram_auth_notifier.dart';
import '../../l10n/l10n.dart';

import 'package:window_manager/window_manager.dart';
import '../widgets/window_controls.dart';

class TelegramLoginScreen extends ConsumerStatefulWidget {
  const TelegramLoginScreen({super.key});

  @override
  ConsumerState<TelegramLoginScreen> createState() =>
      _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends ConsumerState<TelegramLoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(telegramAuthProvider);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.telegramConnectTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
        actions: const [
          SizedBox(width: 8),
          WindowControls(),
          SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                LucideIcons.send,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 32),
              if (authState.error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Text(
                    authState.error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              _buildForm(context, authState),
              if (authState.isLoading) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, TelegramAuthState state) {
    final t = AppLocalizations.of(context);
    if (state.list == AuthState.waitPhoneNumber ||
        state.list == AuthState.initial) {
      return Column(
        children: [
          Text(
            t.telegramEnterPhone,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: t.telegramPhoneLabel,
              hintText: t.telegramPhoneHint,
              border: OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.phone),
            ),
            keyboardType: TextInputType.phone,
            onSubmitted: (val) =>
                ref.read(telegramAuthProvider.notifier).setPhoneNumber(val),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: state.isLoading
                ? null
                : () => ref
                      .read(telegramAuthProvider.notifier)
                      .setPhoneNumber(_phoneController.text),
            child: Text(t.telegramSendCode),
          ),
        ],
      );
    } else if (state.list == AuthState.waitCode) {
      return Column(
        children: [
          Text(
            '${t.telegramCodeSent} ${_phoneController.text}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: InputDecoration(
              labelText: t.telegramCodeLabel,
              border: OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.lock),
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (val) =>
                ref.read(telegramAuthProvider.notifier).checkCode(val),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: state.isLoading
                ? null
                : () => ref
                      .read(telegramAuthProvider.notifier)
                      .checkCode(_codeController.text),
            child: Text(t.telegramVerifyCode),
          ),
        ],
      );
    } else if (state.list == AuthState.waitPassword) {
      return Column(
        children: [
          Text(
            t.telegramPasswordHint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: t.telegramPasswordLabel,
              border: OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.key),
            ),
            obscureText: true,
            onSubmitted: (val) =>
                ref.read(telegramAuthProvider.notifier).checkPassword(val),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: state.isLoading
                ? null
                : () => ref
                      .read(telegramAuthProvider.notifier)
                      .checkPassword(_passwordController.text),
            child: Text(t.telegramUnlock),
          ),
        ],
      );
    } else {
      return const SizedBox();
    }
  }
}
