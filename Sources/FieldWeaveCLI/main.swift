import Foundation
import FieldWeaveCore

func usage() {
    print("""
    FieldWeave native DSP companion
      fieldweave-cli validate configuration.json
      fieldweave-cli build configuration.json output-directory
      fieldweave-cli render configuration.json stereo-input.wav output.wav
    The app and this CLI use the same Swift DSP core. No audio device is opened.
    """)
}
let args=Array(CommandLine.arguments.dropFirst())
do {
    guard args.count>=2 else {usage();exit(args.isEmpty ? 0:2)}
    let configurationURL=URL(fileURLWithPath:args[1]).standardizedFileURL
    let config=try FieldConfiguration.read(from:configurationURL)
    let compiled=try FIRCompiler.compile(config,baseURL:configurationURL.deletingLastPathComponent())
    switch args[0] {
    case "validate":
        print(String(data:try FieldConfiguration.encoder.encode(compiled.report),encoding:.utf8)!)
    case "build":
        guard args.count==3 else {usage();exit(2)}
        try FieldExporter.export(compiled,configuration:config,to:URL(fileURLWithPath:args[2]).standardizedFileURL,baseURL:configurationURL.deletingLastPathComponent())
        print("Exported \(compiled.report.matrixTaps) taps at \(compiled.report.sampleRate) Hz to \(args[2])")
    case "render":
        guard args.count==4 else {usage();exit(2)}
        let report=try FIRProcessor.render(input:URL(fileURLWithPath:args[2]).standardizedFileURL,output:URL(fileURLWithPath:args[3]).standardizedFileURL,compiled:compiled)
        print(String(data:try FieldConfiguration.encoder.encode(report),encoding:.utf8)!)
    default:usage();exit(2)
    }
} catch {fputs("FieldWeave: \(error.localizedDescription)\n",stderr);exit(2)}
