//
//  PomodoroManager.swift
//  boringNotch
//
//  Adds a fully customizable Pomodoro timer that can live in the notch.
//

import AppKit
import Combine
import Defaults
import SwiftUI

/// The three phases of a classic Pomodoro cycle.
enum PomodoroPhase: String, Codable, CaseIterable {
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var symbol: String {
        switch self {
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        }
    }

    /// Fallback tint used when the user hasn't overridden phase colors.
    var defaultTint: Color {
        switch self {
        case .work: return Color(red: 0.98, green: 0.35, blue: 0.35)
        case .shortBreak: return Color(red: 0.30, green: 0.78, blue: 0.55)
        case .longBreak: return Color(red: 0.33, green: 0.60, blue: 0.98)
        }
    }
}

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published private(set) var phase: PomodoroPhase = .work
    @Published private(set) var isRunning: Bool = false
    /// Seconds remaining in the current phase.
    @Published private(set) var timeRemaining: Int = Int(Defaults[.pomodoroWorkDuration]) * 60
    /// Number of completed work sessions in the current long-break cycle.
    @Published private(set) var completedWorkSessions: Int = 0

    private var ticker: AnyCancellable?
    private var endDate: Date?
    private var cancellables: Set<AnyCancellable> = []
    /// True while the current phase is untouched (never started since the last reset),
    /// so its displayed length can follow live changes to the duration preferences.
    private var isFresh = true

    private init() {
        observeDurationChanges()
    }

    // MARK: - Derived state

    /// Total number of seconds for a given phase, based on user preferences.
    func totalSeconds(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .work: return max(1, Int(Defaults[.pomodoroWorkDuration]) * 60)
        case .shortBreak: return max(1, Int(Defaults[.pomodoroShortBreakDuration]) * 60)
        case .longBreak: return max(1, Int(Defaults[.pomodoroLongBreakDuration]) * 60)
        }
    }

    var totalSeconds: Int { totalSeconds(for: phase) }

    /// Fraction of the current phase already elapsed (0...1).
    var progress: Double {
        let total = totalSeconds
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(total - timeRemaining) / Double(total)))
    }

    /// True while the timer is running or paused part-way through a phase.
    var isActive: Bool {
        isRunning || timeRemaining != totalSeconds
    }

    var tint: Color {
        Defaults[.pomodoroUseAccentColor] ? Color.effectiveAccent : phase.defaultTint
    }

    var formattedTime: String {
        let clamped = max(0, timeRemaining)
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Controls

    func startOrPause() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        if timeRemaining <= 0 { timeRemaining = totalSeconds }
        isFresh = false
        endDate = Date().addingTimeInterval(TimeInterval(timeRemaining))
        isRunning = true
        startTicker()
    }

    func pause() {
        guard isRunning else { return }
        refreshRemaining()
        isRunning = false
        endDate = nil
        stopTicker()
    }

    /// Reset the current phase back to its full duration (does not change phase).
    func reset() {
        stopTicker()
        isRunning = false
        endDate = nil
        isFresh = true
        timeRemaining = totalSeconds
    }

    /// Reset the whole cycle back to a fresh work phase.
    func resetCycle() {
        stopTicker()
        isRunning = false
        endDate = nil
        isFresh = true
        completedWorkSessions = 0
        phase = .work
        timeRemaining = totalSeconds
    }

    /// Skip to the next phase in the cycle.
    func skip() {
        advancePhase(userInitiated: true)
    }

    // MARK: - Ticking

    private func startTicker() {
        stopTicker()
        ticker = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        refreshRemaining()
        if timeRemaining <= 0 {
            advancePhase(userInitiated: false)
        }
    }

    private func refreshRemaining() {
        guard let endDate else { return }
        timeRemaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
    }

    // MARK: - Phase transitions

    private func advancePhase(userInitiated: Bool) {
        let previousPhase = phase

        if !userInitiated {
            notifyPhaseFinished()
        }

        if previousPhase == .work {
            completedWorkSessions += 1
            let sessionsGoal = max(1, Int(Defaults[.pomodoroSessionsUntilLongBreak]))
            phase = (completedWorkSessions % sessionsGoal == 0) ? .longBreak : .shortBreak
        } else {
            phase = .work
        }

        timeRemaining = totalSeconds
        isFresh = true

        let shouldAutoStart: Bool
        if phase == .work {
            shouldAutoStart = Defaults[.pomodoroAutoStartWork]
        } else {
            shouldAutoStart = Defaults[.pomodoroAutoStartBreaks]
        }

        stopTicker()
        isRunning = false
        endDate = nil

        if shouldAutoStart && !userInitiated {
            start()
        }
    }

    private func notifyPhaseFinished() {
        guard Defaults[.pomodoroPlaySound] else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    // MARK: - Preference observation

    private func observeDurationChanges() {
        // When the user tweaks a duration while a phase is idle at full length,
        // reflect the new value immediately so the display stays in sync.
        let work = Defaults.publisher(.pomodoroWorkDuration).map { _ in () }
        let shortBreak = Defaults.publisher(.pomodoroShortBreakDuration).map { _ in () }
        let longBreak = Defaults.publisher(.pomodoroLongBreakDuration).map { _ in () }

        work.merge(with: shortBreak, longBreak)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self, !self.isRunning, self.isFresh else { return }
                self.timeRemaining = self.totalSeconds
            }
            .store(in: &cancellables)
    }
}
