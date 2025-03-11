package com.example.sps_dartstart  // Ensure this matches your package name

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

// Make sure your activity extends `AppCompatActivity`
class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Make sure this file exists in `res/layout/activity_main.xml`
        setContentView(R.layout.activity_main)

        // Initialize UI elements (make sure the IDs in `activity_main.xml` match these)
        val titleTextView: TextView = findViewById(R.id.titleTextView)
        val startButton: Button = findViewById(R.id.startButton)
        val infoTextView: TextView = findViewById(R.id.infoTextView)

        // Set the title for the TextView (Optional, if you want to set text programmatically)
        titleTextView.text = "Welcome to SPC App"

        // Set an OnClickListener for the start button
        startButton.setOnClickListener {
            // This is where you can define the action when the button is clicked
            // For example, starting a new activity:
            val intent = Intent(this, AnotherActivity::class.java)
            startActivity(intent)
        }

        // Optionally, you can also set text for the infoTextView
        infoTextView.text = "This is an example SPC app for visualizing data"
    }
}
