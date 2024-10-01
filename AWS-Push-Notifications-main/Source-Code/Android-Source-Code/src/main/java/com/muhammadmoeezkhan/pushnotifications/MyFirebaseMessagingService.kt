package com.bekamguta.pushnotifications

import android.os.Handler
import android.os.Looper
import android.widget.Toast
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage


//created custom class to alert the user -- using a toast
//for when the google firebase server interacts
//used the data passed by the server using the Firebase Cloud Messaging Services

//loop keeps checking for incoming data from the Firebase Cloud Messaging Services
class MyFirebaseMessagingService: FirebaseMessagingService(){
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Looper.prepare()
        Handler().post {
            Toast.makeText(baseContext,remoteMessage.notification?.title, Toast.LENGTH_LONG).show() //display
        }
        Looper.loop()
    }

}