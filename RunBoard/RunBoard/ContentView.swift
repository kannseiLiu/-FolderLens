//
//  ContentView.swift
//  RunBoard
//
//  Created by sheng on 2026/06/18.
//

import SwiftUI

struct ContentView: View {
    let experiments: [Experiment] = [
        Experiment(
            project: "CAMELS",
            experiment: "z2_qfrac_sigma8",
            model: "Ridge",
            trainSuite: "TNG",
            testSuite: "SIMBA",
            target: "sigma8",
            metric: "R2",
            value: 0.664,
            date: "2026-06-18"
        ),
        Experiment(
            project: "CAMELS",
            experiment: "z0z2_all_sigma8",
            model: "RandomForest",
            trainSuite: "TNG",
            testSuite: "SIMBA",
            target: "sigma8",
            metric: "R2",
            value: 0.744,
            date: "2026-06-18"
        ),
        Experiment(
            project: "TNG300",
            experiment: "quench_2gyr",
            model: "XGBoost",
            trainSuite: "host_split",
            testSuite: "test",
            target: "quenching",
            metric: "AUC",
            value: 0.929,
            date: "2026-05-01"
        )
    ]
    
    @State private var selectedExperiment: Experiment?
    
    var body: some View {
        NavigationSplitView{
            List(experiments) {experiment in
                VStack(alignment: .leading, spacing: 4){
                    Text(experiment.experiment)
                        .font(.headline)
                    
                    Text("\(experiment.project) · \(experiment.model)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical,4)
            }
            .navigationTitle("Experiment")
        }detail:{
            VStack(alignment:.leading , spacing: 16){
                Text("RunBoard")
                    .font(.largeTitle)
                    .bold()
                Text("A macOS dashboard for tracking scientific ML experiments")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                Divider()
                
                Text("Select an experiment from the sidebar.")
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 900, minHeight:600)
    }
}

#Preview{
    ContentView()
}
