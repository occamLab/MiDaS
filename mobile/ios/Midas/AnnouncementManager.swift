//
//  AnnouncementManager.swift
//  Midas
//
//  Created by occamlab on 7/25/22.
//  Copyright © 2022 tensorflow. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

class AnnouncementManager {
    public static var shared = AnnouncementManager()
    
    let synth = AVSpeechSynthesizer()
    
    private init() {
        
    }

    /// Communicates a message to the user via speech.  If VoiceOver is active, then VoiceOver is used to communicate the announcement, otherwise we use the AVSpeechEngine
      ///
      /// - Parameter announcement: the text to read to the user
      func announce(announcement: String) {
          if UIAccessibility.isVoiceOverRunning {
              // use the VoiceOver API instead of text to speech
              UIAccessibility.post(notification: UIAccessibility.Notification.announcement, argument: announcement)
          } else {
              let audioSession = AVAudioSession.sharedInstance()
              do {
                  try audioSession.setCategory(AVAudioSession.Category.playback)
                  try audioSession.setActive(true)
                  let utterance = AVSpeechUtterance(string: announcement)
                  utterance.rate = 0.6
                  synth.speak(utterance)
              } catch {
                  print("Unexpected error announcing something using AVSpeechEngine!")
              }
          }
      }
}
