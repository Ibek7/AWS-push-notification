package com.bekamguta.pushnotifications

import android.os.Bundle
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.navigation.fragment.findNavController
import com.bekamguta.pushnotifications.databinding.FragmentSecondBinding


class SecondFragment : Fragment() {

    private var _binding: FragmentSecondBinding? = null

    //this property is only valid between onCreateView and onDestroyView.
    private val binding get() = _binding!!

    //lifecycle method that runs once the activity is first created
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View? {
        _binding = FragmentSecondBinding.inflate(inflater, container, false)
        return binding.root
    }

    //used to call when view first launched and to operate the two fragment sections created
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        binding.buttonSecond.setOnClickListener {
            findNavController().navigate(R.id.action_SecondFragment_to_FirstFragment)
        }
    }

    //method called when the activity is not being used anymore -- destroys from the Android backstack
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}