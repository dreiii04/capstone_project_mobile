# capstone_project

A new Flutter project.

## Secure MongoDB Connection (via Backend API)

This app now connects to MongoDB Atlas through a backend API (Node.js + Express) so MongoDB credentials are not exposed in the Flutter client.

### 1) Backend setup

1. Open the backend folder and install packages:

```bash
cd backend
npm install
```

2. Create backend environment file:

```bash
copy .env.example .env
```

3. Set values in `backend/.env`:

```env
PORT=4000
MONGODB_URI=mongodb://<username>:<password>@<shard-00-00>:27017,<shard-00-01>:27017,<shard-00-02>:27017/verifitor?replicaSet=<replica-set>&authSource=admin&retryWrites=true&w=majority&tls=true
MONGODB_DB_NAME=verifitor
MONGODB_USERS_COLLECTION=users
ALLOWED_ORIGIN=*
MAILBOXLAYER_ACCESS_KEY=
OTP_TTL_MINUTES=10
OTP_DEV_MODE=true
JWT_SECRET=changeme
JWT_ACCESS_TTL_MINUTES=15
JWT_REFRESH_TTL_DAYS=30
JWT_ISSUER=verifitor
```

4. Start backend:

```bash
npm run dev
```

### 2) Flutter app setup

1. In project root, create `.env` from `.env.example` and set:

```env
API_BASE_URL=http://localhost:4000
```

For Android emulator use:

```env
API_BASE_URL=http://10.0.2.2:4000
```

2. Install Flutter packages:

```bash
flutter pub get
```

3. Run the app:

```bash
flutter run
```

Notes:
- Backend validates inputs and hashes passwords with bcrypt before storing.
- Flutter login/register forms also validate input before API calls.
- Forgot password now uses OTP verification endpoints in backend.
- In development, `OTP_DEV_MODE=true` returns OTP in API response/snackbar.
- Set `MAILBOXLAYER_ACCESS_KEY` to enable mailboxlayer email deliverability checks.
- `.env` files are git-ignored.
