@HtmlImport('join_button.html')
library woven.client.components.join_button;

import 'dart:async';
import "dart:html";

import "package:polymer/polymer.dart";
import 'package:firebase/firebase.dart' as db;

import 'package:woven/config/config.dart';
import 'package:woven/src/client/app.dart';
import 'package:woven/src/shared/input_formatter.dart';
import 'package:woven/src/shared/model/community.dart';

@CustomTag("join-button")
class JoinButton extends PolymerElement {
  @published CommunityModel community;
  @published App app;

  db.Firebase get f => app.f;

  JoinButton.created() : super.created();

  void toggleStar(Event e, var detail, Element target) {
    // Don't fire the core-item's on-click, just the icon's.
    e.stopPropagation();

    if (app.user == null)
      return app.showMessage("Kindly sign in first.", "important");

    var starredCommunityRef = f.child('/starred_by_user/' +
        app.user.username.toLowerCase() +
        '/communities/' +
        community.alias);
    var communityRef = f.child('/communities/' + community.alias);

    if (community.starred) {
      // If it's starred, time to unstar it.
      community.starred = false;
      starredCommunityRef.remove();

      app.analytics.sendEvent('Channel', 'leave', label: community.alias);

      // Update the star count.
      communityRef.child('/star_count').transaction((currentCount) {
        if (currentCount == null || currentCount == 0) {
          community.starCount = 0;
          return 0;
        } else {
          community.starCount = currentCount - 1;
          return community.starCount;
        }
      });

      // Update the list of users who starred.
      f
          .child('/users_who_starred/community/' +
              community.alias +
              '/' +
              app.user.username.toLowerCase())
          .remove();
    } else {
      // If it's not starred, time to star it.
      community.starred = true;
      starredCommunityRef.set(true);

      app.analytics.sendEvent('Channel', 'join', label: community.alias);

      // Update the star count.
      communityRef.child('/star_count').transaction((currentCount) {
        if (currentCount == null || currentCount == 0) {
          community.starCount = 1;
          return 1;
        } else {
          community.starCount = currentCount + 1;
          return community.starCount;
        }
      });

      // Update the list of users who starred.
      f
          .child('/users_who_starred/community/' +
              community.alias +
              '/' +
              app.user.username.toLowerCase())
          .set(true);
    }
  }

  /**
   * Stop the link click from also firing other events.
   */
  stopPropagation(Event e) {
    e.stopPropagation();
  }
}
