//
//  ViewController.swift
//  ObjectDetectBitBox
//
//  Created by Mohit Kumar Gupta on 15/03/24.
//

import UIKit
import SwiftUI
import AVFoundation

class ViewController: UIViewController{
    
    private var permissionGranted = false
    
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
}

struct HostedViewController: UIViewControllerRepresentable{
    
    func makeUIViewController(context: Context) -> UIViewController {
        
        return ViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        <#code#>
    }
}

