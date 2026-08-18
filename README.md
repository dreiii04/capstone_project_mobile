# Verifitor Mobile

Flutter client for Verifitor document requests, payments, notifications, and
account management.

## API architecture

The mobile and web clients communicate with one shared Vercel API and therefore
use the same authentication service and database.

```text
Web client ----\
                > Shared Vercel API -> Shared database
Mobile client -/
```

The mobile API URL is defined once in `lib/constants.dart` as
`ApiConstants.baseUrl`:

```text
https://verifitor-backend.vercel.app/api
```

All HTTP and multipart requests are created by `MongoDataApiService` from that
constant.

The same Flutter code can target another environment at build time without
changing source files:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000
flutter build web --dart-define=API_BASE_URL=https://verifitor-backend.vercel.app/api
```

For a browser deployment, set the backend's `ALLOWED_ORIGIN` environment
variable to the web application's HTTPS origin. Multiple web origins are
comma-separated. Native mobile requests do not send a browser origin and use
the same backend automatically.

## Expected API contract

The mobile client retains these existing relative routes under the shared
`/api` prefix:

- `POST /auth/login`
- `POST /auth/refresh`
- `POST /auth/logout`
- `POST /auth/register/request-otp`
- `POST /auth/register/verify-otp`
- `POST /auth/forgot-password/request-otp`
- `POST /auth/forgot-password/verify-otp`
- `POST /auth/forgot-password/reset`
- `GET, PUT /profile`
- `POST /profile/photo`
- `PUT /profile/password`
- `GET, POST /requests`
- `GET /receipts`
- `POST /payments/receipt`
- `GET /notifications`
- `GET /transactions`
- `POST /refunds`

Unsuccessful authentication responses display the message returned by the
shared API, including inactive or deactivated account messages.

## Run and verify

```powershell
flutter pub get
flutter run
flutter analyze
flutter test
```
