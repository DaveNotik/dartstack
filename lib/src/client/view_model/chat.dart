library chat_view_model;

import 'package:polymer/polymer.dart';
import 'package:firebase/firebase.dart' as db;
import 'package:woven/config/config.dart';
import 'package:woven/src/client/app.dart';
import 'dart:async';
import 'dart:html';
import 'dart:js';
import 'base.dart';
import 'package:woven/src/client/components/chat_view/chat_view.dart';
import 'package:woven/src/shared/model/message.dart';
import 'package:woven/src/client/model/user.dart';
import 'package:woven/src/shared/input_formatter.dart';

class ChatViewModel extends BaseViewModel with Observable {
  final App app;
  final List messages = toObservable([]);
  List queuedMessages = [];
  // TODO: Use this later for date separators between messages.
  final Map groupedItems = toObservable({});

  int pageSize = 25;
  @observable bool reloadingContent = false;
  @observable bool reachedEnd = false;
  @observable bool isScrollPosAtBottom = false;
  bool isFirstLoad = true;
  var lastPriority = null;
  var topPriority = null;
  var secondToLastPriority = null;
  int totalCount = 0;

  StreamSubscription childAddedSubscriber, childChangedSubscriber, childMovedSubscriber, childRemovedSubscriber;

  ChatView get chatView => document.querySelector('woven-app').shadowRoot.querySelector('chat-view');

  db.Firebase get f => app.f;

  ChatViewModel({this.app}) {
    loadMessagesByPage();
  }

  /**
   * Load items pageSize at a time.
   */
  Future loadMessagesByPage() {
    reloadingContent = true;
    int count = 0;

    var messagesRef = f.child('/messages_by_community/${app.community.alias}')
    .startAt(priority: lastPriority)
    .limit(pageSize + 1);

    if (messages.length == 0) onLoadCompleter.complete(true);

    // Get the list of items, and listen for new ones.
    return messagesRef.once('value').then((snapshot) {
      Map messages = snapshot.exportVal();
      if (messages == null) {
        reachedEnd = true;
        return null;
      }
      List messagesAsList = [];
      messages.forEach((k,v) {
        Map message = v;
        message['id'] = k;
        messagesAsList.add(message);
      });

      return Future.forEach(messagesAsList, (message) {
        count++;
        totalCount++;

        // Make sure we're using the collapsed username.
        message['user'] = (message['user'] as String).toLowerCase();

        // Track the snapshot's priority so we can paginate from the last one.
        lastPriority = message['.priority'];

        // Don't process the extra item we tacked onto pageSize in the limit() above.
        if (count > pageSize) return null;

        // Remember the priority of the last item, excluding the extra item which we ignore above.
        secondToLastPriority = message['.priority'];

        return usernameForDisplay(message['user']).then((String usernameForDisplay) {
          message['usernameForDisplay'] = usernameForDisplay;
          queuedMessages.add(message);
        });

      }).then((_) {
        queuedMessages.forEach(insertMessage);
        queuedMessages.clear();
        relistenForItems();

        // If we received less than we tried to load, we've reached the end.
        if (count <= pageSize) reachedEnd = true;

        // Wait until the view is loaded, then scroll to bottom.
        if (isScrollPosAtBottom || isFirstLoad && chatView != null) Timer.run(() => chatView.scrollToBottom());
        isFirstLoad = false;

        new Timer(new Duration(seconds: 1), () {
          reloadingContent = false;
        });
      });
    });
  }

  /**
   * Listen for new stuff within the items we're currently showing.
   */
  void relistenForItems() {
    if (childAddedSubscriber != null) {
      childAddedSubscriber.cancel();
      childAddedSubscriber = null;
    }
    if (childChangedSubscriber != null) {
      childChangedSubscriber.cancel();
      childChangedSubscriber = null;
    }
    if (childMovedSubscriber != null) {
      childMovedSubscriber.cancel();
      childMovedSubscriber = null;
    }
    if (childRemovedSubscriber != null) {
      childRemovedSubscriber.cancel();
      childRemovedSubscriber = null;
    }

    // TODO: This is ignoring the page size/limit set above.
    listenForNewItems(startAt: topPriority, endAt: secondToLastPriority);
  }

