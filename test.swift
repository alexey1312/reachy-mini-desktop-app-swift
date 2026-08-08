import SwiftUI

struct TestView: View {
    @State var obj: Int
    init() {
        _obj = State(initialValue: { print("EVALUATED"); return 5 }())
    }
    var body: some View { Text("Hello") }
}
