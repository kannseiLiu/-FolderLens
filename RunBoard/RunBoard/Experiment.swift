//
//  Experiment.swift
//  RunBoard
//
//  Created by sheng on 2026/06/18.
//


import Foundation

struct Experiment: Identifiable {
    let id = UUID()
    let project: String
    let experiment: String
    let model: String
    let trainSuite: String
    let testSuite: String
    let target: String
    let metric: String
    let value: Double
    let date: String
}
