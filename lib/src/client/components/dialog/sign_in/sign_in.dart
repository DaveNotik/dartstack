@HtmlImport('sign_in.html')

library components.dialog.sign_in;

import 'dart:html';
import 'dart:async';
import 'dart:convert';

import 'package:polymer/polymer.dart';
import 'package:firebase/firebase.dart' as db;
import 'package:core_elements/core_overlay.dart';
import 'package:core_elements/core_item.dart';
import 'package:core_elements/core_icon.dart';
import 'package:core_elements/core_icon_button.dart';
import 'package:core_elements/core_toolbar.dart';
import 'package:core_elements/core_a11y_keys.dart';
import 'package:core_elements/core_input.dart';
import 'package:core_elements/core_icon_button.dart';
import 'package:core_elements/core_animation.dart';

import '../welcome/welcome.dart';
import 'package:woven/src/client/components/widgets/dialog/dialog.dart';
import 'package:woven/src/client/app.dart';
import 'package:woven/src/shared/model/user.dart';
import 'package:woven/src/shared/routing/routes.dart';
import 'package:woven/src/shared/response.dart';

@CustomTag('sign-in-dialog')
class SignInDialog extends PolymerElement {
  SignInDialog.created() : super.created();

  @published App app;
  @published bool opened = false;
  var animation = new CoreAnimation();
  var processing = false;


  db.Firebase get f => app.f;

  CoreOverlay get overlay => $['dialog-overlay'];
  CoreInput get username => $['username'];
  CoreInput get password => $['password'];
  CoreIconButton get submitButton => $['submit'];

  DateTime get now => new DateTime.now().toUtc();

  /**
   * Toggle the overlay.
   */
  toggleOverlay() => overlay.toggle();

  /**
   * Submit the form and choose what to do.
   */
  submit(Event e) {
    e.preventDefault();
    doSignIn();
  }

  /**
   * Handle sign in.
   */
  doSignIn() {
    if (username.value.trim().isEmpty || password.value.trim().isEmpty) {
      window.alert("Your username and password, please.");
      return false;
    }

    // Disable button and add activity indicator animation.
    toggleProcessingIndicator();

    // Check credentials and sign the user in server side.
    HttpRequest.request(
        app.serverPath +
        Routes.signIn.toString(),
        method: 'POST',
        sendData: JSON.encode({'username': username.value.toLowerCase(), 'password': password.value}))
    .then((HttpRequest request) {
      // Set up the response as an object.
      Response response = Response.fromJson(JSON.decode(request.responseText));
      if (response.success) {
        // Set the auth token and remove it from the map.
        app.authToken = response.data['authToken'];
        // TODO: This should totally just be part of the UserModel.
        response.data.remove('authToken');
        app.f.authWithCustomToken(app.authToken).catchError((error) => print(error));

        // Set up the user object.
        app.user = UserModel.fromJson(response.data);

        app.signIn();

        toggleProcessingIndicator();
        overlay.toggle();
      } else {
        toggleProcessingIndicator();
        window.alert(response.message);
      }
    });
  }

  toggleProcessingIndicator() {
    if (processing) {
      submitButton.classes.remove('disabled');
      animation.cancel();
      processing = false;
    } else {
      submitButton.classes.add('disabled');
      animation.duration = 300;
      animation.iterations = 'Infinity';
      animation.easing = 'ease-in';
      animation.keyframes = [
          {'background-color': 'rgb(64, 136, 214)'},
          {'background-color': 'rgb(73, 168, 255)'},
          {'background-color': 'rgb(64, 136, 214)'}
      ];
      animation.target = submitButton;
      animation.play();
      processing = true;
    }
  }

  toggleSignUp() {
    this.toggleOverlay();
    app.router.dispatch(url: '/');
    app.showHomePage = true;
  }

  signInWithFacebook() {
    toggleProcessingIndicator();
    app.signInWithFacebook();
  }

  attached() {
    if (app.debugMode) print('+SignIn');
    if (!app.isMobile) $['username'].autofocus = true;
  }

  detached() {
    if (app.debugMode) print('-SignIn');
  }
}