  listenForNewItems({startAt, endAt}) {
    // If this is the first item loaded, start listening for new items.
    var itemsRef = f.child('/messages_by_community/${app.community.alias}')
    .startAt(priority: startAt)
    .endAt(priority: endAt);

    // Listen for new items.
    childAddedSubscriber = itemsRef.onChildAdded.listen((e) {
      Map newItem = e.snapshot.val();
      newItem['id'] = e.snapshot.name;

      // Make sure we're using the collapsed username.
      newItem['user'] = (newItem['user'] as String).toLowerCase();

      var existingItem = messages.firstWhere((i) => (i['id'] != null)
        ? (i['id'] == newItem['id'])
        : (i['user'] == newItem['user'] && i['message'] == newItem['message']), orElse: () => null);

      // If we already have the item, get out of here.
      if (existingItem != null) {
        // Pass the ID to the existing item as we might not have it.
        existingItem['id'] = newItem['id'];

        existingItem['createdDate'] = DateTime.parse(newItem['createdDate']);
        existingItem['updatedDate'] = (newItem['updatedDate'] != null)
                                      ? DateTime.parse(newItem['updatedDate'])
                                      : existingItem['createdDate'];

        // If the message timestamp is after our local time,
        // change it to now so messages aren't in the future.
        DateTime localTime = new DateTime.now().toUtc();
        if (existingItem['updatedDate'].isAfter(localTime)) existingItem['updatedDate'] = localTime;
        if (existingItem['createdDate'].isAfter(localTime)) existingItem['createdDate'] = localTime;

      } else {
        // Insert each new item into the list.
        usernameForDisplay(newItem['user']).then((String usernameForDisplay) {
          newItem['usernameForDisplay'] = usernameForDisplay;
          insertMessage(newItem);
        });
      }

      // If user is scrolled to bottom, keep it that way.
      if (isScrollPosAtBottom || isFirstLoad && chatView != null) Timer.run(() => chatView.scrollToBottom());
    });

    // Listen for changed items.
    childChangedSubscriber = itemsRef.onChildChanged.listen((e) {
      Map currentData = messages.firstWhere((i) => i['id'] == e.snapshot.name);
      Map newData = e.snapshot.val();

      Future processData = new Future.sync(() {
        // First pre-process some things.
        if (newData['createdDate'] != null) newData['createdDate'] = DateTime.parse(newData['createdDate']);
        if (newData['updatedDate'] != null) newData['updatedDate'] = DateTime.parse(newData['updatedDate']);

        // If the message timestamp is after our local time,
        // change it to now so messages aren't in the future.
        DateTime localTime = new DateTime.now().toUtc();
        if (newData['updatedDate'].isAfter(localTime)) newData['updatedDate'] = localTime;
        if (newData['createdDate'].isAfter(localTime)) newData['createdDate'] = localTime;

      }).then((_) {
        // Now that new data is pre-processed, update current data.
        newData.forEach((k, v) => currentData[k] = v);
        // TODO: Ugh, I'd like to avoid this re-sort.
//        messages.sort((m1, m2) => m1["createdDate"].compareTo(m2["createdDate"]));
      });
    });
  }

  /**
   * Find the index of the item with the closest updated date.
   */
  indexOfClosestItemByDate(date) {
    for (var message in messages) {
      if ((message['updatedDate'] as DateTime).isAfter(date)) return messages.indexOf(message);
    }
  }

  Future<String> usernameForDisplay(String username) {
    return UserModel.usernameForDisplay(username.toLowerCase(), f, app.cache)
    .then((String usernameForDisplay) => usernameForDisplay);
  }

