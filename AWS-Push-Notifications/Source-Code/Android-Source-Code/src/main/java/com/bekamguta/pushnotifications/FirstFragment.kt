package com.bekamguta.pushnotifications

import android.os.Bundle
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.navigation.fragment.findNavController
import com.bekamguta.pushnotifications.databinding.FragmentFirstBinding

//using Android fragments for display and categorisation
class FirstFragment : Fragment() {

    private var _binding: FragmentFirstBinding? = null

    //this property is only valid between onCreateView and onDestroyView.
    private val binding get() = _binding!!

    //run once when the activity is first created
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View? {
        _binding = FragmentFirstBinding.inflate(inflater, container, false)
        return binding.root
    }

    //run once when the view is first created
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        //create an intent to move/navigate from one fragment to another
        binding.buttonFirst.setOnClickListener {
            findNavController().navigate(R.id.action_FirstFragment_to_SecondFragment)
        }
    }

    //function runs when the activity is being destroyed from the backstack
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
