// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_emoji_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CustomEmoji)
const customEmojiProvider = CustomEmojiFamily._();

final class CustomEmojiProvider
    extends $NotifierProvider<CustomEmoji, CustomEmojiState> {
  const CustomEmojiProvider._({
    required CustomEmojiFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'customEmojiProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$customEmojiHash();

  @override
  String toString() {
    return r'customEmojiProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CustomEmoji create() => CustomEmoji();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CustomEmojiState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CustomEmojiState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CustomEmojiProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$customEmojiHash() => r'36d4a6ded7bc5deee20c436df072cab63f6a0cec';

final class CustomEmojiFamily extends $Family
    with
        $ClassFamilyOverride<
          CustomEmoji,
          CustomEmojiState,
          CustomEmojiState,
          CustomEmojiState,
          int
        > {
  const CustomEmojiFamily._()
    : super(
        retry: null,
        name: r'customEmojiProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  CustomEmojiProvider call(int customEmojiId) =>
      CustomEmojiProvider._(argument: customEmojiId, from: this);

  @override
  String toString() => r'customEmojiProvider';
}

abstract class _$CustomEmoji extends $Notifier<CustomEmojiState> {
  late final _$args = ref.$arg as int;
  int get customEmojiId => _$args;

  CustomEmojiState build(int customEmojiId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<CustomEmojiState, CustomEmojiState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CustomEmojiState, CustomEmojiState>,
              CustomEmojiState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