  /**
   * Prepare the message and insert it into the observed list.
   */
  insertMessage(Map message) {
    DateTime now = new DateTime.now().toUtc();
    DateTime gracePeriod = app.timeOfLastFocus.add(new Duration(seconds: 2));

    message['highlighted'] = false;
    if (now.isAfter(gracePeriod) && !app.isFocused) message['highlighted'] = true;

    // If no updated date, use the created date.
    // TODO: We assume createdDate is never null!
    if (message['updatedDate'] == null) message['updatedDate'] = message['createdDate'];

    // The live-date-time element needs parsed dates.
    message['updatedDate'] = DateTime.parse(message['updatedDate']);
    message['createdDate'] = DateTime.parse(message['createdDate']);

    // If the message timestamp is after our local time,
    // change it to now so messages aren't in the future.
    DateTime localTime = new DateTime.now().toUtc();
    if (message['updatedDate'].isAfter(localTime)) message['updatedDate'] = localTime;
    if (message['createdDate'].isAfter(localTime)) message['createdDate'] = localTime;

    var index = indexOfClosestItemByDate(message['updatedDate']);

    messages.insert(index == null ? messages.length : index, toObservable(message));
  }


  /**
   * Handle clicks on web notifications.
   */
  notificationClicked(Event e) => context.callMethod('focus');

  /**
   * Handle commands.
   */
  commandRouter(MessageModel message) {
    // TODO: Refactor all this later.
    // A message of type 'local' is a basic, temporary local message
    // to the user, like in response to a command.
//    message.type = 'local';
    message.type = 'notification';
    switch (message.message) {
      case '/theme dark':
        message.message = 'You went dark. I\'ve saved your preference.';
        if (app.user.settings['theme'] == 'dark') message.message = 'You\'ve already gone dark.';
        document.body.classes.add('no-transition');
        insertMessage(message.toJson());
        Timer.run(() => app.user.settings['theme'] = 'dark');
        f.child('/users/${app.user.username.toLowerCase()}/settings/theme').set('dark');
        new Timer(new Duration(seconds: 1), () => document.body.classes.remove('no-transition'));
        break;
      case '/theme light':
        message.message = 'Let there be light. I\'ve saved your preference.';
        if (app.user.settings['theme'] == 'light') message.message = 'You\'re already lit up.';
        document.body.classes.add('no-transition');
        insertMessage(message.toJson());
        Timer.run(() => app.user.settings['theme'] = 'light');
        f.child('/users/${app.user.username.toLowerCase()}/settings/theme').set('light');
        new Timer(new Duration(seconds: 1), () => document.body.classes.remove('no-transition'));
        break;
      case '/print isMobile':
        message.message = app.isMobile.toString() + ' ' + window.screen.width.toString();
        insertMessage(message.toJson());
        break;
      case '/notify':
        // JS interop version of web notifications until Dart fixes land.
        String dummyMessage = 'Lorem ipsum dolor sit amet conseceteur adipiscing\n elit and some other random text and gibberish to prove a point';
        var notificationOptions = new JsObject.jsify({
          'body': InputFormatter.createTeaser(dummyMessage.replaceAll('\n', ' '), 75),
          'icon': '/static/images/woven_button_trans_margin_more.png'
        });

        var notification = new JsObject(context['Notification'], ['${message.user} just said something', notificationOptions]);
        new Timer(new Duration(seconds: 8), () {
          notification.callMethod('close');
        });
        notification.callMethod('addEventListener', ['click', notificationClicked]);

      //    TODO: Testing web notifications.
//        Notification.requestPermission().then((res) {
//          Notification notification = new Notification('New message from ${message.user}', body: message.message, iconUrl: '/static/images/favicon-32x32.png');
//          new Timer(new Duration(seconds: 4), () {
//            notification.close();
//          });
//        });
        break;
      default:
        message.message = 'I don\'t recognize that command.';
        insertMessage(message.toJson());
        break;
    }
  }

  void paginate() {
    if (reloadingContent == false && reachedEnd == false) loadMessagesByPage();
  }
}