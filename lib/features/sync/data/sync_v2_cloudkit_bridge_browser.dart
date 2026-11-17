import 'dart:js_interop';

@JS('himemoCloudKitV2.configure')
external JSPromise<JSString> _configure(JSString options);

@JS('himemoCloudKitV2.invoke')
external JSPromise<JSString> _invoke(JSString method, JSString args);

@JS('himemoCloudKitV2.waitForSignIn')
external JSPromise<JSString> _waitForSignIn();

@JS('himemoCloudKitV2.disconnect')
external JSPromise<JSString> _disconnect();

@JS('himemoCloudKitV2.waitForSignOut')
external JSPromise<JSString> _waitForSignOut();

Future<String> configureCloudKit(String options) async =>
    (await _configure(options.toJS).toDart).toDart;

Future<String> invokeCloudKit(String method, String args) async =>
    (await _invoke(method.toJS, args.toJS).toDart).toDart;

Future<String> waitForSignIn() async => (await _waitForSignIn().toDart).toDart;

Future<String> disconnect() async => (await _disconnect().toDart).toDart;

Future<String> waitForSignOut() async =>
    (await _waitForSignOut().toDart).toDart;
