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
import CoreHaptics

class AnnouncementManager {
    public static var shared = AnnouncementManager()
    private var engine: CHHapticEngine?
    
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
              utterance.rate = 0.7
              synth.speak(utterance)
          } catch {
              print("Unexpected error announcing something using AVSpeechEngine!")
          }
      }
    }
    
    func startHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { announce(announcement: "Haptics are unsupported on this device.")
            return }
        do {
            self.engine = try CHHapticEngine()
            try engine?.start()
        } catch let error {
          fatalError("Engine Creation Error: \(error)")
        }
    }
    
    func vibrate(intensity: Float) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        var events = [CHHapticEvent]()
        
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity), CHHapticEventParameter(parameterID: .hapticSharpness, value: 1)], relativeTime: 0)
        events.append(event)
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Error playing pattern")
        }
        
    }
}
