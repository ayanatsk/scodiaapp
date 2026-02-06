import SwiftUI
import PhotosUI
import Vision
import UIKit
import Combine

@main
struct ScoliosisMVPApp: App {
    var body: some Scene {
        WindowGroup {
            RootFlowView()
        }
    }
}

enum AppStep: Hashable {
    case welcome
    case instructions
    case upload
    case analyzing
    case results(AnalysisReport)
}

struct RootFlowView: View {
    @State private var path: [AppStep] = [.welcome]
    @StateObject private var vm = UploadVM()

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView {
                path.append(.instructions)
            }
            .navigationDestination(for: AppStep.self) { step in
                switch step {
                case .welcome:
                    WelcomeView { path.append(.instructions) }

                case .instructions:
                    InstructionsView { path.append(.upload) }

                case .upload:
                    UploadPhotosView(vm: vm) {
                        path.append(.analyzing)
                        Task {
                            let report = await PoseAnalyzer.analyze(
                                side: vm.sideImage,
                                back: vm.backImage
                            )
                            if !path.isEmpty { _ = path.popLast() }
                            path.append(.results(report))
                        }
                    }

                case .analyzing:
                    AnalyzingView()

                case .results(let report):
                    ResultsView(report: report) {
                        vm.reset()
                        path = [.welcome]
                    }
                }
            }
        }
        .tint(.green)
    }
}

final class UploadVM: ObservableObject {
    @Published var sideImage: UIImage?
    @Published var backImage: UIImage?

    var canAnalyze: Bool { sideImage != nil && backImage != nil }

    func reset() {
        sideImage = nil
        backImage = nil
    }
}

struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "figure.stand")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.green)

            Text("Scodia MVP")
                .font(.title2.weight(.semibold))

            Text("Скрининг асимметрии осанки по фото на основе ключевых точек тела (AI).")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Label("Не медицинский диагноз", systemImage: "exclamationmark.triangle")
                Label("Оценка риска и рекомендации", systemImage: "checkmark.seal")
                Label("При сомнениях — ортопед и/или рентген", systemImage: "cross.case")
            }
            .font(.callout)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button(action: onStart) {
                Text("Начать")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .navigationBarBackButtonHidden(true)
    }
}

struct InstructionsView: View {
    var onContinue: () -> Void

    @State private var items: [CheckItem] = [
        .init(title: "Ровный фон и свет", subtitle: "Без теней, лучше у стены", isOn: false),
        .init(title: "Полный рост в кадре", subtitle: "Голова и стопы должны быть видны", isOn: false),
        .init(title: "Руки опущены", subtitle: "Поза естественная, без наклонов", isOn: false),
        .init(title: "2 фото с ракурсов", subtitle: "Сбоку и сзади", isOn: false)
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("Подготовка")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            List {
                ForEach($items) { $item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isOn ? .green : .secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.body.weight(.semibold))
                            Text(item.subtitle).font(.callout).foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $item.isOn)
                            .labelsHidden()
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.insetGrouped)

            let allDone = items.allSatisfy { $0.isOn }

            Button {
                onContinue()
            } label: {
                Text("Продолжить")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(allDone ? Color.green : Color.gray.opacity(0.3))
                    .foregroundStyle(allDone ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!allDone)
            .padding()

            Text("Дисклеймер: это скрининг асимметрии осанки и не является диагнозом.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .navigationTitle("")
    }
}

struct UploadPhotosView: View {
    @ObservedObject var vm: UploadVM
    var onAnalyze: () -> Void

    @State private var sideItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 14) {
            Text("Загрузите 2 фото")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            PhotoCard(
                title: "Фото сбоку",
                subtitle: "Профиль",
                image: vm.sideImage
            ) {
                PhotosPicker(selection: $sideItem, matching: .images) {
                    UploadButtonLabel(isLoaded: vm.sideImage != nil)
                }
            }
            .onChange(of: sideItem) { _, newItem in
                Task { vm.sideImage = await newItem?.loadUIImage() }
            }

            PhotoCard(
                title: "Фото сзади",
                subtitle: "Спина",
                image: vm.backImage
            ) {
                PhotosPicker(selection: $backItem, matching: .images) {
                    UploadButtonLabel(isLoaded: vm.backImage != nil)
                }
            }
            .onChange(of: backItem) { _, newItem in
                Task { vm.backImage = await newItem?.loadUIImage() }
            }

            Spacer()

            Button {
                onAnalyze()
            } label: {
                Text("Начать анализ")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.canAnalyze ? Color.green : Color.gray.opacity(0.3))
                    .foregroundStyle(vm.canAnalyze ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!vm.canAnalyze)
            .padding()

            Text("Совет: лучше, чтобы фото делал другой человек — камера должна быть ровной.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .navigationTitle("")
    }
}

struct PhotoCard<Accessory: View>: View {
    let title: String
    let subtitle: String
    let image: UIImage?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                accessory()
            }

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.10))
                    .frame(height: 110)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                            Text("Фото не загружено")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    )
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }
}

