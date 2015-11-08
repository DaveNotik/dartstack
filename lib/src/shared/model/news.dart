library shared.model.news;

import 'item.dart';

class NewsModel implements Item {
  String id;
  String user;
  String usernameForDisplay;
  String type;
  DateTime createdDate = new DateTime.now().toUtc();
  DateTime updatedDate = new DateTime.now().toUtc();
  String subject;
  String body;
  String url;
  String uriPreviewId;

  Map encode() {
    return {
      "user": user,
      "subject": subject,
      "type": type,
      "body": body,
      "createdDate": createdDate.toString(),
      "updatedDate": updatedDate.toString(),
      "url": url,
      "uriPreviewId": uriPreviewId
    };
  }

  static NewsModel decode(Map data) {
    return new NewsModel()
      ..user = data['user']
      ..type = data['type']
      ..subject = data['subject']
      ..body = data['body']
      ..createdDate = data['createdDate']
      ..updatedDate = data['updatedDate']
      ..url = data['url']
      ..uriPreviewId = data['uriPreviewId'];
  }
}
