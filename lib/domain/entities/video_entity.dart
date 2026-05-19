import 'package:path/path.dart' as p;

class VideoEntity {
  final String path;
  final bool isNetwork;
  final String? title;

  const VideoEntity({required this.path, this.isNetwork = false, this.title});

  String get name => title ?? p.basename(path);
}
