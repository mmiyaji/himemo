import 'ad_mob_initializer_stub.dart'
    if (dart.library.io) 'ad_mob_initializer_mobile.dart'
    as impl;

Future<void> initializeAdMob() => impl.initializeAdMob();
