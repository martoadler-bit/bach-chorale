import SwiftUI

struct GenerateView: View {
    @ObservedObject var vm: ChoraleViewModel
    @Binding var selectedTab: Int

    private let noteNames = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]

    var body: some View {
        NavigationView {
            Form {
                Section("Key") {
                    HStack {
                        Text("Root note")
                        Spacer()
                        Picker("", selection: $vm.keyRoot) {
                            ForEach(0..<12, id: \.self) { i in
                                Text(noteNames[i]).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack {
                        Text("Mode")
                        Spacer()
                        Picker("", selection: $vm.isMinor) {
                            Text("Major").tag(false)
                            Text("Minor").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                }

                Section("Parameters") {
                    HStack {
                        Text("Measures")
                        Spacer()
                        Stepper("\(vm.measuresCount)", value: $vm.measuresCount, in: 1...16)
                    }
                    HStack {
                        Text("Tempo")
                        Spacer()
                        Stepper("\(vm.tempo) bpm", value: $vm.tempo, in: 40...160, step: 4)
                    }
                }

                Section {
                    Button {
                        vm.generateFromScratch {
                            selectedTab = 2
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isHarmonizing {
                                ProgressView().progressViewStyle(.circular)
                                Text("Generating…").padding(.leading, 8)
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text("Generate chorale").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(vm.isHarmonizing)
                }
            }
            .navigationTitle("Generate chorale")
        }
        .navigationViewStyle(.stack)
    }
}
