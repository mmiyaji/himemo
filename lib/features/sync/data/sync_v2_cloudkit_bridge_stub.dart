Future<String> configureCloudKit(String options) =>
    Future.error(UnsupportedError('CloudKit JS requires a browser'));

Future<String> invokeCloudKit(String method, String args) =>
    Future.error(UnsupportedError('CloudKit JS requires a browser'));

Future<String> waitForSignIn() =>
    Future.error(UnsupportedError('CloudKit JS requires a browser'));

Future<String> disconnect() =>
    Future.error(UnsupportedError('CloudKit JS requires a browser'));

Future<String> waitForSignOut() =>
    Future.error(UnsupportedError('CloudKit JS requires a browser'));
