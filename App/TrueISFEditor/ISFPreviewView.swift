import SwiftUI

struct ISFPreviewView: NSViewRepresentable {
    @ObservedObject var coordinator: PreviewCoordinator
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        embed(coordinator.nsView, in: container)
        return container
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.subviews.first !== coordinator.nsView {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            embed(coordinator.nsView, in: nsView)
        }
    }
    private func embed(_ v: NSView, in container: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: container.topAnchor),
            v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
