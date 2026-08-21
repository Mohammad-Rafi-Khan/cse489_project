import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles photo proof picking from Camera/Gallery and uploading to Supabase Storage.
class StorageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  static const String taskPhotosBucket = 'task-photos';

  /// Picks an image from either camera or gallery.
  Future<XFile?> pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      debugPrint('Error picking image: $e');
      rethrow;
    }
  }

  /// Uploads image bytes and returns a temporary signed URL for the private object.
  Future<String> uploadTaskPhoto({
    required XFile file,
    required String assignmentId,
    required String userId,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final extension = file.name.split('.').last.toLowerCase();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
      final storagePath = '$userId/$assignmentId/$fileName';

      // Upload to bucket
      await _supabase.storage.from(taskPhotosBucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentTypeForExtension(extension),
              upsert: true,
            ),
          );

        return await _supabase.storage
          .from(taskPhotosBucket)
          .createSignedUrl(storagePath, 3600);
    } catch (e) {
      debugPrint('Storage upload error: $e');
      rethrow;
    }
  }

  String _contentTypeForExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