struct UploadButtonLabel: View {
    let isLoaded: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isLoaded ? "checkmark" : "square.and.arrow.up")
            Text(isLoaded ? "Загружено" : "Загрузить")
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.12))
        .foregroundStyle(.green)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AnalyzingView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.2)
            Text("Анализируем…").font(.headline)
            Text("Извлекаем ключевые точки тела и оцениваем асимметрию.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
        .navigationBarBackButtonHidden(true)
    }
}

struct ResultsView: View {
    let report: AnalysisReport
    var onRestart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Результаты")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Скрининг-оценка")
                                .font(.headline)
                            Text(report.verdictTitle)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(report.verdictColor)
                        }
                        Spacer()
                        Text("\(report.riskScore)%")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(report.verdictColor)
                    }

                    Divider().opacity(0.4)

                    MetricRow(name: "Наклон плеч (сзади)", value: report.shoulderTiltText)
                    MetricRow(name: "Наклон таза (сзади)", value: report.hipTiltText)
                    MetricRow(name: "Смещение оси (сзади)", value: report.axisShiftText)
                    MetricRow(name: "Наклон корпуса (сбоку)", value: report.sideLeanText)

                    if let note = report.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Рекомендации")
                        .font(.headline)

                    ForEach(report.recommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text(rec).font(.callout)
                        }
                    }

                    Divider().opacity(0.4)

                    Text("Важно: приложение не ставит диагноз. Для подтверждения степени сколиоза нужен врач и/или рентген.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Button("Начать заново", action: onRestart)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
    }
}

struct MetricRow: View {
    let name: String
    let value: String
    var body: some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.weight(.semibold))
        }
        .font(.callout)
    }
}

struct CheckItem: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var isOn: Bool
}

struct AnalysisReport: Hashable {
    var riskScore: Int
    var shoulderTiltDeg: Double?
    var hipTiltDeg: Double?
    var axisShift: Double?
    var sideLeanDeg: Double?

    var note: String?
    var recommendations: [String]

    var verdictTitle: String {
        switch riskScore {
        case 0...24: return "Низкий риск"
        case 25...59: return "Средний риск"
        default: return "Высокий риск"
        }
    }

    var verdictColor: Color {
        switch riskScore {
        case 0...24: return .green
        case 25...59: return .orange
        default: return .red
        }
    }

    var shoulderTiltText: String {
        guard let v = shoulderTiltDeg else { return "н/д" }
        return String(format: "%.1f°", abs(v))
    }

    var hipTiltText: String {
        guard let v = hipTiltDeg else { return "н/д" }
        return String(format: "%.1f°", abs(v))
    }

    var axisShiftText: String {
        guard let v = axisShift else { return "н/д" }
        return String(format: "%.0f%%", min(max(v, 0), 1) * 100.0)
    }

    var sideLeanText: String {
        guard let v = sideLeanDeg else { return "н/д" }
        return String(format: "%.1f°", abs(v))
    }
}

enum PoseAnalyzer {

