importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBc0NZIXGC9LS4hNOPDe7RPP7qxn8mwsFI',
  authDomain: 'utilitybills-c942a.firebaseapp.com',
  projectId: 'utilitybills-c942a',
  storageBucket: 'utilitybills-c942a.firebasestorage.app',
  messagingSenderId: '263909690816',
  appId: '1:263909690816:web:c6116835210ce10dedcc25',
  measurementId: 'G-L6PQX41MQL',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  const notificationTitle = payload.notification?.title ?? 'New notification';
  const notificationOptions = {
    body: payload.notification?.body ?? '',
    icon: '/icons/Icon-192.png',
  };
  return self.registration.showNotification(notificationTitle, notificationOptions);
});
