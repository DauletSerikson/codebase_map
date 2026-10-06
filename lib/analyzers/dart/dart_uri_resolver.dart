import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/dependency_graph/dependency.dart';
import '../../core/file_system/project_scan.dart';
import '../../core/file_system/project_scanner.dart';

class UriResolution {
  const UriResolution(this.status, {this.targetId, this.message});
  final ResolutionStatus status;
  final String? targetId;
  final String? message;
}

/// Resolves Dart URI syntax; filesystem probing stays behind the IO boundary.
class DartUriResolver {
  const DartUriResolver({this.fileSystem = const ProjectFileSystem()});
  final ProjectFileSystem fileSystem;

  Future<UriResolution> resolve({
    required ProjectInfo project,
    required Set<String> fileIds,
    required String sourceId,
    required String? originalUri,
  }) async {
    if (originalUri == null || originalUri.isEmpty) {
      return const UriResolution(
        ResolutionStatus.invalidUri,
        message: 'Missing or invalid directive URI.',
      );
    }
    try {
      final uri = Uri.parse(originalUri);
      if (uri.hasQuery ||
          uri.hasFragment ||
          uri.hasAuthority ||
          originalUri.contains('\\') ||
          uri.pathSegments.any(
            (segment) =>
                segment.contains('\u0000') ||
                segment.contains('\\') ||
                segment.contains('/'),
          )) {
        return const UriResolution(
          ResolutionStatus.invalidUri,
          message:
              'URI query, fragment, authority or backslash is unsupported.',
        );
      }
      if (uri.scheme == 'dart') {
        return UriResolution(
          uri.path.isEmpty ? ResolutionStatus.invalidUri : ResolutionStatus.sdk,
          message: uri.path.isEmpty ? 'Missing SDK library name.' : null,
        );
      }
      late Uri target;
      final root = Uri.directory(project.root);
      if (uri.scheme == 'package') {
        final segments = uri.pathSegments;
        if (segments.length < 2 ||
            segments.any(
              (s) =>
                  s.isEmpty ||
                  s == '..' ||
                  s == '.' ||
                  s.contains('/') ||
                  s.contains('\\'),
            )) {
          return const UriResolution(
            ResolutionStatus.invalidUri,
            message: 'Invalid package URI.',
          );
        }
        if (segments.first != project.packageName) {
          return const UriResolution(ResolutionStatus.externalPackage);
        }
        target = root.resolveUri(
          Uri(pathSegments: ['lib', ...segments.skip(1)]),
        );
      } else if (uri.scheme.isEmpty && !uri.path.startsWith('/')) {
        target = root.resolveUri(Uri(path: sourceId)).resolveUri(uri);
      } else {
        return const UriResolution(
          ResolutionStatus.invalidUri,
          message: 'Only relative, package: and dart: URIs are supported.',
        );
      }
      final nativePath = target.toFilePath();
      final relative = p
          .split(p.relative(nativePath, from: project.root))
          .join('/');
      if (fileIds.contains(relative)) {
        return UriResolution(ResolutionStatus.resolved, targetId: relative);
      }
      final type = await fileSystem.targetType(nativePath);
      if (type == FileSystemEntityType.file) {
        // Let the filesystem provide canonical spelling on case-insensitive
        // volumes. IDs retain the spelling collected by the scanner.
        final canonical = await fileSystem.resolveFile(nativePath);
        final canonicalId = p
            .split(p.relative(canonical, from: project.root))
            .join('/');
        if (fileIds.contains(canonicalId)) {
          return UriResolution(
            ResolutionStatus.resolved,
            targetId: canonicalId,
          );
        }
      }
      if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.link) {
        return const UriResolution(ResolutionStatus.outOfScope);
      }
      return const UriResolution(
        ResolutionStatus.unresolved,
        message: 'Local dependency target is not an existing source file.',
      );
    } on FormatException catch (error) {
      return UriResolution(ResolutionStatus.invalidUri, message: error.message);
    } on UnsupportedError catch (error) {
      return UriResolution(ResolutionStatus.invalidUri, message: error.message);
    } on FileSystemException catch (error) {
      return UriResolution(
        ResolutionStatus.fileSystemError,
        message: 'Cannot inspect dependency target: ${error.message}',
      );
    }
  }
}
