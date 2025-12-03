class VideoEntity {
  final String path;
  final bool isNetwork;
  final String? title;

  const VideoEntity({required this.path, this.isNetwork = false, this.title});

  String get name => title ?? path.split('/').last;
}
