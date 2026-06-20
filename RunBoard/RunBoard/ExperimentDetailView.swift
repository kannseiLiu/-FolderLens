//
//  ExperimentDetailView.swift
//  RunBoard
//
//  Created by sheng on 2026/06/18.
//

import SwiftUI

struct ExperimentDetailView: View {
    let experiment: Experiment

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(experiment.experiment)
                .font(.largeTitle)
                .bold()

            Text("\(experiment.project) · \(experiment.model)")
                .font(.title3)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Project", value: experiment.project)
                DetailRow(label: "Model", value: experiment.model)
                DetailRow(label: "Train suite", value: experiment.trainSuite)
                DetailRow(label: "Test suite", value: experiment.testSuite)
                DetailRow(label: "Target", value: experiment.target)
                DetailRow(label: "Metric", value: experiment.metric)
                DetailRow(label: "Value", value: String(format: "%.3f", experiment.value))
                DetailRow(label: "Date", value: experiment.date)
            }

            Spacer()
        }
        .padding(32)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .bold()
        }
        .font(.title3)
    }
}

#Preview {
    ExperimentDetailView(
        experiment: Experiment(
            project: "CAMELS",
            experiment: "z2_qfrac_sigma8",
            model: "Ridge",
            trainSuite: "TNG",
            testSuite: "SIMBA",
            target: "sigma8",
            metric: "R2",
            value: 0.664,
            date: "2026-06-18"
        )
    )
}
