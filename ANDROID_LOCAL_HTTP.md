# Android local backend

When using `http://10.0.2.2:8000` on Android Emulator, Android may need cleartext HTTP enabled for local development.

After `flutter create .`, open:
`android/app/src/main/AndroidManifest.xml`

Inside `<application ...>` add:
`android:usesCleartextTraffic="true"`

For production, use HTTPS instead of cleartext HTTP.