    static func analyze(side: UIImage?, back: UIImage?) async -> AnalysisReport {
        let backPose = back.flatMap { detectPose(image: $0) }
        let sidePose = side.flatMap { detectPose(image: $0) }

        guard backPose != nil || sidePose != nil else {
            return AnalysisReport(
                riskScore: 0,
                shoulderTiltDeg: nil,
                hipTiltDeg: nil,
                axisShift: nil,
                sideLeanDeg: nil,
                note: "Не удалось распознать позу. Попробуйте сделать фото при хорошем освещении и полный рост в кадре.",
                recommendations: [
                    "Встаньте ровно, руки опущены",
                    "Сделайте фото с расстояния 2–3 метра",
                    "Не наклоняйте камеру"
                ]
            )
        }

        var shoulderTilt: Double? = nil
        var hipTilt: Double? = nil
        var axisShift: Double? = nil
        var sideLean: Double? = nil

        if let pose = backPose {
            let Ls = pose.point(.leftShoulder)
            let Rs = pose.point(.rightShoulder)
            let Lh = pose.point(.leftHip)
            let Rh = pose.point(.rightHip)

            shoulderTilt = lineAngleDegrees(Ls, Rs)
            hipTilt = lineAngleDegrees(Lh, Rh)

            let shoulderMid = midpoint(Ls, Rs)
            let hipMid = midpoint(Lh, Rh)

            let axis = abs(shoulderMid.x - hipMid.x)
            axisShift = min(max(axis * 2.0, 0), 1)
        }

        if let pose = sidePose {
            let nose = pose.point(.nose)
            let neck = pose.point(.neck)
            let hip = pose.point(.root)

            sideLean = sideLeanDegrees(nose: nose, neck: neck, hip: hip)
        }

        let shoulderScore = min(abs(shoulderTilt ?? 0) / 12.0, 1.0)
        let hipScore = min(abs(hipTilt ?? 0) / 10.0, 1.0)
        let axisScore = min((axisShift ?? 0) / 0.35, 1.0)
        let sideScore = min(abs(sideLean ?? 0) / 10.0, 1.0)

        var risk = Int((0.34 * shoulderScore + 0.26 * hipScore + 0.20 * axisScore + 0.20 * sideScore) * 100.0)

        var recs: [String] = [
            "Следите за симметрией нагрузки (рюкзак на 2 лямках)",
            "Делайте упражнения на мышцы кора 10–15 мин/день",
            "Если есть боль или прогрессирование — обратитесь к врачу"
        ]

        if risk >= 60 {
            recs.insert("Рекомендуется консультация ортопеда/вертебролога", at: 0)
            recs.insert("Для подтверждения степени обычно нужен рентген (Cobb angle)", at: 1)
        } else if risk >= 25 {
            recs.insert("Повторите фото через 2–4 недели для сравнения", at: 0)
        } else {
            recs.insert("Риск низкий: поддерживайте активность и осознанную осанку", at: 0)
        }

        let note = "MVP: метрики сзади (плечи/таз/ось) + метрика сбоку (наклон корпуса)."

        return AnalysisReport(
            riskScore: risk,
            shoulderTiltDeg: shoulderTilt,
            hipTiltDeg: hipTilt,
            axisShift: axisShift,
            sideLeanDeg: sideLean,
            note: note,
            recommendations: recs
        )
    }

    private static func detectPose(image: UIImage) -> PoseObservation? {
        guard let cg = image.cgImage else { return nil }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])

        do {
            try handler.perform([request])
            guard let obs = request.results?.first else { return nil }
            return PoseObservation(obs)
        } catch {
            return nil
        }
    }

    private static func lineAngleDegrees(_ p1: CGPoint?, _ p2: CGPoint?) -> Double? {
        guard let p1, let p2 else { return nil }
        let dx = Double(p2.x - p1.x)
        let dy = Double(p2.y - p1.y)
        return atan2(dy, dx) * 180.0 / .pi
    }

    private static func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint {
        guard let a, let b else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: (a.x + b.x) / 2.0, y: (a.y + b.y) / 2.0)
    }

    private static func sideLeanDegrees(nose: CGPoint?, neck: CGPoint?, hip: CGPoint?) -> Double? {
        guard let neck, let hip else { return nil }
        let refTop = nose ?? neck
        let dx = Double(refTop.x - hip.x)
        let dy = Double(refTop.y - hip.y)
        if abs(dy) < 1e-6 { return nil }
        let angleFromVertical = atan2(dx, dy) * 180.0 / .pi
        return angleFromVertical
    }
}

struct PoseObservation {
    private let points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]

    init(_ observation: VNHumanBodyPoseObservation) {
        self.points = (try? observation.recognizedPoints(.all)) ?? [:]
    }

    func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        guard let p = points[joint], p.confidence > 0.2 else { return nil }
        return CGPoint(x: p.x, y: p.y)
    }

    func confidence(_ joint: VNHumanBodyPoseObservation.JointName) -> Double {
        Double(points[joint]?.confidence ?? 0)
    }
}

extension PhotosPickerItem {
    func loadUIImage() async -> UIImage? {
        do {
            if let data = try await self.loadTransferable(type: Data.self) {
                return UIImage(data: data)
            }
        } catch {
            return nil
        }
        return nil
    }
}
