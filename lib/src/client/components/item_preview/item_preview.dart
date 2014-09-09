import 'package:polymer/polymer.dart';
import 'dart:html';
import 'dart:async';
import 'dart:math';
import 'package:woven/src/client/app.dart';
import 'package:woven/src/shared/input_formatter.dart';
import 'package:firebase/firebase.dart' as db;
import 'package:woven/config/config.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

@CustomTag('item-preview')
class ItemPreview extends PolymerElement {
  @published App app;
  @observable Map item;

  get formattedBody {
    if (app.selectedItem == null) return '';
    return "${InputFormatter.nl2br(app.selectedItem['body'])}";
  }

  String formatItemDate(DateTime value) {
    return InputFormatter.formatMomentDate(value, short: true, momentsAgo: true);
  }

  void getItem() {
    if (app.selectedItem != null) {
      item = app.selectedItem;
      print("have selecteditem");

    } else {
      print("no selecteditem");
      // If there's no app.selectedItem, we probably
      // came here directly, so let's get it.

      // Decode the base64 URL and determine the item.
      var base64 = Uri.parse(window.location.toString()).pathSegments[1];
      var bytes = CryptoUtils.base64StringToBytes(base64);
      var decodedItem = UTF8.decode(bytes);

      var f = new db.Firebase(config['datastore']['firebaseLocation']);

      f.child('/items/' + decodedItem).onValue.first.then((e) {
        item = e.snapshot.val();
        print(item);

        // The live-date-time element needs parsed dates.
        item['createdDate'] = DateTime.parse(item['createdDate']);

        // snapshot.name is Firebase's ID, i.e. "the name of the Firebase location"
        // So we'll add that to our local item list.
        item['id'] = e.snapshot.name();

        // Listen for realtime changes to the star count.
        f.child('/items/' + item['id'] + '/star_count').onValue.listen((e) {
          print("Starq count changed ${e.snapshot.val()}");
          item['star_count'] = (e.snapshot.val() != null) ? e.snapshot.val() : 0;
        });

        // Listen for realtime changes to the like count.
        f.child('/items/' + item['id'] + '/like_count').onValue.listen((e) {
          print("Like count changed ${e.snapshot.val()}");
          item['like_count'] = (e.snapshot.val() != null) ? e.snapshot.val() : 0;
        });

//        loadItemUserStarredLikedInformation(item['id']);

        print(item);

        app.selectedItem = item;

      }).then((e) {
        HtmlElement body = $['body'];
        body.innerHtml = formattedBody;
      });
    }

    if (app.selectedItem != null) {
      // Trick to respect line breaks.
      HtmlElement body = $['body'];
      body.innerHtml = formattedBody;
    }
  }

  void loadItemUserStarredLikedInformation(item) {
    var f = new db.Firebase(config['datastore']['firebaseLocation']);

    if (app.user != null) {
      var starredItemsRef = f.child('/starred_by_user/' + app.user.username + '/items/' + item['id']);
      var likedItemsRef = f.child('/liked_by_user/' + app.user.username + '/items/' + item['id']);
      starredItemsRef.onValue.listen((e) {
        item['starred'] = e.snapshot.val() != null;
      });
      likedItemsRef.onValue.listen((e) {
        item['liked'] = e.snapshot.val() != null;
      });
    } else {
      item['starred'] = false;
      item['liked'] = false;
    }
  }


  void toggleStar(Event e, var detail, Element target) {
    if (app.user == null) return app.showMessage("Kindly sign in first.", "important");

    var f = new db.Firebase(config['datastore']['firebaseLocation']);
    var starredItemRef = f.child('/starred_by_user/' + app.user.username + '/items/' + app.selectedItem['id']);
    var itemRef = f.child('/items/' + app.selectedItem['id']);

    if (item['starred']) {
      // If it's starred, time to unstar it.
      item['starred'] = false;
      starredItemRef.remove();

      // Update the star count.
      itemRef.child('/star_count').transaction((currentCount) {
        if (currentCount == null || currentCount == 0) {
          app.selectedItem['id']['star_count'] = 0;
          return 0;
        } else {
          app.selectedItem['id']['star_count'] = currentCount - 1;
          return item['star_count'];
        }
      });

      // Update the list of users who starred.
      f.child('/users_who_starred/item/' + item['id'] + '/' + app.user.username).remove();
    } else {
      // If it's not starred, time to star it.
      item['starred'] = true;
      starredItemRef.set(true);

      // Update the star count.
      itemRef.child('/star_count').transaction((currentCount) {
        if (currentCount == null || currentCount == 0) {
          app.selectedItem['id']['star_count'] = 1;
          return 1;
        } else {
          app.selectedItem['id']['star_count'] = currentCount + 1;
          return item['star_count'];
        }
      });

      // Update the list of users who starred.
      f.child('/users_who_starred/item/' + item['id'] + '/' + app.user.username).set(true);
    }
  }

  void toggleLike(Event e, var detail, Element target) {
    if (app.user == null) return app.showMessage("Kindly sign in first.", "important");

    var item = target.dataset['id'];

    var f = new db.Firebase(config['datastore']['firebaseLocation']);
    var starredItemRef = f.child('/liked_by_user/' + app.user.username + '/items/' + app.selectedItem['id']);
    var itemRef = f.child('/items/' + app.selectedItem['id']);

    if (item['liked']) {
      // If it's starred, time to unstar it.
      item['liked'] = false;
      starredItemRef.remove();

      // Update the star count.
      itemRef.child('/like_count').transaction((currentCount) {
        if (currentCount == null || currentCount == 0) {
          item['like_count'] = 0;
          return 0;
        } else {
          item['like_count'] = currentCount - 1;
          return item['like_count'];
        }
      });

      // Update the list of users who liked.
      f.child('/users_who_liked/item/' + app.selectedItem['id'] + '/' + app.user.username).remove();
    } else {
      // If it's not starred, time to star it.
      item['liked'] = true;
      starredItemRef.set(true);

      // Update the star count.
      itemRef.child('/like_count').transaction((currentCount) {
        if (currentCount == null || currentCount == 0) {
          item['like_count'] = 1;
          return 1;
        } else {
          item['like_count'] = currentCount + 1;
          return item['like_count'];
        }
      });

      // Update the list of users who liked.
      f.child('/users_who_liked/item/' + app.selectedItem['id'] + '/' + app.user.username).set(true);
    }
  }

  attached() {
    print("+Item");
    getItem();
    app.pageTitle = "";
  }

  detached() {
    //
  }

  ItemPreview.created() : super.created();
}
