package com.bekamguta.pushnotifications

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import com.google.android.material.snackbar.Snackbar
import androidx.appcompat.app.AppCompatActivity
import androidx.navigation.findNavController
import androidx.navigation.ui.AppBarConfiguration
import androidx.navigation.ui.navigateUp
import androidx.navigation.ui.setupActionBarWithNavController
import android.view.Menu
import android.view.MenuItem
import android.widget.Toast
import com.google.android.gms.tasks.OnCompleteListener
import com.google.firebase.messaging.FirebaseMessaging
import com.bekamguta.pushnotifications.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    //Member variables to be used globally and externally
    private lateinit var appBarConfiguration: AppBarConfiguration
    private lateinit var binding: ActivityMainBinding

    //run method once app is first created
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)

        //operating the two fragments created -- configuring the layouts programmatically
        val navController = findNavController(R.id.nav_host_fragment_content_main)

        appBarConfiguration = AppBarConfiguration(navController.graph)

        setupActionBarWithNavController(navController, appBarConfiguration)

        binding.fab.setOnClickListener { view ->

            //use the Firebase Cloud Messaging Services
            FirebaseMessaging.getInstance().token.addOnCompleteListener(OnCompleteListener { task ->

                if(!task.isSuccessful) {
                    //if task completed -- call imported external method
                    return@OnCompleteListener
                }

                val token = task.result

                Toast.makeText(baseContext,token,Toast.LENGTH_LONG).show()

                var clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clipData = ClipData.newPlainText("text",token)
                clipboardManager.setPrimaryClip(clipData)

            })

        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        //inflate the menu
        //this adds items to the action bar if it is present
        menuInflater.inflate(R.menu.menu_main, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        //handle action bar item clicks here
        //the action bar will automatically handle clicks on the Home/Up button
        //as we specify a parent activity in AndroidManifest.xml.
        return when (item.itemId) {
            R.id.action_settings -> true
            else -> super.onOptionsItemSelected(item)
        }
    }

    //operating the two fragments created -- configuring the layouts programmatically
    override fun onSupportNavigateUp(): Boolean {
        val navController = findNavController(R.id.nav_host_fragment_content_main)
        return navController.navigateUp(appBarConfiguration) || super.onSupportNavigateUp()
    }
}