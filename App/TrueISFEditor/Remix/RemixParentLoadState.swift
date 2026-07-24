import Foundation

struct RemixParentRequest: Equatable, Identifiable {
    let id: UUID
    let slot: ParentSlot
    let spec: ParentSpec
    let displayInput: String

    init(id: UUID = UUID(), slot: ParentSlot, spec: ParentSpec, displayInput: String) {
        self.id = id
        self.slot = slot
        self.spec = spec
        self.displayInput = displayInput
    }

    init?(snapshot: RemixParentRequestSnapshot) {
        let spec: ParentSpec
        switch snapshot.source {
        case .pastedISF(let source):
            spec = .pastedISF(source)
        case .libraryPath(let path):
            spec = .libraryFile(URL(fileURLWithPath: path))
        case .shadertoyLink(let input):
            spec = .shadertoyLink(input)
        case .currentEditorSource(let source):
            spec = .pastedISF(source)
        }
        self.init(
            id: snapshot.id,
            slot: snapshot.slot,
            spec: spec,
            displayInput: snapshot.displayInput
        )
    }

    func snapshot(phase: RemixParentRequestPhase) -> RemixParentRequestSnapshot {
        let source: RemixParentSourceSnapshot
        switch spec {
        case .pastedISF(let input):
            source = .pastedISF(input)
        case .libraryFile(let url):
            source = .libraryPath(url.path)
        case .shadertoyLink(let input):
            source = .shadertoyLink(input)
        case .currentEditor:
            source = .currentEditorSource(displayInput)
        }
        return RemixParentRequestSnapshot(
            id: id,
            slot: slot,
            source: source,
            displayInput: displayInput,
            phase: phase
        )
    }
}

enum RemixParentFocusTarget: Equatable {
    case parentSource(ParentSlot)
}

enum RemixParentLoadEvent {
    case verificationRequired
    case waitingForHuman
    case cleared
    case converting
    case succeeded
    case failed(String)
}

enum RemixParentLoadState: Equatable {
    case idle
    case fetching(RemixParentRequest)
    case verificationRequired(RemixParentRequest)
    case waitingForHuman(RemixParentRequest)
    case resuming(RemixParentRequest)
    case converting(RemixParentRequest)
    case succeeded(slot: ParentSlot, requestID: UUID)
    case failed(RemixParentRequest, message: String)
    case cancelled(RemixParentRequest)

    var request: RemixParentRequest? {
        switch self {
        case .idle, .succeeded:
            return nil
        case .fetching(let request),
             .verificationRequired(let request),
             .waitingForHuman(let request),
             .resuming(let request),
             .converting(let request),
             .failed(let request, _),
             .cancelled(let request):
            return request
        }
    }

    var focusTarget: RemixParentFocusTarget? {
        switch self {
        case .succeeded(let slot, _):
            return .parentSource(slot)
        case .failed(let request, _), .cancelled(let request):
            return .parentSource(request.slot)
        default:
            return nil
        }
    }

    func cancelled() -> RemixParentLoadState {
        guard let request else { return self }
        return .cancelled(request)
    }

    func transitioning(
        to event: RemixParentLoadEvent,
        requestID: UUID
    ) -> RemixParentLoadState {
        guard let request, request.id == requestID else { return self }
        switch event {
        case .verificationRequired:
            return .verificationRequired(request)
        case .waitingForHuman:
            return .waitingForHuman(request)
        case .cleared:
            if case .resuming = self { return self }
            return .resuming(request)
        case .converting:
            return .converting(request)
        case .succeeded:
            return .succeeded(slot: request.slot, requestID: request.id)
        case .failed(let message):
            return .failed(request, message: message)
        }
    }
}
