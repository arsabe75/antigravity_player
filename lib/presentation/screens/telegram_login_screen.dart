import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/telegram_auth_notifier.dart';

import 'package:window_manager/window_manager.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Telegram'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
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
    if (state.list == AuthState.waitPhoneNumber ||
        state.list == AuthState.initial) {
      return Column(
        children: [
          const Text(
            'Enter your phone number starting with +',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              hintText: '+1234567890',
              border: OutlineInputBorder(),
              prefixIcon: Icon(LucideIcons.phone),
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
            child: const Text('Send Code'),
          ),
        ],
      );
    } else if (state.list == AuthState.waitCode) {
      return Column(
        children: [
          Text(
            'Enter the code sent to ${_phoneController.text}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Code',
              border: OutlineInputBorder(),
              prefixIcon: Icon(LucideIcons.lock),
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
            child: const Text('Verify Code'),
          ),
        ],
      );
    } else if (state.list == AuthState.waitPassword) {
      return Column(
        children: [
          const Text(
            'Enter your Two-Step Verification password',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(LucideIcons.key),
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
            child: const Text('Unlock'),
          ),
        ],
      );
    } else {
      return const SizedBox();
    }
  }
}
