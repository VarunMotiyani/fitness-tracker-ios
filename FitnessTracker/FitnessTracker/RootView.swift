//
//  RootView.swift
//  FitnessTracker
//
//  Created by Motiyani, Varun on 28/08/26.
//

import SwiftUI
import FitnessDomain

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("FitnessTracker").font(.largeTitle.bold())
            Text("Phase 1b shell").foregroundStyle(.secondary)
            Text("\(MuscleGroup.allCases.count) muscle groups linked from FitnessCore")
                .font(.footnote)
        }
        .padding()
    }
}

#Preview { RootView() }
