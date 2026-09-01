//
//  PomodoroView.swift
//  boringNotch
//
//  The expanded Pomodoro tab plus the compact live activity shown in the
//  closed notch while a timer is running.
//

import Defaults
import SwiftUI

// MARK: - Expanded tab

struct PomodoroView: View {
    @ObservedObject private var pomodoro = PomodoroManager.shared
    @Default(.pomodoroSessionsUntilLongBreak) private var sessionsUntilLongBreak

    var body: some View {
        HStack(spacing: 20) {
            timerDial
                .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 10) {
                phaseHeader
                sessionDots
                Spacer(minLength: 0)
                controls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: Dial

    private var timerDial: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)

            Circle()
                .trim(from: 0, to: CGFloat(pomodoro.progress))
                .stroke(
                    pomodoro.tint,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: pomodoro.progress)

            VStack(spacing: 2) {
                Text(pomodoro.formattedTime)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Image(systemName: pomodoro.phase.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(pomodoro.tint)
            }
        }
    }

    // MARK: Header

    private var phaseHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(pomodoro.phase.title))
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text(statusKey)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusKey: LocalizedStringKey {
        if pomodoro.isRunning { return "In progress" }
        return pomodoro.isActive ? "Paused" : "Ready"
    }

    private var sessionDots: some View {
        let goal = max(1, sessionsUntilLongBreak)
        let done = pomodoro.completedWorkSessions % goal
        return HStack(spacing: 5) {
            ForEach(0..<goal, id: \.self) { index in
                Circle()
                    .fill(index < done ? pomodoro.tint : Color.white.opacity(0.15))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: { pomodoro.startOrPause() }) {
                Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 34)
                    .background(pomodoro.tint, in: Capsule())
            }
            .buttonStyle(.plain)

            circleButton(system: "arrow.counterclockwise") { pomodoro.reset() }
                .help("Reset current phase")

            circleButton(system: "forward.fill") { pomodoro.skip() }
                .help("Skip to next phase")
        }
    }

    private func circleButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Closed-notch live activity

struct PomodoroLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var pomodoro = PomodoroManager.shared

    var body: some View {
        HStack {
            // Left: phase icon aligned with the notch edge.
            HStack {
                Image(systemName: pomodoro.phase.symbol)
                    .foregroundStyle(pomodoro.tint)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            // Right: remaining time.
            HStack {
                Text(pomodoro.formattedTime)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(pomodoro.isRunning ? pomodoro.tint : .gray)
                    .contentTransition(.numericText())
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12) + 34,
                height: max(0, vm.effectiveClosedNotchHeight - 12),
                alignment: .center
            )
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
