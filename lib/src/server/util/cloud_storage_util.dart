library cloud_storage_util;

import 'dart:io';
import 'dart:async';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis/common/common.dart' show DownloadOptions, Media;

class CloudStorageUtil {
  storage.StorageApi storageApi;

  CloudStorageUtil(googleApiClient) {
    this.storageApi = new storage.StorageApi(googleApiClient);
  }
// Upload a file to Google Cloud Storage.
  Future uploadFile(String file,
                    String bucket,
                    String object,
                    {public: false}) {
    // We create a `Media` object with a `Stream` of bytes and the length of the
    // file. This media object is passed to the API call via `uploadMedia`.
    var localFile = new File(file);
    var media = new Media(localFile.openRead(), localFile.lengthSync());
    return storageApi.objects.insert(null, bucket, name: object, uploadMedia: media, predefinedAcl: public ? 'publicRead': null);
  }

// Download a file from Google Cloud Storage.
  Future downloadFile(storage.StorageApi api,
                      String bucket,
                      String object,
                      String file) {
    // The default for `downloadOptions` is metadata. This would only give us the
    // metadata of the Object in Cloud Storage. We specify the `FullMedia` option
    // which will return a `Media` object.
    var options = DownloadOptions.FullMedia;
    return api.objects.get(
        bucket, object, downloadOptions: options).then((Media media) {
      var fileStream = new File(file).openWrite();
      return media.stream.pipe(fileStream);
    });
  }
}