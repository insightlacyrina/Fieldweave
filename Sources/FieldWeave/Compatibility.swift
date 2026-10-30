import SwiftUI
// Use the stable property-wrapper type explicitly: some command-line SDKs expose
// the newer @State macro without shipping its compiler plugin.
typealias FWState<Value> = SwiftUI.State<Value>
